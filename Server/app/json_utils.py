from __future__ import annotations

import json
from typing import Any


def first_json_object(raw: str) -> dict[str, Any]:
    text = strip_code_fence(raw)
    try:
        parsed = json.loads(text)
        if isinstance(parsed, dict):
            return parsed
    except json.JSONDecodeError:
        pass

    start: int | None = None
    depth = 0
    in_string = False
    escaped = False
    for index, char in enumerate(text):
        if escaped:
            escaped = False
            continue
        if char == "\\":
            escaped = True
            continue
        if char == '"':
            in_string = not in_string
            continue
        if in_string:
            continue
        if char == "{":
            if start is None:
                start = index
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0 and start is not None:
                parsed = json.loads(text[start : index + 1])
                if isinstance(parsed, dict):
                    return parsed
                break
    raise ValueError("Structured parse failed: no JSON object found.")


def strip_code_fence(raw: str) -> str:
    text = raw.strip()
    if not text.startswith("```"):
        return text
    lines = text.splitlines()
    if len(lines) <= 2:
        return text.strip("`").strip()
    return "\n".join(lines[1:-1]).strip()


def compact_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2)

