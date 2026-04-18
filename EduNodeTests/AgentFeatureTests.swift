import Foundation
import CoreGraphics
import Testing
import GNodeKit
@testable import EduNode

@MainActor
struct AgentFeatureTests {
    @Test func templateParserExtractsCoreSections() throws {
        let text = """
        教师姓名：张老师
        学生年级：高一
        指导思想/设计理念
        以目标驱动课堂设计。
        文本分析
        【what】
        文章围绕自然灾害展开。
        【why】
        帮助学生理解灾后希望。
        【how】
        采用叙事结构和时间线推进。
        学情分析
        已有知识：学生已了解一般自然灾害概念。
        未有知识：缺少具体文本分析经验。
        学习目标
        学生能够概括文本内容并说明作者态度变化。
        教学资源
        PPT, worksheet
        教学过程
        导入、阅读、讨论、总结
        教学反思
        记录课堂生成与调整点。
        """

        let document = try EduLessonTemplateParser.parse(
            text: text,
            sourceName: "sample.txt"
        )

        let kinds = document.schema.sections.map(\.kind)
        #expect(kinds.contains(.designRationale))
        #expect(kinds.contains(.textAnalysisWhat))
        #expect(kinds.contains(.textAnalysisWhy))
        #expect(kinds.contains(.textAnalysisHow))
        #expect(kinds.contains(.teachingProcess))
        #expect(kinds.contains(.reflection))
    }

    @Test func templateParserTrimsPreambleAndCapturesExactScaffold() throws {
        let text = """
        英语教师职业技能训练课程期末考核打分表
        课堂互动
        教师姓名：
        学生年级：高一
        教材版本：外研版必修三
        单元及语篇：U6 Developing Ideas---Stars after the Storm
        课型及主题：阅读课 人与自然
        指导思想/设计理念
        本课以核心素养为统领。
        文本分析
        结构化知识图表
        本课在单元整体教学设计中的位置
        【what】
        【why】
        【how】
        学情分析
        已有知识：
        未有知识：
        学习目标
        教学重点和难点
        （一）教学重点
        （二）教学难点
        教学资源
        教学过程（第一课时）
        学习目标
        学习活动、活动层次及时间
        设计意图
        效果评价
        作业
        Handout
        教学原文：
        """

        let document = try EduLessonTemplateParser.parse(
            text: text,
            sourceName: "realistic-template.txt"
        )

        #expect(!document.rawText.contains("期末考核打分表"))
        #expect(document.schema.frontMatterFieldLabels == ["教师姓名", "学生年级", "教材版本", "单元及语篇", "课型及主题"])
        #expect(document.schema.teachingProcessColumnTitles == ["学习目标", "学习活动、活动层次及时间", "设计意图", "效果评价"])
        #expect(document.schema.analysisSubsectionTitles == ["【what】", "【why】", "【how】"])
        #expect(document.schema.learnerAnalysisFieldLabels == ["已有知识：", "未有知识："])
        #expect(document.schema.keyPointDifficultyLabels == ["（一）教学重点", "（二）教学难点"])
        #expect(document.schema.sections.contains(where: { $0.kind == .knowledgeStructure }))
        #expect(document.schema.sections.contains(where: { $0.kind == .unitPosition }))
        #expect(document.schema.sections.contains(where: { $0.kind == .homework }))
        #expect(document.schema.sections.contains(where: { $0.kind == .handout }))
        #expect(document.schema.sections.contains(where: { $0.kind == .sourceText }))
    }

    @Test func referenceComplianceFlagsMissingTemplateFieldsAndSections() throws {
        let reference = try EduLessonReferenceDocument.build(
            sourceName: "reference.md",
            extractedMarkdown: """
            教师姓名：
            学生年级：
            指导思想/设计理念
            文本分析
            【what】
            【why】
            【how】
            学情分析
            已有知识：
            未有知识：
            学习目标
            （一）教学重点
            （二）教学难点
            教学过程（第一课时）
            学习目标
            学习活动、活动层次及时间
            设计意图
            效果评价
            作业
            Handout
            教学原文
            """
        )

        let report = EduLessonTemplateComplianceChecker.validate(
            markdown: """
            教师姓名：
            ## 指导思想/设计理念
            以核心素养统整目标与活动。
            ## 文本分析
            ### 【what】
            聚焦文本内容。
            ### 【why】
            说明育人价值。
            ## 学情分析
            学生基础差异较大。
            ## 学习目标
            关注文本理解。
            ## 教学过程（第一课时）
            | 学习目标 | 学习活动、活动层次及时间 | 设计意图 |
            | --- | --- | --- |
            | 理解文本 | 导入与阅读 | 建立整体认知 |
            """,
            referenceDocument: reference
        )

        #expect(report.missingFrontMatterFields == ["学生年级"])
        #expect(report.missingAnalysisSubsectionTitles == ["【how】"])
        #expect(report.missingTeachingProcessColumns == ["效果评价"])
        #expect(report.missingLearnerAnalysisLabels.contains("已有知识"))
        #expect(report.missingLearnerAnalysisLabels.contains("未有知识"))
        #expect(report.missingKeyPointDifficultyLabels.contains("（一）教学重点"))
        #expect(report.missingKeyPointDifficultyLabels.contains("（二）教学难点"))
        #expect(report.missingSectionTitles.contains("作业"))
        #expect(report.missingSectionTitles.contains("Handout"))
        #expect(report.missingSectionTitles.contains("教学原文"))
        #expect(!report.isCompliant)
    }

    @Test func referenceComplianceFlagsSectionOrderMismatch() throws {
        let reference = try EduLessonReferenceDocument.build(
            sourceName: "reference.md",
            extractedMarkdown: """
            指导思想/设计理念
            文本分析
            学习目标
            教学资源
            教学过程（第一课时）
            """
        )

        let report = EduLessonTemplateComplianceChecker.validate(
            markdown: """
            ## 指导思想/设计理念
            内容
            ## 学习目标
            内容
            ## 文本分析
            内容
            ## 教学资源
            内容
            ## 教学过程（第一课时）
            内容
            """,
            referenceDocument: reference
        )

        #expect(report.sectionOrderMismatches == ["学习目标"])
        #expect(report.missingSectionTitles.isEmpty)
        #expect(!report.isCompliant)
    }

    @Test func structuralNormalizerReinsertsMissingReferenceSectionsAndLabels() throws {
        let reference = try EduLessonReferenceDocument.build(
            sourceName: "reference.md",
            extractedMarkdown: """
            教师姓名：
            学生年级：
            教材版本：
            单元及语篇：
            课型及主题：
            指导思想/设计理念
            文本分析
            本课在单元整体教学设计中的位置
            【what】
            【why】
            【how】
            结构化知识图表
            学情分析
            已有知识：
            未有知识：
            学习目标
            教学重点和难点
            （一）教学重点
            （二）教学难点
            教学资源
            教学过程（第一课时）
            学习目标
            学习活动、活动层次及时间
            设计意图
            效果评价
            作业
            Handout
            教学原文：
            """
        )

        let normalized = EduLessonTemplateStructuralNormalizer.normalize(
            markdown: """
            教师姓名：张老师
            ## 指导思想/设计理念
            以核心素养统整课堂目标。
            ## 文本分析
            ### 【what】
            聚焦飓风叙事内容。
            ### 【why】
            强调在灾难中寻找希望。
            ### 【how】
            通过时间线与叙事视角组织表达。
            ## 学情分析
            学生整体能把握文本主旨，但对情感变化的证据提取仍不稳定。
            ## 学习目标
            在学习本课后，学生能够：
            1. 概括文本内容。
            ## 教学重点和难点
            学生能够说明情绪变化。
            ## 教学过程（第一课时）
            活动围绕导入、阅读和讨论展开。
            """,
            referenceDocument: reference
        )

        let report = EduLessonTemplateComplianceChecker.validate(
            markdown: normalized,
            referenceDocument: reference
        )

        #expect(report.isCompliant)
        #expect(normalized.contains("教材版本："))
        #expect(normalized.contains("单元及语篇："))
        #expect(normalized.contains("课型及主题："))
        #expect(normalized.contains("已有知识："))
        #expect(normalized.contains("未有知识："))
        #expect(normalized.contains("（一）教学重点"))
        #expect(normalized.contains("（二）教学难点"))
        #expect(normalized.contains("学习活动、活动层次及时间"))
        #expect(normalized.contains("效果评价"))
        #expect(normalized.contains("作业"))
        #expect(normalized.contains("Handout"))
        #expect(normalized.contains("教学原文"))
    }

    @Test func materializationAnalyzerAsksForAnalysisAndReflectionButNotProcessWhenGraphExists() throws {
        let templateText = """
        指导思想/设计理念
        文本分析
        【what】
        【why】
        【how】
        学情分析
        已有知识
        未有知识
        学习目标
        教学重点和难点
        教学资源
        教学过程
        教学反思
        """
        let template = try EduLessonTemplateParser.parse(
            text: templateText,
            sourceName: "lesson-template.txt"
        )
        let file = makeWorkspaceFile(
            data: try makeKnowledgeToolkitGraphData(),
            goalsText: "学生能够概括文章内容\n学生能够说明作者情感变化",
            resourceConstraints: "PPT, worksheet",
            studentSupportNotes: "部分学生需要额外阅读支架"
        )

        let items = EduLessonMaterializationAnalyzer.missingInfoItems(
            template: template,
            file: file,
            baselineMarkdown: "# Baseline"
        )

        #expect(items.contains(where: { $0.sectionKind == .textAnalysisWhat }))
        #expect(items.contains(where: { $0.sectionKind == .textAnalysisWhy }))
        #expect(items.contains(where: { $0.sectionKind == .textAnalysisHow }))
        #expect(items.contains(where: { $0.sectionKind == .reflection }))
        #expect(!items.contains(where: { $0.sectionKind == .teachingProcess }))
    }

    @Test func readinessTreatsAnsweredAndSkippedItemsAsResolved() {
        let items = [
            EduLessonMissingInfoItem(
                id: "design",
                sectionKind: .designRationale,
                sectionTitle: "指导思想/设计理念",
                title: "补设计理念",
                question: "请补设计理念。",
                placeholder: "填写这里",
                suggestedAnswer: "",
                priority: .core
            ),
            EduLessonMissingInfoItem(
                id: "reflection",
                sectionKind: .reflection,
                sectionTitle: "教学反思",
                title: "补反思",
                question: "请补反思。",
                placeholder: "填写这里",
                suggestedAnswer: "",
                priority: .supportive
            )
        ]

        let readiness = EduLessonMaterializationAnalyzer.readiness(
            items: items,
            answersByID: ["design": "以目标导向组织活动与评价。"],
            skippedItemIDs: ["reflection"]
        )

        #expect(readiness.isReady)
        #expect(readiness.resolvedItems == 2)
        #expect(readiness.unresolvedItemIDs.isEmpty)
    }

    @Test func canvasRecommendationStartsWithKnowledgeBackboneOnEmptyGraph() throws {
        let file = makeWorkspaceFile(
            data: try makeEmptyGraphData(),
            goalsText: "学生能够理解风暴叙事\n学生能够分析作者态度变化"
        )

        let recommendations = EduCanvasRecommendationEngine.recommendations(for: file, limit: 5)

        #expect(recommendations.first?.id == "knowledge-skeleton")
        #expect(!recommendations.contains(where: { $0.id == "evaluation-alignment" }))
        #expect(!recommendations.contains(where: { $0.id == "scaffolding-boost" }))
    }

    @Test func canvasRecommendationAddsEvaluationWhenMissing() throws {
        let file = makeWorkspaceFile(
            data: try makeKnowledgeToolkitGraphData(),
            goalsText: "学生能够概括文章内容\n学生能够说明作者态度变化"
        )

        let recommendations = EduCanvasRecommendationEngine.recommendations(for: file, limit: 6)

        #expect(recommendations.contains(where: { $0.id == "evaluation-alignment" }))
    }

    @Test func canvasRecommendationUsesToolkitRolesForDiversification() throws {
        let file = makeWorkspaceFile(
            data: try makeRegulationOnlyGraphData(),
            goalsText: "学生能够形成论点\n学生能够根据反馈修改表达"
        )

        let recommendations = EduCanvasRecommendationEngine.recommendations(for: file, limit: 6)
        let prompt = recommendations.first(where: { $0.id == "method-diversification" })?.suggestedPrompt ?? ""

        #expect(
            prompt.contains("表达")
                || prompt.contains("协商")
                || prompt.contains("汇报")
                || prompt.localizedCaseInsensitiveContains("communication")
                || prompt.localizedCaseInsensitiveContains("report")
                || prompt.localizedCaseInsensitiveContains("reflection")
                || prompt.localizedCaseInsensitiveContains("transfer")
        )
    }

    @Test func canvasRecommendationAvoidsRedundantScaffoldingWhenAccessibleRampExists() throws {
        let file = makeWorkspaceFile(
            data: try makeAccessibleRampGraphData(),
            goalsText: "学生能够回忆并理解文本基础信息",
            studentSupportNotes: "部分学生需要慢启动"
        )

        let recommendations = EduCanvasRecommendationEngine.recommendations(for: file, limit: 6)

        #expect(!recommendations.contains(where: { $0.id == "scaffolding-boost" }))
    }

    @Test func materializationAnalyzerUsesSingleTextAnalysisFollowUpForGenericTemplate() throws {
        let template = try EduLessonTemplateParser.parse(
            text: """
            文本分析
            学习目标
            教学过程
            """,
            sourceName: "generic-analysis.txt"
        )
        let file = makeWorkspaceFile(
            data: try makeKnowledgeToolkitGraphData(),
            goalsText: "学生能够概括文章内容\n学生能够说明作者态度变化"
        )

        let items = EduLessonMaterializationAnalyzer.missingInfoItems(
            template: template,
            file: file,
            baselineMarkdown: "# Baseline"
        )

        #expect(items.contains(where: { $0.sectionKind == .textAnalysis && $0.autofillPolicy == .seed }))
        #expect(!items.contains(where: { $0.sectionKind == .textAnalysisWhat }))
    }

    @Test func materializationAnalyzerTreatsDisconnectedProcessAsCoreGap() throws {
        let template = try EduLessonTemplateParser.parse(
            text: "教学过程",
            sourceName: "process-only.txt"
        )
        let file = makeWorkspaceFile(
            data: try makeDisconnectedKnowledgeToolkitGraphData(),
            goalsText: "学生能够识别鸟类的主要特征"
        )

        let items = EduLessonMaterializationAnalyzer.missingInfoItems(
            template: template,
            file: file,
            baselineMarkdown: "# Baseline"
        )

        let processItem = items.first(where: { $0.sectionKind == .teachingProcess })
        #expect(processItem != nil)
        #expect(processItem?.priority == .core)
        #expect(processItem?.suggestedAnswer.isEmpty == true)
    }

    @Test func materializationAnalyzerSuppressesReflectionAndLearnerAnalysisWhenBaselineAlreadyHasThem() throws {
        let template = try EduLessonTemplateParser.parse(
            text: """
            学情分析
            教学反思
            """,
            sourceName: "baseline-covered.txt"
        )
        let file = makeWorkspaceFile(
            data: try makeKnowledgeToolkitGraphData(),
            goalsText: "学生能够概括文章内容\n学生能够说明作者态度变化",
            studentSupportNotes: "部分学生需要额外阅读支架"
        )

        let items = EduLessonMaterializationAnalyzer.missingInfoItems(
            template: template,
            file: file,
            baselineMarkdown: """
            ## 3. 学生与支持信息
            - 先备情况：需要阅读支架
            ## 7. 课后延伸与反思
            - 课后反思问题
            """
        )

        #expect(!items.contains(where: { $0.sectionKind == .learnerAnalysis }))
        #expect(!items.contains(where: { $0.sectionKind == .reflection }))
    }

    @Test func materializationAnalyzerAutofillsPriorKnowledgeWithoutSupportNotes() throws {
        let template = try EduLessonTemplateParser.parse(
            text: "已有知识",
            sourceName: "prior-knowledge.txt"
        )
        let file = makeWorkspaceFile(
            data: try makeKnowledgeToolkitGraphData(),
            goalsText: "学生能够概括文章内容",
            studentSupportNotes: ""
        )

        let items = EduLessonMaterializationAnalyzer.missingInfoItems(
            template: template,
            file: file,
            baselineMarkdown: "# Baseline"
        )

        #expect(items.first?.sectionKind == .priorKnowledge)
        #expect(items.first?.autofillPolicy == .resolvedDraft)
    }

    @Test func materializationSmokeCanHonorRealReferenceTemplateWhenLLMEnvIsPresent() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let baseURL = env["EDUNODE_LLM_BASE_URL"],
              let model = env["EDUNODE_LLM_MODEL"],
              let apiKey = env["EDUNODE_LLM_API_KEY"],
              !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let templatePath = env["EDUNODE_REFERENCE_TEMPLATE_PATH"]
            ?? "/Users/euan/Downloads/WWDC SSC26/教案示例/真实英语教案模版.pdf"
        guard FileManager.default.fileExists(atPath: templatePath) else {
            return
        }

        let templateURL = URL(fileURLWithPath: templatePath)
        let extractedText = try EduLessonTemplateDocumentLoader.extractText(from: templateURL)
        let reference = try EduLessonReferenceDocument.build(
            sourceName: templateURL.lastPathComponent,
            extractedMarkdown: extractedText
        )

        let file = makeWorkspaceFile(
            data: try makeKnowledgeToolkitGraphData(),
            goalsText: """
            学生能够梳理飓风事件的主要发展过程，并概括其对主人公生活产生的影响。
            学生能够分析作者在不同时间段的情绪变化及其原因。
            学生能够结合思维导图与角色扮演，表达作者在灾后重建中的积极生活态度。
            """,
            resourceConstraints: "PPT, Blackboard, Multimedia device",
            studentSupportNotes: "部分学生在文本细节整合和情绪变化分析上仍需要显性支架。"
        )
        let context = EduLessonPlanContext(file: file)
        let baselineMarkdown = EduLessonPlanExporter.markdown(
            context: context,
            graphData: file.data
        )
        let missingItems = EduLessonMaterializationAnalyzer.missingInfoItems(
            template: reference.templateDocument,
            file: file,
            baselineMarkdown: baselineMarkdown
        )
        let answersByID = resolvedSmokeAnswers(
            for: missingItems,
            file: file
        )

        let settings = EduAgentProviderSettings(
            providerName: "OpenAI-Compatible",
            baseURLString: baseURL,
            model: model,
            apiKey: apiKey,
            temperature: 0.2,
            maxTokens: 4800,
            timeoutSeconds: 180,
            additionalSystemPrompt: ""
        )

        let reply = try await EduOpenAICompatibleClient(settings: settings).complete(
            messages: EduLessonPlanMaterializationPromptBuilder.materializationMessages(
                settings: settings,
                file: file,
                baselineMarkdown: baselineMarkdown,
                template: reference.templateDocument,
                missingItems: missingItems,
                answersByID: answersByID,
                skippedItemIDs: [],
                supplementaryMaterial: "",
                userDirective: "请严格贴近参考模板的章节结构与写作风格生成教案。",
                referenceDocument: reference
            )
        )

        let structured = try EduAgentJSONParser.decodeFirstJSONObject(
            EduLessonMaterializationResponse.self,
            from: reply
        )
        let generated = structured.generatedMarkdown

        #expect(generated.contains("教师姓名"))
        #expect(generated.contains("学生年级"))
        #expect(generated.contains("指导思想/设计理念"))
        #expect(generated.contains("文本分析"))
        #expect(generated.contains("【what】"))
        #expect(generated.contains("【why】"))
        #expect(generated.contains("【how】"))
        #expect(generated.contains("学情分析"))
        #expect(generated.contains("已有知识"))
        #expect(generated.contains("未有知识"))
        #expect(generated.contains("（一）教学重点"))
        #expect(generated.contains("（二）教学难点"))
        #expect(generated.contains("教学过程（第一课时）"))
        #expect(generated.contains("学习活动、活动层次及时间"))
        #expect(generated.contains("设计意图"))
        #expect(generated.contains("效果评价"))
        #expect(generated.contains("作业"))
        #expect(generated.contains("Handout"))
        #expect(generated.contains("教学原文"))
        #expect(containsTitlesInOrder(
            generated,
            titles: [
                "指导思想/设计理念",
                "文本分析",
                "【what】",
                "【why】",
                "【how】",
                "学情分析",
                "学习目标",
                "教学重点和难点",
                "教学资源",
                "教学过程（第一课时）",
                "作业",
                "Handout",
                "教学原文"
            ]
        ))
    }

    @Test func canvasNormalizerRemapsBirdClassificationPracticeToToolkit() throws {
        let envelope = EduAgentGraphOperationEnvelope(
            assistantReply: "我会补一个鸟类分类练习节点。",
            operations: [
                EduAgentGraphOperation(
                    op: "add_node",
                    tempID: "new_bird_practice",
                    nodeRef: nil,
                    sourceNodeRef: nil,
                    targetNodeRef: nil,
                    nodeType: EduNodeType.knowledge,
                    title: "鸟类分类练习",
                    textValue: "学生根据喙、足、栖息地等特征完成分类。",
                    selectedOption: EduKnowledgeNode.defaultLevel,
                    selectedMethodID: nil,
                    textFieldValues: nil,
                    optionFieldValues: nil,
                    anchorNodeRef: nil,
                    placement: "right",
                    sourcePortName: nil,
                    targetPortName: nil,
                    positionX: nil,
                    positionY: nil
                )
            ]
        )

        let normalized = EduAgentGraphOperationNormalizer.normalize(
            envelope: envelope,
            userRequest: "新增鸟类分类练习"
        )

        let operation = try #require(normalized.operations.first)
        #expect(operation.nodeType == EduNodeType.toolkitPerceptionInquiry)
        #expect(operation.selectedMethodID == "field_observation")
        #expect(operation.optionFieldValues?["field_obs_task_structure"] == "classification")
    }

    @Test func graphMutationProducesToolkitNodeForBirdClassificationPractice() throws {
        let seedData = try makeEmptyGraphData()
        let rawEnvelope = EduAgentGraphOperationEnvelope(
            assistantReply: "我会补一个鸟类分类练习节点。",
            operations: [
                EduAgentGraphOperation(
                    op: "add_node",
                    tempID: "new_bird_practice",
                    nodeRef: nil,
                    sourceNodeRef: nil,
                    targetNodeRef: nil,
                    nodeType: EduNodeType.knowledge,
                    title: "鸟类分类练习",
                    textValue: "学生根据喙、足、栖息地等特征完成分类。",
                    selectedOption: EduKnowledgeNode.defaultLevel,
                    selectedMethodID: nil,
                    textFieldValues: nil,
                    optionFieldValues: nil,
                    anchorNodeRef: nil,
                    placement: "right",
                    sourcePortName: nil,
                    targetPortName: nil,
                    positionX: nil,
                    positionY: nil
                )
            ]
        )
        let normalized = EduAgentGraphOperationNormalizer.normalize(
            envelope: rawEnvelope,
            userRequest: "新增鸟类分类练习"
        )

        let result = try EduAgentGraphMutationEngine.apply(
            operations: normalized.operations,
            to: seedData
        )
        let file = makeWorkspaceFile(
            data: result.data,
            goalsText: "学生能够根据外形特征识别常见鸟类。"
        )
        let snapshot = EduAgentContextBuilder.workspaceSnapshot(file: file)
        let node = try #require(snapshot.nodes.first)

        #expect(node.nodeType == EduNodeType.toolkitPerceptionInquiry)
        #expect(node.title == "鸟类分类练习")
        #expect(node.selectedMethodID == "field_observation")
    }

    @Test func graphMutationSanitizesEvaluationQuantRulesWithoutExplodingIndicators() throws {
        let seedData = try makeEvaluationGraphData()
        let seedDocument = try decodeDocument(from: seedData)
        let evaluationNodeID = try #require(
            seedDocument.nodes.first(where: { $0.nodeType == EduNodeType.evaluation })?.id
        )

        let result = try EduAgentGraphMutationEngine.apply(
            operations: [
                EduAgentGraphOperation(
                    op: "update_node",
                    tempID: nil,
                    nodeRef: evaluationNodeID.uuidString,
                    sourceNodeRef: nil,
                    targetNodeRef: nil,
                    nodeType: nil,
                    title: "课堂评价",
                    textValue: nil,
                    selectedOption: nil,
                    selectedMethodID: nil,
                    textFieldValues: [
                        "evaluation_indicators": """
                        评分细则
                        课堂表现 | score | 2
                        90-100 | score | 3
                        作业提交 | completion | 1
                        优秀 | score | 2
                        """
                    ],
                    optionFieldValues: [
                        "evaluation_formula": "weighted_avg",
                        "evaluation_output_scale": "score100"
                    ],
                    anchorNodeRef: nil,
                    placement: nil,
                    sourcePortName: nil,
                    targetPortName: nil,
                    positionX: nil,
                    positionY: nil
                )
            ],
            to: seedData
        )

        let file = makeWorkspaceFile(
            data: result.data,
            goalsText: "学生能够用量化标准解释课堂达成。"
        )
        let snapshot = EduAgentContextBuilder.workspaceSnapshot(file: file)
        let evaluationNode = try #require(snapshot.nodes.first(where: { $0.nodeType == EduNodeType.evaluation }))
        let indicators = evaluationNode.textFields.first(where: { $0.id == "evaluation_indicators" })?.value ?? ""

        #expect(indicators.contains("课堂表现"))
        #expect(indicators.contains("作业提交"))
        #expect(!indicators.contains("评分细则"))
        #expect(!indicators.contains("90-100"))
        #expect(!indicators.contains("优秀"))
    }

    @Test func graphMutationCanResolveUpdateTargetFromPartialNodeTitle() throws {
        let seedData = try makeKnowledgeToolkitGraphData()

        let result = try EduAgentGraphMutationEngine.apply(
            operations: [
                EduAgentGraphOperation(
                    op: "update_node",
                    tempID: nil,
                    nodeRef: "Narrative",
                    sourceNodeRef: nil,
                    targetNodeRef: nil,
                    nodeType: nil,
                    title: "Storm Narrative",
                    textValue: "Students sequence the main events and mark the author's attitude shift with evidence.",
                    selectedOption: nil,
                    selectedMethodID: nil,
                    textFieldValues: nil,
                    optionFieldValues: nil,
                    anchorNodeRef: nil,
                    placement: nil,
                    sourcePortName: nil,
                    targetPortName: nil,
                    positionX: nil,
                    positionY: nil
                )
            ],
            to: seedData
        )

        let file = makeWorkspaceFile(
            data: result.data,
            goalsText: "学生能够梳理情节并说明作者态度变化。"
        )
        let snapshot = EduAgentContextBuilder.workspaceSnapshot(file: file)
        let knowledgeNode = try #require(snapshot.nodes.first(where: { $0.nodeType == EduNodeType.knowledge }))

        #expect(knowledgeNode.textValue.contains("attitude shift"))
    }

    @Test func followUpPlanningPromptUsesTargetItemAndPlanScaffold() throws {
        let reference = try EduLessonReferenceDocument.build(
            sourceName: "reference.md",
            extractedMarkdown: """
            指导思想/设计理念
            文本分析
            【what】
            【why】
            【how】
            学情分析
            已有知识：
            未有知识：
            学习目标
            教学过程
            教学反思
            """
        )
        let file = makeWorkspaceFile(
            data: try makeKnowledgeToolkitGraphData(),
            goalsText: "学生能够概括文章内容\n学生能够说明作者态度变化",
            studentSupportNotes: "部分学生需要额外阅读支架"
        )
        let items = EduLessonMaterializationAnalyzer.missingInfoItems(
            template: reference.templateDocument,
            file: file,
            baselineMarkdown: "# Baseline"
        )
        let targetItem = try #require(items.first(where: { $0.sectionKind == .textAnalysisWhy }))
        let settings = EduAgentProviderSettings()

        let planningMessages = EduLessonPlanMaterializationPromptBuilder.followUpPlanningMessages(
            settings: settings,
            file: file,
            baselineMarkdown: "# Baseline",
            referenceDocument: reference,
            missingItems: items,
            answersByID: [:],
            skippedItemIDs: [],
            targetItem: targetItem
        )

        #expect(planningMessages.count == 2)
        #expect(planningMessages[0].content.contains("plan-and-solve"))
        #expect(planningMessages[1].content.contains(targetItem.question))
        #expect(planningMessages[1].content.contains(reference.sourceName))
        #expect(planningMessages[1].content.contains(targetItem.sectionTitle))
    }
}

@MainActor
private func makeWorkspaceFile(
    data: Data,
    goalsText: String,
    resourceConstraints: String = "",
    studentSupportNotes: String = ""
) -> GNodeWorkspaceFile {
    GNodeWorkspaceFile(
        name: "Storm Lesson",
        data: data,
        gradeLevel: "grade 10-10",
        gradeMode: "grade",
        gradeMin: 10,
        gradeMax: 10,
        subject: "English",
        lessonDurationMinutes: 45,
        allowOvertime: false,
        periodRange: "Week 3",
        studentCount: 32,
        studentProfile: "priorScore=72, completion=78, supportNeed=4",
        studentPriorKnowledgeLevel: "72",
        studentMotivationLevel: "78",
        studentSupportNotes: studentSupportNotes,
        goalsText: goalsText,
        modelID: "fivee",
        teacherTeam: "lead=1, assistant=0",
        leadTeacherCount: 1,
        assistantTeacherCount: 0,
        teacherRolePlan: "Lead teacher facilitates discussion.",
        learningScenario: "",
        curriculumStandard: "",
        resourceConstraints: resourceConstraints,
        knowledgeToolkitMarkedDone: false,
        lessonPlanMarkedDone: false,
        evaluationMarkedDone: false,
        totalSessions: 1,
        lessonType: "singleLesson",
        teachingStyle: "inquiryDriven",
        formativeCheckIntensity: "medium",
        emphasizeInquiryExperiment: false,
        emphasizeExperienceReflection: false,
        requireStructuredFlow: true
    )
}

private func resolvedSmokeAnswers(
    for items: [EduLessonMissingInfoItem],
    file: GNodeWorkspaceFile
) -> [String: String] {
    items.reduce(into: [String: String]()) { partial, item in
        let suggested = item.suggestedAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !suggested.isEmpty {
            partial[item.id] = suggested
            return
        }

        switch item.sectionKind {
        case .learningObjectives:
            partial[item.id] = file.goalsText
        case .teachingProcess:
            partial[item.id] = "导入 5 分钟；细读与信息梳理 12 分钟；情绪变化分析与思维导图 15 分钟；角色扮演与课堂总结 10 分钟；即时评价与收束 3 分钟。"
        case .reflection:
            partial[item.id] = "关注学生是否真正把文本信息转化为态度理解；若讨论偏表层，可通过追加证据追问帮助学生回到文本。"
        default:
            partial[item.id] = item.placeholder.isEmpty ? "请结合当前课程图补齐本项。" : item.placeholder
        }
    }
}

private func containsTitlesInOrder(
    _ text: String,
    titles: [String]
) -> Bool {
    var searchStart = text.startIndex
    for title in titles {
        guard let range = text.range(of: title, range: searchStart..<text.endIndex) else {
            return false
        }
        searchStart = range.upperBound
    }
    return true
}

@MainActor
private func makeEmptyGraphData() throws -> Data {
    try encodeDocument(
        GNodeDocument(nodes: [], connections: [], canvasState: [])
    )
}

@MainActor
private func makeKnowledgeToolkitGraphData() throws -> Data {
    let knowledge = EduKnowledgeNode(
        name: "Storm Narrative",
        content: "Students identify the main events and emotional shifts.",
        level: EduKnowledgeNode.defaultLevel
    )
    let toolkit = EduToolkitNode(
        name: "Close Reading",
        category: .perceptionInquiry,
        selectedMethodID: "source_analysis",
        textFieldValues: [
            "source_materials": "Lesson text",
            "inquiry_question": "How does the author's attitude change?"
        ]
    )

    let sKnowledge = SerializableNode(from: knowledge, nodeType: EduNodeType.knowledge)
    let sToolkit = SerializableNode(from: toolkit, nodeType: EduNodeType.toolkitPerceptionInquiry)

    let connection = NodeConnection(
        sourceNode: sKnowledge.id,
        sourcePort: sKnowledge.outputPorts[0].id,
        targetNode: sToolkit.id,
        targetPort: sToolkit.inputPorts[0].id,
        dataType: sKnowledge.outputPorts[0].dataType
    )

    let document = GNodeDocument(
        nodes: [sKnowledge, sToolkit],
        connections: [connection],
        canvasState: [
            CanvasNodeState(nodeID: sKnowledge.id, position: CGPoint(x: 60, y: 80)),
            CanvasNodeState(nodeID: sToolkit.id, position: CGPoint(x: 340, y: 80))
        ]
    )
    return try encodeDocument(document)
}

@MainActor
private func makeDisconnectedKnowledgeToolkitGraphData() throws -> Data {
    let knowledge = EduKnowledgeNode(
        name: "Bird Features",
        content: "Students identify habitats and body features of common birds.",
        level: EduKnowledgeNode.defaultLevel
    )
    let toolkit = EduToolkitNode(
        name: "Observation",
        category: .perceptionInquiry,
        selectedMethodID: "field_observation",
        textFieldValues: [
            "observation_target": "Bird photos",
            "observation_focus": "Habitat and beak differences"
        ]
    )

    let sKnowledge = SerializableNode(from: knowledge, nodeType: EduNodeType.knowledge)
    let sToolkit = SerializableNode(from: toolkit, nodeType: EduNodeType.toolkitPerceptionInquiry)

    let document = GNodeDocument(
        nodes: [sKnowledge, sToolkit],
        connections: [],
        canvasState: [
            CanvasNodeState(nodeID: sKnowledge.id, position: CGPoint(x: 60, y: 80)),
            CanvasNodeState(nodeID: sToolkit.id, position: CGPoint(x: 340, y: 80))
        ]
    )
    return try encodeDocument(document)
}

@MainActor
private func makeRegulationOnlyGraphData() throws -> Data {
    let knowledge1 = EduKnowledgeNode(
        name: "Claim Framing",
        content: "Students frame a defensible reading claim.",
        level: EduKnowledgeNode.levelOptions[1]
    )
    let knowledge2 = EduKnowledgeNode(
        name: "Evidence Selection",
        content: "Students choose strong textual evidence.",
        level: EduKnowledgeNode.levelOptions[3]
    )
    let knowledge3 = EduKnowledgeNode(
        name: "Revision Strategy",
        content: "Students revise after peer feedback.",
        level: EduKnowledgeNode.levelOptions[3]
    )
    let toolkit = EduToolkitNode(
        name: "Reflection Protocol",
        category: .regulationMetacognition,
        selectedMethodID: "reflection_protocol"
    )

    let sK1 = SerializableNode(from: knowledge1, nodeType: EduNodeType.knowledge)
    let sK2 = SerializableNode(from: knowledge2, nodeType: EduNodeType.knowledge)
    let sK3 = SerializableNode(from: knowledge3, nodeType: EduNodeType.knowledge)
    let sToolkit = SerializableNode(from: toolkit, nodeType: EduNodeType.toolkitRegulationMetacognition)

    let c1 = NodeConnection(
        sourceNode: sK1.id,
        sourcePort: sK1.outputPorts[0].id,
        targetNode: sToolkit.id,
        targetPort: sToolkit.inputPorts[0].id,
        dataType: sK1.outputPorts[0].dataType
    )
    let c2 = NodeConnection(
        sourceNode: sToolkit.id,
        sourcePort: sToolkit.outputPorts[0].id,
        targetNode: sK2.id,
        targetPort: sK2.inputPorts[0].id,
        dataType: sToolkit.outputPorts[0].dataType
    )

    let document = GNodeDocument(
        nodes: [sK1, sK2, sK3, sToolkit],
        connections: [c1, c2],
        canvasState: [
            CanvasNodeState(nodeID: sK1.id, position: CGPoint(x: 60, y: 80)),
            CanvasNodeState(nodeID: sToolkit.id, position: CGPoint(x: 340, y: 80)),
            CanvasNodeState(nodeID: sK2.id, position: CGPoint(x: 620, y: 80)),
            CanvasNodeState(nodeID: sK3.id, position: CGPoint(x: 620, y: 260))
        ]
    )
    return try encodeDocument(document)
}

@MainActor
private func makeAccessibleRampGraphData() throws -> Data {
    let knowledge1 = EduKnowledgeNode(
        name: "Topic Entry",
        content: "Students recall familiar storm vocabulary.",
        level: EduKnowledgeNode.levelOptions[0]
    )
    let knowledge2 = EduKnowledgeNode(
        name: "Core Meaning",
        content: "Students understand the core conflict in the text.",
        level: EduKnowledgeNode.levelOptions[1]
    )
    let toolkit = EduToolkitNode(
        name: "Context Hook",
        category: .perceptionInquiry,
        selectedMethodID: "context_hook"
    )

    let sK1 = SerializableNode(from: knowledge1, nodeType: EduNodeType.knowledge)
    let sK2 = SerializableNode(from: knowledge2, nodeType: EduNodeType.knowledge)
    let sToolkit = SerializableNode(from: toolkit, nodeType: EduNodeType.toolkitPerceptionInquiry)

    let c1 = NodeConnection(
        sourceNode: sK1.id,
        sourcePort: sK1.outputPorts[0].id,
        targetNode: sToolkit.id,
        targetPort: sToolkit.inputPorts[0].id,
        dataType: sK1.outputPorts[0].dataType
    )
    let c2 = NodeConnection(
        sourceNode: sToolkit.id,
        sourcePort: sToolkit.outputPorts[0].id,
        targetNode: sK2.id,
        targetPort: sK2.inputPorts[0].id,
        dataType: sToolkit.outputPorts[0].dataType
    )

    let document = GNodeDocument(
        nodes: [sK1, sK2, sToolkit],
        connections: [c1, c2],
        canvasState: [
            CanvasNodeState(nodeID: sK1.id, position: CGPoint(x: 60, y: 80)),
            CanvasNodeState(nodeID: sToolkit.id, position: CGPoint(x: 340, y: 80)),
            CanvasNodeState(nodeID: sK2.id, position: CGPoint(x: 620, y: 80))
        ]
    )
    return try encodeDocument(document)
}

@MainActor
private func makeEvaluationGraphData() throws -> Data {
    let knowledge = EduKnowledgeNode(
        name: "Bird Features",
        content: "Students identify habitat, beak, and movement patterns of common birds.",
        level: EduKnowledgeNode.levelOptions[1]
    )
    let evaluation = EduEvaluationNode(
        name: "课堂评价",
        textFieldValues: [
            "evaluation_indicators": """
            课堂表现 | score
            作业提交 | completion
            """
        ],
        optionFieldValues: [
            "evaluation_formula": "average",
            "evaluation_output_scale": "score100"
        ]
    )

    let sKnowledge = SerializableNode(from: knowledge, nodeType: EduNodeType.knowledge)
    let sEvaluation = SerializableNode(from: evaluation, nodeType: EduNodeType.evaluation)

    let connection = NodeConnection(
        sourceNode: sKnowledge.id,
        sourcePort: sKnowledge.outputPorts[0].id,
        targetNode: sEvaluation.id,
        targetPort: sEvaluation.inputPorts[0].id,
        dataType: sKnowledge.outputPorts[0].dataType
    )

    let document = GNodeDocument(
        nodes: [sKnowledge, sEvaluation],
        connections: [connection],
        canvasState: [
            CanvasNodeState(nodeID: sKnowledge.id, position: CGPoint(x: 80, y: 120)),
            CanvasNodeState(nodeID: sEvaluation.id, position: CGPoint(x: 380, y: 120))
        ]
    )
    return try encodeDocument(document)
}
