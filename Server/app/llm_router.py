from __future__ import annotations

import os
import re
import time
import uuid
from dataclasses import dataclass
from typing import Any

# Avoid a slow remote pricing-map fetch during backend cold start. LiteLLM still uses its bundled backup map.
os.environ.setdefault("LITELLM_LOCAL_MODEL_COST_MAP", "True")

import litellm

from .config import LLMModelSettings, LangfuseSettings
from .usage import LLMUsageRecord, UsageLogger


class LLMRouterError(RuntimeError):
    pass


@dataclass(frozen=True)
class LLMCompletionResult:
    content: str
    model_alias: str
    provider_name: str
    model: str
    prompt_tokens: int
    completion_tokens: int
    total_tokens: int
    cost_usd: float | None = None
    response_id: str = ""


class LLMRouter:
    def __init__(
        self,
        models: tuple[LLMModelSettings, ...],
        usage_logger: UsageLogger,
        langfuse: LangfuseSettings | None = None,
    ) -> None:
        self.models = tuple(model for model in models if model.configured)
        self.usage_logger = usage_logger
        self.langfuse = langfuse
        self._configure_litellm_observability()

    @property
    def configured(self) -> bool:
        return bool(self.models)

    async def complete(
        self,
        messages: list[dict[str, str]],
        *,
        route: str,
        user_id: str,
        request_id: str | None = None,
        extra_system_prompt: str = "",
    ) -> LLMCompletionResult:
        if not self.models:
            raise LLMRouterError("Server-side LLM configuration is incomplete.")

        request_id = request_id or str(uuid.uuid4())
        errors: list[str] = []
        for model in self.models:
            started = time.perf_counter()
            try:
                resolved_messages = self._merged_messages(messages, model, extra_system_prompt)
                result = await self._complete_with_model(
                    model,
                    resolved_messages,
                    route=route,
                    user_id=user_id,
                    request_id=request_id,
                )
                latency_ms = int((time.perf_counter() - started) * 1000)
                self.usage_logger.write(
                    LLMUsageRecord(
                        request_id=request_id,
                        user_id=user_id,
                        route=route,
                        provider_name=result.provider_name,
                        model_alias=result.model_alias,
                        model=result.model,
                        success=True,
                        latency_ms=latency_ms,
                        prompt_tokens=result.prompt_tokens,
                        completion_tokens=result.completion_tokens,
                        total_tokens=result.total_tokens,
                        cost_usd=result.cost_usd,
                        response_id=result.response_id,
                    )
                )
                return result
            except Exception as error:  # noqa: BLE001 - fallback should preserve all provider failures.
                latency_ms = int((time.perf_counter() - started) * 1000)
                message = str(error)
                errors.append(f"{model.id}: {message}")
                self.usage_logger.write(
                    LLMUsageRecord(
                        request_id=request_id,
                        user_id=user_id,
                        route=route,
                        provider_name=model.provider_name,
                        model_alias=model.id,
                        model=model.model,
                        success=False,
                        latency_ms=latency_ms,
                        prompt_tokens=estimate_tokens(messages),
                        completion_tokens=0,
                        total_tokens=estimate_tokens(messages),
                        error=message,
                    )
                )
                continue

        raise LLMRouterError("All configured LLM providers failed: " + " | ".join(errors))

    async def list_models(self) -> list[str]:
        # LiteLLM SDK completion is the source of truth; /models endpoints are not reliable across providers.
        return [model.model for model in self.models if model.model.strip()]

    async def _complete_with_model(
        self,
        settings: LLMModelSettings,
        messages: list[dict[str, str]],
        *,
        route: str,
        user_id: str,
        request_id: str,
    ) -> LLMCompletionResult:
        litellm_model = self._litellm_model(settings)
        response = await litellm.acompletion(
            model=litellm_model,
            messages=messages,
            api_base=settings.base_url.rstrip("/"),
            api_key=settings.api_key,
            custom_llm_provider=settings.custom_llm_provider or "openai",
            temperature=settings.temperature,
            max_tokens=settings.max_tokens,
            timeout=settings.timeout_seconds,
            stream=False,
            metadata={
                "trace_id": request_id,
                "generation_name": route,
                "user_id": user_id,
                "edunode_route": route,
                "edunode_model_alias": settings.id,
                "edunode_provider": settings.provider_name,
            },
        )

        payload = response.model_dump() if hasattr(response, "model_dump") else dict(response)
        content = normalized_content(payload)
        if not content.strip():
            raise LLMRouterError("The model returned an empty final response.")

        usage = payload.get("usage") if isinstance(payload, dict) else {}
        prompt_tokens = int((usage or {}).get("prompt_tokens") or estimate_tokens(messages))
        completion_tokens = int((usage or {}).get("completion_tokens") or estimate_text_tokens(content))
        total_tokens = int((usage or {}).get("total_tokens") or prompt_tokens + completion_tokens)
        cost = getattr(response, "_hidden_params", {}).get("response_cost") if hasattr(response, "_hidden_params") else None
        response_id = str(payload.get("id") or "")
        return LLMCompletionResult(
            content=content,
            model_alias=settings.id,
            provider_name=settings.provider_name,
            model=settings.model,
            prompt_tokens=prompt_tokens,
            completion_tokens=completion_tokens,
            total_tokens=total_tokens,
            cost_usd=float(cost) if cost is not None else None,
            response_id=response_id,
        )

    def _litellm_model(self, settings: LLMModelSettings) -> str:
        if settings.litellm_model.strip():
            return settings.litellm_model.strip()
        provider = (settings.custom_llm_provider or "openai").strip()
        if "/" in settings.model:
            return settings.model
        return f"{provider}/{settings.model}"

    def _merged_messages(
        self,
        messages: list[dict[str, str]],
        model: LLMModelSettings,
        extra_system_prompt: str,
    ) -> list[dict[str, str]]:
        extra = "\n\n".join(
            part.strip()
            for part in [model.additional_system_prompt, extra_system_prompt]
            if part and part.strip()
        )
        if not extra:
            return messages
        return [{"role": "system", "content": extra}, *messages]

    def _configure_litellm_observability(self) -> None:
        if not self.langfuse or not self.langfuse.configured:
            return
        os.environ["LANGFUSE_PUBLIC_KEY"] = self.langfuse.public_key
        os.environ["LANGFUSE_SECRET_KEY"] = self.langfuse.secret_key
        os.environ["LANGFUSE_OTEL_HOST"] = self.langfuse.otel_host.rstrip("/")
        callbacks = list(getattr(litellm, "callbacks", []) or [])
        if "langfuse_otel" not in callbacks:
            callbacks.append("langfuse_otel")
        litellm.callbacks = callbacks


def normalized_content(payload: dict[str, Any]) -> str:
    raw = _first_choice_content(payload)
    return strip_reasoning_markup(raw).strip()


def strip_reasoning_markup(text: str) -> str:
    stripped = re.sub(r"<think>.*?</think>", "", text, flags=re.DOTALL | re.IGNORECASE)
    return stripped.strip()


def estimate_tokens(messages: list[dict[str, str]]) -> int:
    return sum(estimate_text_tokens(str(item.get("content", ""))) for item in messages)


def estimate_text_tokens(text: str) -> int:
    return max(1, int(len(text) / 3.2))


def _first_choice_content(payload: dict[str, Any]) -> str:
    choices = payload.get("choices", [])
    if not isinstance(choices, list) or not choices:
        return ""
    first = choices[0]
    if not isinstance(first, dict):
        return ""
    message = first.get("message", {})
    if isinstance(message, dict):
        content = message.get("content")
        if isinstance(content, str):
            return content
        if isinstance(content, list):
            parts = []
            for item in content:
                if isinstance(item, dict):
                    text = item.get("text") or item.get("content")
                    if isinstance(text, str):
                        parts.append(text)
            return "\n".join(parts)
    text = first.get("text")
    return text if isinstance(text, str) else ""
