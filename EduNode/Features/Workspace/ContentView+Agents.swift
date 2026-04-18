import SwiftUI
import SwiftData
import GNodeKit

struct EduAgentGraphUndoSnapshot {
    let data: Data
    let knowledgeToolkitMarkedDone: Bool
    let lessonPlanMarkedDone: Bool
    let evaluationMarkedDone: Bool
}

struct EduWorkspaceAgentReviewTarget {
    enum ChangeKind {
        case add
        case update
        case delete
        case connect
        case disconnect
        case move

        var accentColor: Color {
            switch self {
            case .add, .connect:
                return .green
            case .update, .move:
                return .yellow
            case .delete, .disconnect:
                return .red
            }
        }
    }

    struct PreviewNode: Identifiable {
        enum Kind {
            case unchanged
            case add
            case update
            case delete

            var accentColor: Color {
                switch self {
                case .unchanged:
                    return .white.opacity(0.18)
                case .add:
                    return .green
                case .update:
                    return .orange
                case .delete:
                    return .red
                }
            }
        }

        let id: UUID
        let nodeType: String
        let canvasPosition: CGPoint
        let title: String
        let subtitle: String?
        let detailLines: [String]
        let kind: Kind
        let isGhost: Bool
        let isCurrentFocus: Bool
        let shape: NodeVisualShape
        let backgroundColor: Color
        let topRightSystemImage: String?
        let topRightIconColor: Color
    }

    struct PreviewConnection: Identifiable {
        enum Kind {
            case unchanged
            case add
            case remove

            var accentColor: Color {
                switch self {
                case .unchanged:
                    return .white.opacity(0.26)
                case .add:
                    return .green
                case .remove:
                    return .red
                }
            }

            var dash: [CGFloat] {
                switch self {
                case .unchanged, .add:
                    return []
                case .remove:
                    return [10, 8]
                }
            }
        }

        let id: String
        let kind: Kind
        let fromCanvasPosition: CGPoint
        let toCanvasPosition: CGPoint
        let isCurrentFocus: Bool
    }

    let index: Int
    let total: Int
    let summary: String
    let nodeID: UUID?
    let position: CGPoint?
    let previewData: Data
    let changeKind: ChangeKind
    let nodes: [PreviewNode]
    let connections: [PreviewConnection]
}

private struct EduWorkspaceAgentNodeSnapshot {
    let serialized: SerializableNode
    let state: CanvasNodeState
}

private struct EduWorkspaceAgentCurrentStepDelta {
    let changeKind: EduWorkspaceAgentReviewTarget.ChangeKind
    let focusNodeID: UUID?
    let focusPosition: CGPoint?
    let focusedNodeIDs: Set<UUID>
    let focusedConnectionIDs: Set<String>
}

extension ContentView {
    func openWorkspaceAgent(for file: GNodeWorkspaceFile) {
        selectedFileID = file.id
        workspaceAgentSidebarFileID = file.id
    }

    func closeWorkspaceAgent() {
        workspaceAgentSidebarFileID = nil
    }

    func isWorkspaceAgentSidebarVisible(for file: GNodeWorkspaceFile) -> Bool {
        workspaceAgentSidebarFileID == file.id
    }

    func workspaceAgentSidebarWidth(for availableWidth: CGFloat) -> CGFloat {
        let targetWidth: CGFloat = 408
        let maxAllowedWidth = max(availableWidth - 24, 300)
        return min(targetWidth, maxAllowedWidth)
    }

    @ViewBuilder
    func workspaceAgentSidebar(
        file: GNodeWorkspaceFile,
        availableWidth: CGFloat,
        topPadding: CGFloat
    ) -> some View {
        let panelWidth = workspaceAgentSidebarWidth(for: availableWidth)
        let panelShape = RoundedRectangle(cornerRadius: 26, style: .continuous)

        HStack(spacing: 0) {
            Spacer(minLength: 0)

            EduWorkspaceAgentSheet(
                file: file,
                conversation: Binding(
                    get: { workspaceAgentConversationByFile[file.id] ?? [] },
                    set: { workspaceAgentConversationByFile[file.id] = $0 }
                ),
                pendingCanvasResponse: workspaceAgentPendingResponseByFile[file.id],
                onStorePendingCanvasResponse: { response in
                    storeWorkspaceAgentPendingResponse(fileID: file.id, response: response)
                },
                onApplyPendingCanvasResponse: {
                    applyWorkspaceAgentPendingResponse(file: file)
                },
                onDismissPendingCanvasResponse: {
                    dismissWorkspaceAgentPendingResponse(fileID: file.id)
                },
                canUndoLastApplied: !(agentGraphUndoStackByFile[file.id] ?? []).isEmpty,
                onUndoLastApplied: {
                    undoLastAgentGraphMutation(fileID: file.id)
                },
                onClose: {
                    closeWorkspaceAgent()
                }
            )
            .frame(width: panelWidth)
            .frame(maxHeight: .infinity)
            .background(.ultraThinMaterial, in: panelShape)
            .clipShape(panelShape)
            .overlay(
                panelShape
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
        }
        .padding(.top, max(topPadding, 12))
        .padding(.trailing, 12)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    func applyAgentGraphMutation(fileID: UUID, result: EduAgentGraphMutationResult) {
        if let file = workspaceFiles.first(where: { $0.id == fileID }) {
            pushAgentGraphUndo(file: file)
        }
        persistWorkspaceFileData(id: fileID, data: result.data)
        if let file = workspaceFiles.first(where: { $0.id == fileID }) {
            file.updatedAt = .now
            if EduPlanning.filledNodeCount(of: EduNodeType.knowledge, in: result.data) > 0 ||
                EduPlanning.filledToolkitNodeCount(in: result.data) > 0 {
                file.knowledgeToolkitMarkedDone = true
            }
            if EduPlanning.hasEvaluationDesign(in: result.data) {
                file.evaluationMarkedDone = true
            }
            try? modelContext.save()
        }

        if let focusNodeID = result.focusNodeID {
            selectedFileID = fileID
            selectionRequest = NodeEditorSelectionRequest(nodeID: focusNodeID)
        }
        if let focusPosition = result.focusPosition {
            cameraRequest = NodeEditorCameraRequest(canvasPosition: focusPosition)
        }

        if !result.appliedSummaries.isEmpty || !result.warnings.isEmpty {
            let summary = ([result.appliedSummaries.joined(separator: "\n"), result.warnings.joined(separator: "\n")])
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            lastPersistLog = summary
        }
    }

    func pushAgentGraphUndo(file: GNodeWorkspaceFile) {
        let fileID = file.id
        var stack = agentGraphUndoStackByFile[fileID] ?? []
        guard stack.last?.data != file.data else { return }
        stack.append(
            EduAgentGraphUndoSnapshot(
                data: file.data,
                knowledgeToolkitMarkedDone: file.knowledgeToolkitMarkedDone,
                lessonPlanMarkedDone: file.lessonPlanMarkedDone,
                evaluationMarkedDone: file.evaluationMarkedDone
            )
        )
        if stack.count > 20 {
            stack.removeFirst(stack.count - 20)
        }
        agentGraphUndoStackByFile[fileID] = stack
    }

    func undoLastAgentGraphMutation(fileID: UUID) {
        guard var stack = agentGraphUndoStackByFile[fileID],
              let previous = stack.popLast() else { return }
        agentGraphUndoStackByFile[fileID] = stack
        persistWorkspaceFileData(id: fileID, data: previous.data)
        if let file = workspaceFiles.first(where: { $0.id == fileID }) {
            file.updatedAt = .now
            file.knowledgeToolkitMarkedDone = previous.knowledgeToolkitMarkedDone
            file.lessonPlanMarkedDone = previous.lessonPlanMarkedDone
            file.evaluationMarkedDone = previous.evaluationMarkedDone
            try? modelContext.save()
        }
        lastPersistLog = "Undid last Agent graph change."
    }

    func updateWorkspaceAgentConversation(
        fileID: UUID,
        _ transform: (inout [EduAgentConversationMessage]) -> Void
    ) {
        var messages = workspaceAgentConversationByFile[fileID] ?? []
        transform(&messages)
        workspaceAgentConversationByFile[fileID] = messages
    }

    func markLatestWorkspaceAgentProposal(
        fileID: UUID,
        status: EduAgentProposalStatus
    ) {
        updateWorkspaceAgentConversation(fileID: fileID) { messages in
            guard let index = messages.indices.reversed().first(where: { messages[$0].hasPendingCanvasProposal }) else {
                return
            }
            messages[index].proposalStatus = status
        }
    }

    func storeWorkspaceAgentPendingResponse(fileID: UUID, response: EduAgentGraphOperationEnvelope) {
        guard !response.operations.isEmpty else {
            clearWorkspaceAgentPendingResponse(fileID: fileID)
            return
        }
        workspaceAgentPendingResponseByFile[fileID] = response
        workspaceAgentReviewIndexByFile[fileID] = 0
        previewCurrentWorkspaceAgentReview(fileID: fileID)
    }

    func clearWorkspaceAgentPendingResponse(fileID: UUID) {
        workspaceAgentPendingResponseByFile.removeValue(forKey: fileID)
        workspaceAgentReviewIndexByFile.removeValue(forKey: fileID)
    }

    func dismissWorkspaceAgentPendingResponse(fileID: UUID) {
        markLatestWorkspaceAgentProposal(fileID: fileID, status: .dismissed)
        clearWorkspaceAgentPendingResponse(fileID: fileID)
    }

    func currentWorkspaceAgentReviewTarget(for file: GNodeWorkspaceFile) -> EduWorkspaceAgentReviewTarget? {
        guard let response = workspaceAgentPendingResponseByFile[file.id],
              !response.operations.isEmpty else {
            return nil
        }
        let index = min(max(workspaceAgentReviewIndexByFile[file.id] ?? 0, 0), response.operations.count - 1)
        return buildWorkspaceAgentReviewTarget(
            file: file,
            operations: response.operations,
            selectedIndex: index
        )
    }

    func currentWorkspaceAgentPreviewData(for file: GNodeWorkspaceFile) -> Data? {
        currentWorkspaceAgentReviewTarget(for: file)?.previewData
    }

    func previewCurrentWorkspaceAgentReview(fileID: UUID) {
        guard let file = workspaceFiles.first(where: { $0.id == fileID }),
              let target = currentWorkspaceAgentReviewTarget(for: file) else { return }
        selectedFileID = fileID
        if let nodeID = target.nodeID {
            selectionRequest = NodeEditorSelectionRequest(nodeID: nodeID)
        } else {
            selectionRequest = nil
        }
        if let position = target.position {
            cameraRequest = NodeEditorCameraRequest(canvasPosition: position)
        }
    }

    func moveWorkspaceAgentReviewSelection(file: GNodeWorkspaceFile, delta: Int) {
        guard let response = workspaceAgentPendingResponseByFile[file.id],
              !response.operations.isEmpty else { return }
        let current = workspaceAgentReviewIndexByFile[file.id] ?? 0
        let next = min(max(current + delta, 0), response.operations.count - 1)
        guard next != current else { return }
        workspaceAgentReviewIndexByFile[file.id] = next
        previewCurrentWorkspaceAgentReview(fileID: file.id)
    }

    func applyWorkspaceAgentPendingResponse(file: GNodeWorkspaceFile) {
        guard let response = workspaceAgentPendingResponseByFile[file.id] else { return }
        do {
            let result = try EduAgentGraphMutationEngine.apply(operations: response.operations, to: file.data)
            applyAgentGraphMutation(fileID: file.id, result: result)
            markLatestWorkspaceAgentProposal(fileID: file.id, status: .applied)
            clearWorkspaceAgentPendingResponse(fileID: file.id)
        } catch {
            lastPersistLog = error.localizedDescription
        }
    }

    @ViewBuilder
    func workspaceAgentReviewBar(
        file: GNodeWorkspaceFile,
        target: EduWorkspaceAgentReviewTarget
    ) -> some View {
        let isSidebarVisible = isWorkspaceAgentSidebarVisible(for: file)
        let sidebarInset = isSidebarVisible ? 424.0 : 0.0
        let barMaxWidth = isSidebarVisible ? 388.0 : 500.0

        VStack {
            Spacer(minLength: 0)

            HStack(spacing: 12) {
                reviewBarArrowButton(systemImage: "chevron.left") {
                    moveWorkspaceAgentReviewSelection(file: file, delta: -1)
                }
                .disabled(target.index == 0)

                VStack(alignment: .leading, spacing: 4) {
                    Text(isChineseUI() ? "候选改动 \(target.index + 1)/\(target.total)" : "Change \(target.index + 1) / \(target.total)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(target.summary)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
                .frame(minWidth: 150, maxWidth: 220, alignment: .leading)

                reviewBarArrowButton(systemImage: "chevron.right") {
                    moveWorkspaceAgentReviewSelection(file: file, delta: 1)
                }
                .disabled(target.index >= target.total - 1)

                Button {
                    dismissWorkspaceAgentPendingResponse(fileID: file.id)
                } label: {
                    Text(isChineseUI() ? "清除" : "Clear")
                        .frame(minWidth: 88)
                        .frame(height: 46)
                }
                .buttonStyle(EduAgentActionButtonStyle(variant: .secondary))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

                Button {
                    applyWorkspaceAgentPendingResponse(file: file)
                } label: {
                    Text(isChineseUI() ? "应用" : "Apply")
                        .frame(minWidth: 88)
                        .frame(height: 46)
                }
                .buttonStyle(EduAgentActionButtonStyle(variant: .primary))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.24), radius: 14, y: 6)
            .frame(maxWidth: barMaxWidth)
            .padding(.trailing, sidebarInset)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    func reviewBarArrowButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.06), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func buildWorkspaceAgentReviewTarget(
        file: GNodeWorkspaceFile,
        operations: [EduAgentGraphOperation],
        selectedIndex: Int
    ) -> EduWorkspaceAgentReviewTarget? {
        guard let originalDocument = try? decodeDocument(from: file.data),
              let finalResult = simulatedMutationResult(from: file.data, applying: operations),
              let finalDocument = try? decodeDocument(from: finalResult.data) else {
            return nil
        }

        let selectedOperation = operations[selectedIndex]
        let previousDocument = selectedIndex == 0
            ? originalDocument
            : (simulatedDocument(from: file.data, applying: Array(operations.prefix(selectedIndex))) ?? originalDocument)
        let currentDocument = simulatedDocument(from: file.data, applying: Array(operations.prefix(selectedIndex + 1))) ?? finalDocument
        let delta = currentStepDelta(
            for: selectedOperation,
            previousDocument: previousDocument,
            currentDocument: currentDocument
        )

        return EduWorkspaceAgentReviewTarget(
            index: selectedIndex,
            total: operations.count,
            summary: canvasOperationPreview(
                selectedOperation,
                previousDocument: previousDocument,
                currentDocument: currentDocument
            ),
            nodeID: delta.focusNodeID,
            position: delta.focusPosition,
            previewData: annotatedPreviewData(
                originalDocument: originalDocument,
                simulatedDocument: finalDocument,
                focusedNodeIDs: delta.focusedNodeIDs,
                focusedConnectionIDs: delta.focusedConnectionIDs
            ) ?? finalResult.data,
            changeKind: delta.changeKind,
            nodes: buildPreviewNodes(
                originalDocument: originalDocument,
                simulatedDocument: finalDocument,
                focusedNodeIDs: delta.focusedNodeIDs,
                currentChangeKind: delta.changeKind
            ),
            connections: buildPreviewConnections(
                originalDocument: originalDocument,
                simulatedDocument: finalDocument,
                focusedConnectionIDs: delta.focusedConnectionIDs,
                currentChangeKind: delta.changeKind
            )
        )
    }

    private func canvasOperationPreview(
        _ operation: EduAgentGraphOperation,
        previousDocument: GNodeDocument,
        currentDocument: GNodeDocument
    ) -> String {
        let isChinese = isChineseUI()
        switch operation.op.lowercased() {
        case "add_node":
            let addedNodeID = currentDocument.nodes
                .first(where: { node in
                    !previousDocument.nodes.contains(where: { $0.id == node.id })
                })?.id
            let label = addedNodeID.flatMap { resolvedNodeTitle($0, in: currentDocument) }
                ?? normalizedCanvasOperationLabel(operation.title)
                ?? workspaceAgentNodeTypeTitle(operation.nodeType)
                ?? (isChinese ? "节点" : "node")
            return isChinese ? "新增节点：\(label)" : "Add node: \(label)"
        case "update_node":
            let label = changedNodeIDs(
                previousDocument: previousDocument,
                currentDocument: currentDocument,
                includePositionChange: false
            )
            .first
            .flatMap { resolvedNodeTitle($0, in: currentDocument) }
            ?? (isChinese ? "已有节点" : "existing node")
            return isChinese ? "修改节点：\(label)" : "Update node: \(label)"
        case "connect":
            let connectionKey = addedConnectionIDs(
                previousDocument: previousDocument,
                currentDocument: currentDocument
            ).first
            let source = connectionKey.flatMap { connectionKeySourceTitle($0, in: currentDocument) }
                ?? fallbackNodeReferenceLabel(operation.sourceNodeRef)
            let target = connectionKey.flatMap { connectionKeyTargetTitle($0, in: currentDocument) }
                ?? fallbackNodeReferenceLabel(operation.targetNodeRef)
            return isChinese ? "新增连线：\(source) -> \(target)" : "Add connection: \(source) -> \(target)"
        case "disconnect":
            let connectionKey = removedConnectionIDs(
                previousDocument: previousDocument,
                currentDocument: currentDocument
            ).first
            let source = connectionKey.flatMap { connectionKeySourceTitle($0, in: previousDocument) }
                ?? fallbackNodeReferenceLabel(operation.sourceNodeRef)
            let target = connectionKey.flatMap { connectionKeyTargetTitle($0, in: previousDocument) }
                ?? fallbackNodeReferenceLabel(operation.targetNodeRef)
            return isChinese ? "移除连线：\(source) -> \(target)" : "Remove connection: \(source) -> \(target)"
        case "move_node":
            let label = movedNodeIDs(
                previousDocument: previousDocument,
                currentDocument: currentDocument
            )
            .first
            .flatMap { resolvedNodeTitle($0, in: currentDocument) }
            ?? (isChinese ? "节点" : "node")
            return isChinese ? "移动节点：\(label)" : "Move node: \(label)"
        case "delete_node":
            let label = deletedNodeIDs(
                previousDocument: previousDocument,
                currentDocument: currentDocument
            )
            .first
            .flatMap { resolvedNodeTitle($0, in: previousDocument) }
            ?? (isChinese ? "节点" : "node")
            return isChinese ? "删除节点：\(label)" : "Delete node: \(label)"
        default:
            return operation.op
        }
    }

    @ViewBuilder
    func workspaceAgentCanvasPreviewOverlay(
        target: EduWorkspaceAgentReviewTarget,
        viewport: NodeEditorViewportSnapshot
    ) -> some View {
        EduWorkspaceAgentCanvasPreviewOverlay(
            target: target,
            viewport: viewport
        )
    }

    private func simulatedDocument(
        from originalData: Data,
        applying operations: [EduAgentGraphOperation]
    ) -> GNodeDocument? {
        guard let result = simulatedMutationResult(from: originalData, applying: operations) else {
            return nil
        }
        return try? decodeDocument(from: result.data)
    }

    private func simulatedMutationResult(
        from originalData: Data,
        applying operations: [EduAgentGraphOperation]
    ) -> EduAgentGraphMutationResult? {
        if operations.isEmpty {
            guard let document = try? decodeDocument(from: originalData) else { return nil }
            let focusNodeID = document.canvasState.last?.nodeID
            let focusPosition = focusNodeID.flatMap { nodeID in
                document.canvasState.first(where: { $0.nodeID == nodeID }).map {
                    CGPoint(x: $0.positionX, y: $0.positionY)
                }
            }
            return EduAgentGraphMutationResult(
                data: originalData,
                appliedSummaries: [],
                warnings: [],
                focusNodeID: focusNodeID,
                focusPosition: focusPosition
            )
        }
        return try? EduAgentGraphMutationEngine.apply(operations: operations, to: originalData)
    }

    private func currentStepDelta(
        for operation: EduAgentGraphOperation,
        previousDocument: GNodeDocument,
        currentDocument: GNodeDocument
    ) -> EduWorkspaceAgentCurrentStepDelta {
        switch operation.op.lowercased() {
        case "add_node":
            let focusedNodeIDs = Set(addedNodeIDs(
                previousDocument: previousDocument,
                currentDocument: currentDocument
            ))
            let focusNodeID = focusedNodeIDs.first
            return EduWorkspaceAgentCurrentStepDelta(
                changeKind: .add,
                focusNodeID: focusNodeID,
                focusPosition: focusNodeID.flatMap { canvasPosition(for: $0, in: currentDocument) },
                focusedNodeIDs: focusedNodeIDs,
                focusedConnectionIDs: []
            )
        case "update_node":
            var focusedNodeIDs = Set(changedNodeIDs(
                previousDocument: previousDocument,
                currentDocument: currentDocument,
                includePositionChange: false
            ))
            if focusedNodeIDs.isEmpty,
               let explicitNodeID = operation.nodeRef.flatMap(UUID.init(uuidString:)) {
                focusedNodeIDs.insert(explicitNodeID)
            }
            let focusNodeID = focusedNodeIDs.first
            return EduWorkspaceAgentCurrentStepDelta(
                changeKind: .update,
                focusNodeID: focusNodeID,
                focusPosition: focusNodeID.flatMap { canvasPosition(for: $0, in: currentDocument) },
                focusedNodeIDs: focusedNodeIDs,
                focusedConnectionIDs: []
            )
        case "delete_node":
            var focusedNodeIDs = Set(deletedNodeIDs(
                previousDocument: previousDocument,
                currentDocument: currentDocument
            ))
            let explicitNodeID = operation.nodeRef.flatMap(UUID.init(uuidString:))
            if focusedNodeIDs.isEmpty, let explicitNodeID {
                focusedNodeIDs.insert(explicitNodeID)
            }
            let focusNodeID = explicitNodeID ?? focusedNodeIDs.first
            return EduWorkspaceAgentCurrentStepDelta(
                changeKind: .delete,
                focusNodeID: nil,
                focusPosition: focusNodeID.flatMap { canvasPosition(for: $0, in: previousDocument) },
                focusedNodeIDs: focusedNodeIDs,
                focusedConnectionIDs: Set(removedConnectionIDs(
                    previousDocument: previousDocument,
                    currentDocument: currentDocument
                ))
            )
        case "move_node":
            var focusedNodeIDs = Set(movedNodeIDs(
                previousDocument: previousDocument,
                currentDocument: currentDocument
            ))
            if focusedNodeIDs.isEmpty,
               let explicitNodeID = operation.nodeRef.flatMap(UUID.init(uuidString:)) {
                focusedNodeIDs.insert(explicitNodeID)
            }
            let focusNodeID = focusedNodeIDs.first
            return EduWorkspaceAgentCurrentStepDelta(
                changeKind: .move,
                focusNodeID: focusNodeID,
                focusPosition: focusNodeID.flatMap { canvasPosition(for: $0, in: currentDocument) },
                focusedNodeIDs: focusedNodeIDs,
                focusedConnectionIDs: []
            )
        case "connect", "disconnect":
            var focusedConnectionIDs = Set(
                operation.op.lowercased() == "connect"
                    ? addedConnectionIDs(previousDocument: previousDocument, currentDocument: currentDocument)
                    : removedConnectionIDs(previousDocument: previousDocument, currentDocument: currentDocument)
            )
            let fallbackSourceID = operation.sourceNodeRef.flatMap(UUID.init(uuidString:))
            let fallbackTargetID = operation.targetNodeRef.flatMap(UUID.init(uuidString:))
            if focusedConnectionIDs.isEmpty,
               let fallbackSourceID,
               let fallbackTargetID {
                let document = operation.op.lowercased() == "connect" ? currentDocument : previousDocument
                let fallbackMatches = document.connections
                    .filter { $0.sourceNodeID == fallbackSourceID && $0.targetNodeID == fallbackTargetID }
                    .map(connectionID(for:))
                focusedConnectionIDs.formUnion(fallbackMatches)
            }
            let focusConnectionID = focusedConnectionIDs.first
            var focusedNodeIDs = Set(
                focusConnectionID.map {
                    nodeIDs(forConnectionID: $0)
                } ?? []
            )
            if focusedNodeIDs.isEmpty {
                if let fallbackSourceID { focusedNodeIDs.insert(fallbackSourceID) }
                if let fallbackTargetID { focusedNodeIDs.insert(fallbackTargetID) }
            }
            let focusPosition = focusConnectionID.flatMap {
                connectionMidpoint(for: $0, primary: currentDocument, fallback: previousDocument)
            }
            let focusNodeID = focusedNodeIDs.first
            return EduWorkspaceAgentCurrentStepDelta(
                changeKind: operation.op.lowercased() == "connect" ? .connect : .disconnect,
                focusNodeID: focusNodeID,
                focusPosition: focusPosition,
                focusedNodeIDs: focusedNodeIDs,
                focusedConnectionIDs: focusedConnectionIDs
            )
        default:
            return EduWorkspaceAgentCurrentStepDelta(
                changeKind: .update,
                focusNodeID: nil,
                focusPosition: nil,
                focusedNodeIDs: [],
                focusedConnectionIDs: []
            )
        }
    }

    private func buildPreviewNodes(
        originalDocument: GNodeDocument,
        simulatedDocument: GNodeDocument,
        focusedNodeIDs: Set<UUID>,
        currentChangeKind: EduWorkspaceAgentReviewTarget.ChangeKind
    ) -> [EduWorkspaceAgentReviewTarget.PreviewNode] {
        let originalSnapshots = nodeSnapshotsByID(in: originalDocument)
        let simulatedSnapshots = nodeSnapshotsByID(in: simulatedDocument)

        let liveNodes = simulatedSnapshots.values.map { snapshot in
            let kind: EduWorkspaceAgentReviewTarget.PreviewNode.Kind
            if originalSnapshots[snapshot.serialized.id] == nil {
                kind = .add
            } else if let original = originalSnapshots[snapshot.serialized.id],
                      nodeSignature(for: snapshot) != nodeSignature(for: original) ||
                      nodePosition(for: snapshot) != nodePosition(for: original) {
                kind = .update
            } else if currentChangeKind == .update && focusedNodeIDs.contains(snapshot.serialized.id) {
                kind = .update
            } else {
                kind = .unchanged
            }

            return makePreviewNode(
                from: snapshot,
                kind: kind,
                isGhost: false,
                isCurrentFocus: focusedNodeIDs.contains(snapshot.serialized.id)
            )
        }

        let deletedNodes = originalSnapshots.values
            .filter { simulatedSnapshots[$0.serialized.id] == nil }
            .map {
                makePreviewNode(
                    from: $0,
                    kind: .delete,
                    isGhost: true,
                    isCurrentFocus: focusedNodeIDs.contains($0.serialized.id)
                )
            }

        return (liveNodes + deletedNodes).sorted { lhs, rhs in
            if lhs.isGhost != rhs.isGhost {
                return !lhs.isGhost
            }
            if lhs.canvasPosition.x == rhs.canvasPosition.x {
                return lhs.canvasPosition.y < rhs.canvasPosition.y
            }
            return lhs.canvasPosition.x < rhs.canvasPosition.x
        }
    }

    private func buildPreviewConnections(
        originalDocument: GNodeDocument,
        simulatedDocument: GNodeDocument,
        focusedConnectionIDs: Set<String>,
        currentChangeKind: EduWorkspaceAgentReviewTarget.ChangeKind
    ) -> [EduWorkspaceAgentReviewTarget.PreviewConnection] {
        let originalMap = Dictionary(uniqueKeysWithValues: originalDocument.connections.map { (connectionID(for: $0), $0) })
        let simulatedMap = Dictionary(uniqueKeysWithValues: simulatedDocument.connections.map { (connectionID(for: $0), $0) })

        let simulatedConnections = simulatedMap.map { connectionID, connection in
            makePreviewConnection(
                id: connectionID,
                connection: connection,
                kind: originalMap[connectionID] == nil || (currentChangeKind == .connect && focusedConnectionIDs.contains(connectionID))
                    ? .add
                    : .unchanged,
                positionDocument: simulatedDocument,
                fallbackDocument: originalDocument,
                isCurrentFocus: focusedConnectionIDs.contains(connectionID)
            )
        }

        let removedConnections = Array(originalMap).reduce(into: [EduWorkspaceAgentReviewTarget.PreviewConnection]()) { partial, entry in
            let (connectionID, connection) = entry
            guard simulatedMap[connectionID] == nil else { return }
            partial.append(
                makePreviewConnection(
                    id: connectionID,
                    connection: connection,
                    kind: .remove,
                    positionDocument: originalDocument,
                    fallbackDocument: simulatedDocument,
                    isCurrentFocus: focusedConnectionIDs.contains(connectionID)
                )
            )
        }

        return (simulatedConnections + removedConnections)
            .sorted { lhs, rhs in lhs.id < rhs.id }
    }

    private func annotatedPreviewData(
        originalDocument: GNodeDocument,
        simulatedDocument: GNodeDocument,
        focusedNodeIDs: Set<UUID>,
        focusedConnectionIDs: Set<String>
    ) -> Data? {
        let originalSnapshots = nodeSnapshotsByID(in: originalDocument)
        let simulatedSnapshots = nodeSnapshotsByID(in: simulatedDocument)
        let originalConnectionMap = Dictionary(uniqueKeysWithValues: originalDocument.connections.map { (connectionID(for: $0), $0) })
        let simulatedConnectionMap = Dictionary(uniqueKeysWithValues: simulatedDocument.connections.map { (connectionID(for: $0), $0) })

        var previewDocument = simulatedDocument
        previewDocument.nodes = simulatedDocument.nodes.compactMap { node in
            guard let snapshot = simulatedSnapshots[node.id] else { return nil }
            let previewState: String?
            if originalSnapshots[node.id] == nil {
                previewState = "add"
            } else if let originalSnapshot = originalSnapshots[node.id],
                      nodeSignature(for: snapshot) != nodeSignature(for: originalSnapshot) ||
                      nodePosition(for: snapshot) != nodePosition(for: originalSnapshot) {
                previewState = "update"
            } else {
                previewState = nil
            }
            return annotatedPreviewNode(
                node,
                previewState: previewState,
                isFocused: focusedNodeIDs.contains(node.id),
                isGhost: false
            )
        }

        var existingCanvasStateIDs = Set(previewDocument.canvasState.map(\.nodeID))
        for snapshot in originalSnapshots.values where simulatedSnapshots[snapshot.serialized.id] == nil {
            previewDocument.nodes.append(
                annotatedPreviewNode(
                    snapshot.serialized,
                    previewState: "delete",
                    isFocused: focusedNodeIDs.contains(snapshot.serialized.id),
                    isGhost: true
                )
            )
            if !existingCanvasStateIDs.contains(snapshot.serialized.id) {
                previewDocument.canvasState.append(snapshot.state)
                existingCanvasStateIDs.insert(snapshot.serialized.id)
            }
        }

        previewDocument.connections = simulatedDocument.connections.map { connection in
            let id = connectionID(for: connection)
            return annotatedPreviewConnection(
                connection,
                previewState: originalConnectionMap[id] == nil ? "add" : nil,
                isFocused: focusedConnectionIDs.contains(id)
            )
        }

        for (id, connection) in originalConnectionMap where simulatedConnectionMap[id] == nil {
            previewDocument.connections.append(
                annotatedPreviewConnection(
                    connection,
                    previewState: "remove",
                    isFocused: focusedConnectionIDs.contains(id)
                )
            )
        }

        return try? encodeDocument(previewDocument)
    }

    private func annotatedPreviewNode(
        _ node: SerializableNode,
        previewState: String?,
        isFocused: Bool,
        isGhost: Bool
    ) -> SerializableNode {
        var nodeData = node.nodeData
        nodeData.removeValue(forKey: NodeEditorPreviewMetadata.nodeStateKey)
        nodeData.removeValue(forKey: NodeEditorPreviewMetadata.nodeFocusKey)
        nodeData.removeValue(forKey: NodeEditorPreviewMetadata.nodeGhostKey)
        if let previewState {
            nodeData[NodeEditorPreviewMetadata.nodeStateKey] = previewState
        }
        if isFocused {
            nodeData[NodeEditorPreviewMetadata.nodeFocusKey] = "true"
        }
        if isGhost {
            nodeData[NodeEditorPreviewMetadata.nodeGhostKey] = "true"
        }
        return SerializableNode(
            id: node.id,
            nodeType: node.nodeType,
            attributes: node.attributes,
            inputPorts: node.inputPorts,
            outputPorts: node.outputPorts,
            nodeData: nodeData
        )
    }

    private func annotatedPreviewConnection(
        _ connection: NodeConnection,
        previewState: String?,
        isFocused: Bool
    ) -> NodeConnection {
        NodeConnection(
            id: connection.id,
            sourceNode: connection.sourceNodeID,
            sourcePort: connection.sourcePortID,
            targetNode: connection.targetNodeID,
            targetPort: connection.targetPortID,
            dataType: connection.dataType,
            previewState: previewState,
            previewIsFocused: isFocused ? true : nil
        )
    }

    private func normalizedCanvasOperationLabel(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func fallbackNodeReferenceLabel(_ ref: String?) -> String {
        let trimmed = ref?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            return isChineseUI() ? "节点" : "node"
        }
        if UUID(uuidString: trimmed) != nil {
            return isChineseUI() ? "节点" : "node"
        }
        return trimmed
    }

    private func nodeSnapshotsByID(in document: GNodeDocument) -> [UUID: EduWorkspaceAgentNodeSnapshot] {
        let stateByID = Dictionary(uniqueKeysWithValues: document.canvasState.map { ($0.nodeID, $0) })
        return document.nodes.reduce(into: [UUID: EduWorkspaceAgentNodeSnapshot]()) { partial, node in
            guard let state = stateByID[node.id] else { return }
            partial[node.id] = EduWorkspaceAgentNodeSnapshot(serialized: node, state: state)
        }
    }

    private func nodeSignature(for snapshot: EduWorkspaceAgentNodeSnapshot) -> String {
        let node = snapshot.serialized
        let customName = snapshot.state.customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let nodeData = node.nodeData.keys.sorted().map { key in
            "\(key)=\(node.nodeData[key] ?? "")"
        }
        let inputPorts = node.inputPorts.map(\.name).joined(separator: "|")
        let outputPorts = node.outputPorts.map(\.name).joined(separator: "|")
        return [
            node.nodeType,
            node.attributes.name,
            customName,
            nodeData.joined(separator: ";"),
            inputPorts,
            outputPorts
        ]
        .joined(separator: "||")
    }

    private func nodePosition(for snapshot: EduWorkspaceAgentNodeSnapshot) -> CGPoint {
        CGPoint(x: snapshot.state.positionX, y: snapshot.state.positionY)
    }

    private func addedNodeIDs(
        previousDocument: GNodeDocument,
        currentDocument: GNodeDocument
    ) -> [UUID] {
        let previousIDs = Set(previousDocument.nodes.map(\.id))
        return currentDocument.nodes.map(\.id).filter { !previousIDs.contains($0) }
    }

    private func deletedNodeIDs(
        previousDocument: GNodeDocument,
        currentDocument: GNodeDocument
    ) -> [UUID] {
        let currentIDs = Set(currentDocument.nodes.map(\.id))
        return previousDocument.nodes.map(\.id).filter { !currentIDs.contains($0) }
    }

    private func movedNodeIDs(
        previousDocument: GNodeDocument,
        currentDocument: GNodeDocument
    ) -> [UUID] {
        let previousStateByID = Dictionary(uniqueKeysWithValues: previousDocument.canvasState.map { ($0.nodeID, $0) })
        let currentStateByID = Dictionary(uniqueKeysWithValues: currentDocument.canvasState.map { ($0.nodeID, $0) })
        return currentDocument.nodes.compactMap { node in
            guard let previous = previousStateByID[node.id],
                  let current = currentStateByID[node.id] else { return nil }
            let previousPoint = CGPoint(x: previous.positionX, y: previous.positionY)
            let currentPoint = CGPoint(x: current.positionX, y: current.positionY)
            return previousPoint == currentPoint ? nil : node.id
        }
    }

    private func changedNodeIDs(
        previousDocument: GNodeDocument,
        currentDocument: GNodeDocument,
        includePositionChange: Bool
    ) -> [UUID] {
        let previousSnapshots = nodeSnapshotsByID(in: previousDocument)
        let currentSnapshots = nodeSnapshotsByID(in: currentDocument)
        return currentDocument.nodes.compactMap { node in
            guard let previous = previousSnapshots[node.id],
                  let current = currentSnapshots[node.id] else { return nil }
            if nodeSignature(for: previous) != nodeSignature(for: current) {
                return node.id
            }
            if includePositionChange, nodePosition(for: previous) != nodePosition(for: current) {
                return node.id
            }
            return nil
        }
    }

    private func addedConnectionIDs(
        previousDocument: GNodeDocument,
        currentDocument: GNodeDocument
    ) -> [String] {
        let previousIDs = Set(previousDocument.connections.map(connectionID(for:)))
        return currentDocument.connections
            .map(connectionID(for:))
            .filter { !previousIDs.contains($0) }
    }

    private func removedConnectionIDs(
        previousDocument: GNodeDocument,
        currentDocument: GNodeDocument
    ) -> [String] {
        let currentIDs = Set(currentDocument.connections.map(connectionID(for:)))
        return previousDocument.connections
            .map(connectionID(for:))
            .filter { !currentIDs.contains($0) }
    }

    private func makePreviewNode(
        from snapshot: EduWorkspaceAgentNodeSnapshot,
        kind: EduWorkspaceAgentReviewTarget.PreviewNode.Kind,
        isGhost: Bool,
        isCurrentFocus: Bool
    ) -> EduWorkspaceAgentReviewTarget.PreviewNode {
        let style = NodeVisualStyleRegistry.style(for: snapshot.serialized.nodeType)
        let detail = previewNodeDetail(for: snapshot.serialized)
        return EduWorkspaceAgentReviewTarget.PreviewNode(
            id: snapshot.serialized.id,
            nodeType: snapshot.serialized.nodeType,
            canvasPosition: CGPoint(x: snapshot.state.positionX, y: snapshot.state.positionY),
            title: resolvedNodeTitle(in: snapshot),
            subtitle: detail.subtitle,
            detailLines: detail.lines,
            kind: kind,
            isGhost: isGhost,
            isCurrentFocus: isCurrentFocus,
            shape: style?.shape ?? .rounded,
            backgroundColor: style?.backgroundColor ?? Color(white: 0.18),
            topRightSystemImage: style?.topRightSystemImage,
            topRightIconColor: style?.topRightIconColor ?? .white.opacity(0.82)
        )
    }

    private func makePreviewConnection(
        id: String,
        connection: NodeConnection,
        kind: EduWorkspaceAgentReviewTarget.PreviewConnection.Kind,
        positionDocument: GNodeDocument,
        fallbackDocument: GNodeDocument,
        isCurrentFocus: Bool
    ) -> EduWorkspaceAgentReviewTarget.PreviewConnection {
        let sourcePosition = canvasPosition(for: connection.sourceNodeID, in: positionDocument)
            ?? canvasPosition(for: connection.sourceNodeID, in: fallbackDocument)
            ?? .zero
        let targetPosition = canvasPosition(for: connection.targetNodeID, in: positionDocument)
            ?? canvasPosition(for: connection.targetNodeID, in: fallbackDocument)
            ?? .zero
        return EduWorkspaceAgentReviewTarget.PreviewConnection(
            id: id,
            kind: kind,
            fromCanvasPosition: sourcePosition,
            toCanvasPosition: targetPosition,
            isCurrentFocus: isCurrentFocus
        )
    }

    private func previewNodeDetail(
        for serialized: SerializableNode
    ) -> (subtitle: String?, lines: [String]) {
        guard let liveNode = try? deserializeNode(serialized) else {
            return (workspaceAgentNodeTypeTitle(serialized.nodeType), [])
        }

        var lines: [String] = []
        var subtitle = workspaceAgentNodeTypeTitle(serialized.nodeType)

        if let methodSelectable = liveNode as? any NodeMethodSelectable,
           let toolkitCategory = EduToolkitCategory.fromNodeType(serialized.nodeType) {
            subtitle = toolkitCategory.localizedMethodTitle(for: methodSelectable.editorSelectedMethodID)
        } else if let optionSelectable = liveNode as? any NodeOptionSelectable {
            let option = optionSelectable.editorSelectedOption.trimmingCharacters(in: .whitespacesAndNewlines)
            if !option.isEmpty {
                subtitle = option
            }
        }

        if let textEditable = liveNode as? any NodeTextEditable {
            let text = textEditable.editorTextValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                lines.append(previewTextSnippet(text, limit: 80))
            }
        }

        if let formEditable = liveNode as? any NodeFormEditable {
            for field in formEditable.editorFormOptionFields {
                let value = field.selectedOption.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else { continue }
                lines.append("\(field.label): \(previewTextSnippet(value, limit: 44))")
            }

            for field in formEditable.editorFormTextFields {
                let value = field.value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else { continue }
                lines.append("\(field.label): \(previewTextSnippet(value, limit: 52))")
            }
        }

        return (subtitle, Array(lines.prefix(3)))
    }

    private func previewTextSnippet(_ text: String, limit: Int) -> String {
        let normalized = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > limit else { return normalized }
        let index = normalized.index(normalized.startIndex, offsetBy: limit)
        return String(normalized[..<index]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private func resolvedNodeTitle(in snapshot: EduWorkspaceAgentNodeSnapshot) -> String {
        let custom = snapshot.state.customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return custom.isEmpty ? snapshot.serialized.attributes.name : custom
    }

    private func resolvedNodeTitle(_ nodeID: UUID, in document: GNodeDocument) -> String {
        let stateByID = Dictionary(uniqueKeysWithValues: document.canvasState.map { ($0.nodeID, $0) })
        let custom = stateByID[nodeID]?.customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !custom.isEmpty {
            return custom
        }
        return document.nodes.first(where: { $0.id == nodeID })?.attributes.name ?? nodeID.uuidString
    }

    private func canvasPosition(for nodeID: UUID, in document: GNodeDocument) -> CGPoint? {
        document.canvasState.first(where: { $0.nodeID == nodeID }).map {
            CGPoint(x: $0.positionX, y: $0.positionY)
        }
    }

    private func connectionID(for connection: NodeConnection) -> String {
        [
            connection.sourceNodeID.uuidString,
            connection.sourcePortID.uuidString,
            connection.targetNodeID.uuidString,
            connection.targetPortID.uuidString
        ]
        .joined(separator: "->")
    }

    private func nodeIDs(forConnectionID connectionID: String) -> [UUID] {
        connectionID
            .components(separatedBy: "->")
            .prefix(4)
            .enumerated()
            .compactMap { index, value in
                guard index == 0 || index == 2 else { return nil }
                return UUID(uuidString: value)
            }
    }

    private func connectionKeySourceTitle(_ connectionID: String, in document: GNodeDocument) -> String? {
        nodeIDs(forConnectionID: connectionID).first.map { resolvedNodeTitle($0, in: document) }
    }

    private func connectionKeyTargetTitle(_ connectionID: String, in document: GNodeDocument) -> String? {
        nodeIDs(forConnectionID: connectionID).dropFirst().first.map { resolvedNodeTitle($0, in: document) }
    }

    private func connectionMidpoint(
        for connectionID: String,
        primary: GNodeDocument,
        fallback: GNodeDocument
    ) -> CGPoint? {
        let ids = nodeIDs(forConnectionID: connectionID)
        guard ids.count == 2 else { return nil }
        guard let source = canvasPosition(for: ids[0], in: primary) ?? canvasPosition(for: ids[0], in: fallback),
              let target = canvasPosition(for: ids[1], in: primary) ?? canvasPosition(for: ids[1], in: fallback) else {
            return nil
        }
        return CGPoint(x: (source.x + target.x) / 2, y: (source.y + target.y) / 2)
    }

    private func workspaceAgentNodeTypeTitle(_ nodeType: String?) -> String? {
        guard let nodeType else { return nil }
        switch nodeType {
        case EduNodeType.knowledge:
            return S("menu.node.knowledge")
        case EduNodeType.evaluation:
            return S("menu.node.evaluation")
        case EduNodeType.toolkitPerceptionInquiry:
            return S("menu.node.perceptionInquiry")
        case EduNodeType.toolkitConstructionPrototype:
            return S("menu.node.constructionPrototype")
        case EduNodeType.toolkitCommunicationNegotiation:
            return S("menu.node.communicationNegotiation")
        case EduNodeType.toolkitRegulationMetacognition:
            return S("menu.node.regulationMetacognition")
        default:
            let trimmed = nodeType.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    func applyPresentationAgentOverrides(
        fileID: UUID,
        slideGroupIDBySlideID: [UUID: UUID],
        overridesBySlideID: [UUID: [PresentationNativeElement: String]]
    ) {
        let groupedOverrides = overridesBySlideID.reduce(into: [UUID: [PresentationNativeElement: String]]()) { partial, entry in
            guard let groupID = slideGroupIDBySlideID[entry.key] else { return }
            partial[groupID, default: [:]].merge(entry.value) { _, new in new }
        }

        guard !groupedOverrides.isEmpty else { return }

        for (groupID, overrides) in groupedOverrides {
            pushPresentationStylingUndo(fileID: fileID, groupID: groupID)
            mutatePresentationStylingState(fileID: fileID, groupID: groupID) { state in
                for (element, content) in overrides {
                    let normalized = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    if normalized.isEmpty {
                        state.nativeContentOverrides.removeValue(forKey: element)
                    } else {
                        state.nativeContentOverrides[element] = normalized
                    }
                }
            }
        }

        presentationStylingTouchedFileIDs.insert(fileID)
        persistPresentationState(fileID: fileID)
    }
}

private struct EduWorkspaceAgentCanvasPreviewOverlay: View {
    let target: EduWorkspaceAgentReviewTarget
    let viewport: NodeEditorViewportSnapshot

    @State private var pulse = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.16)

            ForEach(target.connections) { preview in
                connectionOverlay(preview)
            }

            ForEach(target.nodes) { preview in
                nodeOverlay(preview)
            }
        }
        .frame(
            width: viewport.viewportSize.width,
            height: viewport.viewportSize.height,
            alignment: .topLeading
        )
        .onAppear {
            guard !pulse else { return }
            withAnimation(.easeInOut(duration: 0.95).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private func nodeOverlay(_ preview: EduWorkspaceAgentReviewTarget.PreviewNode) -> some View {
        let point = screenPoint(for: preview.canvasPosition)
        let zoom = min(max(viewport.scale, 0.72), 1.0)
        let width = nodeWidth(for: preview, zoom: zoom)
        let accent = preview.kind.accentColor
        let fillOpacity: Double = switch preview.kind {
        case .unchanged:
            preview.isGhost ? 0.22 : 0.94
        case .add:
            0.95
        case .update:
            0.95
        case .delete:
            0.42
        }
        let strokeOpacity = preview.kind == .unchanged
            ? (preview.isCurrentFocus ? (pulse ? 0.9 : 0.74) : 0.22)
            : (preview.isCurrentFocus ? 1.0 : 0.98)
        let lineWidth = preview.kind == .unchanged
            ? (preview.isCurrentFocus ? 2.6 * zoom : 1.15 * zoom)
            : (preview.isCurrentFocus ? 3.8 * zoom : 3.0 * zoom)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let icon = preview.topRightSystemImage {
                    Image(systemName: icon)
                        .font(.system(size: 11 * zoom, weight: .semibold))
                        .foregroundStyle(preview.topRightIconColor.opacity(preview.isGhost ? 0.7 : 0.92))
                }
                Text(preview.title)
                    .font(.system(size: 12 * zoom, weight: .semibold))
                    .foregroundStyle(.white.opacity(preview.isGhost ? 0.82 : 0.96))
                    .lineLimit(2)
                Spacer(minLength: 0)
            }

            if let subtitle = preview.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 10 * zoom, weight: .medium))
                    .foregroundStyle(.white.opacity(preview.isGhost ? 0.58 : 0.68))
                    .lineLimit(1)
            }

            ForEach(Array(preview.detailLines.prefix(3).enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 10 * zoom))
                    .foregroundStyle(.white.opacity(preview.isGhost ? 0.54 : 0.78))
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 12 * zoom)
        .padding(.vertical, 10 * zoom)
        .frame(width: width, alignment: .topLeading)
        .background(nodeBackgroundShape(for: preview).fill(preview.backgroundColor.opacity(fillOpacity)))
        .overlay(
            nodeBackgroundShape(for: preview)
                .stroke(
                    accent.opacity(strokeOpacity),
                    style: StrokeStyle(
                        lineWidth: lineWidth,
                        dash: preview.kind == .delete ? [8 * zoom, 5 * zoom] : []
                    )
                )
        )
        .overlay {
            if preview.kind != .unchanged {
                nodeBackgroundShape(for: preview)
                    .stroke(accent.opacity(preview.isCurrentFocus ? 0.32 : 0.22), lineWidth: 1.2 * zoom)
                    .padding(2.2 * zoom)
            }
        }
        .overlay {
            if preview.isCurrentFocus {
                nodeBackgroundShape(for: preview)
                    .stroke(accent.opacity(pulse ? 0.34 : 0.18), lineWidth: 10 * zoom)
                    .blur(radius: 4 * zoom)
            }
        }
        .clipShape(nodeBackgroundShape(for: preview))
        .shadow(
            color: accent.opacity(preview.isCurrentFocus ? 0.34 : (preview.kind == .unchanged ? 0.0 : 0.14)),
            radius: preview.isCurrentFocus ? 14 * zoom : 8 * zoom,
            y: 4 * zoom
        )
        .opacity(preview.kind == .delete ? 0.34 : (preview.isGhost ? 0.72 : 0.96))
        .position(x: point.x, y: point.y)
    }

    private func connectionOverlay(_ preview: EduWorkspaceAgentReviewTarget.PreviewConnection) -> some View {
        let start = screenPoint(for: preview.fromCanvasPosition)
        let end = screenPoint(for: preview.toCanvasPosition)
        let dx = abs(end.x - start.x)
        let controlOffset = max(56, dx * 0.32)
        let accent = preview.kind.accentColor
        let lineWidth: CGFloat = preview.kind == .unchanged ? 2 : (preview.isCurrentFocus ? 4.8 : 3.6)
        let strokeOpacity = preview.kind == .unchanged ? 0.34 : (preview.isCurrentFocus ? (pulse ? 1.0 : 0.88) : 0.8)

        return Path { path in
            path.move(to: start)
            path.addCurve(
                to: end,
                control1: CGPoint(x: start.x + controlOffset, y: start.y),
                control2: CGPoint(x: end.x - controlOffset, y: end.y)
            )
        }
        .stroke(
            accent.opacity(strokeOpacity),
            style: StrokeStyle(
                lineWidth: lineWidth,
                lineCap: .round,
                lineJoin: .round,
                dash: preview.kind.dash
            )
        )
        .overlay {
            if preview.kind != .unchanged {
                Path { path in
                    path.move(to: start)
                    path.addCurve(
                        to: end,
                        control1: CGPoint(x: start.x + controlOffset, y: start.y),
                        control2: CGPoint(x: end.x - controlOffset, y: end.y)
                    )
                }
                .stroke(accent.opacity(preview.isCurrentFocus ? 0.36 : 0.24), lineWidth: lineWidth + 4)
                .blur(radius: preview.isCurrentFocus ? 5 : 3)
            }
        }
        .overlay {
            if preview.kind != .unchanged {
                Circle()
                    .fill(accent.opacity(preview.isCurrentFocus ? 0.96 : 0.84))
                    .frame(width: preview.isCurrentFocus ? 11 : 9, height: preview.isCurrentFocus ? 11 : 9)
                    .shadow(color: accent.opacity(0.35), radius: 4)
                    .position(start)

                Circle()
                    .fill(accent.opacity(preview.isCurrentFocus ? 0.96 : 0.84))
                    .frame(width: preview.isCurrentFocus ? 11 : 9, height: preview.isCurrentFocus ? 11 : 9)
                    .shadow(color: accent.opacity(0.35), radius: 4)
                    .position(end)
            }
        }
        .shadow(color: accent.opacity(preview.isCurrentFocus ? 0.36 : 0.20), radius: preview.isCurrentFocus ? 12 : 6)
        .opacity(preview.kind == .unchanged ? 0.62 : 1.0)
    }

    private func screenPoint(for canvasPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: canvasPoint.x * viewport.scale + viewport.offset.width,
            y: canvasPoint.y * viewport.scale + viewport.offset.height
        )
    }

    private func nodeWidth(
        for preview: EduWorkspaceAgentReviewTarget.PreviewNode,
        zoom: CGFloat
    ) -> CGFloat {
        let base: CGFloat = (preview.nodeType == EduNodeType.evaluation ? 312 : 232) * zoom
        if preview.detailLines.count >= 3 {
            return base + 42 * zoom
        }
        return base
    }

    private func nodeBackgroundShape(
        for preview: EduWorkspaceAgentReviewTarget.PreviewNode
    ) -> EduWorkspaceAgentPreviewShape {
        EduWorkspaceAgentPreviewShape(kind: preview.shape)
    }
}

private struct EduWorkspaceAgentPreviewShape: InsettableShape {
    let kind: NodeVisualShape
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        switch kind {
        case .capsule:
            return Capsule(style: .continuous)
                .inset(by: insetAmount)
                .path(in: rect)
        case .rounded:
            return RoundedRectangle(cornerRadius: 18, style: .continuous)
                .inset(by: insetAmount)
                .path(in: rect)
        }
    }

    func inset(by amount: CGFloat) -> EduWorkspaceAgentPreviewShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}
