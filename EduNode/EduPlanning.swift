import Foundation
import GNodeKit

enum GradeInputMode: String, CaseIterable {
    case grade
    case age
}

struct CourseCreationDraft {
    var courseName: String = ""
    var gradeInputMode: GradeInputMode = .grade
    var gradeMinText: String = "1"
    var gradeMaxText: String = "1"
    var subject: String = ""
    var lessonDurationMinutesText: String = "45"
    var periodRange: String = ""
    var studentCountText: String = "30"
    var priorAssessmentScoreText: String = "70"
    var assignmentCompletionRateText: String = "75"
    var supportNeedCountText: String = "0"
    var studentSupportNotes: String = ""
    var goals: [String] = []
    var modelID: String = ""
    var leadTeacherCountText: String = "1"
    var assistantTeacherCountText: String = "0"
    var teacherRolePlan: String = ""
    var resourceConstraints: String = ""

    var lessonDurationMinutes: Int {
        max(1, Int(lessonDurationMinutesText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 45)
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
        "priorScore=\(priorAssessmentScore), completion=\(assignmentCompletionRate), supportNeed=\(supportNeedCount), notes=\(studentSupportNotes)"
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

    var isValid: Bool {
        !courseName.trimmed.isEmpty &&
        normalizedGradeRange.0 > 0 &&
        normalizedGradeRange.1 >= normalizedGradeRange.0 &&
        !subject.trimmed.isEmpty &&
        lessonDurationMinutes > 0 &&
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
        var bonusByModelID: [String: Int] = [:]

        if draft.priorAssessmentScore < 55 {
            bonusByModelID["constructivism", default: 0] += 3
            bonusByModelID["collaborative", default: 0] += 1
        } else if draft.priorAssessmentScore < 75 {
            bonusByModelID["constructivism", default: 0] += 1
            bonusByModelID["ubd", default: 0] += 1
        } else {
            bonusByModelID["inquiry", default: 0] += 3
            bonusByModelID["ubd", default: 0] += 2
        }

        if draft.assignmentCompletionRate < 60 {
            bonusByModelID["collaborative", default: 0] += 2
            bonusByModelID["constructivism", default: 0] += 1
        } else if draft.assignmentCompletionRate < 85 {
            bonusByModelID["ubd", default: 0] += 1
        } else {
            bonusByModelID["inquiry", default: 0] += 2
        }

        if draft.supportNeedCount > max(3, draft.studentCount / 5) {
            bonusByModelID["collaborative", default: 0] += 2
        }

        if draft.studentCount >= 36 {
            bonusByModelID["collaborative", default: 0] += 2
        } else if draft.studentCount <= 20 {
            bonusByModelID["inquiry", default: 0] += 1
        }

        let scored = rules.map { rule in
            var score = 0
            score += keywordScore(input: grade, hints: rule.gradeHints) * 2
            score += keywordScore(input: subject, hints: rule.subjectHints) * 3
            score += bonusByModelID[rule.id, default: 0]
            return (rule, score)
        }

        return scored
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 { return lhs.0.id < rhs.0.id }
                return lhs.1 > rhs.1
            }
            .map { $0.0 }
            .prefix(3)
            .map { $0 }
    }

    static func makeInitialDocumentData(
        draft: CourseCreationDraft,
        modelRule: EduModelRule,
        isChinese: Bool
    ) -> Data {
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

        let courseTitle = draft.courseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? S("template.untitledCourse")
            : draft.courseName
        let goalsSummary = draft.goalsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? S("template.noGoals")
            : draft.goalsText
        let modelName = modelRule.displayName(isChinese: isChinese)
        let durationMinutes = draft.lessonDurationMinutes

        let templateConfig = modelTemplateConfig(for: modelRule.id, isChinese: isChinese)

        let knowledgeNode: any GNode = {
            if let registered = GNodeNodeKit.gnodeNodeKit.createNode(type: EduNodeType.knowledge) {
                registered.attributes.name = S("template.knowledge")
                if let node = registered as? EduKnowledgeNode {
                    node.editorTextValue = modelRule.templateFocus(isChinese: isChinese)
                    node.editorSelectedOption = templateConfig.knowledgeLevel
                }
                return registered
            }
            return EduKnowledgeNode(
                name: S("template.knowledge"),
                content: modelRule.templateFocus(isChinese: isChinese),
                level: templateConfig.knowledgeLevel
            )
        }()
        add(knowledgeNode, type: EduNodeType.knowledge, x: -220, y: -210, role: "knowledge")

        let presets = modelRule.toolkitPresetIDs
            .compactMap { presetID in
                toolkitPresets().first(where: { $0.id == presetID })
            }
        let selectedPresets = presets.isEmpty
            ? Array(toolkitPresets().prefix(templateConfig.toolkitCount))
            : Array(presets.prefix(templateConfig.toolkitCount))

        var firstToolkitNode: (any GNode)?

        for (index, preset) in selectedPresets.enumerated() {
            let y = -70.0 + Double(index) * 130.0
            let presetType = toolkitType(forPresetID: preset.id)
            let toolkitNode: any GNode = {
                if let registered = GNodeNodeKit.gnodeNodeKit.createNode(type: EduNodeType.toolkit) {
                    registered.attributes.name = "\(S("template.toolkit")): \(preset.title(isChinese: isChinese))"
                    if let node = registered as? any NodeTextEditable {
                        node.editorTextValue = preset.intent(isChinese: isChinese)
                    }
                    if let node = registered as? any NodeOptionSelectable {
                        node.editorSelectedOption = presetType
                    }
                    return registered
                }
                return EduToolkitNode(
                    name: "\(S("template.toolkit")): \(preset.title(isChinese: isChinese))",
                    value: preset.intent(isChinese: isChinese),
                    selectedType: presetType
                )
            }()
            add(toolkitNode, type: EduNodeType.toolkit, x: -220, y: y, role: "toolkit")
            if firstToolkitNode == nil {
                firstToolkitNode = toolkitNode
            }
        }

        var metricNodes: [any GNode] = []
        for (index, input) in templateConfig.metricInputs.enumerated() {
            let metricNode: any GNode = {
                if let registered = GNodeNodeKit.gnodeNodeKit.createNode(type: EduNodeType.metricValue) {
                    registered.attributes.name = input.displayName
                    if let node = registered as? NumNode {
                        node.setValue(NumData(input.defaultValue))
                    }
                    return registered
                }
                return NumNode(name: input.displayName, value: NumData(input.defaultValue))
            }()
            add(metricNode, type: EduNodeType.metricValue, x: 80, y: -220 + Double(index) * 110.0)
            metricNodes.append(metricNode)
        }

        let metricExpression = metricExpression(
            for: templateConfig.metricInputs,
            modelID: modelRule.id
        )
        let metricScript: any GNode = {
            if let registered = GNodeNodeKit.gnodeNodeKit.createNode(type: EduNodeType.evaluationMetric) {
                registered.attributes.name = S("template.evaluationMetric")
                if let node = registered as? ScriptNode {
                    node.setExpression(metricExpression)
                }
                return registered
            }
            return ScriptNode(name: S("template.evaluationMetric"), expression: metricExpression)
        }()
        add(metricScript, type: EduNodeType.evaluationMetric, x: 360, y: -90, role: "evaluation_metric")

        let summaryExpression = """
		function process(metricScore, metricFocus) {
		    var m = Number(metricScore) || 0;
		    var focusText = String(metricFocus || "");
		    var overall = m;
		    var level = overall >= 85 ? "A" : (overall >= 70 ? "B" : "C");
		    var modelHint = \(jsQuoted(modelRule.templateFocus(isChinese: isChinese)));
		    var summary = modelHint + " | " + focusText;
		    return { overall: overall, level: level, summary: summary };
		}
		"""
        let summaryScript: any GNode = {
            if let registered = GNodeNodeKit.gnodeNodeKit.createNode(type: EduNodeType.evaluationSummary) {
                registered.attributes.name = S("template.evaluationSummary")
                if let node = registered as? ScriptNode {
                    node.setExpression(summaryExpression)
                }
                return registered
            }
            return ScriptNode(name: S("template.evaluationSummary"), expression: summaryExpression)
        }()
        add(summaryScript, type: EduNodeType.evaluationSummary, x: 640, y: -90, role: "evaluation_summary")

        let lessonPlanExpression = """
		function process(summary, knowledge, toolkit) {
			    var title = \(jsQuoted(courseTitle));
			    var goalText = \(jsQuoted(goalsSummary));
			    var duration = \(durationMinutes);
			    var modelName = \(jsQuoted(modelName));
			    var summaryText = String(summary || "Pending");
			    var knowledgeText = String(knowledge || "");
			    var toolkitText = String(toolkit || "");

		    var markdown = "# " + title + "\\n\\n"
		        + "## Teaching Model\\n" + modelName + "\\n\\n"
		        + "## Goals\\n" + goalText + "\\n\\n"
		        + "## Time Boundary\\n" + duration + " minutes\\n\\n"
		        + "## Knowledge Focus\\n" + knowledgeText + "\\n\\n"
		        + "## Toolkit\\n" + toolkitText + "\\n\\n"
		        + "## Evaluation Summary\\n" + summaryText;

	    return { markdown: markdown };
	}
	"""
        let lessonPlanScript: any GNode = {
            if let registered = GNodeNodeKit.gnodeNodeKit.createNode(type: EduNodeType.generateLesson) {
                registered.attributes.name = S("template.lessonPlan")
                if let node = registered as? ScriptNode {
                    node.setExpression(lessonPlanExpression)
                }
                return registered
            }
            return ScriptNode(name: S("template.lessonPlan"), expression: lessonPlanExpression)
        }()
        add(lessonPlanScript, type: EduNodeType.generateLesson, x: 360, y: 210, role: "lesson_plan")

        let exportExpression = """
function process(markdown) {
    var title = \(jsQuoted(courseTitle));
    var md = String(markdown || "");
    var html = "<section><h1>" + title + "</h1><pre>" + md + "</pre></section>";
    return { html: html };
}
"""
        let exportScript: any GNode = {
            if let registered = GNodeNodeKit.gnodeNodeKit.createNode(type: EduNodeType.exportPPT) {
                registered.attributes.name = S("template.exportPPT")
                if let node = registered as? ScriptNode {
                    node.setExpression(exportExpression)
                }
                return registered
            }
            return ScriptNode(name: S("template.exportPPT"), expression: exportExpression)
        }()
        add(exportScript, type: EduNodeType.exportPPT, x: 640, y: 210, role: "export_ppt")

        for (index, node) in metricNodes.enumerated() {
            connectFirstOutput(from: node, to: metricScript, inputIndex: index, in: graph)
        }

        connectOutput(from: metricScript, outputIndex: 0, to: summaryScript, inputIndex: 0, in: graph)
        connectOutput(from: metricScript, outputIndex: 2, to: summaryScript, inputIndex: 1, in: graph)

        connectOutput(from: summaryScript, outputIndex: 2, to: lessonPlanScript, inputIndex: 0, in: graph)
        connectOutput(from: knowledgeNode, outputIndex: 0, to: lessonPlanScript, inputIndex: 1, in: graph)
        if let firstToolkitNode {
            connectFirstOutput(from: firstToolkitNode, to: lessonPlanScript, inputIndex: 2, in: graph)
        }
        connectOutput(from: lessonPlanScript, outputIndex: 0, to: exportScript, inputIndex: 0, in: graph)

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

        let levelBasic = isChinese ? "基础" : "Basic"
        let levelIntermediate = isChinese ? "进阶" : "Intermediate"

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

        func makeToolkit(_ titleZH: String, _ titleEN: String, _ contentZH: String, _ contentEN: String, type: String) -> any GNode {
            let title = isChinese ? titleZH : titleEN
            let content = isChinese ? contentZH : contentEN
            if let registered = GNodeNodeKit.gnodeNodeKit.createNode(type: EduNodeType.toolkit) {
                registered.attributes.name = title
                if let node = registered as? any NodeTextEditable {
                    node.editorTextValue = content
                }
                if let node = registered as? any NodeOptionSelectable {
                    node.editorSelectedOption = type
                }
                return registered
            }
            return EduToolkitNode(
                name: title,
                value: content,
                selectedType: type
            )
        }

        let k1 = makeKnowledge(
            "知识点1：广东珠海的地理气候",
            "K1: Zhuhai Geography & Climate",
            "珠海位于广东南部沿海，气候温暖湿润，适合多种鸟类栖息与迁徙停留。",
            "Zhuhai has a warm and humid coastal climate that supports habitats for many bird species.",
            level: levelBasic
        )
        let k2 = makeKnowledge(
            "知识点2：留鸟与候鸟分类",
            "K2: Resident vs Migratory Birds",
            "根据是否长居本地，鸟类可分为留鸟与候鸟。",
            "Birds can be categorized into resident and migratory types based on seasonal movement.",
            level: levelBasic
        )
        let k3 = makeKnowledge(
            "知识点3：珠海常见鸟学名读音",
            "K3: Pronunciation of Common Bird Names",
            "学习珠海常见鸟类名称读音，便于课堂表达与观察记录。",
            "Practice pronunciation of common bird names used in classroom discussion and observation logs.",
            level: levelIntermediate
        )
        let k4 = makeKnowledge(
            "知识点4：常见候鸟1（示例）",
            "K4: Migratory Bird A",
            "示例候鸟：记录外形、活动时间和栖息地。",
            "Example migratory bird: describe appearance, activity time, and habitat.",
            level: levelIntermediate
        )
        let k5 = makeKnowledge(
            "知识点5：常见候鸟2（示例）",
            "K5: Migratory Bird B",
            "示例候鸟：对比与候鸟1的差异。",
            "Example migratory bird: compare with Migratory Bird A.",
            level: levelIntermediate
        )
        let k6 = makeKnowledge(
            "知识点6：常见留鸟1（示例）",
            "K6: Resident Bird A",
            "示例留鸟：聚焦本地常见特征与行为。",
            "Example resident bird: focus on local traits and behavior.",
            level: levelIntermediate
        )
        let k7 = makeKnowledge(
            "知识点7：常见留鸟2（示例）",
            "K7: Resident Bird B",
            "示例留鸟：与留鸟1进行同类对比。",
            "Example resident bird: compare with Resident Bird A.",
            level: levelIntermediate
        )

        let gameToolkit = makeToolkit(
            "Toolkit：萝卜蹲（读音巩固）",
            "Toolkit: Bird Name Game",
            "游戏规则：用鸟类学名进行“萝卜蹲”，巩固读音与快速辨识。",
            "Use bird names in a quick response game to reinforce pronunciation and recognition.",
            type: S("edu.toolkit.type.game")
        )
        let groupingToolkit = makeToolkit(
            "Toolkit：分层分组任务",
            "Toolkit: Differentiated Group Tasks",
            "按学生年龄或教师手动分组：每组负责1种鸟类，输出观察卡片与口头汇报。",
            "Group by age range or teacher assignment; each group studies one bird and reports observations.",
            type: S("edu.toolkit.type.practice")
        )
        let afterClassToolkit = makeToolkit(
            "Toolkit：拍图识鸟（月度）",
            "Toolkit: Photo Bird ID (Monthly)",
            "课后1个月使用老师指定软件拍图识鸟，累计记录并在月末分享。",
            "For one month, students use the designated app to identify birds from photos and share records.",
            type: S("edu.toolkit.type.observation")
        )

        add(k1, type: EduNodeType.knowledge, x: -620, y: -220, role: "knowledge")
        add(k2, type: EduNodeType.knowledge, x: -360, y: -220, role: "knowledge")
        add(k3, type: EduNodeType.knowledge, x: -100, y: -220, role: "knowledge")
        add(gameToolkit, type: EduNodeType.toolkit, x: 200, y: -220, role: "toolkit")

        add(k4, type: EduNodeType.knowledge, x: 170, y: -80, role: "knowledge")
        add(k5, type: EduNodeType.knowledge, x: 170, y: 20, role: "knowledge")
        add(k6, type: EduNodeType.knowledge, x: 170, y: 120, role: "knowledge")
        add(k7, type: EduNodeType.knowledge, x: 170, y: 220, role: "knowledge")
        add(groupingToolkit, type: EduNodeType.toolkit, x: 500, y: 70, role: "toolkit")
        add(afterClassToolkit, type: EduNodeType.toolkit, x: 790, y: 70, role: "toolkit")

        connectFirstOutput(from: k1, to: k2, inputIndex: 2, in: graph)
        connectFirstOutput(from: k2, to: k3, inputIndex: 2, in: graph)
        connectFirstOutput(from: k3, to: gameToolkit, inputIndex: 0, in: graph)

        connectFirstOutput(from: k3, to: k4, inputIndex: 2, in: graph)
        connectFirstOutput(from: k3, to: k5, inputIndex: 2, in: graph)
        connectFirstOutput(from: k3, to: k6, inputIndex: 2, in: graph)
        connectFirstOutput(from: k3, to: k7, inputIndex: 2, in: graph)

        connectFirstOutput(from: k4, to: groupingToolkit, inputIndex: 0, in: graph)
        connectFirstOutput(from: k5, to: groupingToolkit, inputIndex: 0, in: graph)
        connectFirstOutput(from: k6, to: groupingToolkit, inputIndex: 0, in: graph)
        connectFirstOutput(from: k7, to: groupingToolkit, inputIndex: 0, in: graph)
        connectFirstOutput(from: groupingToolkit, to: afterClassToolkit, inputIndex: 0, in: graph)

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
        document.metadata.description = "edunode.sample=zhuhai_birds;edunode.model=inquiry"

        return (try? encodeDocument(document)) ?? Data()
    }

    static func migrateLegacyKnowledgeInputsAndSampleConnectionsIfNeeded(data: Data) -> Data? {
        guard let document = try? decodeDocument(from: data) else { return nil }
        let hasLegacyKnowledge = document.nodes.contains {
            $0.nodeType == EduNodeType.knowledge && $0.inputPorts.count < 3
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

    static func roles(in data: Data) -> Set<String> {
        guard let document = try? decodeDocument(from: data) else { return [] }
        return Set(document.nodes.compactMap { node in
            parseRole(from: node.attributes.description)
        })
    }

    static func hasRole(_ role: String, in data: Data) -> Bool {
        roles(in: data).contains(role)
    }

    private static func isZhuhaiSample(_ document: GNodeDocument) -> Bool {
        document.metadata.description?.contains("edunode.sample=zhuhai_birds") == true
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

        appendConnectionIfMissing(from: k1, to: k2, targetInputIndex: 2, connections: &connections)
        appendConnectionIfMissing(from: k2, to: k3, targetInputIndex: 2, connections: &connections)
        appendConnectionIfMissing(from: k3, to: k4, targetInputIndex: 2, connections: &connections)
        appendConnectionIfMissing(from: k3, to: k5, targetInputIndex: 2, connections: &connections)
        appendConnectionIfMissing(from: k3, to: k6, targetInputIndex: 2, connections: &connections)
        appendConnectionIfMissing(from: k3, to: k7, targetInputIndex: 2, connections: &connections)
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

    private static func modelTemplateConfig(for modelID: String, isChinese: Bool) -> ModelTemplateConfig {
        switch modelID {
        case "collaborative":
            return ModelTemplateConfig(
                toolkitCount: 3,
                knowledgeLevel: isChinese ? "进阶" : "Intermediate",
                metricInputs: [
                    ModelMetricInput(key: "knowledge", displayName: S("template.metricKnowledge"), defaultValue: 74),
                    ModelMetricInput(key: "engagement", displayName: S("template.metricEngagement"), defaultValue: 81),
                    ModelMetricInput(key: "participation", displayName: S("template.metricParticipation"), defaultValue: 83),
                    ModelMetricInput(key: "collaboration", displayName: S("template.metricCollaboration"), defaultValue: 80)
                ]
            )

        case "inquiry":
            return ModelTemplateConfig(
                toolkitCount: 3,
                knowledgeLevel: isChinese ? "高阶" : "Advanced",
                metricInputs: [
                    ModelMetricInput(key: "knowledge", displayName: S("template.metricKnowledge"), defaultValue: 76),
                    ModelMetricInput(key: "engagement", displayName: S("template.metricEngagement"), defaultValue: 78),
                    ModelMetricInput(key: "participation", displayName: S("template.metricParticipation"), defaultValue: 79),
                    ModelMetricInput(key: "questioning", displayName: S("template.metricQuestioning"), defaultValue: 82)
                ]
            )

        case "constructivism":
            return ModelTemplateConfig(
                toolkitCount: 3,
                knowledgeLevel: isChinese ? "基础" : "Basic",
                metricInputs: [
                    ModelMetricInput(key: "knowledge", displayName: S("template.metricKnowledge"), defaultValue: 72),
                    ModelMetricInput(key: "engagement", displayName: S("template.metricEngagement"), defaultValue: 79),
                    ModelMetricInput(key: "participation", displayName: S("template.metricParticipation"), defaultValue: 77)
                ]
            )

        default:
            return ModelTemplateConfig(
                toolkitCount: 3,
                knowledgeLevel: isChinese ? "进阶" : "Intermediate",
                metricInputs: [
                    ModelMetricInput(key: "knowledge", displayName: S("template.metricKnowledge"), defaultValue: 78),
                    ModelMetricInput(key: "engagement", displayName: S("template.metricEngagement"), defaultValue: 82),
                    ModelMetricInput(key: "participation", displayName: S("template.metricParticipation"), defaultValue: 75)
                ]
            )
        }
    }

    private static func toolkitType(forPresetID presetID: String) -> String {
        switch presetID {
        case "context-hook":
            return S("edu.toolkit.type.demonstration")
        case "experiment-observe":
            return S("edu.toolkit.type.observation")
        case "peer-discussion":
            return S("edu.toolkit.type.discussion")
        case "task-driven":
            return S("edu.toolkit.type.practice")
        case "contrast-analysis":
            return S("edu.toolkit.type.inquiry")
        case "exit-ticket":
            return S("edu.toolkit.type.peerReview")
        default:
            return EduToolkitNode.defaultType
        }
    }

    private static func metricExpression(for inputs: [ModelMetricInput], modelID: String) -> String {
        let parameterList = inputs.map(\.key).joined(separator: ", ")
        let valueLines = inputs.map { input in
            "    var \(input.key)Value = Number(\(input.key)) || 0;"
        }.joined(separator: "\n")

        let weights: [Double]
        switch modelID {
        case "collaborative":
            weights = [0.30, 0.20, 0.25, 0.25]
        case "inquiry":
            weights = [0.35, 0.20, 0.25, 0.20]
        case "constructivism":
            weights = [0.45, 0.35, 0.20]
        default:
            weights = [0.55, 0.25, 0.20]
        }

        let normalizedWeights: [Double]
        if weights.count == inputs.count {
            normalizedWeights = weights
        } else {
            normalizedWeights = Array(repeating: 1.0 / Double(max(1, inputs.count)), count: inputs.count)
        }

        let scoreExpr = zip(inputs, normalizedWeights)
            .map { input, weight in "\(input.key)Value * \(String(format: "%.4f", weight))" }
            .joined(separator: " + ")
        let labelsArray = "[\(inputs.map { jsQuoted($0.displayName) }.joined(separator: ", "))]"
        let valuesArray = "[\(inputs.map { "\($0.key)Value" }.joined(separator: ", "))]"

        return """
function process(\(parameterList)) {
\(valueLines)
    var score = \(scoreExpr);
    var level = score >= 85 ? "A" : (score >= 70 ? "B" : "C");
    var labels = \(labelsArray);
    var values = \(valuesArray);
    var weakIndex = 0;
    for (var i = 1; i < values.length; i++) {
        if (values[i] < values[weakIndex]) weakIndex = i;
    }
    var focus = labels.length > 0 ? labels[weakIndex] : "General";
    return { score: score, level: level, focus: focus };
}
"""
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
    "description_en": "Start from outcomes and evidence, then design learning activities.",
    "description_zh": "先确定目标和证据，再反推教学活动。",
    "grade_hints": ["middle", "high", "初中", "高中"],
    "subject_hints": ["science", "math", "history", "理", "文"],
    "scenario_hints": ["formal", "class", "课堂"],
    "toolkit_preset_ids": ["context-hook", "contrast-analysis", "exit-ticket"],
    "template_focus_en": "Core understanding and transfer evidence",
    "template_focus_zh": "核心理解与迁移证据"
  },
  {
    "id": "constructivism",
    "name_en": "Constructivism",
    "name_zh": "建构主义",
    "description_en": "Build new knowledge from prior ideas through interaction.",
    "description_zh": "通过互动在原有认知上建构新知识。",
    "grade_hints": ["elementary", "middle", "小学", "初中"],
    "subject_hints": ["language", "social", "语文", "社会"],
    "scenario_hints": ["workshop", "discussion", "研讨", "讨论"],
    "toolkit_preset_ids": ["context-hook", "peer-discussion", "task-driven"],
    "template_focus_en": "Activate prior concept and reconstruct understanding",
    "template_focus_zh": "激活旧知并重构新概念"
  },
  {
    "id": "inquiry",
    "name_en": "Inquiry-Based Learning",
    "name_zh": "探究式学习",
    "description_en": "Use questions and investigation cycles to drive learning.",
    "description_zh": "以问题和探究循环驱动学习。",
    "grade_hints": ["middle", "high", "初中", "高中"],
    "subject_hints": ["science", "lab", "physics", "chemistry", "科学", "实验"],
    "scenario_hints": ["lab", "project", "实验", "项目"],
    "toolkit_preset_ids": ["experiment-observe", "peer-discussion", "exit-ticket"],
    "template_focus_en": "Question formation and evidence-based explanation",
    "template_focus_zh": "问题提出与证据解释"
  },
  {
    "id": "collaborative",
    "name_en": "Collaborative Learning",
    "name_zh": "合作学习",
    "description_en": "Improve outcomes with structured collaboration and peer support.",
    "description_zh": "通过结构化协作与互助提升学习成效。",
    "grade_hints": ["all", "全学段"],
    "subject_hints": ["language", "project", "综合", "语文"],
    "scenario_hints": ["class", "workshop", "课堂", "workshop"],
    "toolkit_preset_ids": ["peer-discussion", "task-driven", "exit-ticket"],
    "template_focus_en": "Shared task and peer feedback loop",
    "template_focus_zh": "共同任务与同伴反馈闭环"
  }
]
"""
}

private struct ModelMetricInput {
    let key: String
    let displayName: String
    let defaultValue: Double
}

private struct ModelTemplateConfig {
    let toolkitCount: Int
    let knowledgeLevel: String
    let metricInputs: [ModelMetricInput]
}

private struct TemplateNodeEntry {
    let node: any GNode
    let type: String
    let position: CGPoint
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
