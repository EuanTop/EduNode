from __future__ import annotations

from typing import Any

from .json_utils import compact_json, first_json_object
from .llm_router import LLMRouter


class CanvasAgentService:
    def __init__(self, router: LLMRouter, mode: str = "live") -> None:
        self.router = router
        self.mode = mode

    async def runtime_status(self) -> dict[str, Any]:
        if self.mode == "mock":
            return {
                "llm_configured": True,
                "provider_reachable": True,
                "provider_name": "Mock",
                "active_model": "mock-model",
                "base_url_host": "mock",
                "available_models": ["mock-model"],
                "message": "Mock agent mode is active.",
            }
        primary = self.router.models[0] if self.router.models else None
        if not primary:
            return {
                "llm_configured": False,
                "provider_reachable": False,
                "provider_name": "",
                "active_model": "",
                "base_url_host": "",
                "available_models": [],
                "message": "Server-side LLM configuration is incomplete.",
            }
        try:
            models = await self.router.list_models()
            return {
                "llm_configured": True,
                "provider_reachable": True,
                "provider_name": primary.provider_name,
                "active_model": primary.model,
                "base_url_host": primary.host,
                "available_models": models,
                "message": "Connected to the configured provider.",
            }
        except Exception as error:
            return {
                "llm_configured": True,
                "provider_reachable": False,
                "provider_name": primary.provider_name,
                "active_model": primary.model,
                "base_url_host": primary.host,
                "available_models": [primary.model],
                "message": str(error),
            }

    async def respond(self, payload: dict[str, Any], *, user_id: str) -> dict[str, Any]:
        if self.mode == "mock":
            return _mock_response(payload)

        planning: dict[str, Any] | None = None
        if _get(payload, "thinkingEnabled", "thinking_enabled"):
            try:
                planning_reply = await self.router.complete(
                    _planning_messages(payload),
                    route="canvas.planning",
                    user_id=user_id,
                )
                planning = first_json_object(planning_reply.content)
            except Exception:
                planning = None

        completion = await self.router.complete(
            _auto_messages(payload, planning),
            route="canvas.respond",
            user_id=user_id,
        )
        try:
            structured = first_json_object(completion.content)
            structured.setdefault("assistant_reply", "")
            structured.setdefault("thinking_trace_markdown", planning.get("thinking_trace_markdown") if planning else None)
            structured.setdefault("operations", [])
            return structured
        except Exception:
            return {
                "assistant_reply": completion.content,
                "thinking_trace_markdown": planning.get("thinking_trace_markdown") if planning else None,
                "operations": [],
            }

    async def suggested_prompts(self, payload: dict[str, Any], *, user_id: str) -> dict[str, Any]:
        if self.mode == "mock":
            return {"suggestions": _fallback_suggestions(payload)}
        completion = await self.router.complete(
            _suggested_prompt_messages(payload),
            route="canvas.suggested_prompts",
            user_id=user_id,
        )
        structured = first_json_object(completion.content)
        suggestions = structured.get("suggestions")
        if not isinstance(suggestions, list):
            suggestions = _fallback_suggestions(payload)
        return {"suggestions": [str(item) for item in suggestions[:3]]}


def _planning_messages(payload: dict[str, Any]) -> list[dict[str, str]]:
    return [
        {
            "role": "system",
            "content": """
You are the planning stage of an instructional-design copilot working inside EduNode.
Output strict JSON only. Do not wrap JSON in markdown fences.
Refer to the workspace as a node canvas (Chinese: 节点画布), never as an image.
Base every statement on the provided snapshot JSON. Do not invent missing nodes or counts.

Return this JSON shape:
{
  "decision_mode": "advisory|operational",
  "thinking_trace_markdown": "compact teacher-facing Markdown planning brief"
}
""".strip(),
        },
        {
            "role": "user",
            "content": _workspace_context(payload),
        },
        *_conversation_messages(payload),
        {"role": "user", "content": str(_get(payload, "userRequest", "user_request") or "")},
    ]


def _auto_messages(payload: dict[str, Any], planning: dict[str, Any] | None) -> list[dict[str, str]]:
    thinking_rule = (
        'Include "thinking_trace_markdown" as a concise, user-visible plan-and-solve summary in Markdown.'
        if _get(payload, "thinkingEnabled", "thinking_enabled")
        else 'Set "thinking_trace_markdown" to null.'
    )
    return [
        {
            "role": "system",
            "content": f"""
You are an instructional-design copilot working inside EduNode.
Answer as a rigorous pedagogical collaborator, not as a product marketer.
Ground every answer in the provided course graph and teacher context.
Output strict JSON only. Do not wrap JSON in markdown fences.
Refer to the workspace as a node canvas (Chinese: 节点画布), not as an image or screenshot.
Never invent unsupported node types or field ids.
Prefer small, high-leverage edits over bloated rewrites.
Supported operations are: add_node, update_node, connect, disconnect, move_node, delete_node.
If the user is not explicitly asking for a canvas change, return an empty operations array.
{thinking_rule}

Return:
{{
  "assistant_reply": "brief explanation or answer in Markdown if helpful",
  "thinking_trace_markdown": "optional concise reasoning summary in Markdown, or null",
  "operations": []
}}

For add_node, update_node, connect, disconnect, move_node, delete_node, use the snake_case fields already present in the schema.
For activity/practice/classification tasks, prefer Toolkit node types from the supported schema over Knowledge nodes.
For EduEvaluation updates, put actual indicators only in text_field_values["evaluation_indicators"].
""".strip(),
        },
        {
            "role": "user",
            "content": _workspace_context(payload)
            + "\n\nPlanning artifact:\n"
            + (compact_json(planning) if planning else "(none)"),
        },
        *_conversation_messages(payload),
        {"role": "user", "content": str(_get(payload, "userRequest", "user_request") or "")},
    ]


def _suggested_prompt_messages(payload: dict[str, Any]) -> list[dict[str, str]]:
    return [
        {
            "role": "system",
            "content": """
Generate exactly 3 short suggested teacher prompts for a node-canvas assistant.
Output strict JSON only:
{"suggestions": ["short prompt 1", "short prompt 2", "short prompt 3"]}
Keep each suggestion concise, grounded in the workspace, and aligned with interface language.
""".strip(),
        },
        {"role": "user", "content": _workspace_context(payload)},
    ]


def _workspace_context(payload: dict[str, Any]) -> str:
    workspace = payload.get("workspace", {})
    schema = payload.get("schema", {})
    language = str(_get(payload, "interfaceLanguageCode", "interface_language_code") or "")
    return f"""
Workspace snapshot JSON:
{compact_json(workspace)}

Workspace quick facts:
{_quick_facts(workspace, language)}

Supported canvas schema JSON:
{compact_json(schema)}

Supplementary material:
{str(_get(payload, "supplementaryMaterial", "supplementary_material") or "").strip() or "(none)"}
""".strip()


def _conversation_messages(payload: dict[str, Any]) -> list[dict[str, str]]:
    turns = payload.get("conversation", [])
    if not isinstance(turns, list):
        return []
    messages = []
    for turn in turns[-12:]:
        if isinstance(turn, dict):
            role = str(turn.get("role", "user"))
            content = str(turn.get("content", ""))
            messages.append({"role": role, "content": content})
    return messages


def _quick_facts(workspace: dict[str, Any], language: str) -> str:
    nodes = workspace.get("nodes", [])
    nodes = nodes if isinstance(nodes, list) else []
    knowledge = [str(node.get("title", "")) for node in nodes if isinstance(node, dict) and node.get("nodeFamily") == "knowledge"]
    toolkit = [str(node.get("title", "")) for node in nodes if isinstance(node, dict) and node.get("nodeFamily") == "toolkit"]
    evaluation = [str(node.get("title", "")) for node in nodes if isinstance(node, dict) and node.get("nodeFamily") == "evaluation"]
    is_zh = language.lower().startswith("zh")
    joiner = "、" if is_zh else ", "
    if is_zh:
        return "\n".join(
            [
                "- 当前对象是节点画布，不是图片。",
                f"- 总节点数：{len(nodes)}",
                f"- Knowledge 节点（{len(knowledge)}）：{joiner.join(knowledge) or '无'}",
                f"- Toolkit 节点（{len(toolkit)}）：{joiner.join(toolkit) or '无'}",
                f"- Evaluation 节点（{len(evaluation)}）：{joiner.join(evaluation) or '无'}",
            ]
        )
    return "\n".join(
        [
            "- This is a node canvas, not an image.",
            f"- Total nodes: {len(nodes)}",
            f"- Knowledge nodes ({len(knowledge)}): {joiner.join(knowledge) or 'none'}",
            f"- Toolkit nodes ({len(toolkit)}): {joiner.join(toolkit) or 'none'}",
            f"- Evaluation nodes ({len(evaluation)}): {joiner.join(evaluation) or 'none'}",
        ]
    )


def _fallback_suggestions(payload: dict[str, Any]) -> list[str]:
    is_zh = str(_get(payload, "interfaceLanguageCode", "interface_language_code") or "").lower().startswith("zh")
    return (
        ["优化活动衔接", "补充评价量规", "检查知识链条"]
        if is_zh
        else ["Improve activity flow", "Add assessment rubric", "Check knowledge chain"]
    )


def _mock_response(payload: dict[str, Any]) -> dict[str, Any]:
    is_zh = str(_get(payload, "interfaceLanguageCode", "interface_language_code") or "").lower().startswith("zh")
    return {
        "assistant_reply": "当前是 mock 模式，我会先建议检查知识、活动与评价的证据链。" if is_zh else "Mock mode: check the evidence chain across knowledge, activities, and assessment.",
        "thinking_trace_markdown": "### Decision\nMock advisory response.",
        "operations": [],
    }


def _get(payload: dict[str, Any], camel: str, snake: str) -> Any:
    if camel in payload:
        return payload.get(camel)
    return payload.get(snake)
