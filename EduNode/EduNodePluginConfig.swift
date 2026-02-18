import Foundation
import GNodeKit

enum EduNodeType {
    static let courseInfo = "EduCourseInfo"
    static let knowledge = "EduKnowledge"
    static let goal = "EduGoal"
    static let toolkit = "EduToolkit"
    static let metricValue = "EduMetricValue"
    static let evaluationMetric = "EduEvaluationMetric"
    static let evaluationSummary = "EduEvaluationSummary"
    static let generateLesson = "EduGenerateLesson"
    static let exportPPT = "EduExportPPT"
    static let model = "EduModel"
    static let timeBoundary = "EduTimeBoundary"
}

enum EduNodePluginConfig {
    private static var didConfigure = false

    static func configureIfNeeded() {
        guard !didConfigure else { return }
        didConfigure = true

        let toolkit = GNodeNodeKit.gnodeNodeKit
        toolkit.hideNodeTypesFromCanvas([
            "Num", "Bool", "String", "Array", "Object",
            "Math", "Compare", "Logic", "StringOp", "CollectionOp", "Select",
            "Condition", "Script", "Concat", "ArrayMath", "Add"
        ])

        registerNodes(into: toolkit)
        registerDocs()
    }

    private static func registerNodes(into toolkit: GNodeNodeKit) {
        // Internal/template node: canvas-level course info, not user-addable.
        registerEduTextNode(
            into: toolkit,
            type: EduNodeType.courseInfo,
            defaultName: S("menu.node.courseInfo"),
            defaultValue: "",
            outputName: S("edu.output.courseInfo"),
            placeholder: S("edu.courseInfo.placeholder"),
            menu: NodeMenuMetadata(
                title: S("menu.node.courseInfo"),
                sectionTitle: S("menu.section.core"),
                sectionOrder: 0,
                itemOrder: 0,
                isVisibleInCanvas: false
            )
        )

        registerKnowledgeNode(
            into: toolkit,
            type: EduNodeType.knowledge,
            defaultName: S("menu.node.knowledge"),
            defaultContent: "",
            menu: NodeMenuMetadata(
                title: S("menu.node.knowledge"),
                sectionTitle: S("menu.section.core"),
                sectionOrder: 0,
                itemOrder: 1,
                isVisibleInCanvas: true
            )
        )

        registerEduTextNode(
            into: toolkit,
            type: EduNodeType.goal,
            defaultName: S("menu.node.goal"),
            defaultValue: "",
            outputName: S("edu.output.goal"),
            placeholder: S("edu.goal.placeholder"),
            menu: NodeMenuMetadata(
                title: S("menu.node.goal"),
                sectionTitle: S("menu.section.core"),
                sectionOrder: 0,
                itemOrder: 2,
                isVisibleInCanvas: false
            )
        )

        registerToolkitNode(
            into: toolkit,
            type: EduNodeType.toolkit,
            defaultName: S("menu.node.toolkit"),
            defaultValue: "",
            menu: NodeMenuMetadata(
                title: S("menu.node.toolkit"),
                sectionTitle: S("menu.section.core"),
                sectionOrder: 0,
                itemOrder: 3,
                isVisibleInCanvas: true
            )
        )

        registerNumberNode(
            into: toolkit,
            type: EduNodeType.metricValue,
            defaultName: S("menu.node.metricValue"),
            defaultValue: 0,
            menu: NodeMenuMetadata(
                title: S("menu.node.metricValue"),
                sectionTitle: S("menu.section.evaluation"),
                sectionOrder: 1,
                itemOrder: 0,
                isVisibleInCanvas: true
            )
        )

        registerScriptNode(
            into: toolkit,
            type: EduNodeType.evaluationMetric,
            defaultName: S("menu.node.evalMetric"),
            defaultExpression: evaluationMetricScript(),
            menu: NodeMenuMetadata(
                title: S("menu.node.evalMetric"),
                sectionTitle: S("menu.section.evaluation"),
                sectionOrder: 1,
                itemOrder: 1,
                isVisibleInCanvas: true
            )
        )

        registerScriptNode(
            into: toolkit,
            type: EduNodeType.evaluationSummary,
            defaultName: S("menu.node.evalSummary"),
            defaultExpression: evaluationSummaryScript(),
            menu: NodeMenuMetadata(
                title: S("menu.node.evalSummary"),
                sectionTitle: S("menu.section.evaluation"),
                sectionOrder: 1,
                itemOrder: 2,
                isVisibleInCanvas: true
            )
        )

        registerScriptNode(
            into: toolkit,
            type: EduNodeType.generateLesson,
            defaultName: S("menu.node.generateLesson"),
            defaultExpression: generateLessonScript(),
            menu: NodeMenuMetadata(
                title: S("menu.node.generateLesson"),
                sectionTitle: S("menu.section.output"),
                sectionOrder: 2,
                itemOrder: 0,
                isVisibleInCanvas: true
            )
        )

        registerScriptNode(
            into: toolkit,
            type: EduNodeType.exportPPT,
            defaultName: S("menu.node.exportPpt"),
            defaultExpression: exportPPTScript(),
            menu: NodeMenuMetadata(
                title: S("menu.node.exportPpt"),
                sectionTitle: S("menu.section.output"),
                sectionOrder: 2,
                itemOrder: 1,
                isVisibleInCanvas: true
            )
        )

        // Internal/template nodes.
        registerEduTextNode(
            into: toolkit,
            type: EduNodeType.model,
            defaultName: S("template.model"),
            defaultValue: "",
            outputName: S("edu.output.model"),
            placeholder: S("edu.model.placeholder"),
            menu: NodeMenuMetadata(
                title: S("template.model"),
                sectionTitle: S("menu.section.core"),
                sectionOrder: 0,
                itemOrder: 99,
                isVisibleInCanvas: false
            )
        )

        registerNumberNode(
            into: toolkit,
            type: EduNodeType.timeBoundary,
            defaultName: S("template.lessonDuration"),
            defaultValue: 45,
            menu: NodeMenuMetadata(
                title: S("template.lessonDuration"),
                sectionTitle: S("menu.section.core"),
                sectionOrder: 0,
                itemOrder: 100,
                isVisibleInCanvas: false
            )
        )
    }

    private static func registerEduTextNode(
        into toolkit: GNodeNodeKit,
        type: String,
        defaultName: String,
        defaultValue: String,
        outputName: String,
        placeholder: String,
        menu: NodeMenuMetadata
    ) {
        toolkit.register(
            type: type,
            nodeClass: EduTextNode.self,
            menu: menu,
            create: {
                EduTextNode(name: defaultName, value: defaultValue, outputName: outputName, placeholder: placeholder)
            },
            encode: { node in
                guard let node = node as? EduTextNode else { return [:] }
                return ["value": node.editorTextValue]
            },
            decode: { serialized in
                let value = serialized.nodeData["value"] ?? defaultValue
                let node = EduTextNode(name: serialized.attributes.name, value: value, outputName: outputName, placeholder: placeholder)
                node.attributes = serialized.attributes
                return node
            }
        )
    }

    private static func registerKnowledgeNode(
        into toolkit: GNodeNodeKit,
        type: String,
        defaultName: String,
        defaultContent: String,
        menu: NodeMenuMetadata
    ) {
        toolkit.register(
            type: type,
            nodeClass: EduKnowledgeNode.self,
            menu: menu,
            create: {
                EduKnowledgeNode(name: defaultName, content: defaultContent)
            },
            encode: { node in
                guard let node = node as? EduKnowledgeNode else { return [:] }
                return [
                    "content": node.editorTextValue,
                    "level": node.editorSelectedOption
                ]
            },
            decode: { serialized in
                let content = serialized.nodeData["content"] ?? defaultContent
                let level = serialized.nodeData["level"] ?? EduKnowledgeNode.defaultLevel
                let node = EduKnowledgeNode(name: serialized.attributes.name, content: content, level: level)
                node.attributes = serialized.attributes
                return node
            }
        )
    }

    private static func registerToolkitNode(
        into toolkit: GNodeNodeKit,
        type: String,
        defaultName: String,
        defaultValue: String,
        menu: NodeMenuMetadata
    ) {
        toolkit.register(
            type: type,
            nodeClass: EduToolkitNode.self,
            menu: menu,
            create: {
                EduToolkitNode(name: defaultName, value: defaultValue)
            },
            encode: { node in
                guard let node = node as? EduToolkitNode else { return [:] }
                return [
                    "value": node.editorTextValue,
                    "toolkitType": node.editorSelectedOption
                ]
            },
            decode: { serialized in
                let value = serialized.nodeData["value"] ?? defaultValue
                let selectedType = serialized.nodeData["toolkitType"] ?? EduToolkitNode.defaultType
                let node = EduToolkitNode(
                    name: serialized.attributes.name,
                    value: value,
                    selectedType: selectedType
                )
                node.attributes = serialized.attributes
                return node
            }
        )
    }

    private static func registerNumberNode(
        into toolkit: GNodeNodeKit,
        type: String,
        defaultName: String,
        defaultValue: Double,
        menu: NodeMenuMetadata
    ) {
        toolkit.register(
            type: type,
            nodeClass: NumNode.self,
            menu: menu,
            create: {
                NumNode(name: defaultName, value: NumData(defaultValue))
            },
            encode: { node in
                guard let node = node as? NumNode else { return [:] }
                return ["value": "\(node.getValue().toDouble())"]
            },
            decode: { serialized in
                let value = Double(serialized.nodeData["value"] ?? "\(defaultValue)") ?? defaultValue
                let node = NumNode(name: serialized.attributes.name, value: NumData(value))
                node.attributes = serialized.attributes
                return node
            }
        )
    }

    private static func registerScriptNode(
        into toolkit: GNodeNodeKit,
        type: String,
        defaultName: String,
        defaultExpression: String,
        menu: NodeMenuMetadata
    ) {
        toolkit.register(
            type: type,
            nodeClass: ScriptNode.self,
            menu: menu,
            create: {
                ScriptNode(name: defaultName, expression: defaultExpression)
            },
            encode: { node in
                guard let node = node as? ScriptNode else { return [:] }
                return ["expression": node.getExpression()]
            },
            decode: { serialized in
                let expression = serialized.nodeData["expression"] ?? defaultExpression
                let node = ScriptNode(name: serialized.attributes.name, expression: expression)
                node.attributes = serialized.attributes
                return node
            }
        )
    }

    private static func registerDocs() {
        NodeDocumentation.setBuiltInDocsVisible(false)
        NodeDocumentation.clearExternalDocs()
        NodeDocumentation.registerExternalDocs(eduDocs())
    }

    private static func eduDocs() -> [NodeDoc] {
        let coreTitle = S("menu.section.core")
        let evalTitle = S("menu.section.evaluation")
        let outputTitle = S("menu.section.output")

        return [
            NodeDoc(
                type: EduNodeType.knowledge,
                name: S("menu.node.knowledge"),
                categoryKey: "core",
                categoryTitle: coreTitle,
                description: Bilingual.text(
                    en: "Defines one teachable knowledge unit with both direct form input and chainable input ports.",
                    zh: "定义一个可教授的知识单元，同时支持表单直填与端口连线输入。"
                ),
                inputs: [
                    PortDoc(
                        name: Bilingual.text(en: "Type", zh: "知识类型"),
                        type: "Any",
                        desc: Bilingual.text(
                            en: "Supports multiple links. Connected values are merged line-by-line; the first valid level is used.",
                            zh: "支持多连接。连线值会按行合并，并优先使用第一个有效层级。"
                        )
                    ),
                    PortDoc(
                        name: Bilingual.text(en: "Content", zh: "内容"),
                        type: "Any",
                        desc: Bilingual.text(
                            en: "Supports multiple links. Connected values are merged line-by-line and override manual content.",
                            zh: "支持多连接。连线内容会按行合并，并优先于手填内容。"
                        )
                    ),
                    PortDoc(
                        name: Bilingual.text(en: "Previous Content", zh: "上一个知识点内容"),
                        type: "Any",
                        desc: Bilingual.text(
                            en: "Supports multiple links. Used to chain knowledge flow from previous nodes.",
                            zh: "支持多连接。用于把前序知识点内容串联到当前节点。"
                        )
                    )
                ],
                outputs: [
                    PortDoc(name: S("edu.knowledge.output.content"), type: "String", desc: Bilingual.text(en: "Knowledge content text.", zh: "知识内容文本。")),
                    PortDoc(name: S("edu.knowledge.output.level"), type: "String", desc: Bilingual.text(en: "Knowledge level selected in dropdown.", zh: "下拉框选择的知识层级。"))
                ],
                processDesc: Bilingual.text(
                    en: "Inputs include both links and form fields. Multi-link inputs are merged line-by-line. Content priority: Content input > manual content > Previous Content. Level priority: Type input > dropdown.",
                    zh: "Input 包括连线端口与表单直填。多连接输入会按行合并。内容优先级：内容端口 > 手填内容 > 上一个知识点内容；层级优先级：类型端口 > 下拉框。"
                )
            ),
            NodeDoc(
                type: EduNodeType.toolkit,
                name: S("menu.node.toolkit"),
                categoryKey: "core",
                categoryTitle: coreTitle,
                description: Bilingual.text(en: "Represents one teaching activity block with educational method type presets.", zh: "表示一个教学活动环节，并提供教育学常见方法类型预设。"),
                inputs: [
                    PortDoc(
                        name: S("edu.toolkit.input.knowledge"),
                        type: "Any",
                        desc: Bilingual.text(en: "Supports multiple links; merged line-by-line as activity context.", zh: "支持多连接，并按行合并为活动上下文。")
                    ),
                    PortDoc(
                        name: S("edu.toolkit.input.support"),
                        type: "Any",
                        desc: Bilingual.text(en: "Supports multiple links for constraints/resources/notes.", zh: "支持多连接，用于补充条件、资源或备注。")
                    )
                ],
                outputs: [
                    PortDoc(name: S("edu.output.toolkit"), type: "String", desc: Bilingual.text(en: "Toolkit activity text.", zh: "环节活动文本。")),
                    PortDoc(name: S("edu.toolkit.output.type"), type: "String", desc: Bilingual.text(en: "Selected toolkit method type.", zh: "当前选择的教学法类型。"))
                ],
                processDesc: Bilingual.text(
                    en: "Inputs and manual text are merged into activity output. Type is selected from presets such as Game, Observation, Discussion, Inquiry, and Practice.",
                    zh: "会将输入端口与手填内容合并为活动输出。类型可从预设中选择，如游戏、观察法、讨论法、探究法、练习法等。"
                )
            ),
            NodeDoc(
                type: EduNodeType.metricValue,
                name: S("menu.node.metricValue"),
                categoryKey: "evaluation",
                categoryTitle: evalTitle,
                description: Bilingual.text(en: "Numeric evidence input for evaluation metrics.", zh: "用于评价指标的数值证据输入。"),
                inputs: [PortDoc(name: Bilingual.text(en: "Input", zh: "输入"), type: "Any", desc: Bilingual.text(en: "Accepts connected values with automatic conversion.", zh: "接收连接值并自动转换为数值。"))],
                outputs: [PortDoc(name: Bilingual.text(en: "Value", zh: "数值"), type: "Num", desc: Bilingual.text(en: "Numeric output for metric scripts.", zh: "输出给评价脚本的数值。"))],
                processDesc: Bilingual.text(en: "Holds a metric number and outputs Num data.", zh: "存储评价数值并输出 Num 数据。")
            ),
            NodeDoc(
                type: EduNodeType.evaluationMetric,
                name: S("menu.node.evalMetric"),
                categoryKey: "evaluation",
                categoryTitle: evalTitle,
                description: Bilingual.text(en: "Computes evaluation indicators from multiple evidence inputs.", zh: "基于多路证据输入计算评价指标。"),
                inputs: [PortDoc(name: Bilingual.text(en: "Inputs", zh: "输入"), type: "Any", desc: Bilingual.text(en: "Script parameters are exposed as input ports.", zh: "脚本参数会自动映射为输入端口。"))],
                outputs: [PortDoc(name: Bilingual.text(en: "Outputs", zh: "输出"), type: "Any", desc: Bilingual.text(en: "Returns score/level or custom fields.", zh: "输出得分、等级或自定义字段。"))],
                processDesc: Bilingual.text(en: "Runs script logic to generate metric results.", zh: "运行脚本逻辑生成评价结果。")
            ),
            NodeDoc(
                type: EduNodeType.evaluationSummary,
                name: S("menu.node.evalSummary"),
                categoryKey: "evaluation",
                categoryTitle: evalTitle,
                description: Bilingual.text(en: "Aggregates metric results into a final summary.", zh: "将多项评价结果汇总为最终结论。"),
                inputs: [PortDoc(name: Bilingual.text(en: "Inputs", zh: "输入"), type: "Any", desc: Bilingual.text(en: "Consumes metric outputs and context values.", zh: "接收指标输出与上下文数据。"))],
                outputs: [PortDoc(name: Bilingual.text(en: "Summary", zh: "汇总"), type: "Any", desc: Bilingual.text(en: "Final score/level style output.", zh: "输出最终分数或等级。"))],
                processDesc: Bilingual.text(en: "Combines indicators into final evaluation output.", zh: "将指标合成为最终评价输出。")
            ),
            NodeDoc(
                type: EduNodeType.generateLesson,
                name: S("menu.node.generateLesson"),
                categoryKey: "output",
                categoryTitle: outputTitle,
                description: Bilingual.text(en: "Generates lesson-plan content from course nodes.", zh: "基于课程节点生成教案内容。"),
                inputs: [PortDoc(name: Bilingual.text(en: "Inputs", zh: "输入"), type: "Any", desc: Bilingual.text(en: "Course, goals, metrics, and context inputs.", zh: "接收课程、目标、评价与上下文输入。"))],
                outputs: [PortDoc(name: Bilingual.text(en: "Plan", zh: "教案"), type: "Any", desc: Bilingual.text(en: "Generated lesson plan payload.", zh: "生成后的教案内容。"))],
                processDesc: Bilingual.text(en: "Formats structured teaching plan output.", zh: "格式化输出结构化教案。")
            ),
            NodeDoc(
                type: EduNodeType.exportPPT,
                name: S("menu.node.exportPpt"),
                categoryKey: "output",
                categoryTitle: outputTitle,
                description: Bilingual.text(en: "Converts lesson-plan content into presentation-ready output.", zh: "将教案内容转换为可导出展示内容。"),
                inputs: [PortDoc(name: Bilingual.text(en: "Plan", zh: "教案"), type: "Any", desc: Bilingual.text(en: "Accepts generated plan payload.", zh: "接收生成教案内容。"))],
                outputs: [PortDoc(name: Bilingual.text(en: "Slides", zh: "课件"), type: "Any", desc: Bilingual.text(en: "Presentation payload for PPT export.", zh: "用于 PPT 导出的展示内容。"))],
                processDesc: Bilingual.text(en: "Transforms plan data to slide-oriented output.", zh: "将教案数据转换为课件输出。")
            )
        ]
    }

    private static func evaluationMetricScript() -> String {
        """
function process(knowledge, engagement, participation) {
    var k = Number(knowledge) || 0;
    var e = Number(engagement) || 0;
    var p = Number(participation) || 0;
    var score = k * 0.5 + e * 0.3 + p * 0.2;
    var level = score >= 85 ? "A" : (score >= 70 ? "B" : "C");
    var focus = k < 70 ? "knowledge reinforcement" : (e < 70 ? "engagement design" : "stable");
    return { score: score, level: level, focus: focus };
}
"""
    }

    private static func evaluationSummaryScript() -> String {
        """
function process(metricScore, metricFocus) {
    var m = Number(metricScore) || 0;
    var focusText = String(metricFocus || "");
    var overall = m;
    var level = overall >= 85 ? "A" : (overall >= 70 ? "B" : "C");
    var summary = "Level " + level + ", score " + overall + ". Focus: " + focusText;
    return { overall: overall, level: level, summary: summary };
}
"""
    }

    private static func generateLessonScript() -> String {
        """
function process(summary, knowledge, toolkit) {
    var title = "Lesson Plan";
    var modelName = "General";
    var duration = 45;
    var goalText = "No goals";
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
    }

    private static func exportPPTScript() -> String {
        """
function process(markdown) {
    var title = "Lesson Deck";
    var md = String(markdown || "");
    var html = "<section><h1>" + title + "</h1><pre>" + md + "</pre></section>";
    return { html: html };
}
"""
    }

    private static func S(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }
}

private enum Bilingual {
    static func text(en: String, zh: String) -> String {
        let isChinese = Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
        return isChinese ? zh : en
    }
}
