import Foundation
import CoreGraphics
import GNodeKit

enum EduAgentProposalStatus: String, Codable {
    case pending
    case applied
    case dismissed
}

struct EduAgentConversationMessage: Identifiable, Codable {
    enum Role: String, Codable {
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    var content: String
    var thinkingTraceMarkdown: String?
    var suggestedPrompts: [String]
    var canvasProposal: EduAgentGraphOperationEnvelope?
    var proposalStatus: EduAgentProposalStatus?

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        thinkingTraceMarkdown: String? = nil,
        suggestedPrompts: [String] = [],
        canvasProposal: EduAgentGraphOperationEnvelope? = nil,
        proposalStatus: EduAgentProposalStatus? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.thinkingTraceMarkdown = thinkingTraceMarkdown
        self.suggestedPrompts = suggestedPrompts
        self.canvasProposal = canvasProposal
        self.proposalStatus = proposalStatus
    }

    var effectiveProposalStatus: EduAgentProposalStatus? {
        guard canvasProposal != nil else { return nil }
        return proposalStatus ?? .pending
    }

    var hasPendingCanvasProposal: Bool {
        effectiveProposalStatus == .pending
    }
}

struct EduAgentLessonPlanRevisionResponse: Decodable {
    let assistantReply: String
    let revisedMarkdown: String

    enum CodingKeys: String, CodingKey {
        case assistantReply = "assistant_reply"
        case revisedMarkdown = "revised_markdown"
    }
}

struct EduAgentSlideContentOverride: Decodable, Identifiable {
    let id = UUID()
    let slideID: UUID
    let title: String?
    let subtitle: String?
    let mainContent: String?
    let toolkitContent: String?

    enum CodingKeys: String, CodingKey {
        case slideID = "slide_id"
        case title
        case subtitle
        case mainContent = "main_content"
        case toolkitContent = "toolkit_content"
    }

    var nativeOverrides: [PresentationNativeElement: String] {
        var result: [PresentationNativeElement: String] = [:]
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result[.title] = title
        }
        if let subtitle, !subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result[.subtitle] = subtitle
        }
        if let mainContent, !mainContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result[.mainContent] = mainContent
        }
        if let toolkitContent, !toolkitContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result[.toolkitContent] = toolkitContent
        }
        return result
    }
}

struct EduAgentPresentationRevisionResponse: Decodable {
    let assistantReply: String
    let slideOverrides: [EduAgentSlideContentOverride]

    enum CodingKeys: String, CodingKey {
        case assistantReply = "assistant_reply"
        case slideOverrides = "slide_overrides"
    }
}

enum EduAgentContextBuilder {
    static func workspaceSnapshot(
        file: GNodeWorkspaceFile,
        lessonPlanMarkdown: String? = nil,
        slides: [EduPresentationComposedSlide] = []
    ) -> EduAgentWorkspaceSnapshot {
        let course = EduAgentCourseSnapshot(
            name: file.name,
            subject: file.subject,
            gradeMode: file.gradeMode,
            gradeMin: file.gradeMin,
            gradeMax: file.gradeMax,
            lessonDurationMinutes: file.lessonDurationMinutes,
            studentCount: file.studentCount,
            periodRange: file.periodRange,
            goalsText: file.goalsText,
            modelID: file.modelID,
            teacherTeam: file.teacherTeam,
            studentPriorKnowledgeLevel: file.studentPriorKnowledgeLevel,
            studentMotivationLevel: file.studentMotivationLevel,
            studentSupportNotes: file.studentSupportNotes,
            resourceConstraints: file.resourceConstraints
        )

        guard let document = try? decodeDocument(from: file.data) else {
            return EduAgentWorkspaceSnapshot(
                course: course,
                nodes: [],
                connections: [],
                slides: slides.map { slideSnapshot(from: $0) },
                lessonPlanMarkdown: lessonPlanMarkdown
            )
        }

        let stateByID = Dictionary(uniqueKeysWithValues: document.canvasState.map { ($0.nodeID, $0) })
        let titleByID = Dictionary(uniqueKeysWithValues: document.nodes.map { node in
            let customName = stateByID[node.id]?.customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let resolved = customName.isEmpty ? node.attributes.name : customName
            return (node.id, resolved)
        })

        let incomingByNode = Dictionary(grouping: document.connections, by: \.targetNodeID)
        let outgoingByNode = Dictionary(grouping: document.connections, by: \.sourceNodeID)

        let nodes: [EduAgentGraphNodeSnapshot] = document.nodes.map { serialized in
            let liveNode = try? deserializeNode(serialized)
            let textValue = (liveNode as? any NodeTextEditable)?.editorTextValue ?? serialized.nodeData["content"] ?? serialized.nodeData["value"] ?? ""
            let selectedOption = (liveNode as? any NodeOptionSelectable)?.editorSelectedOption ?? serialized.nodeData["level"] ?? serialized.nodeData["toolkitType"] ?? ""
            let selectedMethodID = (liveNode as? any NodeMethodSelectable)?.editorSelectedMethodID ?? serialized.nodeData["toolkitMethodID"]
            let textFields = (liveNode as? any NodeFormEditable)?.editorFormTextFields.map {
                EduAgentNodeFieldSnapshot(id: $0.id, label: $0.label, value: $0.value)
            } ?? []
            let optionFields = (liveNode as? any NodeFormEditable)?.editorFormOptionFields.map {
                EduAgentNodeFieldSnapshot(id: $0.id, label: $0.label, value: $0.selectedOption)
            } ?? []

            let incoming = incomingByNode[serialized.id] ?? []
            let outgoing = outgoingByNode[serialized.id] ?? []
            let state = stateByID[serialized.id]

            return EduAgentGraphNodeSnapshot(
                id: serialized.id.uuidString,
                nodeType: serialized.nodeType,
                nodeFamily: nodeFamily(for: serialized.nodeType),
                title: titleByID[serialized.id] ?? serialized.attributes.name,
                textValue: textValue,
                selectedOption: selectedOption,
                selectedMethodID: selectedMethodID,
                positionX: state?.positionX ?? 0,
                positionY: state?.positionY ?? 0,
                incomingNodeIDs: incoming.map { $0.sourceNodeID.uuidString },
                outgoingNodeIDs: outgoing.map { $0.targetNodeID.uuidString },
                incomingTitles: incoming.compactMap { titleByID[$0.sourceNodeID] },
                outgoingTitles: outgoing.compactMap { titleByID[$0.targetNodeID] },
                textFields: textFields,
                optionFields: optionFields
            )
        }

        let inputPortNameByID = Dictionary(uniqueKeysWithValues: document.nodes.flatMap { node in
            node.inputPorts.map { ($0.id, $0.name) }
        })
        let outputPortNameByID = Dictionary(uniqueKeysWithValues: document.nodes.flatMap { node in
            node.outputPorts.map { ($0.id, $0.name) }
        })

        let connections: [EduAgentGraphConnectionSnapshot] = document.connections.map { connection in
            EduAgentGraphConnectionSnapshot(
                sourceNodeID: connection.sourceNodeID.uuidString,
                sourcePortName: outputPortNameByID[connection.sourcePortID] ?? "",
                targetNodeID: connection.targetNodeID.uuidString,
                targetPortName: inputPortNameByID[connection.targetPortID] ?? "",
                dataType: connection.dataType
            )
        }

        return EduAgentWorkspaceSnapshot(
            course: course,
            nodes: nodes.sorted { lhs, rhs in
                if lhs.positionX == rhs.positionX {
                    return lhs.positionY < rhs.positionY
                }
                return lhs.positionX < rhs.positionX
            },
            connections: connections,
            slides: slides.map { slideSnapshot(from: $0) },
            lessonPlanMarkdown: lessonPlanMarkdown
        )
    }

    static func canvasSchema() -> EduAgentCanvasSchemaSnapshot {
        let knowledgeNode = supportedKnowledgeNode()
        let evaluationNode = supportedEvaluationNode()
        let toolkitNodes = [
            supportedToolkitNode(type: EduNodeType.toolkitPerceptionInquiry, category: .perceptionInquiry),
            supportedToolkitNode(type: EduNodeType.toolkitConstructionPrototype, category: .constructionPrototype),
            supportedToolkitNode(type: EduNodeType.toolkitCommunicationNegotiation, category: .communicationNegotiation),
            supportedToolkitNode(type: EduNodeType.toolkitRegulationMetacognition, category: .regulationMetacognition)
        ]

        return EduAgentCanvasSchemaSnapshot(nodes: [knowledgeNode] + toolkitNodes + [evaluationNode])
    }

    static func encodedJSONString<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }

    private static func supportedKnowledgeNode() -> EduAgentSupportedCanvasNodeSnapshot {
        let node = EduKnowledgeNode(name: "Knowledge")
        return EduAgentSupportedCanvasNodeSnapshot(
            nodeType: EduNodeType.knowledge,
            title: titleForCanvasNodeType(EduNodeType.knowledge),
            methods: [],
            directTextEditable: true,
            directSelectableOptions: node.editorOptions
        )
    }

    private static func supportedEvaluationNode() -> EduAgentSupportedCanvasNodeSnapshot {
        let node = EduEvaluationNode(name: "Evaluation")
        let method = EduAgentSupportedCanvasMethodSnapshot(
            methodID: "evaluation",
            title: titleForCanvasNodeType(EduNodeType.evaluation),
            textFields: node.editorFormTextFields.map {
                EduAgentNodeFieldSnapshot(id: $0.id, label: $0.label, value: $0.placeholder)
            },
            optionFields: node.editorFormOptionFields.map {
                EduAgentNodeFieldSnapshot(id: $0.id, label: $0.label, value: $0.options.joined(separator: " | "))
            }
        )
        return EduAgentSupportedCanvasNodeSnapshot(
            nodeType: EduNodeType.evaluation,
            title: titleForCanvasNodeType(EduNodeType.evaluation),
            methods: [method],
            directTextEditable: false,
            directSelectableOptions: []
        )
    }

    private static func supportedToolkitNode(
        type: String,
        category: EduToolkitCategory
    ) -> EduAgentSupportedCanvasNodeSnapshot {
        let methods: [EduAgentSupportedCanvasMethodSnapshot] = category.methods.map { method in
            let node = EduToolkitNode(
                name: titleForCanvasNodeType(type),
                category: category,
                selectedMethodID: method.id
            )
            return EduAgentSupportedCanvasMethodSnapshot(
                methodID: method.id,
                title: category.localizedMethodTitle(for: method.id),
                textFields: node.editorFormTextFields.map {
                    EduAgentNodeFieldSnapshot(id: $0.id, label: $0.label, value: $0.placeholder)
                },
                optionFields: node.editorFormOptionFields.map {
                    EduAgentNodeFieldSnapshot(id: $0.id, label: $0.label, value: $0.options.joined(separator: " | "))
                }
            )
        }

        return EduAgentSupportedCanvasNodeSnapshot(
            nodeType: type,
            title: titleForCanvasNodeType(type),
            methods: methods,
            directTextEditable: true,
            directSelectableOptions: category.localizedMethodOptions
        )
    }

    private static func slideSnapshot(from slide: EduPresentationComposedSlide) -> EduAgentSlideSnapshot {
        EduAgentSlideSnapshot(
            slideID: slide.id.uuidString,
            title: slide.title,
            subtitle: slide.subtitle,
            knowledgeItems: slide.knowledgeItems,
            toolkitItems: slide.toolkitItems,
            keyPoints: slide.keyPoints,
            speakerNotes: slide.speakerNotes
        )
    }

    private static func nodeFamily(for nodeType: String) -> String {
        if nodeType == EduNodeType.knowledge {
            return "knowledge"
        }
        if nodeType == EduNodeType.evaluation {
            return "evaluation"
        }
        if EduNodeType.allToolkitTypes.contains(nodeType) {
            return "toolkit"
        }
        return "other"
    }

    private static func titleForCanvasNodeType(_ nodeType: String) -> String {
        switch nodeType {
        case EduNodeType.knowledge:
            return "Knowledge"
        case EduNodeType.evaluation:
            return "Evaluation"
        case EduNodeType.toolkitPerceptionInquiry:
            return "Toolkit · Inquiry"
        case EduNodeType.toolkitConstructionPrototype:
            return "Toolkit · Construction"
        case EduNodeType.toolkitCommunicationNegotiation:
            return "Toolkit · Negotiation"
        case EduNodeType.toolkitRegulationMetacognition:
            return "Toolkit · Metacognition"
        default:
            return nodeType
        }
    }
}

enum EduAgentPromptBuilder {
    static func workspacePlanningMessages(
        settings: EduAgentProviderSettings,
        file: GNodeWorkspaceFile,
        conversation: [EduAgentConversationMessage],
        userRequest: String,
        supplementaryMaterial: String
    ) -> [EduLLMMessage] {
        let snapshot = EduAgentContextBuilder.workspaceSnapshot(file: file)
        let schema = EduAgentContextBuilder.canvasSchema()
        return [
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
                \(EduAgentContextBuilder.encodedJSONString(snapshot))

                Workspace quick facts:
                \(workspaceQuickFacts(snapshot))

                Supported canvas schema JSON:
                \(EduAgentContextBuilder.encodedJSONString(schema))

                Supplementary material:
                \(normalizedSupplementaryMaterial(supplementaryMaterial))
                """
            )
        ] + conversationMessages(conversation) + [
            .init(role: "user", content: userRequest)
        ]
    }

    static func workspaceAutoMessages(
        settings: EduAgentProviderSettings,
        file: GNodeWorkspaceFile,
        conversation: [EduAgentConversationMessage],
        userRequest: String,
        supplementaryMaterial: String,
        thinkingEnabled: Bool,
        thinkingPlan: EduAgentThinkingPlanResponse? = nil
    ) -> [EduLLMMessage] {
        let snapshot = EduAgentContextBuilder.workspaceSnapshot(file: file)
        let schema = EduAgentContextBuilder.canvasSchema()
        let thinkingFieldRule = thinkingEnabled
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
                \(EduAgentContextBuilder.encodedJSONString(snapshot))

                Workspace quick facts:
                \(workspaceQuickFacts(snapshot))

                Supported canvas schema JSON:
                \(EduAgentContextBuilder.encodedJSONString(schema))

                Thinking mode:
                \(thinkingEnabled ? "enabled" : "disabled")

                Planning artifact:
                \(normalizedPlanningArtifact(thinkingPlan))

                Supplementary material:
                \(normalizedSupplementaryMaterial(supplementaryMaterial))
                """
            )
        ] + conversationMessages(conversation) + [
            .init(role: "user", content: userRequest)
        ]
    }

    static func lessonPlanRevisionMessages(
        settings: EduAgentProviderSettings,
        file: GNodeWorkspaceFile,
        lessonPlanMarkdown: String,
        conversation: [EduAgentConversationMessage],
        userRequest: String,
        supplementaryMaterial: String,
        referenceDocument: EduLessonReferenceDocument? = nil
    ) -> [EduLLMMessage] {
        let snapshot = EduAgentContextBuilder.workspaceSnapshot(
            file: file,
            lessonPlanMarkdown: lessonPlanMarkdown
        )
        let referenceSource = referenceDocument?.sourceName ?? "(none)"
        let referenceSchema = referenceDocument.map {
            EduAgentContextBuilder.encodedJSONString($0.templateDocument.schema)
        } ?? "(none)"
        let referenceStyleProfile = referenceDocument.map {
            EduAgentContextBuilder.encodedJSONString($0.styleProfile)
        } ?? "(none)"
        let referenceSectionOrder = referenceDocument?.templateDocument.schema.outlineText ?? "(none)"
        let referenceFrontMatter = referenceDocument.map {
            EduAgentContextBuilder.encodedJSONString($0.templateDocument.schema.frontMatterFieldLabels)
        } ?? "(none)"
        let referenceProcessColumns = referenceDocument.map {
            EduAgentContextBuilder.encodedJSONString($0.templateDocument.schema.teachingProcessColumnTitles)
        } ?? "(none)"
        let referenceSectionExemplars = referenceDocument.map {
            EduAgentContextBuilder.encodedJSONString($0.styleProfile.sectionExemplars)
        } ?? "(none)"
        let referenceChecklist = referenceDocument?.complianceChecklistText ?? "(none)"
        let referenceExcerpt = referenceDocument?.markdownExcerptForPrompt ?? "(none)"
        return [
            .init(
                role: "system",
                content: mergedSystemPrompt(
                    base: """
                    You revise a teacher-facing lesson plan grounded in a pedagogical graph.
                    Preserve the graph's sequence and teacher control.
                    Use a silent plan-and-solve workflow internally: inspect the user's requested change, map the affected template slots, revise only those slots coherently, and then run a final structural check before returning the draft.
                    If a reference lesson-plan document is provided, preserve its exact section titles, section order, field expectations, and wording register while still honoring the live graph.
                    Use the section exemplar with the same title to preserve the reference's rhetorical opening, paragraph density, and register without copying institution-specific facts.
                    Do not paraphrase template section titles.
                    Do not drop template sections.
                    Do not introduce substitute top-level headings when a reference section list is provided.
                    If the template expects a front-matter field block or a teaching-process table, preserve that structure in the revised result.
                    If the template expects internal labels such as 已有知识 / 未有知识 or numbered subparts, preserve those labels explicitly.
                    If the template continues with supplementary sections such as 作业, Handout, or 教学原文 after the teaching process, preserve those trailing sections during revision.
                    Improve clarity, pacing, alignment, differentiation, and implementability.
                    Before finalizing, silently verify that the template section sequence remains intact.
                    Do not wrap JSON in markdown fences.
                    Output strict JSON only:
                    {
                      "assistant_reply": "brief summary of what changed",
                      "revised_markdown": "full revised markdown lesson plan"
                    }
                    """,
                    settings: settings
                )
            ),
            .init(
                role: "user",
                content: """
                Workspace snapshot JSON:
                \(EduAgentContextBuilder.encodedJSONString(snapshot))

                Reference lesson-plan source:
                \(referenceSource)

                Reference lesson-plan schema JSON:
                \(referenceSchema)

                Reference exact section order:
                \(referenceSectionOrder)

                Reference front-matter field labels JSON:
                \(referenceFrontMatter)

                Reference teaching-process column titles JSON:
                \(referenceProcessColumns)

                Reference lesson-plan style profile JSON:
                \(referenceStyleProfile)

                Reference section exemplars JSON:
                \(referenceSectionExemplars)

                Reference compliance checklist:
                \(referenceChecklist)

                Reference lesson-plan markdown excerpt:
                \(referenceExcerpt)

                Supplementary material:
                \(normalizedSupplementaryMaterial(supplementaryMaterial))
                """
            )
        ] + conversationMessages(conversation) + [
            .init(role: "user", content: userRequest)
        ]
    }

    static func presentationRevisionMessages(
        settings: EduAgentProviderSettings,
        file: GNodeWorkspaceFile,
        slides: [EduPresentationComposedSlide],
        conversation: [EduAgentConversationMessage],
        userRequest: String,
        supplementaryMaterial: String
    ) -> [EduLLMMessage] {
        let snapshot = EduAgentContextBuilder.workspaceSnapshot(
            file: file,
            slides: slides
        )
        return [
            .init(
                role: "system",
                content: mergedSystemPrompt(
                    base: """
                    You revise slide copy for a classroom presentation generated from a pedagogical graph.
                    Keep slide order and slide ids unchanged.
                    Adapt wording, progression, questioning prompts, and audience fit without breaking the pedagogical sequence.
                    Do not wrap JSON in markdown fences.
                    Output strict JSON only:
                    {
                      "assistant_reply": "brief summary",
                      "slide_overrides": [
                        {
                          "slide_id": "UUID",
                          "title": "optional",
                          "subtitle": "optional",
                          "main_content": "optional",
                          "toolkit_content": "optional"
                        }
                      ]
                    }
                    Only return overrides for slides that truly need changes.
                    """,
                    settings: settings
                )
            ),
            .init(
                role: "user",
                content: """
                Workspace snapshot JSON:
                \(EduAgentContextBuilder.encodedJSONString(snapshot))

                Supplementary material:
                \(normalizedSupplementaryMaterial(supplementaryMaterial))
                """
            )
        ] + conversationMessages(conversation) + [
            .init(role: "user", content: userRequest)
        ]
    }

    static func workspaceSuggestedPromptMessages(
        settings: EduAgentProviderSettings,
        file: GNodeWorkspaceFile,
        supplementaryMaterial: String
    ) -> [EduLLMMessage] {
        let snapshot = EduAgentContextBuilder.workspaceSnapshot(file: file)
        return [
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
                    - Use the user's UI language when it is inferable from the workspace or supplementary material; otherwise default to English.
                    """,
                    settings: settings
                )
            ),
            .init(
                role: "user",
                content: """
                Workspace snapshot JSON:
                \(EduAgentContextBuilder.encodedJSONString(snapshot))

                Workspace quick facts:
                \(workspaceQuickFacts(snapshot))

                Supplementary material:
                \(normalizedSupplementaryMaterial(supplementaryMaterial))
                """
            )
        ]
    }

    private static func mergedSystemPrompt(
        base: String,
        settings: EduAgentProviderSettings
    ) -> String {
        let extra = settings.additionalSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !extra.isEmpty else { return base }
        return base + "\n\nAdditional provider-specific guidance:\n" + extra
    }

    private static func conversationMessages(_ conversation: [EduAgentConversationMessage]) -> [EduLLMMessage] {
        conversation.suffix(12).map {
            EduLLMMessage(role: $0.role.rawValue, content: $0.content)
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

    private static func workspaceQuickFacts(_ snapshot: EduAgentWorkspaceSnapshot) -> String {
        let isChinese = Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
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
}
