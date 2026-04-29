from __future__ import annotations

import json
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Any


SERVER_DIR = Path(__file__).resolve().parents[1]
REPO_ROOT = SERVER_DIR.parent


def _parse_dotenv(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.exists():
        return values
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[len("export ") :].strip()
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
            value = value[1:-1]
        if key:
            values[key] = value
    return values


def load_environment() -> dict[str, str]:
    merged = dict(os.environ)
    raw_environment = (merged.get("EDUNODE_ENV") or "").strip().lower()
    if raw_environment in {"prod", "production", "release"}:
        environment = "production"
    elif raw_environment in {"dev", "development", "debug"}:
        environment = "dev"
    else:
        environment = raw_environment

    candidates: list[Path] = []
    if environment:
        candidates.extend((SERVER_DIR / f".env.{environment}", REPO_ROOT / f".env.{environment}"))
    candidates.extend((SERVER_DIR / ".env", REPO_ROOT / ".env"))

    for candidate in candidates:
        for key, value in _parse_dotenv(candidate).items():
            if not merged.get(key):
                merged[key] = value
    return merged


def _bool(value: str | None, fallback: bool) -> bool:
    if value is None or not value.strip():
        return fallback
    return value.strip().lower() in {"1", "true", "yes", "y", "on"}


def _float(value: str | None, fallback: float) -> float:
    try:
        return float(value) if value is not None and value.strip() else fallback
    except ValueError:
        return fallback


def _int(value: str | None, fallback: int, minimum: int | None = None) -> int:
    try:
        parsed = int(value) if value is not None and value.strip() else fallback
    except ValueError:
        parsed = fallback
    return max(parsed, minimum) if minimum is not None else parsed


@dataclass(frozen=True)
class SupabaseSettings:
    url: str
    publishable_key: str

    @property
    def configured(self) -> bool:
        return bool(self.url.strip() and self.publishable_key.strip())

    @property
    def auth_base_url(self) -> str:
        return self.url.rstrip("/") + "/auth/v1"


@dataclass(frozen=True)
class MinerUSettings:
    api_token: str
    api_base_url: str
    model_version: str
    language: str
    enable_formula: bool
    enable_table: bool
    enable_ocr: bool
    polling_interval_seconds: float
    max_polling_attempts: int

    @property
    def configured(self) -> bool:
        return bool(self.api_token.strip())

    @property
    def apply_upload_url(self) -> str:
        return self.api_base_url.rstrip("/") + "/file-urls/batch"

    @property
    def batch_result_url_prefix(self) -> str:
        return self.api_base_url.rstrip("/") + "/extract-results/batch"


@dataclass(frozen=True)
class LLMModelSettings:
    id: str
    provider_name: str
    base_url: str
    model: str
    api_key: str
    litellm_model: str
    custom_llm_provider: str
    priority: int
    temperature: float
    max_tokens: int
    timeout_seconds: float
    additional_system_prompt: str = ""
    enabled: bool = True

    @property
    def configured(self) -> bool:
        return bool(self.enabled and self.base_url.strip() and self.model.strip() and self.api_key.strip())

    @property
    def host(self) -> str:
        without_scheme = self.base_url.replace("https://", "").replace("http://", "")
        return without_scheme.split("/", 1)[0]


@dataclass(frozen=True)
class LangfuseSettings:
    enabled: bool
    public_key: str
    secret_key: str
    otel_host: str

    @property
    def configured(self) -> bool:
        return bool(self.enabled and self.public_key.strip() and self.secret_key.strip() and self.otel_host.strip())


@dataclass(frozen=True)
class RuntimeSettings:
    host: str
    port: int
    agent_mode: str
    supabase: SupabaseSettings
    mineru: MinerUSettings
    llm_models: tuple[LLMModelSettings, ...]
    langfuse: LangfuseSettings
    usage_log_path: Path

    @property
    def primary_model(self) -> LLMModelSettings | None:
        for model in sorted(self.llm_models, key=lambda item: item.priority):
            if model.configured:
                return model
        return None


def _load_llm_models(env: dict[str, str]) -> tuple[LLMModelSettings, ...]:
    raw_json = env.get("EDUNODE_LLM_MODELS_JSON", "").strip()
    config_file = env.get("EDUNODE_LLM_MODELS_FILE", "").strip() or str(SERVER_DIR / "llm_models.json")
    raw_models: list[dict[str, Any]] = []

    if raw_json:
        parsed = json.loads(raw_json)
        raw_models = parsed if isinstance(parsed, list) else parsed.get("models", [])
    else:
        config_path = Path(config_file)
        if not config_path.is_absolute() and not config_path.exists():
            config_path = (REPO_ROOT if config_path.parts and config_path.parts[0] == "Server" else SERVER_DIR) / config_path
        if config_path.exists():
            parsed = json.loads(config_path.read_text(encoding="utf-8"))
            raw_models = parsed if isinstance(parsed, list) else parsed.get("models", [])

    models: list[LLMModelSettings] = []
    for index, item in enumerate(raw_models):
        if not isinstance(item, dict):
            continue
        models.append(
            LLMModelSettings(
                id=str(item.get("id") or item.get("alias") or item.get("model") or f"model-{index + 1}"),
                provider_name=str(item.get("provider_name") or item.get("provider") or "OpenAI-Compatible"),
                base_url=str(item.get("base_url") or item.get("baseURL") or ""),
                model=str(item.get("model") or ""),
                api_key=str(item.get("api_key") or item.get("apiKey") or ""),
                litellm_model=str(item.get("litellm_model") or item.get("litellmModel") or ""),
                custom_llm_provider=str(item.get("custom_llm_provider") or item.get("customLLMProvider") or "openai"),
                priority=int(item.get("priority", index + 1)),
                temperature=float(item.get("temperature", env.get("EDUNODE_LLM_TEMPERATURE") or 0.35)),
                max_tokens=int(item.get("max_tokens", env.get("EDUNODE_LLM_MAX_TOKENS") or 3200)),
                timeout_seconds=float(item.get("timeout_seconds", env.get("EDUNODE_LLM_TIMEOUT_SECONDS") or 90)),
                additional_system_prompt=str(item.get("additional_system_prompt") or ""),
                enabled=bool(item.get("enabled", True)),
            )
        )

    legacy = LLMModelSettings(
        id=env.get("EDUNODE_LLM_ALIAS", "default").strip() or "default",
        provider_name=env.get("EDUNODE_LLM_PROVIDER_NAME", "OpenAI-Compatible").strip() or "OpenAI-Compatible",
        base_url=env.get("EDUNODE_LLM_BASE_URL", "").strip(),
        model=env.get("EDUNODE_LLM_MODEL", "").strip(),
        api_key=env.get("EDUNODE_LLM_API_KEY", "").strip(),
        litellm_model=env.get("EDUNODE_LITELLM_MODEL", "").strip(),
        custom_llm_provider=env.get("EDUNODE_LITELLM_CUSTOM_PROVIDER", "openai").strip() or "openai",
        priority=999,
        temperature=_float(env.get("EDUNODE_LLM_TEMPERATURE"), 0.35),
        max_tokens=_int(env.get("EDUNODE_LLM_MAX_TOKENS"), 3200, minimum=256),
        timeout_seconds=_float(env.get("EDUNODE_LLM_TIMEOUT_SECONDS"), 90),
        additional_system_prompt=env.get("EDUNODE_LLM_ADDITIONAL_SYSTEM_PROMPT", "").strip(),
    )
    if legacy.configured and all(model.id != legacy.id for model in models):
        models.append(legacy)

    return tuple(sorted(models, key=lambda item: item.priority))


def load_settings() -> RuntimeSettings:
    env = load_environment()
    usage_path = Path(env.get("EDUNODE_USAGE_LOG_PATH", str(SERVER_DIR / "logs" / "llm_usage.jsonl")))
    if not usage_path.is_absolute():
        usage_path = (REPO_ROOT if usage_path.parts and usage_path.parts[0] == "Server" else SERVER_DIR) / usage_path
    return RuntimeSettings(
        host=env.get("EDUNODE_SERVER_HOST", "127.0.0.1").strip() or "127.0.0.1",
        port=_int(env.get("PORT"), 8080),
        agent_mode=env.get("EDUNODE_SERVER_AGENT_MODE", "live").strip().lower() or "live",
        supabase=SupabaseSettings(
            url=env.get("EDUNODE_SUPABASE_URL", "").strip(),
            publishable_key=(
                env.get("EDUNODE_SUPABASE_PUBLISHABLE_KEY")
                or env.get("EDUNODE_SUPABASE_ANON_KEY")
                or ""
            ).strip(),
        ),
        mineru=MinerUSettings(
            api_token=env.get("MINERU_API_TOKEN", "").strip(),
            api_base_url=env.get("MINERU_API_BASE_URL", "https://mineru.net/api/v4").strip()
            or "https://mineru.net/api/v4",
            model_version=env.get("MINERU_MODEL_VERSION", "vlm").strip() or "vlm",
            language=env.get("MINERU_LANGUAGE", "ch").strip() or "ch",
            enable_formula=_bool(env.get("MINERU_ENABLE_FORMULA"), True),
            enable_table=_bool(env.get("MINERU_ENABLE_TABLE"), True),
            enable_ocr=_bool(env.get("MINERU_ENABLE_OCR"), False),
            polling_interval_seconds=max(0.5, _float(env.get("MINERU_POLLING_INTERVAL_SECONDS"), 2)),
            max_polling_attempts=_int(env.get("MINERU_MAX_POLLING_ATTEMPTS"), 40, minimum=1),
        ),
        llm_models=_load_llm_models(env),
        langfuse=LangfuseSettings(
            enabled=_bool(env.get("EDUNODE_LITELLM_ENABLE_LANGFUSE"), True),
            public_key=env.get("LANGFUSE_PUBLIC_KEY", "").strip(),
            secret_key=env.get("LANGFUSE_SECRET_KEY", "").strip(),
            otel_host=(
                env.get("LANGFUSE_OTEL_HOST")
                or env.get("LANGFUSE_HOST")
                or ""
            ).strip(),
        ),
        usage_log_path=usage_path,
    )
