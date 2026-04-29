from __future__ import annotations

from typing import Any

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from .auth import AuthError, AuthNotConfigured, InvalidToken, SupabaseAuthManager, require_session
from .canvas_agent import CanvasAgentService
from .config import load_settings
from .llm_router import LLMRouter, LLMRouterError
from .mineru import MinerUClient, MinerUError
from .usage import UsageLogger


settings = load_settings()
auth_manager = SupabaseAuthManager(settings.supabase)
usage_logger = UsageLogger(settings.usage_log_path)
llm_router = LLMRouter(settings.llm_models, usage_logger, settings.langfuse)
canvas_service = CanvasAgentService(llm_router, settings.agent_mode)
mineru_client = MinerUClient(settings.mineru)

app = FastAPI(
    title="EduNode Server",
    version="0.1.0",
    docs_url="/docs",
    redoc_url=None,
)


@app.exception_handler(HTTPException)
async def http_exception_handler(_: Request, exc: HTTPException) -> JSONResponse:
    return JSONResponse(status_code=exc.status_code, content={"reason": str(exc.detail)})


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(_: Request, exc: RequestValidationError) -> JSONResponse:
    return JSONResponse(status_code=422, content={"reason": str(exc)})


async def current_session(request: Request):
    return await require_session(request, auth_manager)


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok", "service": "EduNodeServer"}


@app.post("/auth/sign-in")
async def sign_in(payload: dict[str, Any]) -> dict[str, Any]:
    try:
        return await auth_manager.sign_in(str(payload.get("email", "")), str(payload.get("password", "")))
    except AuthNotConfigured as error:
        raise HTTPException(status_code=503, detail=str(error)) from error
    except AuthError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error


@app.post("/auth/sign-up")
async def sign_up(payload: dict[str, Any]) -> dict[str, Any]:
    try:
        return await auth_manager.sign_up(str(payload.get("email", "")), str(payload.get("password", "")))
    except AuthNotConfigured as error:
        raise HTTPException(status_code=503, detail=str(error)) from error
    except AuthError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error


@app.post("/auth/refresh")
async def refresh(payload: dict[str, Any]) -> dict[str, Any]:
    try:
        return await auth_manager.refresh(str(payload.get("refresh_token", "")))
    except AuthNotConfigured as error:
        raise HTTPException(status_code=503, detail=str(error)) from error
    except InvalidToken as error:
        raise HTTPException(status_code=401, detail=str(error)) from error
    except AuthError as error:
        status = 401 if "refresh token" in str(error).lower() else 400
        raise HTTPException(status_code=status, detail=str(error)) from error


@app.get("/auth/session")
async def auth_session(session=Depends(current_session)) -> dict[str, Any]:
    return {
        "authenticated": True,
        "user_id": session.user_id,
        "email": session.email,
        "expires_at_unix_seconds": session.expires_at_unix_seconds,
    }


@app.post("/auth/sign-out")
async def sign_out(request: Request, session=Depends(current_session)) -> dict[str, str]:
    authorization = request.headers.get("Authorization", "")
    token = authorization.removeprefix("Bearer").strip()
    await auth_manager.sign_out(token)
    return {"status": "ok"}


@app.get("/agent/runtime")
async def agent_runtime(session=Depends(current_session)) -> dict[str, Any]:
    return await canvas_service.runtime_status()


@app.post("/llm/complete")
async def llm_complete(payload: dict[str, Any], session=Depends(current_session)) -> dict[str, str]:
    try:
        result = await llm_router.complete(
            payload.get("messages", []),
            route="llm.complete",
            user_id=session.user_id,
        )
        return {"content": result.content}
    except LLMRouterError as error:
        raise HTTPException(status_code=502, detail=str(error)) from error


@app.post("/reference/parse-pdf")
async def parse_reference_pdf(payload: dict[str, Any], session=Depends(current_session)) -> dict[str, str]:
    try:
        return await mineru_client.parse_reference_pdf(
            str(payload.get("file_data_base64", "")),
            str(payload.get("file_name", "reference.pdf")),
        )
    except MinerUError as error:
        status = 503 if "not configured" in str(error).lower() else 502
        raise HTTPException(status_code=status, detail=str(error)) from error


@app.post("/canvas/respond")
async def canvas_respond(payload: dict[str, Any], session=Depends(current_session)) -> dict[str, Any]:
    try:
        return await canvas_service.respond(payload, user_id=session.user_id)
    except (LLMRouterError, ValueError) as error:
        raise HTTPException(status_code=502, detail=str(error)) from error


@app.post("/canvas/suggested-prompts")
async def canvas_suggested_prompts(payload: dict[str, Any], session=Depends(current_session)) -> dict[str, Any]:
    try:
        return await canvas_service.suggested_prompts(payload, user_id=session.user_id)
    except (LLMRouterError, ValueError) as error:
        raise HTTPException(status_code=502, detail=str(error)) from error


@app.get("/llm/usage/summary")
async def llm_usage_summary(session=Depends(current_session)) -> dict[str, Any]:
    # Lightweight placeholder endpoint for future admin UI; raw JSONL is intentionally kept server-side.
    return {
        "usage_log_path": str(settings.usage_log_path),
        "message": "LLM usage is recorded as JSONL on the server.",
    }
