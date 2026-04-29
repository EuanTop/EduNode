import Foundation
import Combine

struct EduLessonAgentTraceEvent: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let stage: String
    let detail: String
}

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
    @Published var debugTraceEvents: [EduLessonAgentTraceEvent] = []

    private var didBootstrap = false
    private var persistenceCancellables: Set<AnyCancellable> = []

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

        if let snapshot = EduAgentConversationPersistence.loadLessonPlanSnapshot(fileID: file.id) {
            self.conversation = snapshot.conversation
            self.generatedMarkdown = snapshot.generatedMarkdown
        }

        $conversation
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.persistConversationSnapshot()
                }
            }
            .store(in: &persistenceCancellables)

        $generatedMarkdown
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.persistConversationSnapshot()
                }
            }
            .store(in: &persistenceCancellables)
    }

    var isChinese: Bool {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
    }

    private var backendLLMService: EduBackendLLMService? {
        EduBackendLLMService()
    }

    private var hasBackendSession: Bool {
        EduBackendSessionStore.load() != nil
    }

    private var backendPromptSettings: EduAgentProviderSettings {
        let cachedModel = EduBackendRuntimeStatusStore.load()?.activeModel
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return EduAgentProviderSettings(
            providerName: "EduNode Backend",
            baseURLString: EduBackendServiceConfig.loadOptional()?.baseURL.absoluteString ?? "backend",
            model: cachedModel.isEmpty ? "backend-model" : cachedModel,
            apiKey: "session",
            temperature: 0.35,
            maxTokens: 3200,
            timeoutSeconds: 120,
            additionalSystemPrompt: ""
        )
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

    var debugTraceText: String {
        let formatter = Self.traceDateFormatter
        var lines: [String] = []
        lines.append("[EduNode][LessonPlanWorkbenchTrace]")
        lines.append("file=\(file.name)")
        lines.append("hasReference=\(hasReferenceFlow)")
        lines.append("ready=\(readiness.resolvedItems)/\(readiness.totalItems)")
        lines.append("running=\(isRunning)")
        lines.append("preparingReference=\(isPreparingReference)")
        lines.append("lastError=\(lastError ?? "")")
        for event in debugTraceEvents {
            lines.append("\(formatter.string(from: event.timestamp)) | \(event.stage) | \(event.detail)")
        }
        return lines.joined(separator: "\n")
    }

    private static let traceDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    func bootstrapIfNeeded() {
        guard !didBootstrap else { return }
        didBootstrap = true
        appendTrace(stage: "bootstrap", detail: "begin hasReference=\(referenceAttachment != nil)")

        if !conversation.isEmpty {
            appendTrace(stage: "bootstrap", detail: "restored local conversation messages=\(conversation.count)")
            if let referenceAttachment,
               referenceDocument == nil,
               generatedMarkdown == nil {
                Task {
                    await prepareReferenceFlow(using: referenceAttachment)
                }
            }
            return
        }

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

    private func persistConversationSnapshot() {
        EduAgentConversationPersistence.saveLessonPlanSnapshot(
            .init(
                conversation: conversation,
                generatedMarkdown: generatedMarkdown
            ),
            fileID: file.id
        )
    }

    func reloadSettingsFromStore() {
        appendTrace(stage: "settings", detail: "reload from store")
        lastError = nil
        followUpSuggestionStatusByID = [:]
        if let referenceAttachment,
           referenceDocument == nil,
           !isPreparingReference {
            Task {
                await prepareReferenceFlow(using: referenceAttachment)
            }
            return
        }
        if let activeFollowUpItem {
            Task {
                await prepareFollowUpSuggestionIfNeeded(for: activeFollowUpItem, force: true)
            }
        }
    }

    func beginEditing(_ item: EduLessonMissingInfoItem) {
        appendTrace(stage: "followup", detail: "begin editing item=\(item.id)")
        let existingAnswer = answersByID[item.id] ?? ""
        focusedMissingItemID = item.id
        answersByID.removeValue(forKey: item.id)
        skippedItemIDs.remove(item.id)
        currentAnswerDraft = existingAnswer
    }

    func saveAnswer(for item: EduLessonMissingInfoItem) {
        let trimmed = currentAnswerDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        appendTrace(stage: "followup", detail: "save answer item=\(item.id) chars=\(trimmed.count)")
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
        appendTrace(stage: "followup", detail: "skip item=\(item.id)")
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

        let settings = backendPromptSettings
        guard let service = backendLLMService, hasBackendSession else {
            appendTrace(stage: "send", detail: "blocked: backend unavailable")
            lastError = isChinese ? "请先登录 EduNode 账户后再使用教案生成。" : "Sign in to your EduNode account before generating lesson plans."
            return
        }

        appendTrace(
            stage: "send",
            detail: "start mode=\(referenceDocument != nil && generatedMarkdown == nil ? "generate" : "revise") inputChars=\(trimmedInput.count)"
        )

        if referenceDocument != nil && generatedMarkdown == nil {
            guard readiness.isReady else {
                appendTrace(stage: "send", detail: "blocked: unresolved follow-up items")
                lastError = isChinese ? "还有未处理的模板补问项。" : "Some template follow-up items are still unresolved."
                return
            }
            await generateReferenceGroundedDraft(
                service: service,
                settings: settings,
                directive: trimmedInput
            )
            return
        }

        guard !trimmedInput.isEmpty else { return }
        await reviseCurrentDraft(
            service: service,
            settings: settings,
            request: trimmedInput
        )
    }

    private func prepareReferenceFlow(
        using attachment: EduLessonPlanReferenceAttachment
    ) async {
        isPreparingReference = true
        lastError = nil
        appendTrace(stage: "reference", detail: "parse start file=\(attachment.fileName) bytes=\(attachment.data.count)")

        guard hasBackendSession else {
            isPreparingReference = false
            lastError = isChinese ? "请先登录 EduNode 账户，再解析参考教案。" : "Sign in to your EduNode account before parsing the reference lesson plan."
            conversation.append(
                .init(
                    role: .assistant,
                    content: isChinese
                        ? "当前已附加参考教案。登录 EduNode 账户后，系统就会继续学习这份参考教案的结构与文风。"
                        : "A reference lesson plan is attached. Sign in to your EduNode account and the system will continue learning its structure and writing style."
                )
            )
            return
        }

        do {
            guard let service = backendLLMService, hasBackendSession else {
                throw EduBackendAPIError.authenticationRequired
            }
            let parsed = try await service.parseReferencePDF(
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
            appendTrace(
                stage: "reference",
                detail: "parse success sections=\(referenceDocument.styleProfile.sectionCount) missingItems=\(missingItems.count)"
            )

            if readiness.isReady {
                if let service = backendLLMService, hasBackendSession {
                    await generateReferenceGroundedDraft(
                        service: service,
                        settings: backendPromptSettings,
                        directive: ""
                    )
                } else {
                    conversation.append(
                        .init(
                            role: .assistant,
                            content: isChinese
                                ? "参考教案已经解析完成；请登录 EduNode 账户后再生成正式教案。"
                                : "The reference lesson plan is parsed. Sign in to your EduNode account to generate the final lesson plan."
                        )
                    )
                }
            }
        } catch {
            lastError = error.localizedDescription
            appendTrace(stage: "reference", detail: "parse failed error=\(error.localizedDescription)")
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
        service: EduBackendLLMService,
        settings: EduAgentProviderSettings,
        directive: String
    ) async {
        guard let referenceDocument else { return }
        isRunning = true
        lastError = nil
        appendTrace(
            stage: "generate",
            detail: "start unresolved=\(unresolvedItems.count) directiveChars=\(directive.count)"
        )

        do {
            var generationSettings = settings
            generationSettings.maxTokens = max(settings.maxTokens, 12000)
            let materializationMessages = EduLessonPlanMaterializationPromptBuilder.materializationMessages(
                settings: generationSettings,
                file: file,
                baselineMarkdown: baselineMarkdown,
                template: referenceDocument.templateDocument,
                missingItems: missingItems,
                answersByID: answersByID,
                skippedItemIDs: skippedItemIDs,
                supplementaryMaterial: "",
                userDirective: directive,
                referenceDocument: referenceDocument,
                compactContext: false
            )
            let structured = try await decodeStructuredWithJSONRetry(
                service: service,
                settings: generationSettings,
                messages: materializationMessages,
                as: EduLessonMaterializationResponse.self,
                compactOnRetry: false
            )
            appendTrace(
                stage: "generate",
                detail: "structured decode success assistantChars=\(structured.assistantReply.count) markdownChars=\(structured.generatedMarkdown.count)"
            )
            var alignedMarkdown = structured.generatedMarkdown
            var assistantReply = structured.assistantReply

            if shouldRetryForLowSubstance(markdown: alignedMarkdown, assistantReply: assistantReply) {
                appendTrace(stage: "generate", detail: "low-substance detected, retry with compact context")
                let qualityDirective = mergedDirective(
                    base: directive,
                    fallback: isChinese
                        ? "必须直接生成完整中文教案，不得索要额外输入或反问。若参考模板主题与当前图谱主题冲突，以当前图谱和课程元数据为准，仅复用模板结构与文风。每个主要章节至少写1-3句实质内容，避免只保留标题或空字段。"
                        : "Generate the full lesson plan directly from the provided context. Do not ask for additional input or clarification. If the reference template topic conflicts with the live graph topic, prioritize the live graph and keep only the reference structure/style. Each major section must contain 1-3 substantive sentences rather than title-only placeholders."
                )
                let compactMessages = EduLessonPlanMaterializationPromptBuilder.materializationMessages(
                    settings: settings,
                    file: file,
                    baselineMarkdown: baselineMarkdown,
                    template: referenceDocument.templateDocument,
                    missingItems: missingItems,
                    answersByID: answersByID,
                    skippedItemIDs: skippedItemIDs,
                    supplementaryMaterial: "",
                    userDirective: qualityDirective,
                    referenceDocument: referenceDocument,
                    compactContext: true
                )
                let compactStructured = try await decodeStructuredWithJSONRetry(
                    service: service,
                    settings: generationSettings,
                    messages: compactMessages,
                    as: EduLessonMaterializationResponse.self,
                    compactOnRetry: false
                )
                appendTrace(
                    stage: "generate",
                    detail: "compact retry decode success assistantChars=\(compactStructured.assistantReply.count) markdownChars=\(compactStructured.generatedMarkdown.count)"
                )
                alignedMarkdown = compactStructured.generatedMarkdown
                assistantReply = compactStructured.assistantReply

                if shouldRetryForLowSubstance(markdown: alignedMarkdown, assistantReply: assistantReply) {
                    appendTrace(stage: "generate", detail: "retry still low-substance, throwing fallback error")
                    throw EduAgentClientError.requestFailed(
                        isChinese
                            ? "已重试但结果仍接近模板空架子。请在‘优化教案’输入框补充一条具体指令（如：按45分钟写出每一步师生活动与评价证据），再试一次。"
                            : "Retried generation, but the result is still mostly a template skeleton. Add a concrete instruction (for example, step-by-step 45-minute activities with assessment evidence) and retry."
                    )
                }
            }

            alignedMarkdown = try await referenceAlignedMarkdownIfNeeded(
                alignedMarkdown,
                service: service,
                settings: settings
            )

            generatedMarkdown = alignedMarkdown
            conversation.append(.init(role: .assistant, content: assistantReply))
            userInput = ""
            appendTrace(stage: "generate", detail: "success finalMarkdownChars=\(alignedMarkdown.count)")
        } catch {
            lastError = error.localizedDescription
            appendTrace(stage: "generate", detail: "failed error=\(error.localizedDescription)")
        }

        isRunning = false
    }

    private func reviseCurrentDraft(
        service: EduBackendLLMService,
        settings: EduAgentProviderSettings,
        request: String
    ) async {
        isRunning = true
        lastError = nil
        appendTrace(stage: "revise", detail: "start requestChars=\(request.count)")

        let history = conversation
        conversation.append(.init(role: .user, content: request))
        userInput = ""

        do {
            let revisionMessages = EduAgentPromptBuilder.lessonPlanRevisionMessages(
                settings: settings,
                file: file,
                lessonPlanMarkdown: previewMarkdown,
                conversation: history,
                userRequest: request,
                supplementaryMaterial: "",
                referenceDocument: referenceDocument
            )
            let structured = try await decodeStructuredWithJSONRetry(
                service: service,
                settings: settings,
                messages: revisionMessages,
                as: EduAgentLessonPlanRevisionResponse.self,
                compactOnRetry: false
            )
            generatedMarkdown = try await referenceAlignedMarkdownIfNeeded(
                structured.revisedMarkdown,
                service: service,
                settings: settings
            )
            conversation.append(.init(role: .assistant, content: structured.assistantReply))
            appendTrace(stage: "revise", detail: "success revisedMarkdownChars=\(structured.revisedMarkdown.count)")
        } catch {
            lastError = error.localizedDescription
            appendTrace(stage: "revise", detail: "failed error=\(error.localizedDescription)")
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

        let settings = backendPromptSettings
        guard let service = backendLLMService, hasBackendSession else {
            followUpSuggestionStatusByID[item.id] = .unavailable(
                isChinese
                    ? "登录 EduNode 账户后，这里会基于模板与当前节点图生成补齐建议。"
                    : "Sign in to your EduNode account to generate template-aware follow-up suggestions here."
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
        appendTrace(stage: "followup", detail: "suggestion start item=\(item.id) force=\(force)")

        do {
            guard let referenceDocument else { return }
            let planningMessages = EduLessonPlanMaterializationPromptBuilder.followUpPlanningMessages(
                settings: settings,
                file: file,
                baselineMarkdown: baselineMarkdown,
                referenceDocument: referenceDocument,
                missingItems: missingItems,
                answersByID: answersByID,
                skippedItemIDs: skippedItemIDs,
                targetItem: item
            )
            let planning = try await decodeStructuredWithJSONRetry(
                service: service,
                settings: settings,
                messages: planningMessages,
                as: EduLessonFollowUpPlanningResponse.self,
                compactOnRetry: false
            )

            let suggestionMessages = EduLessonPlanMaterializationPromptBuilder.followUpSuggestionMessages(
                settings: settings,
                file: file,
                baselineMarkdown: baselineMarkdown,
                referenceDocument: referenceDocument,
                targetItem: item,
                planning: planning
            )
            let suggestion = try await decodeStructuredWithJSONRetry(
                service: service,
                settings: settings,
                messages: suggestionMessages,
                as: EduLessonFollowUpSuggestionResponse.self,
                compactOnRetry: true
            )

            let cleanedSummary = planning.planningSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanedAnswer = suggestion.suggestedAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanedSummary.isEmpty, !cleanedAnswer.isEmpty else {
                throw EduAgentClientError.invalidStructuredResponse
            }

            followUpSuggestionStatusByID[item.id] = .ready(
                EduLessonFollowUpSuggestion(
                    planningSummary: cleanedSummary,
                    suggestedAnswer: cleanedAnswer
                )
            )
            appendTrace(stage: "followup", detail: "suggestion success item=\(item.id) answerChars=\(cleanedAnswer.count)")
        } catch {
            followUpSuggestionStatusByID[item.id] = .failed(error.localizedDescription)
            appendTrace(stage: "followup", detail: "suggestion failed item=\(item.id) error=\(error.localizedDescription)")
        }
    }

    private func appendTrace(stage: String, detail: String) {
        debugTraceEvents.append(
            EduLessonAgentTraceEvent(
                timestamp: Date(),
                stage: stage,
                detail: detail
            )
        )
        if debugTraceEvents.count > 480 {
            debugTraceEvents.removeFirst(debugTraceEvents.count - 480)
        }
    }

    private func formatMessagesForTrace(_ messages: [EduLLMMessage]) -> String {
        var lines: [String] = []
        lines.append("messages.count=\(messages.count)")
        for (index, message) in messages.enumerated() {
            lines.append("--- message[\(index)] role=\(message.role) chars=\(message.content.count)")
            lines.append(message.content)
        }
        return lines.joined(separator: "\n")
    }

    private func decodeStructuredWithJSONRetry<T: Decodable>(
        service: EduBackendLLMService,
        settings: EduAgentProviderSettings,
        messages: [EduLLMMessage],
        as type: T.Type,
        compactOnRetry: Bool
    ) async throws -> T {
        let flowID = String(UUID().uuidString.prefix(8))
        appendTrace(
            stage: "llm.request",
            detail: "flow=\(flowID) step=initial type=\(String(describing: type)) maxTokens=\(settings.maxTokens)\n\(formatMessagesForTrace(messages))"
        )
        let firstReply = try await service.complete(messages: messages)
        appendTrace(
            stage: "llm.response",
            detail: "flow=\(flowID) step=initial type=\(String(describing: type)) chars=\(firstReply.count)\n\(firstReply)"
        )
        if let decoded = try? EduAgentJSONParser.decodeFirstJSONObject(type, from: firstReply) {
            appendTrace(stage: "llm.decode", detail: "flow=\(flowID) step=initial result=success")
            return decoded
        }
        if type == EduLessonFollowUpPlanningResponse.self,
           let lenient = decodeFollowUpPlanningLenient(from: firstReply) as? T {
            appendTrace(stage: "llm.decode", detail: "flow=\(flowID) step=initial result=lenient-success")
            return lenient
        }
        if type == EduLessonFollowUpSuggestionResponse.self,
           let lenient = decodeFollowUpSuggestionLenient(from: firstReply) as? T {
            appendTrace(stage: "llm.decode", detail: "flow=\(flowID) step=initial result=lenient-success")
            return lenient
        }
        if type == EduLessonMaterializationResponse.self,
           let lenient = decodeMaterializationLenient(from: firstReply) as? T {
            appendTrace(stage: "llm.decode", detail: "flow=\(flowID) step=initial result=lenient-success")
            return lenient
        }
        if type == EduAgentLessonPlanRevisionResponse.self,
           let lenient = decodeLessonRevisionLenient(from: firstReply) as? T {
            appendTrace(stage: "llm.decode", detail: "flow=\(flowID) step=initial result=lenient-success")
            return lenient
        }
        appendTrace(stage: "llm.decode", detail: "flow=\(flowID) step=initial result=failed")

#if DEBUG
        let firstExcerpt = String(firstReply.prefix(900)).replacingOccurrences(of: "\n", with: "\\n")
        print("[EduNode][FollowUpSuggestion][first-parse-failed] type=\(String(describing: type))")
        print("[EduNode][FollowUpSuggestion][first-reply]\(firstExcerpt)")
#endif

        let retryInstruction: String
        if type == EduLessonMaterializationResponse.self {
            retryInstruction = "Return only one valid JSON object with keys assistant_reply and generated_markdown. Do not ask for more inputs, do not explain what you need, and do not include markdown fences or extra prose. Treat all required context as already provided."
        } else if type == EduAgentLessonPlanRevisionResponse.self {
            retryInstruction = "Return only one valid JSON object with keys assistant_reply and revised_markdown. Do not ask follow-up questions, and do not include markdown fences or extra prose."
        } else if compactOnRetry {
            retryInstruction = "Return only one valid JSON object that matches the required schema. Do not include markdown fences or extra prose. Keep each string field concise and directly editable."
        } else {
            retryInstruction = "Return only one valid JSON object that matches the required schema. Do not include markdown fences or extra prose."
        }

        let retryMessages = messages + [
            .init(
                role: "user",
                content: retryInstruction
            )
        ]

        var retrySettings = settings
        retrySettings.maxTokens = preferredRetryMaxTokens(
            settings: settings,
            compactOnRetry: compactOnRetry,
            stage: 1
        )
        appendTrace(
            stage: "llm.request",
            detail: "flow=\(flowID) step=retry1 type=\(String(describing: type)) maxTokens=\(retrySettings.maxTokens)\n\(formatMessagesForTrace(retryMessages))"
        )
        let retryReply = try await service.complete(messages: retryMessages)
        appendTrace(
            stage: "llm.response",
            detail: "flow=\(flowID) step=retry1 type=\(String(describing: type)) chars=\(retryReply.count)\n\(retryReply)"
        )
        do {
            let decoded = try EduAgentJSONParser.decodeFirstJSONObject(type, from: retryReply)
            appendTrace(stage: "llm.decode", detail: "flow=\(flowID) step=retry1 result=success")
            return decoded
        } catch {
            if type == EduLessonFollowUpPlanningResponse.self,
               let lenient = decodeFollowUpPlanningLenient(from: retryReply) as? T {
                appendTrace(stage: "llm.decode", detail: "flow=\(flowID) step=retry1 result=lenient-success")
                return lenient
            }
            if type == EduLessonFollowUpSuggestionResponse.self,
               let lenient = decodeFollowUpSuggestionLenient(from: retryReply) as? T {
                appendTrace(stage: "llm.decode", detail: "flow=\(flowID) step=retry1 result=lenient-success")
                return lenient
            }
            if type == EduLessonMaterializationResponse.self,
               let lenient = decodeMaterializationLenient(from: retryReply) as? T {
                appendTrace(stage: "llm.decode", detail: "flow=\(flowID) step=retry1 result=lenient-success")
                return lenient
            }
            if type == EduAgentLessonPlanRevisionResponse.self,
               let lenient = decodeLessonRevisionLenient(from: retryReply) as? T {
                appendTrace(stage: "llm.decode", detail: "flow=\(flowID) step=retry1 result=lenient-success")
                return lenient
            }
            appendTrace(stage: "llm.decode", detail: "flow=\(flowID) step=retry1 result=failed")

            let secondRetryMessages = retryMessages + [
                .init(
                    role: "user",
                    content: "Your last response could not be parsed. Return only one compact valid JSON object. Escape quotes inside strings."
                )
            ]
            var secondRetrySettings = settings
            secondRetrySettings.maxTokens = preferredRetryMaxTokens(
                settings: settings,
                compactOnRetry: compactOnRetry,
                stage: 2
            )
            appendTrace(
                stage: "llm.request",
                detail: "flow=\(flowID) step=retry2 type=\(String(describing: type)) maxTokens=\(secondRetrySettings.maxTokens)\n\(formatMessagesForTrace(secondRetryMessages))"
            )
            let secondRetryReply = try await service.complete(messages: secondRetryMessages)
            appendTrace(
                stage: "llm.response",
                detail: "flow=\(flowID) step=retry2 type=\(String(describing: type)) chars=\(secondRetryReply.count)\n\(secondRetryReply)"
            )
            if let decoded = try? EduAgentJSONParser.decodeFirstJSONObject(type, from: secondRetryReply) {
                appendTrace(stage: "llm.decode", detail: "flow=\(flowID) step=retry2 result=success")
                return decoded
            }
            if type == EduLessonFollowUpPlanningResponse.self,
               let lenient = decodeFollowUpPlanningLenient(from: secondRetryReply) as? T {
                appendTrace(stage: "llm.decode", detail: "flow=\(flowID) step=retry2 result=lenient-success")
                return lenient
            }
            if type == EduLessonFollowUpSuggestionResponse.self,
               let lenient = decodeFollowUpSuggestionLenient(from: secondRetryReply) as? T {
                appendTrace(stage: "llm.decode", detail: "flow=\(flowID) step=retry2 result=lenient-success")
                return lenient
            }
            if type == EduLessonMaterializationResponse.self,
               let lenient = decodeMaterializationLenient(from: secondRetryReply) as? T {
                appendTrace(stage: "llm.decode", detail: "flow=\(flowID) step=retry2 result=lenient-success")
                return lenient
            }
            if type == EduAgentLessonPlanRevisionResponse.self,
               let lenient = decodeLessonRevisionLenient(from: secondRetryReply) as? T {
                appendTrace(stage: "llm.decode", detail: "flow=\(flowID) step=retry2 result=lenient-success")
                return lenient
            }
            appendTrace(stage: "llm.decode", detail: "flow=\(flowID) step=retry2 result=failed")
#if DEBUG
            let retryExcerpt = String(retryReply.prefix(900)).replacingOccurrences(of: "\n", with: "\\n")
            print("[EduNode][FollowUpSuggestion][retry-parse-failed] type=\(String(describing: type))")
            print("[EduNode][FollowUpSuggestion][retry-reply]\(retryExcerpt)")
#endif
            throw error
        }
    }

    private func decodeFollowUpSuggestionLenient(from raw: String) -> EduLessonFollowUpSuggestionResponse? {
        let keys = ["\"suggested_answer\"", "\"answer\"", "\"draft\"", "\"text\""]
        for key in keys {
            guard let keyRange = raw.range(of: key) else { continue }
            let afterKey = raw[keyRange.upperBound...]
            guard let colon = afterKey.firstIndex(of: ":") else { continue }
            var valueSlice = afterKey[raw.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)

            if valueSlice.hasPrefix("\"") {
                valueSlice.removeFirst()
                let chars = Array(valueSlice)
                var output = ""
                var escaped = false
                var index = 0

                func isLikelyJSONStringTerminatorQuote(at quoteIndex: Int, in source: [Character]) -> Bool {
                    var lookahead = quoteIndex + 1
                    while lookahead < source.count,
                          source[lookahead].isWhitespace {
                        lookahead += 1
                    }
                    if lookahead >= source.count {
                        return true
                    }
                    let next = source[lookahead]
                    return next == "," || next == "}" || next == "]" || next == "\n" || next == "\r"
                }

                while index < chars.count {
                    let ch = chars[index]
                    if escaped {
                        switch ch {
                        case "n": output.append("\n")
                        case "t": output.append("\t")
                        case "r": output.append("\r")
                        case "\"": output.append("\"")
                        case "\\": output.append("\\")
                        default: output.append(ch)
                        }
                        escaped = false
                        index += 1
                        continue
                    }
                    if ch == "\\" {
                        escaped = true
                        index += 1
                        continue
                    }
                    if ch == "\"" {
                        if isLikelyJSONStringTerminatorQuote(at: index, in: chars) {
                            break
                        }
                        output.append(ch)
                        index += 1
                        continue
                    }
                    output.append(ch)
                    index += 1
                }
                let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return EduLessonFollowUpSuggestionResponse(suggestedAnswer: trimmed)
                }
            } else {
                if let end = valueSlice.firstIndex(where: { $0 == "\n" || $0 == "}" }) {
                    valueSlice = String(valueSlice[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if !valueSlice.isEmpty {
                    return EduLessonFollowUpSuggestionResponse(suggestedAnswer: valueSlice)
                }
            }
        }
        return nil
    }

    private func decodeFollowUpPlanningLenient(from raw: String) -> EduLessonFollowUpPlanningResponse? {
        let source = raw.replacingOccurrences(of: "\r\n", with: "\n")

        func extractBlock(for key: String, nextKey: String?) -> String? {
            guard let keyRange = source.range(of: "\"\(key)\"") else { return nil }
            let after = source[keyRange.upperBound...]
            guard let colon = after.firstIndex(of: ":") else { return nil }
            let valueStart = source.index(after: colon)
            if let nextKey,
               let nextRange = source.range(of: "\"\(nextKey)\"", range: valueStart..<source.endIndex) {
                return String(source[valueStart..<nextRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return String(source[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func extractPrimaryString(_ block: String) -> String {
            let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let firstQuote = trimmed.firstIndex(of: "\"") else {
                return trimmed
            }
            let tail = trimmed[trimmed.index(after: firstQuote)...]
            if let endQuote = tail.firstIndex(of: "\"") {
                let candidate = String(tail[..<endQuote]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !candidate.isEmpty { return candidate }
            }
            return trimmed
        }

        let planningSummary = extractBlock(for: "planning_summary", nextKey: "grounded_evidence")
            .map(extractPrimaryString)
            .map { $0.replacingOccurrences(of: "\\n", with: "\n") }
            ?? ""

        guard !planningSummary.isEmpty else { return nil }

        return EduLessonFollowUpPlanningResponse(
            planningSummary: planningSummary,
            groundedEvidence: [],
            cautionPoints: []
        )
    }

    private func decodeMaterializationLenient(from raw: String) -> EduLessonMaterializationResponse? {
        let keys = ["\"generated_markdown\"", "\"generatedMarkdown\"", "\"markdown\""]
        for key in keys {
            guard let extractedMarkdown = extractJSONStringValue(for: key, in: raw) else { continue }
            let normalized = extractedMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { continue }

            let assistant = extractJSONStringValue(for: "\"assistant_reply\"", in: raw)
                ?? (isChinese ? "已根据上下文生成教案草稿。" : "Generated a lesson-plan draft from the provided context.")
            return EduLessonMaterializationResponse(
                assistantReply: assistant.trimmingCharacters(in: .whitespacesAndNewlines),
                generatedMarkdown: normalized
            )
        }
        return nil
    }

    private func decodeLessonRevisionLenient(from raw: String) -> EduAgentLessonPlanRevisionResponse? {
        let keys = ["\"revised_markdown\"", "\"revisedMarkdown\"", "\"markdown\""]
        for key in keys {
            guard let revised = extractJSONStringValue(for: key, in: raw) else { continue }
            let normalized = revised.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { continue }
            let assistant = extractJSONStringValue(for: "\"assistant_reply\"", in: raw)
                ?? (isChinese ? "已按你的要求更新教案。" : "Updated the lesson plan as requested.")
            return EduAgentLessonPlanRevisionResponse(
                assistantReply: assistant.trimmingCharacters(in: .whitespacesAndNewlines),
                revisedMarkdown: normalized
            )
        }
        return nil
    }

    private func extractJSONStringValue(for key: String, in raw: String) -> String? {
        guard let keyRange = raw.range(of: key) else { return nil }
        let afterKey = raw[keyRange.upperBound...]
        guard let colon = afterKey.firstIndex(of: ":") else { return nil }
        var valueSlice = afterKey[raw.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)

        guard valueSlice.hasPrefix("\"") else { return nil }
        valueSlice.removeFirst()

        let chars = Array(valueSlice)
        var output = ""
        var escaped = false
        var index = 0

        func isLikelyJSONStringTerminatorQuote(at quoteIndex: Int, in source: [Character]) -> Bool {
            var lookahead = quoteIndex + 1
            while lookahead < source.count,
                  source[lookahead].isWhitespace {
                lookahead += 1
            }
            if lookahead >= source.count {
                return true
            }
            let next = source[lookahead]
            return next == "," || next == "}" || next == "]" || next == "\n" || next == "\r"
        }

        while index < chars.count {
            let ch = chars[index]
            if escaped {
                switch ch {
                case "n": output.append("\n")
                case "t": output.append("\t")
                case "r": output.append("\r")
                case "\"": output.append("\"")
                case "\\": output.append("\\")
                default: output.append(ch)
                }
                escaped = false
                index += 1
                continue
            }
            if ch == "\\" {
                escaped = true
                index += 1
                continue
            }
            if ch == "\"" {
                if isLikelyJSONStringTerminatorQuote(at: index, in: chars) {
                    break
                }
                output.append(ch)
                index += 1
                continue
            }
            output.append(ch)
            index += 1
        }

        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func preferredRetryMaxTokens(
        settings: EduAgentProviderSettings,
        compactOnRetry: Bool,
        stage: Int
    ) -> Int {
        let floor: Int
        if compactOnRetry {
            floor = stage == 1 ? 10000 : 16000
        } else {
            floor = stage == 1 ? 20000 : 32000
        }
        return min(64000, max(settings.maxTokens, floor))
    }

    private func shouldRetryForLowSubstance(markdown: String, assistantReply: String) -> Bool {
        if indicatesMissingContext(assistantReply) {
            return true
        }

        let lines = markdown.components(separatedBy: .newlines)
        let nonEmptyLines = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let headingLikeLines = nonEmptyLines.filter { $0.hasPrefix("#") || $0.hasPrefix("【") || $0.hasPrefix("[") }
        let valueLikeLines = nonEmptyLines.filter { line in
            if line.hasPrefix("#") { return false }
            if line.hasSuffix(":") || line.hasSuffix("：") { return false }
            if line == "[what]" || line == "[why]" || line == "[how]" { return false }
            return line.count >= 8
        }

        let plainTextCharCount = nonEmptyLines
            .filter { !$0.hasPrefix("#") }
            .joined()
            .count

        if plainTextCharCount < 220 {
            return true
        }
        if valueLikeLines.count < 8 {
            return true
        }
        if headingLikeLines.count >= max(1, valueLikeLines.count) {
            return true
        }
        return false
    }

    private func indicatesMissingContext(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("no pedagogical graph")
            || lower.contains("no template")
            || lower.contains("no course metadata")
            || lower.contains("please share those inputs")
            || lower.contains("don't have access")
            || lower.contains("do not have access")
            || lower.contains("nothing was attached")
            || lower.contains("please provide the pedagogical graph")
            || lower.contains("please share")
            || text.contains("未提供")
            || text.contains("请提供")
            || text.contains("请粘贴")
    }

    private func mergedDirective(base: String, fallback: String) -> String {
        let trimmedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedBase.isEmpty {
            return fallback
        }
        return trimmedBase + "\n\n" + fallback
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
        service: EduBackendLLMService,
        settings: EduAgentProviderSettings
    ) async throws -> String {
        guard let referenceDocument else { return candidateMarkdown }
        return try await EduLessonTemplateAlignmentService.align(
            markdown: candidateMarkdown,
            service: service,
            settings: settings,
            file: file,
            referenceDocument: referenceDocument,
            trace: { [weak self] detail in
                guard let self else { return }
                self.appendTrace(stage: "alignment.llm", detail: detail)
            }
        )
    }
}
