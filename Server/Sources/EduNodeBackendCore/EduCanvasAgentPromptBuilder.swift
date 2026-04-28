import Foundation
import EduNodeContracts

enum EduCanvasAgentPromptBuilder {
    static func workspacePlanningMessages(
        request: EduCanvasAgentAutoRequest,
        settings: EduAgentProviderSettingsResolved
    ) -> [EduLLMMessage] {
        [
            .init(
                role: "system",
                content: mergedSystemPrompt(
                    base: """
                    You are the planning stage of an instructional-design copilot working inside EduNode.
                    Your task is to inspect the structured node canvas, decide how the next response should be handled, and produce a concise plan-and-solve artifact for the teacher.

                    Output strict JSON only.
                    Do not wrap JSON in markdown fences.
                    Refer to the workspace as a node canvas (Chinese: 节点画布), never as an image, chart, screenshot, or figure.
                    Base every statement on the provided snapshot JSON.
                    Do not invent missing nodes, missing counts, or unsupported metadata.

                    decision_mode must be one of:
                    - advisory
                    - operational

                    thinking_trace_markdown is user-visible. It is not a raw chain-of-thought dump.
                    Write it as a compact Markdown planning brief with these exact sections:
                    ### Task Framing
                    ### Decision
                    ### Plan
                    ### Checks

                    Under Plan, provide 3-5 short bullets.
                    Under Checks, mention only the most relevant data sufficiency checks, constraints, or guardrails.

                    Return this JSON shape:
                    {
                      "decision_mode": "advisory|operational",
                      "thinking_trace_markdown": "Markdown planning brief"
                    }
                    """,
                    settings: settings
                )
            ),
            .init(
                role: "user",
                content: """
                Workspace snapshot JSON:
                \(encodedJSONString(request.workspace))

                Workspace quick facts:
                \(workspaceQuickFacts(request.workspace, interfaceLanguageCode: request.interfaceLanguageCode))

                Supported canvas schema JSON:
                \(encodedJSONString(request.schema))

                Supplementary material:
                \(normalizedSupplementaryMaterial(request.supplementaryMaterial))
                """
            )
        ] + conversationMessages(request.conversation) + [
            .init(role: "user", content: request.userRequest)
        ]
    }

    static func workspaceAutoMessages(
        request: EduCanvasAgentAutoRequest,
        settings: EduAgentProviderSettingsResolved,
        thinkingPlan: EduAgentThinkingPlanResponse?
    ) -> [EduLLMMessage] {
        let thinkingFieldRule = request.thinkingEnabled
            ? """
                    Thinking mode is enabled.
                    Include "thinking_trace_markdown" as a concise, user-visible plan-and-solve summary in Markdown.
                    Do not expose private chain-of-thought.
                    Keep it compact and teacher-facing.
                    Prefer sections such as:
                    ### Task Framing
                    ### Decision
                    ### Plan Used
                    ### Why This Response
                    """
            : """
                    Thinking mode is disabled.
                    Set "thinking_trace_markdown" to null.
                    """

        return [
            .init(
                role: "system",
                content: mergedSystemPrompt(
                    base: """
                    You are an instructional-design copilot working inside EduNode.
                    Answer as a rigorous pedagogical collaborator, not as a product marketer.
                    Ground every answer in the provided course graph and teacher context.
                    Decide whether the user's request is primarily:
                    1. advisory or diagnostic, in which case you should explain, critique, prioritize, or answer questions; or
                    2. operational, in which case you should return minimal, pedagogically coherent graph operations.

                    Output strict JSON only.
                    Do not wrap JSON in markdown fences.
                    In assistant_reply, refer to the workspace as a node canvas (Chinese: 节点画布), not as an image, picture, chart, screenshot, or figure.
                    Never say "I can only see" or imply partial visual access. You are given the full structured workspace snapshot.
                    Before mentioning counts, missing nodes, or gaps, cross-check them against the snapshot JSON and the node-title inventory.
                    Do not ask the teacher to recount nodes that already exist in the snapshot.
                    Never invent unsupported node types or field ids.
                    Prefer small, high-leverage edits over bloated rewrites.
                    Supported operations are: add_node, update_node, connect, disconnect, move_node, delete_node.
                    If the user is not explicitly asking for a canvas change, or the current information is insufficient to make a safe graph edit, return an empty operations array.
                    When you return no operations, the assistant_reply should still be useful and specific, and it may use Markdown.
                    When you do return operations, the assistant_reply should briefly explain the proposed changes and why they fit the pedagogy.
                    If a planning artifact is provided, treat it as the execution contract unless the snapshot JSON clearly requires a correction.
                    \(thinkingFieldRule)
                    Return this JSON shape:
                    {
                      "assistant_reply": "brief explanation or answer in Markdown if helpful",
                      "thinking_trace_markdown": "optional concise reasoning summary in Markdown, or null",
                      "operations": [
                        {
                          "op": "add_node",
                          "temp_id": "new_k1",
                          "node_type": "EduKnowledge",
                          "title": "optional",
                          "text_value": "optional",
                          "selected_option": "optional",
                          "selected_method_id": "optional",
                          "text_field_values": {"field_id": "value"},
                          "option_field_values": {"field_id": "value"},
                          "anchor_node_ref": "existing_uuid_or_temp_id",
                          "placement": "right|left|above|below"
                        }
                      ]
                    }

                    For update_node, use:
                    {
                      "op": "update_node",
                      "node_ref": "existing_uuid",
                      "title": "optional",
                      "text_value": "optional",
                      "selected_option": "optional",
                      "selected_method_id": "optional",
                      "text_field_values": {"field_id": "value"},
                      "option_field_values": {"field_id": "value"}
                    }

                    For connect/disconnect, use:
                    {
                      "op": "connect",
                      "source_node_ref": "uuid_or_temp_id",
                      "target_node_ref": "uuid_or_temp_id",
                      "source_port_name": "optional",
                      "target_port_name": "optional"
                    }

                    For move_node, use:
                    {
                      "op": "move_node",
                      "node_ref": "existing_uuid",
                      "anchor_node_ref": "optional_existing_uuid_or_temp_id",
                      "placement": "right|left|above|below",
                      "position_x": 640,
                      "position_y": 220
                    }

                    For delete_node, use:
                    {
                      "op": "delete_node",
                      "node_ref": "existing_uuid"
                    }

                    Additional rules for EduEvaluation updates:
                    - Put actual indicators only in text_field_values["evaluation_indicators"].
                    - Each line must be "Indicator | score|completion | optional weight".
                    - Do not place rubric prose, section headings, scoring-band labels, or ranges like "90-100" into evaluation_indicators.
                    - Quantitative refinement should mainly be expressed through indicator weights, evaluation_formula, and evaluation_output_scale.
                    """,
                    settings: settings
                )
            ),
            .init(
                role: "user",
                content: """
                Workspace snapshot JSON:
                \(encodedJSONString(request.workspace))

                Workspace quick facts:
                \(workspaceQuickFacts(request.workspace, interfaceLanguageCode: request.interfaceLanguageCode))

                Supported canvas schema JSON:
                \(encodedJSONString(request.schema))

                Thinking mode:
                \(request.thinkingEnabled ? "enabled" : "disabled")

                Planning artifact:
                \(normalizedPlanningArtifact(thinkingPlan))

                Supplementary material:
                \(normalizedSupplementaryMaterial(request.supplementaryMaterial))
                """
            )
        ] + conversationMessages(request.conversation) + [
            .init(role: "user", content: request.userRequest)
        ]
    }

    static func workspaceSuggestedPromptMessages(
        request: EduCanvasSuggestedPromptsRequest,
        settings: EduAgentProviderSettingsResolved
    ) -> [EduLLMMessage] {
        [
            .init(
                role: "system",
                content: mergedSystemPrompt(
                    base: """
                    You generate short suggested teacher prompts for a teacher assistant working on a node canvas.
                    Output strict JSON only. Do not wrap in markdown fences.
                    Treat the workspace as a node canvas, not an image or picture.
                    Return:
                    {
                      "suggestions": [
                        "short prompt 1",
                        "short prompt 2",
                        "short prompt 3"
                      ]
                    }
                    Requirements:
                    - Generate exactly 3 suggestions.
                    - Each suggestion should be concise and directly clickable as a prompt chip.
                    - Keep each suggestion to at most 18 Chinese characters or 10 English words.
                    - Ground suggestions in the provided workspace graph.
                    - Avoid generic filler.
                    - Mix likely next-step prompts across diagnosis, revision, and concrete graph improvement when appropriate.
                    - Prefer prompts that a teacher can immediately click and use without editing.
                    - Use the interface language code to align the response language when it is available.
                    """,
                    settings: settings
                )
            ),
            .init(
                role: "user",
                content: """
                Workspace snapshot JSON:
                \(encodedJSONString(request.workspace))

                Workspace quick facts:
                \(workspaceQuickFacts(request.workspace, interfaceLanguageCode: request.interfaceLanguageCode))

                Supplementary material:
                \(normalizedSupplementaryMaterial(request.supplementaryMaterial))
                """
            )
        ]
    }

    private static func mergedSystemPrompt(
        base: String,
        settings: EduAgentProviderSettingsResolved
    ) -> String {
        let extra = settings.additionalSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !extra.isEmpty else { return base }
        return base + "\n\nAdditional provider-specific guidance:\n" + extra
    }

    private static func conversationMessages(_ conversation: [EduAgentConversationTurn]) -> [EduLLMMessage] {
        conversation.suffix(12).map {
            EduLLMMessage(role: $0.role, content: $0.content)
        }
    }

    private static func normalizedSupplementaryMaterial(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "(none)" : trimmed
    }

    private static func normalizedPlanningArtifact(_ plan: EduAgentThinkingPlanResponse?) -> String {
        guard let plan else { return "(none)" }
        return """
        decision_mode: \(plan.decisionMode)

        \(plan.thinkingTraceMarkdown)
        """
    }

    private static func workspaceQuickFacts(
        _ snapshot: EduAgentWorkspaceSnapshot,
        interfaceLanguageCode: String
    ) -> String {
        let isChinese = interfaceLanguageCode.lowercased().hasPrefix("zh")
        let knowledgeTitles = snapshot.nodes.filter { $0.nodeFamily == "knowledge" }.map(\.title)
        let toolkitTitles = snapshot.nodes.filter { $0.nodeFamily == "toolkit" }.map(\.title)
        let evaluationTitles = snapshot.nodes.filter { $0.nodeFamily == "evaluation" }.map(\.title)

        let joinedKnowledge = knowledgeTitles.isEmpty ? (isChinese ? "无" : "none") : knowledgeTitles.joined(separator: isChinese ? "、" : ", ")
        let joinedToolkit = toolkitTitles.isEmpty ? (isChinese ? "无" : "none") : toolkitTitles.joined(separator: isChinese ? "、" : ", ")
        let joinedEvaluation = evaluationTitles.isEmpty ? (isChinese ? "无" : "none") : evaluationTitles.joined(separator: isChinese ? "、" : ", ")

        if isChinese {
            return """
            - 当前对象是节点画布，不是图片。
            - 总节点数：\(snapshot.nodes.count)
            - Knowledge 节点（\(knowledgeTitles.count)）：\(joinedKnowledge)
            - Toolkit 节点（\(toolkitTitles.count)）：\(joinedToolkit)
            - Evaluation 节点（\(evaluationTitles.count)）：\(joinedEvaluation)
            """
        }

        return """
        - This is a node canvas, not an image.
        - Total nodes: \(snapshot.nodes.count)
        - Knowledge nodes (\(knowledgeTitles.count)): \(joinedKnowledge)
        - Toolkit nodes (\(toolkitTitles.count)): \(joinedToolkit)
        - Evaluation nodes (\(evaluationTitles.count)): \(joinedEvaluation)
        """
    }

    private static func encodedJSONString<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}
