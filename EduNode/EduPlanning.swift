import Foundation
import CoreGraphics
import GNodeKit

enum GradeInputMode: String, CaseIterable {
    case grade
    case age
}

enum CourseLessonType: String, CaseIterable {
    case singleLesson
    case unitSeries
}

enum LearningOrganizationMode: String, CaseIterable {
    case individual
    case group
    case mixed
}

enum TeachingStyleMode: String, CaseIterable {
    case lectureDriven
    case inquiryDriven
    case experientialReflective
    case taskDriven
}

enum FormativeCheckIntensity: String, CaseIterable {
    case low
    case medium
    case high
}

struct CourseCreationDraft {
    var courseName: String = ""
    var gradeInputMode: GradeInputMode = .grade
    var gradeMinText: String = "1"
    var gradeMaxText: String = "1"
    var subject: String = ""
    var lessonType: CourseLessonType = .singleLesson
    var lessonDurationMinutesText: String = "45"
    var totalSessionsText: String = "1"
    var periodRange: String = ""
    var studentCountText: String = "30"
    var priorAssessmentScoreText: String = "70"
    var assignmentCompletionRateText: String = "75"
    var supportNeedCountText: String = "0"
    var studentSupportNotes: String = ""
    var studentRosterText: String = ""
    var learningOrganization: LearningOrganizationMode = .mixed
    var teachingStyle: TeachingStyleMode = .inquiryDriven
    var emphasizeInquiryExperiment: Bool = false
    var emphasizeExperienceReflection: Bool = false
    var requireStructuredFlow: Bool = false
    var formativeCheckIntensity: FormativeCheckIntensity = .medium
    var expectedOutputIDs: [String] = []
    var expectedOutputCustomText: String = ""
    var goals: [String] = []
    var modelID: String = ""
    var leadTeacherCountText: String = "1"
    var assistantTeacherCountText: String = "0"
    var teacherRolePlan: String = ""
    var resourceConstraints: String = ""

    var lessonDurationMinutes: Int {
        max(1, Int(lessonDurationMinutesText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 45)
    }

    var totalSessions: Int {
        max(1, Int(totalSessionsText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1)
    }

    var studentCount: Int {
        max(0, Int(studentCountText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0)
    }

    var priorAssessmentScore: Int {
        let raw = Int(priorAssessmentScoreText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 70
        return min(max(raw, 0), 100)
    }

    var assignmentCompletionRate: Int {
        let raw = Int(assignmentCompletionRateText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 75
        return min(max(raw, 0), 100)
    }

    var supportNeedCount: Int {
        let raw = Int(supportNeedCountText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        return max(raw, 0)
    }

    private var gradeLowerBound: Int {
        gradeInputMode == .grade ? 1 : 3
    }

    private var gradeUpperBound: Int {
        gradeInputMode == .grade ? 16 : 25
    }

    var gradeMin: Int {
        let raw = Int(gradeMinText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? gradeLowerBound
        return min(max(raw, gradeLowerBound), gradeUpperBound)
    }

    var gradeMax: Int {
        let raw = Int(gradeMaxText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? gradeMin
        return min(max(raw, gradeLowerBound), gradeUpperBound)
    }

    var normalizedGradeRange: (Int, Int) {
        let lower = min(gradeMin, gradeMax)
        let upper = max(gradeMin, gradeMax)
        return (lower, upper)
    }

    var goalsText: String {
        goals.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    var studentProfileSummary: String {
        let outputs = expectedOutputSummary
        return "priorScore=\(priorAssessmentScore), completion=\(assignmentCompletionRate), supportNeed=\(supportNeedCount), notes=\(studentSupportNotes), roster=\(studentRosterText), organization=\(learningOrganization.rawValue), outputs=\(outputs)"
    }

    var teacherTeamSummary: String {
        "lead=\(leadTeacherCount), assistant=\(assistantTeacherCount), plan=\(teacherRolePlan)"
    }

    var leadTeacherCount: Int {
        max(1, Int(leadTeacherCountText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1)
    }

    var assistantTeacherCount: Int {
        max(0, Int(assistantTeacherCountText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0)
    }

    var gradeLevelSummary: String {
        let range = normalizedGradeRange
        switch gradeInputMode {
        case .grade:
            return "grade \(range.0)-\(range.1)"
        case .age:
            return "age \(range.0)-\(range.1)"
        }
    }

    var expectedOutputSummary: String {
        let normalizedIDs = expectedOutputIDs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        let custom = expectedOutputCustomText.trimmingCharacters(in: .whitespacesAndNewlines)
        return ([normalizedIDs.joined(separator: ","), custom].filter { !$0.isEmpty }).joined(separator: " | ")
    }

    var isValid: Bool {
        !courseName.trimmed.isEmpty &&
        normalizedGradeRange.0 > 0 &&
        normalizedGradeRange.1 >= normalizedGradeRange.0 &&
        !subject.trimmed.isEmpty &&
        lessonDurationMinutes > 0 &&
        totalSessions > 0 &&
        studentCount > 0 &&
        priorAssessmentScore >= 0 &&
        priorAssessmentScore <= 100 &&
        assignmentCompletionRate >= 0 &&
        assignmentCompletionRate <= 100 &&
        supportNeedCount >= 0 &&
        !goalsText.trimmed.isEmpty &&
        !modelID.trimmed.isEmpty
    }
}

struct EduModelRule: Codable, Identifiable, Hashable {
    let id: String
    let nameEN: String
    let nameZH: String
    let descriptionEN: String
    let descriptionZH: String
    let gradeHints: [String]
    let subjectHints: [String]
    let scenarioHints: [String]
    let toolkitPresetIDs: [String]
    let templateFocusEN: String
    let templateFocusZH: String

    private enum CodingKeys: String, CodingKey {
        case id
        case nameEN = "name_en"
        case nameZH = "name_zh"
        case descriptionEN = "description_en"
        case descriptionZH = "description_zh"
        case gradeHints = "grade_hints"
        case subjectHints = "subject_hints"
        case scenarioHints = "scenario_hints"
        case toolkitPresetIDs = "toolkit_preset_ids"
        case templateFocusEN = "template_focus_en"
        case templateFocusZH = "template_focus_zh"
    }

    func displayName(isChinese: Bool) -> String {
        isChinese ? nameZH : nameEN
    }

    func displayDescription(isChinese: Bool) -> String {
        isChinese ? descriptionZH : descriptionEN
    }

    func templateFocus(isChinese: Bool) -> String {
        isChinese ? templateFocusZH : templateFocusEN
    }
}

struct EduToolkitPreset: Hashable, Identifiable {
    let id: String
    let titleEN: String
    let titleZH: String
    let intentEN: String
    let intentZH: String

    func title(isChinese: Bool) -> String {
        isChinese ? titleZH : titleEN
    }

    func intent(isChinese: Bool) -> String {
        isChinese ? intentZH : intentEN
    }
}

enum EduPlanning {
    static let rolePrefix = "edunode.role="
    private static let zhuhaiSampleID = "zhuhai_birds_v3"

    static func loadModelRules() -> [EduModelRule] {
        let decoder = JSONDecoder()
        if let url = Bundle.main.url(forResource: "model_rules", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let rules = try? decoder.decode([EduModelRule].self, from: data),
           !rules.isEmpty {
            return rules
        }

        if let data = fallbackRulesJSON.data(using: .utf8),
           let rules = try? decoder.decode([EduModelRule].self, from: data),
           !rules.isEmpty {
            return rules
        }

        return []
    }

    static func toolkitPresets() -> [EduToolkitPreset] {
        [
            EduToolkitPreset(
                id: "context-hook",
                titleEN: "Context Hook",
                titleZH: "情境导入",
                intentEN: "Activate prior knowledge and raise curiosity.",
                intentZH: "激活先验知识并引发学习兴趣。"
            ),
            EduToolkitPreset(
                id: "contrast-analysis",
                titleEN: "Contrast Analysis",
                titleZH: "对比辨析",
                intentEN: "Build concept boundaries by comparing examples.",
                intentZH: "通过对比案例构建概念边界。"
            ),
            EduToolkitPreset(
                id: "peer-discussion",
                titleEN: "Peer Discussion",
                titleZH: "同伴讨论",
                intentEN: "Promote reasoning through peer interaction.",
                intentZH: "通过同伴互动促进推理表达。"
            ),
            EduToolkitPreset(
                id: "experiment-observe",
                titleEN: "Experiment & Observe",
                titleZH: "实验观察",
                intentEN: "Turn abstract points into observable evidence.",
                intentZH: "把抽象知识转化为可观察证据。"
            ),
            EduToolkitPreset(
                id: "task-driven",
                titleEN: "Task Driven",
                titleZH: "任务驱动",
                intentEN: "Strengthen transfer through targeted practice tasks.",
                intentZH: "通过任务实践强化迁移应用。"
            ),
            EduToolkitPreset(
                id: "exit-ticket",
                titleEN: "Exit Ticket",
                titleZH: "出口条",
                intentEN: "Collect final reflection and fast diagnosis.",
                intentZH: "收集课末反思并快速诊断问题。"
            )
        ]
    }

    static func recommendedModels(for draft: CourseCreationDraft, rules: [EduModelRule]) -> [EduModelRule] {
        let grade = draft.gradeLevelSummary.lowercased()
        let subject = draft.subject.lowercased()
        let outputs = draft.expectedOutputSummary.lowercased()
        let scenarioContext = [
            draft.periodRange,
            draft.studentSupportNotes,
            draft.goalsText,
            draft.resourceConstraints,
            outputs
        ]
            .joined(separator: " ")
            .lowercased()

        var bonusByModelID: [String: Int] = [:]

        // SOP 1: Hard preference by lesson type (Kolb also supports unit-series).
        switch draft.lessonType {
        case .singleLesson:
            bonusByModelID["boppps", default: 0] += 3
            bonusByModelID["gagne9", default: 0] += 3
            bonusByModelID["fivee", default: 0] += 2
            bonusByModelID["ubd", default: 0] += 1
        case .unitSeries:
            bonusByModelID["ubd", default: 0] += 4
            bonusByModelID["kolb", default: 0] += 4
            bonusByModelID["fivee", default: 0] += 2
            bonusByModelID["gagne9", default: 0] += 1
            bonusByModelID["boppps", default: 0] += 1
        }

        // SOP 2: Teaching style.
        switch draft.teachingStyle {
        case .lectureDriven:
            bonusByModelID["gagne9", default: 0] += 3
            bonusByModelID["boppps", default: 0] += 2
            bonusByModelID["ubd", default: 0] += 1
        case .inquiryDriven:
            bonusByModelID["fivee", default: 0] += 4
            bonusByModelID["ubd", default: 0] += 2
            bonusByModelID["kolb", default: 0] += 1
        case .experientialReflective:
            bonusByModelID["kolb", default: 0] += 5
            bonusByModelID["fivee", default: 0] += 1
        case .taskDriven:
            bonusByModelID["ubd", default: 0] += 3
            bonusByModelID["boppps", default: 0] += 2
            bonusByModelID["fivee", default: 0] += 1
        }

        // SOP 3: Core preference toggles.
        if draft.emphasizeInquiryExperiment {
            bonusByModelID["fivee", default: 0] += 4
            bonusByModelID["kolb", default: 0] += 1
            bonusByModelID["ubd", default: 0] += 1
        }

        if draft.emphasizeExperienceReflection {
            bonusByModelID["kolb", default: 0] += 5
            bonusByModelID["fivee", default: 0] += 1
        }

        if draft.requireStructuredFlow {
            bonusByModelID["gagne9", default: 0] += 4
            bonusByModelID["boppps", default: 0] += 4
        }

        switch draft.formativeCheckIntensity {
        case .high:
            bonusByModelID["boppps", default: 0] += 3
            bonusByModelID["gagne9", default: 0] += 2
            bonusByModelID["ubd", default: 0] += 1
        case .medium:
            bonusByModelID["boppps", default: 0] += 1
            bonusByModelID["gagne9", default: 0] += 1
        case .low:
            bonusByModelID["kolb", default: 0] += 1
            bonusByModelID["fivee", default: 0] += 1
        }

        // SOP 4: Organization only fine-tunes.
        switch draft.learningOrganization {
        case .individual:
            bonusByModelID["gagne9", default: 0] += 2
            bonusByModelID["boppps", default: 0] += 1
        case .group:
            bonusByModelID["fivee", default: 0] += 2
            bonusByModelID["kolb", default: 0] += 2
        case .mixed:
            bonusByModelID["ubd", default: 0] += 1
            bonusByModelID["fivee", default: 0] += 1
            bonusByModelID["kolb", default: 0] += 1
        }

        // SOP 5: Session count preference.
        if draft.totalSessions >= 4 {
            bonusByModelID["ubd", default: 0] += 3
            bonusByModelID["kolb", default: 0] += 2
        } else if draft.totalSessions >= 2 {
            bonusByModelID["ubd", default: 0] += 2
            bonusByModelID["kolb", default: 0] += 1
            bonusByModelID["fivee", default: 0] += 1
        } else {
            bonusByModelID["boppps", default: 0] += 2
            bonusByModelID["gagne9", default: 0] += 2
            bonusByModelID["fivee", default: 0] += 1
        }

        func containsAny(_ candidates: [String]) -> Bool {
            candidates.contains { token in
                let needle = token.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                return !needle.isEmpty && scenarioContext.contains(needle)
            }
        }

        // SOP 6: Goal/output semantics.
        if containsAny(["探究", "实验", "question", "inquiry", "hypothesis", "experiment"]) {
            bonusByModelID["fivee", default: 0] += 3
            bonusByModelID["kolb", default: 0] += 1
        }
        if containsAny(["目标", "证据", "标准", "outcome", "evidence", "rubric", "transfer"]) {
            bonusByModelID["ubd", default: 0] += 3
            bonusByModelID["gagne9", default: 0] += 1
        }
        if containsAny(["循环", "反思", "迭代", "cycle", "iterate", "reflection"]) {
            bonusByModelID["kolb", default: 0] += 3
        }
        if containsAny(["讲授", "结构化", "direct instruction", "step-by-step"]) {
            bonusByModelID["gagne9", default: 0] += 2
            bonusByModelID["boppps", default: 0] += 1
        }
        if outputs.contains("artifact") || outputs.contains("作品") || outputs.contains("project") || outputs.contains("项目") {
            bonusByModelID["kolb", default: 0] += 2
            bonusByModelID["ubd", default: 0] += 1
        }
        if outputs.contains("quiz") || outputs.contains("测验") || outputs.contains("worksheet") || outputs.contains("练习") {
            bonusByModelID["boppps", default: 0] += 1
            bonusByModelID["gagne9", default: 0] += 1
        }

        let scored = rules.map { rule in
            var score = 0
            score += keywordScore(input: grade, hints: rule.gradeHints) * 2
            score += keywordScore(input: subject, hints: rule.subjectHints) * 3
            score += keywordScore(input: scenarioContext, hints: rule.scenarioHints) * 2
            score += bonusByModelID[rule.id, default: 0]
            return (rule, score)
        }

        return scored
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 { return lhs.0.id < rhs.0.id }
                return lhs.1 > rhs.1
            }
            .map(\.0)
            .prefix(3)
            .map { $0 }
    }

    static func makeInitialDocumentData(
        draft: CourseCreationDraft,
        modelRule: EduModelRule,
        isChinese: Bool
    ) -> Data {
        var entries: [TemplateNodeEntry] = []
        var templateLayoutNodes: [TemplateLayoutNode] = []
        let graph = NodeGraph()

        func add(_ node: any GNode, type: String, x: Double, y: Double, role: String? = nil) {
            if let role {
                node.attributes.description = rolePrefix + role
            }
            graph.addNode(node)
            entries.append(
                TemplateNodeEntry(
                    node: node,
                    type: type,
                    position: CGPoint(x: x, y: y)
                )
            )
        }

        func markLayout(_ node: any GNode, type: String, column: Int, preferredY: Double) {
            templateLayoutNodes.append(
                TemplateLayoutNode(
                    nodeID: node.id,
                    column: column,
                    preferredY: preferredY,
                    size: estimatedTemplateNodeSize(node: node, nodeType: type),
                    order: templateLayoutNodes.count
                )
            )
        }
        func L(_ zh: String, _ en: String) -> String {
            isChinese ? zh : en
        }

        let goals = draft.goals
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let primaryGoal = goals.first ?? L("教学目标待补充", "Teaching goal to be refined")
        let focusText = modelRule.templateFocus(isChinese: isChinese)

        let levelRemember = S("edu.knowledge.type.remember")
        let levelUnderstand = S("edu.knowledge.type.understand")
        let levelApply = S("edu.knowledge.type.apply")
        let levelAnalyze = S("edu.knowledge.type.analyze")
        let levelEvaluate = S("edu.knowledge.type.evaluate")
        let levelCreate = S("edu.knowledge.type.create")

        func toolkitNodeType(for category: EduToolkitCategory) -> String {
            switch category {
            case .perceptionInquiry:
                return EduNodeType.toolkitPerceptionInquiry
            case .constructionPrototype:
                return EduNodeType.toolkitConstructionPrototype
            case .communicationNegotiation:
                return EduNodeType.toolkitCommunicationNegotiation
            case .regulationMetacognition:
                return EduNodeType.toolkitRegulationMetacognition
            }
        }

        func makeKnowledgeNode(title: String, content: String, level: String) -> any GNode {
            if let registered = GNodeNodeKit.gnodeNodeKit.createNode(type: EduNodeType.knowledge) {
                registered.attributes.name = title
                if let node = registered as? EduKnowledgeNode {
                    node.editorTextValue = content
                    node.editorSelectedOption = level
                }
                return registered
            }
            return EduKnowledgeNode(name: title, content: content, level: level)
        }

        func makeToolkitNode(
            title: String,
            content: String,
            category: EduToolkitCategory,
            methodID: String
        ) -> (any GNode, String) {
            let nodeType = toolkitNodeType(for: category)
            if let registered = GNodeNodeKit.gnodeNodeKit.createNode(type: nodeType) {
                registered.attributes.name = title
                if let node = registered as? any NodeTextEditable {
                    node.editorTextValue = content
                }
                if let node = registered as? EduToolkitNode {
                    node.editorSelectedMethodID = methodID
                }
                return (registered, nodeType)
            }
            let fallback = EduToolkitNode(
                name: title,
                category: category,
                value: content,
                selectedMethodID: methodID
            )
            return (fallback, nodeType)
        }

        var nodesByID: [String: any GNode] = [:]

        func addKnowledge(
            id: String,
            title: String,
            content: String,
            level: String,
            column: Int,
            preferredY: Double
        ) {
            let node = makeKnowledgeNode(title: title, content: content, level: level)
            nodesByID[id] = node
            add(node, type: EduNodeType.knowledge, x: 0, y: 0, role: "knowledge")
            markLayout(node, type: EduNodeType.knowledge, column: column, preferredY: preferredY)
        }

        func addToolkit(
            id: String,
            title: String,
            content: String,
            category: EduToolkitCategory,
            methodID: String,
            column: Int,
            preferredY: Double
        ) {
            let (node, nodeType) = makeToolkitNode(
                title: title,
                content: content,
                category: category,
                methodID: methodID
            )
            nodesByID[id] = node
            add(node, type: nodeType, x: 0, y: 0, role: "toolkit")
            markLayout(node, type: nodeType, column: column, preferredY: preferredY)
        }

        func connect(_ sourceID: String, _ targetID: String) {
            guard let source = nodesByID[sourceID], let target = nodesByID[targetID] else { return }
            connectFirstOutput(from: source, to: target, inputIndex: 0, in: graph)
        }

        switch modelRule.id {
        case "ubd":
            addKnowledge(
                id: "k1",
                title: L("UbD 阶段1：预期结果", "UbD Stage 1: Desired Results"),
                content: "\(focusText)\n\(L("聚焦可迁移的大概念与关键表现。", "Focus on transfer goals and key performances."))\n\(L("核心目标：", "Core objective:")) \(primaryGoal)",
                level: levelAnalyze,
                column: 0,
                preferredY: -320
            )
            addKnowledge(
                id: "k2",
                title: L("UbD 阶段2：可接受证据", "UbD Stage 2: Acceptable Evidence"),
                content: L("明确可观察证据、表现任务与达成标准。", "Define observable evidence, performance tasks, and success criteria."),
                level: levelEvaluate,
                column: 1,
                preferredY: -320
            )
            addKnowledge(
                id: "k3",
                title: L("UbD 阶段3：学习体验规划", "UbD Stage 3: Learning Plan"),
                content: L("围绕证据倒推课堂活动与知识顺序。", "Back-design learning experiences from evidence."),
                level: levelApply,
                column: 2,
                preferredY: -320
            )
            addToolkit(
                id: "t1",
                title: L("导入与诊断", "Hook & Diagnose"),
                content: L("激活先验知识，明确学习挑战。", "Activate prior knowledge and surface learning challenges."),
                category: .perceptionInquiry,
                methodID: "context_hook",
                column: 3,
                preferredY: 320
            )
            addToolkit(
                id: "t2",
                title: L("任务建构", "Build Through Task"),
                content: L("以任务驱动产出学习证据。", "Use task-driven activities to generate evidence."),
                category: .constructionPrototype,
                methodID: "low_fidelity_prototype",
                column: 4,
                preferredY: 320
            )
            addToolkit(
                id: "t3",
                title: L("讨论表达", "Discussion & Expression"),
                content: L("通过结构化讨论解释理解。", "Explain understanding through structured discussion."),
                category: .communicationNegotiation,
                methodID: "structured_debate",
                column: 5,
                preferredY: 320
            )
            addToolkit(
                id: "t4",
                title: L("收束反思", "Reflect & Close"),
                content: L("课堂收束，形成下一步改进。", "Close the lesson and capture next-step improvements."),
                category: .regulationMetacognition,
                methodID: "reflection_protocol",
                column: 6,
                preferredY: 320
            )

            connect("k1", "k2")
            connect("k2", "k3")
            connect("k3", "t1")
            connect("t1", "t2")
            connect("t2", "t3")
            connect("t3", "t4")
            connect("k2", "t2")
            connect("k2", "t3")
            connect("k2", "t4")

        case "fivee":
            addKnowledge(
                id: "k1",
                title: "5E Engage",
                content: L("用现象或冲突问题激发兴趣，并提出驱动问题。", "Spark curiosity with a puzzling phenomenon and frame a driving question."),
                level: levelRemember,
                column: 0,
                preferredY: -320
            )
            addToolkit(
                id: "t1",
                title: L("Engage 工具", "Engage Toolkit"),
                content: L("情境导入与兴趣激活。", "Context hook for motivation."),
                category: .perceptionInquiry,
                methodID: "context_hook",
                column: 0,
                preferredY: 320
            )
            addKnowledge(
                id: "k2",
                title: "5E Explore",
                content: L("围绕问题开展观察、实验与证据采集。", "Run exploration and evidence collection."),
                level: levelAnalyze,
                column: 1,
                preferredY: -320
            )
            addToolkit(
                id: "t2",
                title: L("Explore 工具", "Explore Toolkit"),
                content: L("观察记录与数据采集。", "Field observation and data capture."),
                category: .perceptionInquiry,
                methodID: "field_observation",
                column: 1,
                preferredY: 320
            )
            addKnowledge(
                id: "k3",
                title: "5E Explain",
                content: L("组织证据并构建概念解释。", "Organize evidence and build explanations."),
                level: levelUnderstand,
                column: 2,
                preferredY: -320
            )
            addToolkit(
                id: "t3",
                title: L("Explain 工具", "Explain Toolkit"),
                content: L("同伴讨论与观点澄清。", "Peer discussion for conceptual clarification."),
                category: .communicationNegotiation,
                methodID: "structured_debate",
                column: 2,
                preferredY: 320
            )
            addKnowledge(
                id: "k4",
                title: "5E Elaborate",
                content: L("迁移应用到新情境。", "Transfer learning to new situations."),
                level: levelApply,
                column: 3,
                preferredY: -320
            )
            addToolkit(
                id: "t4",
                title: L("Elaborate 工具", "Elaborate Toolkit"),
                content: L("通过原型/任务强化迁移。", "Use task/prototype activities for transfer."),
                category: .constructionPrototype,
                methodID: "story_construction",
                column: 3,
                preferredY: 320
            )
            addKnowledge(
                id: "k5",
                title: "5E Evaluate",
                content: L("总结本课达成与下一步。", "Summarize achievement and next steps."),
                level: levelEvaluate,
                column: 4,
                preferredY: -320
            )
            addToolkit(
                id: "t5",
                title: L("Evaluate 工具", "Evaluate Toolkit"),
                content: L("反思与自我监控。", "Reflection and self-monitoring."),
                category: .regulationMetacognition,
                methodID: "reflection_protocol",
                column: 4,
                preferredY: 320
            )

            connect("k1", "t1")
            connect("t1", "k2")
            connect("k2", "t2")
            connect("t2", "k3")
            connect("k3", "t3")
            connect("t3", "k4")
            connect("k4", "t4")
            connect("t4", "k5")
            connect("k5", "t5")

        case "kolb":
            addKnowledge(
                id: "k1",
                title: L("Kolb 具体体验", "Kolb: Concrete Experience"),
                content: L("从真实体验切入，形成可观察的学习起点。", "Begin with a concrete experience that creates an observable learning entry point."),
                level: levelRemember,
                column: 0,
                preferredY: -300
            )
            addToolkit(
                id: "t1",
                title: L("体验采集工具", "Experience Capture Toolkit"),
                content: L("通过观察或情境任务采集第一手体验证据。", "Capture first-hand experience evidence from observation/context tasks."),
                category: .perceptionInquiry,
                methodID: "field_observation",
                column: 0,
                preferredY: 300
            )
            addKnowledge(
                id: "k2",
                title: L("Kolb 反思观察", "Kolb: Reflective Observation"),
                content: L("记录关键现象与疑问。", "Capture patterns and reflective questions."),
                level: levelAnalyze,
                column: 1,
                preferredY: -300
            )
            addToolkit(
                id: "t2",
                title: L("反思工具", "Reflection Toolkit"),
                content: L("结构化反思与监控。", "Structured reflection and monitoring."),
                category: .regulationMetacognition,
                methodID: "metacognitive_routine",
                column: 1,
                preferredY: 300
            )
            addKnowledge(
                id: "k3",
                title: L("Kolb 抽象概念化", "Kolb: Abstract Conceptualization"),
                content: L("形成概念模型与解释框架。", "Form abstract models and conceptual frameworks."),
                level: levelUnderstand,
                column: 2,
                preferredY: -300
            )
            addToolkit(
                id: "t3",
                title: L("建构工具", "Concept Build Toolkit"),
                content: L("用可视化产出表达概念。", "Externalize concepts via construction."),
                category: .constructionPrototype,
                methodID: "story_construction",
                column: 2,
                preferredY: 300
            )
            addKnowledge(
                id: "k4",
                title: L("Kolb 主动实验", "Kolb: Active Experimentation"),
                content: L("在新任务中验证概念并形成下一轮体验入口。", "Test concepts in new tasks and produce the entry point for the next cycle."),
                level: levelApply,
                column: 3,
                preferredY: -300
            )
            addToolkit(
                id: "t4",
                title: L("实验沟通工具", "Experiment & Share Toolkit"),
                content: L("协商改进方案并沉淀下一轮起始任务。", "Collaboratively refine and package the next-round starting task."),
                category: .communicationNegotiation,
                methodID: "pogil",
                column: 3,
                preferredY: 300
            )

            connect("k1", "t1")
            connect("t1", "k2")
            connect("k2", "t2")
            connect("t2", "k3")
            connect("k3", "t3")
            connect("t3", "k4")
            connect("k4", "t4")

        case "boppps":
            addKnowledge(
                id: "k1",
                title: "BOPPPS Bridge-in",
                content: L("通过简短导入快速进入问题情境。", "Use a short bridge-in to enter the lesson problem quickly."),
                level: levelRemember,
                column: 0,
                preferredY: -300
            )
            addToolkit(
                id: "t1",
                title: L("Bridge-in 工具", "Bridge-in Toolkit"),
                content: L("导入与注意力聚焦。", "Attention and context activation."),
                category: .perceptionInquiry,
                methodID: "context_hook",
                column: 0,
                preferredY: 300
            )
            addKnowledge(
                id: "k2",
                title: "BOPPPS Objective",
                content: "\(L("本课核心目标：", "Core lesson objective:")) \(primaryGoal)",
                level: levelUnderstand,
                column: 1,
                preferredY: -300
            )
            addKnowledge(
                id: "k3",
                title: "BOPPPS Pre-assessment",
                content: L("明确起点与已有认知。", "Clarify baseline understanding."),
                level: levelAnalyze,
                column: 2,
                preferredY: -300
            )
            addToolkit(
                id: "t2",
                title: L("Pre-assessment 工具", "Pre-assessment Toolkit"),
                content: L("使用量规/核查快速诊断。", "Use checklist/rubric for quick diagnosis."),
                category: .regulationMetacognition,
                methodID: "rubric_checklist",
                column: 2,
                preferredY: 300
            )
            addKnowledge(
                id: "k4",
                title: "BOPPPS Participatory",
                content: L("进入参与式学习主活动。", "Run the participatory learning core."),
                level: levelApply,
                column: 3,
                preferredY: 0
            )
            addToolkit(
                id: "t3",
                title: L("参与路径A", "Participatory Path A"),
                content: L("讨论协商路径。", "Discussion-driven participatory path."),
                category: .communicationNegotiation,
                methodID: "world_cafe",
                column: 4,
                preferredY: -300
            )
            addToolkit(
                id: "t4",
                title: L("参与路径B", "Participatory Path B"),
                content: L("建构产出路径。", "Construction/prototype participatory path."),
                category: .constructionPrototype,
                methodID: "low_fidelity_prototype",
                column: 4,
                preferredY: 300
            )
            addKnowledge(
                id: "k5",
                title: "BOPPPS Post-assessment",
                content: L("汇总学习结果并确认达成。", "Post-assess performance and outcomes."),
                level: levelEvaluate,
                column: 5,
                preferredY: 0
            )
            addToolkit(
                id: "t5",
                title: L("Summary 工具", "Summary Toolkit"),
                content: L("反思收束并迁移到下一课。", "Reflection and transfer for next lesson."),
                category: .regulationMetacognition,
                methodID: "reflection_protocol",
                column: 6,
                preferredY: 300
            )
            addKnowledge(
                id: "k6",
                title: "BOPPPS Summary",
                content: L("沉淀关键结论与课后行动。", "Capture key takeaways and follow-up actions."),
                level: levelCreate,
                column: 6,
                preferredY: -300
            )

            connect("k1", "t1")
            connect("t1", "k2")
            connect("k2", "k3")
            connect("k3", "t2")
            connect("t2", "k4")
            connect("k4", "t3")
            connect("k4", "t4")
            connect("t3", "k5")
            connect("t4", "k5")
            connect("k5", "t5")
            connect("t5", "k6")

        case "gagne9":
            addKnowledge(id: "k1", title: L("Gagné 事件1：引起注意", "Gagné 1: Gain Attention"), content: L("用简短刺激引发注意并建立任务期待。", "Use a concise stimulus to gain attention and set task expectation."), level: levelRemember, column: 0, preferredY: -300)
            addToolkit(id: "t1", title: L("事件1工具", "Event 1 Toolkit"), content: L("快速导入与注意力聚焦。", "Hook and focus attention."), category: .perceptionInquiry, methodID: "context_hook", column: 0, preferredY: 300)
            addKnowledge(id: "k2", title: L("Gagné 事件2：告知目标", "Gagné 2: Inform Objectives"), content: "\(L("本课核心目标：", "Core lesson objective:")) \(primaryGoal)", level: levelUnderstand, column: 1, preferredY: -300)
            addKnowledge(id: "k3", title: L("Gagné 事件3：唤醒旧知", "Gagné 3: Stimulate Recall"), content: L("连接先修知识与本课重点。", "Activate prior knowledge linked to this lesson."), level: levelUnderstand, column: 2, preferredY: -300)
            addKnowledge(id: "k4", title: L("Gagné 事件4：呈现内容", "Gagné 4: Present Content"), content: focusText, level: levelAnalyze, column: 3, preferredY: -300)
            addToolkit(id: "t2", title: L("事件4工具", "Event 4 Toolkit"), content: L("多源资料呈现关键知识。", "Present key content through source analysis."), category: .perceptionInquiry, methodID: "source_analysis", column: 3, preferredY: 300)
            addKnowledge(id: "k5", title: L("Gagné 事件5：提供指导", "Gagné 5: Provide Guidance"), content: L("给出策略与思维支架。", "Provide strategy and cognitive scaffolds."), level: levelApply, column: 4, preferredY: -300)
            addToolkit(id: "t3", title: L("事件5工具", "Event 5 Toolkit"), content: L("通过讨论组织指导。", "Use guided discussion for scaffolding."), category: .communicationNegotiation, methodID: "structured_debate", column: 4, preferredY: 300)
            addKnowledge(id: "k6", title: L("Gagné 事件6：引出表现", "Gagné 6: Elicit Performance"), content: L("组织练习并产出表现。", "Elicit learner performance through practice."), level: levelApply, column: 5, preferredY: -300)
            addToolkit(id: "t4", title: L("事件6工具", "Event 6 Toolkit"), content: L("任务驱动练习与建构输出。", "Task-driven practice with tangible output."), category: .constructionPrototype, methodID: "low_fidelity_prototype", column: 5, preferredY: 300)
            addKnowledge(id: "k7", title: L("Gagné 事件7：提供反馈", "Gagné 7: Provide Feedback"), content: L("面向表现给出可操作反馈。", "Provide actionable feedback on performance."), level: levelEvaluate, column: 6, preferredY: -300)
            addToolkit(id: "t5", title: L("事件7工具", "Event 7 Toolkit"), content: L("同伴协商反馈与修正。", "Peer feedback and collaborative refinement."), category: .communicationNegotiation, methodID: "world_cafe", column: 6, preferredY: 300)
            addKnowledge(id: "k8", title: L("Gagné 事件8：检核表现", "Gagné 8: Assess Performance"), content: L("检核学习表现和完成度。", "Assess mastery and performance quality."), level: levelEvaluate, column: 7, preferredY: -300)
            addKnowledge(id: "k9", title: L("Gagné 事件9：促进迁移保持", "Gagné 9: Retention & Transfer"), content: L("巩固要点并迁移到新任务。", "Consolidate and transfer to new tasks."), level: levelCreate, column: 8, preferredY: -300)
            addToolkit(id: "t6", title: L("事件9工具", "Event 9 Toolkit"), content: L("反思收束与迁移计划。", "Reflection closure with transfer planning."), category: .regulationMetacognition, methodID: "reflection_protocol", column: 8, preferredY: 300)

            connect("k1", "t1")
            connect("t1", "k2")
            connect("k2", "k3")
            connect("k3", "k4")
            connect("k4", "t2")
            connect("t2", "k5")
            connect("k5", "t3")
            connect("t3", "k6")
            connect("k6", "t4")
            connect("t4", "k7")
            connect("k7", "t5")
            connect("t5", "k8")
            connect("k8", "k9")
            connect("k9", "t6")

        default:
            addKnowledge(
                id: "k1",
                title: S("template.knowledge"),
                content: "\(focusText)\n\(L("核心目标：", "Core objective:")) \(primaryGoal)",
                level: levelUnderstand,
                column: 0,
                preferredY: -260
            )
            addToolkit(
                id: "t1",
                title: "\(S("template.toolkit")) 1",
                content: L("先完成导入与观察。", "Start with context and observation."),
                category: .perceptionInquiry,
                methodID: "context_hook",
                column: 1,
                preferredY: 260
            )
            addToolkit(
                id: "t2",
                title: "\(S("template.toolkit")) 2",
                content: L("再进行产出与表达。", "Then move to construction and expression."),
                category: .constructionPrototype,
                methodID: "story_construction",
                column: 2,
                preferredY: 260
            )
            connect("k1", "t1")
            connect("t1", "t2")
        }

        let resolvedLayout = resolveTemplateLayout(for: templateLayoutNodes)
        entries = entries.map { entry in
            let resolvedPosition = resolvedLayout[entry.node.id] ?? entry.position
            return TemplateNodeEntry(
                node: entry.node,
                type: entry.type,
                position: resolvedPosition
            )
        }

        let serializedNodes = entries.map { entry in
            SerializableNode(from: entry.node, nodeType: entry.type)
        }
        let canvasState = entries.map { entry in
            CanvasNodeState(nodeID: entry.node.id, position: entry.position)
        }

        var document = GNodeDocument(
            nodes: serializedNodes,
            connections: graph.getAllConnections(),
            canvasState: canvasState
        )
        document.metadata.description = "edunode.model=\(modelRule.id)"

        return (try? encodeDocument(document)) ?? Data()
    }

    static func makeZhuhaiBirdSampleDocumentData(isChinese: Bool) -> Data {
        var entries: [TemplateNodeEntry] = []
        let graph = NodeGraph()

        func add(_ node: any GNode, type: String, x: Double, y: Double, role: String? = nil) {
            if let role {
                node.attributes.description = rolePrefix + role
            }
            graph.addNode(node)
            entries.append(
                TemplateNodeEntry(
                    node: node,
                    type: type,
                    position: CGPoint(x: x, y: y)
                )
            )
        }

        func makeKnowledge(_ titleZH: String, _ titleEN: String, _ contentZH: String, _ contentEN: String, level: String) -> any GNode {
            let title = isChinese ? titleZH : titleEN
            let content = isChinese ? contentZH : contentEN
            if let registered = GNodeNodeKit.gnodeNodeKit.createNode(type: EduNodeType.knowledge) {
                registered.attributes.name = title
                if let node = registered as? EduKnowledgeNode {
                    node.editorTextValue = content
                    node.editorSelectedOption = level
                }
                return registered
            }
            return EduKnowledgeNode(name: title, content: content, level: level)
        }

        func makeToolkit(
            _ titleZH: String,
            _ titleEN: String,
            _ contentZH: String,
            _ contentEN: String,
            nodeType: String,
            methodID: String,
            formText: [String: String] = [:],
            formOptions: [String: String] = [:]
        ) -> any GNode {
            let title = isChinese ? titleZH : titleEN
            let content = isChinese ? contentZH : contentEN
            if let registered = GNodeNodeKit.gnodeNodeKit.createNode(type: nodeType) {
                registered.attributes.name = title
                if let node = registered as? any NodeTextEditable {
                    node.editorTextValue = content
                }
                if let node = registered as? EduToolkitNode {
                    node.editorSelectedMethodID = methodID
                }
                if let formNode = registered as? any NodeFormEditable {
                    for (fieldID, optionValue) in formOptions {
                        formNode.setEditorFormOptionValue(optionValue, for: fieldID)
                    }
                    for (fieldID, textValue) in formText {
                        formNode.setEditorFormTextFieldValue(textValue, for: fieldID)
                    }
                }
                return registered
            }
            let category = EduToolkitCategory.fromNodeType(nodeType) ?? .communicationNegotiation
            return EduToolkitNode(
                name: title,
                category: category,
                value: content,
                selectedMethodID: methodID,
                textFieldValues: formText,
                optionFieldValues: formOptions
            )
        }

        let levelRemember = S("edu.knowledge.type.remember")
        let levelUnderstand = S("edu.knowledge.type.understand")
        let levelApply = S("edu.knowledge.type.apply")
        let levelAnalyze = S("edu.knowledge.type.analyze")
        let levelCreate = S("edu.knowledge.type.create")

        let tCheckinGrouping = makeToolkit(
            "签到分组（年龄×难度）",
            "Check-in Grouping (Age × Difficulty)",
            "根据年龄段（6-13岁）与鸟巢搭建难度，将学生分到7个目标鸟组，高年龄优先进入高难度组。",
            "Students are grouped into 7 bird teams by age band (6-13) and nest-building difficulty; older learners take higher-difficulty tasks.",
            nodeType: EduNodeType.toolkitCommunicationNegotiation,
            methodID: "pogil",
            formText: [
                "pogil_role_dict": isChinese
                    ? "签到助教 | 核对名单并登记年龄段\n分组助教 | 按年龄和巢型难度分配到7组\n组内队长 | 组织两人协作与任务卡填写"
                    : "Check-in TA | Verify attendance and age band\nGrouping TA | Assign 7 bird teams by age and nest difficulty\nTeam lead | Coordinate pair work and worksheet completion",
                "pogil_inquiry_ladder": isChinese
                    ? "1. 你属于哪个年龄段？\n2. 你们组负责哪种鸟？\n3. 该鸟巢搭建的关键挑战是什么？"
                    : "1. Which age band are you in?\n2. Which bird is your team responsible for?\n3. What is the key challenge of this nest?",
                "pogil_sheet_focus": isChinese
                    ? "完成签到分组卡，明确组别、目标鸟种与巢型任务。"
                    : "Complete check-in grouping card: team, target bird, and nest task.",
                "pogil_teacher_trigger_optional": isChinese
                    ? "若年龄与任务难度不匹配，教师现场手动重分。"
                    : "Teacher manually rebalances when age and difficulty mismatch."
            ],
            formOptions: [
                "pogil_checkpoint": "teacher_gate"
            ]
        )

        let tWarmupPuzzle = makeToolkit(
            "暖场游戏：一起拼一拼",
            "Warm-up Game: Puzzle Sprint",
            "两人一组拼图破冰，快速进入鸟类主题。",
            "Pairs solve bird puzzles as an icebreaker and theme entry.",
            nodeType: EduNodeType.toolkitCommunicationNegotiation,
            methodID: "game_mechanism",
            formText: [
                "game_goal_mapping": isChinese
                    ? "拼图行为 -> 识别鸟类外形 -> 触发后续知识学习兴趣。"
                    : "Puzzle actions -> identify bird morphology -> trigger learning interest.",
                "game_core_rules": isChinese
                    ? "每组先拼出图，再读出鸟名；完成后获得下一环节线索。"
                    : "Each pair completes puzzle then reads bird name; completion unlocks next clue.",
                "game_reward_mechanism": isChinese
                    ? "完成前3组优先选择展示顺序并获得奖励贴纸。"
                    : "Top 3 teams choose showcase order first and receive stickers.",
                "game_mission_chain": isChinese
                    ? "任务1 | 拼出鸟图 | 获得鸟名卡\n任务2 | 读出鸟名 | 获得鸟叫线索\n任务3 | 猜测留鸟/候鸟 | 获得分组优先权"
                    : "Mission 1 | Complete puzzle | Unlock bird name card\nMission 2 | Read name aloud | Unlock call clue\nMission 3 | Predict resident/migratory | Unlock grouping priority",
                "game_difficulty_curve_optional": isChinese
                    ? "先单图识别，再混合图快速匹配。"
                    : "From single-image recognition to mixed-image rapid matching."
            ],
            formOptions: [
                "game_progression": "mission"
            ]
        )

        let tContextHook = makeToolkit(
            "故事导入：古元版画里的鸟飞出来了",
            "Story Hook: Birds Fly Out of Ancient Prints",
            "动画展示古元版画中的鸟儿飞出画作，村长发布求助信，召集“鸟巢建筑师”。",
            "Animation: birds fly out from Gu Yuan prints; village chief posts help letter to recruit 'nest architects'.",
            nodeType: EduNodeType.toolkitPerceptionInquiry,
            methodID: "context_hook",
            formText: [
                "context_hook_material": isChinese
                    ? "古元版画鸟主题动画 + 村长求助信"
                    : "Gu Yuan print animation + village chief help letter",
                "context_hook_questions": isChinese
                    ? "1. 鸟儿为什么要在那洲安家？\n2. 你愿意成为哪种鸟的建筑师？\n3. 你们组准备如何帮助它？"
                    : "1. Why do these birds need homes in Nazhou?\n2. Which bird would you like to design for?\n3. How will your team help it?"
            ],
            formOptions: [
                "context_hook_response_pattern": "think_pair_share",
                "context_hook_time_budget": "5min"
            ]
        )

        let kGeographyClimate = makeKnowledge(
            "珠海与那洲的地理气候",
            "Zhuhai & Nazhou Geography-Climate",
            "珠海沿海、温暖湿润、湿地与村庄并存，为不同鸟类提供了多样栖息环境。",
            "Zhuhai is coastal, warm, and humid; wetlands and villages create diverse bird habitats.",
            level: levelUnderstand
        )
        let kResidentMigratory = makeKnowledge(
            "留鸟与候鸟分类",
            "Resident vs Migratory Birds",
            "鸟类按是否长期停留可分留鸟与候鸟，这决定了观察时段与筑巢策略。",
            "Birds are resident or migratory by seasonal stay, shaping observation windows and nesting strategy.",
            level: levelUnderstand
        )
        let kPronunciation = makeKnowledge(
            "7种鸟名读音与识字",
            "Pronunciation of 7 Bird Names",
            "先学会发音与识字，再进行“那洲村里有什么鸟”游戏巩固。",
            "Learners practice pronunciation first, then reinforce with gameplay.",
            level: levelApply
        )

        let tBirdNameGame = makeToolkit(
            "游戏：那洲村里有什么鸟？",
            "Game: What Birds Live in Nazhou?",
            "用鸟名版“萝卜蹲”巩固读音、记忆和快速切换。",
            "Bird-name squat game to reinforce pronunciation, memory, and fast switching.",
            nodeType: EduNodeType.toolkitCommunicationNegotiation,
            methodID: "game_mechanism",
            formText: [
                "game_goal_mapping": isChinese
                    ? "跟读与接龙 -> 加深7种鸟名记忆 -> 为分组建巢任务做准备。"
                    : "Chant-and-pass -> reinforce 7 bird names -> prepare for group nest task.",
                "game_core_rules": isChinese
                    ? "按节奏点名：A蹲完B蹲；错误则全组重来。"
                    : "Rhythmic call chain: A squats then calls B; mistakes reset group turn.",
                "game_reward_mechanism": isChinese
                    ? "连续正确的组获得“观察先锋”徽章。"
                    : "Consecutive-correct teams earn 'Observation Pioneer' badges.",
                "game_level_blueprint": isChinese
                    ? "关卡1 | 读准鸟名\n关卡2 | 读名+判断留鸟/候鸟\n关卡3 | 读名+说出巢型"
                    : "Level 1 | Pronounce names\nLevel 2 | Name + resident/migratory\nLevel 3 | Name + nest type",
                "game_difficulty_curve_optional": isChinese
                    ? "从慢节奏到快节奏，逐步减少提示。"
                    : "Increase rhythm speed and gradually remove prompts."
            ],
            formOptions: [
                "game_progression": "level"
            ]
        )

        let kNestCharacteristics = makeKnowledge(
            "鸟巢特性与巢型",
            "Nest Characteristics & Types",
            "鸟巢常见有碗状、盘状、悬挂巢，不同鸟种对应不同结构与材料需求。",
            "Common nest types include bowl, plate, and hanging; each bird species has different structural needs.",
            level: levelAnalyze
        )
        let kBuildStrategy = makeKnowledge(
            "鸟巢搭建三步策略",
            "Three-step Nest Building Strategy",
            "第一步基础结构；第二步材料填充；第三步创意装饰。三步都需要在任务卡上记录。",
            "Step 1 structure,\n Step 2 material filling,\n Step 3 creative decoration; each step is recorded on task cards.",
            level: levelApply
        )
        let kTaskCard = makeKnowledge(
            "任务卡四步填写",
            "Four-step Worksheet Prompts",
            "结构选择、蓝图与命名、建造日志、成果与期待（含获奖宣言）。",
            "Structure choice, blueprint naming, build log, and final outcomes with award declaration.",
            level: levelCreate
        )

        let kBulbul = makeKnowledge(
            "红耳鹎（留鸟）",
            "Red-whiskered Bulbul (Resident)",
            "留鸟；建议碗状巢。观察重点：枝叶间活动、警戒叫声、隐蔽性需求。",
            "Resident bird; bowl nest recommended. Focus on branch movement, alert calls, and shelter needs.",
            level: levelRemember
        )
        let kDove = makeKnowledge(
            "朱颈斑鸠（留鸟）",
            "Spotted Dove (Resident)",
            "留鸟；建议盘状巢。观察重点：开阔处停留、稳固支撑与安全高度。",
            "Resident bird; plate nest recommended. Focus on open-area perching and stable support.",
            level: levelRemember
        )
        let kStarling = makeKnowledge(
            "黑领椋鸟（留鸟）",
            "Black-collared Starling (Resident)",
            "留鸟；建议悬挂巢。观察重点：群体活动、巢位固定方式与防坠要求。",
            "Resident bird; hanging nest recommended. Focus on flock behavior and anti-drop structure.",
            level: levelRemember
        )
        let kGoshawk = makeKnowledge(
            "凤头鹰（留鸟）",
            "Crested Goshawk (Resident)",
            "留鸟；建议盘状巢。观察重点：高位支撑、稳定受力与隐蔽边界。",
            "Resident bird; plate nest recommended. Focus on elevated support and stable load paths.",
            level: levelRemember
        )
        let kEgret = makeKnowledge(
            "小白鹭（候鸟）",
            "Little Egret (Migratory)",
            "候鸟；建议盘状巢。观察重点：水域活动、季节停留与巢位选择。",
            "Migratory bird; plate nest recommended. Focus on waterside behavior and seasonal stay.",
            level: levelRemember
        )
        let kMallard = makeKnowledge(
            "绿头鸭（候鸟）",
            "Mallard (Migratory)",
            "候鸟；建议碗状巢。观察重点：近水觅食、保温需求与巢体包裹性。",
            "Migratory bird; bowl nest recommended. Focus on near-water feeding and thermal needs.",
            level: levelRemember
        )
        let kWoodSandpiper = makeKnowledge(
            "林鹬（候鸟）",
            "Wood Sandpiper (Migratory)",
            "候鸟；建议碗状巢。观察重点：湿地停歇、轻量结构与隐蔽纹理。",
            "Migratory bird; bowl nest recommended. Focus on wetland stops and lightweight hidden structure.",
            level: levelRemember
        )

        let tBuildWorkshop = makeToolkit(
            "分组任务：两人协作搭建鸟巢",
            "Group Task: Pair Nest Construction",
            "每组围绕目标鸟种完成结构选择、材料建造、创意装饰与任务卡记录。",
            "Each team completes structure choice, material building, creative decoration, and worksheet records.",
            nodeType: EduNodeType.toolkitCommunicationNegotiation,
            methodID: "pogil",
            formText: [
                "pogil_role_dict": isChinese
                    ? "结构设计师 | 决定巢型与基础结构\n材料工程师 | 负责稻秆与连接稳定\n记录员 | 完成四步任务卡并准备展示"
                    : "Structure designer | Decide nest type and base frame\nMaterial engineer | Handle straw filling and stability\nRecorder | Complete 4-step worksheet and showcase prep",
                "pogil_inquiry_ladder": isChinese
                    ? "1. 这只鸟需要什么巢型？\n2. 我们如何用稻秆实现结构稳定？\n3. 我们的创意装饰如何回应鸟的需求？"
                    : "1. What nest type does this bird need?\n2. How do we stabilize with straw materials?\n3. How does our decoration respond to bird needs?",
                "pogil_sheet_focus": isChinese
                    ? "任务卡四步：结构选择 -> 蓝图命名 -> 建造日志 -> 成果与期待。"
                    : "Worksheet 4-step flow: structure -> blueprint naming -> build log -> final outcomes.",
                "pogil_teacher_trigger_optional": isChinese
                    ? "当小组在结构稳定性上连续失败2次时，教师介入示范。"
                    : "Teacher intervenes after two failed stability attempts."
            ],
            formOptions: [
                "pogil_checkpoint": "teacher_gate"
            ]
        )

        let tExhibitionAwards = makeToolkit(
            "展览与颁奖",
            "Exhibition & Awards",
            "把鸟巢安置到展区，完成跨组讲解、互评与颁奖。",
            "Place nests in exhibition space for cross-team walkthrough, peer review, and awards.",
            nodeType: EduNodeType.toolkitCommunicationNegotiation,
            methodID: "world_cafe",
            formText: [
                "cafe_core_question": isChinese
                    ? "你的鸟巢最能回应该鸟哪一种关键需求？"
                    : "Which key need of your bird does this nest address best?",
                "cafe_table_topics": isChinese
                    ? "桌1 | 结构稳定性\n桌2 | 材料适配性\n桌3 | 创意与美感\n桌4 | 对鸟需求的回应度"
                    : "Table 1 | Structural stability\nTable 2 | Material suitability\nTable 3 | Creativity and aesthetics\nTable 4 | Alignment to bird needs",
                "cafe_rotation_plan": isChinese
                    ? "每轮4分钟，顺时针轮转，保留1名“主讲”留桌。"
                    : "4-minute clockwise rotations; one host remains at each table.",
                "cafe_harvest_rule": isChinese
                    ? "每桌输出1条“最优亮点+1条可改进建议”，汇总后颁奖。"
                    : "Each table outputs one top strength + one improvement suggestion for awards.",
                "cafe_output_template_optional": isChinese
                    ? "作品名 | 目标鸟 | 亮点 | 改进建议"
                    : "Artifact | Target Bird | Highlight | Improvement"
            ]
        )

        let tReflection = makeToolkit(
            "课末反思：建造日志与获奖宣言",
            "End Reflection: Build Log & Award Declaration",
            "回顾建造亮点与挑战，形成下一次改进承诺。",
            "Review highlights/challenges and commit to next-round improvements.",
            nodeType: EduNodeType.toolkitRegulationMetacognition,
            methodID: "reflection_protocol",
            formText: [
                "reflect_prompt_group": isChinese
                    ? "回顾今天：我们做得最好的一点是什么？\n最难的地方是什么？\n下次我们准备如何做得更好？"
                    : "Review today: What did we do best?\nWhat was hardest?\nWhat will we improve next time?",
                "reflect_timing": isChinese ? "展览与颁奖后立即进行（8分钟）" : "Immediately after exhibition and awards (8 min)",
                "reflect_kss_keep": isChinese ? "保留：最有效的结构与协作做法" : "Keep: most effective structure and teamwork behaviors",
                "reflect_kss_stop": isChinese ? "停止：导致巢体不稳或沟通低效的做法" : "Stop: unstable build or inefficient communication behaviors",
                "reflect_kss_start": isChinese ? "开始：下一轮先验证结构再装饰" : "Start: validate structure before decoration next round",
                "reflect_action_commitment_optional": isChinese ? "每组写1条可执行改进行动并指定责任人。" : "Each team writes one actionable improvement with owner."
            ],
            formOptions: [
                "reflect_structure_template": "kss",
                "reflect_channel": "written"
            ]
        )

        let tAfterClassObservation = makeToolkit(
            "课后延伸：拍图识鸟（月度）",
            "Post-class Extension: Monthly Photo Bird ID",
            "学生用教师指定的第三方工具在生活中拍图识鸟，持续1个月并在月末分享。",
            "Students use a teacher-selected third-party tool for one month of photo-based bird identification and sharing.",
            nodeType: EduNodeType.toolkitPerceptionInquiry,
            methodID: "field_observation",
            formText: [
                "field_obs_site": isChinese ? "那洲村与周边湿地/社区" : "Nazhou village and nearby wetlands/community",
                "field_obs_focus": isChinese ? "记录鸟种、出现时间、行为线索与环境位置。" : "Record species, appearance time, behavior clues, and location context.",
                "field_obs_sampling_rule": isChinese ? "每周≥2次，每次10分钟，持续1个月。" : "At least 2 times/week, 10 minutes each, for one month.",
                "field_obs_record_template": isChinese ? "日期 | 地点 | 鸟种 | 证据图 | 一句观察描述" : "Date | Site | Species | Photo evidence | One-line observation",
                "field_obs_tool_ref": isChinese ? "教师指定第三方识图工具（班级统一版本）。" : "Teacher-designated third-party image-ID tool (class-standard version).",
                "field_obs_class_dict": isChinese
                    ? "留鸟 | 常年可见，记录稳定活动区域\n候鸟 | 季节性出现，记录来去时间窗口"
                    : "Resident | Seen year-round; record stable activity zones\nMigratory | Seasonal; record arrival/departure windows"
            ],
            formOptions: [
                "field_obs_task_structure": "classification",
                "field_obs_capture": "photo"
            ]
        )

        let tRubric = makeToolkit(
            "课堂评价指标（三维三级）",
            "Class Evaluation Rubric (3D × 3L)",
            "课堂版三维三级：知识理解与运用、技能掌握与实践、情感态度与价值观；等级为初级/良好/优秀。",
            "Classroom 3-dimension/3-level rubric: knowledge use, skill practice, and attitude/value; levels are Basic/Good/Excellent.",
            nodeType: EduNodeType.toolkitRegulationMetacognition,
            methodID: "rubric_checklist",
            formText: [
                "rubric_dimension_dict": isChinese
                    ? "知识理解与运用 | 能说出鸟类分类与巢型依据\n技能掌握与实践 | 能完成稳定结构与材料搭建\n情感态度与价值观 | 能协作并体现生态关怀"
                    : "Knowledge Use | Explain bird classification and nest rationale\nSkill Practice | Build stable structure with suitable materials\nAttitude & Value | Collaborate and show ecological care",
                "rubric_weight_config": isChinese
                    ? "知识理解与运用 | 35\n技能掌握与实践 | 40\n情感态度与价值观 | 25"
                    : "Knowledge Use | 35\nSkill Practice | 40\nAttitude & Value | 25",
                "rubric_level_descriptions": isChinese
                    ? "初级 | 在提示下完成基础识别与搭建\n良好 | 能独立完成并解释主要设计理由\n优秀 | 能迁移知识、优化设计并高质量协作"
                    : "Basic | Complete with prompts\nGood | Independently complete with clear rationale\nExcellent | Transfer knowledge, optimize design, and collaborate effectively",
                "rubric_band_ranges": isChinese
                    ? "初级 | 0-59\n良好 | 60-84\n优秀 | 85-100"
                    : "Basic | 0-59\nGood | 60-84\nExcellent | 85-100",
                "rubric_evidence_library_optional": isChinese
                    ? "证据示例：任务卡填写、鸟巢实物、展览讲解记录。"
                    : "Evidence examples: worksheets, nest artifact, exhibition explanation notes.",
                "rubric_feedback_template_optional": isChinese
                    ? "你们在【维度】表现为【等级】；建议下一步【行动】。"
                    : "In [dimension], your level is [band]; next step: [action]."
            ],
            formOptions: [
                "rubric_levels": "level3",
                "rubric_summary_strategy": "grade_band"
            ]
        )

        let tDashboard = makeToolkit(
            "评价汇总（课中+课后）",
            "Evaluation Summary (In-class + After-class)",
            "汇总课堂评价与月度拍图识鸟数据，形成后续教学改进输入。",
            "Aggregate in-class rubric and monthly photo-ID results as input for follow-up instruction.",
            nodeType: EduNodeType.toolkitRegulationMetacognition,
            methodID: "learning_dashboard",
            formText: [
                "dashboard_metric_dict": isChinese
                    ? "课堂掌握度 | 三维三级课堂评分\n合作表现 | 组内协作观察记录\n延伸参与度 | 月度拍图识鸟提交率"
                    : "Class Mastery | 3D×3L classroom rating\nCollaboration | Teamwork observation logs\nExtension Participation | Monthly photo-ID submission rate",
                "dashboard_source_mapping": isChinese
                    ? "课堂掌握度 | 评价指标节点\n合作表现 | 展览互评+教师观察\n延伸参与度 | 拍图识鸟记录"
                    : "Class Mastery | Rubric node\nCollaboration | Exhibition peer review + teacher notes\nExtension Participation | Photo-ID records",
                "dashboard_alert_threshold": isChinese
                    ? "任一指标连续2次低于60触发复教与小组支持。"
                    : "Any metric below 60 for two cycles triggers reteaching and group support.",
                "dashboard_view_mode_optional": isChinese
                    ? "课次趋势 + 组别对比摘要"
                    : "Lesson trend + group comparison summary"
            ],
            formOptions: [
                "dashboard_cycle": "per_lesson"
            ]
        )

        add(tCheckinGrouping, type: EduNodeType.toolkitCommunicationNegotiation, x: -1700, y: -420, role: "toolkit")
        add(tWarmupPuzzle, type: EduNodeType.toolkitCommunicationNegotiation, x: -1240, y: -420, role: "toolkit")
        add(tContextHook, type: EduNodeType.toolkitPerceptionInquiry, x: -780, y: -420, role: "toolkit")
        add(kGeographyClimate, type: EduNodeType.knowledge, x: -320, y: -420, role: "knowledge")
        add(kResidentMigratory, type: EduNodeType.knowledge, x: 140, y: -420, role: "knowledge")
        add(kPronunciation, type: EduNodeType.knowledge, x: 600, y: -420, role: "knowledge")
        add(tBirdNameGame, type: EduNodeType.toolkitCommunicationNegotiation, x: 1060, y: -420, role: "toolkit")

        let birdColumnX = 1520.0
        add(kBulbul, type: EduNodeType.knowledge, x: birdColumnX, y: -700, role: "knowledge")
        add(kDove, type: EduNodeType.knowledge, x: birdColumnX, y: -520, role: "knowledge")
        add(kStarling, type: EduNodeType.knowledge, x: birdColumnX, y: -340, role: "knowledge")
        add(kGoshawk, type: EduNodeType.knowledge, x: birdColumnX, y: -160, role: "knowledge")
        add(kEgret, type: EduNodeType.knowledge, x: birdColumnX, y: 20, role: "knowledge")
        add(kMallard, type: EduNodeType.knowledge, x: birdColumnX, y: 200, role: "knowledge")
        add(kWoodSandpiper, type: EduNodeType.knowledge, x: birdColumnX, y: 380, role: "knowledge")

        add(kNestCharacteristics, type: EduNodeType.knowledge, x: 1980, y: -420, role: "knowledge")
        add(kBuildStrategy, type: EduNodeType.knowledge, x: 2440, y: -420, role: "knowledge")
        add(kTaskCard, type: EduNodeType.knowledge, x: 2900, y: -420, role: "knowledge")
        add(tBuildWorkshop, type: EduNodeType.toolkitCommunicationNegotiation, x: 3360, y: -420, role: "toolkit")
        add(tExhibitionAwards, type: EduNodeType.toolkitCommunicationNegotiation, x: 3820, y: -420, role: "toolkit")
        add(tReflection, type: EduNodeType.toolkitRegulationMetacognition, x: 4280, y: -420, role: "toolkit")
        add(tAfterClassObservation, type: EduNodeType.toolkitPerceptionInquiry, x: 4740, y: -420, role: "toolkit")

        add(tRubric, type: EduNodeType.toolkitRegulationMetacognition, x: 4280, y: 220, role: "evaluation_metric")
        add(tDashboard, type: EduNodeType.toolkitRegulationMetacognition, x: 4740, y: 220, role: "evaluation_summary")

        connectFirstOutput(from: tCheckinGrouping, to: tWarmupPuzzle, inputIndex: 0, in: graph)
        connectFirstOutput(from: tWarmupPuzzle, to: tContextHook, inputIndex: 0, in: graph)
        connectFirstOutput(from: tContextHook, to: kGeographyClimate, inputIndex: 0, in: graph)
        connectFirstOutput(from: kGeographyClimate, to: kResidentMigratory, inputIndex: 0, in: graph)
        connectFirstOutput(from: kResidentMigratory, to: kPronunciation, inputIndex: 0, in: graph)
        connectFirstOutput(from: kPronunciation, to: tBirdNameGame, inputIndex: 0, in: graph)

        connectFirstOutput(from: tBirdNameGame, to: kBulbul, inputIndex: 0, in: graph)
        connectFirstOutput(from: kBulbul, to: kDove, inputIndex: 0, in: graph)
        connectFirstOutput(from: kDove, to: kStarling, inputIndex: 0, in: graph)
        connectFirstOutput(from: kStarling, to: kGoshawk, inputIndex: 0, in: graph)
        connectFirstOutput(from: kGoshawk, to: kEgret, inputIndex: 0, in: graph)
        connectFirstOutput(from: kEgret, to: kMallard, inputIndex: 0, in: graph)
        connectFirstOutput(from: kMallard, to: kWoodSandpiper, inputIndex: 0, in: graph)

        connectFirstOutput(from: kWoodSandpiper, to: kNestCharacteristics, inputIndex: 0, in: graph)
        connectFirstOutput(from: kNestCharacteristics, to: kBuildStrategy, inputIndex: 0, in: graph)
        connectFirstOutput(from: kBuildStrategy, to: kTaskCard, inputIndex: 0, in: graph)
        connectFirstOutput(from: kTaskCard, to: tBuildWorkshop, inputIndex: 0, in: graph)
        connectFirstOutput(from: tBuildWorkshop, to: tExhibitionAwards, inputIndex: 0, in: graph)
        connectFirstOutput(from: tExhibitionAwards, to: tReflection, inputIndex: 0, in: graph)
        connectFirstOutput(from: tReflection, to: tAfterClassObservation, inputIndex: 0, in: graph)

        connectFirstOutput(from: tBuildWorkshop, to: tRubric, inputIndex: 0, in: graph)
        connectFirstOutput(from: tExhibitionAwards, to: tRubric, inputIndex: 0, in: graph)
        connectFirstOutput(from: tReflection, to: tRubric, inputIndex: 0, in: graph)
        connectFirstOutput(from: tRubric, to: tDashboard, inputIndex: 0, in: graph)
        connectFirstOutput(from: tAfterClassObservation, to: tDashboard, inputIndex: 0, in: graph)

        let serializedNodes = entries.map { entry in
            SerializableNode(from: entry.node, nodeType: entry.type)
        }
        let canvasState = entries.map { entry in
            CanvasNodeState(nodeID: entry.node.id, position: entry.position)
        }

        var document = GNodeDocument(
            nodes: serializedNodes,
            connections: graph.getAllConnections(),
            canvasState: canvasState
        )
        document.metadata.description = "edunode.sample=\(zhuhaiSampleID);edunode.model=inquiry"

        return (try? encodeDocument(document)) ?? Data()
    }

    static func migrateLegacyKnowledgeInputsAndSampleConnectionsIfNeeded(data: Data) -> Data? {
        guard let document = try? decodeDocument(from: data) else { return nil }
        if shouldUpgradeZhuhaiSample(document) {
            return makeZhuhaiBirdSampleDocumentData(isChinese: documentPrefersChinese(document))
        }

        let hasLegacyKnowledge = document.nodes.contains {
            $0.nodeType == EduNodeType.knowledge && $0.inputPorts.count != 1
        }
        let isZhuhai = isZhuhaiSample(document)
        let sampleNeedsRepair = isZhuhai && hasMissingZhuhaiKnowledgeConnections(in: document)
        guard hasLegacyKnowledge || sampleNeedsRepair else { return nil }

        var rebuiltNodes: [SerializableNode] = []
        var rebuiltCanvasState: [CanvasNodeState] = []
        var nodeIDMap: [UUID: UUID] = [:]
        var inputPortIDMap: [UUID: UUID] = [:]
        var outputPortIDMap: [UUID: UUID] = [:]

        for serialized in document.nodes {
            guard let node = try? deserializeNode(serialized) else { return nil }
            let rebuilt = SerializableNode(from: node, nodeType: serialized.nodeType)
            rebuiltNodes.append(rebuilt)
            nodeIDMap[serialized.id] = rebuilt.id

            for (index, port) in serialized.inputPorts.enumerated() where index < rebuilt.inputPorts.count {
                inputPortIDMap[port.id] = rebuilt.inputPorts[index].id
            }
            for (index, port) in serialized.outputPorts.enumerated() where index < rebuilt.outputPorts.count {
                outputPortIDMap[port.id] = rebuilt.outputPorts[index].id
            }
        }

        for state in document.canvasState {
            guard let newNodeID = nodeIDMap[state.nodeID] else { continue }
            rebuiltCanvasState.append(
                CanvasNodeState(
                    nodeID: newNodeID,
                    position: CGPoint(x: state.positionX, y: state.positionY),
                    customName: state.customName
                )
            )
        }

        var rebuiltConnections: [NodeConnection] = []
        for connection in document.connections {
            guard let newSourceNodeID = nodeIDMap[connection.sourceNodeID],
                  let newSourcePortID = outputPortIDMap[connection.sourcePortID],
                  let newTargetNodeID = nodeIDMap[connection.targetNodeID],
                  let newTargetPortID = inputPortIDMap[connection.targetPortID] else {
                continue
            }
            rebuiltConnections.append(
                NodeConnection(
                    sourceNode: newSourceNodeID,
                    sourcePort: newSourcePortID,
                    targetNode: newTargetNodeID,
                    targetPort: newTargetPortID,
                    dataType: connection.dataType
                )
            )
        }

        if isZhuhai {
            addMissingZhuhaiKnowledgeConnections(
                nodes: rebuiltNodes,
                connections: &rebuiltConnections
            )
        }

        var migrated = GNodeDocument(
            nodes: rebuiltNodes,
            connections: rebuiltConnections,
            canvasState: rebuiltCanvasState
        )
        migrated.metadata = document.metadata
        migrated.metadata.modifiedAt = .now
        return (try? encodeDocument(migrated))
    }

    static func filledNodeCount(of type: String, in data: Data) -> Int {
        guard let document = try? decodeDocument(from: data) else { return 0 }
        return document.nodes.reduce(into: 0) { count, node in
            guard node.nodeType == type else { return }
            let textValue = (node.nodeData["content"] ?? node.nodeData["value"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !textValue.isEmpty {
                count += 1
            }
        }
    }

    static func filledToolkitNodeCount(in data: Data) -> Int {
        guard let document = try? decodeDocument(from: data) else { return 0 }
        let types = Set(EduNodeType.allToolkitTypes)
        return document.nodes.reduce(into: 0) { count, node in
            guard types.contains(node.nodeType) else { return }
            let textValue = (node.nodeData["value"] ?? node.nodeData["content"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !textValue.isEmpty {
                count += 1
            }
        }
    }

    static func roles(in data: Data) -> Set<String> {
        guard let document = try? decodeDocument(from: data) else { return [] }
        return Set(document.nodes.compactMap { node in
            parseRole(from: node.attributes.description)
        })
    }

    static func hasRole(_ role: String, in data: Data) -> Bool {
        roles(in: data).contains(role)
    }

    static func hasEvaluationDesign(in data: Data) -> Bool {
        guard let document = try? decodeDocument(from: data) else { return false }

        if document.nodes.contains(where: { node in
            node.nodeType == EduNodeType.evaluation
        }) {
            return true
        }

        // Backward compatibility for legacy evaluation chain and sample roles.
        let roleSet = Set(document.nodes.compactMap { node in
            parseRole(from: node.attributes.description)
        })
        if roleSet.contains("evaluation") {
            return true
        }
        return roleSet.contains("evaluation_metric") && roleSet.contains("evaluation_summary")
    }

    static func isZhuhaiSampleData(_ data: Data) -> Bool {
        guard let document = try? decodeDocument(from: data) else { return false }
        return isZhuhaiSample(document)
    }

    private static func isZhuhaiSample(_ document: GNodeDocument) -> Bool {
        document.metadata.description?.contains("edunode.sample=zhuhai_birds") == true
    }

    private static func shouldUpgradeZhuhaiSample(_ document: GNodeDocument) -> Bool {
        guard isZhuhaiSample(document) else { return false }
        let description = document.metadata.description ?? ""
        guard !description.contains("edunode.sample=\(zhuhaiSampleID)") else { return false }
        if description.contains("edunode.sample=zhuhai_birds_v2") {
            return true
        }
        return legacyZhuhaiNamePrefixes.contains { prefix in
            document.nodes.contains(where: { $0.attributes.name.hasPrefix(prefix) })
        }
    }

    private static func documentPrefersChinese(_ document: GNodeDocument) -> Bool {
        if document.nodes.contains(where: { containsChinese($0.attributes.name) }) {
            return true
        }
        return Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
    }

    private static func containsChinese(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
        }
    }

    private static var legacyZhuhaiNamePrefixes: [String] {
        ["知识点1", "知识点2", "知识点3", "知识点4", "知识点5", "知识点6", "知识点7", "K1:", "K2:", "K3:", "K4:", "K5:", "K6:", "K7:"]
    }

    private static func hasMissingZhuhaiKnowledgeConnections(in document: GNodeDocument) -> Bool {
        let nodes = document.nodes
        guard let k1 = findZhuhaiNode(in: nodes, prefixes: ["知识点1", "K1:"]),
              let k2 = findZhuhaiNode(in: nodes, prefixes: ["知识点2", "K2:"]),
              let k3 = findZhuhaiNode(in: nodes, prefixes: ["知识点3", "K3:"]),
              let k4 = findZhuhaiNode(in: nodes, prefixes: ["知识点4", "K4:"]),
              let k5 = findZhuhaiNode(in: nodes, prefixes: ["知识点5", "K5:"]),
              let k6 = findZhuhaiNode(in: nodes, prefixes: ["知识点6", "K6:"]),
              let k7 = findZhuhaiNode(in: nodes, prefixes: ["知识点7", "K7:"]) else {
            return false
        }

        let existing = Set(document.connections.map { "\($0.sourceNodeID.uuidString)->\($0.targetNodeID.uuidString)" })
        let required = [
            "\(k1.id.uuidString)->\(k2.id.uuidString)",
            "\(k2.id.uuidString)->\(k3.id.uuidString)",
            "\(k3.id.uuidString)->\(k4.id.uuidString)",
            "\(k3.id.uuidString)->\(k5.id.uuidString)",
            "\(k3.id.uuidString)->\(k6.id.uuidString)",
            "\(k3.id.uuidString)->\(k7.id.uuidString)"
        ]

        return required.contains { !existing.contains($0) }
    }

    private static func addMissingZhuhaiKnowledgeConnections(
        nodes: [SerializableNode],
        connections: inout [NodeConnection]
    ) {
        guard let k1 = findZhuhaiNode(in: nodes, prefixes: ["知识点1", "K1:"]),
              let k2 = findZhuhaiNode(in: nodes, prefixes: ["知识点2", "K2:"]),
              let k3 = findZhuhaiNode(in: nodes, prefixes: ["知识点3", "K3:"]),
              let k4 = findZhuhaiNode(in: nodes, prefixes: ["知识点4", "K4:"]),
              let k5 = findZhuhaiNode(in: nodes, prefixes: ["知识点5", "K5:"]),
              let k6 = findZhuhaiNode(in: nodes, prefixes: ["知识点6", "K6:"]),
              let k7 = findZhuhaiNode(in: nodes, prefixes: ["知识点7", "K7:"]) else {
            return
        }

        appendConnectionIfMissing(from: k1, to: k2, targetInputIndex: 0, connections: &connections)
        appendConnectionIfMissing(from: k2, to: k3, targetInputIndex: 0, connections: &connections)
        appendConnectionIfMissing(from: k3, to: k4, targetInputIndex: 0, connections: &connections)
        appendConnectionIfMissing(from: k3, to: k5, targetInputIndex: 0, connections: &connections)
        appendConnectionIfMissing(from: k3, to: k6, targetInputIndex: 0, connections: &connections)
        appendConnectionIfMissing(from: k3, to: k7, targetInputIndex: 0, connections: &connections)
    }

    private static func appendConnectionIfMissing(
        from source: SerializableNode,
        to target: SerializableNode,
        targetInputIndex: Int,
        connections: inout [NodeConnection]
    ) {
        guard source.outputPorts.indices.contains(0),
              target.inputPorts.indices.contains(targetInputIndex) else {
            return
        }
        if connections.contains(where: { $0.sourceNodeID == source.id && $0.targetNodeID == target.id }) {
            return
        }
        connections.append(
            NodeConnection(
                sourceNode: source.id,
                sourcePort: source.outputPorts[0].id,
                targetNode: target.id,
                targetPort: target.inputPorts[targetInputIndex].id,
                dataType: source.outputPorts[0].dataType
            )
        )
    }

    private static func findZhuhaiNode(in nodes: [SerializableNode], prefixes: [String]) -> SerializableNode? {
        nodes.first { node in
            prefixes.contains { prefix in
                node.attributes.name.hasPrefix(prefix)
            }
        }
    }

    private static func keywordScore(input: String, hints: [String]) -> Int {
        guard !input.isEmpty else { return 0 }
        return hints.reduce(into: 0) { partialResult, hint in
            let needle = hint.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if !needle.isEmpty, input.contains(needle) {
                partialResult += 1
            }
        }
    }

    private static func parseRole(from description: String) -> String? {
        guard let range = description.range(of: rolePrefix) else { return nil }
        let role = description[range.upperBound...]
            .split(separator: ";", maxSplits: 1)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let role, !role.isEmpty else { return nil }
        return role
    }

    private static func connectFirstOutput(from source: any GNode, to target: any GNode, inputIndex: Int, in graph: NodeGraph) {
        connectOutput(from: source, outputIndex: 0, to: target, inputIndex: inputIndex, in: graph)
    }

    private static func connectOutput(
        from source: any GNode,
        outputIndex: Int,
        to target: any GNode,
        inputIndex: Int,
        in graph: NodeGraph
    ) {
        guard source.outputs.indices.contains(outputIndex), target.inputs.indices.contains(inputIndex) else { return }
        try? graph.connect(
            from: source.id,
            sourcePort: source.outputs[outputIndex].id,
            to: target.id,
            targetPort: target.inputs[inputIndex].id
        )
    }

    private static func S(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    private static func jsQuoted(_ value: String) -> String {
        let scalar = [value]
        guard let data = try? JSONSerialization.data(withJSONObject: scalar),
              let json = String(data: data, encoding: .utf8),
              let firstQuote = json.firstIndex(of: "\""),
              let lastQuote = json.lastIndex(of: "\""),
              firstQuote < lastQuote else {
            return "\"\""
        }
        return String(json[firstQuote...lastQuote])
    }

    private static let fallbackRulesJSON = """
[
  {
    "id": "ubd",
    "name_en": "Understanding by Design (UbD)",
    "name_zh": "逆向设计（UbD）",
    "description_en": "Design backward from outcomes and evidence, then plan learning experiences.",
    "description_zh": "从目标与证据逆向规划学习体验。",
    "grade_hints": ["middle", "high", "初中", "高中"],
    "subject_hints": ["science", "math", "history", "理", "文"],
    "scenario_hints": ["outcome", "evidence", "标准", "目标", "unit"],
    "toolkit_preset_ids": ["context-hook", "task-driven", "exit-ticket"],
    "template_focus_en": "Desired results, evidence, and aligned learning plan",
    "template_focus_zh": "预期结果、证据与对齐的学习规划"
  },
  {
    "id": "fivee",
    "name_en": "5E Instructional Model",
    "name_zh": "5E 探究模型",
    "description_en": "Use Engage-Explore-Explain-Elaborate-Evaluate as an inquiry sequence.",
    "description_zh": "以 Engage-Explore-Explain-Elaborate-Evaluate 形成探究序列。",
    "grade_hints": ["elementary", "middle", "小学", "初中"],
    "subject_hints": ["science", "physics", "chemistry", "科学", "实验"],
    "scenario_hints": ["inquiry", "experiment", "探究", "实验", "question"],
    "toolkit_preset_ids": ["context-hook", "experiment-observe", "peer-discussion"],
    "template_focus_en": "Question-driven inquiry with progressive explanation and transfer",
    "template_focus_zh": "问题驱动探究并逐步解释与迁移"
  },
  {
    "id": "kolb",
    "name_en": "Kolb Experiential Cycle",
    "name_zh": "Kolb 体验学习循环",
    "description_en": "Learn through a cycle of experience, reflection, conceptualization, and experimentation.",
    "description_zh": "通过体验、反思、概念化与实验形成学习循环。",
    "grade_hints": ["middle", "high", "初中", "高中"],
    "subject_hints": ["project", "practice", "engineering", "综合", "实践"],
    "scenario_hints": ["cycle", "reflection", "iterate", "反思", "迭代"],
    "toolkit_preset_ids": ["experiment-observe", "task-driven", "peer-discussion"],
    "template_focus_en": "Experience-reflection-concept-experiment closed loop",
    "template_focus_zh": "体验-反思-概念-实验闭环"
  },
  {
    "id": "boppps",
    "name_en": "BOPPPS",
    "name_zh": "BOPPPS 模型",
    "description_en": "Bridge-in, Objective, Pre-assessment, Participatory learning, Post-assessment, and Summary.",
    "description_zh": "Bridge-in、Objective、Pre-assessment、Participatory、Post-assessment、Summary 六段短课结构。",
    "grade_hints": ["all", "全学段"],
    "subject_hints": ["language", "math", "science", "语文", "综合"],
    "scenario_hints": ["micro", "short", "workshop", "短课", "微课"],
    "toolkit_preset_ids": ["context-hook", "peer-discussion", "exit-ticket"],
    "template_focus_en": "Concise lesson flow with strong participation and closure",
    "template_focus_zh": "强调参与和收束的单课时流程"
  },
  {
    "id": "gagne9",
    "name_en": "Gagne's Nine Events",
    "name_zh": "加涅九事件教学",
    "description_en": "A highly structured sequence of nine instructional events.",
    "description_zh": "九个教学事件组成的高结构化教学序列。",
    "grade_hints": ["middle", "high", "初中", "高中"],
    "subject_hints": ["math", "science", "technology", "理", "工"],
    "scenario_hints": ["structured", "lecture", "step", "结构化", "讲授"],
    "toolkit_preset_ids": ["context-hook", "contrast-analysis", "exit-ticket"],
    "template_focus_en": "Stepwise event design from attention to transfer",
    "template_focus_zh": "从注意到迁移的步骤化事件设计"
  }
]
"""
}

private struct TemplateLayoutNode {
    let nodeID: UUID
    let column: Int
    let preferredY: Double
    let size: CGSize
    let order: Int
}

private struct TemplateNodeEntry {
    let node: any GNode
    let type: String
    let position: CGPoint
}

private extension EduPlanning {
    static func estimatedTemplateNodeSize(node: any GNode, nodeType: String) -> CGSize {
        let isToolkitNode = nodeType.hasPrefix("EduToolkit")
        let formNode = node as? any NodeFormEditable
        let hasAdvancedToolkitEditors = formNode?.editorFormTextFields.contains(where: { field in
            switch field.editorKind {
            case .tags, .orderedList, .keyValueTable:
                return true
            case .text:
                return false
            }
        }) ?? false

        let width: Double = (isToolkitNode && hasAdvancedToolkitEditors) ? 440 : 220

        var height: Double = 92
        let portRows = max(node.inputs.count, node.outputs.count)
        height += Double(portRows) * 22

        if node is any NodeOptionSelectable {
            height += 44
        }

        if let formNode {
            height += Double(formNode.editorFormOptionFields.count) * 58
            for field in formNode.editorFormTextFields {
                switch field.editorKind {
                case .tags:
                    height += 66
                case .orderedList:
                    height += 110
                case .keyValueTable:
                    height += 148
                case .text:
                    if field.isMultiline {
                        let minLines = max(1, min(field.minVisibleLines, 8))
                        height += Double(minLines) * 20 + 32
                    } else {
                        height += 54
                    }
                }
            }
        }

        if let textNode = node as? any NodeTextEditable {
            if textNode.editorPrefersMultiline {
                let visibleLines = max(2, min(textNode.editorMinVisibleLines + 2, 8))
                height += Double(visibleLines) * 18 + 26
            } else {
                height += 54
            }

            let lineCount = max(1, min(textNode.editorTextValue.components(separatedBy: .newlines).count, 12))
            if lineCount > 1 {
                height += Double(lineCount - 1) * 12
            }
        }

        let clampedHeight = min(max(height, 150), 760)
        return CGSize(width: CGFloat(width), height: CGFloat(clampedHeight))
    }

    static func resolveTemplateLayout(for nodes: [TemplateLayoutNode]) -> [UUID: CGPoint] {
        guard !nodes.isEmpty else { return [:] }

        let sortedColumns = Array(Set(nodes.map(\.column))).sorted()
        var widthByColumn: [Int: CGFloat] = [:]
        for column in sortedColumns {
            let maxWidth = nodes
                .filter { $0.column == column }
                .map(\.size.width)
                .max() ?? 220
            widthByColumn[column] = maxWidth
        }

        let horizontalGap: CGFloat = 180
        var xByColumn: [Int: CGFloat] = [:]
        for (index, column) in sortedColumns.enumerated() {
            if index == 0 {
                xByColumn[column] = 0
                continue
            }
            let prevColumn = sortedColumns[index - 1]
            let prevCenter = xByColumn[prevColumn] ?? 0
            let prevWidth = widthByColumn[prevColumn] ?? 220
            let currentWidth = widthByColumn[column] ?? 220
            xByColumn[column] = prevCenter + prevWidth / 2 + currentWidth / 2 + horizontalGap
        }

        let verticalGap: CGFloat = 72
        var positions: [UUID: CGPoint] = [:]

        for column in sortedColumns {
            let columnNodes = nodes
                .filter { $0.column == column }
                .sorted { lhs, rhs in
                    if lhs.preferredY == rhs.preferredY {
                        return lhs.order < rhs.order
                    }
                    return lhs.preferredY < rhs.preferredY
                }

            var yByNode: [UUID: CGFloat] = [:]
            var previousBottom = -CGFloat.greatestFiniteMagnitude
            for item in columnNodes {
                let halfHeight = item.size.height / 2
                let minCenterY = previousBottom + verticalGap + halfHeight
                let y = max(CGFloat(item.preferredY), minCenterY)
                yByNode[item.nodeID] = y
                previousBottom = y + halfHeight
            }

            let avgPreferred = CGFloat(columnNodes.map(\.preferredY).reduce(0, +)) / CGFloat(max(1, columnNodes.count))
            let avgPlaced = yByNode.values.reduce(0, +) / CGFloat(max(1, yByNode.count))
            let shift = avgPreferred - avgPlaced

            previousBottom = -CGFloat.greatestFiniteMagnitude
            for item in columnNodes {
                let halfHeight = item.size.height / 2
                let current = (yByNode[item.nodeID] ?? CGFloat(item.preferredY)) + shift
                let minCenterY = previousBottom + verticalGap + halfHeight
                let adjustedY = max(current, minCenterY)
                yByNode[item.nodeID] = adjustedY
                previousBottom = adjustedY + halfHeight
            }

            let x = xByColumn[column] ?? 0
            for item in columnNodes {
                positions[item.nodeID] = CGPoint(
                    x: x,
                    y: yByNode[item.nodeID] ?? CGFloat(item.preferredY)
                )
            }
        }

        let collisionPadding: CGFloat = 56
        let sortedNodes = nodes.sorted { $0.order < $1.order }
        for _ in 0..<120 {
            var hasCollision = false

            for i in 0..<sortedNodes.count {
                for j in (i + 1)..<sortedNodes.count {
                    let lhs = sortedNodes[i]
                    let rhs = sortedNodes[j]
                    guard let lhsPos = positions[lhs.nodeID], let rhsPos = positions[rhs.nodeID] else { continue }

                    let lhsRect = CGRect(
                        x: lhsPos.x - lhs.size.width / 2 - collisionPadding / 2,
                        y: lhsPos.y - lhs.size.height / 2 - collisionPadding / 2,
                        width: lhs.size.width + collisionPadding,
                        height: lhs.size.height + collisionPadding
                    )
                    let rhsRect = CGRect(
                        x: rhsPos.x - rhs.size.width / 2 - collisionPadding / 2,
                        y: rhsPos.y - rhs.size.height / 2 - collisionPadding / 2,
                        width: rhs.size.width + collisionPadding,
                        height: rhs.size.height + collisionPadding
                    )

                    guard lhsRect.intersects(rhsRect) else { continue }
                    hasCollision = true

                    let overlapY = min(lhsRect.maxY, rhsRect.maxY) - max(lhsRect.minY, rhsRect.minY)
                    let pushDown = max(CGFloat(24), overlapY + 12)
                    positions[rhs.nodeID] = CGPoint(x: rhsPos.x, y: rhsPos.y + pushDown)
                }
            }

            if !hasCollision {
                break
            }
        }

        if !positions.isEmpty {
            let xs = positions.values.map(\.x)
            let ys = positions.values.map(\.y)
            let shiftX = (xs.min()! + xs.max()!) / 2
            let shiftY = (ys.min()! + ys.max()!) / 2

            for key in positions.keys {
                guard let point = positions[key] else { continue }
                positions[key] = CGPoint(x: point.x - shiftX, y: point.y - shiftY)
            }
        }

        return positions
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
