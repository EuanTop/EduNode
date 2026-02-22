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

        for (index, preset) in selectedPresets.enumerated() {
            let y = -70.0 + Double(index) * 130.0
            let placement = toolkitPlacement(forPresetID: preset.id)
            let toolkitNode: any GNode = {
                if let registered = GNodeNodeKit.gnodeNodeKit.createNode(type: placement.nodeType) {
                    registered.attributes.name = "\(S("template.toolkit")): \(preset.title(isChinese: isChinese))"
                    if let node = registered as? any NodeTextEditable {
                        node.editorTextValue = preset.intent(isChinese: isChinese)
                    }
                    if let node = registered as? EduToolkitNode {
                        node.editorSelectedMethodID = placement.methodID
                    }
                    return registered
                }
                return EduToolkitNode(
                    name: "\(S("template.toolkit")): \(preset.title(isChinese: isChinese))",
                    category: placement.category,
                    value: preset.intent(isChinese: isChinese),
                    selectedMethodID: placement.methodID
                )
            }()
            add(toolkitNode, type: placement.nodeType, x: -220, y: y, role: "toolkit")
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

        for (index, node) in metricNodes.enumerated() {
            connectFirstOutput(from: node, to: metricScript, inputIndex: index, in: graph)
        }

        connectOutput(from: metricScript, outputIndex: 0, to: summaryScript, inputIndex: 0, in: graph)
        connectOutput(from: metricScript, outputIndex: 2, to: summaryScript, inputIndex: 1, in: graph)

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
            "Step 1 structure, Step 2 material filling, Step 3 creative decoration; each step is recorded on task cards.",
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

    private static func modelTemplateConfig(for modelID: String, isChinese: Bool) -> ModelTemplateConfig {
        switch modelID {
        case "collaborative":
            return ModelTemplateConfig(
                toolkitCount: 3,
                knowledgeLevel: S("edu.knowledge.type.apply"),
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
                knowledgeLevel: S("edu.knowledge.type.analyze"),
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
                knowledgeLevel: S("edu.knowledge.type.understand"),
                metricInputs: [
                    ModelMetricInput(key: "knowledge", displayName: S("template.metricKnowledge"), defaultValue: 72),
                    ModelMetricInput(key: "engagement", displayName: S("template.metricEngagement"), defaultValue: 79),
                    ModelMetricInput(key: "participation", displayName: S("template.metricParticipation"), defaultValue: 77)
                ]
            )

        default:
            return ModelTemplateConfig(
                toolkitCount: 3,
                knowledgeLevel: S("edu.knowledge.type.apply"),
                metricInputs: [
                    ModelMetricInput(key: "knowledge", displayName: S("template.metricKnowledge"), defaultValue: 78),
                    ModelMetricInput(key: "engagement", displayName: S("template.metricEngagement"), defaultValue: 82),
                    ModelMetricInput(key: "participation", displayName: S("template.metricParticipation"), defaultValue: 75)
                ]
            )
        }
    }

    private static func toolkitPlacement(forPresetID presetID: String) -> ToolkitPlacement {
        switch presetID {
        case "context-hook":
            return ToolkitPlacement(
                nodeType: EduNodeType.toolkitPerceptionInquiry,
                category: .perceptionInquiry,
                methodID: "context_hook"
            )
        case "experiment-observe":
            return ToolkitPlacement(
                nodeType: EduNodeType.toolkitPerceptionInquiry,
                category: .perceptionInquiry,
                methodID: "field_observation"
            )
        case "peer-discussion":
            return ToolkitPlacement(
                nodeType: EduNodeType.toolkitCommunicationNegotiation,
                category: .communicationNegotiation,
                methodID: "structured_debate"
            )
        case "task-driven":
            return ToolkitPlacement(
                nodeType: EduNodeType.toolkitConstructionPrototype,
                category: .constructionPrototype,
                methodID: "low_fidelity_prototype"
            )
        case "contrast-analysis":
            return ToolkitPlacement(
                nodeType: EduNodeType.toolkitPerceptionInquiry,
                category: .perceptionInquiry,
                methodID: "source_analysis"
            )
        case "exit-ticket":
            return ToolkitPlacement(
                nodeType: EduNodeType.toolkitRegulationMetacognition,
                category: .regulationMetacognition,
                methodID: "reflection_protocol"
            )
        default:
            return ToolkitPlacement(
                nodeType: EduNodeType.toolkitCommunicationNegotiation,
                category: .communicationNegotiation,
                methodID: "role_play"
            )
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

private struct ToolkitPlacement {
    let nodeType: String
    let category: EduToolkitCategory
    let methodID: String
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
