import Foundation
import GNodeKit

final class EduTextNode: GNode, NodeTextEditable {
    let id: UUID
    var attributes: NodeAttributes
    var inputs: [AnyInputPort]
    var outputs: [AnyOutputPort]

    private var userValue: StringData
    private let placeholder: String

    init(name: String, value: String = "", outputName: String, placeholder: String) {
        self.id = UUID()
        self.attributes = NodeAttributes(name: name)
        self.inputs = []
        self.outputs = [AnyOutputPort(name: outputName, dataType: "String")]
        self.userValue = StringData(value)
        self.placeholder = placeholder
    }

    func process() throws {
        guard attributes.isRun else {
            throw GNodeError.nodeDisabled(id: id)
        }
        try outputs[0].setValue(userValue)
    }

    func canExecute() -> Bool {
        attributes.isRun
    }

    var editorTextValue: String {
        get { userValue.value }
        set { userValue = StringData(newValue) }
    }

    var editorTextPlaceholder: String {
        placeholder
    }
}

final class EduKnowledgeNode: GNode, NodeTextEditable, NodeOptionSelectable {
    let id: UUID
    var attributes: NodeAttributes
    var inputs: [AnyInputPort]
    var outputs: [AnyOutputPort]

    private var content: StringData
    private var knowledgeType: String

    init(name: String, content: String = "", level: String = EduKnowledgeNode.defaultLevel) {
        self.id = UUID()
        self.attributes = NodeAttributes(name: name)
        self.inputs = [
            AnyInputPort(name: S("edu.knowledge.input.previous"), dataType: "Any", allowsMultipleConnections: true)
        ]
        self.outputs = [
            AnyOutputPort(name: S("edu.knowledge.output.content"), dataType: "String"),
            AnyOutputPort(name: S("edu.knowledge.output.level"), dataType: "String")
        ]
        self.content = StringData(content)
        self.knowledgeType = Self.canonicalKnowledgeType(from: level)
    }

    func process() throws {
        guard attributes.isRun else {
            throw GNodeError.nodeDisabled(id: id)
        }

        let previousContent = normalizedStringInput(at: 0)

        let localContent = content.value.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedContent = !localContent.isEmpty ? localContent : previousContent
        knowledgeType = Self.canonicalKnowledgeType(from: knowledgeType)

        try outputs[0].setValue(StringData(resolvedContent))
        try outputs[1].setValue(StringData(knowledgeType))
    }

    func canExecute() -> Bool {
        attributes.isRun
    }

    var editorTextValue: String {
        get { content.value }
        set { content = StringData(newValue) }
    }

    var editorTextPlaceholder: String {
        S("edu.knowledge.placeholder")
    }

    var editorPrefersMultiline: Bool {
        true
    }

    var editorMinVisibleLines: Int {
        1
    }

    var editorSelectedOption: String {
        get { knowledgeType }
        set {
            knowledgeType = Self.canonicalKnowledgeType(from: newValue)
        }
    }

    var editorOptionLabel: String {
        S("edu.knowledge.type.label")
    }

    var editorOptions: [String] {
        Self.levelOptions
    }

    static var levelOptions: [String] {
        [
            S("edu.knowledge.type.remember"),
            S("edu.knowledge.type.understand"),
            S("edu.knowledge.type.apply"),
            S("edu.knowledge.type.analyze"),
            S("edu.knowledge.type.evaluate"),
            S("edu.knowledge.type.create")
        ]
    }

    static var defaultLevel: String {
        levelOptions[0]
    }

    private func normalizedStringInput(at index: Int) -> String {
        guard inputs.indices.contains(index) else { return "" }
        guard let raw = stringValue(from: inputs[index]) else { return "" }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stringValue(from input: AnyInputPort) -> String? {
        if let value: StringData = ((try? input.getValue()) ?? nil) {
            return value.value
        }
        if let value: NumData = ((try? input.getValue()) ?? nil) {
            let number = value.toDouble()
            return number == number.rounded() ? "\(Int(number))" : "\(number)"
        }
        if let value: BoolData = ((try? input.getValue()) ?? nil) {
            return value.value ? "true" : "false"
        }
        if let value: ArrayData = ((try? input.getValue()) ?? nil) {
            return value.values
                .map { number in
                    number == number.rounded() ? "\(Int(number))" : "\(number)"
                }
                .joined(separator: ", ")
        }
        if let value: ObjectData = ((try? input.getValue()) ?? nil) {
            let fields = value.keys.map { key -> String in
                let display = value.get(key)?.displayString() ?? ""
                return "\(key): \(display)"
            }
            return "{\(fields.joined(separator: ", "))}"
        }
        return nil
    }

    private static func canonicalKnowledgeTypeIfValid(from raw: String) -> String? {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }

        let rememberTokens = ["remember", "remembering", "记忆", "识记"]
        if rememberTokens.contains(where: { normalized.contains($0) }) {
            return S("edu.knowledge.type.remember")
        }

        let understandTokens = ["understand", "understanding", "理解"]
        if understandTokens.contains(where: { normalized.contains($0) }) {
            return S("edu.knowledge.type.understand")
        }

        let applyTokens = ["apply", "applying", "应用"]
        if applyTokens.contains(where: { normalized.contains($0) }) {
            return S("edu.knowledge.type.apply")
        }

        let analyzeTokens = ["analyze", "analyse", "analyzing", "analysing", "分析"]
        if analyzeTokens.contains(where: { normalized.contains($0) }) {
            return S("edu.knowledge.type.analyze")
        }

        let evaluateTokens = ["evaluate", "evaluating", "评估", "评价"]
        if evaluateTokens.contains(where: { normalized.contains($0) }) {
            return S("edu.knowledge.type.evaluate")
        }

        let createTokens = ["create", "creating", "创新", "创造"]
        if createTokens.contains(where: { normalized.contains($0) }) {
            return S("edu.knowledge.type.create")
        }

        // Legacy values migration.
        let legacyBasicTokens = ["basic", "基础", "初级", "low"]
        if legacyBasicTokens.contains(where: { normalized.contains($0) }) {
            return S("edu.knowledge.type.remember")
        }
        let legacyIntermediateTokens = ["intermediate", "进阶", "中级", "medium"]
        if legacyIntermediateTokens.contains(where: { normalized.contains($0) }) {
            return S("edu.knowledge.type.understand")
        }
        let legacyAdvancedTokens = ["advanced", "高阶", "高级", "high"]
        if legacyAdvancedTokens.contains(where: { normalized.contains($0) }) {
            return S("edu.knowledge.type.analyze")
        }

        if levelOptions.contains(raw) {
            return raw
        }

        return nil
    }

    private static func canonicalKnowledgeType(from raw: String) -> String {
        canonicalKnowledgeTypeIfValid(from: raw) ?? defaultLevel
    }
}

enum EduToolkitCategory: String, CaseIterable {
    case perceptionInquiry
    case constructionPrototype
    case communicationNegotiation
    case regulationMetacognition

    struct Method {
        let id: String
        let titleKey: String
    }

    var methods: [Method] {
        switch self {
        case .perceptionInquiry:
            return [
                Method(id: "context_hook", titleKey: "edu.toolkit.perception.method.contextHook"),
                Method(id: "field_observation", titleKey: "edu.toolkit.perception.method.fieldObservation"),
                Method(id: "source_analysis", titleKey: "edu.toolkit.perception.method.sourceAnalysis"),
                Method(id: "sensor_probe", titleKey: "edu.toolkit.perception.method.sensorProbe"),
                Method(id: "immersive_simulation", titleKey: "edu.toolkit.perception.method.immersiveSimulation")
            ]
        case .constructionPrototype:
            return [
                Method(id: "low_fidelity_prototype", titleKey: "edu.toolkit.construction.method.lowFidelityPrototype"),
                Method(id: "physical_computing", titleKey: "edu.toolkit.construction.method.physicalComputing"),
                Method(id: "story_construction", titleKey: "edu.toolkit.construction.method.storyConstruction"),
                Method(id: "service_blueprint", titleKey: "edu.toolkit.construction.method.serviceBlueprint"),
                Method(id: "adaptive_learning_platform", titleKey: "edu.toolkit.construction.method.adaptiveLearningPlatform")
            ]
        case .communicationNegotiation:
            return [
                Method(id: "role_play", titleKey: "edu.toolkit.communication.method.rolePlay"),
                Method(id: "structured_debate", titleKey: "edu.toolkit.communication.method.structuredDebate"),
                Method(id: "world_cafe", titleKey: "edu.toolkit.communication.method.worldCafe"),
                Method(id: "game_mechanism", titleKey: "edu.toolkit.communication.method.gameMechanism"),
                Method(id: "pogil", titleKey: "edu.toolkit.communication.method.pogil")
            ]
        case .regulationMetacognition:
            return [
                Method(id: "kanban_monitoring", titleKey: "edu.toolkit.regulation.method.kanbanMonitoring"),
                Method(id: "reflection_protocol", titleKey: "edu.toolkit.regulation.method.reflectionProtocol"),
                Method(id: "metacognitive_routine", titleKey: "edu.toolkit.regulation.method.metacognitiveRoutine")
            ]
        }
    }

    var defaultMethodID: String {
        methods.first?.id ?? ""
    }

    func localizedMethodTitle(for methodID: String) -> String {
        guard let method = methods.first(where: { $0.id == methodID }) else {
            return S(methods.first?.titleKey ?? "")
        }
        return S(method.titleKey)
    }

    func methodID(forLocalizedTitle title: String) -> String? {
        methods.first(where: { S($0.titleKey) == title })?.id
    }

    var localizedMethodOptions: [String] {
        methods.map { S($0.titleKey) }
    }

    static func fromNodeType(_ nodeType: String) -> EduToolkitCategory? {
        switch nodeType {
        case EduNodeType.toolkitPerceptionInquiry:
            return .perceptionInquiry
        case EduNodeType.toolkitConstructionPrototype:
            return .constructionPrototype
        case EduNodeType.toolkitCommunicationNegotiation:
            return .communicationNegotiation
        case EduNodeType.toolkitRegulationMetacognition:
            return .regulationMetacognition
        default:
            return nil
        }
    }
}

final class EduToolkitNode: GNode, NodeOptionSelectable, NodeMethodSelectable, NodeFormEditable {
    let id: UUID
    var attributes: NodeAttributes
    var inputs: [AnyInputPort]
    var outputs: [AnyOutputPort]

    let category: EduToolkitCategory
    private var methodID: String
    private var textFieldValues: [String: String]
    private var optionFieldValues: [String: String] // stores option choice IDs

    private struct OptionChoice {
        let id: String
        let titleEn: String
        let titleZh: String
    }

    private struct TextFieldDefinition {
        let id: String
        let label: String
        let placeholder: String
        let isMultiline: Bool
        let minVisibleLines: Int
        let editorKind: NodeEditorTextFieldSpec.EditorKind
        let tableColumnTitles: [String]
        let isOptional: Bool
    }

    private struct OptionFieldDefinition {
        let id: String
        let label: String
        let options: [OptionChoice]
        let isOptional: Bool
    }

    private struct MethodSchema {
        let textFields: [TextFieldDefinition]
        let optionFields: [OptionFieldDefinition]
    }

    init(
        name: String,
        category: EduToolkitCategory,
        value: String = "",
        selectedMethodID: String? = nil,
        selectedType: String? = nil,
        textFieldValues: [String: String] = [:],
        optionFieldValues: [String: String] = [:]
    ) {
        self.id = UUID()
        self.attributes = NodeAttributes(name: name)
        self.category = category
        self.methodID = Self.resolveMethodID(
            category: category,
            selectedMethodID: selectedMethodID,
            selectedType: selectedType
        )
        self.textFieldValues = textFieldValues
        self.optionFieldValues = optionFieldValues
        self.inputs = [
            AnyInputPort(name: S("edu.toolkit.input.knowledge"), dataType: "Any", allowsMultipleConnections: true)
        ]
        self.outputs = [
            AnyOutputPort(name: S("edu.output.toolkit"), dataType: "String"),
            AnyOutputPort(name: S("edu.toolkit.output.type"), dataType: "String")
        ]
        applyOptionDefaultsIfNeeded()
        applyLegacyValueIfNeeded(value)
        normalizeStoredTextFieldValues()
    }

    func process() throws {
        guard attributes.isRun else {
            throw GNodeError.nodeDisabled(id: id)
        }

        let knowledgeInput = normalizedStringInput(at: 0)
        let schema = activeSchema
        var lines: [String] = []

        if !knowledgeInput.isEmpty {
            lines.append(knowledgeInput)
        }

        for field in schema.textFields {
            let raw = textFieldValues[field.id] ?? ""
            let resolved = normalizedFieldValue(raw, fieldID: field.id)
            textFieldValues[field.id] = resolved
            appendLineIfNeeded(&lines, label: field.label, value: resolved)
        }

        for field in schema.optionFields {
            let chosenChoiceID: String
            if let stored = resolvedStoredChoiceID(fromStored: optionFieldValues[field.id], in: field.options) {
                chosenChoiceID = stored
            } else {
                chosenChoiceID = field.options.first?.id ?? ""
            }

            optionFieldValues[field.id] = chosenChoiceID
            let display = localizedChoiceTitle(for: chosenChoiceID, in: field.options)
            appendLineIfNeeded(&lines, label: field.label, value: display)
        }

        let resolvedText = lines.joined(separator: "\n")
        try outputs[0].setValue(StringData(resolvedText))
        try outputs[1].setValue(StringData(category.localizedMethodTitle(for: methodID)))
    }

    func canExecute() -> Bool {
        attributes.isRun
    }

    var editorSelectedOption: String {
        get { category.localizedMethodTitle(for: methodID) }
        set {
            if let localizedMatch = category.methodID(forLocalizedTitle: newValue) {
                applyMethodSelection(localizedMatch)
                return
            }
            guard category.methods.contains(where: { $0.id == newValue }) else { return }
            applyMethodSelection(newValue)
        }
    }

    var editorOptionLabel: String {
        S("edu.toolkit.method.label")
    }

    var editorOptions: [String] {
        category.localizedMethodOptions
    }

    var editorSelectedMethodID: String {
        get { methodID }
        set {
            guard category.methods.contains(where: { $0.id == newValue }) else { return }
            applyMethodSelection(newValue)
        }
    }

    var editorFormTextFields: [NodeEditorTextFieldSpec] {
        activeSchema.textFields.map { field in
            NodeEditorTextFieldSpec(
                id: field.id,
                label: field.label,
                placeholder: field.placeholder,
                value: textFieldValues[field.id] ?? "",
                isMultiline: field.isMultiline,
                minVisibleLines: field.minVisibleLines,
                inputMode: .textOnly,
                editorKind: field.editorKind,
                tableColumnTitles: field.tableColumnTitles,
                isOptional: field.isOptional
            )
        }
    }

    var editorFormOptionFields: [NodeEditorOptionFieldSpec] {
        activeSchema.optionFields.map { field in
            let selectedID = resolvedStoredChoiceID(fromStored: optionFieldValues[field.id], in: field.options)
                ?? field.options.first?.id
                ?? ""
            return NodeEditorOptionFieldSpec(
                id: field.id,
                label: field.label,
                options: field.options.map { localizedChoiceTitle(for: $0.id, in: field.options) },
                selectedOption: localizedChoiceTitle(for: selectedID, in: field.options),
                inputMode: .textOnly,
                isOptional: field.isOptional
            )
        }
    }

    func setEditorFormTextFieldValue(_ value: String, for fieldID: String) {
        guard activeSchema.textFields.contains(where: { $0.id == fieldID }) else { return }
        textFieldValues[fieldID] = value
    }

    func setEditorFormOptionValue(_ value: String, for fieldID: String) {
        guard let field = activeSchema.optionFields.first(where: { $0.id == fieldID }) else { return }
        guard let choice = choiceID(for: value, in: field.options) else { return }
        optionFieldValues[fieldID] = choice
        applyOptionDefaultsIfNeeded()
    }

    var serializedMethodID: String {
        methodID
    }

    var serializedCategoryID: String {
        category.rawValue
    }

    var serializedTextFieldValues: [String: String] {
        textFieldValues
    }

    var serializedOptionFieldValues: [String: String] {
        optionFieldValues
    }

    private var activeSchema: MethodSchema {
        methodSchema(for: methodID)
    }

    private var isChineseUI: Bool {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
    }

    private func L(_ en: String, _ zh: String) -> String {
        isChineseUI ? zh : en
    }

    private func option(_ id: String, _ en: String, _ zh: String) -> OptionChoice {
        OptionChoice(id: id, titleEn: en, titleZh: zh)
    }

    private func textField(
        _ id: String,
        enLabel: String,
        zhLabel: String,
        enPlaceholder: String,
        zhPlaceholder: String,
        multiline: Bool = true,
        minLines: Int = 1,
        optional: Bool? = nil
    ) -> TextFieldDefinition {
        let resolvedOptional = optional ?? inferredOptional(
            id: id,
            enLabel: enLabel,
            zhLabel: zhLabel
        )
        let kind = editorKind(for: id)
        return TextFieldDefinition(
            id: id,
            label: L(enLabel, zhLabel),
            placeholder: L(enPlaceholder, zhPlaceholder),
            isMultiline: multiline,
            minVisibleLines: minLines,
            editorKind: kind,
            tableColumnTitles: tableColumnTitles(for: id),
            isOptional: resolvedOptional
        )
    }

    private func optionField(
        _ id: String,
        enLabel: String,
        zhLabel: String,
        options: [OptionChoice],
        optional: Bool? = nil
    ) -> OptionFieldDefinition {
        let resolvedOptional = optional ?? inferredOptional(
            id: id,
            enLabel: enLabel,
            zhLabel: zhLabel
        )
        return OptionFieldDefinition(
            id: id,
            label: L(enLabel, zhLabel),
            options: options,
            isOptional: resolvedOptional
        )
    }

    private func inferredOptional(id: String, enLabel: String, zhLabel: String) -> Bool {
        id.hasSuffix("_optional")
            || enLabel.lowercased().contains("optional")
            || zhLabel.contains("可选")
    }

    private func editorKind(for fieldID: String) -> NodeEditorTextFieldSpec.EditorKind {
        let tagFields: Set<String> = [
            "story_keywords",
            "phycomp_modules",
            "kanban_columns"
        ]
        if tagFields.contains(fieldID) {
            return .tags
        }

        let orderedFields: Set<String> = [
            "story_mainline"
        ]
        if orderedFields.contains(fieldID) {
            return .orderedList
        }

        if tableColumnTitles(for: fieldID).count == 2 {
            return .keyValueTable
        }

        return .text
    }

    private func tableColumnTitles(for fieldID: String) -> [String] {
        switch fieldID {
        case "service_object_dict", "roleplay_role_dict", "pogil_role_dict":
            return [L("Name", "名称"), L("Responsibility", "职责")]
        case "source_analysis_matrix":
            return [L("Claim", "主张"), L("Evidence", "证据")]
        case "field_obs_class_dict":
            return [L("Category", "类别"), L("Criteria", "判定标准")]
        case "field_obs_event_dict":
            return [L("Event", "事件"), L("Trigger", "触发条件")]
        case "field_obs_stage_dict":
            return [L("Stage", "阶段"), L("Completion", "完成标志")]
        case "field_obs_compare_metrics":
            return [L("Metric", "指标"), L("Rule", "记录规则")]
        case "rubric_dimension_dict":
            return [L("Dimension", "维度"), L("Definition", "定义")]
        case "rubric_weight_config":
            return [L("Dimension", "维度"), L("Weight", "权重")]
        case "dashboard_metric_dict":
            return [L("Metric", "指标"), L("Meaning", "含义")]
        case "dashboard_source_mapping":
            return [L("Metric", "指标"), L("Source", "来源")]
        case "meta_monitor_signals":
            return [L("Signal", "信号"), L("Action", "行动")]
        default:
            return []
        }
    }

    private func methodSchema(for methodID: String) -> MethodSchema {
        switch methodID {
        case "context_hook":
            let textFields = [
                textField(
                    "context_hook_material",
                    enLabel: "Trigger Material",
                    zhLabel: "触发材料",
                    enPlaceholder: "Image, clip, object, story...",
                    zhPlaceholder: "图片、视频、实物、故事等"
                ),
                textField(
                    "context_hook_questions",
                    enLabel: "Guiding Questions",
                    zhLabel: "引导问题组",
                    enPlaceholder: "List 2-3 key opening questions",
                    zhPlaceholder: "填写 2-3 个开场关键问题",
                    multiline: true,
                    minLines: 2
                )
            ]
            let optionFields = [
                optionField(
                    "context_hook_response_pattern",
                    enLabel: "Response Pattern",
                    zhLabel: "回应方式",
                    options: [
                        option("quick_poll", "Quick Poll", "快速投票"),
                        option("think_pair_share", "Think-Pair-Share", "先思考后同伴交流"),
                        option("choral_response", "Choral Response", "全班齐答")
                    ]
                ),
                optionField(
                    "context_hook_time_budget",
                    enLabel: "Time Budget (Optional)",
                    zhLabel: "时间配额（可选）",
                    options: [
                        option("2min", "2 min", "2 分钟"),
                        option("3min", "3 min", "3 分钟"),
                        option("5min", "5 min", "5 分钟"),
                        option("8min", "8 min", "8 分钟")
                    ]
                )
            ]
            return MethodSchema(textFields: textFields, optionFields: optionFields)

        case "field_observation":
            let taskStructureChoices = [
                option("classification", "Classification", "分类识别"),
                option("behavior_event", "Behavior Event", "行为事件"),
                option("process_tracking", "Process Tracking", "过程追踪"),
                option("comparative_observation", "Comparative Observation", "对比观察"),
                option("open_observation", "Open Observation", "开放观察")
            ]
            let evidenceCaptureChoices = [
                option("photo", "Photo", "照片"),
                option("note_table", "Note Table", "表格记录"),
                option("audio", "Audio", "录音"),
                option("video", "Video", "视频"),
                option("mixed", "Mixed", "混合")
            ]

            let selectedStructure = resolvedStoredChoiceID(
                fromStored: optionFieldValues["field_obs_task_structure"],
                in: taskStructureChoices
            ) ?? taskStructureChoices.first?.id ?? "classification"

            var textFields = [
                textField(
                    "field_obs_site",
                    enLabel: "Observation Site",
                    zhLabel: "观察场域",
                    enPlaceholder: "Where will students observe?",
                    zhPlaceholder: "学生在何处进行观察？"
                ),
                textField(
                    "field_obs_focus",
                    enLabel: "Observation Focus",
                    zhLabel: "观察焦点",
                    enPlaceholder: "What should students notice and record?",
                    zhPlaceholder: "学生要重点观察并记录什么？",
                    multiline: true,
                    minLines: 2
                ),
                textField(
                    "field_obs_sampling_rule",
                    enLabel: "Sampling Rule",
                    zhLabel: "采样规则",
                    enPlaceholder: "Who/when/how often to sample?",
                    zhPlaceholder: "采样对象、时间与频率规则",
                    multiline: true,
                    minLines: 2
                ),
                textField(
                    "field_obs_record_template",
                    enLabel: "Observation Record Template (Optional)",
                    zhLabel: "观察记录模板（可选）",
                    enPlaceholder: "Template for student recording",
                    zhPlaceholder: "学生记录模板",
                    multiline: true,
                    minLines: 2
                ),
                textField(
                    "field_obs_tool_ref",
                    enLabel: "Tool Reference (Optional)",
                    zhLabel: "工具引用（可选）",
                    enPlaceholder: "External app/device and usage",
                    zhPlaceholder: "外部工具及使用说明"
                )
            ]

            var optionFields = [
                optionField(
                    "field_obs_task_structure",
                    enLabel: "Task Structure",
                    zhLabel: "观察任务结构",
                    options: taskStructureChoices
                ),
                optionField(
                    "field_obs_capture",
                    enLabel: "Evidence Capture",
                    zhLabel: "证据采集",
                    options: evidenceCaptureChoices
                )
            ]

            switch selectedStructure {
            case "classification":
                textFields.append(
                    textField(
                        "field_obs_class_dict",
                        enLabel: "Classification Dictionary",
                        zhLabel: "分类字典",
                        enPlaceholder: "Category | Criteria | Typical sample",
                        zhPlaceholder: "类别 | 判定特征 | 典型样例",
                        multiline: true,
                        minLines: 3
                    )
                )
            case "behavior_event":
                textFields.append(
                    textField(
                        "field_obs_event_dict",
                        enLabel: "Event Dictionary",
                        zhLabel: "事件字典",
                        enPlaceholder: "Event | Trigger condition | Notes",
                        zhPlaceholder: "事件名 | 触发条件 | 记录说明",
                        multiline: true,
                        minLines: 3
                    )
                )
                optionFields.append(
                    optionField(
                        "field_obs_count_mode",
                        enLabel: "Count Mode",
                        zhLabel: "计数方式",
                        options: [
                            option("frequency", "Frequency", "频次"),
                            option("duration", "Duration", "时长")
                        ]
                    )
                )
            case "process_tracking":
                textFields.append(
                    textField(
                        "field_obs_stage_dict",
                        enLabel: "Stage Dictionary",
                        zhLabel: "阶段字典",
                        enPlaceholder: "Stage | Entry condition | Completion flag",
                        zhPlaceholder: "阶段名 | 进入条件 | 完成标志",
                        multiline: true,
                        minLines: 3
                    )
                )
            case "comparative_observation":
                textFields.append(
                    textField(
                        "field_obs_compare_metrics",
                        enLabel: "Comparison Metrics",
                        zhLabel: "对比指标表",
                        enPlaceholder: "Object A/B | Indicator | Recording method",
                        zhPlaceholder: "对象A/B | 指标 | 记录方式",
                        multiline: true,
                        minLines: 3
                    )
                )
            default:
                textFields.append(
                    textField(
                        "field_obs_open_prompts",
                        enLabel: "Prompt Checklist",
                        zhLabel: "提示清单",
                        enPlaceholder: "Open prompts for observation",
                        zhPlaceholder: "开放观察提示清单",
                        multiline: true,
                        minLines: 3
                    )
                )
            }

            return MethodSchema(textFields: textFields, optionFields: optionFields)

        case "source_analysis":
            let textFields = [
                textField(
                    "source_analysis_set",
                    enLabel: "Source Set",
                    zhLabel: "资料集合",
                    enPlaceholder: "List primary sources for students",
                    zhPlaceholder: "列出给学生的一手资料"
                ),
                textField(
                    "source_analysis_rule",
                    enLabel: "Evidence Extraction Rule",
                    zhLabel: "证据提取规则",
                    enPlaceholder: "How should evidence be selected?",
                    zhPlaceholder: "如何筛选与提取证据？",
                    multiline: true,
                    minLines: 2
                ),
                textField(
                    "source_analysis_matrix",
                    enLabel: "Claim-Evidence Matrix",
                    zhLabel: "主张-证据矩阵",
                    enPlaceholder: "Claim | Evidence | Confidence",
                    zhPlaceholder: "主张 | 证据 | 置信度",
                    multiline: true,
                    minLines: 3
                ),
                textField(
                    "source_analysis_credibility",
                    enLabel: "Credibility Clues (Optional)",
                    zhLabel: "可信度线索（可选）",
                    enPlaceholder: "Author/source/date/bias clues",
                    zhPlaceholder: "作者/来源/时间/偏差线索"
                )
            ]
            let optionFields = [
                optionField(
                    "source_analysis_verify",
                    enLabel: "Verification Method",
                    zhLabel: "验证方法",
                    options: [
                        option("cross_source", "Cross-Source", "跨来源比对"),
                        option("timeline_check", "Timeline Check", "时间线核对"),
                        option("claim_evidence", "Claim-Evidence Match", "观点证据匹配")
                    ]
                )
            ]
            return MethodSchema(textFields: textFields, optionFields: optionFields)

        case "sensor_probe":
            let textFields = [
                textField(
                    "sensor_probe_variables",
                    enLabel: "Variable Dictionary",
                    zhLabel: "变量字典",
                    enPlaceholder: "Variable | Unit | Meaning",
                    zhPlaceholder: "变量 | 单位 | 含义",
                    multiline: true,
                    minLines: 2
                ),
                textField(
                    "sensor_probe_setup",
                    enLabel: "Instrument Setup",
                    zhLabel: "仪器配置",
                    enPlaceholder: "Tools and setup notes",
                    zhPlaceholder: "仪器与配置说明"
                ),
                textField(
                    "sensor_probe_sampling_plan",
                    enLabel: "Sampling Plan",
                    zhLabel: "采样计划",
                    enPlaceholder: "When/where/how often to sample",
                    zhPlaceholder: "采样时间、地点与频次",
                    multiline: true,
                    minLines: 2
                ),
                textField(
                    "sensor_probe_cleaning_rule",
                    enLabel: "Data Cleaning Rule",
                    zhLabel: "数据清洗规则",
                    enPlaceholder: "How to handle noise/outliers",
                    zhPlaceholder: "如何处理噪声与离群值"
                ),
                textField(
                    "sensor_probe_anomaly_threshold",
                    enLabel: "Anomaly Threshold (Optional)",
                    zhLabel: "异常阈值（可选）",
                    enPlaceholder: "Threshold for warning/intervention",
                    zhPlaceholder: "触发预警的阈值"
                )
            ]
            return MethodSchema(textFields: textFields, optionFields: [])

        case "immersive_simulation":
            let textFields = [
                textField(
                    "immersive_scene",
                    enLabel: "Simulation Scene",
                    zhLabel: "模拟情境",
                    enPlaceholder: "What scenario is simulated?",
                    zhPlaceholder: "模拟什么情境？"
                ),
                textField(
                    "immersive_triggers",
                    enLabel: "Event Triggers",
                    zhLabel: "事件触发点",
                    enPlaceholder: "What events trigger role/decision changes?",
                    zhPlaceholder: "哪些事件触发角色或决策变化？",
                    multiline: true,
                    minLines: 2
                ),
                textField(
                    "immersive_debrief",
                    enLabel: "Debrief Questions",
                    zhLabel: "复盘问题组",
                    enPlaceholder: "Questions for post-simulation reflection",
                    zhPlaceholder: "模拟后的复盘问题",
                    multiline: true,
                    minLines: 2
                ),
                textField(
                    "immersive_safety",
                    enLabel: "Safety Boundary (Optional)",
                    zhLabel: "安全边界（可选）",
                    enPlaceholder: "Psychological/physical boundaries",
                    zhPlaceholder: "心理与行动安全边界"
                )
            ]
            let optionFields = [
                optionField(
                    "immersive_role_mode",
                    enLabel: "Role Mode",
                    zhLabel: "角色模式",
                    options: [
                        option("single_role", "Single Role", "单一角色"),
                        option("group_role", "Group Role", "小组角色"),
                        option("rotating_role", "Rotating Role", "轮转角色")
                    ]
                )
            ]
            return MethodSchema(textFields: textFields, optionFields: optionFields)

        case "low_fidelity_prototype":
            let textFields = [
                textField(
                    "lowfi_problem_definition",
                    enLabel: "Problem Definition",
                    zhLabel: "问题定义",
                    enPlaceholder: "What exact problem is solved?",
                    zhPlaceholder: "该原型要解决什么问题？"
                ),
                textField(
                    "lowfi_goal",
                    enLabel: "Prototype Goal",
                    zhLabel: "原型目标",
                    enPlaceholder: "What idea should the prototype express?",
                    zhPlaceholder: "原型要表达什么关键想法？"
                ),
                textField(
                    "lowfi_material_constraints",
                    enLabel: "Material Constraints",
                    zhLabel: "材料约束",
                    enPlaceholder: "Time/material limits",
                    zhPlaceholder: "时间与材料限制"
                ),
                textField(
                    "lowfi_test_task",
                    enLabel: "Test Task",
                    zhLabel: "测试任务",
                    enPlaceholder: "How will students test this prototype?",
                    zhPlaceholder: "学生如何测试原型？"
                ),
                textField(
                    "lowfi_optional_rubric",
                    enLabel: "Evaluation Rubric (Optional)",
                    zhLabel: "评价量规（可选）",
                    enPlaceholder: "Simple criteria for judging quality",
                    zhPlaceholder: "质量判断标准"
                )
            ]
            return MethodSchema(textFields: textFields, optionFields: [])

        case "physical_computing":
            let textFields = [
                textField(
                    "phycomp_function_goal",
                    enLabel: "Function Goal",
                    zhLabel: "功能目标",
                    enPlaceholder: "What behavior/function should be achieved?",
                    zhPlaceholder: "要实现的功能目标是什么？"
                ),
                textField(
                    "phycomp_modules",
                    enLabel: "Module Combination",
                    zhLabel: "模块组合",
                    enPlaceholder: "Hardware modules and wiring plan",
                    zhPlaceholder: "硬件模块与连接方案",
                    multiline: true,
                    minLines: 2
                ),
                textField(
                    "phycomp_logic_flow",
                    enLabel: "Logic Flow",
                    zhLabel: "逻辑流程",
                    enPlaceholder: "Input -> Process -> Output flow",
                    zhPlaceholder: "输入 -> 处理 -> 输出流程",
                    multiline: true,
                    minLines: 2
                ),
                textField(
                    "phycomp_debug",
                    enLabel: "Debug Rule",
                    zhLabel: "调试规则",
                    enPlaceholder: "How do students troubleshoot?",
                    zhPlaceholder: "学生如何排错？"
                ),
                textField(
                    "phycomp_safety_check",
                    enLabel: "Safety Check (Optional)",
                    zhLabel: "安全检查（可选）",
                    enPlaceholder: "Safety notes before operation",
                    zhPlaceholder: "操作前安全检查说明"
                )
            ]
            return MethodSchema(textFields: textFields, optionFields: [])

        case "story_construction":
            let structureChoices = [
                option("problem_solution", "Problem-Solution", "问题-解决"),
                option("journey", "Journey", "旅程式"),
                option("compare_contrast", "Compare-Contrast", "对比式")
            ]
            let selectedStructure = resolvedStoredChoiceID(
                fromStored: optionFieldValues["story_structure"],
                in: structureChoices
            ) ?? structureChoices.first?.id ?? "problem_solution"

            var textFields = [
                textField(
                    "story_mainline",
                    enLabel: "Story Mainline",
                    zhLabel: "叙事主线",
                    enPlaceholder: "One line per step: 1. ... 2. ... 3. ...",
                    zhPlaceholder: "按行填写主线：1. ... 2. ... 3. ...",
                    multiline: true,
                    minLines: 3
                ),
                textField(
                    "story_keywords",
                    enLabel: "Key Terms",
                    zhLabel: "关键术语",
                    enPlaceholder: "One term per line (press Return)",
                    zhPlaceholder: "每行一个关键词（回车新增）",
                    multiline: true,
                    minLines: 2
                )
            ]
            let optionFields = [
                optionField(
                    "story_structure",
                    enLabel: "Narrative Structure",
                    zhLabel: "叙事结构",
                    options: structureChoices
                )
            ]

            switch selectedStructure {
            case "problem_solution":
                textFields.append(
                    textField(
                        "story_problem_setup",
                        enLabel: "Problem Setup",
                        zhLabel: "问题设定",
                        enPlaceholder: "What exact learning problem starts this story?",
                        zhPlaceholder: "故事从哪个学习问题切入？",
                        multiline: true,
                        minLines: 2
                    )
                )
                textFields.append(
                    textField(
                        "story_solution_path",
                        enLabel: "Solution Path",
                        zhLabel: "解决路径",
                        enPlaceholder: "How does the story move from problem to solution?",
                        zhPlaceholder: "故事如何从问题推进到解决？",
                        multiline: true,
                        minLines: 2
                    )
                )
                textFields.append(
                    textField(
                        "story_validation_evidence",
                        enLabel: "Validation Evidence",
                        zhLabel: "验证证据",
                        enPlaceholder: "What evidence proves the solution works?",
                        zhPlaceholder: "什么证据能证明方案有效？"
                    )
                )
            case "journey":
                textFields.append(
                    textField(
                        "story_journey_stages",
                        enLabel: "Journey Stages",
                        zhLabel: "旅程阶段",
                        enPlaceholder: "One stage per line: stage | learning task",
                        zhPlaceholder: "每行一个阶段：阶段 | 学习任务",
                        multiline: true,
                        minLines: 3
                    )
                )
                textFields.append(
                    textField(
                        "story_turning_points",
                        enLabel: "Turning Points",
                        zhLabel: "转折点",
                        enPlaceholder: "What key events push learners to next stage?",
                        zhPlaceholder: "哪些关键事件推动进入下一阶段？",
                        multiline: true,
                        minLines: 2
                    )
                )
                textFields.append(
                    textField(
                        "story_journey_guide_optional",
                        enLabel: "Guide/Perspective (Optional)",
                        zhLabel: "引导角色/视角（可选）",
                        enPlaceholder: "Who guides learners through the journey?",
                        zhPlaceholder: "由谁引导学习旅程（可选）"
                    )
                )
            default:
                textFields.append(
                    textField(
                        "story_compare_targets",
                        enLabel: "Compare Targets",
                        zhLabel: "对比对象",
                        enPlaceholder: "Target A | Target B",
                        zhPlaceholder: "对象A | 对象B",
                        multiline: true,
                        minLines: 2
                    )
                )
                textFields.append(
                    textField(
                        "story_compare_dimensions",
                        enLabel: "Compare Dimensions",
                        zhLabel: "对比维度",
                        enPlaceholder: "Dimension | Observation focus",
                        zhPlaceholder: "维度 | 观察焦点",
                        multiline: true,
                        minLines: 2
                    )
                )
                textFields.append(
                    textField(
                        "story_conclusion_rule",
                        enLabel: "Synthesis Rule",
                        zhLabel: "归纳规则",
                        enPlaceholder: "How students derive conclusion from comparison",
                        zhPlaceholder: "学生如何从对比结果归纳结论"
                    )
                )
            }

            return MethodSchema(textFields: textFields, optionFields: optionFields)

        case "service_blueprint":
            let orientationChoices = [
                option("efficiency", "Efficiency", "效率"),
                option("engagement", "Engagement", "参与度"),
                option("equity", "Equity", "公平性"),
                option("retention", "Retention", "保持度")
            ]
            let selectedOrientation = resolvedStoredChoiceID(
                fromStored: optionFieldValues["service_goal_orientation"],
                in: orientationChoices
            ) ?? orientationChoices.first?.id ?? "efficiency"

            var textFields = [
                textField(
                    "service_object_dict",
                    enLabel: "Object Dictionary",
                    zhLabel: "对象字典",
                    enPlaceholder: "Object | Responsibility",
                    zhPlaceholder: "对象名 | 职责描述",
                    multiline: true,
                    minLines: 3
                ),
                textField(
                    "service_environment",
                    enLabel: "Environment",
                    zhLabel: "环境",
                    enPlaceholder: "Physical/digital/social environment",
                    zhPlaceholder: "物理/数字/社会环境说明"
                ),
                textField(
                    "service_journey_stages",
                    enLabel: "Journey Stages",
                    zhLabel: "旅程阶段",
                    enPlaceholder: "Pre-class | In-class | Post-class",
                    zhPlaceholder: "课前 | 课中 | 课后阶段",
                    multiline: true,
                    minLines: 2
                ),
                textField(
                    "service_touchpoint_issues",
                    enLabel: "Touchpoint Issues",
                    zhLabel: "触点问题清单",
                    enPlaceholder: "Touchpoint | Pain point | Cause",
                    zhPlaceholder: "触点 | 痛点 | 原因",
                    multiline: true,
                    minLines: 3
                )
            ]

            switch selectedOrientation {
            case "engagement":
                textFields.append(
                    textField(
                        "service_engagement_triggers",
                        enLabel: "Engagement Triggers",
                        zhLabel: "参与触发点",
                        enPlaceholder: "Touchpoint | Trigger design",
                        zhPlaceholder: "触点 | 参与触发设计",
                        multiline: true,
                        minLines: 2
                    )
                )
            case "equity":
                textFields.append(
                    textField(
                        "service_equity_support",
                        enLabel: "Equity Support Plan",
                        zhLabel: "公平支持方案",
                        enPlaceholder: "Learner profile | Support action",
                        zhPlaceholder: "学习者画像 | 支持动作",
                        multiline: true,
                        minLines: 2
                    )
                )
            case "retention":
                textFields.append(
                    textField(
                        "service_retention_loop",
                        enLabel: "Retention Loop",
                        zhLabel: "保持度回流机制",
                        enPlaceholder: "Review timing | Recall activity",
                        zhPlaceholder: "复习时机 | 回忆活动",
                        multiline: true,
                        minLines: 2
                    )
                )
            default:
                textFields.append(
                    textField(
                        "service_efficiency_metric",
                        enLabel: "Efficiency Metric",
                        zhLabel: "效率指标",
                        enPlaceholder: "Step | Time cost | Optimization target",
                        zhPlaceholder: "环节 | 时间成本 | 优化目标",
                        multiline: true,
                        minLines: 2
                    )
                )
            }

            textFields.append(
                textField(
                    "service_priority_optional",
                    enLabel: "Intervention Priority (Optional)",
                    zhLabel: "干预优先级（可选）",
                    enPlaceholder: "High/Medium/Low with rationale",
                    zhPlaceholder: "高/中/低优先级及理由"
                )
            )
            textFields.append(
                textField(
                    "service_tool_ref_optional",
                    enLabel: "Tool Reference (Optional)",
                    zhLabel: "工具引用（可选）",
                    enPlaceholder: "External tools for this service flow",
                    zhPlaceholder: "该服务流程引用的外部工具"
                )
            )

            let optionFields = [
                optionField(
                    "service_goal_orientation",
                    enLabel: "Goal Orientation",
                    zhLabel: "目标导向",
                    options: orientationChoices
                )
            ]
            return MethodSchema(textFields: textFields, optionFields: optionFields)

        case "adaptive_learning_platform", "digital_artifact":
            let textFields = [
                textField(
                    "adaptive_routing_rule",
                    enLabel: "Routing Rule",
                    zhLabel: "分流规则",
                    enPlaceholder: "How students are routed by diagnosis/performance",
                    zhPlaceholder: "基于诊断或表现的分流规则",
                    multiline: true,
                    minLines: 2
                ),
                textField(
                    "adaptive_feedback_trigger",
                    enLabel: "Feedback Trigger",
                    zhLabel: "反馈触发条件",
                    enPlaceholder: "When and how feedback is triggered",
                    zhPlaceholder: "何时触发反馈与提示"
                ),
                textField(
                    "adaptive_return_strategy",
                    enLabel: "Return Strategy",
                    zhLabel: "回流策略",
                    enPlaceholder: "When students return to main learning line",
                    zhPlaceholder: "何时回到主学习路径"
                ),
                textField(
                    "adaptive_tool_ref_optional",
                    enLabel: "Tool Reference (Optional)",
                    zhLabel: "工具引用（可选）",
                    enPlaceholder: "Platform/app used in class",
                    zhPlaceholder: "课堂使用的平台或应用"
                ),
                textField(
                    "adaptive_teacher_intervention_optional",
                    enLabel: "Teacher Intervention Node (Optional)",
                    zhLabel: "教师人工干预节点（可选）",
                    enPlaceholder: "When teacher manually overrides the path",
                    zhPlaceholder: "教师何时手动干预路径"
                )
            ]
            let optionFields = [
                optionField(
                    "adaptive_target",
                    enLabel: "Adaptation Target",
                    zhLabel: "适配目标",
                    options: [
                        option("ability_diff", "Ability Difference", "能力差异"),
                        option("pace_diff", "Pace Difference", "节奏差异"),
                        option("interest_diff", "Interest Difference", "兴趣差异")
                    ]
                )
            ]
            return MethodSchema(textFields: textFields, optionFields: optionFields)

        case "role_play":
            let facilitationChoices = [
                option("inner_outer", "Inner-Outer Circle", "内外圈"),
                option("station", "Station Rotation", "站点轮换"),
                option("fishbowl", "Fishbowl", "鱼缸式")
            ]
            let selectedFacilitation = resolvedStoredChoiceID(
                fromStored: optionFieldValues["roleplay_facilitation"],
                in: facilitationChoices
            ) ?? facilitationChoices.first?.id ?? "inner_outer"

            var textFields = [
                textField(
                    "roleplay_role_dict",
                    enLabel: "Role Dictionary",
                    zhLabel: "角色字典",
                    enPlaceholder: "Role | Responsibility",
                    zhPlaceholder: "角色名 | 职责描述",
                    multiline: true,
                    minLines: 3
                ),
                textField(
                    "roleplay_scene",
                    enLabel: "Scene Design",
                    zhLabel: "场景设计",
                    enPlaceholder: "Describe context and objective",
                    zhPlaceholder: "描述场景背景与目标"
                ),
                textField(
                    "roleplay_conflict_trigger",
                    enLabel: "Conflict Trigger",
                    zhLabel: "冲突触发点",
                    enPlaceholder: "What conflict drives dialogue?",
                    zhPlaceholder: "哪种冲突推动对话？"
                ),
                textField(
                    "roleplay_round_timing",
                    enLabel: "Rounds and Duration",
                    zhLabel: "轮次与时长",
                    enPlaceholder: "Round plan and duration",
                    zhPlaceholder: "轮次安排与时长",
                    multiline: true,
                    minLines: 2
                )
            ]

            switch selectedFacilitation {
            case "station":
                textFields.append(
                    textField(
                        "roleplay_station_design",
                        enLabel: "Station Design",
                        zhLabel: "站点设计",
                        enPlaceholder: "Station | Task | Output",
                        zhPlaceholder: "站点 | 任务 | 产出",
                        multiline: true,
                        minLines: 2
                    )
                )
                textFields.append(
                    textField(
                        "roleplay_station_rotation",
                        enLabel: "Rotation Rule",
                        zhLabel: "轮转规则",
                        enPlaceholder: "How groups rotate among stations",
                        zhPlaceholder: "小组如何在站点间轮转"
                    )
                )
            case "fishbowl":
                textFields.append(
                    textField(
                        "roleplay_hotseat_rule",
                        enLabel: "Hot Seat Rule",
                        zhLabel: "内圈发言规则",
                        enPlaceholder: "Who can speak and when to switch speakers",
                        zhPlaceholder: "内圈发言和换人规则"
                    )
                )
                textFields.append(
                    textField(
                        "roleplay_observer_feedback",
                        enLabel: "Observer Feedback Protocol",
                        zhLabel: "观察者反馈协议",
                        enPlaceholder: "How outer circle gives structured feedback",
                        zhPlaceholder: "外圈如何给结构化反馈"
                    )
                )
            default:
                textFields.append(
                    textField(
                        "roleplay_inner_task",
                        enLabel: "Inner Circle Task",
                        zhLabel: "内圈任务",
                        enPlaceholder: "What inner circle must complete",
                        zhPlaceholder: "内圈需要完成什么任务"
                    )
                )
                textFields.append(
                    textField(
                        "roleplay_outer_observe",
                        enLabel: "Outer Circle Observation",
                        zhLabel: "外圈观察任务",
                        enPlaceholder: "What outer circle tracks and records",
                        zhPlaceholder: "外圈观察并记录什么"
                    )
                )
            }

            textFields.append(
                textField(
                    "roleplay_observe_rubric_optional",
                    enLabel: "Observation Rubric (Optional)",
                    zhLabel: "观察量规（可选）",
                    enPlaceholder: "How observers record performance",
                    zhPlaceholder: "观察者记录量规"
                )
            )
            textFields.append(
                textField(
                    "roleplay_tool_ref_optional",
                    enLabel: "Tool Reference (Optional)",
                    zhLabel: "工具引用（可选）",
                    enPlaceholder: "Supporting tools/cards/media",
                    zhPlaceholder: "支持该活动的工具或媒介"
                )
            )

            let optionFields = [
                optionField(
                    "roleplay_facilitation",
                    enLabel: "Facilitation Pattern",
                    zhLabel: "组织方式",
                    options: facilitationChoices
                )
            ]
            return MethodSchema(textFields: textFields, optionFields: optionFields)

        case "structured_debate":
            let protocolChoices = [
                option("cer", "CER", "观点-证据-推理"),
                option("oxford", "Oxford", "牛津式"),
                option("toulmin", "Toulmin", "图尔敏论证")
            ]
            let selectedProtocol = resolvedStoredChoiceID(
                fromStored: optionFieldValues["debate_protocol"],
                in: protocolChoices
            ) ?? protocolChoices.first?.id ?? "cer"

            var textFields = [
                textField(
                    "debate_motion",
                    enLabel: "Debate Motion",
                    zhLabel: "辩题陈述",
                    enPlaceholder: "Define debate statement",
                    zhPlaceholder: "定义辩题陈述"
                ),
                textField(
                    "debate_evidence_threshold",
                    enLabel: "Evidence Threshold",
                    zhLabel: "证据门槛",
                    enPlaceholder: "What evidence is minimally acceptable?",
                    zhPlaceholder: "最低证据门槛是什么？"
                ),
                textField(
                    "debate_speaking_flow",
                    enLabel: "Speaking Flow",
                    zhLabel: "发言流程",
                    enPlaceholder: "Order and timing of speaking turns",
                    zhPlaceholder: "发言顺序与时长",
                    multiline: true,
                    minLines: 2
                )
            ]

            switch selectedProtocol {
            case "oxford":
                textFields.append(
                    textField(
                        "debate_team_positions",
                        enLabel: "Team Position Setup",
                        zhLabel: "正反方立场设置",
                        enPlaceholder: "Affirmative/Negative role assignment",
                        zhPlaceholder: "正反方角色配置"
                    )
                )
                textFields.append(
                    textField(
                        "debate_rebuttal_rounds",
                        enLabel: "Rebuttal Rounds",
                        zhLabel: "驳论轮次",
                        enPlaceholder: "Round count and timing per rebuttal",
                        zhPlaceholder: "驳论轮次数与时长"
                    )
                )
            case "toulmin":
                textFields.append(
                    textField(
                        "debate_warrant_backing",
                        enLabel: "Warrant & Backing",
                        zhLabel: "论据支撑链",
                        enPlaceholder: "Claim | Warrant | Backing",
                        zhPlaceholder: "主张 | 保证 | 支撑",
                        multiline: true,
                        minLines: 2
                    )
                )
                textFields.append(
                    textField(
                        "debate_rebuttal_prebuttal",
                        enLabel: "Rebuttal / Prebuttal",
                        zhLabel: "反驳与预设反驳",
                        enPlaceholder: "Likely counter-arguments and responses",
                        zhPlaceholder: "预判反方观点及回应"
                    )
                )
            default:
                textFields.append(
                    textField(
                        "debate_claim_template",
                        enLabel: "CER Claim Template",
                        zhLabel: "CER 主张模板",
                        enPlaceholder: "Claim | Evidence | Reasoning",
                        zhPlaceholder: "观点 | 证据 | 推理",
                        multiline: true,
                        minLines: 2
                    )
                )
                textFields.append(
                    textField(
                        "debate_reasoning_checks",
                        enLabel: "Reasoning Quality Checks",
                        zhLabel: "推理质量核查",
                        enPlaceholder: "How to verify reasoning quality",
                        zhPlaceholder: "如何核查推理质量"
                    )
                )
            }

            textFields.append(
                textField(
                    "debate_judgement_optional",
                    enLabel: "Judgement Criteria (Optional)",
                    zhLabel: "裁决标准（可选）",
                    enPlaceholder: "Criteria for deciding result",
                    zhPlaceholder: "裁决结果标准"
                )
            )

            let optionFields = [
                optionField(
                    "debate_protocol",
                    enLabel: "Debate Protocol",
                    zhLabel: "辩论协议",
                    options: protocolChoices
                )
            ]
            return MethodSchema(textFields: textFields, optionFields: optionFields)

        case "world_cafe":
            let textFields = [
                textField(
                    "cafe_core_question",
                    enLabel: "Core Question",
                    zhLabel: "核心问题",
                    enPlaceholder: "What question rotates across tables?",
                    zhPlaceholder: "跨桌轮转的核心问题是什么？"
                ),
                textField(
                    "cafe_table_topics",
                    enLabel: "Table Topics",
                    zhLabel: "桌次主题",
                    enPlaceholder: "Topic for each table",
                    zhPlaceholder: "每桌讨论主题",
                    multiline: true,
                    minLines: 2
                ),
                textField(
                    "cafe_rotation_plan",
                    enLabel: "Rotation Plan",
                    zhLabel: "轮转计划",
                    enPlaceholder: "How groups rotate",
                    zhPlaceholder: "小组如何轮转"
                ),
                textField(
                    "cafe_harvest_rule",
                    enLabel: "Harvest Rule",
                    zhLabel: "汇总规则",
                    enPlaceholder: "How to merge outputs from each table?",
                    zhPlaceholder: "如何汇总每桌结论？"
                ),
                textField(
                    "cafe_output_template_optional",
                    enLabel: "Output Template (Optional)",
                    zhLabel: "输出模板（可选）",
                    enPlaceholder: "Template for final synthesis",
                    zhPlaceholder: "最终汇总输出模板"
                )
            ]
            return MethodSchema(textFields: textFields, optionFields: [])

        case "game_mechanism":
            let progressionChoices = [
                option("level", "Level", "关卡"),
                option("mission", "Mission", "任务线"),
                option("badge", "Badge", "徽章")
            ]
            let selectedProgression = resolvedStoredChoiceID(
                fromStored: optionFieldValues["game_progression"],
                in: progressionChoices
            ) ?? progressionChoices.first?.id ?? "level"

            var textFields = [
                textField(
                    "game_goal_mapping",
                    enLabel: "Learning Goal Mapping",
                    zhLabel: "学习目标映射",
                    enPlaceholder: "How game actions map to learning goals",
                    zhPlaceholder: "游戏动作如何映射学习目标",
                    multiline: true,
                    minLines: 2
                ),
                textField(
                    "game_core_rules",
                    enLabel: "Core Rules",
                    zhLabel: "核心规则",
                    enPlaceholder: "Define win/lose and turn flow",
                    zhPlaceholder: "定义胜负条件与回合流程"
                ),
                textField(
                    "game_reward_mechanism",
                    enLabel: "Reward Mechanism",
                    zhLabel: "奖励机制",
                    enPlaceholder: "How rewards and feedback are given",
                    zhPlaceholder: "奖励与反馈机制"
                )
            ]

            switch selectedProgression {
            case "mission":
                textFields.append(
                    textField(
                        "game_mission_chain",
                        enLabel: "Mission Chain",
                        zhLabel: "任务链",
                        enPlaceholder: "Mission | Unlock condition | Reward",
                        zhPlaceholder: "任务 | 解锁条件 | 奖励",
                        multiline: true,
                        minLines: 2
                    )
                )
            case "badge":
                textFields.append(
                    textField(
                        "game_badge_catalog",
                        enLabel: "Badge Catalog",
                        zhLabel: "徽章清单",
                        enPlaceholder: "Badge | Trigger behavior | Evidence",
                        zhPlaceholder: "徽章 | 触发行为 | 证据",
                        multiline: true,
                        minLines: 2
                    )
                )
            default:
                textFields.append(
                    textField(
                        "game_level_blueprint",
                        enLabel: "Level Blueprint",
                        zhLabel: "关卡蓝图",
                        enPlaceholder: "Level | Goal | Challenge",
                        zhPlaceholder: "关卡 | 目标 | 挑战",
                        multiline: true,
                        minLines: 2
                    )
                )
            }

            textFields.append(
                textField(
                    "game_difficulty_curve_optional",
                    enLabel: "Difficulty Curve (Optional)",
                    zhLabel: "难度曲线（可选）",
                    enPlaceholder: "How difficulty increases over time",
                    zhPlaceholder: "难度如何逐步提升"
                )
            )

            let optionFields = [
                optionField(
                    "game_progression",
                    enLabel: "Progression Style",
                    zhLabel: "进阶方式",
                    options: progressionChoices
                )
            ]
            return MethodSchema(textFields: textFields, optionFields: optionFields)

        case "pogil":
            let textFields = [
                textField(
                    "pogil_role_dict",
                    enLabel: "Team Role Dictionary",
                    zhLabel: "小组角色字典",
                    enPlaceholder: "Role | Responsibility",
                    zhPlaceholder: "角色名 | 责任描述",
                    multiline: true,
                    minLines: 2
                ),
                textField(
                    "pogil_inquiry_ladder",
                    enLabel: "Inquiry Question Ladder",
                    zhLabel: "探究问题阶梯",
                    enPlaceholder: "Question sequence by depth",
                    zhPlaceholder: "按深度递进的问题序列",
                    multiline: true,
                    minLines: 2
                ),
                textField(
                    "pogil_sheet_focus",
                    enLabel: "Worksheet Focus",
                    zhLabel: "任务单焦点",
                    enPlaceholder: "Core worksheet focus",
                    zhPlaceholder: "任务单核心推进焦点"
                ),
                textField(
                    "pogil_teacher_trigger_optional",
                    enLabel: "Teacher Intervention Trigger (Optional)",
                    zhLabel: "教师介入触发（可选）",
                    enPlaceholder: "When teacher steps in",
                    zhPlaceholder: "教师何时介入"
                )
            ]
            let optionFields = [
                optionField(
                    "pogil_checkpoint",
                    enLabel: "Checkpoint Control",
                    zhLabel: "检查点控制",
                    options: [
                        option("teacher_gate", "Teacher Check", "教师把关"),
                        option("peer_gate", "Peer Check", "同伴把关"),
                        option("self_gate", "Self Check", "自检把关")
                    ]
                )
            ]
            return MethodSchema(textFields: textFields, optionFields: optionFields)

        case "kanban_monitoring":
            let textFields = [
                textField(
                    "kanban_columns",
                    enLabel: "Board Columns",
                    zhLabel: "看板列配置",
                    enPlaceholder: "e.g. To Do / Doing / Done",
                    zhPlaceholder: "例如 待办/进行中/已完成"
                ),
                textField(
                    "kanban_wip_limit",
                    enLabel: "WIP Limit",
                    zhLabel: "WIP 限制",
                    enPlaceholder: "Limits per column",
                    zhPlaceholder: "各列在制品数量限制"
                ),
                textField(
                    "kanban_blocker_types",
                    enLabel: "Blocker Categories",
                    zhLabel: "阻塞分类",
                    enPlaceholder: "Types of blockers and handling",
                    zhPlaceholder: "阻塞类型与处理方式"
                ),
                textField(
                    "kanban_milestone_optional",
                    enLabel: "Milestone Nodes (Optional)",
                    zhLabel: "里程碑节点（可选）",
                    enPlaceholder: "Important milestone checkpoints",
                    zhPlaceholder: "关键里程碑节点"
                )
            ]
            let optionFields = [
                optionField(
                    "kanban_refresh",
                    enLabel: "Refresh Frequency",
                    zhLabel: "刷新频率",
                    options: [
                        option("every5", "Every 5 Min", "每5分钟"),
                        option("each_phase", "Each Phase", "每阶段"),
                        option("end_lesson", "End of Lesson", "课末一次")
                    ]
                )
            ]
            return MethodSchema(textFields: textFields, optionFields: optionFields)

        case "rubric_checklist":
            let summaryChoices = [
                option("weighted_avg", "Weighted Average", "加权平均"),
                option("threshold_gate", "Threshold Gate", "门槛达标"),
                option("grade_band", "Grade Band", "分档判定")
            ]
            let selectedSummary = resolvedStoredChoiceID(
                fromStored: optionFieldValues["rubric_summary_strategy"],
                in: summaryChoices
            ) ?? summaryChoices.first?.id ?? "weighted_avg"

            var textFields = [
                textField(
                    "rubric_dimension_dict",
                    enLabel: "Dimension Dictionary",
                    zhLabel: "评价维度字典",
                    enPlaceholder: "Dimension | Definition",
                    zhPlaceholder: "维度 | 定义",
                    multiline: true,
                    minLines: 3
                ),
                textField(
                    "rubric_weight_config",
                    enLabel: "Weight Configuration",
                    zhLabel: "权重配置",
                    enPlaceholder: "Dimension | Weight(%)",
                    zhPlaceholder: "维度 | 权重(%)",
                    multiline: true,
                    minLines: 2
                ),
                textField(
                    "rubric_level_descriptions",
                    enLabel: "Level Descriptions",
                    zhLabel: "等级描述",
                    enPlaceholder: "Describe each level clearly",
                    zhPlaceholder: "填写各等级行为描述",
                    multiline: true,
                    minLines: 3
                )
            ]

            switch selectedSummary {
            case "threshold_gate":
                textFields.append(
                    textField(
                        "rubric_gate_conditions",
                        enLabel: "Gate Conditions",
                        zhLabel: "达标门槛",
                        enPlaceholder: "Dimension | Minimum level required",
                        zhPlaceholder: "维度 | 最低达标等级",
                        multiline: true,
                        minLines: 2
                    )
                )
            case "grade_band":
                textFields.append(
                    textField(
                        "rubric_band_ranges",
                        enLabel: "Grade Bands",
                        zhLabel: "分档区间",
                        enPlaceholder: "Band A/B/C with score ranges",
                        zhPlaceholder: "A/B/C 档区间范围",
                        multiline: true,
                        minLines: 2
                    )
                )
            default:
                textFields.append(
                    textField(
                        "rubric_weight_formula",
                        enLabel: "Weighted Formula",
                        zhLabel: "加权公式",
                        enPlaceholder: "How weighted score is calculated",
                        zhPlaceholder: "加权得分如何计算"
                    )
                )
            }

            textFields.append(
                textField(
                    "rubric_evidence_library_optional",
                    enLabel: "Evidence Library (Optional)",
                    zhLabel: "证据样例库（可选）",
                    enPlaceholder: "Typical evidence examples",
                    zhPlaceholder: "典型证据样例"
                )
            )
            textFields.append(
                textField(
                    "rubric_feedback_template_optional",
                    enLabel: "Feedback Template (Optional)",
                    zhLabel: "反馈语句模板（可选）",
                    enPlaceholder: "Reusable feedback sentence templates",
                    zhPlaceholder: "可复用反馈语句模板"
                )
            )

            let optionFields = [
                optionField(
                    "rubric_levels",
                    enLabel: "Number of Levels",
                    zhLabel: "等级档数",
                    options: [
                        option("level3", "3-Level", "三级"),
                        option("level4", "4-Level", "四级"),
                        option("level5", "5-Level", "五级")
                    ]
                ),
                optionField(
                    "rubric_summary_strategy",
                    enLabel: "Summary Strategy",
                    zhLabel: "汇总策略",
                    options: summaryChoices
                )
            ]
            return MethodSchema(textFields: textFields, optionFields: optionFields)

        case "reflection_protocol":
            let structureChoices = [
                option("what_so_what_now_what", "What-So What-Now What", "发生了什么-意味着什么-下一步"),
                option("orid", "ORID", "ORID"),
                option("kss", "KSS", "Keep-Stop-Start")
            ]
            let selectedStructure = resolvedStoredChoiceID(
                fromStored: optionFieldValues["reflect_structure_template"],
                in: structureChoices
            ) ?? structureChoices.first?.id ?? "what_so_what_now_what"

            var textFields = [
                textField(
                    "reflect_prompt_group",
                    enLabel: "Reflection Prompt Group",
                    zhLabel: "反思提示组",
                    enPlaceholder: "Prompt lines shown to students",
                    zhPlaceholder: "写给学生的反思提示语",
                    multiline: true,
                    minLines: 2
                ),
                textField(
                    "reflect_timing",
                    enLabel: "Trigger Timing",
                    zhLabel: "触发时机",
                    enPlaceholder: "When this reflection is triggered",
                    zhPlaceholder: "何时触发本次反思"
                )
            ]

            switch selectedStructure {
            case "orid":
                textFields.append(
                    textField(
                        "reflect_orid_objective",
                        enLabel: "Objective Prompt",
                        zhLabel: "O：客观层问题",
                        enPlaceholder: "What facts/events did you observe?",
                        zhPlaceholder: "你观察到了哪些事实？"
                    )
                )
                textFields.append(
                    textField(
                        "reflect_orid_reflective",
                        enLabel: "Reflective Prompt",
                        zhLabel: "R：感受层问题",
                        enPlaceholder: "How did you feel during this activity?",
                        zhPlaceholder: "活动过程中你的感受如何？"
                    )
                )
                textFields.append(
                    textField(
                        "reflect_orid_interpretive",
                        enLabel: "Interpretive Prompt",
                        zhLabel: "I：解释层问题",
                        enPlaceholder: "What does this mean for your learning?",
                        zhPlaceholder: "这对你的学习意味着什么？"
                    )
                )
                textFields.append(
                    textField(
                        "reflect_orid_decisional",
                        enLabel: "Decisional Prompt",
                        zhLabel: "D：决策层问题",
                        enPlaceholder: "What will you do next time?",
                        zhPlaceholder: "下一次你会怎么做？"
                    )
                )
            case "kss":
                textFields.append(
                    textField(
                        "reflect_kss_keep",
                        enLabel: "Keep Prompt",
                        zhLabel: "Keep 提示",
                        enPlaceholder: "What should be kept?",
                        zhPlaceholder: "哪些做法应该继续保留？"
                    )
                )
                textFields.append(
                    textField(
                        "reflect_kss_stop",
                        enLabel: "Stop Prompt",
                        zhLabel: "Stop 提示",
                        enPlaceholder: "What should be stopped?",
                        zhPlaceholder: "哪些做法应该停止？"
                    )
                )
                textFields.append(
                    textField(
                        "reflect_kss_start",
                        enLabel: "Start Prompt",
                        zhLabel: "Start 提示",
                        enPlaceholder: "What should be started?",
                        zhPlaceholder: "下一步要开始什么？"
                    )
                )
            default:
                textFields.append(
                    textField(
                        "reflect_what_prompt",
                        enLabel: "What Prompt",
                        zhLabel: "What 问题",
                        enPlaceholder: "What happened?",
                        zhPlaceholder: "发生了什么？"
                    )
                )
                textFields.append(
                    textField(
                        "reflect_so_what_prompt",
                        enLabel: "So What Prompt",
                        zhLabel: "So What 问题",
                        enPlaceholder: "Why does it matter?",
                        zhPlaceholder: "这件事的意义是什么？"
                    )
                )
                textFields.append(
                    textField(
                        "reflect_now_what_prompt",
                        enLabel: "Now What Prompt",
                        zhLabel: "Now What 问题",
                        enPlaceholder: "What is your next action?",
                        zhPlaceholder: "你的下一步行动是什么？"
                    )
                )
            }

            textFields.append(
                textField(
                    "reflect_action_commitment_optional",
                    enLabel: "Action Commitment (Optional)",
                    zhLabel: "行动承诺表（可选）",
                    enPlaceholder: "Action commitments for next cycle",
                    zhPlaceholder: "下一轮行动承诺"
                )
            )

            let optionFields = [
                optionField(
                    "reflect_structure_template",
                    enLabel: "Structure Template",
                    zhLabel: "反思结构模板",
                    options: structureChoices
                ),
                optionField(
                    "reflect_channel",
                    enLabel: "Reflection Channel",
                    zhLabel: "反思渠道",
                    options: [
                        option("written", "Written", "文字"),
                        option("audio", "Audio", "语音"),
                        option("peer_interview", "Peer Interview", "同伴访谈")
                    ]
                )
            ]
            return MethodSchema(textFields: textFields, optionFields: optionFields)

        case "learning_dashboard":
            let textFields = [
                textField(
                    "dashboard_metric_dict",
                    enLabel: "Metric Dictionary",
                    zhLabel: "指标字典",
                    enPlaceholder: "Metric | Meaning | Unit",
                    zhPlaceholder: "指标 | 含义 | 单位",
                    multiline: true,
                    minLines: 2
                ),
                textField(
                    "dashboard_source_mapping",
                    enLabel: "Data Source Mapping",
                    zhLabel: "数据来源映射",
                    enPlaceholder: "Metric | Source",
                    zhPlaceholder: "指标 | 数据来源",
                    multiline: true,
                    minLines: 2
                ),
                textField(
                    "dashboard_alert_threshold",
                    enLabel: "Alert Threshold",
                    zhLabel: "预警阈值",
                    enPlaceholder: "Thresholds for intervention",
                    zhPlaceholder: "触发干预的阈值规则"
                ),
                textField(
                    "dashboard_view_mode_optional",
                    enLabel: "View Mode (Optional)",
                    zhLabel: "视图模式（可选）",
                    enPlaceholder: "Trend table / radar / summary",
                    zhPlaceholder: "趋势表/雷达图/摘要"
                )
            ]
            let optionFields = [
                optionField(
                    "dashboard_cycle",
                    enLabel: "Review Frequency",
                    zhLabel: "查看频率",
                    options: [
                        option("daily", "Daily", "每天"),
                        option("weekly", "Weekly", "每周"),
                        option("per_lesson", "Per Lesson", "每课次")
                    ]
                )
            ]
            return MethodSchema(textFields: textFields, optionFields: optionFields)

        case "metacognitive_routine":
            let textFields = [
                textField(
                    "meta_plan_prompts",
                    enLabel: "Plan Prompts",
                    zhLabel: "计划提示",
                    enPlaceholder: "Prompts before task starts",
                    zhPlaceholder: "任务开始前提示语",
                    multiline: true,
                    minLines: 2
                ),
                textField(
                    "meta_monitor_signals",
                    enLabel: "Monitor Signal Dictionary",
                    zhLabel: "监控信号字典",
                    enPlaceholder: "Signal | Meaning | Action",
                    zhPlaceholder: "信号 | 含义 | 对应行动",
                    multiline: true,
                    minLines: 2
                ),
                textField(
                    "meta_adjust_strategy",
                    enLabel: "Adjustment Strategy Library",
                    zhLabel: "调整策略库",
                    enPlaceholder: "When X happens, adjust with Y",
                    zhPlaceholder: "当X发生时采用Y策略",
                    multiline: true,
                    minLines: 2
                ),
                textField(
                    "meta_self_assessment_optional",
                    enLabel: "Self-Assessment Scale (Optional)",
                    zhLabel: "自评量表（可选）",
                    enPlaceholder: "Simple self-check scale",
                    zhPlaceholder: "自评量表说明"
                )
            ]
            let optionFields = [
                optionField(
                    "meta_routine_pattern",
                    enLabel: "Routine Pattern",
                    zhLabel: "例程模式",
                    options: [
                        option("plan_monitor_adjust", "Plan-Monitor-Adjust", "计划-监控-调整"),
                        option("stop_think_share", "Stop-Think-Share", "暂停-思考-分享"),
                        option("self_explain", "Self Explain", "自我解释")
                    ]
                )
            ]
            return MethodSchema(textFields: textFields, optionFields: optionFields)

        default:
            let textFields = [
                textField(
                    "fallback_focus",
                    enLabel: "Method Focus",
                    zhLabel: "方法焦点",
                    enPlaceholder: "Describe focus for this method",
                    zhPlaceholder: "描述该方法的焦点"
                ),
                textField(
                    "fallback_steps",
                    enLabel: "Execution Steps",
                    zhLabel: "执行步骤",
                    enPlaceholder: "Write key execution steps",
                    zhPlaceholder: "填写关键执行步骤",
                    multiline: true,
                    minLines: 2
                )
            ]
            let optionFields = [
                optionField(
                    "fallback_mode",
                    enLabel: "Execution Mode",
                    zhLabel: "执行模式",
                    options: [
                        option("guided", "Guided", "引导"),
                        option("collaborative", "Collaborative", "协作"),
                        option("independent", "Independent", "自主")
                    ]
                )
            ]
            return MethodSchema(textFields: textFields, optionFields: optionFields)
        }
    }

    private func applyLegacyValueIfNeeded(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let firstFieldID = activeSchema.textFields.first?.id else { return }
        let existing = textFieldValues[firstFieldID]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if existing.isEmpty {
            textFieldValues[firstFieldID] = trimmed
        }
    }

    private func applyOptionDefaultsIfNeeded() {
        for field in activeSchema.optionFields {
            if resolvedStoredChoiceID(fromStored: optionFieldValues[field.id], in: field.options) == nil {
                optionFieldValues[field.id] = field.options.first?.id
            }
        }
    }

    private func applyMethodSelection(_ newMethodID: String) {
        guard methodID != newMethodID else { return }
        methodID = newMethodID
        applyOptionDefaultsIfNeeded()
    }

    private func normalizeStoredTextFieldValues() {
        guard !textFieldValues.isEmpty else { return }
        var normalized: [String: String] = [:]
        normalized.reserveCapacity(textFieldValues.count)
        for (fieldID, raw) in textFieldValues {
            normalized[fieldID] = normalizedFieldValue(raw, fieldID: fieldID)
        }
        textFieldValues = normalized
    }

    private func choiceID(for raw: String, in options: [OptionChoice]) -> String? {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }

        if let byID = options.first(where: { $0.id.lowercased() == normalized }) {
            return byID.id
        }

        if let byTitle = options.first(where: {
            localizedChoiceTitle(for: $0.id, in: options)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() == normalized
        }) {
            return byTitle.id
        }

        if let contains = options.first(where: {
            let title = localizedChoiceTitle(for: $0.id, in: options).lowercased()
            return title.contains(normalized) || normalized.contains(title)
        }) {
            return contains.id
        }

        return nil
    }

    private func resolvedStoredChoiceID(fromStored stored: String?, in options: [OptionChoice]) -> String? {
        guard let stored else { return nil }
        if options.contains(where: { $0.id == stored }) {
            return stored
        }
        return choiceID(for: stored, in: options)
    }

    private func localizedChoiceTitle(for choiceID: String, in options: [OptionChoice]) -> String {
        guard let choice = options.first(where: { $0.id == choiceID }) ?? options.first else {
            return choiceID
        }
        return L(choice.titleEn, choice.titleZh)
    }

    private func appendLineIfNeeded(_ lines: inout [String], label: String, value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lines.append("\(label): \(trimmed)")
    }

    private func normalizedFieldValue(_ raw: String, fieldID: String) -> String {
        switch fieldID {
        case "story_keywords", "phycomp_modules", "kanban_columns":
            return normalizeLineList(raw, allowDelimiterSplit: true, numbered: false)
        case "story_mainline", "story_journey_stages":
            return normalizeLineList(raw, allowDelimiterSplit: false, numbered: true)
        case "service_object_dict", "roleplay_role_dict", "pogil_role_dict",
             "source_analysis_matrix", "field_obs_class_dict", "field_obs_event_dict",
             "field_obs_stage_dict", "field_obs_compare_metrics",
             "rubric_dimension_dict", "rubric_weight_config",
             "dashboard_metric_dict", "dashboard_source_mapping", "meta_monitor_signals":
            return normalizeKeyValueLines(raw)
        default:
            return raw
        }
    }

    private func normalizeLineList(_ raw: String, allowDelimiterSplit: Bool, numbered: Bool) -> String {
        let normalizedRaw = raw.replacingOccurrences(of: "\r\n", with: "\n")
        let segments: [String]
        if allowDelimiterSplit {
            let delimiters = CharacterSet(charactersIn: "\n,，;；")
            segments = normalizedRaw.components(separatedBy: delimiters)
        } else {
            segments = normalizedRaw.components(separatedBy: .newlines)
        }

        var cleaned = segments
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if numbered {
            cleaned = cleaned.enumerated().map { index, line in
                let removed = line.replacingOccurrences(
                    of: #"^\d+[\.\)、\s]+"#,
                    with: "",
                    options: .regularExpression
                )
                return "\(index + 1). \(removed)"
            }
        }

        return cleaned.joined(separator: "\n")
    }

    private func normalizeKeyValueLines(_ raw: String) -> String {
        let normalizedRaw = raw.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalizedRaw
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let normalized = lines.map { line -> String in
            if line.contains("|") || line.contains("｜") {
                let normalizedLine = line.replacingOccurrences(of: "｜", with: "|")
                let components = normalizedLine
                    .split(separator: "|", omittingEmptySubsequences: false)
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                let left = components.first ?? ""
                let right = components.dropFirst()
                    .filter { !$0.isEmpty }
                    .joined(separator: " / ")
                return "\(left) | \(right)"
            }
            if line.contains(":") || line.contains("：") {
                let normalizedLine = line.replacingOccurrences(of: "：", with: ":")
                let components = normalizedLine
                    .split(separator: ":", omittingEmptySubsequences: false)
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                let left = components.first ?? ""
                let right = components.dropFirst()
                    .filter { !$0.isEmpty }
                    .joined(separator: " / ")
                return "\(left) | \(right)"
            }
            return "\(line) | "
        }

        return normalized.joined(separator: "\n")
    }

    private func normalizedStringInput(at index: Int) -> String {
        guard inputs.indices.contains(index) else { return "" }
        guard let raw = stringValue(from: inputs[index]) else { return "" }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stringValue(from input: AnyInputPort) -> String? {
        if let value: StringData = ((try? input.getValue()) ?? nil) {
            return value.value
        }
        if let value: NumData = ((try? input.getValue()) ?? nil) {
            let number = value.toDouble()
            return number == number.rounded() ? "\(Int(number))" : "\(number)"
        }
        if let value: BoolData = ((try? input.getValue()) ?? nil) {
            return value.value ? "true" : "false"
        }
        if let value: ArrayData = ((try? input.getValue()) ?? nil) {
            return value.values
                .map { number in
                    number == number.rounded() ? "\(Int(number))" : "\(number)"
                }
                .joined(separator: ", ")
        }
        if let value: ObjectData = ((try? input.getValue()) ?? nil) {
            let fields = value.keys.map { key -> String in
                let display = value.get(key)?.displayString() ?? ""
                return "\(key): \(display)"
            }
            return "{\(fields.joined(separator: ", "))}"
        }
        return nil
    }

    private static func resolveMethodID(
        category: EduToolkitCategory,
        selectedMethodID: String?,
        selectedType: String?
    ) -> String {
        if let selectedMethodID {
            let mappedMethodID: String
            if selectedMethodID == "digital_artifact" {
                mappedMethodID = "adaptive_learning_platform"
            } else {
                mappedMethodID = selectedMethodID
            }

            if category.methods.contains(where: { $0.id == mappedMethodID }) {
                return mappedMethodID
            }
        }

        if let selectedType {
            if let methodID = category.methodID(forLocalizedTitle: selectedType) {
                return methodID
            }
            if category.methods.contains(where: { $0.id == selectedType }) {
                return selectedType
            }
            if selectedType == "digital_artifact", category == .constructionPrototype {
                return "adaptive_learning_platform"
            }
            if let legacyMethodID = legacyMethodID(from: selectedType, in: category) {
                return legacyMethodID
            }
        }

        return category.defaultMethodID
    }

    private static func legacyMethodID(from selectedType: String, in category: EduToolkitCategory) -> String? {
        let value = selectedType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty else { return nil }

        if value.contains("observation") || value.contains("观察") {
            return category == .perceptionInquiry ? "field_observation" : nil
        }
        if value.contains("inquiry") || value.contains("探究") {
            return category == .perceptionInquiry ? "source_analysis" : nil
        }
        if value.contains("demonstration") || value.contains("示范") {
            return category == .perceptionInquiry ? "context_hook" : nil
        }
        if value.contains("discussion") || value.contains("讨论") {
            return category == .communicationNegotiation ? "structured_debate" : nil
        }
        if value.contains("game") || value.contains("游戏") {
            return category == .communicationNegotiation ? "game_mechanism" : nil
        }
        if value.contains("practice") || value.contains("练习") {
            return category == .constructionPrototype ? "low_fidelity_prototype" : nil
        }
        if value.contains("artifact") || value.contains("制品") {
            return category == .constructionPrototype ? "adaptive_learning_platform" : nil
        }
        if value.contains("peer") || value.contains("同伴") {
            return category == .regulationMetacognition ? "reflection_protocol" : nil
        }

        return nil
    }
}

final class EduEvaluationNode: GNode, NodeFormEditable {
    let id: UUID
    var attributes: NodeAttributes
    var inputs: [AnyInputPort]
    var outputs: [AnyOutputPort]

    private var textFieldValues: [String: String]
    private var optionFieldValues: [String: String]

    private struct OptionChoice {
        let id: String
        let titleEn: String
        let titleZh: String
    }

    private struct IndicatorRow {
        let name: String
        let type: String
        let weight: String
    }

    private enum EvaluationOutputValue {
        case number(Double)
        case text(String)
    }

    private let indicatorsFieldID = "evaluation_indicators"
    private let legacyDefsFieldID = "evaluation_indicator_defs"
    private let legacyScoresFieldID = "evaluation_indicator_scores"
    private let legacyWeightsFieldID = "evaluation_indicator_weights"

    init(
        name: String,
        textFieldValues: [String: String] = [:],
        optionFieldValues: [String: String] = [:]
    ) {
        self.id = UUID()
        self.attributes = NodeAttributes(name: name)
        self.inputs = []
        self.outputs = [
            AnyOutputPort(name: S("edu.evaluation.output.score"), dataType: "Any")
        ]
        self.textFieldValues = textFieldValues
        self.optionFieldValues = optionFieldValues
        applyOptionDefaultsIfNeeded()
        normalizeStoredTextFieldValues()
        updateDynamicInputPorts()
    }

    func process() throws {
        guard attributes.isRun else {
            throw GNodeError.nodeDisabled(id: id)
        }

        let formulaID = resolvedFormulaID()
        let outputScaleID = resolvedOutputScaleID()
        let indicatorRows = parseIndicatorRows()

        var scoreRows: [(name: String, type: String, score5: Double, weight: Double)] = []
        scoreRows.reserveCapacity(indicatorRows.count)

        for (index, row) in indicatorRows.enumerated() {
            let isCompletion = row.type == "completion" || isCompletionType(row.type)
            let rawValue = connectedIndicatorValue(at: index) ?? "0"
            let score5 = parsedScore5(from: rawValue, isCompletion: isCompletion)
            let weight = parsedWeight(row.weight)
            scoreRows.append((
                name: row.name,
                type: isCompletion ? "completion" : "score",
                score5: score5,
                weight: weight
            ))
        }

        let computedScore5 = computeScore5(rows: scoreRows, formulaID: formulaID)
        let outputValue = convertOutputValue(score5: computedScore5, outputScaleID: outputScaleID)
        switch outputValue {
        case .number(let number):
            try outputs[0].setValue(NumData(number))
        case .text(let text):
            try outputs[0].setValue(StringData(text))
        }
    }

    func canExecute() -> Bool {
        attributes.isRun
    }

    var serializedTextFieldValues: [String: String] {
        textFieldValues
    }

    var serializedOptionFieldValues: [String: String] {
        optionFieldValues
    }

    var editorFormTextFields: [NodeEditorTextFieldSpec] {
        let includeWeight = formulaNeedsWeights(resolvedFormulaID())
        let normalizedValue = normalizedIndicatorTableText(
            from: textFieldValues[indicatorsFieldID] ?? "",
            includeWeight: includeWeight
        )
        return [
            NodeEditorTextFieldSpec(
                id: indicatorsFieldID,
                label: S("edu.evaluation.form.indicators"),
                placeholder: S("edu.evaluation.form.indicators.placeholder"),
                value: normalizedValue,
                isMultiline: true,
                minVisibleLines: 4,
                editorKind: .keyValueTable,
                tableColumnTitles: includeWeight
                    ? [
                        S("edu.evaluation.table.indicator"),
                        S("edu.evaluation.table.type"),
                        S("edu.evaluation.table.weight")
                    ]
                    : [
                        S("edu.evaluation.table.indicator"),
                        S("edu.evaluation.table.type")
                    ]
            )
        ]
    }

    var editorFormOptionFields: [NodeEditorOptionFieldSpec] {
        [
            NodeEditorOptionFieldSpec(
                id: "evaluation_formula",
                label: S("edu.evaluation.form.formula"),
                options: formulaChoices.map { localizedChoiceTitle(for: $0) },
                selectedOption: localizedFormulaTitle(for: resolvedFormulaID())
            ),
            NodeEditorOptionFieldSpec(
                id: "evaluation_grouping",
                label: S("edu.evaluation.form.grouping"),
                options: groupingChoices.map { localizedChoiceTitle(for: $0) },
                selectedOption: localizedGroupingTitle(for: resolvedGroupingID())
            ),
            NodeEditorOptionFieldSpec(
                id: "evaluation_output_scale",
                label: S("edu.evaluation.form.outputScale"),
                options: outputScaleChoices.map { localizedChoiceTitle(for: $0) },
                selectedOption: localizedOutputScaleTitle(for: resolvedOutputScaleID())
            )
        ]
    }

    func setEditorFormTextFieldValue(_ value: String, for fieldID: String) {
        guard fieldID == indicatorsFieldID else { return }
        let includeWeight = formulaNeedsWeights(resolvedFormulaID())
        textFieldValues[fieldID] = normalizedIndicatorTableText(from: value, includeWeight: includeWeight)
        updateDynamicInputPorts()
    }

    func setEditorFormOptionValue(_ value: String, for fieldID: String) {
        var formulaChanged = false

        switch fieldID {
        case "evaluation_formula":
            if let choice = choiceID(for: value, in: formulaChoices) {
                optionFieldValues[fieldID] = choice.id
                formulaChanged = true
            }
        case "evaluation_grouping":
            if let choice = choiceID(for: value, in: groupingChoices) {
                optionFieldValues[fieldID] = choice.id
            }
        case "evaluation_output_scale":
            if let choice = choiceID(for: value, in: outputScaleChoices) {
                optionFieldValues[fieldID] = choice.id
            }
        default:
            break
        }

        applyOptionDefaultsIfNeeded()
        if formulaChanged {
            syncIndicatorRowsForCurrentFormula()
        }
        updateDynamicInputPorts()
    }

    private func parseIndicatorRows() -> [IndicatorRow] {
        let includeWeight = formulaNeedsWeights(resolvedFormulaID())
        let currentText = textFieldValues[indicatorsFieldID] ?? ""
        let rows = parseIndicatorRows(from: currentText, includeWeight: includeWeight)
        if !rows.isEmpty {
            return rows
        }
        return parseLegacyIndicatorRows(includeWeight: includeWeight)
    }

    private func parseIndicatorRows(from raw: String, includeWeight: Bool) -> [IndicatorRow] {
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
        return normalized
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { rawLine -> IndicatorRow? in
                let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty else { return nil }

                let normalizedLine = line
                    .replacingOccurrences(of: "｜", with: "|")
                    .replacingOccurrences(of: "：", with: ":")
                var components = normalizedLine
                    .split(separator: "|", omittingEmptySubsequences: false)
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

                if components.count == 1 && normalizedLine.contains(":") {
                    components = normalizedLine
                        .split(separator: ":", omittingEmptySubsequences: false)
                        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                }

                guard let nameRaw = components.first else { return nil }
                let name = nameRaw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return nil }

                var typeToken = components.count > 1 ? components[1] : "score"
                var weightToken = components.count > 2 ? components[2] : "1"

                // Backward compatibility: "type/weight"
                if components.count == 2 && typeToken.contains("/") {
                    let parts = typeToken
                        .split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
                        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    typeToken = parts.first ?? "score"
                    if parts.count > 1 {
                        weightToken = parts[1]
                    }
                }

                let type = normalizedIndicatorType(from: typeToken)
                let weight = includeWeight ? normalizedWeightText(from: weightToken) : "1"
                return IndicatorRow(name: name, type: type, weight: weight)
            }
    }

    private func parseLegacyIndicatorRows(includeWeight: Bool) -> [IndicatorRow] {
        let defs = parseKeyValuePairs(textFieldValues[legacyDefsFieldID] ?? "")
        let weights = Dictionary(
            uniqueKeysWithValues: parseKeyValuePairs(textFieldValues[legacyWeightsFieldID] ?? "")
                .map { ($0.key.lowercased(), normalizedWeightText(from: $0.value)) }
        )
        let scoreNames = parseKeyValuePairs(textFieldValues[legacyScoresFieldID] ?? "").map { $0.key }

        if !defs.isEmpty {
            return defs.map { pair in
                let normalizedType = normalizedIndicatorType(from: pair.value)
                let weight = includeWeight ? (weights[pair.key.lowercased()] ?? "1") : "1"
                return IndicatorRow(name: pair.key, type: normalizedType, weight: weight)
            }
        }

        return scoreNames.map { name in
            IndicatorRow(name: name, type: "score", weight: includeWeight ? (weights[name.lowercased()] ?? "1") : "1")
        }
    }

    private func parseKeyValuePairs(_ raw: String) -> [(key: String, value: String)] {
        raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { rawLine -> (String, String)? in
                let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty else { return nil }

                let normalized = line
                    .replacingOccurrences(of: "｜", with: "|")
                    .replacingOccurrences(of: "：", with: ":")
                if let marker = normalized.firstIndex(of: "|") ?? normalized.firstIndex(of: ":") {
                    let key = String(normalized[..<marker]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let valueStart = normalized.index(after: marker)
                    let value = String(normalized[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !key.isEmpty else { return nil }
                    return (key, value)
                }

                return (normalized, "")
            }
    }

    private func serializedIndicatorRows(_ rows: [IndicatorRow], includeWeight: Bool) -> String {
        rows
            .compactMap { row -> String? in
                let name = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return nil }
                let type = normalizedIndicatorType(from: row.type)
                if includeWeight {
                    let weight = normalizedWeightText(from: row.weight)
                    return "\(name) | \(type) | \(weight)"
                }
                return "\(name) | \(type)"
            }
            .joined(separator: "\n")
    }

    private func syncIndicatorRowsForCurrentFormula() {
        let includeWeight = formulaNeedsWeights(resolvedFormulaID())
        var rows = parseIndicatorRows(from: textFieldValues[indicatorsFieldID] ?? "", includeWeight: includeWeight)
        if rows.isEmpty {
            rows = parseLegacyIndicatorRows(includeWeight: includeWeight)
        }
        textFieldValues[indicatorsFieldID] = serializedIndicatorRows(rows, includeWeight: includeWeight)
    }

    private func normalizeStoredTextFieldValues() {
        syncIndicatorRowsForCurrentFormula()
    }

    private func normalizedIndicatorTableText(from raw: String, includeWeight: Bool) -> String {
        let rows = parseIndicatorRows(from: raw, includeWeight: includeWeight)
        return serializedIndicatorRows(rows, includeWeight: includeWeight)
    }

    private func updateDynamicInputPorts() {
        let existingInputs = inputs
        var rebuiltInputs: [AnyInputPort] = []
        let rows = parseIndicatorRows()
        for (index, row) in rows.enumerated() {
            let trimmedName = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let portName = trimmedName.isEmpty
                ? "\(S("edu.evaluation.autoIndicatorPrefix")) \(index + 1)"
                : trimmedName

            if index < existingInputs.count {
                var reusedPort = existingInputs[index]
                reusedPort.name = portName
                rebuiltInputs.append(reusedPort)
            } else {
                rebuiltInputs.append(AnyInputPort(name: portName, dataType: "Any"))
            }
        }
        inputs = rebuiltInputs
    }

    private func connectedIndicatorValue(at index: Int) -> String? {
        let dynamicStartIndex = 0
        let portIndex = dynamicStartIndex + index
        guard inputs.indices.contains(portIndex) else { return nil }
        guard let raw = stringValue(from: inputs[portIndex]) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func stringValue(from input: AnyInputPort) -> String? {
        if let value: StringData = ((try? input.getValue()) ?? nil) {
            return value.value
        }
        if let value: NumData = ((try? input.getValue()) ?? nil) {
            let number = value.toDouble()
            return number == number.rounded() ? "\(Int(number))" : "\(number)"
        }
        if let value: BoolData = ((try? input.getValue()) ?? nil) {
            return value.value ? "true" : "false"
        }
        if let value: ArrayData = ((try? input.getValue()) ?? nil) {
            return value.values
                .map { number in
                    number == number.rounded() ? "\(Int(number))" : "\(number)"
                }
                .joined(separator: ", ")
        }
        if let value: ObjectData = ((try? input.getValue()) ?? nil) {
            let fields = value.keys.map { key -> String in
                let display = value.get(key)?.displayString() ?? ""
                return "\(key): \(display)"
            }
            return "{\(fields.joined(separator: ", "))}"
        }
        return nil
    }

    private func isCompletionType(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let completionTokens = ["completion", "complete", "done", "yes/no", "binary", "完成", "达成", "是否完成", "完成制"]
        return completionTokens.contains(where: { normalized.contains($0) })
    }

    private func parsedScore5(from raw: String, isCompletion: Bool) -> Double {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if isCompletion {
            if ["yes", "y", "true", "completed", "done", "1", "完成", "已完成", "达成"].contains(trimmed) {
                return 5
            }
            if ["no", "n", "false", "0", "未完成", "未达成"].contains(trimmed) {
                return 0
            }
            if let number = Double(trimmed) {
                return number > 0 ? 5 : 0
            }
            return 0
        }

        guard let value = Double(trimmed) else { return 0 }
        return max(0, min(value, 5))
    }

    private func parsedWeight(_ raw: String) -> Double {
        let normalized = normalizedWeightText(from: raw)
        guard let value = Double(normalized), value > 0 else { return 1 }
        return value
    }

    private func computeScore5(
        rows: [(name: String, type: String, score5: Double, weight: Double)],
        formulaID: String
    ) -> Double {
        guard !rows.isEmpty else { return 0 }

        switch formulaID {
        case "weighted_avg":
            let totalWeight = rows.reduce(0) { $0 + $1.weight }
            guard totalWeight > 0 else { return 0 }
            return rows.reduce(0) { $0 + $1.score5 * $1.weight } / totalWeight

        case "geometric_mean":
            let normalized = rows.map { max(0.001, min($0.score5 / 5.0, 1.0)) }
            let product = normalized.reduce(1.0, *)
            let root = pow(product, 1.0 / Double(normalized.count))
            return root * 5.0

        case "sigmoid_curve":
            let mean = rows.reduce(0) { $0 + $1.score5 } / Double(rows.count)
            let scaled = 1.0 / (1.0 + exp(-2.2 * (mean - 2.5)))
            return scaled * 5.0

        default:
            return rows.reduce(0) { $0 + $1.score5 } / Double(rows.count)
        }
    }

    private func convertOutputValue(score5: Double, outputScaleID: String) -> EvaluationOutputValue {
        let clampedScore5 = max(0, min(score5, 5))
        let score100 = clampedScore5 / 5.0 * 100.0
        switch outputScaleID {
        case "grade_abcd":
            let grade: String
            switch score100 {
            case 90...:
                grade = "A"
            case 80..<90:
                grade = "B"
            case 70..<80:
                grade = "C"
            default:
                grade = "D"
            }
            return .text(grade)
        case "score5":
            return .number(clampedScore5)
        default:
            return .number(score100)
        }
    }

    private func normalizedIndicatorType(from raw: String) -> String {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.contains("completion")
            || normalized.contains("complete")
            || normalized.contains("完成")
            || normalized.contains("达成") {
            return "completion"
        }
        return "score"
    }

    private func normalizedWeightText(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(trimmed), value > 0 else { return "1" }
        if value == value.rounded() {
            return "\(Int(value))"
        }
        return String(value)
    }

    private func choiceID(for raw: String, in options: [OptionChoice]) -> OptionChoice? {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }

        if let byID = options.first(where: { $0.id.lowercased() == normalized }) {
            return byID
        }
        return options.first(where: { localizedChoiceTitle(for: $0).lowercased() == normalized })
    }

    private func applyOptionDefaultsIfNeeded() {
        if formulaChoices.contains(where: { $0.id == optionFieldValues["evaluation_formula"] }) == false {
            optionFieldValues["evaluation_formula"] = "average"
        }
        if groupingChoices.contains(where: { $0.id == optionFieldValues["evaluation_grouping"] }) == false {
            optionFieldValues["evaluation_grouping"] = "individual"
        }
        if outputScaleChoices.contains(where: { $0.id == optionFieldValues["evaluation_output_scale"] }) == false {
            optionFieldValues["evaluation_output_scale"] = "score100"
        }
    }

    private func resolvedFormulaID() -> String {
        return optionFieldValues["evaluation_formula"] ?? "average"
    }

    private func resolvedGroupingID() -> String {
        return optionFieldValues["evaluation_grouping"] ?? "individual"
    }

    private func resolvedOutputScaleID() -> String {
        optionFieldValues["evaluation_output_scale"] ?? "score100"
    }

    private func formulaNeedsWeights(_ formulaID: String) -> Bool {
        formulaID == "weighted_avg"
    }

    private func localizedFormulaTitle(for formulaID: String) -> String {
        if let choice = formulaChoices.first(where: { $0.id == formulaID }) {
            return localizedChoiceTitle(for: choice)
        }
        return localizedChoiceTitle(for: formulaChoices[0])
    }

    private func localizedGroupingTitle(for groupingID: String) -> String {
        if let choice = groupingChoices.first(where: { $0.id == groupingID }) {
            return localizedChoiceTitle(for: choice)
        }
        return localizedChoiceTitle(for: groupingChoices[0])
    }

    private func localizedOutputScaleTitle(for outputScaleID: String) -> String {
        if let choice = outputScaleChoices.first(where: { $0.id == outputScaleID }) {
            return localizedChoiceTitle(for: choice)
        }
        return localizedChoiceTitle(for: outputScaleChoices[0])
    }

    private func localizedChoiceTitle(for choice: OptionChoice) -> String {
        isChinese ? choice.titleZh : choice.titleEn
    }

    private var formulaChoices: [OptionChoice] {
        [
            OptionChoice(id: "average", titleEn: S("edu.evaluation.formula.average"), titleZh: S("edu.evaluation.formula.average")),
            OptionChoice(id: "weighted_avg", titleEn: S("edu.evaluation.formula.weightedAverage"), titleZh: S("edu.evaluation.formula.weightedAverage")),
            OptionChoice(id: "geometric_mean", titleEn: S("edu.evaluation.formula.geometricMean"), titleZh: S("edu.evaluation.formula.geometricMean")),
            OptionChoice(id: "sigmoid_curve", titleEn: S("edu.evaluation.formula.sigmoidCurve"), titleZh: S("edu.evaluation.formula.sigmoidCurve"))
        ]
    }

    private var groupingChoices: [OptionChoice] {
        [
            OptionChoice(id: "individual", titleEn: S("edu.evaluation.grouping.individual"), titleZh: S("edu.evaluation.grouping.individual")),
            OptionChoice(id: "group", titleEn: S("edu.evaluation.grouping.group"), titleZh: S("edu.evaluation.grouping.group")),
            OptionChoice(id: "auto", titleEn: S("edu.evaluation.grouping.auto"), titleZh: S("edu.evaluation.grouping.auto"))
        ]
    }

    private var outputScaleChoices: [OptionChoice] {
        [
            OptionChoice(id: "score100", titleEn: S("edu.evaluation.outputScale.score100"), titleZh: S("edu.evaluation.outputScale.score100")),
            OptionChoice(id: "score5", titleEn: S("edu.evaluation.outputScale.score5"), titleZh: S("edu.evaluation.outputScale.score5")),
            OptionChoice(id: "grade_abcd", titleEn: S("edu.evaluation.outputScale.gradeABCD"), titleZh: S("edu.evaluation.outputScale.gradeABCD"))
        ]
    }

    private var isChinese: Bool {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
    }
}

private func S(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}
