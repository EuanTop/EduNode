from __future__ import annotations

import json
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class LLMUsageRecord:
    request_id: str
    user_id: str
    route: str
    provider_name: str
    model_alias: str
    model: str
    success: bool
    latency_ms: int
    prompt_tokens: int
    completion_tokens: int
    total_tokens: int
    cost_usd: float | None = None
    response_id: str = ""
    error: str = ""

    def as_json(self) -> dict[str, Any]:
        return {
            "ts": int(time.time()),
            "request_id": self.request_id,
            "user_id": self.user_id,
            "route": self.route,
            "provider_name": self.provider_name,
            "model_alias": self.model_alias,
            "model": self.model,
            "success": self.success,
            "latency_ms": self.latency_ms,
            "prompt_tokens": self.prompt_tokens,
            "completion_tokens": self.completion_tokens,
            "total_tokens": self.total_tokens,
            "cost_usd": self.cost_usd,
            "response_id": self.response_id,
            "error": self.error,
        }


class UsageLogger:
    def __init__(self, path: Path) -> None:
        self.path = path

    def write(self, record: LLMUsageRecord) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self.path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(record.as_json(), ensure_ascii=False) + "\n")
