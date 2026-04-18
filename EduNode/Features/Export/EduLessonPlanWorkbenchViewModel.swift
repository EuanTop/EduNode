import Foundation
import Combine

struct EduLessonPlanReferenceAttachment: Identifiable, Hashable {
    let id: UUID
    let fileName: String
    let data: Data

    init(
        id: UUID = UUID(),
        fileName: String,
        data: Data
    ) {
        self.id = id
        self.fileName = fileName
        self.data = data
    }
}

struct EduLessonFollowUpSuggestion: Equatable {
    let planningSummary: String
    let suggestedAnswer: String
}

enum EduLessonFollowUpSuggestionStatus: Equatable {
    case unavailable(String)
    case loading
    case ready(EduLessonFollowUpSuggestion)
    case failed(String)
}

@MainActor
final class EduLessonPlanWorkbenchViewModel: ObservableObject {
    let file: GNodeWorkspaceFile
    let baseFileName: String
    let baselineMarkdown: String
    let referenceAttachment: EduLessonPlanReferenceAttachment?

    @Published var referenceDocument: EduLessonReferenceDocument?
    @Published var missingItems: [EduLessonMissingInfoItem] = []
    @Published var answersByID: [String: String] = [:]
    @Published var skippedItemIDs: Set<String> = []
    @Published var focusedMissingItemID: String?
    @Published var currentAnswerDraft = ""
    @Published var followUpSuggestionStatusByID: [String: EduLessonFollowUpSuggestionStatus] = [:]
    @Published var conversation: [EduAgentConversationMessage] = []
    @Published var userInput = ""
    @Published var generatedMarkdown: String?
    @Published var isPreparingReference = false
    @Published var isRunning = false
    @Published var lastError: String?
    @Published var showingSettings = false

    private var didBootstrap = false

    init(
        file: GNodeWorkspaceFile,
        baseFileName: String,
        baselineMarkdown: String,
        referenceAttachment: EduLessonPlanReferenceAttachment?
    ) {
        self.file = file
        self.baseFileName = baseFileName
        self.baselineMarkdown = baselineMarkdown
        self.referenceAttachment = referenceAttachment
    }

    var isChinese: Bool {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
    }

    var previewMarkdown: String {
        let generated = generatedMarkdown?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let candidate = generated.isEmpty ? baselineMarkdown : generated
        guard !generated.isEmpty, let referenceDocument else {
            return candidate
        }
        return EduLessonTemplateStructuralNormalizer.normalize(
            markdown: candidate,
            referenceDocument: referenceDocument
        )
    }

    var hasReferenceFlow: Bool {
        referenceAttachment != nil
    }

    var readiness: EduLessonGenerationReadiness {
        guard hasReferenceFlow else {
            return EduLessonGenerationReadiness(
                totalItems: 0,
                resolvedItems: 0,
                unresolvedItemIDs: []
            )
        }
        return EduLessonMaterializationAnalyzer.readiness(
            items: missingItems,
            answersByID: answersByID,
            skippedItemIDs: skippedItemIDs
        )
    }

    var unresolvedItems: [EduLessonMissingInfoItem] {
        missingItems.filter { !isResolved($0) }
    }

    var activeFollowUpItem: EduLessonMissingInfoItem? {
        if let focusedMissingItemID,
           let item = missingItems.first(where: { $0.id == focusedMissingItemID }) {
            return item
        }
        return unresolvedItems.first
    }

    var readinessProgress: Double {
        guard readiness.totalItems > 0 else {
            return referenceDocument == nil && hasReferenceFlow ? 0 : 1
        }
        return Double(readiness.resolvedItems) / Double(readiness.totalItems)
    }

    var canGenerateReferenceDraft: Bool {
        referenceDocument != nil && readiness.isReady
    }

    var unresolvedCoreCount: Int {
        unresolvedItems.filter { $0.priority == .core }.count
    }

    var unresolvedSupportiveCount: Int {
        unresolvedItems.filter { $0.priority == .supportive }.count
    }

    var actionButtonTitle: String {
        if referenceDocument != nil && generatedMarkdown == nil {
            return isChinese ? "生成教案" : "Generate Lesson Plan"
        }
        return isChinese ? "优化教案" : "Refine Lesson Plan"
    }

    var composerPlaceholder: String {
        if isPreparingReference {
            return isChinese
                ? "正在解析参考教案，请稍候。"
                : "Preparing the reference lesson plan. Please wait."
        }
        if referenceDocument != nil && generatedMarkdown == nil {
            return isChinese
                ? "可选：补充生成偏好，例如更强调支架、分层评价或活动节奏。"
                : "Optional: add generation preferences such as stronger scaffolding, differentiated assessment, or pacing."
        }
        return isChinese
            ? "例如：把教学过程压缩为 40 分钟，并加强对低先备学生的支持。"
            : "For example: tighten the lesson to 40 minutes and strengthen support for learners with lower prior knowledge."
    }

    var composerFootnote: String {
        if referenceDocument != nil && generatedMarkdown == nil {
            if !readiness.isReady {
                return isChinese
                    ? "先完成模板信息补问，再正式生成教案。"
                    : "Resolve the template follow-up items before generating the lesson plan."
            }
            return isChinese
                ? "参考教案结构已准备好，现在可以正式生成。"
                : "The reference lesson-plan structure is ready. You can generate now."
        }
        if generatedMarkdown == nil {
            return isChinese
                ? "当前展示的是基于节点图的基线教案，可继续通过右侧对话优化。"
                : "You are viewing the graph-grounded baseline lesson plan and can refine it from the right panel."
        }
        return isChinese
            ? "当前预览会随 Agent 改写实时更新。"
            : "The preview updates live as the agent revises the lesson plan."
    }

    func bootstrapIfNeeded() {
        guard !didBootstrap else { return }
        didBootstrap = true

        if let referenceAttachment {
            conversation = [
                .init(
                    role: .assistant,
                    content: isChinese
                        ? "已进入教案工作台。系统会先学习参考教案的结构、内容组织与文风，再结合当前节点图补足缺失信息并生成教案。"
                        : "Entered the lesson-plan workbench. The system will first learn the reference lesson plan's structure, content organization, and tone, then resolve the remaining lesson details from the graph and generate the draft."
                )
            ]
            Task {
                await prepareReferenceFlow(using: referenceAttachment)
            }
        } else {
            conversation = [
                .init(
                    role: .assistant,
                    content: isChinese
                        ? "当前未附加参考教案，预览已先显示基于节点图导出的基线教案。你可以直接在右侧要求 Agent 优化内容、节奏与评价表达。"
                        : "No reference lesson plan was attached. The preview is showing the graph-grounded baseline draft, and you can refine its content, pacing, or assessment wording from the right panel."
                )
            ]
        }
    }

    func reloadSettingsFromStore() {
        lastError = nil
        followUpSuggestionStatusByID = [:]
        if let activeFollowUpItem {
            Task {
                await prepareFollowUpSuggestionIfNeeded(for: activeFollowUpItem, force: true)
            }
        }
    }

    func beginEditing(_ item: EduLessonMissingInfoItem) {
        let existingAnswer = answersByID[item.id] ?? ""
        focusedMissingItemID = item.id
        answersByID.removeValue(forKey: item.id)
        skippedItemIDs.remove(item.id)
        currentAnswerDraft = existingAnswer
    }

    func saveAnswer(for item: EduLessonMissingInfoItem) {
        let trimmed = currentAnswerDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        invalidateGeneratedDraftIfNeeded()
        answersByID[item.id] = trimmed
        skippedItemIDs.remove(item.id)
        followUpSuggestionStatusByID = [:]
        focusedMissingItemID = nil
        currentAnswerDraft = ""

        if let next = unresolvedItems.first {
            focusedMissingItemID = next.id
        } else {
            conversation.append(
                .init(
                    role: .assistant,
                    content: isChinese
                        ? "模板缺失信息已经补齐，可以生成正式教案了。"
                        : "The template follow-up items have now been resolved. The lesson plan is ready to generate."
                )
            )
        }
    }

    func skip(_ item: EduLessonMissingInfoItem) {
        invalidateGeneratedDraftIfNeeded()
        answersByID.removeValue(forKey: item.id)
        skippedItemIDs.insert(item.id)
        followUpSuggestionStatusByID = [:]
        focusedMissingItemID = nil
        currentAnswerDraft = ""

        if let next = unresolvedItems.first {
            focusedMissingItemID = next.id
        } else {
            conversation.append(
                .init(
                    role: .assistant,
                    content: isChinese
                        ? "剩余模板项已处理完毕。若有跳过项，生成时只会采用中性占位而不会杜撰。"
                        : "The remaining template items are now handled. Skipped items will use neutral placeholders rather than invented facts."
                )
            )
        }
    }

    func send() async {
        let trimmedInput = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty || (referenceDocument != nil && generatedMarkdown == nil) else {
            return
        }

        let settings = EduAgentSettingsStore.load()
        guard settings.isConfigured else {
            lastError = isChinese ? "请先配置 LLM 模型。" : "Configure the LLM first."
            return
        }

        if referenceDocument != nil && generatedMarkdown == nil {
            guard readiness.isReady else {
                lastError = isChinese ? "还有未处理的模板补问项。" : "Some template follow-up items are still unresolved."
                return
            }
            await generateReferenceGroundedDraft(
                settings: settings,
                directive: trimmedInput
            )
            return
        }

        guard !trimmedInput.isEmpty else { return }
        await reviseCurrentDraft(
            settings: settings,
            request: trimmedInput
        )
    }

    private func prepareReferenceFlow(
        using attachment: EduLessonPlanReferenceAttachment
    ) async {
        isPreparingReference = true
        lastError = nil

        do {
            let parsed = try await EduMinerUClient().parseReferencePDF(
                data: attachment.data,
                fileName: attachment.fileName
            )
            let referenceDocument = try EduLessonReferenceDocument.build(
                sourceName: attachment.fileName,
                extractedMarkdown: parsed.markdown
            )
            self.referenceDocument = referenceDocument

            missingItems = EduLessonMaterializationAnalyzer.missingInfoItems(
                template: referenceDocument.templateDocument,
                file: file,
                baselineMarkdown: baselineMarkdown
            )
            let prefilledAnswers = missingItems.reduce(into: [String: String]()) { partial, item in
                guard item.autofillPolicy == .resolvedDraft else { return }
                let suggested = item.suggestedAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !suggested.isEmpty else { return }
                partial[item.id] = suggested
            }
            answersByID = prefilledAnswers
            skippedItemIDs = []
            focusedMissingItemID = unresolvedItems.first?.id
            followUpSuggestionStatusByID = [:]

            let summary = referenceImportSummary(
                referenceDocument: referenceDocument,
                prefilledCount: prefilledAnswers.count
            )
            conversation.append(.init(role: .assistant, content: summary))

            if readiness.isReady {
                let settings = EduAgentSettingsStore.load()
                if settings.isConfigured {
                    await generateReferenceGroundedDraft(
                        settings: settings,
                        directive: ""
                    )
                } else {
                    conversation.append(
                        .init(
                            role: .assistant,
                            content: isChinese
                                ? "参考教案已经解析完成；请先配置 LLM，再生成正式教案。"
                                : "The reference lesson plan is parsed. Configure the LLM to generate the final lesson plan."
                        )
                    )
                }
            }
        } catch {
            lastError = error.localizedDescription
            conversation.append(
                .init(
                    role: .assistant,
                    content: isChinese
                        ? "参考 PDF 解析失败，当前会保留基线教案预览。你也可以不使用参考文档，直接继续优化。"
                        : "Reference-PDF parsing failed, so the workbench will keep the baseline lesson-plan preview. You can also continue refining without a reference document."
                )
            )
        }

        isPreparingReference = false
    }

    private func generateReferenceGroundedDraft(
        settings: EduAgentProviderSettings,
        directive: String
    ) async {
        guard let referenceDocument else { return }
        isRunning = true
        lastError = nil

        do {
            let client = EduOpenAICompatibleClient(settings: settings)
            let reply = try await client.complete(
                messages: EduLessonPlanMaterializationPromptBuilder.materializationMessages(
                    settings: settings,
                    file: file,
                    baselineMarkdown: baselineMarkdown,
                    template: referenceDocument.templateDocument,
                    missingItems: missingItems,
                    answersByID: answersByID,
                    skippedItemIDs: skippedItemIDs,
                    supplementaryMaterial: "",
                    userDirective: directive,
                    referenceDocument: referenceDocument
                )
            )
            let structured = try EduAgentJSONParser.decodeFirstJSONObject(
                EduLessonMaterializationResponse.self,
                from: reply
            )
            generatedMarkdown = try await referenceAlignedMarkdownIfNeeded(
                structured.generatedMarkdown,
                settings: settings
            )
            conversation.append(.init(role: .assistant, content: structured.assistantReply))
            userInput = ""
        } catch {
            lastError = error.localizedDescription
        }

        isRunning = false
    }

    private func reviseCurrentDraft(
        settings: EduAgentProviderSettings,
        request: String
    ) async {
        isRunning = true
        lastError = nil

        let history = conversation
        conversation.append(.init(role: .user, content: request))
        userInput = ""

        do {
            let client = EduOpenAICompatibleClient(settings: settings)
            let reply = try await client.complete(
                messages: EduAgentPromptBuilder.lessonPlanRevisionMessages(
                    settings: settings,
                    file: file,
                    lessonPlanMarkdown: previewMarkdown,
                    conversation: history,
                    userRequest: request,
                    supplementaryMaterial: "",
                    referenceDocument: referenceDocument
                )
            )
            let structured = try EduAgentJSONParser.decodeFirstJSONObject(
                EduAgentLessonPlanRevisionResponse.self,
                from: reply
            )
            generatedMarkdown = try await referenceAlignedMarkdownIfNeeded(
                structured.revisedMarkdown,
                settings: settings
            )
            conversation.append(.init(role: .assistant, content: structured.assistantReply))
        } catch {
            lastError = error.localizedDescription
        }

        isRunning = false
    }

    private func referenceImportSummary(
        referenceDocument: EduLessonReferenceDocument,
        prefilledCount: Int
    ) -> String {
        let unresolvedCount = max(0, missingItems.count - prefilledCount)
        if isChinese {
            return """
            已解析参考教案“\(referenceDocument.sourceName)”，识别到 \(referenceDocument.styleProfile.sectionCount) 个章节结构。

            - 体例线索：\(referenceDocument.styleProfile.featureHints.joined(separator: "；"))
            - 自动补足：\(prefilledCount) 项
            - 待补问：\(unresolvedCount) 项
            """
        }
        return """
        Parsed reference lesson plan "\(referenceDocument.sourceName)" with \(referenceDocument.styleProfile.sectionCount) detected sections.

        - Style cues: \(referenceDocument.styleProfile.featureHints.joined(separator: "; "))
        - Auto-filled items: \(prefilledCount)
        - Follow-up items left: \(unresolvedCount)
        """
    }

    func followUpSuggestionStatus(for item: EduLessonMissingInfoItem) -> EduLessonFollowUpSuggestionStatus? {
        followUpSuggestionStatusByID[item.id]
    }

    func prepareFollowUpSuggestionIfNeeded(
        for item: EduLessonMissingInfoItem,
        force: Bool = false
    ) async {
        guard referenceDocument != nil else { return }
        guard !isResolved(item) else { return }

        let settings = EduAgentSettingsStore.load()
        guard settings.isConfigured else {
            followUpSuggestionStatusByID[item.id] = .unavailable(
                isChinese
                    ? "配置 LLM 后，这里会基于模板与当前节点图生成补齐建议。"
                    : "Configure the LLM to generate a template-aware follow-up suggestion here."
            )
            return
        }

        if !force, let existingStatus = followUpSuggestionStatusByID[item.id] {
            switch existingStatus {
            case .loading, .ready:
                return
            case .unavailable, .failed:
                break
            }
        }

        followUpSuggestionStatusByID[item.id] = .loading

        do {
            guard let referenceDocument else { return }
            let client = EduOpenAICompatibleClient(settings: settings)
            let planningReply = try await client.complete(
                messages: EduLessonPlanMaterializationPromptBuilder.followUpPlanningMessages(
                    settings: settings,
                    file: file,
                    baselineMarkdown: baselineMarkdown,
                    referenceDocument: referenceDocument,
                    missingItems: missingItems,
                    answersByID: answersByID,
                    skippedItemIDs: skippedItemIDs,
                    targetItem: item
                )
            )
            let planning = try EduAgentJSONParser.decodeFirstJSONObject(
                EduLessonFollowUpPlanningResponse.self,
                from: planningReply
            )

            let suggestionReply = try await client.complete(
                messages: EduLessonPlanMaterializationPromptBuilder.followUpSuggestionMessages(
                    settings: settings,
                    file: file,
                    baselineMarkdown: baselineMarkdown,
                    referenceDocument: referenceDocument,
                    targetItem: item,
                    planning: planning
                )
            )
            let suggestion = try EduAgentJSONParser.decodeFirstJSONObject(
                EduLessonFollowUpSuggestionResponse.self,
                from: suggestionReply
            )

            followUpSuggestionStatusByID[item.id] = .ready(
                EduLessonFollowUpSuggestion(
                    planningSummary: planning.planningSummary.trimmingCharacters(in: .whitespacesAndNewlines),
                    suggestedAnswer: suggestion.suggestedAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )
        } catch {
            followUpSuggestionStatusByID[item.id] = .failed(error.localizedDescription)
        }
    }

    private func invalidateGeneratedDraftIfNeeded() {
        guard generatedMarkdown != nil else { return }
        generatedMarkdown = nil
        conversation.append(
            .init(
                role: .assistant,
                content: isChinese
                    ? "模板补充信息已更新，之前的生成稿已清空，请重新生成。"
                    : "Structured template inputs changed, so the previous generated draft has been cleared. Generate again to refresh it."
            )
        )
    }

    private func isResolved(_ item: EduLessonMissingInfoItem) -> Bool {
        skippedItemIDs.contains(item.id) || !(answersByID[item.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty
    }

    private func referenceAlignedMarkdownIfNeeded(
        _ candidateMarkdown: String,
        settings: EduAgentProviderSettings
    ) async throws -> String {
        guard let referenceDocument else { return candidateMarkdown }

        let initialReport = EduLessonTemplateComplianceChecker.validate(
            markdown: candidateMarkdown,
            referenceDocument: referenceDocument
        )
        guard !initialReport.isCompliant else {
            return candidateMarkdown
        }

        let structurallyAligned = EduLessonTemplateStructuralNormalizer.normalize(
            markdown: candidateMarkdown,
            referenceDocument: referenceDocument
        )
        let structuralReport = EduLessonTemplateComplianceChecker.validate(
            markdown: structurallyAligned,
            referenceDocument: referenceDocument
        )
        if structuralReport.isCompliant {
            return structurallyAligned
        }

        do {
            let client = EduOpenAICompatibleClient(settings: settings)
            let repairReply = try await client.complete(
                messages: EduLessonPlanMaterializationPromptBuilder.repairMessages(
                    settings: settings,
                    file: file,
                    currentMarkdown: structurallyAligned,
                    referenceDocument: referenceDocument,
                    complianceReport: structuralReport
                )
            )
            let repaired = try EduAgentJSONParser.decodeFirstJSONObject(
                EduLessonMaterializationResponse.self,
                from: repairReply
            )
            return EduLessonTemplateStructuralNormalizer.normalize(
                markdown: repaired.generatedMarkdown,
                referenceDocument: referenceDocument
            )
        } catch {
            return structurallyAligned
        }
    }
}
