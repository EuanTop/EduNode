from __future__ import annotations

import base64
import hashlib
import json
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


@dataclass(frozen=True)
class AuthenticatedSession:
    user_id: str
    email: str
    expires_at_unix_seconds: int


class SupabaseAuthManager:
    def __init__(self, settings: SupabaseSettings) -> None:
        self.settings = settings
        self._cache: dict[str, tuple[AuthenticatedSession, int]] = {}

    async def sign_in(self, email: str, password: str) -> dict[str, Any]:
        payload = await self._post_auth_json(
            "/token?grant_type=password",
            {"email": email.strip(), "password": password},
        )
        return _session_response(payload)

    async def sign_up(self, email: str, password: str) -> dict[str, Any]:
        normalized_email = email.strip()
        payload = await self._post_auth_json(
            "/signup",
            {"email": normalized_email, "password": password},
        )
        session_payload = payload.get("session")
        return {
            "status": "signed_in" if session_payload else "confirmation_required",
            "email": _nested_str(payload, ["user", "email"]) or normalized_email,
            "session": _session_response(session_payload) if isinstance(session_payload, dict) else None,
        }

    async def refresh(self, refresh_token: str) -> dict[str, Any]:
        token = refresh_token.strip()
        if not token:
            raise InvalidToken("Invalid refresh token.")
        payload = await self._post_auth_json(
            "/token?grant_type=refresh_token",
            {"refresh_token": token},
        )
        return _session_response(payload)

    async def sign_out(self, access_token: str) -> None:
        if not self.settings.configured:
            return
        headers = self._headers(access_token)
        async with httpx.AsyncClient(timeout=20) as client:
            await client.post(self.settings.auth_base_url + "/logout", headers=headers)

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


def _nested_str(payload: dict[str, Any], path: list[str]) -> str:
    current: Any = payload
    for key in path:
        if not isinstance(current, dict):
            return ""
        current = current.get(key)
    return current.strip() if isinstance(current, str) else ""

