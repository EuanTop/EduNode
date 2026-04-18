import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct EduLessonMaterializationAgentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let file: GNodeWorkspaceFile
    let baselineMarkdown: String
    let baseFileName: String

    @State private var templateDocument: EduLessonTemplateDocument?
    @State private var missingItems: [EduLessonMissingInfoItem] = []
    @State private var answersByID: [String: String] = [:]
    @State private var skippedItemIDs: Set<String> = []
    @State private var currentAnswerDraft = ""
    @State private var focusedMissingItemID: String?
    @State private var conversation: [EduAgentConversationMessage] = []
    @State private var userInput = ""
    @State private var supplementaryMaterial = ""
    @State private var generatedMarkdown: String?
    @State private var isRunning = false
    @State private var lastError: String?
    @State private var showingSettings = false
    @State private var showingTemplateImporter = false
    @State private var showExporter = false
    @State private var exportDocument: EduExportDocument?

    private var isChinese: Bool {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
    }

    private var readiness: EduLessonGenerationReadiness {
        EduLessonMaterializationAnalyzer.readiness(
            items: missingItems,
            answersByID: answersByID,
            skippedItemIDs: skippedItemIDs
        )
    }

    private var currentUnresolvedItem: EduLessonMissingInfoItem? {
        missingItems.first { item in
            if skippedItemIDs.contains(item.id) {
                return false
            }
            let answer = answersByID[item.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return answer.isEmpty
        }
    }

    private var activeFollowUpItem: EduLessonMissingInfoItem? {
        if let focusedMissingItemID,
           let focused = missingItems.first(where: { $0.id == focusedMissingItemID }) {
            return focused
        }
        return currentUnresolvedItem
    }

    private var activeLessonPlanMarkdown: String {
        let candidate = generatedMarkdown?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return candidate.isEmpty ? baselineMarkdown : candidate
    }

    private var canGenerateMaterializedDraft: Bool {
        templateDocument != nil && readiness.isReady
    }

    private var canRefineGeneratedDraft: Bool {
        generatedMarkdown != nil && !userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var unresolvedItems: [EduLessonMissingInfoItem] {
        missingItems.filter { !isResolved($0) }
    }

    private var activeFollowUpPositionText: String? {
        guard let activeFollowUpItem,
              let index = unresolvedItems.firstIndex(where: { $0.id == activeFollowUpItem.id }) else {
            return nil
        }
        if isChinese {
            return "问题 \(index + 1) / \(unresolvedItems.count)"
        }
        return "Item \(index + 1) / \(unresolvedItems.count)"
    }

    private var readinessProgress: Double {
        if templateDocument == nil {
            return 0
        }
        guard readiness.totalItems > 0 else { return 1 }
        return Double(readiness.resolvedItems) / Double(readiness.totalItems)
    }

    private var unresolvedCoreCount: Int {
        unresolvedItems.filter { $0.priority == .core }.count
    }

    private var unresolvedSupportiveCount: Int {
        unresolvedItems.filter { $0.priority == .supportive }.count
    }

    private var composerPlaceholder: String {
        if generatedMarkdown == nil {
            return isChinese
                ? "这里可补充生成教案时的额外要求，例如语气、结构倾向、是否更强调评价证据等。留空也可以直接生成。"
                : "Optional extra instructions for lesson-plan generation, such as tone, structural preference, or stronger emphasis on assessment evidence."
        }
        return isChinese
            ? "例如：把教学过程改得更适合 40 分钟课堂，并加强对低先备学生的支架。"
            : "For example: tighten the teaching process for a 40-minute lesson and strengthen support for learners with lower prior knowledge."
    }

    private var composerFootnote: String {
        if generatedMarkdown == nil {
            if templateDocument == nil {
                return isChinese ? "先导入模板，系统才能判断当前图谱还缺哪些教案信息。" : "Import a template first so the system can detect what lesson-content information is still missing."
            }
            if !readiness.isReady {
                return isChinese
                    ? "还有 \(unresolvedItems.count) 项待处理信息，其中核心项 \(unresolvedCoreCount) 项。回答或跳过后才能正式生成。"
                    : "\(unresolvedItems.count) follow-up items are still unresolved, including \(unresolvedCoreCount) core items. Resolve or skip them before generation."
            }
            return isChinese
                ? "当前结构化信息已齐备，可以直接生成，也可以先补充额外要求。"
                : "Structured lesson inputs are now complete. You can generate directly or add optional constraints first."
        }
        return isChinese
            ? "生成稿已经就位。你可以继续让 Agent 改写，但它会以当前生成稿为基础，而不是重新从头生成。"
            : "A generated draft is ready. Further requests revise the current draft instead of regenerating from scratch."
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        templateCard

                        workflowCard

                        if let lastError {
                            EduAgentStatusCard(
                                title: isChinese ? "请求失败" : "Request Failed",
                                message: lastError,
                                tint: .orange
                            )
                        }

                        readinessCard

                        if !unresolvedItems.isEmpty {
                            unresolvedItemsCard
                        }

                        if let activeFollowUpItem {
                            followUpCard(for: activeFollowUpItem)
                                .id(activeFollowUpItem.id)
                        }

                        if !resolvedItems.isEmpty {
                            resolvedItemsCard
                        }

                        if let generatedMarkdown {
                            generatedDraftCard(generatedMarkdown)
                        } else {
                            EduAgentStatusCard(
                                title: isChinese ? "先导入模板，再补齐缺失信息" : "Import the template, then resolve missing information",
                                message: isChinese
                                    ? "系统会先基于模板结构检查当前图谱与元数据够不够，再逐项向教师追问真正缺失的教案内容。"
                                    : "The agent first checks whether the current graph and metadata satisfy the template, then asks only for genuinely missing lesson content.",
                                tint: .blue
                            )
                        }

                        ForEach(conversation) { message in
                            EduAgentBubble(
                                role: message.role,
                                content: message.content,
                                isChinese: isChinese
                            )
                        }
                    }
                    .padding(16)
                }

                divider

                VStack(spacing: 12) {
                    DisclosureGroup {
                        EduAgentTextEditor(
                            text: $supplementaryMaterial,
                            placeholder: isChinese
                                ? "可粘贴范例教案要求、课堂限制、学校格式要求，或任何你希望生成稿遵守的额外信息。"
                                : "Paste optional reference material, local template rules, or any extra constraints the generated lesson plan should follow.",
                            minHeight: 88
                        )
                    } label: {
                        Text(isChinese ? "补充素材 / 额外要求" : "Supplementary Material / Extra Constraints")
                            .font(.subheadline.weight(.semibold))
                    }
                    .tint(.white)

                    EduAgentTextEditor(
                        text: $userInput,
                        placeholder: composerPlaceholder,
                        minHeight: 92
                    )

                    HStack {
                        Button {
                            showingTemplateImporter = true
                        } label: {
                            Text(isChinese ? "导入模板" : "Import Template")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)

                        Spacer()

                        Button {
                            Task { await send() }
                        } label: {
                            HStack(spacing: 8) {
                                if isRunning {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                                Text(actionButtonTitle)
                                    .fontWeight(.semibold)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isActionDisabled)
                    }

                    Text(composerFootnote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
                .background(Color(white: 0.09))
            }
            .background(Color(white: 0.08).ignoresSafeArea())
            .navigationTitle(isChinese ? "教案 Agent" : "Lesson Plan Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(isChinese ? "关闭" : "Close") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 14) {
                        if generatedMarkdown != nil {
                            Button {
                                exportGeneratedMarkdown()
                            } label: {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                        Button {
                            showingSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingSettings) {
            EduAgentSettingsSheet()
        }
        .fileImporter(
            isPresented: $showingTemplateImporter,
            allowedContentTypes: [.pdf, .plainText, .text]
        ) { result in
            handleTemplateImport(result)
        }
        .fileExporter(
            isPresented: $showExporter,
            document: exportDocument,
            contentType: .plainText,
            defaultFilename: isChinese
                ? "\(baseFileName)-agent-教案.md"
                : "\(baseFileName)-agent-lesson-plan.md"
        ) { _ in
            exportDocument = nil
        }
    }

    private var actionButtonTitle: String {
        if generatedMarkdown == nil {
            return isChinese ? "生成教案" : "Generate Lesson Plan"
        }
        return isChinese ? "继续改写" : "Refine Draft"
    }

    private var isActionDisabled: Bool {
        if isRunning {
            return true
        }
        if generatedMarkdown == nil {
            return !canGenerateMaterializedDraft
        }
        return !canRefineGeneratedDraft
    }

    private var resolvedItems: [EduLessonMissingInfoItem] {
        missingItems.filter { item in
            isResolved(item)
        }
    }

    private var workflowCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isChinese ? "当前流程" : "Current Workflow")
                .font(.headline)

            HStack(spacing: 10) {
                workflowStep(
                    title: isChinese ? "1. 模板" : "1. Template",
                    subtitle: templateDocument == nil
                        ? (isChinese ? "待导入" : "Not imported")
                        : (isChinese ? "已解析" : "Parsed"),
                    isActive: templateDocument == nil,
                    isDone: templateDocument != nil
                )
                workflowStep(
                    title: isChinese ? "2. 补问" : "2. Follow-up",
                    subtitle: missingItems.isEmpty
                        ? (isChinese ? "无需补问" : "No follow-up needed")
                        : (readiness.isReady
                           ? (isChinese ? "已完成" : "Ready")
                           : (isChinese ? "处理中" : "In progress")),
                    isActive: templateDocument != nil && !readiness.isReady,
                    isDone: templateDocument != nil && readiness.isReady
                )
                workflowStep(
                    title: isChinese ? "3. 教案" : "3. Draft",
                    subtitle: generatedMarkdown == nil
                        ? (isChinese ? "待生成" : "Not generated")
                        : (isChinese ? "已生成" : "Generated"),
                    isActive: readiness.isReady && generatedMarkdown == nil,
                    isDone: generatedMarkdown != nil
                )
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var templateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(isChinese ? "模板理解" : "Template Understanding")
                    .font(.headline)
                Spacer()
                Button {
                    showingTemplateImporter = true
                } label: {
                    Text(templateDocument == nil ? (isChinese ? "导入" : "Import") : (isChinese ? "替换" : "Replace"))
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
            }

            if let templateDocument {
                Text(templateDocument.fileName)
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 8) {
                    EduAgentBadge(
                        text: isChinese
                            ? "\(templateDocument.schema.sections.count) 个章节"
                            : "\(templateDocument.schema.sections.count) sections",
                        tint: .teal
                    )
                    EduAgentBadge(
                        text: isChinese
                            ? "\(templateDocument.schema.styleNotes.count) 条体例提示"
                            : "\(templateDocument.schema.styleNotes.count) style notes",
                        tint: .white
                    )
                }
                Text(templateDocument.schema.outlineText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if !templateDocument.schema.styleNotes.isEmpty {
                    Text(templateDocument.schema.styleNotes.joined(separator: "\n"))
                        .font(.caption2)
                        .foregroundStyle(Color.teal.opacity(0.92))
                }
            } else {
                Text(isChinese
                     ? "导入教师提供的教案模板后，系统会先解析章节结构，再检查当前节点画布和元数据还缺哪些真正影响教案生成的信息。"
                     : "After you import a teacher-provided lesson template, the system parses its section structure first and then checks which lesson-content details are still missing from the current canvas and metadata.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var readinessCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(isChinese ? "生成就绪度" : "Generation Readiness")
                    .font(.headline)
                Spacer()
                EduAgentBadge(
                    text: readiness.isReady
                        ? (isChinese ? "可生成" : "Ready")
                        : (isChinese ? "待补充" : "Needs follow-up"),
                    tint: readiness.isReady ? .green : .orange
                )
            }

            EduAgentProgressBar(
                progress: readinessProgress,
                tint: readiness.isReady ? .green : .teal
            )

            if templateDocument == nil {
                Text(isChinese ? "尚未导入模板。" : "No template imported yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if missingItems.isEmpty {
                Text(isChinese
                     ? "当前模板下没有检测到必须补问的教案内容，可以直接生成。"
                     : "No mandatory follow-up items were detected for the current template. You can generate directly.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    EduAgentMetricBadge(
                        title: isChinese ? "已处理" : "Resolved",
                        value: "\(readiness.resolvedItems)/\(readiness.totalItems)",
                        tint: .teal
                    )
                    EduAgentMetricBadge(
                        title: isChinese ? "核心待补" : "Core left",
                        value: "\(unresolvedCoreCount)",
                        tint: unresolvedCoreCount == 0 ? .green : .orange
                    )
                    if unresolvedSupportiveCount > 0 {
                        EduAgentMetricBadge(
                            title: isChinese ? "补充待补" : "Supportive left",
                            value: "\(unresolvedSupportiveCount)",
                            tint: .white
                        )
                    }
                }
                if !readiness.isReady {
                    Text(isChinese ? "还有未处理问题，需回答或选择跳过后才能正式生成。" : "Some follow-up items are still unresolved. Answer or skip them before generation.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var unresolvedItemsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(isChinese ? "待处理信息" : "Items To Resolve")
                    .font(.headline)
                Spacer()
                Text(isChinese
                     ? "剩余 \(unresolvedItems.count) 项"
                     : "\(unresolvedItems.count) left")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(unresolvedItems) { item in
                Button {
                    focusedMissingItemID = item.id
                    currentAnswerDraft = answersByID[item.id] ?? ""
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(item.priority == .core ? Color.orange.opacity(0.9) : Color.white.opacity(0.36))
                            .frame(width: 8, height: 8)
                            .padding(.top, 6)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(item.sectionTitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if focusedMissingItemID == item.id {
                            EduAgentBadge(
                                text: isChinese ? "当前" : "Current",
                                tint: .teal
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func followUpCard(for item: EduLessonMissingInfoItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.headline)
                    if let activeFollowUpPositionText {
                        Text(activeFollowUpPositionText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(item.priority == .core
                     ? (isChinese ? "核心" : "Core")
                     : (isChinese ? "补充" : "Supportive"))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.06), in: Capsule())
            }

            Text(item.question)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(item.sectionTitle)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if !item.suggestedAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    currentAnswerDraft = item.suggestedAnswer
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(isChinese ? "使用建议草稿" : "Use Suggested Draft")
                            .font(.caption.weight(.semibold))
                        Text(item.suggestedAnswer)
                            .font(.caption2)
                            .foregroundStyle(Color.teal.opacity(0.92))
                            .lineLimit(4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            EduAgentTextEditor(
                text: $currentAnswerDraft,
                placeholder: item.placeholder,
                minHeight: 110
            )

            HStack {
                Button(isChinese ? "跳过" : "Skip") {
                    skip(item)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Button(isChinese ? "保存回答" : "Save Answer") {
                    saveAnswer(for: item)
                }
                .buttonStyle(.borderedProminent)
                .disabled(currentAnswerDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .onAppear {
            currentAnswerDraft = answersByID[item.id] ?? ""
        }
    }

    private var resolvedItemsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isChinese ? "已处理的问题" : "Resolved Follow-up Items")
                .font(.headline)
            ForEach(resolvedItems) { item in
                let answer = answerText(for: item)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top) {
                        Text(item.title)
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Button(isChinese ? "编辑" : "Edit") {
                            beginEditing(item)
                        }
                        .buttonStyle(.plain)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.teal.opacity(0.92))
                    }
                    if skippedItemIDs.contains(item.id) {
                        Text(isChinese ? "已跳过" : "Skipped")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(answer)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func generatedDraftCard(_ markdown: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(isChinese ? "生成稿" : "Generated Draft")
                    .font(.headline)
                Spacer()
                Button {
                    exportGeneratedMarkdown()
                } label: {
                    Text(".md")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
            }
            ScrollView(.vertical, showsIndicators: false) {
                Text(markdown)
                    .font(.system(size: 13, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 260, maxHeight: 400)
        }
        .padding(14)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func workflowStep(
        title: String,
        subtitle: String,
        isActive: Bool,
        isDone: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(isDone ? Color.green : (isActive ? Color.teal : Color.white.opacity(0.2)))
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            (isDone ? Color.green.opacity(0.08) : (isActive ? Color.teal.opacity(0.08) : Color.white.opacity(0.04))),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke((isDone ? Color.green : (isActive ? Color.teal : Color.white)).opacity(isActive || isDone ? 0.24 : 0.08), lineWidth: 1)
        )
    }

    @MainActor
    private func send() async {
        let settings = EduAgentSettingsStore.load()
        guard settings.isConfigured else {
            lastError = isChinese ? "请先配置 LLM。" : "Configure the LLM first."
            return
        }

        lastError = nil
        isRunning = true

        do {
            let client = EduOpenAICompatibleClient(settings: settings)

            if generatedMarkdown == nil {
                guard let templateDocument else {
                    lastError = isChinese ? "请先导入模板。" : "Import a template first."
                    isRunning = false
                    return
                }
                guard readiness.isReady else {
                    lastError = isChinese ? "还有未处理的补充问题。" : "Some follow-up items are still unresolved."
                    isRunning = false
                    return
                }

                let reply = try await client.complete(
                    messages: EduLessonPlanMaterializationPromptBuilder.materializationMessages(
                        settings: settings,
                        file: file,
                        baselineMarkdown: baselineMarkdown,
                        template: templateDocument,
                        missingItems: missingItems,
                        answersByID: answersByID,
                        skippedItemIDs: skippedItemIDs,
                        supplementaryMaterial: supplementaryMaterial,
                        userDirective: userInput
                    )
                )
                let structured = try EduAgentJSONParser.decodeFirstJSONObject(
                    EduLessonMaterializationResponse.self,
                    from: reply
                )
                generatedMarkdown = structured.generatedMarkdown
                markLessonPlanMaterialized()
                conversation.append(.init(role: .assistant, content: structured.assistantReply))
                userInput = ""
            } else {
                let request = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !request.isEmpty else {
                    isRunning = false
                    return
                }
                let history = conversation
                conversation.append(.init(role: .user, content: request))
                userInput = ""

                let reply = try await client.complete(
                    messages: EduAgentPromptBuilder.lessonPlanRevisionMessages(
                        settings: settings,
                        file: file,
                        lessonPlanMarkdown: activeLessonPlanMarkdown,
                        conversation: history,
                        userRequest: request,
                        supplementaryMaterial: supplementaryMaterial
                    )
                )
                let structured = try EduAgentJSONParser.decodeFirstJSONObject(
                    EduAgentLessonPlanRevisionResponse.self,
                    from: reply
                )
                conversation.append(.init(role: .assistant, content: structured.assistantReply))
                generatedMarkdown = structured.revisedMarkdown
                markLessonPlanMaterialized()
            }
        } catch {
            lastError = error.localizedDescription
        }

        isRunning = false
    }

    private func handleTemplateImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            guard url.startAccessingSecurityScopedResource() else {
                lastError = isChinese ? "无法访问模板文件。" : "Unable to access the template file."
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let document = try EduLessonTemplateDocumentLoader.load(from: url)
                templateDocument = document
                missingItems = EduLessonMaterializationAnalyzer.missingInfoItems(
                    template: document,
                    file: file,
                    baselineMarkdown: baselineMarkdown
                )
                markLessonPlanDirty()
                let prefilledAnswers = missingItems.reduce(into: [String: String]()) { partial, item in
                    guard item.autofillPolicy == .resolvedDraft else { return }
                    let suggested = item.suggestedAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !suggested.isEmpty else { return }
                    partial[item.id] = suggested
                }
                answersByID = prefilledAnswers
                skippedItemIDs = []
                focusedMissingItemID = nil
                currentAnswerDraft = ""
                generatedMarkdown = nil
                userInput = ""
                lastError = nil
                conversation = [
                    .init(
                        role: .assistant,
                        content: importedTemplateSummary(
                            document: document,
                            itemCount: missingItems.count,
                            prefilledCount: prefilledAnswers.count
                        )
                    )
                ]
            } catch {
                lastError = error.localizedDescription
            }
        case .failure(let error):
            lastError = error.localizedDescription
        }
    }

    private func importedTemplateSummary(
        document: EduLessonTemplateDocument,
        itemCount: Int,
        prefilledCount: Int
    ) -> String {
        let unresolvedCount = max(0, itemCount - prefilledCount)
        if isChinese {
            if itemCount == 0 {
                return "已解析模板“\(document.fileName)”。当前未发现必须补问的信息，可以直接生成教案。"
            }
            if unresolvedCount == 0 {
                return "已解析模板“\(document.fileName)”，识别到 \(document.schema.sections.count) 个章节结构，并基于当前图谱与元数据自动补足了 \(prefilledCount) 项内容。当前可以直接生成，也可以先手动微调。"
            }
            if prefilledCount > 0 {
                return "已解析模板“\(document.fileName)”，识别到 \(document.schema.sections.count) 个章节结构；其中 \(prefilledCount) 项已根据当前图谱与元数据自动补足，仍有 \(unresolvedCount) 项需要教师补充。"
            }
            return "已解析模板“\(document.fileName)”，识别到 \(document.schema.sections.count) 个章节结构，并提出 \(itemCount) 个待补问的教案内容。"
        }
        if itemCount == 0 {
            return "Parsed template \"\(document.fileName)\". No mandatory follow-up items were detected, so the lesson plan can be generated directly."
        }
        if unresolvedCount == 0 {
            return "Parsed template \"\(document.fileName)\" with \(document.schema.sections.count) detected sections and auto-filled \(prefilledCount) lesson-content items from the current graph and metadata. The lesson plan can now be generated directly."
        }
        if prefilledCount > 0 {
            return "Parsed template \"\(document.fileName)\" with \(document.schema.sections.count) detected sections. Auto-filled \(prefilledCount) lesson-content items from the current graph and metadata, with \(unresolvedCount) items still needing teacher input."
        }
        return "Parsed template \"\(document.fileName)\" with \(document.schema.sections.count) detected sections and \(itemCount) follow-up lesson-content items to resolve."
    }

    private func exportGeneratedMarkdown() {
        guard let generatedMarkdown,
              let data = generatedMarkdown.data(using: .utf8) else { return }
        exportDocument = EduExportDocument(data: data)
        showExporter = true
    }

    private func isResolved(_ item: EduLessonMissingInfoItem) -> Bool {
        skippedItemIDs.contains(item.id) || !answerText(for: item).isEmpty
    }

    private func answerText(for item: EduLessonMissingInfoItem) -> String {
        answersByID[item.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func beginEditing(_ item: EduLessonMissingInfoItem) {
        let existingAnswer = answersByID[item.id] ?? ""
        focusedMissingItemID = item.id
        answersByID.removeValue(forKey: item.id)
        skippedItemIDs.remove(item.id)
        currentAnswerDraft = existingAnswer
    }

    private func saveAnswer(for item: EduLessonMissingInfoItem) {
        let trimmed = currentAnswerDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        invalidateGeneratedDraftIfNeeded()
        answersByID[item.id] = trimmed
        skippedItemIDs.remove(item.id)
        currentAnswerDraft = ""
        if focusedMissingItemID == item.id {
            focusedMissingItemID = nil
        }
    }

    private func skip(_ item: EduLessonMissingInfoItem) {
        invalidateGeneratedDraftIfNeeded()
        answersByID.removeValue(forKey: item.id)
        skippedItemIDs.insert(item.id)
        currentAnswerDraft = ""
        if focusedMissingItemID == item.id {
            focusedMissingItemID = nil
        }
    }

    private func markLessonPlanMaterialized() {
        file.lessonPlanMarkedDone = true
        file.updatedAt = .now
        try? modelContext.save()
    }

    private func markLessonPlanDirty() {
        file.lessonPlanMarkedDone = false
        file.updatedAt = .now
        try? modelContext.save()
    }

    private func invalidateGeneratedDraftIfNeeded() {
        guard generatedMarkdown != nil else { return }
        generatedMarkdown = nil
        markLessonPlanDirty()
        conversation.append(
            .init(
                role: .assistant,
                content: isChinese
                    ? "结构化补充信息已更新，之前的生成稿已失效。请重新生成教案。"
                    : "Structured lesson inputs changed, so the previous generated draft has been cleared. Generate again to refresh the lesson plan."
            )
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
    }
}
