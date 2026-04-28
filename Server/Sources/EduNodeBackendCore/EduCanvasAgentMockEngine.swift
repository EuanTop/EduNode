import Foundation
import EduNodeContracts

enum EduCanvasAgentMockEngine {
    private static let evaluationNodeType = "EduEvaluation"
    private static let toolkitInquiryNodeType = "EduToolkitPerceptionInquiry"
    private static let toolkitKnowledgePort = "Knowledge"
    private static let toolkitOutputPort = "Toolkit Output"

    static func suggestedPrompts(
        for request: EduCanvasSuggestedPromptsRequest
    ) -> EduAgentSuggestedPromptsResponse {
        let isChinese = request.interfaceLanguageCode.lowercased().hasPrefix("zh")
        let graph = GraphContext(workspace: request.workspace)

        var suggestions: [String] = []

        if graph.evaluationNodes.isEmpty {
            suggestions.append(
                isChinese
                    ? "补一个与现有活动衔接的评价节点，并明确量化规则。"
                    : "Add an evaluation node that connects to the current activity flow and makes scoring criteria explicit."
            )
        }

        if graph.toolkitNodes.count <= 1 {
            suggestions.append(
                isChinese
                    ? "围绕现有知识主线，再补一个更可执行的 Toolkit 活动。"
                    : "Add one more executable toolkit activity around the current knowledge backbone."
            )
        }

        suggestions.append(
            isChinese
                ? "检查节点之间的承接关系，避免知识点与活动链条脱节。"
                : "Check whether the current node connections keep knowledge and activity flow aligned."
        )

        if !request.supplementaryMaterial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            suggestions.append(
                isChinese
                    ? "把补充材料中的约束翻译成节点层级的修改建议。"
                    : "Translate the supplementary constraints into concrete node-level revisions."
            )
        }

        return EduAgentSuggestedPromptsResponse(suggestions: Array(suggestions.prefix(3)))
    }

    static func respond(
        to request: EduCanvasAgentAutoRequest
    ) -> EduAgentGraphOperationEnvelope {
        let isChinese = request.interfaceLanguageCode.lowercased().hasPrefix("zh")
        let graph = GraphContext(workspace: request.workspace)
        let semantic = semanticText(for: request)

        if semantic.contains(anyOf: evaluationTokens) {
            return evaluationResponse(for: request, graph: graph, isChinese: isChinese)
        }

        if semantic.contains(anyOf: classificationTokens) || semantic.contains(anyOf: practiceTokens) {
            return toolkitResponse(for: request, graph: graph, isChinese: isChinese)
        }

        let assistantReply = isChinese
            ? """
            我先不给出激进改动，建议优先补足两个方向：
            1. 让知识节点明确落到一个可执行的 Toolkit 活动。
            2. 让活动输出进入评价节点，形成可追踪的证据链。
            """
            : """
            I would avoid aggressive edits first. Prioritize two things:
            1. Attach each knowledge idea to an executable toolkit activity.
            2. Route activity output into evaluation so evidence remains traceable.
            """

        return EduAgentGraphOperationEnvelope(
            assistantReply: assistantReply,
            thinkingTraceMarkdown: thinkingTrace(isChinese: isChinese, decision: isChinese ? "advisory" : "advisory"),
            operations: []
        )
    }

    private static func evaluationResponse(
        for request: EduCanvasAgentAutoRequest,
        graph: GraphContext,
        isChinese: Bool
    ) -> EduAgentGraphOperationEnvelope {
        let indicatorText = isChinese
            ? """
            观察准确性 | score | 2
            证据表达 | score | 2
            反思完成度 | completion | 1
            """
            : """
            Observation accuracy | score | 2
            Evidence explanation | score | 2
            Reflection completion | completion | 1
            """

        let optionValues = [
            "evaluation_formula": "weighted_avg",
            "evaluation_grouping": "individual",
            "evaluation_output_scale": "score100"
        ]

        var operations: [EduAgentGraphOperation] = []

        if let existingEvaluation = graph.evaluationNodes.first {
            operations.append(
                EduAgentGraphOperation(
                    op: "update_node",
                    nodeRef: existingEvaluation.id,
                    title: isChinese ? "课堂评价量规" : "Classroom Assessment Rubric",
                    textFieldValues: [
                        "evaluation_indicators": indicatorText
                    ],
                    optionFieldValues: optionValues
                )
            )

            if let sourceNode = graph.preferredActivityAnchor ?? graph.knowledgeNodes.first,
               !graph.hasConnection(from: sourceNode.id, to: existingEvaluation.id) {
                operations.append(
                    EduAgentGraphOperation(
                        op: "connect",
                        sourceNodeRef: sourceNode.id,
                        targetNodeRef: existingEvaluation.id,
                        sourcePortName: nil,
                        targetPortName: nil
                    )
                )
            }

            let reply = isChinese
                ? "我把已有评价节点补成更明确的量化量规，并尽量与当前活动链条直接连接。"
                : "I tightened the existing evaluation node into a clearer quantitative rubric and linked it back to the current activity flow."
            return EduAgentGraphOperationEnvelope(
                assistantReply: reply,
                thinkingTraceMarkdown: thinkingTrace(isChinese: isChinese, decision: isChinese ? "evaluation-update" : "evaluation-update"),
                operations: operations
            )
        }

        let tempID = "mock-evaluation-1"
        let anchor = graph.preferredActivityAnchor ?? graph.knowledgeNodes.first

        operations.append(
            EduAgentGraphOperation(
                op: "add_node",
                tempID: tempID,
                nodeType: evaluationNodeType,
                title: isChinese ? "课堂评价量规" : "Classroom Assessment Rubric",
                textFieldValues: [
                    "evaluation_indicators": indicatorText
                ],
                optionFieldValues: optionValues,
                anchorNodeRef: anchor?.id,
                placement: "right"
            )
        )

        if let sourceNode = anchor {
            operations.append(
                EduAgentGraphOperation(
                    op: "connect",
                    sourceNodeRef: sourceNode.id,
                    targetNodeRef: tempID,
                    sourcePortName: nil,
                    targetPortName: nil
                )
            )
        }

        let reply = isChinese
            ? "我补了一个评价节点，并把它挂到当前最相关的活动节点后面，方便后续直接形成可量化的课堂证据。"
            : "I added an evaluation node and attached it after the most relevant activity node so the lesson can keep a quantifiable evidence trail."

        return EduAgentGraphOperationEnvelope(
            assistantReply: reply,
            thinkingTraceMarkdown: thinkingTrace(isChinese: isChinese, decision: isChinese ? "evaluation-add" : "evaluation-add"),
            operations: operations
        )
    }

    private static func toolkitResponse(
        for request: EduCanvasAgentAutoRequest,
        graph: GraphContext,
        isChinese: Bool
    ) -> EduAgentGraphOperationEnvelope {
        let tempID = "mock-toolkit-1"
        let anchor = graph.knowledgeNodes.first

        let title = isChinese ? "鸟类分类练习" : "Bird Classification Practice"
        let textValue = isChinese
            ? "学生依据喙、足、栖息地与食性，对鸟类样本进行分类并给出证据。"
            : "Students classify bird examples by beak, feet, habitat, and feeding pattern, then justify each choice with evidence."

        let textFields = isChinese
            ? [
                "observation_target": "鸟类卡片与本地鸟类照片",
                "observation_focus": "喙、足、栖息地、取食方式",
                "field_obs_open_prompts": "先分类，再说明分类依据，并比较至少两类差异。"
            ]
            : [
                "observation_target": "Bird cards and local bird photos",
                "observation_focus": "Beak, feet, habitat, and feeding pattern",
                "field_obs_open_prompts": "Classify first, then justify the criteria and compare at least two categories."
            ]

        var operations: [EduAgentGraphOperation] = [
            EduAgentGraphOperation(
                op: "add_node",
                tempID: tempID,
                nodeType: toolkitInquiryNodeType,
                title: title,
                textValue: textValue,
                selectedMethodID: "field_observation",
                textFieldValues: textFields,
                optionFieldValues: [
                    "field_obs_task_structure": "classification"
                ],
                anchorNodeRef: anchor?.id ?? graph.toolkitNodes.first?.id,
                placement: "right"
            )
        ]

        if let knowledge = anchor {
            operations.append(
                EduAgentGraphOperation(
                    op: "connect",
                    sourceNodeRef: knowledge.id,
                    targetNodeRef: tempID,
                    sourcePortName: nil,
                    targetPortName: toolkitKnowledgePort
                )
            )
        }

        if let evaluation = graph.evaluationNodes.first {
            operations.append(
                EduAgentGraphOperation(
                    op: "connect",
                    sourceNodeRef: tempID,
                    targetNodeRef: evaluation.id,
                    sourcePortName: toolkitOutputPort,
                    targetPortName: nil
                )
            )
        }

        let reply = isChinese
            ? "我加了一个更贴近当前内容的分类练习 Toolkit，并尽量接在现有知识与评价链之间。"
            : "I added a classification-practice toolkit that fits the current content and sits between the knowledge and evaluation chain."

        return EduAgentGraphOperationEnvelope(
            assistantReply: reply,
            thinkingTraceMarkdown: thinkingTrace(isChinese: isChinese, decision: isChinese ? "toolkit-add" : "toolkit-add"),
            operations: operations
        )
    }

    private static func semanticText(
        for request: EduCanvasAgentAutoRequest
    ) -> String {
        [
            request.userRequest,
            request.supplementaryMaterial,
            request.conversation.last?.content
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
        .lowercased()
    }

    private static func thinkingTrace(
        isChinese: Bool,
        decision: String
    ) -> String {
        if isChinese {
            return """
            ## Planning
            - 先识别当前请求更接近“评价补足”还是“活动补足”。
            - 优先沿着现有节点链条做最小增量修改，避免打断教师已经完成的画布结构。

            ## Decision
            - 当前采用：\(decision)
            - 修改遵循“少改动、强承接、可落地”的原则。
            """
        }

        return """
        ## Planning
        - First classify the request as evaluation completion or activity completion.
        - Prefer the smallest graph change that preserves the teacher's current canvas structure.

        ## Decision
        - Current path: \(decision)
        - The change follows a minimal, coherent, and directly actionable editing strategy.
        """
    }

    private static let evaluationTokens = [
        "evaluation", "assessment", "rubric", "score", "grading", "feedback",
        "评价", "评估", "量化", "评分", "打分", "反馈"
    ]

    private static let classificationTokens = [
        "classify", "classification", "sort", "分类", "归类"
    ]

    private static let practiceTokens = [
        "practice", "exercise", "activity", "task", "练习", "活动", "任务"
    ]

    private struct GraphContext {
        let workspace: EduAgentWorkspaceSnapshot

        var knowledgeNodes: [EduAgentGraphNodeSnapshot] {
            workspace.nodes.filter { $0.nodeFamily == "knowledge" }
        }

        var toolkitNodes: [EduAgentGraphNodeSnapshot] {
            workspace.nodes.filter { $0.nodeFamily == "toolkit" }
        }

        var evaluationNodes: [EduAgentGraphNodeSnapshot] {
            workspace.nodes.filter { $0.nodeFamily == "evaluation" }
        }

        var preferredActivityAnchor: EduAgentGraphNodeSnapshot? {
            toolkitNodes.last ?? knowledgeNodes.last
        }

        func hasConnection(from sourceNodeID: String, to targetNodeID: String) -> Bool {
            workspace.connections.contains {
                $0.sourceNodeID == sourceNodeID && $0.targetNodeID == targetNodeID
            }
        }
    }
}

private extension String {
    func contains(anyOf tokens: [String]) -> Bool {
        tokens.contains(where: { self.contains($0) })
    }
}
