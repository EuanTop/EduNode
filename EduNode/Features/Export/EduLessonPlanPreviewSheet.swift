import SwiftUI
import UniformTypeIdentifiers
import SwiftData
#if canImport(UIKit) && canImport(WebKit)
import UIKit
import WebKit
#endif
#if canImport(AppKit)
import AppKit
#endif

struct EduLessonPlanSetupPayload: Identifiable {
    let id = UUID()
    let sourceFile: GNodeWorkspaceFile
    let context: EduLessonPlanContext
    let graphData: Data
    let baseFileName: String
    let evaluationSnapshot: EduEvaluationScoreSnapshot?
}

struct EduLessonPlanPreviewPayload: Identifiable {
    let id = UUID()
    let sourceFile: GNodeWorkspaceFile
    let context: EduLessonPlanContext
    let graphData: Data
    let baseFileName: String
    let evaluationSnapshot: EduEvaluationScoreSnapshot?
    let baselineMarkdown: String
    let baselineHTML: String
    let referenceAttachment: EduLessonPlanReferenceAttachment?
}

struct EduLessonPlanExportSetupSheet: View {
    @Environment(\.dismiss) private var dismiss

    let payload: EduLessonPlanSetupPayload
    let onContinue: (EduLessonPlanPreviewPayload) -> Void

    @State private var referenceAttachment: EduLessonPlanReferenceAttachment?
    @State private var showingReferenceImporter = false
    @State private var lastError: String?

    private var isChinese: Bool {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
    }

    private var interfaceAccentColor: Color {
        .accentColor
    }

    var body: some View {
        VStack(spacing: 0) {
            setupHeaderBar()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    referenceCard
                    if let lastError {
                        EduAgentStatusCard(
                            title: isChinese ? "导入失败" : "Import Failed",
                            message: lastError,
                            tint: .orange
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.height(setupSheetHeight)])
        .presentationDragIndicator(.visible)
        .fileImporter(
            isPresented: $showingReferenceImporter,
            allowedContentTypes: [.pdf]
        ) { result in
            handleReferenceImport(result)
        }
    }

    private func setupHeaderBar() -> some View {
        HStack(spacing: 12) {
            headerCircleButton(
                systemImage: "xmark",
                accessibilityLabel: isChinese ? "关闭" : "Close"
            ) {
                dismiss()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(isChinese ? "导出教案" : "Export Lesson Plan")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(isChinese ? "选择参考教案后继续" : "Choose a reference plan, then continue")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)

            Spacer(minLength: 12)

            Button {
                continueToWorkbench()
            } label: {
                Text(isChinese ? "继续" : "Continue")
                    .font(.subheadline.weight(.semibold))
                    .frame(minWidth: 118)
                    .frame(height: 42)
            }
            .buttonStyle(EduAgentActionButtonStyle(variant: .primary))
        }
        .padding(.leading, 18)
        .padding(.trailing, 18)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private func headerCircleButton(
        systemImage: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 34, height: 34)
                .background(EduPanelStyle.controlFill, in: Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var referenceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text(isChinese ? "参考教案（可选）" : "Reference Lesson Plan (Optional)")
                    .font(.headline)
                Text(
                    isChinese
                        ? "上传后，系统会学习这份教案的章节安排、内容组织与文风，再结合当前节点图生成更贴近的教案。"
                        : "If you upload one, the system will learn its section arrangement, content organization, and tone, then generate a closer lesson plan from the current graph."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Button {
                showingReferenceImporter = true
            } label: {
                VStack(spacing: 12) {
                    Image(systemName: referenceAttachment == nil ? "square.and.arrow.up" : "doc.badge.gearshape")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(interfaceAccentColor)
                    Text(referenceAttachment == nil
                         ? (isChinese ? "点击选择参考教案 PDF" : "Tap to choose a reference lesson-plan PDF")
                         : (isChinese ? "已选择参考教案，点击可替换" : "Reference lesson plan selected. Tap to replace"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(referenceAttachment?.fileName ?? (isChinese ? "未上传也可以直接继续" : "You can also continue without uploading one"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 172)
                .background(EduPanelStyle.cardFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(stylePickerBorderColor, style: StrokeStyle(lineWidth: 1.2, dash: [8, 8]))
                )
            }
            .buttonStyle(.plain)

            if let referenceAttachment {
                HStack(spacing: 10) {
                    Image(systemName: "doc.richtext")
                        .foregroundStyle(interfaceAccentColor)
                    Text(referenceAttachment.fileName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Button {
                        self.referenceAttachment = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .frame(height: 42)
                .background(EduPanelStyle.cardFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eduPanelCard(cornerRadius: 18)
    }

    private func handleReferenceImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let data = try Data(contentsOf: url)
                referenceAttachment = EduLessonPlanReferenceAttachment(
                    fileName: url.lastPathComponent,
                    data: data
                )
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
        case .failure(let error):
            lastError = error.localizedDescription
        }
    }

    private func continueToWorkbench() {
        let baselineMarkdown = EduLessonPlanExporter.markdown(
            context: payload.context,
            graphData: payload.graphData,
            evaluationSnapshot: payload.evaluationSnapshot
        )
        let baselineHTML = EduLessonPlanExporter.html(
            context: payload.context,
            graphData: payload.graphData,
            evaluationSnapshot: payload.evaluationSnapshot
        )
        onContinue(
            EduLessonPlanPreviewPayload(
                sourceFile: payload.sourceFile,
                context: payload.context,
                graphData: payload.graphData,
                baseFileName: payload.baseFileName,
                evaluationSnapshot: payload.evaluationSnapshot,
                baselineMarkdown: baselineMarkdown,
                baselineHTML: baselineHTML,
                referenceAttachment: referenceAttachment
            )
        )
        dismiss()
    }

    private var stylePickerBorderColor: Color {
        referenceAttachment == nil ? Color.white.opacity(0.16) : interfaceAccentColor.opacity(0.34)
    }

    private var setupSheetHeight: CGFloat {
        if referenceAttachment != nil || lastError != nil {
            return 560
        }
        return 500
    }
}

struct EduLessonPlanWorkbenchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let payload: EduLessonPlanPreviewPayload

    @StateObject private var viewModel: EduLessonPlanWorkbenchViewModel
    @State private var showExporter = false
    @State private var exportDocument: EduExportDocument?
    @State private var exportContentType: UTType = .plainText
    @State private var exportFilename = "lesson-plan.md"
    @State private var isExportingPDF = false

    init(payload: EduLessonPlanPreviewPayload) {
        self.payload = payload
        _viewModel = StateObject(
            wrappedValue: EduLessonPlanWorkbenchViewModel(
                file: payload.sourceFile,
                baseFileName: payload.baseFileName,
                baselineMarkdown: payload.baselineMarkdown,
                referenceAttachment: payload.referenceAttachment
            )
        )
    }

    private var isChinese: Bool {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
    }

    private var interfaceAccentColor: Color {
        .accentColor
    }

    private var catalystWindowControlReservedWidth: CGFloat {
        #if targetEnvironment(macCatalyst)
        return 78
        #else
        return 0
        #endif
    }

    private var workbenchHeaderLeadingPadding: CGFloat {
        18 + catalystWindowControlReservedWidth
    }

    private var previewHTML: String {
        if viewModel.generatedMarkdown != nil {
            return EduMarkdownDocumentRenderer.html(
                markdown: viewModel.previewMarkdown,
                title: payload.context.name,
                isChinese: isChinese
            )
        }
        return payload.baselineHTML
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                workbenchHeaderBar(topInset: proxy.safeAreaInsets.top)

                HStack(spacing: 0) {
                    previewPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Rectangle()
                        .fill(EduPanelStyle.divider)
                        .frame(width: 1)

                    sidebar(proxy: proxy)
                        .frame(width: min(392, max(332, proxy.size.width * 0.31)))
                        .background(EduPanelStyle.sidebarBase)
                }
                .background(EduPanelStyle.sheetBackground)
            }
        }
        .eduSheetChrome()
        .ignoresSafeArea(.container, edges: .top)
        .sheet(isPresented: $viewModel.showingSettings) {
            EduAgentSettingsSheet(
                onSaved: {
                    viewModel.reloadSettingsFromStore()
                }
            )
        }
        .fileExporter(
            isPresented: $showExporter,
            document: exportDocument,
            contentType: exportContentType,
            defaultFilename: exportFilename
        ) { _ in
            exportDocument = nil
        }
        .task {
            viewModel.bootstrapIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .eduNodeBackendSessionDidChange)) { _ in
            viewModel.reloadSettingsFromStore()
        }
        .onChange(of: viewModel.generatedMarkdown) { _, newValue in
            let isDone = !(newValue?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            payload.sourceFile.lessonPlanMarkedDone = isDone
            payload.sourceFile.updatedAt = .now
            try? modelContext.save()
        }
    }

    private func workbenchHeaderBar(topInset: CGFloat) -> some View {
        HStack(spacing: 12) {
            headerCircleButton(
                systemImage: "xmark",
                accessibilityLabel: isChinese ? "关闭" : "Close"
            ) {
                dismiss()
            }

            Spacer(minLength: 12)

            exportActions
        }
        .padding(.leading, workbenchHeaderLeadingPadding)
        .padding(.trailing, 18)
        .padding(.top, topInset + 12)
        .padding(.bottom, 12)
        .background(EduPanelStyle.sheetBase)
    }

    private func headerCircleButton(
        systemImage: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 34, height: 34)
                .background(EduPanelStyle.controlFill, in: Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var previewPanel: some View {
        ZStack {
            if shouldShowReferenceLoadingPlaceholder {
                previewPlaceholder
            } else {
                LessonPlanHTMLView(html: previewHTML)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .padding(18)
            }

            if shouldShowPreviewRunningOverlay {
                generationLoadingOverlay
            }

            if isExportingPDF {
                ZStack {
                    Color.black.opacity(0.26).ignoresSafeArea()
                    VStack(spacing: 10) {
                        ProgressView()
                            .progressViewStyle(.circular)
                        Text(isChinese ? "正在导出 PDF…" : "Exporting PDF…")
                            .font(.callout)
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
    }

    private var shouldShowReferenceLoadingPlaceholder: Bool {
        payload.referenceAttachment != nil
            && viewModel.generatedMarkdown == nil
            && viewModel.lastError == nil
    }

    private var shouldShowPreviewRunningOverlay: Bool {
        viewModel.isRunning && !shouldShowReferenceLoadingPlaceholder
    }

    private var previewPlaceholder: some View {
        VStack(spacing: 16) {
            if viewModel.isPreparingReference || viewModel.isRunning {
                ProgressView()
                    .controlSize(.large)
            } else {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(interfaceAccentColor)
            }
            Text(previewPlaceholderTitle)
                .font(.headline)
            Text(previewPlaceholderBody)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var generationLoadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.24)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text(isChinese ? "正在生成教案" : "Generating Lesson Plan")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(
                    isChinese
                        ? "系统正在综合节点图、模板结构与补充信息，更新当前预览。"
                        : "The system is synthesizing the graph, template structure, and follow-up inputs to refresh the preview."
                )
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.78))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(18)
    }

    private var previewPlaceholderTitle: String {
        if viewModel.isPreparingReference {
            return isChinese
                ? "正在准备参考教案预览"
                : "Preparing the reference-based preview"
        }
        if viewModel.isRunning {
            return isChinese
                ? "正在生成正式教案"
                : "Generating the final lesson plan"
        }
        return isChinese
            ? "等待补齐信息后生成正式教案"
            : "Waiting for the remaining inputs before generating the final lesson plan"
    }

    private var previewPlaceholderBody: String {
        if viewModel.isPreparingReference {
            return isChinese
                ? "系统会先学习参考教案的结构、内容组织与文风，再结合当前节点图生成更贴近的正式稿。"
                : "The system first learns the reference lesson plan's structure, content organization, and tone, then uses the current graph to generate a closer final draft."
        }
        if viewModel.isRunning {
            return isChinese
                ? "系统正在整合参考教案结构、教师补充信息与当前节点图，请稍候。"
                : "The system is combining the reference structure, teacher follow-up inputs, and the current graph. Please wait."
        }
        return isChinese
            ? "参考模板已经识别完成，但系统还在等待教师补齐关键缺失项。右侧完成补问后，正式稿会自动进入预览。"
            : "The reference template has been parsed, but the system is still waiting for the remaining high-value teacher inputs. Once the follow-up items are resolved on the right, the final draft will appear here automatically."
    }

    private func sidebar(proxy: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            sidebarHeader

            GeometryReader { geometry in
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            if let referenceDocument = viewModel.referenceDocument {
                                referenceSummaryCard(referenceDocument)
                            }

                            if let lastError = viewModel.lastError {
                                EduAgentStatusCard(
                                    title: isChinese ? "请求失败" : "Request Failed",
                                    message: lastError,
                                    tint: .orange
                                )
                            }

                            ForEach(viewModel.conversation) { message in
                                lessonConversationRow(message)
                                    .id(message.id)
                            }

                            if viewModel.hasReferenceFlow && !viewModel.unresolvedItems.isEmpty {
                                followUpWorkbenchCard
                            }

                            Color.clear
                                .frame(height: 1)
                                .id("lesson-plan-workbench-bottom-anchor")
                        }
                        .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .bottom)
                        .padding(16)
                    }
                    .defaultScrollAnchor(.bottom)
                    .scrollIndicators(.hidden)
                    .onAppear {
                        scrollToBottom(scrollProxy, animated: false)
                    }
                    .onChange(of: conversationSignature) { _, _ in
                        scrollToBottom(scrollProxy, animated: true)
                    }
                }
            }

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)

            composerSection
        }
    }

    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isChinese ? "教案 Agent" : "Lesson Plan Agent")
                        .font(.headline)
                    Text(currentModelText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(currentModelColor)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    viewModel.showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.06), in: Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }

            Button {
                copyToClipboard(viewModel.debugTraceText)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.on.doc")
                    Text(isChinese ? "复制调试日志" : "Copy Debug Trace")
                        .font(.caption.weight(.semibold))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            if viewModel.hasReferenceFlow {
                sidebarReadinessStrip
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var composerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            EduAgentTextEditor(
                text: $viewModel.userInput,
                placeholder: viewModel.composerPlaceholder,
                minHeight: 52,
                maxHeight: 132,
                usesCompactComposerStyle: true
            )

            HStack {
                Text(viewModel.composerFootnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                Button {
                    Task { await viewModel.send() }
                } label: {
                    HStack(spacing: 8) {
                        if viewModel.isRunning {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(viewModel.actionButtonTitle)
                            .fontWeight(.semibold)
                    }
                    .frame(minWidth: 114)
                    .frame(height: 42)
                }
                .buttonStyle(EduAgentActionButtonStyle(variant: .primary))
                .disabled(actionButtonDisabled)
            }
        }
        .padding(16)
        .background(EduPanelStyle.headerBase)
    }

    private var actionButtonDisabled: Bool {
        if viewModel.isPreparingReference || viewModel.isRunning {
            return true
        }
        if viewModel.referenceDocument != nil && viewModel.generatedMarkdown == nil {
            return !viewModel.canGenerateReferenceDraft
        }
        return viewModel.userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var currentModelText: String {
        guard EduBackendServiceConfig.loadOptional() != nil else {
            return isChinese ? "未配置后端" : "Backend Unset"
        }
        guard EduBackendSessionStore.load() != nil else {
            return isChinese ? "未登录账户" : "Account Sign-in Required"
        }
        let cachedModel = EduBackendRuntimeStatusStore.load()?.activeModel.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return cachedModel.isEmpty ? (isChinese ? "模型检测中" : "Checking Model") : cachedModel
    }

    private var currentModelColor: Color {
        guard EduBackendServiceConfig.loadOptional() != nil else {
            return .orange
        }
        guard EduBackendSessionStore.load() != nil else {
            return .orange
        }
        if EduBackendRuntimeStatusStore.load()?.providerReachable == true {
            return .green
        }
        return interfaceAccentColor
    }

    private var conversationSignature: String {
        let messageSegments = viewModel.conversation.map { message in
            "\(message.id.uuidString):\(message.role.rawValue):\(message.content.count)"
        }
        let unresolvedSegments = viewModel.unresolvedItems.map { item in
            "\(item.id):\(viewModel.answersByID[item.id]?.count ?? 0):\(viewModel.skippedItemIDs.contains(item.id) ? "skip" : "open")"
        }
        let suggestionSegments = viewModel.followUpSuggestionStatusByID.keys.sorted().map { key in
            let stateLabel: String
            switch viewModel.followUpSuggestionStatusByID[key] {
            case .some(.loading):
                stateLabel = "loading"
            case .some(.ready(let suggestion)):
                stateLabel = "ready:\(suggestion.suggestedAnswer.count)"
            case .some(.failed(let message)):
                stateLabel = "failed:\(message.count)"
            case .some(.unavailable(let message)):
                stateLabel = "unavailable:\(message.count)"
            case .none:
                stateLabel = "none"
            }
            return "\(key):\(stateLabel)"
        }
        return (messageSegments + [
            viewModel.lastError ?? "",
            viewModel.generatedMarkdown == nil ? "draft:baseline" : "draft:generated",
            viewModel.isPreparingReference ? "preparing" : "idle",
            viewModel.isRunning ? "running" : "stopped",
            "focused:\(viewModel.focusedMissingItemID ?? "none")",
            "draftAnswer:\(viewModel.currentAnswerDraft.count)",
            "unresolved:\(unresolvedSegments.joined(separator: ","))",
            "suggestions:\(suggestionSegments.joined(separator: ","))"
        ]).joined(separator: "|")
    }

    @ViewBuilder
    private func lessonConversationRow(_ message: EduAgentConversationMessage) -> some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 10) {
            EduAgentBubble(
                role: message.role,
                content: message.content,
                isChinese: isChinese
            )
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private func referenceSummaryCard(_ referenceDocument: EduLessonReferenceDocument) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(isChinese ? "参考教案" : "Reference Lesson Plan")
                    .font(.headline)
                Spacer()
                EduAgentBadge(
                    text: isChinese
                        ? "\(referenceDocument.styleProfile.sectionCount) 个章节"
                        : "\(referenceDocument.styleProfile.sectionCount) sections",
                    tint: interfaceAccentColor
                )
            }
            Text(referenceDocument.sourceName)
                .font(.subheadline.weight(.semibold))
            Text(referenceDocument.styleProfile.featureHints.joined(separator: "\n"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eduPanelCard(cornerRadius: 16)
    }

    private var sidebarReadinessStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(isChinese ? "生成就绪进度" : "Generation Readiness")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("\(viewModel.readiness.resolvedItems)/\(viewModel.readiness.totalItems)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                EduAgentBadge(
                    text: readinessBadgeText,
                    tint: readinessBadgeTint
                )
            }
            EduAgentProgressBar(
                progress: viewModel.readinessProgress,
                tint: readinessBadgeTint
            )
            HStack(spacing: 8) {
                if viewModel.unresolvedCoreCount > 0 || viewModel.unresolvedSupportiveCount > 0 {
                    EduAgentMetricBadge(
                        title: isChinese ? "核心待补" : "Core left",
                        value: "\(viewModel.unresolvedCoreCount)",
                        tint: viewModel.unresolvedCoreCount == 0 ? .green : .orange
                    )
                    if viewModel.unresolvedSupportiveCount > 0 {
                        EduAgentMetricBadge(
                            title: isChinese ? "补充待补" : "Supportive left",
                            value: "\(viewModel.unresolvedSupportiveCount)",
                            tint: .white
                        )
                    }
                }
            }
            Text(readinessSummaryText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eduPanelCard(cornerRadius: 16)
    }

    private var followUpWorkbenchCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(isChinese ? "待补问信息" : "Follow-up Items")
                    .font(.headline)
                Spacer()
                Text(isChinese ? "剩余 \(viewModel.unresolvedItems.count) 项" : "\(viewModel.unresolvedItems.count) left")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(readinessSummaryText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(viewModel.unresolvedItems) { item in
                Button {
                    viewModel.beginEditing(item)
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(item.priority == .core ? Color.orange.opacity(0.94) : Color.white.opacity(0.34))
                            .frame(width: 8, height: 8)
                            .padding(.top, 5)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(item.sectionTitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if viewModel.activeFollowUpItem?.id == item.id {
                            Image(systemName: "pencil.circle.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(interfaceAccentColor)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        (viewModel.activeFollowUpItem?.id == item.id ? interfaceAccentColor.opacity(0.12) : Color.white.opacity(0.04)),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
            }

            if let activeItem = viewModel.activeFollowUpItem {
                Divider()
                    .overlay(Color.white.opacity(0.08))
                    .padding(.vertical, 2)

                followUpEditorSection(for: activeItem)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eduPanelCard(cornerRadius: 16)
    }

    private func followUpEditorSection(for item: EduLessonMissingInfoItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.headline)
                    Text(item.sectionTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                EduAgentBadge(
                    text: item.priority == .core
                        ? (isChinese ? "核心" : "Core")
                        : (isChinese ? "补充" : "Supportive"),
                    tint: item.priority == .core ? .orange : .white
                )
            }

            Text(item.question)
                .font(.caption)
                .foregroundStyle(.secondary)

            switch viewModel.followUpSuggestionStatus(for: item) {
            case .some(.loading):
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(isChinese ? "正在根据模板与节点图规划建议稿…" : "Planning a template-aware suggestion from the graph…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            case .some(.ready(let suggestion)):
                VStack(alignment: .leading, spacing: 8) {
                    Text(isChinese ? "规划摘要" : "Planning Summary")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(suggestion.planningSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Button {
                    viewModel.currentAnswerDraft = suggestion.suggestedAnswer
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(isChinese ? "使用建议草稿" : "Use Suggested Draft")
                            .font(.caption.weight(.semibold))
                        Text(suggestion.suggestedAnswer)
                            .font(.caption2)
                            .foregroundStyle(interfaceAccentColor.opacity(0.96))
                            .lineLimit(6)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

            case .some(.failed(let message)):
                VStack(alignment: .leading, spacing: 10) {
                    EduAgentStatusCard(
                        title: isChinese ? "建议生成失败" : "Suggestion Failed",
                        message: message,
                        tint: .orange
                    )
                    Button(isChinese ? "复制错误详情" : "Copy Error Details") {
                        copyToClipboard(message)
                    }
                    .buttonStyle(EduAgentActionButtonStyle(variant: .secondary))
                    Button(isChinese ? "重新生成建议" : "Retry Suggestion") {
                        Task {
                            await viewModel.prepareFollowUpSuggestionIfNeeded(for: item, force: true)
                        }
                    }
                    .buttonStyle(EduAgentActionButtonStyle(variant: .secondary))
                }

            case .some(.unavailable(let message)):
                VStack(alignment: .leading, spacing: 10) {
                    EduAgentStatusCard(
                        title: isChinese ? "等待模型配置" : "LLM Required",
                        message: message,
                        tint: .orange
                    )
                    Button(isChinese ? "打开模型设置" : "Open Model Settings") {
                        viewModel.showingSettings = true
                    }
                    .buttonStyle(EduAgentActionButtonStyle(variant: .secondary))
                }

            case .none:
                EmptyView()
            }

            EduAgentTextEditor(
                text: $viewModel.currentAnswerDraft,
                placeholder: item.placeholder,
                minHeight: 92
            )

            HStack {
                Button(isChinese ? "跳过" : "Skip") {
                    viewModel.skip(item)
                }
                .buttonStyle(EduAgentActionButtonStyle(variant: .secondary))

                Spacer()

                Button(isChinese ? "保存回答" : "Save Answer") {
                    viewModel.saveAnswer(for: item)
                }
                .buttonStyle(EduAgentActionButtonStyle(variant: .primary))
                .disabled(viewModel.currentAnswerDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eduPanelCard(cornerRadius: 16)
        .task(id: item.id) {
            await viewModel.prepareFollowUpSuggestionIfNeeded(for: item)
        }
    }

    private var readinessBadgeText: String {
        if payload.referenceAttachment == nil {
            return isChinese ? "基线预览" : "Baseline"
        }
        if viewModel.referenceDocument == nil {
            return isChinese ? "解析中" : "Parsing"
        }
        return viewModel.readiness.isReady
            ? (isChinese ? "可生成" : "Ready")
            : (isChinese ? "待补充" : "Needs follow-up")
    }

    private var readinessBadgeTint: Color {
        if payload.referenceAttachment == nil {
            return interfaceAccentColor
        }
        if viewModel.referenceDocument == nil {
            return .orange
        }
        return viewModel.readiness.isReady ? .green : .orange
    }

    private var readinessSummaryText: String {
        if payload.referenceAttachment == nil {
            return isChinese
                ? "未附加参考教案时，当前以节点图导出的基线教案作为优化起点。"
                : "Without a reference lesson plan, the graph-grounded baseline draft is used as the optimization starting point."
        }
        if viewModel.referenceDocument == nil {
            return isChinese
                ? "系统正在读取参考教案，并提取后续生成所需的章节结构与文风线索。"
                : "The system is reading the reference lesson plan and extracting the section and tone cues needed for generation."
        }
        if viewModel.unresolvedItems.isEmpty {
            return isChinese
                ? "模板要求的信息已齐备，系统可以正式生成教案。"
                : "All required template information is ready, so the workbench can generate the lesson plan."
        }
        return isChinese
            ? "请先回答或跳过当前补问项，系统不会对缺失事实进行杜撰。"
            : "Answer or skip the follow-up items first; the system will not invent missing lesson facts."
    }

    private func scrollToBottom(
        _ proxy: ScrollViewProxy,
        animated: Bool
    ) {
        let action = {
            proxy.scrollTo("lesson-plan-workbench-bottom-anchor", anchor: .bottom)
        }
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                action()
            }
        } else {
            action()
        }
    }

    private func copyToClipboard(_ text: String) {
#if canImport(UIKit)
        UIPasteboard.general.string = text
#elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
#endif
    }

    private func exportMarkdown() {
        guard !isExportingPDF,
              let data = viewModel.previewMarkdown.data(using: .utf8) else { return }
        exportDocument = EduExportDocument(data: data)
        exportContentType = .plainText
        exportFilename = isChinese
            ? "\(payload.baseFileName)-教案.md"
            : "\(payload.baseFileName)-lesson-plan.md"
        showExporter = true
    }

    private func exportPDF() {
        guard !isExportingPDF else { return }
        isExportingPDF = true

        let generatedMarkdown = viewModel.generatedMarkdown
        let previewMarkdown = viewModel.previewMarkdown
        let hasReferenceAttachment = payload.referenceAttachment != nil
        let context = payload.context
        let graphData = payload.graphData
        let evaluationSnapshot = payload.evaluationSnapshot
        let isChinese = self.isChinese
        let baseFileName = payload.baseFileName

        Task.detached(priority: .userInitiated) {
            let data: Data?
            if generatedMarkdown != nil || hasReferenceAttachment {
                data = await MainActor.run {
                    EduMarkdownDocumentRenderer.pdfData(
                        markdown: previewMarkdown,
                        title: context.name,
                        isChinese: isChinese
                    )
                }
            } else {
                data = await MainActor.run {
                    EduLessonPlanExporter.pdfData(
                        context: context,
                        graphData: graphData,
                        evaluationSnapshot: evaluationSnapshot
                    )
                }
            }

            await MainActor.run {
                isExportingPDF = false
                guard let data else { return }
                exportDocument = EduExportDocument(data: data)
                exportContentType = .pdf
                exportFilename = isChinese
                    ? "\(baseFileName)-教案.pdf"
                    : "\(baseFileName)-lesson-plan.pdf"
                showExporter = true
            }
        }
    }

    private var exportActions: some View {
        HStack(spacing: 8) {
            exportFormatButton(
                title: ".md",
                systemImage: "doc.plaintext",
                action: exportMarkdown
            )
            exportFormatButton(
                title: ".pdf",
                systemImage: "doc.richtext",
                action: exportPDF
            )
        }
        .disabled(isExportingPDF)
        .opacity(isExportingPDF ? 0.66 : 1)
    }

    private func exportFormatButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#if canImport(UIKit) && canImport(WebKit)
private struct LessonPlanHTMLView: UIViewRepresentable {
    let html: String

    final class Coordinator {
        var lastHTML = ""
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.isOpaque = false
        webView.backgroundColor = UIColor.clear
        webView.scrollView.backgroundColor = UIColor.clear
        context.coordinator.lastHTML = html
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        guard context.coordinator.lastHTML != html else { return }
        context.coordinator.lastHTML = html
        uiView.loadHTMLString(html, baseURL: nil)
    }
}
#else
private struct LessonPlanHTMLView: View {
    let html: String

    var body: some View {
        ScrollView {
            Text(html)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white)
                .padding()
        }
    }
}
#endif

struct EduExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText, .pdf] }
    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
