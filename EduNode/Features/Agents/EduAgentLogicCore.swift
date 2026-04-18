import Foundation

struct EduCanvasRecommendation: Identifiable, Hashable {
    let id: String
    let title: String
    let rationale: String
    let suggestedPrompt: String
}

struct EduLessonMissingInfoItem: Identifiable, Hashable, Codable {
    enum Priority: String, Codable, Hashable {
        case core
        case supportive
    }

    enum AutofillPolicy: String, Codable, Hashable {
        case none
        case seed
        case resolvedDraft
    }

    let id: String
    let sectionKind: EduLessonTemplateSectionKind
    let sectionTitle: String
    let title: String
    let question: String
    let placeholder: String
    let suggestedAnswer: String
    let priority: Priority
    let autofillPolicy: AutofillPolicy

    init(
        id: String,
        sectionKind: EduLessonTemplateSectionKind,
        sectionTitle: String,
        title: String,
        question: String,
        placeholder: String,
        suggestedAnswer: String,
        priority: Priority,
        autofillPolicy: AutofillPolicy = .none
    ) {
        self.id = id
        self.sectionKind = sectionKind
        self.sectionTitle = sectionTitle
        self.title = title
        self.question = question
        self.placeholder = placeholder
        self.suggestedAnswer = suggestedAnswer
        self.priority = priority
        self.autofillPolicy = autofillPolicy
    }
}

struct EduLessonGenerationReadiness: Hashable {
    let totalItems: Int
    let resolvedItems: Int
    let unresolvedItemIDs: [String]

    var isReady: Bool {
        unresolvedItemIDs.isEmpty
    }
}

struct EduAgentCourseContext: Hashable, Codable {
    let subject: String
    let goals: [String]
    let modelFocus: String
    let teachingStyle: String
    let formativeCheckIntensity: String
    let emphasizeInquiryExperiment: Bool
    let emphasizeExperienceReflection: Bool
    let requireStructuredFlow: Bool
    let studentCount: Int
    let studentPriorKnowledgeScore: Int
    let studentMotivationScore: Int
    let studentSupportNotes: String
    let resourceConstraints: String
    let lessonDurationMinutes: Int
}

struct EduAgentGraphFieldContext: Identifiable, Hashable, Codable {
    let id: String
    let label: String
    let value: String
}

struct EduAgentGraphNodeContext: Identifiable, Hashable, Codable {
    let id: String
    let nodeFamily: String
    let title: String
    let textValue: String
    let selectedOption: String
    let selectedMethodID: String?
    let incomingNodeIDs: [String]
    let outgoingNodeIDs: [String]
    let incomingTitles: [String]
    let outgoingTitles: [String]
    let textFields: [EduAgentGraphFieldContext]
    let optionFields: [EduAgentGraphFieldContext]
}

struct EduAgentGraphContext: Hashable, Codable {
    let nodes: [EduAgentGraphNodeContext]
    let totalConnections: Int

    var knowledgeNodes: [EduAgentGraphNodeContext] {
        nodes.filter { $0.nodeFamily == "knowledge" }
    }

    var toolkitNodes: [EduAgentGraphNodeContext] {
        nodes.filter { $0.nodeFamily == "toolkit" }
    }

    var evaluationNodes: [EduAgentGraphNodeContext] {
        nodes.filter { $0.nodeFamily == "evaluation" }
    }

    var knowledgeIDsLinkedToToolkit: Set<String> {
        var result = Set<String>()
        let familyByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.nodeFamily) })
        for node in nodes {
            let sourceFamily = familyByID[node.id] ?? ""
            for outgoingID in node.outgoingNodeIDs {
                let targetFamily = familyByID[outgoingID] ?? ""
                if sourceFamily == "knowledge" && targetFamily == "toolkit" {
                    result.insert(node.id)
                }
                if sourceFamily == "toolkit" && targetFamily == "knowledge" {
                    result.insert(outgoingID)
                }
            }
        }
        return result
    }

    var orphanKnowledgeNodes: [EduAgentGraphNodeContext] {
        knowledgeNodes.filter { !knowledgeIDsLinkedToToolkit.contains($0.id) }
    }

    var toolkitMethodIDs: [String] {
        toolkitNodes.compactMap(\.selectedMethodID)
    }

    var uniqueToolkitMethodIDs: Set<String> {
        Set(
            toolkitMethodIDs
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    var hasGraphFlow: Bool {
        !knowledgeIDsLinkedToToolkit.isEmpty && totalConnections > 0
    }
}

private struct EduCanvasRecommendationCandidate {
    let priority: Int
    let recommendation: EduCanvasRecommendation
}

enum EduCanvasRecommendationCoreEngine {
    static func recommendations(
        course: EduAgentCourseContext,
        graph: EduAgentGraphContext,
        isChinese: Bool,
        limit: Int = 3
    ) -> [EduCanvasRecommendation] {
        var candidates: [EduCanvasRecommendationCandidate] = []

        if graph.knowledgeNodes.isEmpty {
            candidates.append(
                .init(
                    priority: 100,
                    recommendation: EduCanvasRecommendation(
                        id: "knowledge-skeleton",
                        title: isChinese ? "先搭知识骨架" : "Start with a knowledge backbone",
                        rationale: isChinese
                            ? "当前画布还没有可承载课程目标的 Knowledge 主线，先把目标拆成 3-4 个层次化知识节点最稳。"
                            : "The canvas has no Knowledge backbone yet. The most reliable next move is to break the goals into 3-4 layered knowledge nodes.",
                        suggestedPrompt: knowledgeBackbonePrompt(course: course, isChinese: isChinese)
                    )
                )
            )
        }

        if !graph.knowledgeNodes.isEmpty && graph.toolkitNodes.isEmpty {
            let descriptor = preferredToolkitDescriptor(course: course, isChinese: isChinese)
            candidates.append(
                .init(
                    priority: 92,
                    recommendation: EduCanvasRecommendation(
                        id: "first-toolkit-bridge",
                        title: isChinese ? "补第一段活动承接" : "Add the first activity bridge",
                        rationale: isChinese
                            ? "知识节点已经出现，但还没有活动层把内容转成可执行课堂过程。"
                            : "Knowledge nodes exist, but there is still no activity layer to turn content into classroom action.",
                        suggestedPrompt: toolkitBridgePrompt(
                            descriptor: descriptor,
                            graph: graph,
                            course: course,
                            isChinese: isChinese
                        )
                    )
                )
            )
        }

        if !graph.orphanKnowledgeNodes.isEmpty && !graph.toolkitNodes.isEmpty {
            candidates.append(
                .init(
                    priority: 84,
                    recommendation: EduCanvasRecommendation(
                        id: "connect-orphan-knowledge",
                        title: isChinese ? "补齐断开的知识承接" : "Bridge unconnected knowledge",
                        rationale: isChinese
                            ? "有些 Knowledge 节点还没有被 Toolkit 活动承接，学生难以从目标走到实施。"
                            : "Some Knowledge nodes still lack Toolkit activity bridges, so the path from goals to enactment is weak.",
                        suggestedPrompt: orphanKnowledgePrompt(
                            orphanNodes: graph.orphanKnowledgeNodes,
                            isChinese: isChinese
                        )
                    )
                )
            )
        }

        if shouldSuggestEvaluationAlignment(graph: graph) {
            candidates.append(
                .init(
                    priority: 80,
                    recommendation: EduCanvasRecommendation(
                        id: "evaluation-alignment",
                        title: isChinese ? "补评价闭环" : "Close the assessment loop",
                        rationale: isChinese
                            ? "当前还没有 Evaluation 节点，目标与活动缺少证据回路。"
                            : "There is no Evaluation node yet, so the current goals and activities still lack an evidence loop.",
                        suggestedPrompt: evaluationPrompt(
                            course: course,
                            graph: graph,
                            isChinese: isChinese
                        )
                    )
                )
            )
        }

        if needsMethodDiversification(course: course, graph: graph) {
            candidates.append(
                .init(
                    priority: 72,
                    recommendation: EduCanvasRecommendation(
                        id: "method-diversification",
                        title: isChinese ? "补第二种活动范式" : "Add a second activity mode",
                        rationale: isChinese
                            ? "当前活动形态偏单一，继续推进前最好补一个不同作用的 Toolkit，避免整课只有一种学习动作。"
                            : "The current activity pattern is too narrow. Add a second Toolkit role before expanding further so the lesson is not built on a single learning move.",
                        suggestedPrompt: methodDiversificationPrompt(course: course, graph: graph, isChinese: isChinese)
                    )
                )
            )
        }

        if needsScaffoldingBoost(course: course, graph: graph) {
            candidates.append(
                .init(
                    priority: 68,
                    recommendation: EduCanvasRecommendation(
                        id: "scaffolding-boost",
                        title: isChinese ? "加强低门槛支架" : "Strengthen scaffolding",
                        rationale: isChinese
                            ? "当前学生先备或支持需求显示需要更清晰的分层支架，建议补一段低门槛过渡。"
                            : "Current learner readiness suggests the lesson needs a clearer scaffolded ramp before the main task.",
                        suggestedPrompt: scaffoldingPrompt(course: course, isChinese: isChinese)
                    )
                )
            )
        }

        if needsStructureCleanup(course: course, graph: graph) {
            candidates.append(
                .init(
                    priority: 64,
                    recommendation: EduCanvasRecommendation(
                        id: "structure-cleanup",
                        title: isChinese ? "整理主线结构" : "Clarify the main flow",
                        rationale: isChinese
                            ? "当前节点和连线还没有形成清晰主线，先收束结构比继续加节点更重要。"
                            : "The current nodes and links do not yet read as a coherent main flow. Clarifying structure matters more than adding more nodes.",
                        suggestedPrompt: structurePrompt(isChinese: isChinese)
                    )
                )
            )
        }

        let sorted = candidates
            .sorted { lhs, rhs in
                if lhs.priority == rhs.priority {
                    return lhs.recommendation.id < rhs.recommendation.id
                }
                return lhs.priority > rhs.priority
            }
            .map(\.recommendation)

        var seen = Set<String>()
        let deduped = sorted.filter { recommendation in
            seen.insert(recommendation.id).inserted
        }
        return Array(deduped.prefix(limit))
    }

    private static func knowledgeBackbonePrompt(
        course: EduAgentCourseContext,
        isChinese: Bool
    ) -> String {
        let goals = course.goals
        let goalPreview = goals.prefix(3).joined(separator: isChinese ? "；" : "; ")
        let shouldStageForAccessibility = course.studentPriorKnowledgeScore < 60
            || !course.studentSupportNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if isChinese {
            return """
            请基于当前课程元数据与目标“\(goalPreview.isEmpty ? "当前课程目标" : goalPreview)”先补 3-4 个层次清晰的 Knowledge 节点，并只做最小必要连线。\(shouldStageForAccessibility ? "优先从低门槛、可进入的基础理解节点起步，再递进到更高阶的分析或迁移节点。" : "")不要重写整张图，也不要添加冗余 Toolkit。
            """
        }
        return """
        Based on the current course metadata and goals "\(goalPreview.isEmpty ? "current course goals" : goalPreview)", add 3-4 clearly layered Knowledge nodes with only the minimum necessary links. \(shouldStageForAccessibility ? "Start with lower-floor, easy-entry knowledge nodes before moving into more analytic or transfer-oriented ones. " : "")Do not rewrite the entire canvas or add extra Toolkit nodes yet.
        """
    }

    private static func toolkitBridgePrompt(
        descriptor: String,
        graph: EduAgentGraphContext,
        course: EduAgentCourseContext,
        isChinese: Bool
    ) -> String {
        let anchorTitles = graph.knowledgeNodes.prefix(2).map(\.title).joined(separator: isChinese ? "、" : ", ")
        let learnerCue = learnerCue(course: course, isChinese: isChinese)
        if isChinese {
            return """
            请围绕现有 Knowledge 主线（优先参考：\(anchorTitles.isEmpty ? "当前知识节点" : anchorTitles)）补 1-2 个\(descriptor)，并自动连到最相关的 Knowledge 节点。请优先照顾\(learnerCue)的实施可行性。
            """
        }
        return """
        Add 1-2 \(descriptor) around the current Knowledge backbone (prioritize: \(anchorTitles.isEmpty ? "the current knowledge nodes" : anchorTitles)) and connect them to the most relevant Knowledge nodes. Prioritize feasibility for \(learnerCue).
        """
    }

    private static func orphanKnowledgePrompt(
        orphanNodes: [EduAgentGraphNodeContext],
        isChinese: Bool
    ) -> String {
        let titles = orphanNodes.prefix(3).map(\.title).joined(separator: isChinese ? "、" : ", ")
        if isChinese {
            return """
            请检查这些还没有活动承接的 Knowledge 节点：\(titles)。只做最小必要修改，为每个关键缺口补 1 个合适的 Toolkit 或补上必要连线，并保持整体结构简洁。
            """
        }
        return """
        Inspect these Knowledge nodes that still lack an activity bridge: \(titles). Make only the minimum necessary edits by adding an appropriate Toolkit or the needed links while keeping the overall structure compact.
        """
    }

    private static func evaluationPrompt(
        course: EduAgentCourseContext,
        graph: EduAgentGraphContext,
        isChinese: Bool
    ) -> String {
        let goalPreview = course.goals.prefix(2).joined(separator: isChinese ? "；" : "; ")
        let activityAnchor = graph.toolkitNodes.prefix(2).map(\.title).joined(separator: isChinese ? "、" : ", ")
        let intensity = formativeCheckLabel(course.formativeCheckIntensity, isChinese: isChinese)
        if isChinese {
            return """
            请基于当前目标“\(goalPreview.isEmpty ? "当前课程目标" : goalPreview)”与活动链（优先参考：\(activityAnchor.isEmpty ? "当前 Toolkit 节点" : activityAnchor)）补 1 个 Evaluation 节点，给出 3 条可观察指标，并让检查强度保持在\(intensity)。
            """
        }
        return """
        Add one Evaluation node grounded in the current goals "\(goalPreview.isEmpty ? "current course goals" : goalPreview)" and activity chain (prioritize: \(activityAnchor.isEmpty ? "the current Toolkit nodes" : activityAnchor)). Include three observable indicators and keep the check intensity at \(intensity).
        """
    }

    private static func methodDiversificationPrompt(
        course: EduAgentCourseContext,
        graph: EduAgentGraphContext,
        isChinese: Bool
    ) -> String {
        let currentRoles = uniqueToolkitRoleIDs(in: graph)
        let desiredMethod: String
        if !currentRoles.contains("regulation") && course.requireStructuredFlow {
            desiredMethod = isChinese ? "带有反思或调节作用的 Toolkit" : "a metacognitive or reflective Toolkit"
        } else if !currentRoles.contains("communication") {
            desiredMethod = isChinese ? "带有表达、协商或汇报作用的 Toolkit" : "a communication or reporting Toolkit"
        } else if !currentRoles.contains("construction") {
            desiredMethod = isChinese ? "带有建构或产出功能的 Toolkit" : "a construction-oriented Toolkit with a visible learner artifact"
        } else {
            desiredMethod = isChinese ? "功能不同于现有活动的第二类 Toolkit" : "a second Toolkit with a different role from the current one"
        }
        if isChinese {
            return "请不要继续堆同一种活动。围绕现有主线补 1 个\(desiredMethod)，让学生除了当前学习动作外，还能完成表达、协商、反思或迁移中的至少一种。"
        }
        return "Do not add more of the same activity pattern. Add \(desiredMethod) around the current flow so learners do more than the existing action pattern and also engage in communication, reflection, or transfer."
    }

    private static func scaffoldingPrompt(
        course: EduAgentCourseContext,
        isChinese: Bool
    ) -> String {
        let learnerCue = learnerCue(course: course, isChinese: isChinese)
        if isChinese {
            return """
            请检查当前画布是否对\(learnerCue)提供了足够支架；如果不足，请只补最小必要的 Knowledge/Toolkit 过渡节点与连线，帮助学生从低门槛进入主任务。
            """
        }
        return """
        Check whether the current canvas provides enough support for \(learnerCue). If not, add only the minimum necessary Knowledge or Toolkit bridge nodes and links so learners can enter the main task with less friction.
        """
    }

    private static func structurePrompt(isChinese: Bool) -> String {
        if isChinese {
            return "请不要继续堆节点，先把当前画布整理成更清晰的有向主线：必要时移动节点、补关键连线、删除冗余连线，并保持结构可读。"
        }
        return "Do not add more nodes yet. First turn the current canvas into a clearer directed flow by moving nodes, adding key links, and removing redundant links where needed."
    }

    private static func preferredToolkitDescriptor(
        course: EduAgentCourseContext,
        isChinese: Bool
    ) -> String {
        switch course.teachingStyle {
        case "inquiryDriven":
            return isChinese ? "探究取向的 Toolkit" : "an inquiry-oriented Toolkit"
        case "experientialReflective":
            return isChinese ? "体验-反思取向的 Toolkit" : "an experience-reflection Toolkit"
        case "taskDriven":
            return isChinese ? "任务推进型 Toolkit" : "a task-driven Toolkit"
        case "lectureDriven":
            return isChinese ? "讲授后承接练习的 Toolkit" : "a post-explanation practice Toolkit"
        default:
            if course.emphasizeInquiryExperiment {
                return isChinese ? "证据驱动的 Toolkit" : "an evidence-building Toolkit"
            }
            if course.emphasizeExperienceReflection {
                return isChinese ? "反思调节型 Toolkit" : "a reflective Toolkit"
            }
            return isChinese ? "活动承接 Toolkit" : "an activity-bridge Toolkit"
        }
    }

    private static func learnerCue(
        course: EduAgentCourseContext,
        isChinese: Bool
    ) -> String {
        if course.studentPriorKnowledgeScore < 60 {
            return isChinese ? "先备较弱的学生" : "learners with weaker prior knowledge"
        }
        if !course.studentSupportNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return isChinese ? "存在额外支持需求的学生" : "learners who need additional support"
        }
        return isChinese ? "当前学生群体" : "the current learner group"
    }

    private static func formativeCheckLabel(
        _ raw: String,
        isChinese: Bool
    ) -> String {
        switch raw {
        case "low":
            return isChinese ? "低" : "low"
        case "high":
            return isChinese ? "高" : "high"
        default:
            return isChinese ? "中" : "medium"
        }
    }

    private static func needsMethodDiversification(
        course: EduAgentCourseContext,
        graph: EduAgentGraphContext
    ) -> Bool {
        let toolkitCount = graph.toolkitNodes.count
        guard toolkitCount > 0 else { return false }
        let roleCount = uniqueToolkitRoleIDs(in: graph).count

        if toolkitCount == 1 && graph.knowledgeNodes.count >= 3 {
            return true
        }

        if toolkitCount >= 2 && roleCount <= 1 && graph.knowledgeNodes.count >= 3 {
            return true
        }

        return toolkitCount == 1 && course.requireStructuredFlow && !graph.evaluationNodes.isEmpty
    }

    private static func needsScaffoldingBoost(
        course: EduAgentCourseContext,
        graph: EduAgentGraphContext
    ) -> Bool {
        let isTooEarlyToJudge = graph.toolkitNodes.isEmpty && graph.knowledgeNodes.count < 2
        if isTooEarlyToJudge {
            return false
        }

        let supportNotes = course.studentSupportNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowLevelKnowledgeCount = graph.knowledgeNodes.filter {
            let option = $0.selectedOption.lowercased()
            return option.contains("remember")
                || option.contains("understand")
                || option.contains("记忆")
                || option.contains("理解")
        }.count
        let accessibleEntryToolkitCount = graph.toolkitNodes.filter {
            isAccessibleEntryToolkitMethod($0.selectedMethodID)
        }.count
        let needsMoreAccessibleRamp = graph.knowledgeNodes.count >= 3 && lowLevelKnowledgeCount < 2
        if course.studentPriorKnowledgeScore < 60 {
            if accessibleEntryToolkitCount > 0 && lowLevelKnowledgeCount >= 2 {
                return false
            }
            return needsMoreAccessibleRamp || (graph.toolkitNodes.count < 2 && accessibleEntryToolkitCount == 0)
        }
        if !supportNotes.isEmpty {
            return accessibleEntryToolkitCount == 0 && (graph.toolkitNodes.count < 2 || lowLevelKnowledgeCount == 0)
        }
        return false
    }

    private static func shouldSuggestEvaluationAlignment(
        graph: EduAgentGraphContext
    ) -> Bool {
        guard graph.evaluationNodes.isEmpty else { return false }
        return !graph.toolkitNodes.isEmpty || graph.knowledgeNodes.count >= 2
    }

    private static func needsStructureCleanup(
        course: EduAgentCourseContext,
        graph: EduAgentGraphContext
    ) -> Bool {
        if graph.nodes.count < 3 {
            return false
        }
        if course.requireStructuredFlow {
            return graph.totalConnections < max(graph.nodes.count - 1, 2)
        }
        return graph.totalConnections < max(graph.nodes.count / 2, 2)
    }

    private static func uniqueToolkitRoleIDs(
        in graph: EduAgentGraphContext
    ) -> Set<String> {
        Set(graph.toolkitNodes.compactMap { toolkitRoleID(for: $0.selectedMethodID) })
    }

    private static func toolkitRoleID(
        for methodID: String?
    ) -> String? {
        let normalized = methodID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        guard !normalized.isEmpty else { return nil }

        switch normalized {
        case "context_hook", "field_observation", "guided_observation", "source_analysis", "sensor_probe", "immersive_simulation":
            return "perception"
        case "low_fidelity_prototype", "prototype_build", "physical_computing", "story_construction", "service_blueprint", "adaptive_learning_platform", "digital_artifact":
            return "construction"
        case "role_play", "structured_debate", "world_cafe", "game_mechanism", "pogil", "peer_negotiation", "communication":
            return "communication"
        case "kanban_monitoring", "reflection_protocol", "metacognitive_routine", "reflection_log", "metacognition", "regulation":
            return "regulation"
        default:
            return nil
        }
    }

    private static func isAccessibleEntryToolkitMethod(
        _ methodID: String?
    ) -> Bool {
        let normalized = methodID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        guard !normalized.isEmpty else { return false }
        return [
            "context_hook",
            "field_observation",
            "guided_observation",
            "source_analysis"
        ].contains(normalized)
    }
}

enum EduLessonMaterializationCoreAnalyzer {
    static func missingInfoItems(
        template: EduLessonTemplateDocument,
        course: EduAgentCourseContext,
        graph: EduAgentGraphContext,
        baselineMarkdown: String,
        isChinese: Bool
    ) -> [EduLessonMissingInfoItem] {
        let sectionKinds = Set(template.schema.sections.map(\.kind))
        let hasGoals = !course.goals.isEmpty
        let hasResources = !course.resourceConstraints.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let baselineHasLearnerProfile = baselineContainsLearnerProfile(baselineMarkdown)
        let baselineHasReflection = baselineContainsReflection(baselineMarkdown)
        let wantsTimedProcessTable = template.schema.styleNotes.contains(where: { $0.localizedCaseInsensitiveContains("time-annotated") })
        let wantsProcessIntent = template.schema.styleNotes.contains(where: { $0.localizedCaseInsensitiveContains("design intent") })
        let wantsProcessEvidence = template.schema.styleNotes.contains(where: { $0.localizedCaseInsensitiveContains("effect-evaluation") })

        var items: [EduLessonMissingInfoItem] = []

        func appendIfNeeded(
            kind: EduLessonTemplateSectionKind,
            title: String,
            question: String,
            placeholder: String,
            suggestedAnswer: String,
            priority: EduLessonMissingInfoItem.Priority,
            autofillPolicy: EduLessonMissingInfoItem.AutofillPolicy = .none,
            condition: Bool = true
        ) {
            guard condition else { return }
            guard let section = template.schema.sections.first(where: { $0.kind == kind }) else { return }
            items.append(
                EduLessonMissingInfoItem(
                    id: "\(kind.rawValue)-followup",
                    sectionKind: kind,
                    sectionTitle: section.title,
                    title: title,
                    question: question,
                    placeholder: placeholder,
                    suggestedAnswer: suggestedAnswer,
                    priority: priority,
                    autofillPolicy: autofillPolicy
                )
            )
        }

        appendIfNeeded(
            kind: .designRationale,
            title: isChinese ? "补设计理念" : "Add the design rationale",
            question: isChinese
                ? "这个教案模板要求写设计理念。请补充本课的总体 pedagogical rationale，例如目标导向、活动组织逻辑与评价如何一体化。"
                : "This template expects a design rationale. Add the overall pedagogical rationale, including how goals, activities, and assessment are aligned.",
            placeholder: isChinese
                ? "例如：以……为主线，通过……活动推进理解，并以……证据检验目标达成。"
                : "For example: organize the lesson around..., move learning through..., and check attainment with...",
            suggestedAnswer: designRationaleSuggestion(course: course, isChinese: isChinese),
            priority: .core,
            autofillPolicy: .resolvedDraft,
            condition: sectionKinds.contains(.designRationale)
        )

        let hasDetailedTextAnalysis = sectionKinds.contains(.textAnalysisWhat)
            || sectionKinds.contains(.textAnalysisWhy)
            || sectionKinds.contains(.textAnalysisHow)
        if sectionKinds.contains(.textAnalysis) && !hasDetailedTextAnalysis {
            appendIfNeeded(
                kind: .textAnalysis,
                title: isChinese ? "补材料分析" : "Add the material analysis",
                question: isChinese
                    ? "模板需要“文本/材料分析”。请概括材料讲了什么、为什么值得学，以及它在结构或语言上有什么教学价值。"
                    : "The template needs a text/material analysis. Summarize what the material is about, why it matters, and what structural or language features matter instructionally.",
                placeholder: isChinese ? "可按“what / why / how”组织。" : "You can structure it as what / why / how.",
                suggestedAnswer: compositeTextAnalysisSuggestion(course: course, graph: graph, isChinese: isChinese),
                priority: .core,
                autofillPolicy: .seed,
                condition: true
            )
        } else {
            appendIfNeeded(
                kind: .textAnalysisWhat,
                title: isChinese ? "补 what 分析" : "Add the what analysis",
                question: isChinese
                    ? "请补充材料/文本的 what 分析：主要内容是什么，学生需要把握哪些核心信息或概念？"
                    : "Add the what analysis: what is the material about, and what core ideas or information should students grasp?",
                placeholder: isChinese ? "概括主要内容与关键信息。" : "Summarize the main content and key information.",
                suggestedAnswer: textAnalysisWhatSuggestion(graph: graph, isChinese: isChinese),
                priority: .core,
                autofillPolicy: .seed,
                condition: sectionKinds.contains(.textAnalysisWhat)
            )
            appendIfNeeded(
                kind: .textAnalysisWhy,
                title: isChinese ? "补 why 分析" : "Add the why analysis",
                question: isChinese
                    ? "请补充材料/文本的 why 分析：为什么值得学，它承载什么主题意义、价值或 transfer 价值？"
                    : "Add the why analysis: why is this material worth learning, and what theme, value, or transfer potential does it carry?",
                placeholder: isChinese ? "说明学习价值与育人意义。" : "Explain the learning value and wider significance.",
                suggestedAnswer: textAnalysisWhySuggestion(course: course, graph: graph, isChinese: isChinese),
                priority: .core,
                autofillPolicy: .seed,
                condition: sectionKinds.contains(.textAnalysisWhy)
            )
            appendIfNeeded(
                kind: .textAnalysisHow,
                title: isChinese ? "补 how 分析" : "Add the how analysis",
                question: isChinese
                    ? "请补充材料/文本的 how 分析：体裁、结构、语言或表现方式上有哪些对教学设计关键的特征？"
                    : "Add the how analysis: what genre, structure, language, or representational features are instructionally important?",
                placeholder: isChinese ? "例如：叙事结构、论证逻辑、关键词句、图文关系等。" : "For example: narrative structure, argument logic, key language, or multimodal features.",
                suggestedAnswer: textAnalysisHowSuggestion(graph: graph, isChinese: isChinese),
                priority: .core,
                autofillPolicy: .seed,
                condition: sectionKinds.contains(.textAnalysisHow)
            )
        }

        appendIfNeeded(
            kind: .learnerAnalysis,
            title: isChinese ? "补学情分析" : "Add learner analysis",
            question: isChinese
                ? "请补充更具体的学情分析，尤其是学生已有基础、可能卡点与本课需要的支持方式。"
                : "Add a more specific learner analysis, especially students' prior strengths, likely sticking points, and the support this lesson needs.",
            placeholder: isChinese ? "描述已有基础、困难与支持方式。" : "Describe existing strengths, likely difficulties, and support moves.",
            suggestedAnswer: learnerAnalysisSuggestion(course: course, isChinese: isChinese),
            priority: .core,
            autofillPolicy: .resolvedDraft,
            condition: sectionKinds.contains(.learnerAnalysis) && !baselineHasLearnerProfile
        )

        appendIfNeeded(
            kind: .priorKnowledge,
            title: isChinese ? "补已有知识" : "Add prior knowledge",
            question: isChinese
                ? "模板要求写“已有知识”。请概括学生在进入本课前已经掌握了什么，哪些经验可直接调动。"
                : "The template asks for prior knowledge. Summarize what students already know before this lesson and what prior experiences can be activated.",
            placeholder: isChinese ? "例如：已学过的概念、技能、经验或表达方式。" : "For example: prior concepts, skills, experiences, or ways of expressing ideas.",
            suggestedAnswer: priorKnowledgeSuggestion(course: course, isChinese: isChinese),
            priority: .core,
            autofillPolicy: .resolvedDraft,
            condition: sectionKinds.contains(.priorKnowledge)
        )

        appendIfNeeded(
            kind: .missingKnowledge,
            title: isChinese ? "补欠缺知识" : "Add knowledge gaps",
            question: isChinese
                ? "模板要求写“未有知识/知识缺口”。请概括学生当前还欠缺什么，因此本课需要重点支架什么。"
                : "The template asks for knowledge gaps. Summarize what students still lack and therefore what this lesson needs to scaffold explicitly.",
            placeholder: isChinese ? "说明当前短板、误区或尚未形成的能力。" : "Describe the current gaps, misconceptions, or underdeveloped capabilities.",
            suggestedAnswer: learnerGapSuggestion(course: course, isChinese: isChinese),
            priority: .core,
            autofillPolicy: .resolvedDraft,
            condition: sectionKinds.contains(.missingKnowledge)
        )

        appendIfNeeded(
            kind: .learningObjectives,
            title: isChinese ? "补学习目标" : "Add learning objectives",
            question: isChinese
                ? "当前目标信息不足。请补充 2-3 条可观察、可评价的学习目标。"
                : "The current goal information is insufficient. Add 2-3 observable and assessable learning objectives.",
            placeholder: isChinese ? "用“学生能够……”表述。" : "Phrase them as what students will be able to do.",
            suggestedAnswer: "",
            priority: .core,
            condition: sectionKinds.contains(.learningObjectives) && !hasGoals
        )

        appendIfNeeded(
            kind: .keyDifficulties,
            title: isChinese ? "补重点与难点" : "Add key points and difficulties",
            question: isChinese
                ? "模板要求写教学重点和难点。请概括本课最关键的学习重点，以及学生最可能遇到的难点。"
                : "The template asks for key points and difficulties. Summarize the most important learning focus and the most likely learner difficulties.",
            placeholder: isChinese ? "可分别写重点与难点。" : "You can separate key points from difficulties.",
            suggestedAnswer: keyDifficultySuggestion(course: course, isChinese: isChinese),
            priority: .core,
            autofillPolicy: .resolvedDraft,
            condition: sectionKinds.contains(.keyDifficulties)
        )

        appendIfNeeded(
            kind: .teachingResources,
            title: isChinese ? "补教学资源" : "Add teaching resources",
            question: isChinese
                ? "模板需要列出教学资源。请补充本课真正会用到的资源、材料或设备。"
                : "The template expects teaching resources. Add the materials, tools, or equipment the lesson will actually use.",
            placeholder: isChinese ? "例如：PPT、讲义、实验材料、板书资源、多媒体设备等。" : "For example: slides, handouts, experiment materials, boardwork resources, or media devices.",
            suggestedAnswer: teachingResourcesSuggestion(course: course, graph: graph, isChinese: isChinese),
            priority: .supportive,
            autofillPolicy: hasResources ? .resolvedDraft : .seed,
            condition: sectionKinds.contains(.teachingResources)
        )

        let processNeedsDetails = sectionKinds.contains(.teachingProcess) && (
            !graph.hasGraphFlow
                || (wantsTimedProcessTable && !containsTimingMarkers(baselineMarkdown))
                || (wantsProcessIntent && !containsDesignIntentMarkers(baselineMarkdown))
                || (wantsProcessEvidence && !containsEvaluationEvidenceMarkers(baselineMarkdown) && graph.evaluationNodes.isEmpty)
        )

        appendIfNeeded(
            kind: .teachingProcess,
            title: isChinese ? "补教学流程关键信息" : "Add core process details",
            question: processQuestion(
                isChinese: isChinese,
                graphHasFlow: graph.hasGraphFlow,
                wantsTimedProcessTable: wantsTimedProcessTable,
                wantsProcessIntent: wantsProcessIntent,
                wantsProcessEvidence: wantsProcessEvidence
            ),
            placeholder: isChinese ? "例如：导入 5 分钟，小组探究 10 分钟，汇报 8 分钟，并说明每一步的设计意图或评价证据。" : "For example: lead-in 5 minutes, group inquiry 10 minutes, reporting 8 minutes, plus design intent or evaluation evidence when needed.",
            suggestedAnswer: graph.hasGraphFlow
                ? teachingProcessSuggestion(course: course, graph: graph, isChinese: isChinese)
                : "",
            priority: graph.hasGraphFlow ? .supportive : .core,
            autofillPolicy: graph.hasGraphFlow ? .seed : .none,
            condition: processNeedsDetails
        )

        appendIfNeeded(
            kind: .reflection,
            title: isChinese ? "补反思" : "Add reflection",
            question: isChinese
                ? "模板需要写反思。请补充你希望在教案中预留的 reflection 方向，例如课堂风险、即时调整点或课后改进点。"
                : "The template asks for reflection. Add the reflection direction you want to reserve in the lesson plan, such as class risks, in-the-moment adjustments, or post-lesson improvements.",
            placeholder: isChinese ? "写 1-3 条即可。" : "1-3 concise points are enough.",
            suggestedAnswer: reflectionSuggestion(course: course, graph: graph, isChinese: isChinese),
            priority: .supportive,
            autofillPolicy: .seed,
            condition: sectionKinds.contains(.reflection) && !baselineHasReflection
        )

        return items
    }

    static func readiness(
        items: [EduLessonMissingInfoItem],
        answersByID: [String: String],
        skippedItemIDs: Set<String>
    ) -> EduLessonGenerationReadiness {
        let resolvedItems = items.filter { item in
            skippedItemIDs.contains(item.id)
                || !(answersByID[item.id]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
        let unresolvedIDs = items.compactMap { item -> String? in
            if skippedItemIDs.contains(item.id) {
                return nil
            }
            let answer = answersByID[item.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return answer.isEmpty ? item.id : nil
        }
        return EduLessonGenerationReadiness(
            totalItems: items.count,
            resolvedItems: resolvedItems.count,
            unresolvedItemIDs: unresolvedIDs
        )
    }

    private static func designRationaleSuggestion(
        course: EduAgentCourseContext,
        isChinese: Bool
    ) -> String {
        let goalPreview = course.goals.prefix(2).joined(separator: isChinese ? "；" : "; ")
        let style = teachingStyleLabel(course.teachingStyle, isChinese: isChinese)
        if isChinese {
            return "本课以\(goalPreview.isEmpty ? "课程目标" : goalPreview)为主线，结合\(style)组织学习过程，并以\(course.modelFocus.isEmpty ? "可观察证据" : course.modelFocus)确保目标、活动与评价的对齐。"
        }
        return "This lesson is organized around \(goalPreview.isEmpty ? "the course goals" : goalPreview), uses a \(style) teaching flow, and keeps goals, activities, and assessment aligned through \(course.modelFocus.isEmpty ? "observable evidence" : course.modelFocus)."
    }

    private static func learnerAnalysisSuggestion(
        course: EduAgentCourseContext,
        isChinese: Bool
    ) -> String {
        let supportNotes = course.studentSupportNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if isChinese {
            return "本课面向\(course.studentCount)名学生，当前先备水平约为\(course.studentPriorKnowledgeScore)%、任务完成度约为\(course.studentMotivationScore)%\(supportNotes.isEmpty ? "" : "，需特别关注：\(supportNotes)")。因此课堂需要在活动推进中提供明确提示、示例与即时反馈。"
        }
        return "The lesson serves \(course.studentCount) learners, with prior readiness around \(course.studentPriorKnowledgeScore)% and task completion around \(course.studentMotivationScore)%\(supportNotes.isEmpty ? "" : ", with additional support needed in: \(supportNotes)"). The lesson should therefore provide clear prompts, examples, and timely feedback."
    }

    private static func priorKnowledgeSuggestion(
        course: EduAgentCourseContext,
        isChinese: Bool
    ) -> String {
        if course.studentPriorKnowledgeScore >= 70 {
            return isChinese
                ? "学生已经具备与本课主题相关的基础经验，并能在教师提示下调用已有概念或表达方式完成初步判断。"
                : "Students already possess baseline experiences related to this topic and can draw on prior concepts or language with teacher prompting."
        }
        return isChinese
            ? "学生对相关主题并非完全陌生，但已有知识仍较零散，需要借助教师提示与示例才能稳定调用。"
            : "Students are not entirely unfamiliar with the topic, but their prior knowledge is still fragmented and needs teacher prompts or examples to be activated consistently."
    }

    private static func learnerGapSuggestion(
        course: EduAgentCourseContext,
        isChinese: Bool
    ) -> String {
        let supportNotes = course.studentSupportNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if isChinese {
            return supportNotes.isEmpty
                ? "学生目前更缺少把已有知识迁移到新情境中的能力，因此需要更明确的分析支架与过程性反馈。"
                : "学生当前仍存在这些关键缺口：\(supportNotes)。因此需要在课堂中补充明确支架。"
        }
        return supportNotes.isEmpty
            ? "Students still need help transferring prior knowledge into a new context, so the lesson should provide clearer analytic scaffolds and process feedback."
            : "Students still show these key gaps: \(supportNotes). The lesson should therefore add explicit scaffolds."
    }

    private static func keyDifficultySuggestion(
        course: EduAgentCourseContext,
        isChinese: Bool
    ) -> String {
        let goalLead = course.goals.first ?? (isChinese ? "目标理解与表达" : "goal comprehension and expression")
        let style = teachingStyleLabel(course.teachingStyle, isChinese: isChinese)
        if isChinese {
            return "教学重点：围绕“\(goalLead)”组织核心活动并确保学生形成可观察产出。教学难点：在\(style)情境下，引导学生把理解转化为更完整的表达、应用或证据。"
        }
        return "Key point: organize the core learning around \"\(goalLead)\" and ensure students produce observable evidence. Difficulty: help students convert understanding into fuller expression, application, or evidence within a \(style) flow."
    }

    private static func compositeTextAnalysisSuggestion(
        course: EduAgentCourseContext,
        graph: EduAgentGraphContext,
        isChinese: Bool
    ) -> String {
        [textAnalysisWhatSuggestion(graph: graph, isChinese: isChinese),
         textAnalysisWhySuggestion(course: course, graph: graph, isChinese: isChinese),
         textAnalysisHowSuggestion(graph: graph, isChinese: isChinese)]
            .filter { !$0.isEmpty }
            .joined(separator: isChinese ? "\n" : "\n")
    }

    private static func textAnalysisWhatSuggestion(
        graph: EduAgentGraphContext,
        isChinese: Bool
    ) -> String {
        let titles = graph.knowledgeNodes
            .map(\.title)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let titlePreview = titles.prefix(3).joined(separator: isChinese ? "、" : ", ")
        let detailPreview = graph.knowledgeNodes
            .map(\.textValue)
            .map { compactSentence($0, limit: 56) }
            .first(where: { !$0.isEmpty })
        guard !titlePreview.isEmpty || !(detailPreview ?? "").isEmpty else { return "" }
        if isChinese {
            if let detailPreview, !detailPreview.isEmpty {
                return "材料主要围绕\(titlePreview.isEmpty ? "本课核心内容" : "“\(titlePreview)”")展开，学生需要把握其中的关键信息、概念关系与内容推进线索，尤其应关注：\(detailPreview)。"
            }
            return "材料主要围绕“\(titlePreview)”展开，学生需要把握其中的关键信息、核心概念与内容推进线索。"
        }
        if let detailPreview, !detailPreview.isEmpty {
            return "The material centers on \(titlePreview.isEmpty ? "the lesson's core content" : "\"\(titlePreview)\""), and students need to grasp its key information, conceptual relations, and content progression, especially \(detailPreview)."
        }
        return "The material centers on \"\(titlePreview)\", and students need to grasp its key information, core concepts, and progression of meaning."
    }

    private static func textAnalysisWhySuggestion(
        course: EduAgentCourseContext,
        graph: EduAgentGraphContext,
        isChinese: Bool
    ) -> String {
        let goalPreview = course.goals.prefix(2).joined(separator: isChinese ? "；" : "; ")
        guard !goalPreview.isEmpty || !graph.evaluationNodes.isEmpty else { return "" }
        if isChinese {
            return "这一材料值得学习，因为它不仅支撑学生完成“\(goalPreview.isEmpty ? "本课核心目标" : goalPreview)”等学习任务，还能帮助学生把内容理解迁移到表达、判断或应用之中。"
        }
        return "This material is worth studying because it supports learners in achieving \(goalPreview.isEmpty ? "the lesson's core goals" : "\"\(goalPreview)\"") while also helping them transfer understanding into expression, judgment, or application."
    }

    private static func textAnalysisHowSuggestion(
        graph: EduAgentGraphContext,
        isChinese: Bool
    ) -> String {
        let methodLabels = graph.toolkitNodes
            .compactMap(\.selectedMethodID)
            .map { readableMethodLabel($0, isChinese: isChinese) }
        let uniqueMethods = Array(NSOrderedSet(array: methodLabels)) as? [String] ?? []
        let methodPreview = uniqueMethods.prefix(3).joined(separator: isChinese ? "、" : ", ")
        guard !methodPreview.isEmpty else { return "" }
        if isChinese {
            return "从 how 来看，这一材料适合通过\(methodPreview)等方式组织学习，这说明其教学关键不只是内容本身，还包括结构展开、关键信息提取与表达支架的安排。"
        }
        return "From a how perspective, this material is well suited to \(methodPreview), which means its instructional value lies not only in the content itself but also in how structure, key information, and expression scaffolds can be organized."
    }

    private static func teachingResourcesSuggestion(
        course: EduAgentCourseContext,
        graph: EduAgentGraphContext,
        isChinese: Bool
    ) -> String {
        let explicit = course.resourceConstraints.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicit.isEmpty {
            return explicit
        }
        guard graph.hasGraphFlow else { return "" }
        if isChinese {
            return "节点图谱、教学讲义/worksheet、课堂展示材料，以及用于形成性评价的记录工具。"
        }
        return "The node graph, lesson handouts/worksheets, presentation materials, and lightweight tools for formative evidence capture."
    }

    private static func teachingProcessSuggestion(
        course: EduAgentCourseContext,
        graph: EduAgentGraphContext,
        isChinese: Bool
    ) -> String {
        let phases = inferredProcessPhases(graph: graph, isChinese: isChinese)
        let minutes = allocatedMinutes(total: max(course.lessonDurationMinutes, 30), bucketCount: phases.count)
        let rows = zip(phases, minutes).map { phase, minute in
            if isChinese {
                return "\(phase) \(minute)分钟"
            }
            return "\(phase) \(minute) min"
        }
        return rows.joined(separator: isChinese ? "；" : "; ")
    }

    private static func reflectionSuggestion(
        course: EduAgentCourseContext,
        graph: EduAgentGraphContext,
        isChinese: Bool
    ) -> String {
        var points: [String] = []
        if course.studentPriorKnowledgeScore < 65 {
            points.append(
                isChinese
                    ? "关注低先备学生是否真正进入任务，而不是停留在表层完成。"
                    : "Check whether lower-readiness learners truly entered the task rather than only completing surface actions."
            )
        }
        if !course.studentSupportNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            points.append(
                isChinese
                    ? "记录对支持需求学生最有效的即时支架，并判断哪些支架需要前置。"
                    : "Record which in-the-moment scaffolds worked best for students needing extra support and which ones should be moved earlier."
            )
        }
        if graph.evaluationNodes.isEmpty {
            points.append(
                isChinese
                    ? "反思本课证据收集是否足够支撑对目标达成的判断。"
                    : "Reflect on whether the lesson collected enough evidence to justify judgments about goal attainment."
            )
        } else {
            points.append(
                isChinese
                    ? "比较评价节点中的指标与课堂真实产出是否一致，并据此调整后续任务。"
                    : "Compare the evaluation indicators with students' actual products and adjust subsequent tasks accordingly."
            )
        }
        return points.joined(separator: isChinese ? "\n" : "\n")
    }

    private static func processQuestion(
        isChinese: Bool,
        graphHasFlow: Bool,
        wantsTimedProcessTable: Bool,
        wantsProcessIntent: Bool,
        wantsProcessEvidence: Bool
    ) -> String {
        if isChinese {
            if !graphHasFlow {
                return "模板要求把教学过程写成更完整的活动链。请补充本课教学过程里最需要强调的时间分配、关键活动或过渡安排。"
            }
            var requirements: [String] = []
            if wantsTimedProcessTable { requirements.append("时间分配") }
            if wantsProcessIntent { requirements.append("设计意图") }
            if wantsProcessEvidence { requirements.append("效果评价证据") }
            let joined = requirements.joined(separator: "、")
            return "模板对教学过程还有更细的要求。请补充课堂流程中的\(joined.isEmpty ? "关键细节" : joined)，让生成稿更贴近模板体例。"
        }
        if !graphHasFlow {
            return "The template expects a fuller teaching process. Add the time distribution, key activities, or transition moves that deserve emphasis."
        }
        var requirements: [String] = []
        if wantsTimedProcessTable { requirements.append("time allocation") }
        if wantsProcessIntent { requirements.append("design intent") }
        if wantsProcessEvidence { requirements.append("evaluation evidence") }
        let joined = requirements.joined(separator: ", ")
        return "The template expects more process detail. Add the \(joined.isEmpty ? "missing teaching-process details" : joined) needed to match the template more closely."
    }

    private static func containsTimingMarkers(_ text: String) -> Bool {
        text.range(of: #"(\d+\s*(分钟|min|mins|minutes?))"#, options: .regularExpression) != nil
    }

    private static func containsDesignIntentMarkers(_ text: String) -> Bool {
        let normalized = text.lowercased()
        return normalized.contains("设计意图") || normalized.contains("design intent")
    }

    private static func containsEvaluationEvidenceMarkers(_ text: String) -> Bool {
        let normalized = text.lowercased()
        return normalized.contains("效果评价")
            || normalized.contains("评价证据")
            || normalized.contains("observable evidence")
            || normalized.contains("evaluation evidence")
    }

    private static func baselineContainsLearnerProfile(_ text: String) -> Bool {
        let normalized = text.lowercased()
        return normalized.contains("学生与支持信息")
            || normalized.contains("learner profile & support")
    }

    private static func baselineContainsReflection(_ text: String) -> Bool {
        let normalized = text.lowercased()
        return normalized.contains("课后延伸与反思")
            || normalized.contains("课后反思问题")
            || normalized.contains("extension & reflection")
            || normalized.contains("post-lesson reflection")
    }

    private static func inferredProcessPhases(
        graph: EduAgentGraphContext,
        isChinese: Bool
    ) -> [String] {
        if graph.toolkitNodes.isEmpty {
            return isChinese
                ? ["导入与目标唤起", "核心学习任务", "整理与评价"]
                : ["Lead-in and goal activation", "Core learning task", "Consolidation and evaluation"]
        }

        var phases: [String] = [isChinese ? "导入与目标唤起" : "Lead-in and goal activation"]

        for toolkit in graph.toolkitNodes.prefix(2) {
            let label = toolkit.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !label.isEmpty {
                phases.append(label)
            }
        }

        if graph.toolkitNodes.count > 2 {
            phases.append(isChinese ? "综合应用与交流" : "Application and communication")
        }

        phases.append(isChinese ? "整理与评价" : "Consolidation and evaluation")
        return phases
    }

    private static func allocatedMinutes(
        total: Int,
        bucketCount: Int
    ) -> [Int] {
        guard bucketCount > 0 else { return [] }
        let base = max(4, total / bucketCount)
        var minutes = Array(repeating: base, count: bucketCount)
        var remainder = total - (base * bucketCount)
        var index = 0
        while remainder > 0 {
            minutes[index % bucketCount] += 1
            remainder -= 1
            index += 1
        }
        return minutes
    }

    private static func readableMethodLabel(
        _ methodID: String,
        isChinese: Bool
    ) -> String {
        switch methodID {
        case "context_hook":
            return isChinese ? "情境导入" : "context hook"
        case "field_observation":
            return isChinese ? "现场观察" : "field observation"
        case "source_analysis":
            return isChinese ? "材料细读" : "close reading"
        case "guided_observation":
            return isChinese ? "引导观察" : "guided observation"
        case "sensor_probe":
            return isChinese ? "传感探测" : "sensor probe"
        case "immersive_simulation":
            return isChinese ? "沉浸模拟" : "immersive simulation"
        case "low_fidelity_prototype", "prototype_build":
            return isChinese ? "低保真原型" : "low-fidelity prototype"
        case "physical_computing":
            return isChinese ? "实体计算" : "physical computing"
        case "story_construction":
            return isChinese ? "叙事建构" : "story construction"
        case "service_blueprint":
            return isChinese ? "服务蓝图" : "service blueprint"
        case "adaptive_learning_platform":
            return isChinese ? "自适应学习平台" : "adaptive learning platform"
        case "role_play":
            return isChinese ? "角色扮演" : "role play"
        case "structured_debate":
            return isChinese ? "结构化辩论" : "structured debate"
        case "world_cafe":
            return isChinese ? "世界咖啡" : "world cafe"
        case "game_mechanism":
            return isChinese ? "游戏机制" : "game mechanism"
        case "pogil":
            return isChinese ? "POGIL 协作探究" : "POGIL inquiry"
        case "peer_negotiation":
            return isChinese ? "同伴协商" : "peer negotiation"
        case "kanban_monitoring":
            return isChinese ? "看板监测" : "kanban monitoring"
        case "reflection_protocol", "reflection_log":
            return isChinese ? "反思协议" : "reflection protocol"
        case "metacognitive_routine":
            return isChinese ? "元认知例程" : "metacognitive routine"
        default:
            return methodID.replacingOccurrences(of: "_", with: " ")
        }
    }

    private static func teachingStyleLabel(
        _ raw: String,
        isChinese: Bool
    ) -> String {
        switch raw {
        case "lectureDriven":
            return isChinese ? "讲授驱动" : "lecture-driven"
        case "experientialReflective":
            return isChinese ? "体验-反思" : "experience-reflection"
        case "taskDriven":
            return isChinese ? "任务驱动" : "task-driven"
        default:
            return isChinese ? "探究驱动" : "inquiry-driven"
        }
    }

    private static func compactSentence(
        _ text: String,
        limit: Int
    ) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > limit else { return normalized }
        return String(normalized.prefix(limit)) + "..."
    }
}
