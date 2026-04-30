from __future__ import annotations

import base64
import hashlib
import json
import re
import sqlite3
import time
from dataclasses import dataclass
from typing import Any

import httpx
from fastapi import HTTPException, Request
from fastapi.security.utils import get_authorization_scheme_param

from .config import SupabaseSettings


class AuthError(RuntimeError):
    pass


class AuthNotConfigured(AuthError):
    pass


class InvalidToken(AuthError):
    pass


class ExpiredToken(AuthError):
    pass


class SessionRevoked(AuthError):
    pass


@dataclass(frozen=True)
class AuthenticatedSession:
    user_id: str
    email: str
    expires_at_unix_seconds: int


class ActiveSessionStore:
    def __init__(self, database_path) -> None:
        self.database_path = database_path
        self.database_path.parent.mkdir(parents=True, exist_ok=True)
        self._ensure_schema()

    def activate(self, user_id: str, session_id: str) -> None:
        normalized_user_id = user_id.strip()
        normalized_session_id = session_id.strip()
        if not normalized_user_id or not normalized_session_id:
            return
        with sqlite3.connect(self.database_path) as connection:
            connection.execute(
                """
                INSERT INTO active_sessions(user_id, session_id, updated_at)
                VALUES (?, ?, ?)
                ON CONFLICT(user_id) DO UPDATE SET
                    session_id = excluded.session_id,
                    updated_at = excluded.updated_at
                """,
                (normalized_user_id, normalized_session_id, int(time.time())),
            )

    def deactivate_if_current(self, user_id: str, session_id: str) -> None:
        normalized_user_id = user_id.strip()
        normalized_session_id = session_id.strip()
        if not normalized_user_id or not normalized_session_id:
            return
        with sqlite3.connect(self.database_path) as connection:
            connection.execute(
                "DELETE FROM active_sessions WHERE user_id = ? AND session_id = ?",
                (normalized_user_id, normalized_session_id),
            )

    def is_current(self, user_id: str, session_id: str) -> bool:
        normalized_user_id = user_id.strip()
        normalized_session_id = session_id.strip()
        if not normalized_user_id or not normalized_session_id:
            return True
        with sqlite3.connect(self.database_path) as connection:
            row = connection.execute(
                "SELECT session_id FROM active_sessions WHERE user_id = ?",
                (normalized_user_id,),
            ).fetchone()
        if row is None:
            return True
        return str(row[0]) == normalized_session_id

    def _ensure_schema(self) -> None:
        with sqlite3.connect(self.database_path) as connection:
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS active_sessions (
                    user_id TEXT PRIMARY KEY,
                    session_id TEXT NOT NULL,
                    updated_at INTEGER NOT NULL
                )
                """
            )


class SupabaseAuthManager:
    def __init__(self, settings: SupabaseSettings) -> None:
        self.settings = settings
        self._cache: dict[str, tuple[AuthenticatedSession, int]] = {}
        self._active_sessions = ActiveSessionStore(settings.session_store_path)

    async def sign_in(self, email: str, password: str) -> dict[str, Any]:
        _validate_email_password(email, password)
        payload = await self._post_auth_json(
            "/token?grant_type=password",
            {"email": email.strip(), "password": password},
        )
        response = _session_response(payload)
        self._activate_response_session(response)
        return response

    async def sign_in_with_apple(self, id_token: str, nonce: str) -> dict[str, Any]:
        normalized_id_token = id_token.strip()
        normalized_nonce = nonce.strip()
        if not normalized_id_token:
            raise AuthError("Missing Apple identity token.")
        if not normalized_nonce:
            raise AuthError("Missing Apple sign-in nonce.")
        payload = await self._post_auth_json(
            "/token?grant_type=id_token",
            {
                "provider": "apple",
                "id_token": normalized_id_token,
                "nonce": normalized_nonce,
            },
        )
        response = _session_response(payload)
        self._activate_response_session(response)
        return response

    async def sign_up(self, email: str, password: str) -> dict[str, Any]:
        _validate_email_password(email, password)
        normalized_email = email.strip()
        payload = await self._post_auth_json(
            "/signup",
            {"email": normalized_email, "password": password},
        )
        session_payload = payload.get("session")
        session_response = _session_response(session_payload) if isinstance(session_payload, dict) else None
        if session_response:
            self._activate_response_session(session_response)
        return {
            "status": "signed_in" if session_payload else "confirmation_required",
            "email": _nested_str(payload, ["user", "email"]) or normalized_email,
            "session": session_response,
        }

    async def refresh(self, refresh_token: str) -> dict[str, Any]:
        token = refresh_token.strip()
        if not token:
            raise InvalidToken("Invalid refresh token.")
        payload = await self._post_auth_json(
            "/token?grant_type=refresh_token",
            {"refresh_token": token},
        )
        response = _session_response(payload)
        self._ensure_response_session_is_current(response)
        return response

    async def request_password_reset(self, email: str) -> dict[str, Any]:
        normalized_email = _validate_email(email)
        body: dict[str, Any] = {"email": normalized_email}
        if self.settings.auth_redirect_url:
            body["redirect_to"] = self.settings.auth_redirect_url
        await self._post_auth_json("/recover", body)
        return {"status": "ok", "email": normalized_email}

    async def resend_confirmation(self, email: str) -> dict[str, Any]:
        normalized_email = _validate_email(email)
        body: dict[str, Any] = {"type": "signup", "email": normalized_email}
        if self.settings.auth_redirect_url:
            body["options"] = {"email_redirect_to": self.settings.auth_redirect_url}
        await self._post_auth_json("/resend", body)
        return {"status": "ok", "email": normalized_email}

    async def sign_out(self, access_token: str) -> None:
        if not self.settings.configured:
            return
        claims = _decode_jwt_claims(access_token)
        headers = self._headers(access_token)
        async with httpx.AsyncClient(timeout=20) as client:
            await client.post(self.settings.auth_base_url + "/logout", headers=headers)
        self._active_sessions.deactivate_if_current(_claim_str(claims, "sub"), _claim_str(claims, "session_id"))

    async def session_status(self, access_token: str) -> dict[str, Any]:
        session = await self.validate(access_token)
        return {
            "authenticated": True,
            "user_id": session.user_id,
            "email": session.email,
            "expires_at_unix_seconds": session.expires_at_unix_seconds,
        }

    async def validate(self, access_token: str) -> AuthenticatedSession:
        if not self.settings.configured:
            raise AuthNotConfigured("Account authentication is not configured on the server.")
        token = access_token.strip()
        if not token:
            raise InvalidToken("Invalid account access token.")
        claims = _decode_jwt_claims(token)
        now = int(time.time())
        exp = int(claims.get("exp", now + 3600)) if isinstance(claims.get("exp"), int) else now + 3600
        if now >= exp:
            raise ExpiredToken("Account session expired.")
        user_id = _claim_str(claims, "sub")
        session_id = _claim_str(claims, "session_id")
        if not self._active_sessions.is_current(user_id, session_id):
            raise SessionRevoked("This account is signed in on another device. Please sign in again.")

        token_hash = hashlib.sha256(token.encode("utf-8")).hexdigest()
        cached = self._cache.get(token_hash)
        if cached and now < cached[1]:
            return cached[0]

        headers = self._headers(token)
        async with httpx.AsyncClient(timeout=30) as client:
            response = await client.get(self.settings.auth_base_url + "/user", headers=headers)
        if response.status_code in {401, 403}:
            raise InvalidToken("Invalid account access token.")
        if response.status_code < 200 or response.status_code >= 300:
            raise AuthError(_supabase_error(response))
        user = response.json()
        session = AuthenticatedSession(
            user_id=str(user.get("id", "")),
            email=str(user.get("email") or ""),
            expires_at_unix_seconds=exp,
        )
        self._cache[token_hash] = (session, min(exp, now + 60))
        return session

    def _activate_response_session(self, response: dict[str, Any]) -> None:
        claims = _decode_jwt_claims(str(response.get("access_token") or ""))
        user_id = str(response.get("user_id") or _claim_str(claims, "sub"))
        session_id = _claim_str(claims, "session_id")
        self._active_sessions.activate(user_id, session_id)
        self._cache.clear()

    def _ensure_response_session_is_current(self, response: dict[str, Any]) -> None:
        claims = _decode_jwt_claims(str(response.get("access_token") or ""))
        user_id = str(response.get("user_id") or _claim_str(claims, "sub"))
        session_id = _claim_str(claims, "session_id")
        if not self._active_sessions.is_current(user_id, session_id):
            raise SessionRevoked("This account is signed in on another device. Please sign in again.")

    async def _post_auth_json(self, path_and_query: str, body: dict[str, Any]) -> dict[str, Any]:
        if not self.settings.configured:
            raise AuthNotConfigured("Account authentication is not configured on the server.")
        async with httpx.AsyncClient(timeout=45) as client:
            response = await client.post(
                self.settings.auth_base_url + path_and_query,
                headers=self._headers(),
                json=body,
            )
        if response.status_code < 200 or response.status_code >= 300:
            raise AuthError(_supabase_error(response))
        return response.json()

    def _headers(self, access_token: str | None = None) -> dict[str, str]:
        headers = {
            "apikey": self.settings.publishable_key,
            "Content-Type": "application/json",
        }
        if access_token:
            headers["Authorization"] = f"Bearer {access_token}"
        return headers


async def require_session(request: Request, auth: SupabaseAuthManager) -> AuthenticatedSession:
    authorization = request.headers.get("Authorization")
    scheme, token = get_authorization_scheme_param(authorization)
    if scheme.lower() != "bearer" or not token:
        raise HTTPException(status_code=401, detail="Missing account access token.")
    try:
        return await auth.validate(token)
    except AuthNotConfigured as error:
        raise HTTPException(status_code=503, detail=str(error)) from error
    except ExpiredToken as error:
        raise HTTPException(status_code=401, detail=str(error)) from error
    except SessionRevoked as error:
        raise HTTPException(status_code=401, detail=str(error)) from error
    except AuthError as error:
        raise HTTPException(status_code=401, detail=str(error)) from error


def _session_response(payload: dict[str, Any]) -> dict[str, Any]:
    user = payload.get("user") if isinstance(payload.get("user"), dict) else {}
    expires_at = payload.get("expires_at")
    if not isinstance(expires_at, int):
        expires_in = int(payload.get("expires_in") or 3600)
        expires_at = int(time.time()) + expires_in
    return {
        "access_token": str(payload.get("access_token") or ""),
        "refresh_token": str(payload.get("refresh_token") or ""),
        "user_id": str(user.get("id") or payload.get("user_id") or ""),
        "email": str(user.get("email") or payload.get("email") or ""),
        "expires_at_unix_seconds": expires_at,
    }


def _supabase_error(response: httpx.Response) -> str:
    try:
        payload = response.json()
        if isinstance(payload, dict):
            for key in ("msg", "message", "error_description", "error", "detail"):
                value = payload.get(key)
                if isinstance(value, str) and value.strip():
                    return value
    except Exception:
        pass
    return response.text.strip() or f"HTTP {response.status_code}"


def _decode_jwt_claims(token: str) -> dict[str, Any]:
    segments = token.split(".")
    if len(segments) < 2:
        return {}
    payload = segments[1]
    padding = "=" * (-len(payload) % 4)
    try:
        decoded = base64.urlsafe_b64decode((payload + padding).encode("utf-8"))
        parsed = json.loads(decoded)
        return parsed if isinstance(parsed, dict) else {}
    except Exception:
        return {}


def _claim_str(claims: dict[str, Any], key: str) -> str:
    value = claims.get(key)
    return value.strip() if isinstance(value, str) else ""


def _nested_str(payload: dict[str, Any], path: list[str]) -> str:
    current: Any = payload
    for key in path:
        if not isinstance(current, dict):
            return ""
        current = current.get(key)
    return current.strip() if isinstance(current, str) else ""


def _validate_email(email: str) -> str:
    normalized = email.strip()
    if not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", normalized):
        raise AuthError("Enter a valid email address.")
    return normalized


def _validate_email_password(email: str, password: str) -> None:
    _validate_email(email)
    if len(password) < 8:
        raise AuthError("Password must be at least 8 characters.")
