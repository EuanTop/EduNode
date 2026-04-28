import SwiftUI
import UniformTypeIdentifiers
import UIKit
import PDFKit

struct EduWorkspaceAgentSheet: View {
    private enum LiveThinkingPhase {
        case planning
        case solving
    }

    @Environment(\.dismiss) private var dismiss

    let file: GNodeWorkspaceFile
    @Binding private var conversation: [EduAgentConversationMessage]
    let pendingCanvasResponse: EduAgentGraphOperationEnvelope?
    let onStorePendingCanvasResponse: (EduAgentGraphOperationEnvelope) -> Void
    let onApplyPendingCanvasResponse: () -> Void
    let onDismissPendingCanvasResponse: () -> Void
    let canUndoLastApplied: Bool
    let onUndoLastApplied: () -> Void
    let onClose: (() -> Void)?

    @State private var userInput = ""
    @State private var supplementaryMaterial = ""
    @State private var isRunning = false
    @State private var lastError: String?
    @State private var showingSettings = false
    @State private var showingSupplementaryImporter = false
    @State private var runtimeStatus: EduAgentRuntimeStatusResponse?
    @State private var availableModels: [String] = []
    @State private var isRefreshingModels = false
    @State private var isModelPickerExpanded = false
    @State private var isThinkingEnabled = true
    @State private var landingSuggestedPrompts: [String] = []
    @State private var supplementaryMaterialSourceName: String?
    @State private var thinkingStartedAt: Date?
    @State private var isThinkingDetailsExpanded = false
    @State private var expandedThinkingMessageIDs: Set<UUID> = []
    @State private var liveThinkingMarkdown: String?
    @State private var liveThinkingPhase: LiveThinkingPhase = .planning
    @FocusState private var isComposerFocused: Bool
    init(
        file: GNodeWorkspaceFile,
        conversation: Binding<[EduAgentConversationMessage]>,
        pendingCanvasResponse: EduAgentGraphOperationEnvelope?,
        onStorePendingCanvasResponse: @escaping (EduAgentGraphOperationEnvelope) -> Void,
        onApplyPendingCanvasResponse: @escaping () -> Void,
        onDismissPendingCanvasResponse: @escaping () -> Void,
        canUndoLastApplied: Bool,
        onUndoLastApplied: @escaping () -> Void,
        onClose: (() -> Void)? = nil
    ) {
        self.file = file
        self._conversation = conversation
        self.pendingCanvasResponse = pendingCanvasResponse
        self.onStorePendingCanvasResponse = onStorePendingCanvasResponse
        self.onApplyPendingCanvasResponse = onApplyPendingCanvasResponse
        self.onDismissPendingCanvasResponse = onDismissPendingCanvasResponse
        self.canUndoLastApplied = canUndoLastApplied
        self.onUndoLastApplied = onUndoLastApplied
        self.onClose = onClose
    }

    private var isChinese: Bool {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
    }

    private var backendConfig: EduBackendServiceConfig? {
        EduBackendServiceConfig.loadOptional()
    }

    private var workspaceAgentService: EduWorkspaceAgentService? {
        EduWorkspaceAgentService(backendConfig: backendConfig)
    }

    private var isBackendConfigured: Bool {
        backendConfig != nil
    }

    private var isSignedIntoBackend: Bool {
        EduBackendSessionStore.load() != nil
    }

    private var isAgentReady: Bool {
        isBackendConfigured && isSignedIntoBackend && runtimeStatus?.providerReachable == true
    }

    private var statusBadgeText: String {
        guard isBackendConfigured else {
            return isChinese ? "未连接后端" : "Backend Unset"
        }
        guard isSignedIntoBackend else {
            return isChinese ? "请先登录" : "Sign In"
        }
        guard let runtimeStatus else {
            return isChinese ? "检测中" : "Checking"
        }
        if !runtimeStatus.llmConfigured {
            return isChinese ? "后端未配置 LLM" : "LLM Not Set"
        }
        let model = runtimeStatus.activeModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.isEmpty ? (isChinese ? "模型未命名" : "Unnamed Model") : model
    }

    private var statusBadgeTint: Color {
        guard isBackendConfigured else {
            return .orange
        }
        guard isSignedIntoBackend else {
            return .orange
        }
        if isRefreshingModels && runtimeStatus == nil {
            return .blue
        }
        if let runtimeStatus, runtimeStatus.providerReachable {
            return .green
        }
        if let runtimeStatus, runtimeStatus.llmConfigured {
            return .orange
        }
        return .blue
    }

    private var composerPlaceholder: String {
        guard isAgentReady else {
            if !isBackendConfigured {
                return isChinese
                    ? "请先连接 EduNode 在线服务。"
                    : "Connect the EduNode online service first."
            }
            if !isSignedIntoBackend {
                return isChinese
                    ? "请先登录 EduNode 账户。"
                    : "Sign in to your EduNode account first."
            }
            return isChinese
                ? "请先确保 EduNode 在线服务已启动且模型服务可用。"
                : "Make sure the EduNode online service is running and its model service is available."
        }

        return isChinese
            ? "例如：新增一个适合低先备学生的 Toolkit 活动；或指出当前课程结构最先该修的两处问题。"
            : "For example: add a lower-floor Toolkit activity; or identify the two most urgent structural problems in the lesson."
    }

    private var composerFootnote: String {
        if !isBackendConfigured {
            return isChinese
                ? "当前应用只连接 EduNode 在线服务；模型与解析服务都由服务端统一管理。"
                : "The app connects to EduNode online service only; model and parsing services are managed server-side."
        }
        if !isSignedIntoBackend {
            return isChinese
                ? "请先登录 EduNode 账户，随后即可使用 AI 搭图与其他在线能力。"
                : "Sign in to your EduNode account first to use AI canvas assistance and other online features."
        }
        if let runtimeStatus, !runtimeStatus.providerReachable {
            return isChinese
                ? runtimeStatus.message
                : runtimeStatus.message
        }
        if runtimeStatus == nil {
            return isChinese
                ? "正在检测后端运行状态与模型可用性。"
                : "Checking backend runtime status and model availability."
        }
        if pendingCanvasResponse?.operations.isEmpty == false {
            return isChinese
                ? "当前已有待审核的画布改动。可以先审核，也可以继续追问后再统一应用。"
                : "There are pending graph changes. Review them now or keep refining before applying."
        }
        return isChinese
            ? "Agent 会根据你的请求自动判断是给出分析建议，还是返回可审核的画布改动。"
            : "The agent will automatically decide whether to answer diagnostically or return reviewable graph edits."
    }

    private var conversationScrollSignature: String {
        let messageSegments = conversation.map { message in
            [
                message.id.uuidString,
                message.role.rawValue,
                message.proposalStatus?.rawValue ?? "none",
                String(message.content.count),
                String(message.canvasProposal?.operations.count ?? 0),
                String(message.suggestedPrompts.count)
            ]
            .joined(separator: ":")
        }
        let statusSegments = [
            lastError ?? "",
            isRunning ? "running" : "idle",
            String(landingSuggestedPrompts.count)
        ]
        let thinkingSegments = conversation.map { message in
            String(message.thinkingTraceMarkdown?.count ?? 0)
        }
        return (messageSegments + thinkingSegments + statusSegments).joined(separator: "|")
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                GeometryReader { proxy in
                    ScrollViewReader { scrollProxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 14) {
                                Spacer(minLength: 0)

                                setupStateCard

                                ForEach(conversation) { message in
                                    conversationRow(message)
                                        .id(message.id)
                                }

                                if isRunning, isThinkingEnabled {
                                    thinkingTraceCard
                                }

                                if let lastError {
                                    EduAgentStatusCard(
                                        title: isChinese ? "请求失败" : "Request Failed",
                                        message: lastError,
                                        tint: .orange
                                    )
                                }

                                Color.clear
                                    .frame(height: 1)
                                    .id("workspace-agent-bottom-anchor")
                            }
                            .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .bottom)
                            .padding(16)
                        }
                        .defaultScrollAnchor(.bottom)
                        .scrollIndicators(.hidden)
                        .onAppear {
                            scrollConversationToBottom(using: scrollProxy, animated: false)
                        }
                        .onChange(of: conversationScrollSignature) { _, _ in
                            scrollConversationToBottom(using: scrollProxy, animated: true)
                        }
                    }
                }

                divider

                if isAgentReady {
                    composerSection
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(composerFootnote)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
            }

            panelTopBar
                .padding(.top, 12)
                .padding(.trailing, 12)
                .zIndex(40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.clear)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingSettings) {
            EduAgentSettingsSheet(
                onSaved: {
                    Task { await refreshRuntimeStatus(force: true) }
                }
            )
        }
        .fileImporter(
            isPresented: $showingSupplementaryImporter,
            allowedContentTypes: supplementaryImportTypes
        ) { result in
            handleSupplementaryImport(result)
        }
        .task(id: suggestedPromptTaskID) {
            await refreshSuggestedPrompts()
        }
        .task(id: modelCatalogTaskID) {
            await refreshModelsSilently()
        }
    }

    private var panelTopBar: some View {
        HStack(spacing: 12) {
            if canUndoLastApplied {
                panelIconButton(systemImage: "arrow.uturn.backward") {
                    onUndoLastApplied()
                }
            }

            modelPickerBadge

            panelIconButton(systemImage: "gearshape") {
                isModelPickerExpanded = false
                showingSettings = true
            }

            panelIconButton(systemImage: "xmark") {
                isModelPickerExpanded = false
                closePanel()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var setupStateCard: some View {
        if !isBackendConfigured {
            EduAgentStatusCard(
                title: isChinese ? "需要先连接后端" : "Backend Connection Required",
                message: isChinese
                    ? "当前工作区 Agent 需要先连接 EduNode 在线服务。连接成功后，模型与参考教案解析能力会自动可用。"
                    : "The workspace agent needs an EduNode online service connection first. Once connected, model access and reference-template parsing become available automatically.",
                tint: .orange
            )
        } else if let runtimeStatus, !runtimeStatus.providerReachable {
            EduAgentStatusCard(
                title: isChinese ? "后端模型连接失败" : "Backend Model Connection Failed",
                message: runtimeStatus.message,
                tint: .orange
            )
        } else if runtimeStatus == nil {
            EduAgentStatusCard(
                title: isChinese ? "正在检查后端状态" : "Checking Backend Status",
                message: isChinese
                    ? "系统正在读取后端当前模型与可用模型列表。检查完成后会自动恢复对话与建议。"
                    : "The app is fetching the backend runtime model and available-model list. Chat and suggestions will resume automatically once the check completes.",
                tint: .blue
            )
        }
    }

    private var composerSection: some View {
        VStack(spacing: 12) {
            if conversation.isEmpty, !landingSuggestedPrompts.isEmpty {
                promptSuggestionList(landingSuggestedPrompts)
            }

            VStack(alignment: .leading, spacing: 8) {
                if let supplementaryMaterialSourceName,
                   !supplementaryMaterialSourceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    supplementaryAttachmentChip(name: supplementaryMaterialSourceName)
                }

                EduAgentTextEditor(
                    text: $userInput,
                    placeholder: composerPlaceholder,
                    minHeight: 26,
                    maxHeight: 92,
                    usesCompactComposerStyle: true,
                    focusState: $isComposerFocused
                )
            }

            HStack {
                HStack(spacing: 8) {
                    composerAccessoryButton(
                        title: "Thinking",
                        systemImage: isThinkingEnabled ? "brain.head.profile.fill" : "brain.head.profile",
                        isActive: isThinkingEnabled
                    ) {
                        isThinkingEnabled.toggle()
                    }

                    composerAccessoryButton(
                        title: isChinese ? "补充素材" : "Attachment",
                        systemImage: supplementaryMaterialSourceName == nil ? "paperclip" : "paperclip.circle.fill",
                        isActive: supplementaryMaterialSourceName != nil
                    ) {
                        showingSupplementaryImporter = true
                    }
                }

                Spacer()
                Button {
                    Task { await send() }
                } label: {
                    HStack(spacing: 8) {
                        if isRunning {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isChinese ? "发送" : "Send")
                            .fontWeight(.semibold)
                    }
                    .frame(minWidth: 86)
                    .frame(height: 42)
                }
                .buttonStyle(EduAgentActionButtonStyle(variant: .primary))
                .disabled(isRunning || userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

        }
        .padding(16)
    }

    @ViewBuilder
    private func conversationRow(_ message: EduAgentConversationMessage) -> some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 10) {
            if message.role == .assistant,
               let thinkingTraceMarkdown = message.thinkingTraceMarkdown,
               !thinkingTraceMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                thinkingSummaryCard(
                    messageID: message.id,
                    markdown: thinkingTraceMarkdown
                )
            }

            EduAgentBubble(
                role: message.role,
                content: message.content,
                isChinese: isChinese
            )

            if message.role == .assistant, let proposal = message.canvasProposal {
                canvasProposalCard(
                    proposal,
                    status: message.effectiveProposalStatus ?? .pending
                )
            }

            if message.role == .assistant, !message.suggestedPrompts.isEmpty {
                promptSuggestionList(message.suggestedPrompts)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private var liveThinkingTitle: String {
        switch liveThinkingPhase {
        case .planning:
            return isChinese ? "Thinking · 规划中" : "Thinking · Planning"
        case .solving:
            return isChinese ? "Thinking · 执行中" : "Thinking · Solving"
        }
    }

    private var liveThinkingPlaceholder: String {
        switch liveThinkingPhase {
        case .planning:
            return isChinese
                ? "正在根据当前节点画布生成 plan-and-solve 规划摘要。"
                : "Building a plan-and-solve brief from the current node canvas."
        case .solving:
            return isChinese
                ? "正在依据上面的规划摘要组织回答与画布改动。"
                : "Using the planning brief to assemble the reply and any canvas edits."
        }
    }

    @ViewBuilder
    private var thinkingTraceCard: some View {
        DisclosureGroup(
            isExpanded: $isThinkingDetailsExpanded,
            content: {
                VStack(alignment: .leading, spacing: 8) {
                    if let liveThinkingMarkdown,
                       !liveThinkingMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        EduAgentMarkdownBubbleContent(markdown: liveThinkingMarkdown, maxWidth: 300)
                    } else {
                        Text(liveThinkingPlaceholder)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 8)
            },
            label: {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(liveThinkingTitle)
                        .font(.subheadline.weight(.semibold))
                }
            }
        )
        .tint(.white)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func promptSuggestionList(_ prompts: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(prompts, id: \.self) { prompt in
                Button {
                    userInput = prompt
                    clearSuggestedPrompts()
                    isComposerFocused = true
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.teal)
                            .padding(.top, 1)

                        Text(prompt)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.07), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func canvasProposalCard(
        _ response: EduAgentGraphOperationEnvelope,
        status: EduAgentProposalStatus
    ) -> some View {
        let tint: Color
        let badgeText: String
        let iconName: String

        switch status {
        case .pending:
            tint = .orange
            badgeText = isChinese ? "待审核" : "Pending"
            iconName = "wand.and.stars"
        case .applied:
            tint = .green
            badgeText = isChinese ? "已应用" : "Applied"
            iconName = "checkmark.seal.fill"
        case .dismissed:
            tint = .gray
            badgeText = isChinese ? "已拒绝" : "Dismissed"
            iconName = "xmark.seal.fill"
        }

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(isChinese ? "画布改动建议" : "Canvas Change Proposal")
                    .font(.headline)
                Spacer()
                EduAgentBadge(text: badgeText, tint: tint)
            }

            if !response.operations.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(response.operations.prefix(6).enumerated()), id: \.offset) { index, operation in
                        Text("\(index + 1). \(canvasOperationPreview(operation))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if response.operations.count > 6 {
                        Text(isChinese ? "其余改动会在应用时一并处理。" : "Additional changes will also be applied.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if status == .pending {
                HStack(spacing: 10) {
                    Button {
                        onDismissPendingCanvasResponse()
                    } label: {
                        Text(isChinese ? "暂不采用" : "Dismiss")
                            .frame(minWidth: 96)
                            .frame(height: 46)
                    }
                    .buttonStyle(EduAgentActionButtonStyle(variant: .secondary))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                    Button {
                        onApplyPendingCanvasResponse()
                    } label: {
                        Text(isChinese ? "应用到画布" : "Apply to Canvas")
                            .frame(minWidth: 124)
                            .frame(height: 46)
                    }
                    .buttonStyle(EduAgentActionButtonStyle(variant: .primary))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                }
            } else {
                Text(status == .applied
                     ? (isChinese ? "该组改动已应用到当前画布。" : "This change set has been applied to the live canvas.")
                     : (isChinese ? "该组改动已被保留为历史建议，但未应用。" : "This change set was kept in history but not applied."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(tint.opacity(status == .pending ? 0.08 : 0.06))
        )
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: iconName)
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(tint.opacity(status == .pending ? 0.08 : 0.14))
                .padding(10)
                .allowsHitTesting(false)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tint.opacity(status == .pending ? 0.24 : 0.18), lineWidth: 1)
        )
        .fixedSize(horizontal: false, vertical: true)
    }

    @MainActor
    private func send() async {
        guard isBackendConfigured else {
            lastError = isChinese ? "请先连接 EduNode 后端。" : "Connect to EduNode backend first."
            return
        }
        guard isAgentReady else {
            lastError = runtimeStatus?.message ?? (isChinese ? "后端模型尚未就绪。" : "The backend model is not ready yet.")
            return
        }
        guard let workspaceAgentService else {
            lastError = isChinese ? "当前无法初始化后端连接。" : "Unable to initialize the backend connection."
            return
        }

        let request = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { return }

        lastError = nil
        isRunning = true
        thinkingStartedAt = .now
        isThinkingDetailsExpanded = isThinkingEnabled
        liveThinkingPhase = .planning
        liveThinkingMarkdown = nil
        isModelPickerExpanded = false
        dismissKeyboard()
        clearSuggestedPrompts()
        let history = conversation
        conversation.append(.init(role: .user, content: request))
        userInput = ""
        defer {
            isRunning = false
            thinkingStartedAt = nil
            liveThinkingMarkdown = nil
        }

        do {
            let assistantMessageID = UUID()
            let response = try await workspaceAgentService.send(
                file: file,
                conversation: history,
                userRequest: request,
                supplementaryMaterial: supplementaryMaterial,
                thinkingEnabled: isThinkingEnabled
            )
            liveThinkingPhase = .solving
            liveThinkingMarkdown = response.thinkingTraceMarkdown

            let normalized = EduAgentGraphOperationNormalizer.normalize(
                envelope: response,
                userRequest: request
            )

            if pendingCanvasResponse?.operations.isEmpty == false, !normalized.operations.isEmpty {
                onDismissPendingCanvasResponse()
            }

            if normalized.operations.isEmpty {
                conversation.append(
                    .init(
                        id: assistantMessageID,
                        role: .assistant,
                        content: normalized.assistantReply,
                        thinkingTraceMarkdown: normalized.thinkingTraceMarkdown
                    )
                )
            } else {
                conversation.append(
                    .init(
                        id: assistantMessageID,
                        role: .assistant,
                        content: normalized.assistantReply,
                        thinkingTraceMarkdown: normalized.thinkingTraceMarkdown,
                        canvasProposal: normalized,
                        proposalStatus: .pending
                    )
                )
                onStorePendingCanvasResponse(normalized)
            }

            if normalized.thinkingTraceMarkdown?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty == false {
                expandedThinkingMessageIDs.insert(assistantMessageID)
            }

            await refreshSuggestedPrompts(attachingTo: assistantMessageID)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func canvasOperationPreview(_ operation: EduAgentGraphOperation) -> String {
        switch operation.op.lowercased() {
        case "add_node":
            let nodeType = operation.nodeType?.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = operation.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            return [isChinese ? "新增" : "Add", label, nodeType]
                .compactMap { value in
                    guard let value, !value.isEmpty else { return nil }
                    return value
                }
                .joined(separator: " · ")
        case "update_node":
            return isChinese ? "更新已有节点" : "Update an existing node"
        case "connect":
            return isChinese ? "新增连线" : "Add a connection"
        case "disconnect":
            return isChinese ? "移除连线" : "Remove a connection"
        case "move_node":
            return isChinese ? "移动节点位置" : "Move a node"
        case "delete_node":
            return isChinese ? "删除节点" : "Delete a node"
        default:
            return operation.op
        }
    }

    private var supplementaryImportTypes: [UTType] {
        var result: [UTType] = [.pdf]
        if let mdType = UTType(filenameExtension: "md") {
            result.append(mdType)
        }
        if let markdownType = UTType(filenameExtension: "markdown"),
           !result.contains(markdownType) {
            result.append(markdownType)
        }
        return result
    }

    private func thinkingExpansionBinding(for messageID: UUID) -> Binding<Bool> {
        Binding(
            get: { expandedThinkingMessageIDs.contains(messageID) },
            set: { isExpanded in
                if isExpanded {
                    expandedThinkingMessageIDs.insert(messageID)
                } else {
                    expandedThinkingMessageIDs.remove(messageID)
                }
            }
        )
    }

    private func thinkingSummaryCard(
        messageID: UUID,
        markdown: String
    ) -> some View {
        DisclosureGroup(
            isExpanded: thinkingExpansionBinding(for: messageID),
            content: {
                EduAgentMarkdownBubbleContent(markdown: markdown, maxWidth: 300)
                    .padding(.top, 8)
            },
            label: {
                HStack(spacing: 8) {
                    Image(systemName: "brain.head.profile")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.teal)
                    Text("Thinking")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                }
            }
        )
        .tint(.white)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.teal.opacity(0.18), lineWidth: 1)
        )
    }

    private func supplementaryAttachmentChip(name: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.teal)

            Text(name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            Button {
                clearSupplementaryMaterial()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .frame(maxWidth: 280, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .fixedSize(horizontal: false, vertical: true)
    }

    private func composerAccessoryButton(
        title: String,
        systemImage: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(isActive ? Color.teal : Color.primary)
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isActive ? Color.teal.opacity(0.14) : Color.white.opacity(0.055))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isActive ? Color.teal.opacity(0.28) : Color.white.opacity(0.10), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func panelIconButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
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

    private var modelBadgeWidth: CGFloat { 164 }

    @ViewBuilder
    private var modelPickerDropdown: some View {
        if isBackendConfigured && isModelPickerExpanded {
            VStack(alignment: .leading, spacing: 6) {
                if availableModels.isEmpty, !isRefreshingModels {
                    Text(isChinese ? "后端暂未返回可用模型" : "No models returned by backend")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.top, 4)
                }

                if !availableModels.isEmpty {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            ForEach(availableModels, id: \.self) { model in
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(model == runtimeStatus?.activeModel ? statusBadgeTint : Color.clear)
                                        .frame(width: 6, height: 6)
                                    Text(model)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer(minLength: 0)
                                    if model == runtimeStatus?.activeModel {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(statusBadgeTint)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .frame(height: 28)
                                .background(
                                    (model == runtimeStatus?.activeModel ? statusBadgeTint.opacity(0.18) : Color.clear),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 180)
                }

                Button {
                    Task { await refreshRuntimeStatus(force: true) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                        Text(isChinese ? "刷新后端状态" : "Refresh Backend")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 30)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isRefreshingModels)

                Button {
                    isModelPickerExpanded = false
                    showingSettings = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "gearshape")
                        Text(isChinese ? "账户" : "Account")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 30)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .frame(width: modelBadgeWidth, alignment: .leading)
            .padding(8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.22), radius: 8, x: 0, y: 4)
            .offset(y: 40)
            .zIndex(12)
        }
    }

    @ViewBuilder
    private var modelPickerBadge: some View {
        Button {
            if isBackendConfigured {
                isModelPickerExpanded.toggle()
            } else {
                showingSettings = true
            }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusBadgeTint)
                    .frame(width: 6, height: 6)

                Text(statusBadgeText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(statusBadgeTint.opacity(0.98))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if isRefreshingModels {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: isBackendConfigured ? (isModelPickerExpanded ? "chevron.up" : "chevron.down") : "gearshape")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(isBackendConfigured ? 0.82 : 0.6))
                }
            }
            .padding(.horizontal, 10)
            .frame(width: modelBadgeWidth, alignment: .leading)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topLeading) {
            modelPickerDropdown
        }
        .zIndex(30)
    }

    private func closePanel() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
    }

    private var suggestedPromptTaskID: String {
        [
            file.id.uuidString,
            backendConfig?.baseURL.absoluteString ?? "no-backend",
            runtimeStatus?.activeModel ?? "no-model",
            String(supplementaryMaterial.count),
            isAgentReady ? "ready" : "not-ready"
        ].joined(separator: "|")
    }

    private var modelCatalogTaskID: String {
        [
            backendConfig?.baseURL.absoluteString ?? "no-backend"
        ].joined(separator: "|")
    }

    @MainActor
    private func refreshSuggestedPrompts(attachingTo messageID: UUID? = nil) async {
        guard isAgentReady else {
            landingSuggestedPrompts = []
            return
        }
        guard let workspaceAgentService else {
            landingSuggestedPrompts = []
            return
        }

        if conversation.isEmpty, messageID == nil {
            landingSuggestedPrompts = defaultLandingSuggestedPrompts()
        }

        do {
            let prompts = try await workspaceAgentService.suggestedPrompts(
                file: file,
                supplementaryMaterial: supplementaryMaterial
            )
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .prefix(3)
                .map { $0 }

            attachSuggestedPrompts(prompts, to: messageID)
        } catch {
            if conversation.isEmpty, messageID == nil, landingSuggestedPrompts.isEmpty {
                landingSuggestedPrompts = defaultLandingSuggestedPrompts()
            }
        }
    }

    private func attachSuggestedPrompts(_ prompts: [String], to messageID: UUID?) {
        guard !prompts.isEmpty else { return }

        if let messageID,
           let index = conversation.firstIndex(where: { $0.id == messageID }) {
            conversation[index].suggestedPrompts = prompts
            return
        }

        if let index = conversation.indices.last(where: { conversation[$0].role == .assistant }) {
            conversation[index].suggestedPrompts = prompts
            return
        }

        landingSuggestedPrompts = prompts
    }

    private func clearSuggestedPrompts() {
        landingSuggestedPrompts = []
        for index in conversation.indices {
            if !conversation[index].suggestedPrompts.isEmpty {
                conversation[index].suggestedPrompts = []
            }
        }
    }

    private func scrollConversationToBottom(
        using proxy: ScrollViewProxy,
        animated: Bool
    ) {
        let action = {
            proxy.scrollTo("workspace-agent-bottom-anchor", anchor: .bottom)
        }
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                action()
            }
        } else {
            action()
        }
    }

    private func dismissKeyboard() {
        isComposerFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func handleSupplementaryImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            Task {
                do {
                    let importedText = try readSupplementaryMaterial(from: url)
                    await MainActor.run {
                        supplementaryMaterial = importedText
                        supplementaryMaterialSourceName = url.lastPathComponent
                        lastError = nil
                    }
                    await refreshSuggestedPrompts()
                } catch {
                    await MainActor.run {
                        lastError = error.localizedDescription
                    }
                }
            }
        case .failure(let error):
            lastError = error.localizedDescription
        }
    }

    private func clearSupplementaryMaterial() {
        supplementaryMaterial = ""
        supplementaryMaterialSourceName = nil
        Task {
            await refreshSuggestedPrompts()
        }
    }

    private func readSupplementaryMaterial(from url: URL) throws -> String {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let ext = url.pathExtension.lowercased()
        if ext == "pdf" {
            guard let document = PDFDocument(url: url) else {
                throw EduAgentClientError.requestFailed(
                    isChinese ? "无法读取所选 PDF。" : "Unable to read the selected PDF."
                )
            }
            let pages = (0..<document.pageCount).compactMap { index in
                document.page(at: index)?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let text = pages
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw EduAgentClientError.requestFailed(
                    isChinese ? "所选 PDF 中没有可提取文本。" : "The selected PDF does not contain extractable text."
                )
            }
            return text
        }

        let text = try String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw EduAgentClientError.requestFailed(
                isChinese ? "所选 Markdown 文件为空。" : "The selected Markdown file is empty."
            )
        }
        return text
    }

    private func defaultLandingSuggestedPrompts() -> [String] {
        let snapshot = EduAgentContextBuilder.workspaceSnapshot(file: file)
        let graph = EduAgentLogicAdapter.graphContext(snapshot: snapshot)

        var prompts: [String] = []
        if graph.evaluationNodes.isEmpty {
            prompts.append(isChinese ? "补一项可执行的评价设计" : "Add one actionable evaluation node")
        }
        if graph.toolkitNodes.isEmpty {
            prompts.append(isChinese ? "补第一段 Toolkit 活动" : "Add the first Toolkit activity")
        } else {
            prompts.append(isChinese ? "指出当前节点画布最先该修的两处问题" : "Find the two biggest canvas issues")
        }
        if graph.knowledgeNodes.count >= 3 {
            prompts.append(isChinese ? "检查知识链与 Toolkit 承接" : "Check knowledge-toolkit alignment")
        } else {
            prompts.append(isChinese ? "补齐知识主线的层次结构" : "Strengthen the knowledge backbone")
        }
        prompts.append(isChinese ? "把建议改成具体画布操作" : "Turn advice into canvas edits")

        return Array(prompts.prefix(3))
    }

    @MainActor
    private func refreshModelsSilently() async {
        guard isBackendConfigured else {
            availableModels = []
            runtimeStatus = nil
            isRefreshingModels = false
            return
        }
        await refreshRuntimeStatus(force: false)
    }

    @MainActor
    private func refreshRuntimeStatus(force: Bool) async {
        guard let workspaceAgentService else {
            availableModels = []
            runtimeStatus = nil
            isRefreshingModels = false
            return
        }
        guard !isRefreshingModels else { return }
        if !force, runtimeStatus != nil, !availableModels.isEmpty { return }

        isRefreshingModels = true
        defer { isRefreshingModels = false }

        do {
            let status = try await workspaceAgentService.runtimeStatus()
            runtimeStatus = status
            availableModels = status.availableModels
        } catch {
            runtimeStatus = nil
            availableModels = []
            if force {
                lastError = error.localizedDescription
            }
        }
    }
}

struct EduPresentationAgentSheet: View {
    @Environment(\.dismiss) private var dismiss

    let file: GNodeWorkspaceFile
    let slides: [EduPresentationComposedSlide]
    let initialContentOverridesBySlideID: [UUID: [PresentationNativeElement: String]]
    let slideGroupIDBySlideID: [UUID: UUID]
    let onApplyOverrides: ([UUID: [PresentationNativeElement: String]]) -> Void

    @State private var conversation: [EduAgentConversationMessage] = []
    @State private var userInput = ""
    @State private var supplementaryMaterial = ""
    @State private var pendingOverrides: [EduAgentSlideContentOverride] = []
    @State private var workingContentOverridesBySlideID: [UUID: [PresentationNativeElement: String]]
    @State private var isRunning = false
    @State private var lastError: String?
    @State private var showingSettings = false

    init(
        file: GNodeWorkspaceFile,
        slides: [EduPresentationComposedSlide],
        initialContentOverridesBySlideID: [UUID: [PresentationNativeElement: String]],
        slideGroupIDBySlideID: [UUID: UUID],
        onApplyOverrides: @escaping ([UUID: [PresentationNativeElement: String]]) -> Void
    ) {
        self.file = file
        self.slides = slides
        self.initialContentOverridesBySlideID = initialContentOverridesBySlideID
        self.slideGroupIDBySlideID = slideGroupIDBySlideID
        self.onApplyOverrides = onApplyOverrides
        _workingContentOverridesBySlideID = State(initialValue: initialContentOverridesBySlideID)
    }

    private var isChinese: Bool {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let lastError {
                            EduAgentStatusCard(
                                title: isChinese ? "请求失败" : "Request Failed",
                                message: lastError,
                                tint: .orange
                            )
                        }

                        if !pendingOverrides.isEmpty {
                            overrideCard
                        } else {
                            EduAgentStatusCard(
                                title: isChinese ? "Agent 会改写现有 slide copy" : "The agent revises the existing slide copy",
                                message: isChinese
                                    ? "它会保留 slide 顺序和图谱语义，只覆盖真正需要调整的标题、副标题与主体文案。"
                                    : "It preserves slide order and graph semantics, and only overrides titles, subtitles, or body copy when needed.",
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

                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)

                VStack(spacing: 12) {
                    DisclosureGroup {
                        TextEditor(text: $supplementaryMaterial)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 88)
                            .padding(10)
                            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } label: {
                        Text(isChinese ? "补充素材 / 语气要求" : "Supplementary Material / Tone Constraints")
                            .font(.subheadline.weight(.semibold))
                    }
                    .tint(.white)

                    TextEditor(text: $userInput)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 92)
                        .padding(10)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )

                    HStack {
                        Button(isChinese ? "更口语化" : "Make It More Spoken") {
                            userInput = isChinese ? "请把整套 slide 文案调整得更适合教师现场讲述，减少书面堆砌感。" : "Make the slide copy more suitable for live teacher delivery and less text-heavy."
                        }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.semibold))
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
                                Text(isChinese ? "生成改写" : "Revise Slides")
                                    .fontWeight(.semibold)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isRunning || userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(16)
                .background(Color(white: 0.09))
            }
            .background(Color(white: 0.08).ignoresSafeArea())
            .navigationTitle(isChinese ? "课件 Agent" : "Presentation Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(isChinese ? "关闭" : "Close") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 14) {
                        if !pendingOverrides.isEmpty {
                            Button(isChinese ? "应用" : "Apply") {
                                applyOverrides()
                            }
                            .fontWeight(.semibold)
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
    }

    private var overrideCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(isChinese ? "待应用文案改写" : "Pending Slide Overrides")
                    .font(.headline)
                Spacer()
                Button(isChinese ? "应用到当前课件" : "Apply to Deck") {
                    applyOverrides()
                }
                .buttonStyle(.borderedProminent)
            }

            ForEach(pendingOverrides) { override in
                VStack(alignment: .leading, spacing: 6) {
                    Text(slides.first(where: { $0.id == override.slideID })?.title ?? override.slideID.uuidString)
                        .font(.subheadline.weight(.semibold))
                    if let title = override.title {
                        Text("Title: \(title)")
                            .font(.caption)
                    }
                    if let subtitle = override.subtitle {
                        Text("Subtitle: \(subtitle)")
                            .font(.caption)
                    }
                    if let mainContent = override.mainContent {
                        Text("Main: \(mainContent)")
                            .font(.caption)
                            .lineLimit(3)
                    }
                    if let toolkitContent = override.toolkitContent {
                        Text("Toolkit: \(toolkitContent)")
                            .font(.caption)
                            .lineLimit(3)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
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

    @MainActor
    private func send() async {
        guard let service = EduBackendLLMService(),
              EduBackendSessionStore.load() != nil else {
            lastError = isChinese ? "请先登录 EduNode 账户后再使用 AI 搭图。" : "Sign in to your EduNode account before using AI canvas assistance."
            return
        }
        let request = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { return }

        let activeModel = (EduBackendRuntimeStatusStore.load()?.activeModel ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let settings = EduAgentProviderSettings(
            providerName: "EduNode Backend",
            baseURLString: EduBackendServiceConfig.loadOptional()?.baseURL.absoluteString ?? "backend",
            model: activeModel.isEmpty ? "backend-model" : activeModel,
            apiKey: "session",
            temperature: 0.35,
            maxTokens: 3200,
            timeoutSeconds: 120,
            additionalSystemPrompt: ""
        )

        lastError = nil
        isRunning = true
        let history = conversation
        conversation.append(.init(role: .user, content: request))
        userInput = ""

        do {
            let reply = try await service.complete(
                messages: EduAgentPromptBuilder.presentationRevisionMessages(
                    settings: settings,
                    file: file,
                    slides: effectiveSlidesForPrompt(),
                    conversation: history,
                    userRequest: request,
                    supplementaryMaterial: supplementaryMaterial
                )
            )
            let structured = try EduAgentJSONParser.decodeFirstJSONObject(EduAgentPresentationRevisionResponse.self, from: reply)
            conversation.append(.init(role: .assistant, content: structured.assistantReply))
            pendingOverrides = structured.slideOverrides
        } catch {
            lastError = error.localizedDescription
        }

        isRunning = false
    }

    private func applyOverrides() {
        let map = pendingOverrides.reduce(into: [UUID: [PresentationNativeElement: String]]()) { partial, entry in
            let content = entry.nativeOverrides
            guard !content.isEmpty else { return }
            partial[entry.slideID] = content
        }
        mergeWorkingOverrides(map)
        onApplyOverrides(map)
        pendingOverrides = []
    }

    private func mergeWorkingOverrides(_ overrides: [UUID: [PresentationNativeElement: String]]) {
        for (slideID, content) in overrides {
            workingContentOverridesBySlideID[slideID, default: [:]].merge(content) { _, new in new }
        }
    }

    private func effectiveSlidesForPrompt() -> [EduPresentationComposedSlide] {
        let pendingOverrideMap = pendingOverrides.reduce(into: [UUID: [PresentationNativeElement: String]]()) { partial, entry in
            let content = entry.nativeOverrides
            guard !content.isEmpty else { return }
            partial[entry.slideID, default: [:]].merge(content) { _, new in new }
        }

        return slides.map { slide in
            var merged = workingContentOverridesBySlideID[slide.id] ?? [:]
            if let pending = pendingOverrideMap[slide.id] {
                merged.merge(pending) { _, new in new }
            }
            return slideApplyingContentOverrides(slide, overrides: merged)
        }
    }

    private func slideApplyingContentOverrides(
        _ slide: EduPresentationComposedSlide,
        overrides: [PresentationNativeElement: String]
    ) -> EduPresentationComposedSlide {
        let resolvedTitle = normalizedOverrideText(overrides[.title]) ?? slide.title
        let resolvedSubtitle = normalizedOverrideText(overrides[.subtitle]) ?? slide.subtitle
        let resolvedMainContent = normalizedOverrideText(overrides[.mainContent])
        let resolvedToolkitContent = normalizedOverrideText(overrides[.toolkitContent])

        var knowledgeItems = slide.knowledgeItems
        var toolkitItems = slide.toolkitItems
        var keyPoints = slide.keyPoints

        if let resolvedMainContent {
            let items = parsedSlideItems(from: resolvedMainContent)
            if !slide.knowledgeItems.isEmpty {
                knowledgeItems = items
                keyPoints = items
            } else {
                keyPoints = items
            }
        }

        if let resolvedToolkitContent {
            toolkitItems = parsedSlideItems(from: resolvedToolkitContent)
        }

        return EduPresentationComposedSlide(
            id: slide.id,
            index: slide.index,
            title: resolvedTitle,
            subtitle: resolvedSubtitle,
            knowledgeItems: knowledgeItems,
            toolkitItems: toolkitItems,
            keyPoints: keyPoints,
            speakerNotes: slide.speakerNotes
        )
    }

    private func normalizedOverrideText(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func parsedSlideItems(from text: String) -> [String] {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: .newlines)
            .map { line in
                line.trimmingCharacters(in: CharacterSet(charactersIn: " \t-•*0123456789.)、"))
            }
            .filter { !$0.isEmpty }

        if !lines.isEmpty {
            return lines
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? [] : [trimmed]
    }
}

struct EduAgentBubble: View {
    let role: EduAgentConversationMessage.Role
    let content: String
    let isChinese: Bool

    private let maxBubbleWidth: CGFloat = 290
    private let minimumBubbleWidth: CGFloat = 54

    private var prefersCompactWidth: Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        guard !trimmed.contains("\n") else { return false }

        let denseMarkdownMarkers = [
            "|", "```", "# ", "##", "###", "- ", "* ", "1. ", "2. ", "3. "
        ]
        guard denseMarkdownMarkers.allSatisfy({ !trimmed.contains($0) }) else {
            return false
        }

        return trimmed.count <= 46
    }

    var body: some View {
        VStack(alignment: role == .user ? .trailing : .leading, spacing: 6) {
            Text(role == .user ? (isChinese ? "你" : "You") : "Agent")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            bubbleBody
                .frame(maxWidth: .infinity, alignment: role == .user ? .trailing : .leading)
        }
        .frame(maxWidth: .infinity, alignment: role == .user ? .trailing : .leading)
    }

    private var bubbleBody: some View {
        Group {
            if role == .assistant {
                EduAgentMarkdownBubbleContent(
                    markdown: content,
                    maxWidth: maxBubbleWidth - 24
                )
            } else {
                Text(content)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(
            minWidth: minimumBubbleWidth,
            idealWidth: prefersCompactWidth ? nil : maxBubbleWidth,
            maxWidth: prefersCompactWidth ? nil : maxBubbleWidth,
            alignment: .leading
        )
        .fixedSize(horizontal: prefersCompactWidth, vertical: false)
        .background(
            (role == .user ? Color.accentColor.opacity(0.22) : Color.white.opacity(0.05)),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(role == .user ? 0.06 : 0.08), lineWidth: 1)
        )
    }
}

struct EduAgentActionButtonStyle: ButtonStyle {
    enum Variant: Equatable {
        case primary
        case secondary
        case destructive

        var foregroundColor: Color {
            switch self {
            case .primary:
                return .accentColor
            case .secondary:
                return .primary
            case .destructive:
                return .red.opacity(0.96)
            }
        }

        var fillColor: Color {
            switch self {
            case .primary:
                return Color.accentColor.opacity(0.16)
            case .secondary:
                return Color.white.opacity(0.06)
            case .destructive:
                return Color.red.opacity(0.10)
            }
        }

        var strokeColor: Color {
            switch self {
            case .primary:
                return Color.accentColor.opacity(0.30)
            case .secondary:
                return Color.white.opacity(0.12)
            case .destructive:
                return Color.red.opacity(0.20)
            }
        }
    }

    let variant: Variant

    func makeBody(configuration: Configuration) -> some View {
        EduAgentActionButtonStyleBody(configuration: configuration, variant: variant)
    }
}

private struct EduAgentActionButtonStyleBody: View {
    @Environment(\.isEnabled) private var isEnabled

    let configuration: ButtonStyle.Configuration
    let variant: EduAgentActionButtonStyle.Variant

    var body: some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(foreground.opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1.0) : 0.42))
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(fill.opacity(isEnabled ? (configuration.isPressed ? 1.0 : 0.94) : 0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(stroke.opacity(isEnabled ? (configuration.isPressed ? 0.92 : 1.0) : 0.44), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var foreground: Color {
        variant.foregroundColor
    }

    private var fill: Color {
        variant.fillColor
    }

    private var stroke: Color {
        variant.strokeColor
    }
}

struct EduAgentStatusCard: View {
    let title: String
    let message: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(tint.opacity(0.35), lineWidth: 1)
        )
    }
}

struct EduAgentBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint.opacity(0.96))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tint.opacity(0.14), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(tint.opacity(0.32), lineWidth: 1)
            )
    }
}

struct EduAgentMetricBadge: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint.opacity(0.96))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        )
    }
}

struct EduAgentProgressBar: View {
    let progress: Double
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            let clamped = min(max(progress, 0), 1)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(tint.opacity(0.88))
                    .frame(width: max(8, geometry.size.width * clamped))
            }
        }
        .frame(height: 8)
    }
}

struct EduAgentTextEditor: View {
    @Binding var text: String
    let placeholder: String
    let minHeight: CGFloat
    var maxHeight: CGFloat? = nil
    var usesCompactComposerStyle: Bool = false
    var focusState: FocusState<Bool>.Binding? = nil

    var body: some View {
        ZStack(alignment: .topLeading) {
            if usesCompactComposerStyle {
                compactComposerField
            } else {
                regularEditorField
            }

            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(placeholder)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, usesCompactComposerStyle ? 9 : 18)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture {
            focusState?.wrappedValue = true
        }
    }

    @ViewBuilder
    private var compactComposerField: some View {
        if let focusState {
            TextField("", text: $text, axis: .vertical)
                .focused(focusState)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .lineLimit(1...5)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minHeight: minHeight, maxHeight: maxHeight, alignment: .topLeading)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        } else {
            TextField("", text: $text, axis: .vertical)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .lineLimit(1...5)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minHeight: minHeight, maxHeight: maxHeight, alignment: .topLeading)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        }
    }

    @ViewBuilder
    private var regularEditorField: some View {
        if let focusState {
            TextEditor(text: $text)
                .focused(focusState)
                .scrollContentBackground(.hidden)
                .frame(minHeight: minHeight, maxHeight: maxHeight)
                .padding(10)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        } else {
            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .frame(minHeight: minHeight, maxHeight: maxHeight)
                .padding(10)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        }
    }
}
