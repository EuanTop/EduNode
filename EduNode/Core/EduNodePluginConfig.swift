import Foundation
import GNodeKit
import SwiftUI

enum EduNodeType {
    static let courseInfo = "EduCourseInfo"
    static let knowledge = "EduKnowledge"
    static let goal = "EduGoal"
    static let evaluation = "EduEvaluation"
    static let toolkit = "EduToolkit" // Legacy compatibility node type.
    static let toolkitPerceptionInquiry = "EduToolkitPerceptionInquiry"
    static let toolkitConstructionPrototype = "EduToolkitConstructionPrototype"
    static let toolkitCommunicationNegotiation = "EduToolkitCommunicationNegotiation"
    static let toolkitRegulationMetacognition = "EduToolkitRegulationMetacognition"
    static let metricValue = "EduMetricValue"
    static let evaluationMetric = "EduEvaluationMetric"
    static let evaluationSummary = "EduEvaluationSummary"
    static let model = "EduModel"
    static let timeBoundary = "EduTimeBoundary"

    static let visibleToolkitTypes: [String] = [
        toolkitPerceptionInquiry,
        toolkitConstructionPrototype,
        toolkitCommunicationNegotiation,
        toolkitRegulationMetacognition
    ]

    static let allToolkitTypes: [String] = visibleToolkitTypes + [toolkit]
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

        configureNodeStyles()
        registerNodes(into: toolkit)
        registerDocs()
    }

    private static func configureNodeStyles() {
        NodeVisualStyleRegistry.setStyle(
            NodeVisualStyle(
                backgroundColor: Color(red: 0.12, green: 0.28, blue: 0.30),
                selectedBorderColor: .accentColor,
                menuDotColor: .teal,
                shape: .rounded,
                topRightSystemImage: "wrench.adjustable.fill"
            ),
            for: EduNodeType.toolkitPerceptionInquiry
        )

        NodeVisualStyleRegistry.setStyle(
            NodeVisualStyle(
                backgroundColor: Color(red: 0.34, green: 0.22, blue: 0.12),
                selectedBorderColor: .accentColor,
                menuDotColor: .orange,
                shape: .rounded,
                topRightSystemImage: "wrench.adjustable.fill"
            ),
            for: EduNodeType.toolkitConstructionPrototype
        )

        NodeVisualStyleRegistry.setStyle(
            NodeVisualStyle(
                backgroundColor: Color(red: 0.18, green: 0.18, blue: 0.36),
                selectedBorderColor: .accentColor,
                menuDotColor: .indigo,
                shape: .rounded,
                topRightSystemImage: "wrench.adjustable.fill"
            ),
            for: EduNodeType.toolkitCommunicationNegotiation
        )

        NodeVisualStyleRegistry.setStyle(
            NodeVisualStyle(
                backgroundColor: Color(red: 0.14, green: 0.30, blue: 0.20),
                selectedBorderColor: .accentColor,
                menuDotColor: .mint,
                shape: .rounded,
                topRightSystemImage: "wrench.adjustable.fill"
            ),
            for: EduNodeType.toolkitRegulationMetacognition
        )

        NodeVisualStyleRegistry.setStyle(
            NodeVisualStyle(
                backgroundColor: Color(red: 0.20, green: 0.22, blue: 0.30),
                selectedBorderColor: .accentColor,
                menuDotColor: .cyan,
                shape: .rounded,
                topRightSystemImage: "wrench.adjustable.fill"
            ),
            for: EduNodeType.toolkit
        )

        NodeVisualStyleRegistry.setStyle(
            NodeVisualStyle(
                backgroundColor: Color(red: 0.16, green: 0.16, blue: 0.24),
                selectedBorderColor: .accentColor,
                menuDotColor: .orange,
                shape: .rounded,
                topRightSystemImage: "checklist"
            ),
            for: EduNodeType.evaluation
        )
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

        registerEvaluationNode(
            into: toolkit,
            type: EduNodeType.evaluation,
            defaultName: S("menu.node.evaluation"),
            menu: NodeMenuMetadata(
                title: S("menu.node.evaluation"),
                sectionTitle: S("menu.section.core"),
                sectionOrder: 0,
                itemOrder: 2,
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
            type: EduNodeType.toolkitPerceptionInquiry,
            category: .perceptionInquiry,
            defaultName: S("menu.node.perceptionInquiry"),
            defaultValue: "",
            menu: NodeMenuMetadata(
                title: S("menu.node.perceptionInquiry"),
                sectionTitle: S("menu.section.toolkit"),
                sectionOrder: 1,
                itemOrder: 3,
                isVisibleInCanvas: true
            )
        )

        registerToolkitNode(
            into: toolkit,
            type: EduNodeType.toolkitConstructionPrototype,
            category: .constructionPrototype,
            defaultName: S("menu.node.constructionPrototype"),
            defaultValue: "",
            menu: NodeMenuMetadata(
                title: S("menu.node.constructionPrototype"),
                sectionTitle: S("menu.section.toolkit"),
                sectionOrder: 1,
                itemOrder: 4,
                isVisibleInCanvas: true
            )
        )

        registerToolkitNode(
            into: toolkit,
            type: EduNodeType.toolkitCommunicationNegotiation,
            category: .communicationNegotiation,
            defaultName: S("menu.node.communicationNegotiation"),
            defaultValue: "",
            menu: NodeMenuMetadata(
                title: S("menu.node.communicationNegotiation"),
                sectionTitle: S("menu.section.toolkit"),
                sectionOrder: 1,
                itemOrder: 5,
                isVisibleInCanvas: true
            )
        )

        registerToolkitNode(
            into: toolkit,
            type: EduNodeType.toolkitRegulationMetacognition,
            category: .regulationMetacognition,
            defaultName: S("menu.node.regulationMetacognition"),
            defaultValue: "",
            menu: NodeMenuMetadata(
                title: S("menu.node.regulationMetacognition"),
                sectionTitle: S("menu.section.toolkit"),
                sectionOrder: 1,
                itemOrder: 6,
                isVisibleInCanvas: true
            )
        )

        // Legacy toolkit node type remains decodable for old documents.
        registerLegacyToolkitNode(
            into: toolkit,
            type: EduNodeType.toolkit,
            defaultName: S("menu.node.toolkit"),
            defaultValue: "",
            menu: NodeMenuMetadata(
                title: S("menu.node.toolkit"),
                sectionTitle: S("menu.section.toolkit"),
                sectionOrder: 1,
                itemOrder: 99,
                isVisibleInCanvas: false
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
                sectionOrder: 2,
                itemOrder: 0,
                isVisibleInCanvas: false
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
                sectionOrder: 2,
                itemOrder: 1,
                isVisibleInCanvas: false
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
                sectionOrder: 2,
                itemOrder: 2,
                isVisibleInCanvas: false
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

    private static func registerEvaluationNode(
        into toolkit: GNodeNodeKit,
        type: String,
        defaultName: String,
        menu: NodeMenuMetadata
    ) {
        toolkit.register(
            type: type,
            nodeClass: EduEvaluationNode.self,
            menu: menu,
            create: {
                return EduEvaluationNode(name: defaultName)
            },
            encode: { node in
                guard let node = node as? EduEvaluationNode else { return [:] }
                return [
                    "evaluationTextFields": encodeJSONStringDictionary(node.serializedTextFieldValues),
                    "evaluationOptionFields": encodeJSONStringDictionary(node.serializedOptionFieldValues)
                ]
            },
            decode: { serialized in
                let textFieldValues = decodeJSONStringDictionary(serialized.nodeData["evaluationTextFields"])
                let optionFieldValues = decodeJSONStringDictionary(serialized.nodeData["evaluationOptionFields"])
                let node = EduEvaluationNode(
                    name: serialized.attributes.name,
                    textFieldValues: textFieldValues,
                    optionFieldValues: optionFieldValues
                )
                node.attributes = serialized.attributes
                return node
            }
        )
    }

    private static func registerToolkitNode(
        into toolkit: GNodeNodeKit,
        type: String,
        category: EduToolkitCategory,
        defaultName: String,
        defaultValue: String,
        menu: NodeMenuMetadata
    ) {
        toolkit.register(
            type: type,
            nodeClass: EduToolkitNode.self,
            menu: menu,
            create: {
                EduToolkitNode(name: defaultName, category: category, value: defaultValue)
            },
            encode: { node in
                guard let node = node as? EduToolkitNode else { return [:] }
                return [
                    "toolkitType": node.editorSelectedOption,
                    "toolkitMethodID": node.serializedMethodID,
                    "toolkitCategory": node.serializedCategoryID,
                    "toolkitTextFields": encodeJSONStringDictionary(node.serializedTextFieldValues),
                    "toolkitOptionFields": encodeJSONStringDictionary(node.serializedOptionFieldValues)
                ]
            },
            decode: { serialized in
                let value = serialized.nodeData["value"] ?? defaultValue
                let selectedType = serialized.nodeData["toolkitType"]
                let selectedMethodID = serialized.nodeData["toolkitMethodID"]
                let textFieldValues = decodeJSONStringDictionary(serialized.nodeData["toolkitTextFields"])
                let optionFieldValues = decodeJSONStringDictionary(serialized.nodeData["toolkitOptionFields"])
                let node = EduToolkitNode(
                    name: serialized.attributes.name,
                    category: category,
                    value: value,
                    selectedMethodID: selectedMethodID,
                    selectedType: selectedType,
                    textFieldValues: textFieldValues,
                    optionFieldValues: optionFieldValues
                )
                node.attributes = serialized.attributes
                return node
            }
        )
    }

    private static func registerLegacyToolkitNode(
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
                EduToolkitNode(
                    name: defaultName,
                    category: .communicationNegotiation,
                    value: defaultValue
                )
            },
            encode: { node in
                guard let node = node as? EduToolkitNode else { return [:] }
                return [
                    "toolkitType": node.editorSelectedOption,
                    "toolkitMethodID": node.serializedMethodID,
                    "toolkitCategory": node.serializedCategoryID,
                    "toolkitTextFields": encodeJSONStringDictionary(node.serializedTextFieldValues),
                    "toolkitOptionFields": encodeJSONStringDictionary(node.serializedOptionFieldValues)
                ]
            },
            decode: { serialized in
                let value = serialized.nodeData["value"] ?? defaultValue
                let selectedType = serialized.nodeData["toolkitType"]
                let selectedMethodID = serialized.nodeData["toolkitMethodID"]
                let rawCategory = serialized.nodeData["toolkitCategory"] ?? ""
                let fallbackCategory = inferLegacyToolkitCategory(from: selectedType)
                let category = EduToolkitCategory(rawValue: rawCategory) ?? fallbackCategory
                let textFieldValues = decodeJSONStringDictionary(serialized.nodeData["toolkitTextFields"])
                let optionFieldValues = decodeJSONStringDictionary(serialized.nodeData["toolkitOptionFields"])

                let node = EduToolkitNode(
                    name: serialized.attributes.name,
                    category: category,
                    value: value,
                    selectedMethodID: selectedMethodID,
                    selectedType: selectedType,
                    textFieldValues: textFieldValues,
                    optionFieldValues: optionFieldValues
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
        let modelTitle = Bilingual.text(en: "Education Models", zh: "教育模型")
        let coreTitle = S("menu.section.core")
        let toolkitTitle = S("menu.section.toolkit")

        return modelTemplateDocs(categoryTitle: modelTitle) + [
            NodeDoc(
                type: EduNodeType.knowledge,
                name: S("menu.node.knowledge"),
                categoryKey: "core",
                categoryTitle: coreTitle,
                description: Bilingual.text(
                    en: "Defines one teachable knowledge unit. Content is edited in the text box, and Type is selected from Bloom taxonomy dropdown.",
                    zh: "定义一个可教授知识单元。Content 通过文本框填写，Type 通过 Bloom 分类法下拉框选择。"
                ),
                inputs: [
                    PortDoc(
                        name: Bilingual.text(en: "Previous Content", zh: "上一个知识点内容"),
                        type: "Any",
                        desc: Bilingual.text(
                            en: "Optional link from previous knowledge node. Used when chaining knowledge flow across nodes.",
                            zh: "可选连接。用于把前序知识点内容串联到当前节点。"
                        )
                    )
                ],
                outputs: [
                    PortDoc(name: S("edu.knowledge.output.content"), type: "String", desc: Bilingual.text(en: "Knowledge content text.", zh: "知识内容文本。")),
                    PortDoc(name: S("edu.knowledge.output.level"), type: "String", desc: Bilingual.text(en: "Bloom knowledge type selected in dropdown.", zh: "下拉框中选择的 Bloom 知识类型。"))
                ],
                processDesc: Bilingual.text(
                    en: "Reads content from the Content text box. If Content is empty, it falls back to Previous Content input. Type always uses the dropdown selection.",
                    zh: "优先读取 Content 文本框；当 Content 为空时，回退使用“上一个知识点内容”输入。Type 始终以节点下拉框选择为准。"
                ),
                detailSections: knowledgeDetailSections(),
                exampleScenario: knowledgeExampleScenario()
            ),
            NodeDoc(
                type: EduNodeType.toolkitPerceptionInquiry,
                name: S("menu.node.perceptionInquiry"),
                categoryKey: "toolkit",
                categoryTitle: toolkitTitle,
                description: Bilingual.text(
                    en: "Collects information and observation evidence for inquiry-oriented learning.",
                    zh: "用于采集信息与观察证据，支撑探究导向学习。"
                ),
                inputs: [
                    PortDoc(
                        name: S("edu.toolkit.input.knowledge"),
                        type: "Any",
                        desc: Bilingual.text(
                            en: "Optional knowledge context input from previous nodes. Supports multiple links.",
                            zh: "可选知识上下文输入，支持多连接。"
                        )
                    )
                ],
                outputs: [
                    PortDoc(name: S("edu.output.toolkit"), type: "String", desc: Bilingual.text(en: "Activity description output.", zh: "输出活动描述文本。")),
                    PortDoc(name: S("edu.toolkit.output.type"), type: "String", desc: Bilingual.text(en: "Selected method of this node.", zh: "输出当前节点所选方法。"))
                ],
                processDesc: Bilingual.text(
                    en: "Combines Knowledge input with method-specific form fields, then outputs an activity description and the selected method.",
                    zh: "将 Knowledge 输入与所选方法的专属表单字段合并，输出活动描述与当前方法名。"
                ),
                detailSections: toolkitMethodSections(
                    category: .perceptionInquiry,
                    toolkitType: EduNodeType.toolkitPerceptionInquiry
                )
            ),
            NodeDoc(
                type: EduNodeType.toolkitConstructionPrototype,
                name: S("menu.node.constructionPrototype"),
                categoryKey: "toolkit",
                categoryTitle: toolkitTitle,
                description: Bilingual.text(
                    en: "Supports externalization activities such as constructing models or prototypes.",
                    zh: "用于支持建构与原型化等外化活动设计。"
                ),
                inputs: [
                    PortDoc(
                        name: S("edu.toolkit.input.knowledge"),
                        type: "Any",
                        desc: Bilingual.text(
                            en: "Optional knowledge context input from previous nodes. Supports multiple links.",
                            zh: "可选知识上下文输入，支持多连接。"
                        )
                    )
                ],
                outputs: [
                    PortDoc(name: S("edu.output.toolkit"), type: "String", desc: Bilingual.text(en: "Activity description output.", zh: "输出活动描述文本。")),
                    PortDoc(name: S("edu.toolkit.output.type"), type: "String", desc: Bilingual.text(en: "Selected method of this node.", zh: "输出当前节点所选方法。"))
                ],
                processDesc: Bilingual.text(
                    en: "Combines Knowledge input with method-specific form fields, then outputs an activity description and the selected method.",
                    zh: "将 Knowledge 输入与所选方法的专属表单字段合并，输出活动描述与当前方法名。"
                ),
                detailSections: toolkitMethodSections(
                    category: .constructionPrototype,
                    toolkitType: EduNodeType.toolkitConstructionPrototype
                )
            ),
            NodeDoc(
                type: EduNodeType.toolkitCommunicationNegotiation,
                name: S("menu.node.communicationNegotiation"),
                categoryKey: "toolkit",
                categoryTitle: toolkitTitle,
                description: Bilingual.text(
                    en: "Designs communication and social negotiation activities in classroom interaction.",
                    zh: "用于设计课堂中的沟通与社会协商活动。"
                ),
                inputs: [
                    PortDoc(
                        name: S("edu.toolkit.input.knowledge"),
                        type: "Any",
                        desc: Bilingual.text(
                            en: "Optional knowledge context input from previous nodes. Supports multiple links.",
                            zh: "可选知识上下文输入，支持多连接。"
                        )
                    )
                ],
                outputs: [
                    PortDoc(name: S("edu.output.toolkit"), type: "String", desc: Bilingual.text(en: "Activity description output.", zh: "输出活动描述文本。")),
                    PortDoc(name: S("edu.toolkit.output.type"), type: "String", desc: Bilingual.text(en: "Selected method of this node.", zh: "输出当前节点所选方法。"))
                ],
                processDesc: Bilingual.text(
                    en: "Combines Knowledge input with method-specific form fields, then outputs an activity description and the selected method.",
                    zh: "将 Knowledge 输入与所选方法的专属表单字段合并，输出活动描述与当前方法名。"
                ),
                detailSections: toolkitMethodSections(
                    category: .communicationNegotiation,
                    toolkitType: EduNodeType.toolkitCommunicationNegotiation
                )
            ),
            NodeDoc(
                type: EduNodeType.toolkitRegulationMetacognition,
                name: S("menu.node.regulationMetacognition"),
                categoryKey: "toolkit",
                categoryTitle: toolkitTitle,
                description: Bilingual.text(
                    en: "Designs reflection, monitoring and metacognitive regulation activities.",
                    zh: "用于设计反思、监控与元认知调节活动。"
                ),
                inputs: [
                    PortDoc(
                        name: S("edu.toolkit.input.knowledge"),
                        type: "Any",
                        desc: Bilingual.text(
                            en: "Optional knowledge context input from previous nodes. Supports multiple links.",
                            zh: "可选知识上下文输入，支持多连接。"
                        )
                    )
                ],
                outputs: [
                    PortDoc(name: S("edu.output.toolkit"), type: "String", desc: Bilingual.text(en: "Activity description output.", zh: "输出活动描述文本。")),
                    PortDoc(name: S("edu.toolkit.output.type"), type: "String", desc: Bilingual.text(en: "Selected method of this node.", zh: "输出当前节点所选方法。"))
                ],
                processDesc: Bilingual.text(
                    en: "Combines Knowledge input with method-specific form fields, then outputs an activity description and the selected method.",
                    zh: "将 Knowledge 输入与所选方法的专属表单字段合并，输出活动描述与当前方法名。"
                ),
                detailSections: toolkitMethodSections(
                    category: .regulationMetacognition,
                    toolkitType: EduNodeType.toolkitRegulationMetacognition
                )
            ),
            NodeDoc(
                type: EduNodeType.evaluation,
                name: S("menu.node.evaluation"),
                categoryKey: "core",
                categoryTitle: coreTitle,
                description: Bilingual.text(
                    en: "One unified evaluation node for indicator setup, formula selection, and score output.",
                    zh: "统一评价节点：在同一节点完成指标配置、公式选择与得分输出。"
                ),
                inputs: [
                    PortDoc(
                        name: Bilingual.text(en: "Indicator Inputs (Dynamic)", zh: "指标输入（动态）"),
                        type: "Any",
                        desc: Bilingual.text(
                            en: "The node creates one input port for each indicator row in the table. Connect one Knowledge/Toolkit source per row.",
                            zh: "节点会根据指标表每一行自动生成一个输入端口。每行连接一个 Knowledge/Toolkit 来源。"
                        )
                    )
                ],
                outputs: [
                    PortDoc(
                        name: S("edu.evaluation.output.score"),
                        type: "Any",
                        desc: Bilingual.text(
                            en: "Final score output. Supports 100-point, 5-point, and ABCD level scales from the same node.",
                            zh: "最终成绩输出。可在同一节点选择百分制、五分制或 ABCD 等级制。"
                        )
                    )
                ],
                processDesc: Bilingual.text(
                    en: "Supports score-type (0-5) and completion-type (0/5) indicators. Weighted Average shows an extra Weight column in the indicator table.",
                    zh: "支持分数制（0-5）与完成制（0/5）指标。选择加权平均时，指标表会新增权重列。"
                ),
                exampleScenario: tutorialPhysicsMicroLessonScenario()
            )
        ]
    }

    private static func modelTemplateDocs(categoryTitle: String) -> [NodeDoc] {
        [
            NodeDoc(
                type: "EduModelTemplateUbD",
                name: Bilingual.text(en: "Understanding by Design (UbD)", zh: "逆向设计（UbD）"),
                categoryKey: "model",
                categoryTitle: categoryTitle,
                description: Bilingual.text(
                    en: "A backward-design model centered on desired results, evidence, and aligned learning experiences.",
                    zh: "以“预期结果-证据-学习体验”逆向设计为核心的教育模型。"
                ),
                inputs: modelTemplateInputs(),
                outputs: modelTemplateOutputs(),
                processDesc: Bilingual.text(
                    en: "Build a results-first chain (K1-K3), then connect Toolkit execution (T1-T4) to evidence criteria.",
                    zh: "先构建结果导向链路（K1-K3），再把 Toolkit 执行链（T1-T4）与证据标准对齐。"
                ),
                detailSections: [
                    detailSection(
                        id: "ipo_overview",
                        enTitle: "IPO Overview",
                        zhTitle: "IPO 概览",
                        enBody: "Input: course context + core objective.\nProcess: Desired Results -> Acceptable Evidence -> Learning Plan, then Hook/Task/Discussion/Reflection execution.\nOutput: an evidence-aligned lesson chain for planning and PPT generation.",
                        zhBody: "Input：课程背景 + 核心目标。\nProcess：预期结果 -> 可接受证据 -> 学习体验规划，再进入导入/任务/讨论/反思执行链。\nOutput：得到证据对齐的课堂链路，可直接用于讲义与 PPT 生成。",
                        initiallyExpanded: true
                    ),
                    detailSection(
                        id: "node_sequence",
                        enTitle: "Node Sequence (L->R / T->B)",
                        zhTitle: "节点序列（左到右 / 上到下）",
                        enBody: "1) K1 Desired Results\n2) K2 Acceptable Evidence\n3) K3 Learning Plan\n4) T1 Hook & Diagnose\n5) T2 Build Through Task\n6) T3 Discussion & Expression\n7) T4 Reflect & Close",
                        zhBody: "1）K1 预期结果\n2）K2 可接受证据\n3）K3 学习体验规划\n4）T1 导入与诊断\n5）T2 任务建构\n6）T3 讨论表达\n7）T4 收束反思"
                    ),
                    detailSection(
                        id: "fit_case",
                        enTitle: "When To Use",
                        zhTitle: "适用场景",
                        enBody: "Use when objectives and evidence standards must be explicit before activity design.",
                        zhBody: "适用于需要先明确目标与证据标准，再设计活动链路的课程。"
                    )
                ],
                exampleScenario: ubdModelTemplateScenario()
            ),
            NodeDoc(
                type: "EduModelTemplate5E",
                name: Bilingual.text(en: "5E Instructional Model", zh: "5E 探究模型"),
                categoryKey: "model",
                categoryTitle: categoryTitle,
                description: Bilingual.text(
                    en: "An inquiry-sequence model: Engage, Explore, Explain, Elaborate, Evaluate.",
                    zh: "探究序列教育模型：Engage、Explore、Explain、Elaborate、Evaluate。"
                ),
                inputs: modelTemplateInputs(),
                outputs: modelTemplateOutputs(),
                processDesc: Bilingual.text(
                    en: "Alternate Knowledge and Toolkit nodes by stage to form a complete inquiry progression.",
                    zh: "按阶段交替组织 Knowledge 与 Toolkit 节点，形成完整探究推进链。"
                ),
                detailSections: [
                    detailSection(
                        id: "ipo_overview",
                        enTitle: "IPO Overview",
                        zhTitle: "IPO 概览",
                        enBody: "Input: driving question + class context.\nProcess: K/T stage alternation across Engage -> Explore -> Explain -> Elaborate -> Evaluate.\nOutput: a stable inquiry teaching flow with direct slide ordering.",
                        zhBody: "Input：驱动问题 + 课堂背景。\nProcess：按 Engage -> Explore -> Explain -> Elaborate -> Evaluate 进行 K/T 交替推进。\nOutput：得到完整探究教学流，并保持稳定的幻灯片顺序。",
                        initiallyExpanded: true
                    ),
                    detailSection(
                        id: "node_sequence",
                        enTitle: "Node Sequence (L->R / T->B)",
                        zhTitle: "节点序列（左到右 / 上到下）",
                        enBody: "K1 Engage -> T1 Engage -> K2 Explore -> T2 Explore -> K3 Explain -> T3 Explain -> K4 Elaborate -> T4 Elaborate -> K5 Evaluate -> T5 Evaluate",
                        zhBody: "K1 Engage -> T1 Engage -> K2 Explore -> T2 Explore -> K3 Explain -> T3 Explain -> K4 Elaborate -> T4 Elaborate -> K5 Evaluate -> T5 Evaluate"
                    ),
                    detailSection(
                        id: "fit_case",
                        enTitle: "When To Use",
                        zhTitle: "适用场景",
                        enBody: "Best for science inquiry and question-driven lessons requiring gradual concept building.",
                        zhBody: "适用于科学探究与问题驱动课程，强调概念渐进建构。"
                    )
                ],
                exampleScenario: fiveEModelTemplateScenario()
            ),
            NodeDoc(
                type: "EduModelTemplateKolb",
                name: Bilingual.text(en: "Kolb Experiential Cycle", zh: "Kolb 体验学习循环"),
                categoryKey: "model",
                categoryTitle: categoryTitle,
                description: Bilingual.text(
                    en: "An experiential-cycle model mapped to a non-cyclic execution graph for safe runtime.",
                    zh: "体验学习循环教育模型（执行图为无环结构，保证运行安全）。"
                ),
                inputs: modelTemplateInputs(),
                outputs: modelTemplateOutputs(),
                processDesc: Bilingual.text(
                    en: "Map the four Kolb stages into a left-to-right DAG: Experience -> Reflection -> Conceptualization -> Experimentation.",
                    zh: "将 Kolb 四阶段映射为左到右无环链：体验 -> 反思 -> 概念化 -> 主动实验。"
                ),
                detailSections: [
                    detailSection(
                        id: "ipo_overview",
                        enTitle: "IPO Overview",
                        zhTitle: "IPO 概览",
                        enBody: "Input: initial experience trigger + objective.\nProcess: each stage has a paired Toolkit action, but graph remains acyclic for execution.\nOutput: one completed cycle that can be manually iterated in the next lesson.",
                        zhBody: "Input：起始体验触发点 + 教学目标。\nProcess：每阶段配一类 Toolkit 行动，但整体保持无环执行图。\nOutput：得到可落地的一轮体验学习闭环（下一轮由教师手动续接）。",
                        initiallyExpanded: true
                    ),
                    detailSection(
                        id: "node_sequence",
                        enTitle: "Node Sequence (L->R / T->B)",
                        zhTitle: "节点序列（左到右 / 上到下）",
                        enBody: "K1 Concrete Experience -> T1 Experience Capture -> K2 Reflective Observation -> T2 Reflection -> K3 Abstract Conceptualization -> T3 Concept Build -> K4 Active Experimentation -> T4 Experiment & Share",
                        zhBody: "K1 具体体验 -> T1 体验采集 -> K2 反思观察 -> T2 反思工具 -> K3 抽象概念化 -> T3 建构工具 -> K4 主动实验 -> T4 实验沟通"
                    ),
                    detailSection(
                        id: "fit_case",
                        enTitle: "When To Use",
                        zhTitle: "适用场景",
                        enBody: "Suitable for project-based and practice-heavy lessons where reflection quality matters.",
                        zhBody: "适用于项目实践类课程，强调“体验后反思”的学习质量。"
                    )
                ],
                exampleScenario: kolbModelTemplateScenario()
            ),
            NodeDoc(
                type: "EduModelTemplateBOPPPS",
                name: Bilingual.text(en: "BOPPPS Model", zh: "BOPPPS 模型"),
                categoryKey: "model",
                categoryTitle: categoryTitle,
                description: Bilingual.text(
                    en: "A compact lesson model with Bridge-in, Objective, Pre-assessment, Participatory, Post-assessment, Summary.",
                    zh: "紧凑型单课时教育模型：Bridge-in、Objective、Pre-assessment、Participatory、Post-assessment、Summary。"
                ),
                inputs: modelTemplateInputs(),
                outputs: modelTemplateOutputs(),
                processDesc: Bilingual.text(
                    en: "Run a concise lesson with a branching participatory segment and a merged assessment/summary closure.",
                    zh: "以紧凑节奏推进课堂，中段参与环节分支，后段汇合到检核与总结。"
                ),
                detailSections: [
                    detailSection(
                        id: "ipo_overview",
                        enTitle: "IPO Overview",
                        zhTitle: "IPO 概览",
                        enBody: "Input: lesson objective + baseline assumptions.\nProcess: Bridge-in -> Objective -> Pre-assessment -> Participatory (Path A/B) -> Post-assessment -> Summary.\nOutput: a complete short-lesson chain with explicit opening and closure.",
                        zhBody: "Input：课时目标 + 起点假设。\nProcess：Bridge-in -> Objective -> Pre-assessment -> Participatory（A/B 路径）-> Post-assessment -> Summary。\nOutput：得到“有导入、有参与、有收束”的完整短课链路。",
                        initiallyExpanded: true
                    ),
                    detailSection(
                        id: "node_sequence",
                        enTitle: "Node Sequence (L->R / T->B)",
                        zhTitle: "节点序列（左到右 / 上到下）",
                        enBody: "K1 Bridge-in -> T1 Bridge-in -> K2 Objective -> K3 Pre-assessment -> T2 Pre-assessment -> K4 Participatory -> T3 Path A / T4 Path B -> K5 Post-assessment -> T5 Summary -> K6 Summary",
                        zhBody: "K1 Bridge-in -> T1 Bridge-in -> K2 Objective -> K3 Pre-assessment -> T2 Pre-assessment -> K4 Participatory -> T3 路径A / T4 路径B -> K5 Post-assessment -> T5 Summary -> K6 Summary"
                    ),
                    detailSection(
                        id: "fit_case",
                        enTitle: "When To Use",
                        zhTitle: "适用场景",
                        enBody: "Use for 20-45 minute classes requiring clear rhythm and participation checkpoints.",
                        zhBody: "适用于 20-45 分钟的课时，强调节奏清晰与参与检查点。"
                    )
                ],
                exampleScenario: bopppsModelTemplateScenario()
            ),
            NodeDoc(
                type: "EduModelTemplateGagne9",
                name: Bilingual.text(en: "Gagne's Nine Events", zh: "Gagné 九事件教学模型"),
                categoryKey: "model",
                categoryTitle: categoryTitle,
                description: Bilingual.text(
                    en: "A highly structured nine-event model from attention to retention and transfer.",
                    zh: "高结构化九事件教育模型：从引起注意到保持与迁移。"
                ),
                inputs: modelTemplateInputs(),
                outputs: modelTemplateOutputs(),
                processDesc: Bilingual.text(
                    en: "Builds a long left-to-right instructional chain with explicit event checkpoints and toolkit supports.",
                    zh: "构建长链式左到右教学流程，事件节点与 Toolkit 支撑点一一对应。"
                ),
                detailSections: [
                    detailSection(
                        id: "ipo_overview",
                        enTitle: "IPO Overview",
                        zhTitle: "IPO 概览",
                        enBody: "Input: objective + prerequisite knowledge assumptions.\nProcess: nine events are sequenced with toolkit supports at key execution events.\nOutput: an explicit, auditable teaching flow suitable for structured instruction.",
                        zhBody: "Input：教学目标 + 先修知识假设。\nProcess：九事件按序推进，关键执行事件插入 Toolkit 支撑。\nOutput：得到结构明确、可追踪的课堂流程，适配结构化教学。",
                        initiallyExpanded: true
                    ),
                    detailSection(
                        id: "node_sequence",
                        enTitle: "Node Sequence (L->R / T->B)",
                        zhTitle: "节点序列（左到右 / 上到下）",
                        enBody: "K1 Attention -> T1 Hook -> K2 Objectives -> K3 Recall -> K4 Present -> T2 Content Support -> K5 Guidance -> T3 Guided Discussion -> K6 Performance -> T4 Practice -> K7 Feedback -> T5 Peer Feedback -> K8 Assess -> K9 Transfer -> T6 Reflection",
                        zhBody: "K1 引起注意 -> T1 导入 -> K2 告知目标 -> K3 唤醒旧知 -> K4 呈现内容 -> T2 内容支撑 -> K5 提供指导 -> T3 引导讨论 -> K6 引出表现 -> T4 练习任务 -> K7 提供反馈 -> T5 同伴反馈 -> K8 检核表现 -> K9 促进迁移 -> T6 反思收束"
                    ),
                    detailSection(
                        id: "fit_case",
                        enTitle: "When To Use",
                        zhTitle: "适用场景",
                        enBody: "Suitable for larger classes and topics requiring explicit step-by-step instruction.",
                        zhBody: "适用于人数较多、步骤化讲授要求高的课堂。"
                    )
                ],
                exampleScenario: gagne9ModelTemplateScenario()
            )
        ]
    }

    private static func modelTemplateInputs() -> [PortDoc] {
        [
            guideInput(
                enName: "Course Context (Global)",
                zhName: "课程上下文（全局）",
                type: "Any",
                enDesc: "Subject, grade, duration, and constraints from course setup.",
                zhDesc: "来自课程设置的学科、学段、课时和约束信息。",
                isOptional: true
            ),
            guideInput(
                enName: "Teaching Goal (Global)",
                zhName: "教学目标（全局）",
                type: "Any",
                enDesc: "Core objective used to anchor the template sequence.",
                zhDesc: "用于锚定模板链路的核心教学目标。",
                isOptional: true
            )
        ]
    }

    private static func modelTemplateOutputs() -> [PortDoc] {
        [
            PortDoc(
                name: Bilingual.text(en: "Knowledge Chain", zh: "Knowledge 链路"),
                type: "Any",
                desc: Bilingual.text(en: "Ordered knowledge-stage sequence for instruction.", zh: "面向授课顺序的知识阶段链。")
            ),
            PortDoc(
                name: Bilingual.text(en: "Toolkit Chain", zh: "Toolkit 链路"),
                type: "Any",
                desc: Bilingual.text(en: "Method execution sequence attached to each stage.", zh: "与各阶段配套的方法执行链。")
            )
        ]
    }

    private static func ubdModelTemplateScenario() -> NodeDocExampleScenario {
        NodeDocExampleScenario(
            nodes: [
                NodeDocExampleNode(id: "k1", type: EduNodeType.knowledge, x: -1200, y: -220, customTitle: Bilingual.text(en: "K1 Desired Results", zh: "K1 预期结果"), textValue: Bilingual.text(en: "Clarify transfer goals and success criteria.", zh: "明确可迁移目标与达成标准。"), selectedOption: S("edu.knowledge.type.analyze")),
                NodeDocExampleNode(id: "k2", type: EduNodeType.knowledge, x: -760, y: -220, customTitle: Bilingual.text(en: "K2 Acceptable Evidence", zh: "K2 可接受证据"), textValue: Bilingual.text(en: "Define evidence and performance tasks.", zh: "定义证据与表现任务。"), selectedOption: S("edu.knowledge.type.evaluate")),
                NodeDocExampleNode(id: "k3", type: EduNodeType.knowledge, x: -320, y: -220, customTitle: Bilingual.text(en: "K3 Learning Plan", zh: "K3 学习体验规划"), textValue: Bilingual.text(en: "Back-design lesson activities from evidence.", zh: "从证据倒推课堂活动。"), selectedOption: S("edu.knowledge.type.apply")),
                NodeDocExampleNode(id: "t1", type: EduNodeType.toolkitPerceptionInquiry, x: 120, y: 220, customTitle: Bilingual.text(en: "T1 Hook & Diagnose", zh: "T1 导入与诊断"), selectedMethodID: "context_hook"),
                NodeDocExampleNode(id: "t2", type: EduNodeType.toolkitConstructionPrototype, x: 560, y: 220, customTitle: Bilingual.text(en: "T2 Build Through Task", zh: "T2 任务建构"), selectedMethodID: "low_fidelity_prototype"),
                NodeDocExampleNode(id: "t3", type: EduNodeType.toolkitCommunicationNegotiation, x: 1000, y: 220, customTitle: Bilingual.text(en: "T3 Discussion & Expression", zh: "T3 讨论表达"), selectedMethodID: "structured_debate"),
                NodeDocExampleNode(id: "t4", type: EduNodeType.toolkitRegulationMetacognition, x: 1440, y: 220, customTitle: Bilingual.text(en: "T4 Reflect & Close", zh: "T4 收束反思"), selectedMethodID: "reflection_protocol")
            ],
            connections: [
                NodeDocExampleConnection(sourceNodeID: "k1", targetNodeID: "k2"),
                NodeDocExampleConnection(sourceNodeID: "k2", targetNodeID: "k3"),
                NodeDocExampleConnection(sourceNodeID: "k3", targetNodeID: "t1"),
                NodeDocExampleConnection(sourceNodeID: "t1", targetNodeID: "t2"),
                NodeDocExampleConnection(sourceNodeID: "t2", targetNodeID: "t3"),
                NodeDocExampleConnection(sourceNodeID: "t3", targetNodeID: "t4"),
                NodeDocExampleConnection(sourceNodeID: "k2", targetNodeID: "t2"),
                NodeDocExampleConnection(sourceNodeID: "k2", targetNodeID: "t3"),
                NodeDocExampleConnection(sourceNodeID: "k2", targetNodeID: "t4")
            ]
        )
    }

    private static func fiveEModelTemplateScenario() -> NodeDocExampleScenario {
        NodeDocExampleScenario(
            nodes: [
                NodeDocExampleNode(id: "k1", type: EduNodeType.knowledge, x: -1080, y: -220, customTitle: "K1 Engage", textValue: Bilingual.text(en: "Raise a driving question.", zh: "提出驱动问题。"), selectedOption: S("edu.knowledge.type.remember")),
                NodeDocExampleNode(id: "t1", type: EduNodeType.toolkitPerceptionInquiry, x: -1080, y: 220, customTitle: Bilingual.text(en: "T1 Engage Toolkit", zh: "T1 Engage 工具"), selectedMethodID: "context_hook"),
                NodeDocExampleNode(id: "k2", type: EduNodeType.knowledge, x: -620, y: -220, customTitle: "K2 Explore", textValue: Bilingual.text(en: "Collect evidence through exploration.", zh: "通过探究采集证据。"), selectedOption: S("edu.knowledge.type.analyze")),
                NodeDocExampleNode(id: "t2", type: EduNodeType.toolkitPerceptionInquiry, x: -620, y: 220, customTitle: Bilingual.text(en: "T2 Explore Toolkit", zh: "T2 Explore 工具"), selectedMethodID: "field_observation"),
                NodeDocExampleNode(id: "k3", type: EduNodeType.knowledge, x: -160, y: -220, customTitle: "K3 Explain", textValue: Bilingual.text(en: "Build concept explanations from evidence.", zh: "基于证据形成概念解释。"), selectedOption: S("edu.knowledge.type.understand")),
                NodeDocExampleNode(id: "t3", type: EduNodeType.toolkitCommunicationNegotiation, x: -160, y: 220, customTitle: Bilingual.text(en: "T3 Explain Toolkit", zh: "T3 Explain 工具"), selectedMethodID: "structured_debate"),
                NodeDocExampleNode(id: "k4", type: EduNodeType.knowledge, x: 300, y: -220, customTitle: "K4 Elaborate", textValue: Bilingual.text(en: "Transfer to a new context.", zh: "迁移到新情境。"), selectedOption: S("edu.knowledge.type.apply")),
                NodeDocExampleNode(id: "t4", type: EduNodeType.toolkitConstructionPrototype, x: 300, y: 220, customTitle: Bilingual.text(en: "T4 Elaborate Toolkit", zh: "T4 Elaborate 工具"), selectedMethodID: "story_construction"),
                NodeDocExampleNode(id: "k5", type: EduNodeType.knowledge, x: 760, y: -220, customTitle: "K5 Evaluate", textValue: Bilingual.text(en: "Check achievement and next step.", zh: "检核达成并规划下一步。"), selectedOption: S("edu.knowledge.type.evaluate")),
                NodeDocExampleNode(id: "t5", type: EduNodeType.toolkitRegulationMetacognition, x: 760, y: 220, customTitle: Bilingual.text(en: "T5 Evaluate Toolkit", zh: "T5 Evaluate 工具"), selectedMethodID: "reflection_protocol")
            ],
            connections: [
                NodeDocExampleConnection(sourceNodeID: "k1", targetNodeID: "t1"),
                NodeDocExampleConnection(sourceNodeID: "t1", targetNodeID: "k2"),
                NodeDocExampleConnection(sourceNodeID: "k2", targetNodeID: "t2"),
                NodeDocExampleConnection(sourceNodeID: "t2", targetNodeID: "k3"),
                NodeDocExampleConnection(sourceNodeID: "k3", targetNodeID: "t3"),
                NodeDocExampleConnection(sourceNodeID: "t3", targetNodeID: "k4"),
                NodeDocExampleConnection(sourceNodeID: "k4", targetNodeID: "t4"),
                NodeDocExampleConnection(sourceNodeID: "t4", targetNodeID: "k5"),
                NodeDocExampleConnection(sourceNodeID: "k5", targetNodeID: "t5")
            ]
        )
    }

    private static func kolbModelTemplateScenario() -> NodeDocExampleScenario {
        NodeDocExampleScenario(
            nodes: [
                NodeDocExampleNode(id: "k1", type: EduNodeType.knowledge, x: -1080, y: -220, customTitle: Bilingual.text(en: "K1 Concrete Experience", zh: "K1 具体体验"), textValue: Bilingual.text(en: "Start with concrete experience.", zh: "从具体体验切入。"), selectedOption: S("edu.knowledge.type.remember")),
                NodeDocExampleNode(id: "t1", type: EduNodeType.toolkitPerceptionInquiry, x: -1080, y: 220, customTitle: Bilingual.text(en: "T1 Experience Capture", zh: "T1 体验采集"), selectedMethodID: "field_observation"),
                NodeDocExampleNode(id: "k2", type: EduNodeType.knowledge, x: -620, y: -220, customTitle: Bilingual.text(en: "K2 Reflective Observation", zh: "K2 反思观察"), textValue: Bilingual.text(en: "Capture patterns and confusion points.", zh: "记录规律与疑难点。"), selectedOption: S("edu.knowledge.type.analyze")),
                NodeDocExampleNode(id: "t2", type: EduNodeType.toolkitRegulationMetacognition, x: -620, y: 220, customTitle: Bilingual.text(en: "T2 Reflection Toolkit", zh: "T2 反思工具"), selectedMethodID: "metacognitive_routine"),
                NodeDocExampleNode(id: "k3", type: EduNodeType.knowledge, x: -160, y: -220, customTitle: Bilingual.text(en: "K3 Abstract Conceptualization", zh: "K3 抽象概念化"), textValue: Bilingual.text(en: "Generalize rules and concept model.", zh: "抽象出规则与概念模型。"), selectedOption: S("edu.knowledge.type.understand")),
                NodeDocExampleNode(id: "t3", type: EduNodeType.toolkitConstructionPrototype, x: -160, y: 220, customTitle: Bilingual.text(en: "T3 Concept Build", zh: "T3 建构工具"), selectedMethodID: "story_construction"),
                NodeDocExampleNode(id: "k4", type: EduNodeType.knowledge, x: 300, y: -220, customTitle: Bilingual.text(en: "K4 Active Experimentation", zh: "K4 主动实验"), textValue: Bilingual.text(en: "Apply concept in a new task.", zh: "在新任务中验证概念。"), selectedOption: S("edu.knowledge.type.apply")),
                NodeDocExampleNode(id: "t4", type: EduNodeType.toolkitCommunicationNegotiation, x: 300, y: 220, customTitle: Bilingual.text(en: "T4 Experiment & Share", zh: "T4 实验沟通"), selectedMethodID: "pogil")
            ],
            connections: [
                NodeDocExampleConnection(sourceNodeID: "k1", targetNodeID: "t1"),
                NodeDocExampleConnection(sourceNodeID: "t1", targetNodeID: "k2"),
                NodeDocExampleConnection(sourceNodeID: "k2", targetNodeID: "t2"),
                NodeDocExampleConnection(sourceNodeID: "t2", targetNodeID: "k3"),
                NodeDocExampleConnection(sourceNodeID: "k3", targetNodeID: "t3"),
                NodeDocExampleConnection(sourceNodeID: "t3", targetNodeID: "k4"),
                NodeDocExampleConnection(sourceNodeID: "k4", targetNodeID: "t4")
            ]
        )
    }

    private static func bopppsModelTemplateScenario() -> NodeDocExampleScenario {
        NodeDocExampleScenario(
            nodes: [
                NodeDocExampleNode(id: "k1", type: EduNodeType.knowledge, x: -1260, y: -220, customTitle: "K1 Bridge-in", textValue: Bilingual.text(en: "Open with a concise bridge-in.", zh: "用简短导入聚焦课堂。"), selectedOption: S("edu.knowledge.type.remember")),
                NodeDocExampleNode(id: "t1", type: EduNodeType.toolkitPerceptionInquiry, x: -1260, y: 220, customTitle: Bilingual.text(en: "T1 Bridge-in Toolkit", zh: "T1 Bridge-in 工具"), selectedMethodID: "context_hook"),
                NodeDocExampleNode(id: "k2", type: EduNodeType.knowledge, x: -820, y: -220, customTitle: "K2 Objective", textValue: Bilingual.text(en: "State lesson objective.", zh: "明确本课目标。"), selectedOption: S("edu.knowledge.type.understand")),
                NodeDocExampleNode(id: "k3", type: EduNodeType.knowledge, x: -380, y: -220, customTitle: "K3 Pre-assessment", textValue: Bilingual.text(en: "Identify baseline understanding.", zh: "识别学生起点。"), selectedOption: S("edu.knowledge.type.analyze")),
                NodeDocExampleNode(id: "t2", type: EduNodeType.toolkitRegulationMetacognition, x: -380, y: 220, customTitle: Bilingual.text(en: "T2 Pre-assessment Toolkit", zh: "T2 Pre-assessment 工具"), selectedMethodID: "rubric_checklist"),
                NodeDocExampleNode(id: "k4", type: EduNodeType.knowledge, x: 60, y: 0, customTitle: "K4 Participatory", textValue: Bilingual.text(en: "Run participatory learning.", zh: "进入参与式学习主活动。"), selectedOption: S("edu.knowledge.type.apply")),
                NodeDocExampleNode(id: "t3", type: EduNodeType.toolkitCommunicationNegotiation, x: 500, y: -220, customTitle: Bilingual.text(en: "T3 Path A", zh: "T3 路径A"), selectedMethodID: "world_cafe"),
                NodeDocExampleNode(id: "t4", type: EduNodeType.toolkitConstructionPrototype, x: 500, y: 220, customTitle: Bilingual.text(en: "T4 Path B", zh: "T4 路径B"), selectedMethodID: "low_fidelity_prototype"),
                NodeDocExampleNode(id: "k5", type: EduNodeType.knowledge, x: 940, y: 0, customTitle: "K5 Post-assessment", textValue: Bilingual.text(en: "Check learning outcomes.", zh: "检核学习达成。"), selectedOption: S("edu.knowledge.type.evaluate")),
                NodeDocExampleNode(id: "k6", type: EduNodeType.knowledge, x: 1380, y: -220, customTitle: "K6 Summary", textValue: Bilingual.text(en: "Capture key takeaways.", zh: "沉淀关键结论。"), selectedOption: S("edu.knowledge.type.create")),
                NodeDocExampleNode(id: "t5", type: EduNodeType.toolkitRegulationMetacognition, x: 1380, y: 220, customTitle: Bilingual.text(en: "T5 Summary Toolkit", zh: "T5 Summary 工具"), selectedMethodID: "reflection_protocol")
            ],
            connections: [
                NodeDocExampleConnection(sourceNodeID: "k1", targetNodeID: "t1"),
                NodeDocExampleConnection(sourceNodeID: "t1", targetNodeID: "k2"),
                NodeDocExampleConnection(sourceNodeID: "k2", targetNodeID: "k3"),
                NodeDocExampleConnection(sourceNodeID: "k3", targetNodeID: "t2"),
                NodeDocExampleConnection(sourceNodeID: "t2", targetNodeID: "k4"),
                NodeDocExampleConnection(sourceNodeID: "k4", targetNodeID: "t3"),
                NodeDocExampleConnection(sourceNodeID: "k4", targetNodeID: "t4"),
                NodeDocExampleConnection(sourceNodeID: "t3", targetNodeID: "k5"),
                NodeDocExampleConnection(sourceNodeID: "t4", targetNodeID: "k5"),
                NodeDocExampleConnection(sourceNodeID: "k5", targetNodeID: "t5"),
                NodeDocExampleConnection(sourceNodeID: "t5", targetNodeID: "k6")
            ]
        )
    }

    private static func gagne9ModelTemplateScenario() -> NodeDocExampleScenario {
        NodeDocExampleScenario(
            nodes: [
                NodeDocExampleNode(id: "k1", type: EduNodeType.knowledge, x: -1640, y: -220, customTitle: Bilingual.text(en: "K1 Gain Attention", zh: "K1 引起注意"), textValue: Bilingual.text(en: "Use a concise attention stimulus.", zh: "使用简短刺激引起注意。"), selectedOption: S("edu.knowledge.type.remember")),
                NodeDocExampleNode(id: "t1", type: EduNodeType.toolkitPerceptionInquiry, x: -1640, y: 220, customTitle: Bilingual.text(en: "T1 Hook", zh: "T1 导入工具"), selectedMethodID: "context_hook"),
                NodeDocExampleNode(id: "k2", type: EduNodeType.knowledge, x: -1240, y: -220, customTitle: Bilingual.text(en: "K2 Inform Objectives", zh: "K2 告知目标"), textValue: Bilingual.text(en: "Clarify objective and success criteria.", zh: "明确目标与达成标准。"), selectedOption: S("edu.knowledge.type.understand")),
                NodeDocExampleNode(id: "k3", type: EduNodeType.knowledge, x: -840, y: -220, customTitle: Bilingual.text(en: "K3 Stimulate Recall", zh: "K3 唤醒旧知"), textValue: Bilingual.text(en: "Recall prerequisite knowledge.", zh: "唤醒先修知识。"), selectedOption: S("edu.knowledge.type.understand")),
                NodeDocExampleNode(id: "k4", type: EduNodeType.knowledge, x: -440, y: -220, customTitle: Bilingual.text(en: "K4 Present Content", zh: "K4 呈现内容"), textValue: Bilingual.text(en: "Present key concept and examples.", zh: "呈现关键概念与案例。"), selectedOption: S("edu.knowledge.type.analyze")),
                NodeDocExampleNode(id: "t2", type: EduNodeType.toolkitPerceptionInquiry, x: -440, y: 220, customTitle: Bilingual.text(en: "T2 Content Support", zh: "T2 内容支撑"), selectedMethodID: "source_analysis"),
                NodeDocExampleNode(id: "k5", type: EduNodeType.knowledge, x: -40, y: -220, customTitle: Bilingual.text(en: "K5 Provide Guidance", zh: "K5 提供指导"), textValue: Bilingual.text(en: "Provide scaffolds and strategy hints.", zh: "提供策略支架与提示。"), selectedOption: S("edu.knowledge.type.apply")),
                NodeDocExampleNode(id: "t3", type: EduNodeType.toolkitCommunicationNegotiation, x: -40, y: 220, customTitle: Bilingual.text(en: "T3 Guided Discussion", zh: "T3 引导讨论"), selectedMethodID: "structured_debate"),
                NodeDocExampleNode(id: "k6", type: EduNodeType.knowledge, x: 360, y: -220, customTitle: Bilingual.text(en: "K6 Elicit Performance", zh: "K6 引出表现"), textValue: Bilingual.text(en: "Run practice and capture output.", zh: "组织练习并收集表现。"), selectedOption: S("edu.knowledge.type.apply")),
                NodeDocExampleNode(id: "t4", type: EduNodeType.toolkitConstructionPrototype, x: 360, y: 220, customTitle: Bilingual.text(en: "T4 Practice Toolkit", zh: "T4 练习工具"), selectedMethodID: "low_fidelity_prototype"),
                NodeDocExampleNode(id: "k7", type: EduNodeType.knowledge, x: 760, y: -220, customTitle: Bilingual.text(en: "K7 Provide Feedback", zh: "K7 提供反馈"), textValue: Bilingual.text(en: "Give actionable feedback.", zh: "给出可执行反馈。"), selectedOption: S("edu.knowledge.type.evaluate")),
                NodeDocExampleNode(id: "t5", type: EduNodeType.toolkitCommunicationNegotiation, x: 760, y: 220, customTitle: Bilingual.text(en: "T5 Peer Feedback", zh: "T5 同伴反馈"), selectedMethodID: "world_cafe"),
                NodeDocExampleNode(id: "k8", type: EduNodeType.knowledge, x: 1160, y: -220, customTitle: Bilingual.text(en: "K8 Assess Performance", zh: "K8 检核表现"), textValue: Bilingual.text(en: "Assess mastery and completion.", zh: "检核掌握与完成度。"), selectedOption: S("edu.knowledge.type.evaluate")),
                NodeDocExampleNode(id: "k9", type: EduNodeType.knowledge, x: 1560, y: -220, customTitle: Bilingual.text(en: "K9 Retention & Transfer", zh: "K9 保持与迁移"), textValue: Bilingual.text(en: "Consolidate and transfer to new task.", zh: "巩固并迁移到新任务。"), selectedOption: S("edu.knowledge.type.create")),
                NodeDocExampleNode(id: "t6", type: EduNodeType.toolkitRegulationMetacognition, x: 1560, y: 220, customTitle: Bilingual.text(en: "T6 Reflection Closure", zh: "T6 反思收束"), selectedMethodID: "reflection_protocol")
            ],
            connections: [
                NodeDocExampleConnection(sourceNodeID: "k1", targetNodeID: "t1"),
                NodeDocExampleConnection(sourceNodeID: "t1", targetNodeID: "k2"),
                NodeDocExampleConnection(sourceNodeID: "k2", targetNodeID: "k3"),
                NodeDocExampleConnection(sourceNodeID: "k3", targetNodeID: "k4"),
                NodeDocExampleConnection(sourceNodeID: "k4", targetNodeID: "t2"),
                NodeDocExampleConnection(sourceNodeID: "t2", targetNodeID: "k5"),
                NodeDocExampleConnection(sourceNodeID: "k5", targetNodeID: "t3"),
                NodeDocExampleConnection(sourceNodeID: "t3", targetNodeID: "k6"),
                NodeDocExampleConnection(sourceNodeID: "k6", targetNodeID: "t4"),
                NodeDocExampleConnection(sourceNodeID: "t4", targetNodeID: "k7"),
                NodeDocExampleConnection(sourceNodeID: "k7", targetNodeID: "t5"),
                NodeDocExampleConnection(sourceNodeID: "t5", targetNodeID: "k8"),
                NodeDocExampleConnection(sourceNodeID: "k8", targetNodeID: "k9"),
                NodeDocExampleConnection(sourceNodeID: "k9", targetNodeID: "t6")
            ]
        )
    }

    private static func detailSection(
        id: String,
        enTitle: String,
        zhTitle: String,
        enBody: String,
        zhBody: String,
        initiallyExpanded: Bool = false,
        methodGuide: NodeDocMethodGuide? = nil,
        exampleScenario: NodeDocExampleScenario? = nil
    ) -> NodeDocDetailSection {
        NodeDocDetailSection(
            id: id,
            title: Bilingual.text(en: enTitle, zh: zhTitle),
            body: Bilingual.text(en: enBody, zh: zhBody),
            initiallyExpanded: initiallyExpanded,
            methodGuide: methodGuide,
            exampleScenario: exampleScenario
        )
    }

    private static func tutorialPhysicsMicroLessonScenario() -> NodeDocExampleScenario {
        NodeDocExampleScenario(
            nodes: [
                NodeDocExampleNode(
                    id: "k1",
                    type: EduNodeType.knowledge,
                    x: -700,
                    y: -180,
                    customTitle: Bilingual.text(en: "K1: Uniform Motion", zh: "K1：匀速直线运动"),
                    textValue: Bilingual.text(en: "Identify variables of speed, distance, and time.", zh: "识别速度、路程、时间三变量。"),
                    selectedOption: S("edu.knowledge.type.understand")
                ),
                NodeDocExampleNode(
                    id: "tk_probe",
                    type: EduNodeType.toolkitPerceptionInquiry,
                    x: -250,
                    y: -180,
                    customTitle: Bilingual.text(en: "Toolkit: Sensor Probe", zh: "Toolkit：传感测量"),
                    selectedMethodID: "sensor_probe"
                ),
                NodeDocExampleNode(
                    id: "tk_phy",
                    type: EduNodeType.toolkitConstructionPrototype,
                    x: 220,
                    y: -180,
                    customTitle: Bilingual.text(en: "Toolkit: Physical Computing", zh: "Toolkit：物理计算"),
                    selectedMethodID: "physical_computing"
                ),
                NodeDocExampleNode(
                    id: "k2",
                    type: EduNodeType.knowledge,
                    x: 670,
                    y: -180,
                    customTitle: Bilingual.text(en: "K2: Force-Acceleration", zh: "K2：力与加速度"),
                    textValue: Bilingual.text(en: "Use measured data to explain force-acceleration trend.", zh: "用测量数据说明力与加速度变化趋势。"),
                    selectedOption: S("edu.knowledge.type.apply")
                ),
                NodeDocExampleNode(
                    id: "evaluation",
                    type: EduNodeType.evaluation,
                    x: 260,
                    y: 240,
                    customTitle: Bilingual.text(en: "Evaluation Score", zh: "评价节点"),
                    formTextFields: [
                        "evaluation_indicators": Bilingual.text(
                            en: "Knowledge Understanding | score | 0.4\nExperiment Completion | completion | 0.3\nTeam Explanation | score | 0.3",
                            zh: "知识理解 | score | 0.4\n实验完成 | completion | 0.3\n小组讲解 | score | 0.3"
                        )
                    ],
                    formOptionFields: [
                        "evaluation_formula": "weighted_avg",
                        "evaluation_grouping": "group",
                        "evaluation_output_scale": "score100"
                    ]
                )
            ],
            connections: [
                NodeDocExampleConnection(sourceNodeID: "k1", sourcePortIndex: 0, targetNodeID: "tk_probe", targetPortIndex: 0),
                NodeDocExampleConnection(sourceNodeID: "tk_probe", sourcePortIndex: 0, targetNodeID: "tk_phy", targetPortIndex: 0),
                NodeDocExampleConnection(sourceNodeID: "tk_phy", sourcePortIndex: 0, targetNodeID: "k2", targetPortIndex: 0),
                NodeDocExampleConnection(sourceNodeID: "k1", sourcePortIndex: 0, targetNodeID: "evaluation", targetPortIndex: 0),
                NodeDocExampleConnection(sourceNodeID: "tk_phy", sourcePortIndex: 0, targetNodeID: "evaluation", targetPortIndex: 1),
                NodeDocExampleConnection(sourceNodeID: "k2", sourcePortIndex: 0, targetNodeID: "evaluation", targetPortIndex: 2)
            ]
        )
    }

    private static func knowledgeDetailSections() -> [NodeDocDetailSection] {
        [
            detailSection(
                id: "remember",
                enTitle: "1 Remember",
                zhTitle: "1 记忆",
                enBody: "Use for factual recall and recognition.\nTypical task: list, name, identify.\nRecommended evidence: quick quiz, card recall, oral check.",
                zhBody: "用于事实回忆与识别。\n典型任务：列举、命名、识别。\n建议证据：快问快答、小测、口头抽查。",
                initiallyExpanded: true
            ),
            detailSection(
                id: "understand",
                enTitle: "2 Understand",
                zhTitle: "2 理解",
                enBody: "Use for explaining meaning and relationships.\nTypical task: explain, classify, summarize.\nRecommended evidence: concept map, paraphrase, pair explanation.",
                zhBody: "用于解释概念含义与关系。\n典型任务：解释、分类、概括。\n建议证据：概念图、同义转述、同伴讲解。"
            ),
            detailSection(
                id: "apply",
                enTitle: "3 Apply",
                zhTitle: "3 应用",
                enBody: "Use when students apply knowledge to a concrete task.\nTypical task: solve, execute, demonstrate.\nRecommended evidence: task completion record, worked example.",
                zhBody: "用于将知识迁移到具体任务。\n典型任务：解题、执行、演示。\n建议证据：任务完成记录、操作示例。"
            ),
            detailSection(
                id: "analyze",
                enTitle: "4 Analyze",
                zhTitle: "4 分析",
                enBody: "Use for breaking down structure and finding patterns.\nTypical task: compare, infer, diagnose.\nRecommended evidence: contrast table, causal chain, reasoning notes.",
                zhBody: "用于拆解结构、发现规律。\n典型任务：比较、推断、诊断。\n建议证据：对照表、因果链、推理记录。"
            ),
            detailSection(
                id: "evaluate",
                enTitle: "5 Evaluate",
                zhTitle: "5 评价",
                enBody: "Use for judgement against criteria.\nTypical task: critique, justify, rate.\nRecommended evidence: rubric score, argument quality check.",
                zhBody: "用于依据标准进行判断。\n典型任务：评议、论证、评级。\n建议证据：量规评分、论证质量核查。"
            ),
            detailSection(
                id: "create",
                enTitle: "6 Create",
                zhTitle: "6 创造",
                enBody: "Use for producing original solution or artifact.\nTypical task: design, compose, prototype.\nRecommended evidence: design brief, artifact demo, reflection log.",
                zhBody: "用于产出原创方案或作品。\n典型任务：设计、创作、原型化。\n建议证据：设计说明、作品演示、反思日志。"
            )
        ]
    }

    private static func toolkitMethodSections(category: EduToolkitCategory, toolkitType: String) -> [NodeDocDetailSection] {
        let sections: [NodeDocDetailSection]
        switch category {
        case .perceptionInquiry:
            sections = [
                detailSection(
                    id: "context_hook",
                    enTitle: "Context Hook",
                    zhTitle: "情境导入",
                    enBody: "Goal: activate prior knowledge quickly.\nFill: Trigger Material + Guiding Questions + Response Pattern (+ optional Time Budget).\nWhen to use: first 2-8 minutes of a new topic.",
                    zhBody: "目标：快速激活先验知识。\n填写：触发材料 + 引导问题组 + 回应方式（可选时间配额）。\n适用：新主题开场 2-8 分钟。"
                ),
                detailSection(
                    id: "field_observation",
                    enTitle: "Field Observation",
                    zhTitle: "田野观察",
                    enBody: "Goal: collect evidence from authentic contexts.\nFill: Task Structure + Observation Site + Focus + Sampling Rule + Evidence Capture.\nDynamic fields change by Task Structure (classification / behavior event / process tracking / comparative / open).\nWhen to use: topics requiring real-world observation evidence.",
                    zhBody: "目标：在真实场景采集证据。\n填写：任务结构 + 观察场域 + 观察焦点 + 采样规则 + 证据采集。\n会根据任务结构动态显示字段（分类识别/行为事件/过程追踪/对比观察/开放观察）。\n适用：需要真实观察证据的主题。"
                ),
                detailSection(
                    id: "source_analysis",
                    enTitle: "Source Analysis",
                    zhTitle: "资料溯源",
                    enBody: "Goal: train evidence extraction and verification.\nFill: Source Set + Extraction Rule + Claim-Evidence Matrix + Verification Method (+ optional Credibility Clues).\nWhen to use: topics with document/image/text evidence.",
                    zhBody: "目标：训练证据提取与验证。\n填写：资料集合 + 提取规则 + 主张-证据矩阵 + 验证方法（可选可信度线索）。\n适用：依赖文本/图像/文献证据的主题。"
                ),
                detailSection(
                    id: "sensor_probe",
                    enTitle: "Sensor Probe",
                    zhTitle: "传感测量",
                    enBody: "Goal: obtain measurable data for inquiry.\nFill: Variable Dictionary + Instrument Setup + Sampling Plan + Data Cleaning Rule (+ optional Anomaly Threshold).\nWhen to use: science/engineering topics needing quantitative evidence.",
                    zhBody: "目标：采集可量化数据支撑探究。\n填写：变量字典 + 仪器配置 + 采样计划 + 数据清洗规则（可选异常阈值）。\n适用：理工类、需要定量证据的主题。"
                ),
                detailSection(
                    id: "immersive_simulation",
                    enTitle: "Immersive Simulation",
                    zhTitle: "沉浸式模拟",
                    enBody: "Goal: simulate hard-to-observe situations.\nFill: Simulation Scene + Event Triggers + Debrief Questions + Role Mode (+ optional Safety Boundary).\nWhen to use: risky, costly, or impossible-to-live-observe scenarios.",
                    zhBody: "目标：模拟难以直接观察的情境。\n填写：模拟情境 + 事件触发点 + 复盘问题组 + 角色模式（可选安全边界）。\n适用：高风险、高成本或难现场观察场景。"
                )
            ]
        case .constructionPrototype:
            sections = [
                detailSection(
                    id: "low_fidelity_prototype",
                    enTitle: "Low-Fidelity Prototype",
                    zhTitle: "低保真原型",
                    enBody: "Goal: externalize ideas quickly before polishing.\nFill: Problem Definition + Prototype Goal + Material Constraints + Test Task (+ optional Rubric).\nWhen to use: early-stage idea validation.",
                    zhBody: "目标：在早期快速外化想法。\n填写：问题定义 + 原型目标 + 材料约束 + 测试任务（可选评价量规）。\n适用：概念验证与早期迭代。"
                ),
                detailSection(
                    id: "physical_computing",
                    enTitle: "Physical Computing",
                    zhTitle: "物理计算",
                    enBody: "Goal: build interactive artifacts with hardware modules.\nFill: Function Goal + Module Combination + Logic Flow + Debug Rule (+ optional Safety Check).\nWhen to use: hands-on STEM learning.",
                    zhBody: "目标：用硬件模块构建可交互作品。\n填写：功能目标 + 模块组合 + 逻辑流程 + 调试规则（可选安全检查）。\n适用：动手型 STEM 学习。"
                ),
                detailSection(
                    id: "story_construction",
                    enTitle: "Story Construction",
                    zhTitle: "叙事建构",
                    enBody: "Goal: organize concepts into narrative logic.\nFill: Story Mainline (line-by-line) + Key Terms (one per line) + Narrative Structure.\nDynamic fields change by selected structure: Problem-Solution / Journey / Compare-Contrast.\nWhen to use: language, humanities, and explanation-heavy topics.",
                    zhBody: "目标：用叙事方式组织概念逻辑。\n填写：叙事主线（逐行）+ 关键术语（每行一个）+ 叙事结构。\n会根据结构选项动态变化字段：问题-解决 / 旅程式 / 对比式。\n适用：语文、人文和解释型主题。"
                ),
                detailSection(
                    id: "service_blueprint",
                    enTitle: "Service Blueprint",
                    zhTitle: "服务蓝图",
                    enBody: "Goal: map learner journey and improve touchpoints.\nFill: Object Dictionary + Goal Orientation + Environment + Journey Stages + Touchpoint Issues.\nDynamic fields change by Goal Orientation (efficiency / engagement / equity / retention).\nWhen to use: course flow redesign and experience optimization.",
                    zhBody: "目标：梳理学习旅程并优化教学触点。\n填写：对象字典 + 目标导向 + 环境 + 旅程阶段 + 触点问题。\n会根据目标导向动态变化字段（效率 / 参与度 / 公平性 / 保持度）。\n适用：教学流程重构与体验优化。"
                ),
                detailSection(
                    id: "adaptive_learning_platform",
                    enTitle: "Adaptive Learning Platform",
                    zhTitle: "适应性学习平台",
                    enBody: "Goal: design differentiated learning paths.\nFill: Adaptation Target + Routing Rule + Feedback Trigger + Return Strategy (+ optional Tool/Teacher Intervention).\nWhen to use: classes requiring differentiated pacing/support.",
                    zhBody: "目标：设计分层分流学习路径。\n填写：适配目标 + 分流规则 + 反馈触发条件 + 回流策略（可选工具引用/教师干预节点）。\n适用：需要差异化节奏与支持的课堂。"
                )
            ]
        case .communicationNegotiation:
            sections = [
                detailSection(
                    id: "role_play",
                    enTitle: "Role Play",
                    zhTitle: "角色扮演",
                    enBody: "Goal: deepen perspective-taking and empathy.\nFill: Role Dictionary + Scene Design + Conflict Trigger + Facilitation Pattern + Rounds/Duration.\nDynamic fields change by Facilitation Pattern (Inner-Outer / Station / Fishbowl).\nWhen to use: controversial issues or perspective negotiation.",
                    zhBody: "目标：提升视角转换与同理理解。\n填写：角色字典 + 场景设计 + 冲突触发点 + 组织方式 + 轮次时长。\n会根据组织方式动态变化字段（内外圈 / 站点轮换 / 鱼缸式）。\n适用：争议议题或立场协商场景。"
                ),
                detailSection(
                    id: "structured_debate",
                    enTitle: "Structured Debate",
                    zhTitle: "结构化辩论",
                    enBody: "Goal: improve argument quality with explicit protocol.\nFill: Debate Motion + Evidence Threshold + Debate Protocol + Speaking Flow.\nDynamic fields change by protocol (CER / Oxford / Toulmin).\nWhen to use: claim-evidence-reasoning training.",
                    zhBody: "目标：通过协议化流程提升论证质量。\n填写：辩题陈述 + 证据门槛 + 辩论协议 + 发言流程。\n会根据辩论协议动态变化字段（CER / 牛津式 / 图尔敏）。\n适用：观点-证据-推理训练。"
                ),
                detailSection(
                    id: "world_cafe",
                    enTitle: "World Cafe",
                    zhTitle: "世界咖啡馆",
                    enBody: "Goal: co-construct ideas across rotating groups.\nFill: Core Question + Table Topics + Rotation Plan + Harvest Rule (+ optional Output Template).\nWhen to use: divergent discussion and synthesis.",
                    zhBody: "目标：通过轮转小组共建多视角结论。\n填写：核心问题 + 桌次主题 + 轮转计划 + 汇总规则（可选输出模板）。\n适用：发散讨论与共识整合。"
                ),
                detailSection(
                    id: "game_mechanism",
                    enTitle: "Game Mechanism",
                    zhTitle: "博弈游戏机制",
                    enBody: "Goal: sustain participation with challenge loops.\nFill: Goal Mapping + Core Rules + Reward Mechanism + Progression Style.\nDynamic fields change by progression style (Level / Mission / Badge).\nWhen to use: repetition-heavy content needing motivation.",
                    zhBody: "目标：通过挑战机制维持学习参与。\n填写：学习目标映射 + 核心规则 + 奖励机制 + 进阶方式。\n会根据进阶方式动态变化字段（关卡 / 任务线 / 徽章）。\n适用：需要高重复练习与高动机维持的内容。"
                ),
                detailSection(
                    id: "pogil",
                    enTitle: "POGIL Collaboration",
                    zhTitle: "POGIL 协作",
                    enBody: "Goal: guided inquiry with clear team roles.\nFill: Team Role Dictionary + Inquiry Ladder + Worksheet Focus + Checkpoint Control (+ optional Teacher Trigger).\nWhen to use: small-group inquiry with scaffolded process.",
                    zhBody: "目标：在清晰分工下开展引导式探究。\n填写：小组角色字典 + 探究问题阶梯 + 任务单焦点 + 检查点控制（可选教师介入触发）。\n适用：小组探究且需要脚手架流程。"
                )
            ]
        case .regulationMetacognition:
            sections = [
                detailSection(
                    id: "kanban_monitoring",
                    enTitle: "Kanban Monitoring",
                    zhTitle: "看板监控",
                    enBody: "Goal: visualize progress and blockers in real time.\nFill: Board Columns + WIP Limit + Blocker Categories + Refresh Frequency (+ optional Milestones).\nWhen to use: project-based learning with multiple parallel tasks.",
                    zhBody: "目标：实时可视化进度与阻塞点。\n填写：看板列配置 + WIP 限制 + 阻塞分类 + 刷新频率（可选里程碑节点）。\n适用：多任务并行的项目式学习。"
                ),
                detailSection(
                    id: "rubric_checklist",
                    enTitle: "Rubric & Checklist",
                    zhTitle: "量规与核查表",
                    enBody: "Goal: align process to explicit quality standards.\nFill: Dimension Dictionary + Weight Configuration + Level Descriptions + Number of Levels + Summary Strategy.\nDynamic fields change by Summary Strategy (Weighted Average / Threshold Gate / Grade Band).\nWhen to use: formative assessment and transparent scoring.",
                    zhBody: "目标：用明确标准约束学习过程质量。\n填写：评价维度字典 + 权重配置 + 等级描述 + 等级档数 + 汇总策略。\n会根据汇总策略动态变化字段（加权平均 / 门槛达标 / 分档判定）。\n适用：形成性评价和透明评分。"
                ),
                detailSection(
                    id: "reflection_protocol",
                    enTitle: "Reflection Protocol",
                    zhTitle: "反思协议",
                    enBody: "Goal: guide structured reflection and next-step planning.\nFill: Structure Template + Prompt Group + Trigger Timing + Reflection Channel.\nDynamic prompts change by template (What-So What-Now What / ORID / KSS).\nWhen to use: end-of-activity review and improvement planning.",
                    zhBody: "目标：引导结构化复盘与下一步计划。\n填写：反思结构模板 + 反思提示组 + 触发时机 + 反思渠道。\n会根据模板动态变化提示字段（What-So What-Now What / ORID / KSS）。\n适用：活动结束后的复盘改进阶段。"
                ),
                detailSection(
                    id: "learning_dashboard",
                    enTitle: "Learning Dashboard",
                    zhTitle: "学习仪表盘",
                    enBody: "Goal: monitor key indicators and trigger timely intervention.\nFill: Metric Dictionary + Source Mapping + Alert Threshold + Review Frequency (+ optional View Mode).\nWhen to use: classes needing ongoing data-informed adjustment.",
                    zhBody: "目标：跟踪核心指标并及时触发干预。\n填写：指标字典 + 数据来源映射 + 预警阈值 + 查看频率（可选视图模式）。\n适用：需要持续数据化调控的课堂。"
                ),
                detailSection(
                    id: "metacognitive_routine",
                    enTitle: "Metacognitive Routine",
                    zhTitle: "元认知例程",
                    enBody: "Goal: train students to plan-monitor-adjust strategies.\nFill: Routine Pattern + Plan Prompts + Monitor Signal Dictionary + Adjustment Strategy Library (+ optional Self-Assessment).\nWhen to use: self-regulated learning and strategy transfer.",
                    zhBody: "目标：训练学生“计划-监控-调整”策略。\n填写：例程模式 + 计划提示 + 监控信号字典 + 调整策略库（可选自评量表）。\n适用：自我调节学习与策略迁移。"
                )
            ]
        }
        return sections.map { enrichToolkitMethodSection($0, toolkitType: toolkitType) }
    }

    private static func enrichToolkitMethodSection(
        _ section: NodeDocDetailSection,
        toolkitType: String
    ) -> NodeDocDetailSection {
        NodeDocDetailSection(
            id: section.id,
            title: section.title,
            body: section.body,
            initiallyExpanded: section.initiallyExpanded,
            methodGuide: toolkitMethodGuide(for: section.id),
            exampleScenario: toolkitMethodExampleScenario(toolkitType: toolkitType, methodID: section.id)
        )
    }

    private static func guideInput(
        enName: String,
        zhName: String,
        type: String,
        enDesc: String,
        zhDesc: String,
        isOptional: Bool? = nil
    ) -> PortDoc {
        let resolvedOptional: Bool
        if let isOptional {
            resolvedOptional = isOptional
        } else {
            resolvedOptional = enName.lowercased().contains("optional")
                || zhName.contains("可选")
                || enDesc.lowercased().contains("optional")
                || zhDesc.contains("可选")
        }
        return PortDoc(
            name: Bilingual.text(en: enName, zh: zhName),
            type: type,
            desc: Bilingual.text(en: enDesc, zh: zhDesc),
            isOptional: resolvedOptional
        )
    }

    private static func toolkitMethodCommonOutputs() -> [PortDoc] {
        [
            PortDoc(
                name: S("edu.output.toolkit"),
                type: "String",
                desc: Bilingual.text(en: "Method activity description output.", zh: "方法活动描述输出。")
            ),
            PortDoc(
                name: S("edu.toolkit.output.type"),
                type: "String",
                desc: Bilingual.text(en: "Current selected method ID/title.", zh: "当前选择的方法。")
            )
        ]
    }

    private static func methodGuide(
        enDescription: String,
        zhDescription: String,
        inputs: [PortDoc],
        enProcess: String,
        zhProcess: String,
        enScenario: String,
        zhScenario: String
    ) -> NodeDocMethodGuide {
        NodeDocMethodGuide(
            description: Bilingual.text(en: enDescription, zh: zhDescription),
            inputs: inputs,
            outputs: toolkitMethodCommonOutputs(),
            processDesc: Bilingual.text(en: enProcess, zh: zhProcess),
            scenario: Bilingual.text(en: enScenario, zh: zhScenario)
        )
    }

    private static func toolkitMethodGuide(for methodID: String) -> NodeDocMethodGuide? {
        let commonKnowledge = guideInput(
            enName: "Knowledge",
            zhName: "Knowledge 知识输入",
            type: "Any",
            enDesc: "Linked knowledge context from previous node(s).",
            zhDesc: "来自前序节点的知识上下文。",
            isOptional: true
        )

        switch methodID {
        case "context_hook":
            return methodGuide(
                enDescription: "Short opening to activate prior knowledge and attention.",
                zhDescription: "用于课堂开场，激活先验知识和注意力。",
                inputs: [
                    commonKnowledge,
                    guideInput(enName: "Trigger Material", zhName: "触发材料", type: "String", enDesc: "Image/video/object used to start discussion.", zhDesc: "用于开启讨论的图片/视频/实物。"),
                    guideInput(enName: "Guiding Questions", zhName: "引导问题组", type: "String", enDesc: "2-3 opening questions.", zhDesc: "2-3 个开场问题。"),
                    guideInput(enName: "Response Pattern", zhName: "回应方式", type: "String", enDesc: "Quick poll / think-pair-share / choral response.", zhDesc: "快速投票/同伴交流/全班齐答。")
                ],
                enProcess: "Merge knowledge input with opening prompt settings and output a ready-to-run opener.",
                zhProcess: "将知识输入与开场设置合并，输出可执行导入环节。",
                enScenario: "Use when introducing a new topic in the first minutes of class.",
                zhScenario: "用于新主题导入的前几分钟。"
            )
        case "field_observation":
            return methodGuide(
                enDescription: "Design authentic observation tasks and capture evidence.",
                zhDescription: "设计真实场景观察任务并采集证据。",
                inputs: [
                    commonKnowledge,
                    guideInput(enName: "Task Structure", zhName: "任务结构", type: "String", enDesc: "Classification / behavior / process / comparative / open.", zhDesc: "分类/行为/过程/对比/开放观察。"),
                    guideInput(enName: "Observation Site", zhName: "观察场域", type: "String", enDesc: "Where observation happens.", zhDesc: "观察发生的场域。"),
                    guideInput(enName: "Sampling Rule", zhName: "采样规则", type: "String", enDesc: "Who/when/how often to observe.", zhDesc: "观察对象、时间与频率规则。"),
                    guideInput(enName: "Evidence Capture", zhName: "证据采集", type: "String", enDesc: "Photo/note/audio/video capture format.", zhDesc: "照片/表格/录音/视频等采集方式。")
                ],
                enProcess: "Generate an observation plan with structure-dependent fields.",
                zhProcess: "根据任务结构生成对应观察计划。",
                enScenario: "Outdoor science or community inquiry tasks.",
                zhScenario: "适用于户外科学探究或社区观察任务。"
            )
        case "source_analysis":
            return methodGuide(
                enDescription: "Guide learners to extract and verify evidence from sources.",
                zhDescription: "引导学生从资料中提取并验证证据。",
                inputs: [
                    commonKnowledge,
                    guideInput(enName: "Source Set", zhName: "资料集合", type: "String", enDesc: "Texts/images/videos for analysis.", zhDesc: "用于分析的资料集合。"),
                    guideInput(enName: "Extraction Rule", zhName: "提取规则", type: "String", enDesc: "How to identify useful evidence.", zhDesc: "如何识别有效证据。"),
                    guideInput(enName: "Claim-Evidence Matrix", zhName: "主张-证据矩阵", type: "String", enDesc: "Map claim to evidence.", zhDesc: "建立主张与证据对应关系。"),
                    guideInput(enName: "Verification Method", zhName: "验证方法", type: "String", enDesc: "Cross-source/timeline/check rules.", zhDesc: "跨来源/时间线/一致性验证。")
                ],
                enProcess: "Compose a source-analysis task with explicit verification path.",
                zhProcess: "输出具备验证路径的资料分析任务。",
                enScenario: "History, media literacy, and reading evidence tasks.",
                zhScenario: "适用于历史、人文和媒介素养课。"
            )
        case "sensor_probe":
            return methodGuide(
                enDescription: "Collect measurable data through sensors or instruments.",
                zhDescription: "通过传感器或测量工具采集量化数据。",
                inputs: [
                    commonKnowledge,
                    guideInput(enName: "Variable Dictionary", zhName: "变量字典", type: "String", enDesc: "Variable names, units, and meanings.", zhDesc: "变量名、单位和含义。"),
                    guideInput(enName: "Instrument Setup", zhName: "仪器配置", type: "String", enDesc: "Tools and setup notes.", zhDesc: "仪器工具与配置说明。"),
                    guideInput(enName: "Sampling Plan", zhName: "采样计划", type: "String", enDesc: "Sampling time/space/frequency.", zhDesc: "采样时间、空间与频率。")
                ],
                enProcess: "Output a measurable inquiry procedure with data-cleaning guidance.",
                zhProcess: "输出可量化的探究流程和数据清洗规范。",
                enScenario: "STEM labs and environmental measurement activities.",
                zhScenario: "适用于 STEM 实验和环境测量任务。"
            )
        case "immersive_simulation":
            return methodGuide(
                enDescription: "Create a simulation when direct observation is difficult.",
                zhDescription: "在难以真实观察时构建模拟情境。",
                inputs: [
                    commonKnowledge,
                    guideInput(enName: "Simulation Scene", zhName: "模拟情境", type: "String", enDesc: "Key simulated environment.", zhDesc: "核心模拟环境描述。"),
                    guideInput(enName: "Event Triggers", zhName: "事件触发点", type: "String", enDesc: "Trigger points that change decisions.", zhDesc: "影响决策变化的触发点。"),
                    guideInput(enName: "Debrief Questions", zhName: "复盘问题组", type: "String", enDesc: "Reflection prompts after simulation.", zhDesc: "模拟结束后的复盘问题。"),
                    guideInput(enName: "Role Mode", zhName: "角色模式", type: "String", enDesc: "Single/group/rotating roles.", zhDesc: "单角色/小组角色/轮转角色。")
                ],
                enProcess: "Build a simulation flow plus post-activity debrief structure.",
                zhProcess: "生成模拟流程并附带复盘结构。",
                enScenario: "Emergency, ecological, or social system simulations.",
                zhScenario: "适用于应急、生态、社会系统模拟。"
            )
        case "low_fidelity_prototype":
            return methodGuide(
                enDescription: "Rapidly externalize ideas before high-cost implementation.",
                zhDescription: "在高成本实现前快速外化想法。",
                inputs: [
                    commonKnowledge,
                    guideInput(enName: "Problem Definition", zhName: "问题定义", type: "String", enDesc: "Problem to solve.", zhDesc: "要解决的核心问题。"),
                    guideInput(enName: "Prototype Goal", zhName: "原型目标", type: "String", enDesc: "What to demonstrate.", zhDesc: "原型要验证/表达什么。"),
                    guideInput(enName: "Material Constraints", zhName: "材料约束", type: "String", enDesc: "Time and material limits.", zhDesc: "时间和材料限制。")
                ],
                enProcess: "Generate a low-cost prototype task with explicit test activity.",
                zhProcess: "输出低成本原型任务及测试环节。",
                enScenario: "Early concept validation in project-based learning.",
                zhScenario: "适用于项目式学习前期概念验证。"
            )
        case "physical_computing":
            return methodGuide(
                enDescription: "Design hands-on hardware + logic construction tasks.",
                zhDescription: "设计硬件与逻辑结合的动手建构任务。",
                inputs: [
                    commonKnowledge,
                    guideInput(enName: "Function Goal", zhName: "功能目标", type: "String", enDesc: "Expected artifact behavior.", zhDesc: "期望实现的功能行为。"),
                    guideInput(enName: "Module Combination", zhName: "模块组合", type: "String", enDesc: "Hardware modules and wiring.", zhDesc: "硬件模块与连接方案。"),
                    guideInput(enName: "Logic Flow", zhName: "逻辑流程", type: "String", enDesc: "Input-process-output logic.", zhDesc: "输入-处理-输出逻辑。")
                ],
                enProcess: "Create build + debug steps for physical-computing activities.",
                zhProcess: "生成物理计算搭建与调试流程。",
                enScenario: "Robotics and maker classroom activities.",
                zhScenario: "适用于机器人与创客课堂。"
            )
        case "story_construction":
            return methodGuide(
                enDescription: "Transform concepts into narrative structures for understanding.",
                zhDescription: "将知识概念组织为叙事结构促进理解。",
                inputs: [
                    commonKnowledge,
                    guideInput(enName: "Story Mainline", zhName: "叙事主线", type: "String", enDesc: "Line-by-line narrative progression.", zhDesc: "逐行的叙事推进主线。"),
                    guideInput(enName: "Key Terms", zhName: "关键术语", type: "String", enDesc: "One term per line.", zhDesc: "每行一个关键术语。"),
                    guideInput(enName: "Narrative Structure", zhName: "叙事结构", type: "String", enDesc: "Problem-solution / journey / compare-contrast.", zhDesc: "问题-解决/旅程/对比结构。")
                ],
                enProcess: "Combine structure option with story fields to produce a teachable narrative.",
                zhProcess: "结合叙事结构与字段，输出可教学叙事任务。",
                enScenario: "Language, humanities, and explanation-heavy classes.",
                zhScenario: "适用于语文、人文和解释型课程。"
            )
        case "service_blueprint":
            return methodGuide(
                enDescription: "Map learner journey and optimize teaching touchpoints.",
                zhDescription: "绘制学习旅程并优化教学触点。",
                inputs: [
                    commonKnowledge,
                    guideInput(enName: "Object Dictionary", zhName: "对象字典", type: "String", enDesc: "Roles and responsibilities.", zhDesc: "参与对象及职责。"),
                    guideInput(enName: "Goal Orientation", zhName: "目标导向", type: "String", enDesc: "Efficiency/engagement/equity/retention target.", zhDesc: "效率/参与度/公平/保持度导向。"),
                    guideInput(enName: "Journey Stages", zhName: "旅程阶段", type: "String", enDesc: "Pre/in/post lesson stages.", zhDesc: "课前/课中/课后阶段。")
                ],
                enProcess: "Output touchpoint-focused service flow with orientation-specific fields.",
                zhProcess: "输出以触点优化为核心的服务流程设计。",
                enScenario: "Redesigning full lesson experience flow.",
                zhScenario: "适用于完整教学流程重构。"
            )
        case "adaptive_learning_platform":
            return methodGuide(
                enDescription: "Define differentiated routing and feedback loops.",
                zhDescription: "定义差异化学习分流与反馈回路。",
                inputs: [
                    commonKnowledge,
                    guideInput(enName: "Adaptation Target", zhName: "适配目标", type: "String", enDesc: "Ability/pace/interest difference.", zhDesc: "能力/节奏/兴趣差异目标。"),
                    guideInput(enName: "Routing Rule", zhName: "分流规则", type: "String", enDesc: "How students are routed.", zhDesc: "学生如何分流。"),
                    guideInput(enName: "Feedback Trigger", zhName: "反馈触发条件", type: "String", enDesc: "When feedback is triggered.", zhDesc: "何时触发反馈。"),
                    guideInput(enName: "Return Strategy", zhName: "回流策略", type: "String", enDesc: "How learners return to main path.", zhDesc: "如何回流主路径。")
                ],
                enProcess: "Generate a differentiated learning-path design with intervention points.",
                zhProcess: "输出含干预节点的差异化学习路径。",
                enScenario: "Mixed-ability class with multi-path support.",
                zhScenario: "适用于混合能力班级分层支持。"
            )
        case "role_play":
            return methodGuide(
                enDescription: "Set role-based interaction for perspective negotiation.",
                zhDescription: "通过角色扮演进行立场协商与视角转换。",
                inputs: [
                    commonKnowledge,
                    guideInput(enName: "Role Dictionary", zhName: "角色字典", type: "String", enDesc: "Role responsibilities.", zhDesc: "各角色职责描述。"),
                    guideInput(enName: "Scene Design", zhName: "场景设计", type: "String", enDesc: "Context and objective.", zhDesc: "情境与目标。"),
                    guideInput(enName: "Facilitation Pattern", zhName: "组织方式", type: "String", enDesc: "Inner-outer / station / fishbowl.", zhDesc: "内外圈/站点轮换/鱼缸式。")
                ],
                enProcess: "Produce a role-play script scaffold and interaction rounds.",
                zhProcess: "输出角色扮演脚本骨架和轮次安排。",
                enScenario: "Debate-heavy social studies and ethics classes.",
                zhScenario: "适用于社会议题或伦理讨论课堂。"
            )
        case "structured_debate":
            return methodGuide(
                enDescription: "Run argumentation activities under explicit debate protocols.",
                zhDescription: "在明确协议下开展结构化辩论训练。",
                inputs: [
                    commonKnowledge,
                    guideInput(enName: "Debate Motion", zhName: "辩题陈述", type: "String", enDesc: "Formal debate statement.", zhDesc: "正式辩题陈述。"),
                    guideInput(enName: "Evidence Threshold", zhName: "证据门槛", type: "String", enDesc: "Minimum evidence quality.", zhDesc: "最低证据质量门槛。"),
                    guideInput(enName: "Debate Protocol", zhName: "辩论协议", type: "String", enDesc: "CER / Oxford / Toulmin.", zhDesc: "CER/牛津式/图尔敏。")
                ],
                enProcess: "Generate debate flow and protocol-specific support fields.",
                zhProcess: "生成辩论流程并附带协议专属字段。",
                enScenario: "Claim-evidence-reasoning classroom discussions.",
                zhScenario: "适用于观点-证据-推理训练课堂。"
            )
        case "world_cafe":
            return methodGuide(
                enDescription: "Use rotating-table discussion to co-construct ideas.",
                zhDescription: "通过轮转桌讨论共建多视角观点。",
                inputs: [
                    commonKnowledge,
                    guideInput(enName: "Core Question", zhName: "核心问题", type: "String", enDesc: "Shared rotating question.", zhDesc: "跨桌轮转的核心问题。"),
                    guideInput(enName: "Table Topics", zhName: "桌次主题", type: "String", enDesc: "Topic per table.", zhDesc: "每桌讨论主题。"),
                    guideInput(enName: "Rotation Plan", zhName: "轮转计划", type: "String", enDesc: "How groups rotate.", zhDesc: "小组轮转规则。")
                ],
                enProcess: "Combine rotation and harvest rules into a collaborative protocol.",
                zhProcess: "将轮转与汇总规则整合为协作流程。",
                enScenario: "Divergent brainstorming and consensus synthesis.",
                zhScenario: "适用于发散讨论与共识整合。"
            )
        case "game_mechanism":
            return methodGuide(
                enDescription: "Embed learning goals into game loops and progression.",
                zhDescription: "将学习目标嵌入游戏循环和进阶机制。",
                inputs: [
                    commonKnowledge,
                    guideInput(enName: "Goal Mapping", zhName: "学习目标映射", type: "String", enDesc: "Learning objective to game action map.", zhDesc: "学习目标到游戏行为映射。"),
                    guideInput(enName: "Core Rules", zhName: "核心规则", type: "String", enDesc: "Win/lose and turn rules.", zhDesc: "胜负与回合规则。"),
                    guideInput(enName: "Progression Style", zhName: "进阶方式", type: "String", enDesc: "Level / mission / badge.", zhDesc: "关卡/任务线/徽章进阶。")
                ],
                enProcess: "Output a rule-based game activity blueprint for reinforcement.",
                zhProcess: "输出可用于巩固练习的游戏活动蓝图。",
                enScenario: "Repetitive practice with motivation support.",
                zhScenario: "适用于高重复练习内容。"
            )
        case "pogil":
            return methodGuide(
                enDescription: "Guided inquiry with explicit team roles and checkpoints.",
                zhDescription: "通过角色分工和检查点进行引导式协作探究。",
                inputs: [
                    commonKnowledge,
                    guideInput(enName: "Team Role Dictionary", zhName: "小组角色字典", type: "String", enDesc: "Group role definitions.", zhDesc: "小组角色职责定义。"),
                    guideInput(enName: "Inquiry Ladder", zhName: "探究问题阶梯", type: "String", enDesc: "Progressive inquiry questions.", zhDesc: "递进式探究问题。"),
                    guideInput(enName: "Checkpoint Control", zhName: "检查点控制", type: "String", enDesc: "Teacher/peer/self gate mode.", zhDesc: "教师/同伴/自检把关模式。")
                ],
                enProcess: "Generate role-based inquiry sequence with checkpoint control.",
                zhProcess: "输出带检查点控制的角色化探究流程。",
                enScenario: "Small-group inquiry activities with scaffolding.",
                zhScenario: "适用于脚手架式小组探究。"
            )
        case "kanban_monitoring":
            return methodGuide(
                enDescription: "Visualize progress and blockers with kanban workflow.",
                zhDescription: "通过看板流程可视化进度与阻塞。",
                inputs: [
                    commonKnowledge,
                    guideInput(enName: "Board Columns", zhName: "看板列配置", type: "String", enDesc: "Column stages.", zhDesc: "看板阶段列配置。"),
                    guideInput(enName: "WIP Limit", zhName: "WIP 限制", type: "String", enDesc: "In-progress limits.", zhDesc: "在制任务数量限制。"),
                    guideInput(enName: "Refresh Frequency", zhName: "刷新频率", type: "String", enDesc: "How often board updates.", zhDesc: "看板更新频率。")
                ],
                enProcess: "Output a monitoring protocol for ongoing project execution.",
                zhProcess: "输出项目执行阶段的监控协议。",
                enScenario: "Project-based learning with parallel task tracking.",
                zhScenario: "适用于项目式学习并行任务管理。"
            )
        case "rubric_checklist":
            return methodGuide(
                enDescription: "Define transparent criteria and aggregation strategy.",
                zhDescription: "定义透明评价标准与汇总策略。",
                inputs: [
                    commonKnowledge,
                    guideInput(enName: "Dimension Dictionary", zhName: "评价维度字典", type: "String", enDesc: "Dimensions and definitions.", zhDesc: "评价维度及定义。"),
                    guideInput(enName: "Weight Configuration", zhName: "权重配置", type: "String", enDesc: "Weight by dimension.", zhDesc: "各维度权重。"),
                    guideInput(enName: "Summary Strategy", zhName: "汇总策略", type: "String", enDesc: "Weighted / threshold / grade-band.", zhDesc: "加权/门槛/分档策略。")
                ],
                enProcess: "Produce rubric template and strategy-specific aggregation rules.",
                zhProcess: "输出量规模版及策略化汇总规则。",
                enScenario: "Formative assessment and multi-dimension scoring.",
                zhScenario: "适用于形成性评价与多维评分。"
            )
        case "reflection_protocol":
            return methodGuide(
                enDescription: "Structure reflection prompts for post-activity learning loops.",
                zhDescription: "为活动后复盘建立结构化反思流程。",
                inputs: [
                    commonKnowledge,
                    guideInput(enName: "Structure Template", zhName: "反思结构模板", type: "String", enDesc: "What-So-Now / ORID / KSS.", zhDesc: "What-So-Now / ORID / KSS 模板。"),
                    guideInput(enName: "Prompt Group", zhName: "反思提示组", type: "String", enDesc: "Prompt set for learners.", zhDesc: "学生使用的提示问题组。"),
                    guideInput(enName: "Reflection Channel", zhName: "反思渠道", type: "String", enDesc: "Written/audio/peer interview.", zhDesc: "文字/语音/同伴访谈渠道。")
                ],
                enProcess: "Generate template-specific reflection prompts and action commitments.",
                zhProcess: "输出模板化反思问题与行动承诺。",
                enScenario: "End-of-task review and improvement planning.",
                zhScenario: "适用于任务结束后的复盘改进。"
            )
        case "learning_dashboard":
            return methodGuide(
                enDescription: "Track class indicators and trigger timely intervention.",
                zhDescription: "追踪班级指标并触发及时教学干预。",
                inputs: [
                    commonKnowledge,
                    guideInput(enName: "Metric Dictionary", zhName: "指标字典", type: "String", enDesc: "Metrics to track.", zhDesc: "需追踪的指标。"),
                    guideInput(enName: "Source Mapping", zhName: "数据来源映射", type: "String", enDesc: "Metric to source mapping.", zhDesc: "指标与数据源映射。"),
                    guideInput(enName: "Alert Threshold", zhName: "预警阈值", type: "String", enDesc: "Trigger threshold for intervention.", zhDesc: "干预触发阈值。")
                ],
                enProcess: "Combine indicator definitions and thresholds into dashboard rules.",
                zhProcess: "将指标定义与阈值合并为仪表盘监控规则。",
                enScenario: "Ongoing data-informed classroom adjustment.",
                zhScenario: "适用于持续数据驱动教学调控。"
            )
        case "metacognitive_routine":
            return methodGuide(
                enDescription: "Train students to plan, monitor, and adjust strategies.",
                zhDescription: "训练学生进行计划-监控-调整的元认知例程。",
                inputs: [
                    commonKnowledge,
                    guideInput(enName: "Routine Pattern", zhName: "例程模式", type: "String", enDesc: "Pattern of self-regulation routine.", zhDesc: "元认知例程模式。"),
                    guideInput(enName: "Plan Prompts", zhName: "计划提示", type: "String", enDesc: "Prompts before execution.", zhDesc: "执行前计划提示。"),
                    guideInput(enName: "Monitor Signals", zhName: "监控信号字典", type: "String", enDesc: "Signals for self-monitoring.", zhDesc: "自我监控信号。")
                ],
                enProcess: "Output routine prompts and strategy-adjustment library.",
                zhProcess: "输出例程提示与策略调整库。",
                enScenario: "Self-regulated learning and strategy transfer tasks.",
                zhScenario: "适用于自主学习和策略迁移训练。"
            )
        default:
            return nil
        }
    }

    private static func toolkitMethodExampleScenario(toolkitType: String, methodID: String) -> NodeDocExampleScenario? {
        switch methodID {
        case "context_hook":
            return toolkitFlowScenario(
                toolkitType: toolkitType,
                methodID: methodID,
                prevKnowledge: Bilingual.text(en: "Know names of common birds in Zhuhai.", zh: "已认识珠海常见鸟类名称。"),
                nextKnowledge: Bilingual.text(en: "Students can explain migration reasons.", zh: "学生能解释候鸟迁徙原因。"),
                formText: [
                    "context_hook_material": Bilingual.text(en: "Photo set: heron, egret, black-faced spoonbill", zh: "图片集：苍鹭、白鹭、黑脸琵鹭"),
                    "context_hook_questions": Bilingual.text(en: "1. Which birds stay year-round?\n2. Why do some birds migrate?", zh: "1. 哪些鸟常年居住？\n2. 为什么有些鸟会迁徙？")
                ],
                formOptions: [
                    "context_hook_response_pattern": "think_pair_share",
                    "context_hook_time_budget": "3min"
                ]
            )
        case "field_observation":
            return toolkitFlowScenario(
                toolkitType: toolkitType,
                methodID: methodID,
                prevKnowledge: Bilingual.text(en: "Students know migratory vs resident birds.", zh: "学生已理解候鸟与留鸟区分。"),
                nextKnowledge: Bilingual.text(en: "Students summarize observed distribution patterns.", zh: "学生能总结观察到的分布规律。"),
                formText: [
                    "field_obs_site": Bilingual.text(en: "Qianshan River wetland", zh: "前山河湿地"),
                    "field_obs_focus": Bilingual.text(en: "Observe species and activity periods.", zh: "观察鸟种与活动时段。"),
                    "field_obs_sampling_rule": Bilingual.text(en: "Observe 10 min every afternoon for one week.", zh: "连续一周每天下午观察10分钟。"),
                    "field_obs_class_dict": Bilingual.text(en: "Resident | Stays all year\nMigratory | Seasonal appearance", zh: "留鸟 | 常年出现\n候鸟 | 季节性出现")
                ],
                formOptions: [
                    "field_obs_task_structure": "classification",
                    "field_obs_capture": "photo"
                ]
            )
        case "source_analysis":
            return toolkitFlowScenario(
                toolkitType: toolkitType,
                methodID: methodID,
                prevKnowledge: Bilingual.text(en: "Students can identify bird species names.", zh: "学生能识别常见鸟种名称。"),
                nextKnowledge: Bilingual.text(en: "Students can justify claims with source evidence.", zh: "学生能用资料证据支撑结论。"),
                formText: [
                    "source_analysis_set": Bilingual.text(en: "Local bird atlas + migration map + climate chart", zh: "本地鸟类图鉴 + 迁徙路线图 + 气候图"),
                    "source_analysis_rule": Bilingual.text(en: "Extract evidence containing season + location.", zh: "优先提取包含季节与地点信息的证据。"),
                    "source_analysis_matrix": Bilingual.text(en: "Claim | Evidence | Confidence", zh: "主张 | 证据 | 置信度")
                ],
                formOptions: [
                    "source_analysis_verify": "cross_source"
                ]
            )
        case "sensor_probe":
            return toolkitFlowScenario(
                toolkitType: toolkitType,
                methodID: methodID,
                prevKnowledge: Bilingual.text(en: "Students understand habitat preferences.", zh: "学生已理解鸟类栖息偏好。"),
                nextKnowledge: Bilingual.text(en: "Students can correlate environment data with sightings.", zh: "学生能关联环境数据与鸟类观测。"),
                formText: [
                    "sensor_probe_variables": Bilingual.text(en: "Temp | °C\nHumidity | %\nBird Count | count", zh: "温度 | ℃\n湿度 | %\n鸟类数量 | 次"),
                    "sensor_probe_setup": Bilingual.text(en: "Use handheld weather sensor at fixed points.", zh: "在固定点位使用手持气象传感器。"),
                    "sensor_probe_sampling_plan": Bilingual.text(en: "3 points, twice daily, 5 days.", zh: "3个点位，每天2次，持续5天。")
                ]
            )
        case "immersive_simulation":
            return toolkitFlowScenario(
                toolkitType: toolkitType,
                methodID: methodID,
                prevKnowledge: Bilingual.text(en: "Students know local migration routes.", zh: "学生已了解本地候鸟迁徙路线。"),
                nextKnowledge: Bilingual.text(en: "Students evaluate habitat-protection decisions.", zh: "学生能评估栖息地保护决策。"),
                formText: [
                    "immersive_scene": Bilingual.text(en: "Wetland management crisis simulation", zh: "湿地管理危机场景模拟"),
                    "immersive_triggers": Bilingual.text(en: "Trigger A: sudden cold front\nTrigger B: habitat disturbance report", zh: "触发A：寒潮来袭\n触发B：栖息地干扰上报"),
                    "immersive_debrief": Bilingual.text(en: "Which decision had best ecological impact?", zh: "哪种决策对生态影响最好？")
                ],
                formOptions: [
                    "immersive_role_mode": "group_role"
                ]
            )
        case "low_fidelity_prototype":
            return toolkitFlowScenario(
                toolkitType: toolkitType,
                methodID: methodID,
                prevKnowledge: Bilingual.text(en: "Students know key migration concepts.", zh: "学生已掌握迁徙关键概念。"),
                nextKnowledge: Bilingual.text(en: "Students can explain prototype logic and limits.", zh: "学生能解释原型逻辑与局限。"),
                formText: [
                    "lowfi_problem_definition": Bilingual.text(en: "How to explain migration routes clearly to peers?", zh: "如何向同伴清晰解释迁徙路线？"),
                    "lowfi_goal": Bilingual.text(en: "Build a route-board model with climate cues.", zh: "制作带气候信息的迁徙路线板模型。"),
                    "lowfi_material_constraints": Bilingual.text(en: "Paper, strings, labels, 20 minutes.", zh: "纸张、线、标签，20分钟完成。")
                ]
            )
        case "physical_computing":
            return toolkitFlowScenario(
                toolkitType: toolkitType,
                methodID: methodID,
                prevKnowledge: Bilingual.text(en: "Students understand migration timing factors.", zh: "学生已理解迁徙时机影响因素。"),
                nextKnowledge: Bilingual.text(en: "Students can map sensor input to alert behavior.", zh: "学生能将传感输入映射到提醒行为。"),
                formText: [
                    "phycomp_function_goal": Bilingual.text(en: "Build a wetland alert light by sensor threshold.", zh: "基于传感阈值触发湿地提醒灯。"),
                    "phycomp_modules": Bilingual.text(en: "Temp sensor + microcontroller + RGB LED", zh: "温度传感器 + 控制板 + RGB灯"),
                    "phycomp_logic_flow": Bilingual.text(en: "Temp high -> warning color; normal -> green", zh: "温度过高 -> 警示色；正常 -> 绿色")
                ]
            )
        case "story_construction":
            return toolkitFlowScenario(
                toolkitType: toolkitType,
                methodID: methodID,
                prevKnowledge: Bilingual.text(en: "Students know names and sounds of common birds.", zh: "学生已掌握常见鸟名与读音。"),
                nextKnowledge: Bilingual.text(en: "Students narrate migration story from data.", zh: "学生能基于数据讲述迁徙故事。"),
                formText: [
                    "story_mainline": Bilingual.text(en: "1. Winter arrives in Zhuhai\n2. Birds choose habitats\n3. Humans influence routes", zh: "1. 冬季来到珠海\n2. 鸟类选择栖息地\n3. 人类活动影响路线"),
                    "story_keywords": Bilingual.text(en: "migratory\nresident\nwetland\nhabitat", zh: "候鸟\n留鸟\n湿地\n栖息地"),
                    "story_journey_stages": Bilingual.text(en: "Arrival | Observation\nAdaptation | Feeding\nDeparture | Route selection", zh: "到达 | 观察\n适应 | 觅食\n离开 | 路径选择")
                ],
                formOptions: [
                    "story_structure": "journey"
                ]
            )
        case "service_blueprint":
            return toolkitFlowScenario(
                toolkitType: toolkitType,
                methodID: methodID,
                prevKnowledge: Bilingual.text(en: "Students can classify local bird species.", zh: "学生能分类本地常见鸟类。"),
                nextKnowledge: Bilingual.text(en: "Students optimize learning touchpoints by feedback.", zh: "学生能根据反馈优化学习触点。"),
                formText: [
                    "service_object_dict": Bilingual.text(en: "Teacher | Facilitation\nStudent Group | Observation\nParent | Field support", zh: "教师 | 引导\n学生组 | 观察\n家长 | 课后支持"),
                    "service_journey_stages": Bilingual.text(en: "Pre-class prep\nIn-class inquiry\nPost-class sharing", zh: "课前准备\n课中探究\n课后分享"),
                    "service_touchpoint_issues": Bilingual.text(en: "Data upload delay at home", zh: "课后在家上传数据速度慢")
                ],
                formOptions: [
                    "service_goal_orientation": "engagement"
                ]
            )
        case "adaptive_learning_platform":
            return toolkitFlowScenario(
                toolkitType: toolkitType,
                methodID: methodID,
                prevKnowledge: Bilingual.text(en: "Students finished initial bird-recognition quiz.", zh: "学生完成鸟类识别初测。"),
                nextKnowledge: Bilingual.text(en: "Students follow differentiated tasks then return.", zh: "学生完成分层任务并回流主线。"),
                formText: [
                    "adaptive_routing_rule": Bilingual.text(en: "Score < 60 -> remediation path; >= 60 -> challenge path", zh: "分数<60走补救路径；>=60走挑战路径"),
                    "adaptive_feedback_trigger": Bilingual.text(en: "Two consecutive wrong answers trigger hint card.", zh: "连续两次错误触发提示卡。"),
                    "adaptive_return_strategy": Bilingual.text(en: "Complete checkpoint quiz then return to core task.", zh: "完成检查点测验后回到主任务。")
                ],
                formOptions: [
                    "adaptive_target": "pace_diff"
                ]
            )
        case "role_play":
            return toolkitFlowScenario(
                toolkitType: toolkitType,
                methodID: methodID,
                prevKnowledge: Bilingual.text(en: "Students learned migration and habitat constraints.", zh: "学生已学习迁徙与栖息地约束。"),
                nextKnowledge: Bilingual.text(en: "Students compare perspectives and negotiate decisions.", zh: "学生能比较视角并协商方案。"),
                formText: [
                    "roleplay_role_dict": Bilingual.text(en: "Wetland Manager | Balance tourism and ecology\nResearcher | Provide evidence", zh: "湿地管理者 | 平衡旅游与生态\n研究员 | 提供证据"),
                    "roleplay_scene": Bilingual.text(en: "City plans night-light show near wetland.", zh: "城市计划在湿地附近举办夜间灯光秀。"),
                    "roleplay_conflict_trigger": Bilingual.text(en: "Bird activity drops after trial lights.", zh: "试运行后鸟类活动明显下降。")
                ],
                formOptions: [
                    "roleplay_facilitation": "fishbowl"
                ]
            )
        case "structured_debate":
            return toolkitFlowScenario(
                toolkitType: toolkitType,
                methodID: methodID,
                prevKnowledge: Bilingual.text(en: "Students collected evidence from migration reports.", zh: "学生已收集迁徙报告证据。"),
                nextKnowledge: Bilingual.text(en: "Students justify claims with evidence and reasoning.", zh: "学生能基于证据进行论证。"),
                formText: [
                    "debate_motion": Bilingual.text(en: "Should tourism zones be seasonally restricted?", zh: "是否应在候鸟季节限制旅游活动？"),
                    "debate_evidence_threshold": Bilingual.text(en: "At least two cross-source evidences per claim.", zh: "每个主张至少两条跨来源证据。"),
                    "debate_claim_template": Bilingual.text(en: "Claim | Evidence | Reasoning", zh: "观点 | 证据 | 推理")
                ],
                formOptions: [
                    "debate_protocol": "cer"
                ]
            )
        case "world_cafe":
            return toolkitFlowScenario(
                toolkitType: toolkitType,
                methodID: methodID,
                prevKnowledge: Bilingual.text(en: "Students know key bird-protection facts.", zh: "学生已掌握鸟类保护关键事实。"),
                nextKnowledge: Bilingual.text(en: "Students synthesize group ideas into action plan.", zh: "学生能将多组观点整合为行动方案。"),
                formText: [
                    "cafe_core_question": Bilingual.text(en: "How can our school help migratory birds?", zh: "学校如何帮助保护候鸟？"),
                    "cafe_table_topics": Bilingual.text(en: "Habitat / Awareness / Data collection", zh: "栖息地 / 宣传 / 数据采集"),
                    "cafe_rotation_plan": Bilingual.text(en: "Rotate every 8 minutes; one host stays.", zh: "每8分钟轮转，一人留桌主持。")
                ]
            )
        case "game_mechanism":
            return toolkitFlowScenario(
                toolkitType: toolkitType,
                methodID: methodID,
                prevKnowledge: Bilingual.text(en: "Students can identify 8 local bird species.", zh: "学生可识别8种本地鸟类。"),
                nextKnowledge: Bilingual.text(en: "Students improve retention through mission loop.", zh: "学生通过任务循环提升记忆保持。"),
                formText: [
                    "game_goal_mapping": Bilingual.text(en: "Correct pronunciation -> mission completion", zh: "正确读音 -> 完成任务"),
                    "game_core_rules": Bilingual.text(en: "Team challenge, time-limited rounds.", zh: "小组挑战，限时回合制。"),
                    "game_mission_chain": Bilingual.text(en: "Mission1 sound match -> Mission2 habitat match", zh: "任务1读音匹配 -> 任务2栖息地匹配")
                ],
                formOptions: [
                    "game_progression": "mission"
                ]
            )
        case "pogil":
            return toolkitFlowScenario(
                toolkitType: toolkitType,
                methodID: methodID,
                prevKnowledge: Bilingual.text(en: "Students have baseline understanding of migration.", zh: "学生对迁徙已有基础理解。"),
                nextKnowledge: Bilingual.text(en: "Students produce group inference with role collaboration.", zh: "学生通过分工协作产出推理结论。"),
                formText: [
                    "pogil_role_dict": Bilingual.text(en: "Facilitator | Timekeeper | Recorder", zh: "主持人 | 计时员 | 记录员"),
                    "pogil_inquiry_ladder": Bilingual.text(en: "Q1 facts -> Q2 cause -> Q3 decision", zh: "Q1事实 -> Q2原因 -> Q3决策"),
                    "pogil_sheet_focus": Bilingual.text(en: "Infer migration cause from multi-source evidence", zh: "基于多源证据推断迁徙原因")
                ],
                formOptions: [
                    "pogil_checkpoint": "peer_gate"
                ]
            )
        case "kanban_monitoring":
            return toolkitFlowScenario(
                toolkitType: toolkitType,
                methodID: methodID,
                prevKnowledge: Bilingual.text(en: "Project tasks have been assigned.", zh: "项目任务已分配。"),
                nextKnowledge: Bilingual.text(en: "Students monitor blockers and adjust execution.", zh: "学生能监控阻塞并调整执行。"),
                formText: [
                    "kanban_columns": Bilingual.text(en: "To Do | Doing | Review | Done", zh: "待办 | 进行中 | 复核 | 完成"),
                    "kanban_wip_limit": Bilingual.text(en: "Doing <= 2 tasks per group", zh: "每组进行中任务不超过2个"),
                    "kanban_blocker_types": Bilingual.text(en: "Data missing / Time conflict / Device issue", zh: "数据缺失 / 时间冲突 / 设备问题")
                ],
                formOptions: [
                    "kanban_refresh": "each_phase"
                ]
            )
        case "rubric_checklist":
            return toolkitFlowScenario(
                toolkitType: toolkitType,
                methodID: methodID,
                prevKnowledge: Bilingual.text(en: "Students completed inquiry outputs.", zh: "学生完成探究输出。"),
                nextKnowledge: Bilingual.text(en: "Students receive transparent feedback by rubric.", zh: "学生获得可解释的量规反馈。"),
                formText: [
                    "rubric_dimension_dict": Bilingual.text(en: "Evidence quality | Collaboration | Reflection", zh: "证据质量 | 协作表现 | 反思质量"),
                    "rubric_weight_config": Bilingual.text(en: "Evidence 40 | Collaboration 30 | Reflection 30", zh: "证据40 | 协作30 | 反思30"),
                    "rubric_weight_formula": Bilingual.text(en: "Score = sum(dimension * weight)", zh: "总分=维度得分×权重求和")
                ],
                formOptions: [
                    "rubric_levels": "level4",
                    "rubric_summary_strategy": "weighted_avg"
                ]
            )
        case "reflection_protocol":
            return toolkitFlowScenario(
                toolkitType: toolkitType,
                methodID: methodID,
                prevKnowledge: Bilingual.text(en: "Students finished role-play activity.", zh: "学生完成角色扮演活动。"),
                nextKnowledge: Bilingual.text(en: "Students set actionable next-step commitments.", zh: "学生形成可执行的下一步承诺。"),
                formText: [
                    "reflect_prompt_group": Bilingual.text(en: "Keep / Stop / Start prompts for team review", zh: "围绕 Keep/Stop/Start 进行团队复盘"),
                    "reflect_timing": Bilingual.text(en: "Immediately after discussion", zh: "讨论结束后立即进行"),
                    "reflect_kss_keep": Bilingual.text(en: "What collaboration behavior should we keep?", zh: "哪些协作行为要继续保持？"),
                    "reflect_kss_stop": Bilingual.text(en: "What low-value behavior should we stop?", zh: "哪些低效行为要停止？"),
                    "reflect_kss_start": Bilingual.text(en: "What new action should we start next lesson?", zh: "下节课准备开始哪些新行动？")
                ],
                formOptions: [
                    "reflect_structure_template": "kss",
                    "reflect_channel": "written"
                ]
            )
        case "learning_dashboard":
            return toolkitFlowScenario(
                toolkitType: toolkitType,
                methodID: methodID,
                prevKnowledge: Bilingual.text(en: "Class has multi-week learning data.", zh: "班级已有多周学习数据。"),
                nextKnowledge: Bilingual.text(en: "Teacher adjusts support by indicator alerts.", zh: "教师根据指标预警调整支持策略。"),
                formText: [
                    "dashboard_metric_dict": Bilingual.text(en: "Completion rate | Quiz score | Participation", zh: "完成率 | 小测得分 | 参与度"),
                    "dashboard_source_mapping": Bilingual.text(en: "Completion->LMS, Score->Quiz, Participation->Observation", zh: "完成率->平台，得分->测验，参与度->观察"),
                    "dashboard_alert_threshold": Bilingual.text(en: "Quiz < 60 for 2 lessons triggers intervention", zh: "连续两课得分<60触发干预")
                ],
                formOptions: [
                    "dashboard_cycle": "weekly"
                ]
            )
        case "metacognitive_routine":
            return toolkitFlowScenario(
                toolkitType: toolkitType,
                methodID: methodID,
                prevKnowledge: Bilingual.text(en: "Students can complete tasks with guidance.", zh: "学生能在引导下完成任务。"),
                nextKnowledge: Bilingual.text(en: "Students self-monitor and adjust strategies.", zh: "学生能进行自我监控和策略调整。"),
                formText: [
                    "meta_plan_prompts": Bilingual.text(en: "Before starting: goal, resource, risk", zh: "开始前：目标、资源、风险"),
                    "meta_monitor_signals": Bilingual.text(en: "Signal: confusion -> Action: ask peer", zh: "信号：困惑 -> 动作：同伴求助"),
                    "meta_adjust_strategy": Bilingual.text(en: "If no progress in 5 min, switch strategy.", zh: "5分钟无进展则切换策略。")
                ],
                formOptions: [
                    "meta_routine_pattern": "plan_monitor_adjust"
                ]
            )
        default:
            return nil
        }
    }

    private static func toolkitFlowScenario(
        toolkitType: String,
        methodID: String,
        prevKnowledge: String,
        nextKnowledge: String,
        formText: [String: String],
        formOptions: [String: String] = [:]
    ) -> NodeDocExampleScenario {
        NodeDocExampleScenario(
            nodes: [
                NodeDocExampleNode(
                    id: "k_prev",
                    type: EduNodeType.knowledge,
                    x: -320,
                    y: -40,
                    customTitle: Bilingual.text(en: "Prior Knowledge", zh: "前置知识"),
                    textValue: prevKnowledge,
                    selectedOption: S("edu.knowledge.type.understand")
                ),
                NodeDocExampleNode(
                    id: "tool",
                    type: toolkitType,
                    x: 0,
                    y: 0,
                    customTitle: Bilingual.text(en: "Toolkit Step", zh: "方法环节"),
                    selectedMethodID: methodID,
                    formTextFields: formText,
                    formOptionFields: formOptions
                ),
                NodeDocExampleNode(
                    id: "k_next",
                    type: EduNodeType.knowledge,
                    x: 340,
                    y: 40,
                    customTitle: Bilingual.text(en: "Post Knowledge", zh: "后续知识"),
                    textValue: nextKnowledge,
                    selectedOption: S("edu.knowledge.type.apply")
                )
            ],
            connections: [
                NodeDocExampleConnection(sourceNodeID: "k_prev", sourcePortIndex: 0, targetNodeID: "tool", targetPortIndex: 0),
                NodeDocExampleConnection(sourceNodeID: "tool", sourcePortIndex: 0, targetNodeID: "k_next", targetPortIndex: 0)
            ]
        )
    }

    private static func knowledgeExampleScenario() -> NodeDocExampleScenario {
        NodeDocExampleScenario(
            nodes: [
                NodeDocExampleNode(
                    id: "knowledge_1",
                    type: EduNodeType.knowledge,
                    x: -230,
                    y: -20,
                    customTitle: Bilingual.text(en: "K1: Zhuhai Climate", zh: "K1：珠海气候"),
                    textValue: Bilingual.text(en: "Zhuhai has warm and humid winter suitable for many bird species.", zh: "珠海冬季温暖湿润，适合多种鸟类停留。"),
                    selectedOption: S("edu.knowledge.type.understand")
                ),
                NodeDocExampleNode(
                    id: "knowledge_2",
                    type: EduNodeType.knowledge,
                    x: 220,
                    y: 30,
                    customTitle: Bilingual.text(en: "K2: Migratory vs Resident", zh: "K2：候鸟与留鸟"),
                    textValue: Bilingual.text(en: "Students classify birds into migratory and resident by seasonal behavior.", zh: "学生依据季节行为区分候鸟与留鸟。"),
                    selectedOption: S("edu.knowledge.type.apply")
                )
            ],
            connections: [
                NodeDocExampleConnection(sourceNodeID: "knowledge_1", sourcePortIndex: 0, targetNodeID: "knowledge_2", targetPortIndex: 0)
            ]
        )
    }

    private static func metricValueExampleScenario() -> NodeDocExampleScenario {
        NodeDocExampleScenario(
            nodes: [
                NodeDocExampleNode(
                    id: "metric_value",
                    type: EduNodeType.metricValue,
                    x: 0,
                    y: 0,
                    customTitle: Bilingual.text(en: "Participation Score", zh: "参与度分值"),
                    textValue: "82"
                )
            ]
        )
    }

    private static func evaluationMetricExampleScenario() -> NodeDocExampleScenario {
        NodeDocExampleScenario(
            nodes: [
                NodeDocExampleNode(id: "k_score", type: EduNodeType.metricValue, x: -420, y: -120, customTitle: Bilingual.text(en: "Knowledge", zh: "知识"), textValue: "84"),
                NodeDocExampleNode(id: "e_score", type: EduNodeType.metricValue, x: -420, y: 0, customTitle: Bilingual.text(en: "Engagement", zh: "参与"), textValue: "76"),
                NodeDocExampleNode(id: "p_score", type: EduNodeType.metricValue, x: -420, y: 120, customTitle: Bilingual.text(en: "Participation", zh: "协作"), textValue: "88"),
                NodeDocExampleNode(id: "metric", type: EduNodeType.evaluationMetric, x: 40, y: 0, customTitle: Bilingual.text(en: "Evaluation Metric", zh: "评价指标"))
            ],
            connections: [
                NodeDocExampleConnection(sourceNodeID: "k_score", sourcePortIndex: 0, targetNodeID: "metric", targetPortIndex: 0),
                NodeDocExampleConnection(sourceNodeID: "e_score", sourcePortIndex: 0, targetNodeID: "metric", targetPortIndex: 1),
                NodeDocExampleConnection(sourceNodeID: "p_score", sourcePortIndex: 0, targetNodeID: "metric", targetPortIndex: 2)
            ]
        )
    }

    private static func evaluationSummaryExampleScenario() -> NodeDocExampleScenario {
        NodeDocExampleScenario(
            nodes: [
                NodeDocExampleNode(id: "k_score", type: EduNodeType.metricValue, x: -520, y: -120, customTitle: Bilingual.text(en: "Knowledge", zh: "知识"), textValue: "84"),
                NodeDocExampleNode(id: "e_score", type: EduNodeType.metricValue, x: -520, y: 0, customTitle: Bilingual.text(en: "Engagement", zh: "参与"), textValue: "76"),
                NodeDocExampleNode(id: "p_score", type: EduNodeType.metricValue, x: -520, y: 120, customTitle: Bilingual.text(en: "Participation", zh: "协作"), textValue: "88"),
                NodeDocExampleNode(id: "metric", type: EduNodeType.evaluationMetric, x: -60, y: 0, customTitle: Bilingual.text(en: "Metric", zh: "指标")),
                NodeDocExampleNode(id: "summary", type: EduNodeType.evaluationSummary, x: 340, y: 0, customTitle: Bilingual.text(en: "Summary", zh: "汇总"))
            ],
            connections: [
                NodeDocExampleConnection(sourceNodeID: "k_score", sourcePortIndex: 0, targetNodeID: "metric", targetPortIndex: 0),
                NodeDocExampleConnection(sourceNodeID: "e_score", sourcePortIndex: 0, targetNodeID: "metric", targetPortIndex: 1),
                NodeDocExampleConnection(sourceNodeID: "p_score", sourcePortIndex: 0, targetNodeID: "metric", targetPortIndex: 2),
                NodeDocExampleConnection(sourceNodeID: "metric", sourcePortIndex: 0, targetNodeID: "summary", targetPortIndex: 0)
            ]
        )
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

    private static func inferLegacyToolkitCategory(from selectedType: String?) -> EduToolkitCategory {
        guard let selectedType else { return .communicationNegotiation }
        let value = selectedType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty else { return .communicationNegotiation }

        let perceptionTokens = [
            "observation", "inquiry", "观察", "探究"
        ]
        if perceptionTokens.contains(where: { value.contains($0) }) {
            return .perceptionInquiry
        }

        let constructionTokens = [
            "practice", "demonstration", "练习", "示范"
        ]
        if constructionTokens.contains(where: { value.contains($0) }) {
            return .constructionPrototype
        }

        let regulationTokens = [
            "peer review", "peerreview", "同伴"
        ]
        if regulationTokens.contains(where: { value.contains($0) }) {
            return .regulationMetacognition
        }

        return .communicationNegotiation
    }

    private static func encodeJSONStringDictionary(_ dict: [String: String]) -> String {
        guard !dict.isEmpty else { return "{}" }
        if let data = try? JSONEncoder().encode(dict),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return "{}"
    }

    private static func decodeJSONStringDictionary(_ raw: String?) -> [String: String] {
        guard let raw, !raw.isEmpty, let data = raw.data(using: .utf8) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
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
