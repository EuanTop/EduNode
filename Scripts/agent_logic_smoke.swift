import Foundation
import Darwin

@main
struct AgentLogicSmoke {
    static func main() throws {
        var failures = 0

        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            if condition() {
                print("PASS | \(message)")
            } else {
                failures += 1
                print("FAIL | \(message)")
            }
        }

        let course = EduAgentCourseContext(
            subject: "English",
            goals: [
                "Students identify the main events in the storm narrative.",
                "Students explain how the author's attitude changes.",
                "Students justify their interpretation with textual evidence."
            ],
            modelFocus: "observable evidence",
            teachingStyle: "inquiryDriven",
            formativeCheckIntensity: "medium",
            emphasizeInquiryExperiment: false,
            emphasizeExperienceReflection: false,
            requireStructuredFlow: true,
            studentCount: 32,
            studentPriorKnowledgeScore: 58,
            studentMotivationScore: 74,
            studentSupportNotes: "Some students need sentence starters and slower task ramp-up.",
            resourceConstraints: "PPT, worksheet",
            lessonDurationMinutes: 45
        )

        let emptyGraph = EduAgentGraphContext(nodes: [], totalConnections: 0)
        let emptyRecommendations = EduCanvasRecommendationCoreEngine.recommendations(
            course: course,
            graph: emptyGraph,
            isChinese: true,
            limit: 5
        )
        print("RECS_EMPTY | \(emptyRecommendations.map(\.id).joined(separator: ","))")
        expect(emptyRecommendations.first?.id == "knowledge-skeleton", "empty canvas prioritizes knowledge backbone")
        expect(!emptyRecommendations.contains(where: { $0.id == "evaluation-alignment" }), "empty canvas does not rush into evaluation")
        expect(!emptyRecommendations.contains(where: { $0.id == "scaffolding-boost" }), "empty canvas folds low-floor support into the initial backbone step")

        let graphWithSingleMethod = EduAgentGraphContext(
            nodes: [
                EduAgentGraphNodeContext(
                    id: "k1",
                    nodeFamily: "knowledge",
                    title: "Storm Narrative",
                    textValue: "Students identify the sequence of events and emotional shifts.",
                    selectedOption: "understand",
                    selectedMethodID: nil,
                    incomingNodeIDs: [],
                    outgoingNodeIDs: ["t1"],
                    incomingTitles: [],
                    outgoingTitles: ["Close Reading"],
                    textFields: [],
                    optionFields: []
                ),
                EduAgentGraphNodeContext(
                    id: "k2",
                    nodeFamily: "knowledge",
                    title: "Author Attitude",
                    textValue: "Students infer how the author's feelings shift from fear to hope.",
                    selectedOption: "analyze",
                    selectedMethodID: nil,
                    incomingNodeIDs: [],
                    outgoingNodeIDs: [],
                    incomingTitles: [],
                    outgoingTitles: [],
                    textFields: [],
                    optionFields: []
                ),
                EduAgentGraphNodeContext(
                    id: "k3",
                    nodeFamily: "knowledge",
                    title: "Evidence Use",
                    textValue: "Students justify claims with details from the text.",
                    selectedOption: "analyze",
                    selectedMethodID: nil,
                    incomingNodeIDs: [],
                    outgoingNodeIDs: [],
                    incomingTitles: [],
                    outgoingTitles: [],
                    textFields: [],
                    optionFields: []
                ),
                EduAgentGraphNodeContext(
                    id: "t1",
                    nodeFamily: "toolkit",
                    title: "Close Reading",
                    textValue: "Students annotate the text in pairs.",
                    selectedOption: "",
                    selectedMethodID: "source_analysis",
                    incomingNodeIDs: ["k1"],
                    outgoingNodeIDs: [],
                    incomingTitles: ["Storm Narrative"],
                    outgoingTitles: [],
                    textFields: [],
                    optionFields: []
                )
            ],
            totalConnections: 1
        )
        let graphRecommendations = EduCanvasRecommendationCoreEngine.recommendations(
            course: course,
            graph: graphWithSingleMethod,
            isChinese: true,
            limit: 6
        )
        print("RECS_GRAPH | \(graphRecommendations.map(\.id).joined(separator: ","))")
        expect(graphRecommendations.contains(where: { $0.id == "evaluation-alignment" }), "graph without evaluation requests assessment loop")
        expect(graphRecommendations.contains(where: { $0.id == "method-diversification" }), "single-method graph requests second toolkit mode")
        expect(graphRecommendations.contains(where: { $0.id == "scaffolding-boost" }), "low-readiness context requests scaffolding")

        let graphWithDuplicatedMethods = EduAgentGraphContext(
            nodes: [
                EduAgentGraphNodeContext(
                    id: "dk1",
                    nodeFamily: "knowledge",
                    title: "Topic Entry",
                    textValue: "Students recall the setting and key vocabulary.",
                    selectedOption: "remember",
                    selectedMethodID: nil,
                    incomingNodeIDs: [],
                    outgoingNodeIDs: ["dt1"],
                    incomingTitles: [],
                    outgoingTitles: ["Close Reading 1"],
                    textFields: [],
                    optionFields: []
                ),
                EduAgentGraphNodeContext(
                    id: "dk2",
                    nodeFamily: "knowledge",
                    title: "Meaning Making",
                    textValue: "Students infer how the conflict develops.",
                    selectedOption: "understand",
                    selectedMethodID: nil,
                    incomingNodeIDs: ["dt1"],
                    outgoingNodeIDs: ["dt2"],
                    incomingTitles: ["Close Reading 1"],
                    outgoingTitles: ["Close Reading 2"],
                    textFields: [],
                    optionFields: []
                ),
                EduAgentGraphNodeContext(
                    id: "dk3",
                    nodeFamily: "knowledge",
                    title: "Evidence Claim",
                    textValue: "Students support claims with textual evidence.",
                    selectedOption: "analyze",
                    selectedMethodID: nil,
                    incomingNodeIDs: ["dt2"],
                    outgoingNodeIDs: [],
                    incomingTitles: ["Close Reading 2"],
                    outgoingTitles: [],
                    textFields: [],
                    optionFields: []
                ),
                EduAgentGraphNodeContext(
                    id: "dt1",
                    nodeFamily: "toolkit",
                    title: "Close Reading 1",
                    textValue: "Students annotate the opening paragraph.",
                    selectedOption: "",
                    selectedMethodID: "source_analysis",
                    incomingNodeIDs: ["dk1"],
                    outgoingNodeIDs: ["dk2"],
                    incomingTitles: ["Topic Entry"],
                    outgoingTitles: ["Meaning Making"],
                    textFields: [],
                    optionFields: []
                ),
                EduAgentGraphNodeContext(
                    id: "dt2",
                    nodeFamily: "toolkit",
                    title: "Close Reading 2",
                    textValue: "Students annotate the ending paragraph.",
                    selectedOption: "",
                    selectedMethodID: "source_analysis",
                    incomingNodeIDs: ["dk2"],
                    outgoingNodeIDs: ["dk3"],
                    incomingTitles: ["Meaning Making"],
                    outgoingTitles: ["Evidence Claim"],
                    textFields: [],
                    optionFields: []
                )
            ],
            totalConnections: 4
        )
        let duplicatedMethodRecommendations = EduCanvasRecommendationCoreEngine.recommendations(
            course: course,
            graph: graphWithDuplicatedMethods,
            isChinese: true,
            limit: 6
        )
        print("RECS_DUP_METHOD | \(duplicatedMethodRecommendations.map(\.id).joined(separator: ","))")
        expect(duplicatedMethodRecommendations.contains(where: { $0.id == "method-diversification" }), "duplicate toolkit methods still trigger diversification")

        let graphWithRegulationOnly = EduAgentGraphContext(
            nodes: [
                EduAgentGraphNodeContext(
                    id: "rk1",
                    nodeFamily: "knowledge",
                    title: "Claim Framing",
                    textValue: "Students frame a defensible reading claim.",
                    selectedOption: "understand",
                    selectedMethodID: nil,
                    incomingNodeIDs: [],
                    outgoingNodeIDs: ["rt1"],
                    incomingTitles: [],
                    outgoingTitles: ["Reflection Protocol"],
                    textFields: [],
                    optionFields: []
                ),
                EduAgentGraphNodeContext(
                    id: "rk2",
                    nodeFamily: "knowledge",
                    title: "Evidence Selection",
                    textValue: "Students select the strongest textual evidence.",
                    selectedOption: "analyze",
                    selectedMethodID: nil,
                    incomingNodeIDs: ["rt1"],
                    outgoingNodeIDs: [],
                    incomingTitles: ["Reflection Protocol"],
                    outgoingTitles: [],
                    textFields: [],
                    optionFields: []
                ),
                EduAgentGraphNodeContext(
                    id: "rk3",
                    nodeFamily: "knowledge",
                    title: "Revision Strategy",
                    textValue: "Students revise their response after feedback.",
                    selectedOption: "analyze",
                    selectedMethodID: nil,
                    incomingNodeIDs: [],
                    outgoingNodeIDs: [],
                    incomingTitles: [],
                    outgoingTitles: [],
                    textFields: [],
                    optionFields: []
                ),
                EduAgentGraphNodeContext(
                    id: "rt1",
                    nodeFamily: "toolkit",
                    title: "Reflection Protocol",
                    textValue: "Students review and revise their first draft.",
                    selectedOption: "",
                    selectedMethodID: "reflection_protocol",
                    incomingNodeIDs: ["rk1"],
                    outgoingNodeIDs: ["rk2"],
                    incomingTitles: ["Claim Framing"],
                    outgoingTitles: ["Evidence Selection"],
                    textFields: [],
                    optionFields: []
                )
            ],
            totalConnections: 2
        )
        let regulationOnlyRecommendations = EduCanvasRecommendationCoreEngine.recommendations(
            course: course,
            graph: graphWithRegulationOnly,
            isChinese: true,
            limit: 6
        )
        let regulationDiversificationPrompt = regulationOnlyRecommendations.first(where: { $0.id == "method-diversification" })?.suggestedPrompt ?? ""
        expect(regulationDiversificationPrompt.contains("表达") || regulationDiversificationPrompt.contains("协商") || regulationDiversificationPrompt.contains("汇报"), "regulation-only graph now asks for communication instead of repeating metacognition")

        let graphWithAccessibleRamp = EduAgentGraphContext(
            nodes: [
                EduAgentGraphNodeContext(
                    id: "ak1",
                    nodeFamily: "knowledge",
                    title: "Topic Entry",
                    textValue: "Students recall familiar storm vocabulary.",
                    selectedOption: "remember",
                    selectedMethodID: nil,
                    incomingNodeIDs: [],
                    outgoingNodeIDs: ["at1"],
                    incomingTitles: [],
                    outgoingTitles: ["Context Hook"],
                    textFields: [],
                    optionFields: []
                ),
                EduAgentGraphNodeContext(
                    id: "ak2",
                    nodeFamily: "knowledge",
                    title: "Core Meaning",
                    textValue: "Students understand the core conflict in the text.",
                    selectedOption: "understand",
                    selectedMethodID: nil,
                    incomingNodeIDs: ["at1"],
                    outgoingNodeIDs: [],
                    incomingTitles: ["Context Hook"],
                    outgoingTitles: [],
                    textFields: [],
                    optionFields: []
                ),
                EduAgentGraphNodeContext(
                    id: "at1",
                    nodeFamily: "toolkit",
                    title: "Context Hook",
                    textValue: "Students respond to a familiar weather photo prompt.",
                    selectedOption: "",
                    selectedMethodID: "context_hook",
                    incomingNodeIDs: ["ak1"],
                    outgoingNodeIDs: ["ak2"],
                    incomingTitles: ["Topic Entry"],
                    outgoingTitles: ["Core Meaning"],
                    textFields: [],
                    optionFields: []
                )
            ],
            totalConnections: 2
        )
        let accessibleRampRecommendations = EduCanvasRecommendationCoreEngine.recommendations(
            course: course,
            graph: graphWithAccessibleRamp,
            isChinese: true,
            limit: 6
        )
        expect(!accessibleRampRecommendations.contains(where: { $0.id == "scaffolding-boost" }), "existing accessible entry toolkit suppresses redundant scaffolding advice")

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
        教学过程（学习活动、活动层次及时间 / 设计意图 / 效果评价）
        教学反思
        """

        let template = try EduLessonTemplateParser.parse(
            text: templateText,
            sourceName: "smoke-template.txt"
        )
        print("STYLE_NOTES | \(template.schema.styleNotes.joined(separator: " | "))")
        expect(template.schema.sections.contains(where: { $0.kind == .textAnalysisWhat }), "template parser detects what section")
        expect(template.schema.styleNotes.contains(where: { $0.localizedCaseInsensitiveContains("time-annotated") }), "template parser detects timed process expectation")

        let realTemplateURL = URL(fileURLWithPath: "/Users/euan/Downloads/WWDC SSC26/教案示例/真实英语教案模版.pdf")
        if FileManager.default.fileExists(atPath: realTemplateURL.path) {
            let realTemplate = try EduLessonTemplateDocumentLoader.load(from: realTemplateURL)
            let realKinds = Set(realTemplate.schema.sections.map(\.kind))
            print("REAL_TEMPLATE | sections=\(realTemplate.schema.sections.count) | styles=\(realTemplate.schema.styleNotes.joined(separator: " | "))")
            expect(realKinds.contains(.designRationale), "real PDF template exposes design rationale section")
            expect(realKinds.contains(.teachingProcess), "real PDF template exposes teaching process section")
            expect(realKinds.contains(.textAnalysisWhat), "real PDF template exposes what-analysis section")
        } else {
            print("REAL_TEMPLATE | skipped because the reference PDF was not found")
        }

        let items = EduLessonMaterializationCoreAnalyzer.missingInfoItems(
            template: template,
            course: course,
            graph: graphWithSingleMethod,
            baselineMarkdown: "# Baseline\n## 教学过程\n导入\n活动\n总结",
            isChinese: true
        )

        for item in items {
            let preview = item.suggestedAnswer
                .replacingOccurrences(of: "\n", with: " ")
            print("ITEM | \(item.id) | \(item.autofillPolicy.rawValue) | \(preview.prefix(70))")
        }

        expect(items.contains(where: { $0.sectionKind == .designRationale && $0.autofillPolicy == .resolvedDraft }), "design rationale is reliably auto-filled")
        expect(items.contains(where: { $0.sectionKind == .textAnalysisWhat && $0.autofillPolicy == .seed }), "text analysis stays as teacher-confirmed seed draft")
        expect(items.contains(where: { $0.sectionKind == .teachingProcess && $0.autofillPolicy == .seed }), "timed process template triggers process detail follow-up")
        expect(items.contains(where: { $0.sectionKind == .reflection && !$0.suggestedAnswer.isEmpty }), "reflection receives a suggested draft")

        let genericAnalysisTemplate = try EduLessonTemplateParser.parse(
            text: """
            文本分析
            学习目标
            教学过程
            """,
            sourceName: "generic-analysis.txt"
        )
        let genericAnalysisItems = EduLessonMaterializationCoreAnalyzer.missingInfoItems(
            template: genericAnalysisTemplate,
            course: course,
            graph: graphWithSingleMethod,
            baselineMarkdown: "# Baseline\n## 教学过程\n导入\n活动\n总结",
            isChinese: true
        )
        expect(genericAnalysisItems.contains(where: { $0.sectionKind == .textAnalysis && $0.autofillPolicy == .seed }), "generic text-analysis template produces a single teacher-reviewed analysis item")

        let baselineReflectionItems = EduLessonMaterializationCoreAnalyzer.missingInfoItems(
            template: template,
            course: course,
            graph: graphWithSingleMethod,
            baselineMarkdown: """
            ## 3. 学生与支持信息
            - 先备情况：需要句型支架
            ## 7. 课后延伸与反思
            - 课后反思问题
            """,
            isChinese: true
        )
        expect(!baselineReflectionItems.contains(where: { $0.sectionKind == .reflection }), "baseline reflection section suppresses redundant reflection follow-up")
        expect(!baselineReflectionItems.contains(where: { $0.sectionKind == .learnerAnalysis }), "baseline learner-profile section suppresses redundant learner-analysis follow-up")

        let noSupportCourse = EduAgentCourseContext(
            subject: "English",
            goals: ["Students summarize the text."],
            modelFocus: "observable evidence",
            teachingStyle: "inquiryDriven",
            formativeCheckIntensity: "medium",
            emphasizeInquiryExperiment: false,
            emphasizeExperienceReflection: false,
            requireStructuredFlow: true,
            studentCount: 28,
            studentPriorKnowledgeScore: 76,
            studentMotivationScore: 80,
            studentSupportNotes: "",
            resourceConstraints: "",
            lessonDurationMinutes: 40
        )
        let priorKnowledgeTemplate = try EduLessonTemplateParser.parse(
            text: "已有知识",
            sourceName: "prior-knowledge.txt"
        )
        let priorKnowledgeItems = EduLessonMaterializationCoreAnalyzer.missingInfoItems(
            template: priorKnowledgeTemplate,
            course: noSupportCourse,
            graph: graphWithSingleMethod,
            baselineMarkdown: "# Baseline",
            isChinese: true
        )
        expect(priorKnowledgeItems.first?.autofillPolicy == .resolvedDraft, "prior knowledge now auto-fills even when support notes are absent")

        let disconnectedGraph = EduAgentGraphContext(
            nodes: [
                EduAgentGraphNodeContext(
                    id: "sk1",
                    nodeFamily: "knowledge",
                    title: "Bird Features",
                    textValue: "Students identify bird habitats and body features.",
                    selectedOption: "understand",
                    selectedMethodID: nil,
                    incomingNodeIDs: [],
                    outgoingNodeIDs: [],
                    incomingTitles: [],
                    outgoingTitles: [],
                    textFields: [],
                    optionFields: []
                ),
                EduAgentGraphNodeContext(
                    id: "st1",
                    nodeFamily: "toolkit",
                    title: "Observation",
                    textValue: "Students observe local bird photos.",
                    selectedOption: "",
                    selectedMethodID: "guided_observation",
                    incomingNodeIDs: [],
                    outgoingNodeIDs: [],
                    incomingTitles: [],
                    outgoingTitles: [],
                    textFields: [],
                    optionFields: []
                )
            ],
            totalConnections: 0
        )
        let processOnlyTemplate = try EduLessonTemplateParser.parse(
            text: "教学过程",
            sourceName: "process-only.txt"
        )
        let disconnectedItems = EduLessonMaterializationCoreAnalyzer.missingInfoItems(
            template: processOnlyTemplate,
            course: course,
            graph: disconnectedGraph,
            baselineMarkdown: "# Baseline",
            isChinese: true
        )
        let disconnectedProcessItem = disconnectedItems.first(where: { $0.sectionKind == .teachingProcess })
        expect(disconnectedProcessItem != nil, "disconnected graph still surfaces a teaching-process follow-up")
        expect(disconnectedProcessItem?.priority == .core, "disconnected graph upgrades teaching-process follow-up to core")
        expect(disconnectedProcessItem?.suggestedAnswer.isEmpty == true, "disconnected graph does not pretend a coherent process already exists")

        let prefilledAnswers = Dictionary(
            uniqueKeysWithValues: items.compactMap { item -> (String, String)? in
                guard item.autofillPolicy == .resolvedDraft else { return nil }
                let trimmed = item.suggestedAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                return (item.id, trimmed)
            }
        )
        let readinessBeforeTeacherInput = EduLessonMaterializationCoreAnalyzer.readiness(
            items: items,
            answersByID: prefilledAnswers,
            skippedItemIDs: []
        )
        print("READINESS_BEFORE | resolved=\(readinessBeforeTeacherInput.resolvedItems) total=\(readinessBeforeTeacherInput.totalItems) unresolved=\(readinessBeforeTeacherInput.unresolvedItemIDs.joined(separator: ","))")
        expect(!readinessBeforeTeacherInput.isReady, "seed-only items still require teacher review")

        let teacherCompletedAnswers = prefilledAnswers.merging(
            Dictionary(
                uniqueKeysWithValues: items.compactMap { item -> (String, String)? in
                    guard item.autofillPolicy == .seed else { return nil }
                    let trimmed = item.suggestedAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return nil }
                    return (item.id, trimmed)
                }
            ),
            uniquingKeysWith: { _, new in new }
        )
        let readinessAfterTeacherReview = EduLessonMaterializationCoreAnalyzer.readiness(
            items: items,
            answersByID: teacherCompletedAnswers,
            skippedItemIDs: []
        )
        print("READINESS_AFTER | resolved=\(readinessAfterTeacherReview.resolvedItems) total=\(readinessAfterTeacherReview.totalItems)")
        expect(readinessAfterTeacherReview.isReady, "reviewed seed drafts produce ready-to-generate state")

        if failures > 0 {
            fputs("Agent logic smoke test failed with \(failures) issue(s).\n", stderr)
            exit(1)
        }

        print("ALL_PASS | agent logic smoke validation succeeded")
    }
}
