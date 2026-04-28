import Foundation
import CoreGraphics
import GNodeKit

struct EduAgentGraphMutationResult {
    let data: Data
    let appliedSummaries: [String]
    let warnings: [String]
    let focusNodeID: UUID?
    let focusPosition: CGPoint?
}

enum EduAgentGraphOperationNormalizer {
    static func normalize(
        envelope: EduAgentGraphOperationEnvelope,
        userRequest: String
    ) -> EduAgentGraphOperationEnvelope {
        EduAgentGraphOperationEnvelope(
            assistantReply: envelope.assistantReply,
            thinkingTraceMarkdown: envelope.thinkingTraceMarkdown,
            operations: envelope.operations.map { normalize(operation: $0, userRequest: userRequest) }
        )
    }

    private static func normalize(
        operation: EduAgentGraphOperation,
        userRequest: String
    ) -> EduAgentGraphOperation {
        let opKind = operation.op.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard opKind == "add_node" || opKind == "update_node" else {
            return operation
        }

        let semantic = semanticText(for: operation, userRequest: userRequest)
        let inferred = inferredSemanticTarget(from: semantic)
        guard let inferred else {
            return operation
        }

        let currentNodeType = operation.nodeType.flatMap { EduAgentGraphMutationEngine.resolvedNodeType(from: $0) }
        let normalizedNodeType = inferred.nodeType

        let shouldReplaceNodeType =
            currentNodeType == nil ||
            currentNodeType == EduNodeType.knowledge ||
            currentNodeType != normalizedNodeType

        guard shouldReplaceNodeType else {
            return operation
        }

        var optionFieldValues = operation.optionFieldValues ?? [:]
        inferred.optionFieldValues.forEach { key, value in
            optionFieldValues[key] = value
        }

        var textFieldValues = operation.textFieldValues ?? [:]
        inferred.textFieldValues.forEach { key, value in
            if textFieldValues[key]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                textFieldValues[key] = value
            }
        }

        let preservedSelectedOption = currentNodeType == normalizedNodeType ? operation.selectedOption : nil

        return EduAgentGraphOperation(
            op: operation.op,
            tempID: operation.tempID,
            nodeRef: operation.nodeRef,
            sourceNodeRef: operation.sourceNodeRef,
            targetNodeRef: operation.targetNodeRef,
            nodeType: normalizedNodeType,
            title: operation.title,
            textValue: operation.textValue,
            selectedOption: preservedSelectedOption,
            selectedMethodID: inferred.selectedMethodID ?? operation.selectedMethodID,
            textFieldValues: textFieldValues.isEmpty ? nil : textFieldValues,
            optionFieldValues: optionFieldValues.isEmpty ? nil : optionFieldValues,
            anchorNodeRef: operation.anchorNodeRef,
            placement: operation.placement,
            sourcePortName: operation.sourcePortName,
            targetPortName: operation.targetPortName,
            positionX: operation.positionX,
            positionY: operation.positionY
        )
    }

    private static func semanticText(
        for operation: EduAgentGraphOperation,
        userRequest: String
    ) -> String {
        [
            userRequest,
            operation.title,
            operation.textValue,
            operation.selectedOption,
            operation.selectedMethodID,
            operation.textFieldValues?.values.joined(separator: " "),
            operation.optionFieldValues?.values.joined(separator: " ")
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
        .lowercased()
    }

    private static func inferredSemanticTarget(from semantic: String) -> SemanticTarget? {
        if semantic.contains(anyOf: evaluationTokens) {
            return SemanticTarget(nodeType: EduNodeType.evaluation)
        }

        if semantic.contains(anyOf: reflectionTokens) {
            return SemanticTarget(
                nodeType: EduNodeType.toolkitRegulationMetacognition,
                selectedMethodID: "reflection_protocol"
            )
        }

        if semantic.contains(anyOf: rolePlayTokens) {
            return SemanticTarget(
                nodeType: EduNodeType.toolkitCommunicationNegotiation,
                selectedMethodID: "role_play"
            )
        }

        if semantic.contains(anyOf: gameTokens) {
            return SemanticTarget(
                nodeType: EduNodeType.toolkitCommunicationNegotiation,
                selectedMethodID: "game_mechanism"
            )
        }

        if semantic.contains(anyOf: discussionTokens) {
            return SemanticTarget(
                nodeType: EduNodeType.toolkitCommunicationNegotiation,
                selectedMethodID: "structured_debate"
            )
        }

        if semantic.contains(anyOf: classificationTokens),
           semantic.contains(anyOf: activityTokens + observationTokens + practiceTokens) {
            return SemanticTarget(
                nodeType: EduNodeType.toolkitPerceptionInquiry,
                selectedMethodID: "field_observation",
                optionFieldValues: ["field_obs_task_structure": "classification"]
            )
        }

        if semantic.contains(anyOf: observationTokens) {
            return SemanticTarget(
                nodeType: EduNodeType.toolkitPerceptionInquiry,
                selectedMethodID: "field_observation"
            )
        }

        if semantic.contains(anyOf: analysisTokens),
           !semantic.contains(anyOf: knowledgeContentTokens) {
            return SemanticTarget(
                nodeType: EduNodeType.toolkitPerceptionInquiry,
                selectedMethodID: "source_analysis"
            )
        }

        if semantic.contains(anyOf: activityTokens + practiceTokens),
           !semantic.contains(anyOf: knowledgeContentTokens) {
            return SemanticTarget(
                nodeType: EduNodeType.toolkitConstructionPrototype,
                selectedMethodID: "low_fidelity_prototype"
            )
        }

        return nil
    }

    private struct SemanticTarget {
        let nodeType: String
        var selectedMethodID: String? = nil
        var textFieldValues: [String: String] = [:]
        var optionFieldValues: [String: String] = [:]
    }

    private static let evaluationTokens = [
        "evaluation", "assessment", "quiz", "rubric", "checklist", "exit ticket", "评分", "打分", "测验", "评价", "评估", "反馈"
    ]

    private static let reflectionTokens = [
        "reflection", "reflect", "metacognition", "self-assessment", "peer review", "复盘", "反思", "自评", "互评", "回顾"
    ]

    private static let rolePlayTokens = [
        "role play", "role-play", "角色扮演", "模拟对话", "采访", "interview"
    ]

    private static let gameTokens = [
        "game", "gamified", "competition", "闯关", "游戏", "竞赛"
    ]

    private static let discussionTokens = [
        "discussion", "debate", "share", "presentation", "brainstorm", "汇报", "讨论", "辩论", "分享", "协商"
    ]

    private static let classificationTokens = [
        "classification", "classify", "sort", "分类", "归类", "辨认"
    ]

    private static let observationTokens = [
        "observation", "observe", "field note", "compare", "comparison", "identify", "观察", "对比", "比较", "识别"
    ]

    private static let analysisTokens = [
        "analysis", "analyze", "analyse", "source", "evidence", "文本分析", "分析", "证据"
    ]

    private static let activityTokens = [
        "activity", "task", "exercise", "practice", "worksheet", "活动", "任务", "练习", "工作单"
    ]

    private static let practiceTokens = [
        "drill", "prototype", "build", "make", "创作", "制作", "建构", "演练"
    ]

    private static let knowledgeContentTokens = [
        "knowledge", "concept", "definition", "theory", "vocabulary", "知识", "概念", "定义", "原理", "术语", "词汇"
    ]
}

enum EduAgentGraphMutationEngine {
    static func apply(
        operations: [EduAgentGraphOperation],
        to graphData: Data
    ) throws -> EduAgentGraphMutationResult {
        guard var document = try? decodeDocument(from: graphData) else {
            throw EduAgentClientError.invalidStructuredResponse
        }

        var tempNodeIDs: [String: UUID] = [:]
        var applied: [String] = []
        var warnings: [String] = []
        var focusNodeID: UUID?

        for operation in operations.prefix(18) {
            switch operation.op.lowercased() {
            case "add_node":
                if let summary = applyAddNode(
                    operation,
                    to: &document,
                    tempNodeIDs: &tempNodeIDs,
                    warnings: &warnings,
                    focusNodeID: &focusNodeID
                ) {
                    applied.append(summary)
                }
            case "update_node":
                if let summary = applyUpdateNode(
                    operation,
                    to: &document,
                    tempNodeIDs: tempNodeIDs,
                    warnings: &warnings,
                    focusNodeID: &focusNodeID
                ) {
                    applied.append(summary)
                }
            case "connect":
                if let summary = applyConnect(
                    operation,
                    to: &document,
                    tempNodeIDs: tempNodeIDs,
                    warnings: &warnings,
                    focusNodeID: &focusNodeID
                ) {
                    applied.append(summary)
                }
            case "disconnect":
                if let summary = applyDisconnect(
                    operation,
                    to: &document,
                    tempNodeIDs: tempNodeIDs,
                    warnings: &warnings,
                    focusNodeID: &focusNodeID
                ) {
                    applied.append(summary)
                }
            case "move_node":
                if let summary = applyMoveNode(
                    operation,
                    to: &document,
                    tempNodeIDs: tempNodeIDs,
                    warnings: &warnings,
                    focusNodeID: &focusNodeID
                ) {
                    applied.append(summary)
                }
            case "delete_node":
                if let summary = applyDeleteNode(
                    operation,
                    to: &document,
                    tempNodeIDs: tempNodeIDs,
                    warnings: &warnings,
                    focusNodeID: &focusNodeID
                ) {
                    applied.append(summary)
                }
            default:
                warnings.append("Unsupported op: \(operation.op)")
            }
        }

        document.metadata.modifiedAt = .now
        let data = try encodeDocument(document)
        let focusPosition = focusNodeID.flatMap { nodeID in
            document.canvasState.first(where: { $0.nodeID == nodeID }).map {
                CGPoint(x: $0.positionX, y: $0.positionY)
            }
        }
        return EduAgentGraphMutationResult(
            data: data,
            appliedSummaries: applied,
            warnings: warnings,
            focusNodeID: focusNodeID,
            focusPosition: focusPosition
        )
    }

    private static func applyAddNode(
        _ operation: EduAgentGraphOperation,
        to document: inout GNodeDocument,
        tempNodeIDs: inout [String: UUID],
        warnings: inout [String],
        focusNodeID: inout UUID?
    ) -> String? {
        guard let rawType = operation.nodeType,
              let resolvedType = resolvedNodeType(from: rawType),
              let liveNode = GNodeNodeKit.gnodeNodeKit.createNode(type: resolvedType) else {
            warnings.append("Unable to create node for type: \(operation.nodeType ?? "nil")")
            return nil
        }

        configure(
            node: liveNode,
            resolvedType: resolvedType,
            title: operation.title,
            textValue: operation.textValue,
            selectedOption: operation.selectedOption,
            selectedMethodID: operation.selectedMethodID,
            textFieldValues: operation.textFieldValues ?? [:],
            optionFieldValues: operation.optionFieldValues ?? [:]
        )

        let serialized = SerializableNode(from: liveNode, nodeType: resolvedType)
        let position = suggestedPosition(
            for: serialized.id,
            anchorRef: operation.anchorNodeRef,
            placement: operation.placement,
            document: document,
            tempNodeIDs: tempNodeIDs
        )

        let customTitle = operation.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        document.nodes.append(serialized)
        document.canvasState.append(
            CanvasNodeState(
                nodeID: serialized.id,
                position: position,
                customName: customTitle?.isEmpty == false ? customTitle : nil
            )
        )

        if let tempID = operation.tempID?.trimmingCharacters(in: .whitespacesAndNewlines), !tempID.isEmpty {
            tempNodeIDs[tempID] = serialized.id
        }

        focusNodeID = serialized.id
        let displayTitle = resolvedNodeTitle(serialized.id, in: document)
        return "Added \(displayTitle)"
    }

    private static func applyUpdateNode(
        _ operation: EduAgentGraphOperation,
        to document: inout GNodeDocument,
        tempNodeIDs: [String: UUID],
        warnings: inout [String],
        focusNodeID: inout UUID?
    ) -> String? {
        guard let ref = operation.nodeRef,
              let targetNodeID = resolveNodeID(from: ref, document: document, tempNodeIDs: tempNodeIDs),
              let index = document.nodes.firstIndex(where: { $0.id == targetNodeID }),
              let liveNode = try? deserializeNode(document.nodes[index]) else {
            warnings.append("Unable to resolve update target: \(operation.nodeRef ?? "nil")")
            return nil
        }

        let previous = document.nodes[index]
        configure(
            node: liveNode,
            resolvedType: previous.nodeType,
            title: operation.title,
            textValue: operation.textValue,
            selectedOption: operation.selectedOption,
            selectedMethodID: operation.selectedMethodID,
            textFieldValues: operation.textFieldValues ?? [:],
            optionFieldValues: operation.optionFieldValues ?? [:]
        )

        let updated = SerializableNode._withID(targetNodeID, from: SerializableNode(from: liveNode, nodeType: previous.nodeType))
        let inputPortMapping = portMapping(from: previous.inputPorts, to: updated.inputPorts)
        let outputPortMapping = portMapping(from: previous.outputPorts, to: updated.outputPorts)
        document.nodes[index] = updated

        if let title = operation.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty,
           let stateIndex = document.canvasState.firstIndex(where: { $0.nodeID == targetNodeID }) {
            document.canvasState[stateIndex].customName = title
        }

        document.connections = document.connections.compactMap { connection in
            if connection.sourceNodeID == targetNodeID {
                guard let newPortID = outputPortMapping[connection.sourcePortID] else { return nil }
                return NodeConnection(
                    sourceNode: connection.sourceNodeID,
                    sourcePort: newPortID,
                    targetNode: connection.targetNodeID,
                    targetPort: connection.targetPortID,
                    dataType: connection.dataType
                )
            }
            if connection.targetNodeID == targetNodeID {
                guard let newPortID = inputPortMapping[connection.targetPortID] else { return nil }
                return NodeConnection(
                    sourceNode: connection.sourceNodeID,
                    sourcePort: connection.sourcePortID,
                    targetNode: connection.targetNodeID,
                    targetPort: newPortID,
                    dataType: connection.dataType
                )
            }
            return connection
        }

        focusNodeID = targetNodeID
        return "Updated \(resolvedNodeTitle(targetNodeID, in: document))"
    }

    private static func applyConnect(
        _ operation: EduAgentGraphOperation,
        to document: inout GNodeDocument,
        tempNodeIDs: [String: UUID],
        warnings: inout [String],
        focusNodeID: inout UUID?
    ) -> String? {
        guard let sourceRef = operation.sourceNodeRef,
              let targetRef = operation.targetNodeRef,
              let sourceNodeID = resolveNodeID(from: sourceRef, document: document, tempNodeIDs: tempNodeIDs),
              let targetNodeID = resolveNodeID(from: targetRef, document: document, tempNodeIDs: tempNodeIDs),
              let sourceNode = document.nodes.first(where: { $0.id == sourceNodeID }),
              let targetNode = document.nodes.first(where: { $0.id == targetNodeID }),
              let sourcePort = resolveOutputPort(on: sourceNode, preferredName: operation.sourcePortName),
              let targetPort = resolveInputPort(on: targetNode, preferredName: operation.targetPortName) else {
            warnings.append("Unable to connect \(operation.sourceNodeRef ?? "?") -> \(operation.targetNodeRef ?? "?")")
            return nil
        }

        if document.connections.contains(where: {
            $0.sourceNodeID == sourceNodeID &&
            $0.targetNodeID == targetNodeID &&
            $0.sourcePortID == sourcePort.id &&
            $0.targetPortID == targetPort.id
        }) {
            return nil
        }

        document.connections.append(
            NodeConnection(
                sourceNode: sourceNodeID,
                sourcePort: sourcePort.id,
                targetNode: targetNodeID,
                targetPort: targetPort.id,
                dataType: sourcePort.dataType
            )
        )
        focusNodeID = targetNodeID
        return "Connected \(resolvedNodeTitle(sourceNodeID, in: document)) -> \(resolvedNodeTitle(targetNodeID, in: document))"
    }

    private static func applyDisconnect(
        _ operation: EduAgentGraphOperation,
        to document: inout GNodeDocument,
        tempNodeIDs: [String: UUID],
        warnings: inout [String],
        focusNodeID: inout UUID?
    ) -> String? {
        guard let sourceRef = operation.sourceNodeRef,
              let targetRef = operation.targetNodeRef,
              let sourceNodeID = resolveNodeID(from: sourceRef, document: document, tempNodeIDs: tempNodeIDs),
              let targetNodeID = resolveNodeID(from: targetRef, document: document, tempNodeIDs: tempNodeIDs) else {
            warnings.append("Unable to resolve disconnect target.")
            return nil
        }

        let originalCount = document.connections.count
        document.connections.removeAll { connection in
            connection.sourceNodeID == sourceNodeID && connection.targetNodeID == targetNodeID
        }
        guard document.connections.count != originalCount else { return nil }
        focusNodeID = targetNodeID
        return "Disconnected \(resolvedNodeTitle(sourceNodeID, in: document)) -> \(resolvedNodeTitle(targetNodeID, in: document))"
    }

    private static func applyMoveNode(
        _ operation: EduAgentGraphOperation,
        to document: inout GNodeDocument,
        tempNodeIDs: [String: UUID],
        warnings: inout [String],
        focusNodeID: inout UUID?
    ) -> String? {
        guard let ref = operation.nodeRef,
              let targetNodeID = resolveNodeID(from: ref, document: document, tempNodeIDs: tempNodeIDs),
              let stateIndex = document.canvasState.firstIndex(where: { $0.nodeID == targetNodeID }) else {
            warnings.append("Unable to resolve move target: \(operation.nodeRef ?? "nil")")
            return nil
        }

        let current = document.canvasState[stateIndex]
        let nextPosition = resolvedMovePosition(
            operation: operation,
            currentPosition: CGPoint(x: current.positionX, y: current.positionY),
            document: document,
            tempNodeIDs: tempNodeIDs
        )

        guard nextPosition.x.isFinite, nextPosition.y.isFinite else {
            warnings.append("Move target position is invalid.")
            return nil
        }

        document.canvasState[stateIndex].positionX = nextPosition.x
        document.canvasState[stateIndex].positionY = nextPosition.y
        focusNodeID = targetNodeID
        return "Moved \(resolvedNodeTitle(targetNodeID, in: document))"
    }

    private static func applyDeleteNode(
        _ operation: EduAgentGraphOperation,
        to document: inout GNodeDocument,
        tempNodeIDs: [String: UUID],
        warnings: inout [String],
        focusNodeID: inout UUID?
    ) -> String? {
        guard let ref = operation.nodeRef,
              let targetNodeID = resolveNodeID(from: ref, document: document, tempNodeIDs: tempNodeIDs) else {
            warnings.append("Unable to resolve delete target: \(operation.nodeRef ?? "nil")")
            return nil
        }

        let title = resolvedNodeTitle(targetNodeID, in: document)
        let removedConnections = document.connections.reduce(into: 0) { count, connection in
            if connection.sourceNodeID == targetNodeID || connection.targetNodeID == targetNodeID {
                count += 1
            }
        }

        document.nodes.removeAll { $0.id == targetNodeID }
        document.canvasState.removeAll { $0.nodeID == targetNodeID }
        document.connections.removeAll {
            $0.sourceNodeID == targetNodeID || $0.targetNodeID == targetNodeID
        }

        focusNodeID = document.canvasState.last?.nodeID
        if removedConnections > 0 {
            let suffix = removedConnections == 1 ? "connection" : "connections"
            return "Removed \(title) and \(removedConnections) \(suffix)"
        }
        return "Removed \(title)"
    }

    private static func configure(
        node: any GNode,
        resolvedType: String,
        title: String?,
        textValue: String?,
        selectedOption: String?,
        selectedMethodID: String?,
        textFieldValues: [String: String],
        optionFieldValues: [String: String]
    ) {
        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            node.attributes.name = title
        }

        if let methodSelectable = node as? any NodeMethodSelectable,
           let selectedMethodID = selectedMethodID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !selectedMethodID.isEmpty {
            methodSelectable.editorSelectedMethodID = selectedMethodID
        }

        if let optionSelectable = node as? any NodeOptionSelectable,
           let selectedOption = selectedOption?.trimmingCharacters(in: .whitespacesAndNewlines),
           !selectedOption.isEmpty {
            optionSelectable.editorSelectedOption = selectedOption
        }

        if let textEditable = node as? any NodeTextEditable,
           let textValue = textValue?.trimmingCharacters(in: .whitespacesAndNewlines),
           !textValue.isEmpty {
            textEditable.editorTextValue = textValue
        }

        if let formEditable = node as? any NodeFormEditable {
            let normalizedTextFieldValues: [String: String]
            if resolvedType == EduNodeType.evaluation,
               let evaluationNode = node as? EduEvaluationNode {
                normalizedTextFieldValues = sanitizedEvaluationTextFieldValues(
                    incoming: textFieldValues,
                    optionFieldValues: optionFieldValues,
                    evaluationNode: evaluationNode
                )
            } else {
                normalizedTextFieldValues = textFieldValues
            }

            for (fieldID, value) in normalizedTextFieldValues {
                formEditable.setEditorFormTextFieldValue(value, for: fieldID)
            }
            for (fieldID, value) in optionFieldValues {
                formEditable.setEditorFormOptionValue(value, for: fieldID)
            }
        }

        if resolvedType == EduNodeType.knowledge,
           let knowledge = node as? EduKnowledgeNode,
           let selectedOption = selectedOption?.trimmingCharacters(in: .whitespacesAndNewlines),
           !selectedOption.isEmpty {
            knowledge.editorSelectedOption = selectedOption
        }
    }

    private static func sanitizedEvaluationTextFieldValues(
        incoming: [String: String],
        optionFieldValues: [String: String],
        evaluationNode: EduEvaluationNode
    ) -> [String: String] {
        let indicatorsFieldID = "evaluation_indicators"
        guard let rawIndicators = incoming[indicatorsFieldID] else { return incoming }

        let resolvedFormulaID = optionFieldValues["evaluation_formula"]
            ?? evaluationNode.serializedOptionFieldValues["evaluation_formula"]
            ?? "average"
        let includeWeight = resolvedFormulaID == "weighted_avg"

        let existingRows = parseEvaluationIndicatorRows(
            from: evaluationNode.serializedTextFieldValues[indicatorsFieldID] ?? "",
            includeWeight: includeWeight
        )
        let candidateRows = parseEvaluationIndicatorRows(
            from: rawIndicators,
            includeWeight: includeWeight
        )

        let filteredRows = deduplicatedEvaluationRows(
            candidateRows.filter { isSubstantiveEvaluationIndicatorName($0.name) }
        )

        let resolvedRows: [EvaluationIndicatorRow]
        if filteredRows.isEmpty {
            resolvedRows = existingRows
        } else if existingRows.isEmpty {
            resolvedRows = filteredRows
        } else {
            resolvedRows = mergedEvaluationRows(existing: existingRows, incoming: filteredRows)
        }

        var normalized = incoming
        normalized[indicatorsFieldID] = serializedEvaluationIndicatorRows(
            resolvedRows,
            includeWeight: includeWeight
        )
        return normalized
    }

    private struct EvaluationIndicatorRow {
        let name: String
        let type: String
        let weight: String
    }

    private static func parseEvaluationIndicatorRows(
        from raw: String,
        includeWeight: Bool
    ) -> [EvaluationIndicatorRow] {
        raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { rawLine -> EvaluationIndicatorRow? in
                let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty else { return nil }

                let normalizedLine = line
                    .replacingOccurrences(of: "｜", with: "|")
                    .replacingOccurrences(of: "：", with: ":")
                var components = normalizedLine
                    .split(separator: "|", omittingEmptySubsequences: false)
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

                if components.count == 1 && normalizedLine.contains(":") {
                    components = normalizedLine
                        .split(separator: ":", omittingEmptySubsequences: false)
                        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                }

                guard let nameRaw = components.first else { return nil }
                let name = nameRaw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return nil }

                var typeToken = components.count > 1 ? components[1] : "score"
                var weightToken = components.count > 2 ? components[2] : "1"

                if components.count == 2 && typeToken.contains("/") {
                    let parts = typeToken
                        .split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
                        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    typeToken = parts.first ?? "score"
                    if parts.count > 1 {
                        weightToken = parts[1]
                    }
                }

                return EvaluationIndicatorRow(
                    name: name,
                    type: normalizedEvaluationIndicatorType(from: typeToken),
                    weight: includeWeight ? normalizedEvaluationWeightText(from: weightToken) : "1"
                )
            }
    }

    private static func serializedEvaluationIndicatorRows(
        _ rows: [EvaluationIndicatorRow],
        includeWeight: Bool
    ) -> String {
        rows
            .compactMap { row -> String? in
                let trimmedName = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedName.isEmpty else { return nil }
                if includeWeight {
                    return "\(trimmedName) | \(normalizedEvaluationIndicatorType(from: row.type)) | \(normalizedEvaluationWeightText(from: row.weight))"
                }
                return "\(trimmedName) | \(normalizedEvaluationIndicatorType(from: row.type))"
            }
            .joined(separator: "\n")
    }

    private static func deduplicatedEvaluationRows(
        _ rows: [EvaluationIndicatorRow]
    ) -> [EvaluationIndicatorRow] {
        var seen: Set<String> = []
        var result: [EvaluationIndicatorRow] = []
        for row in rows {
            let key = normalizedEvaluationIndicatorKey(row.name)
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(row)
        }
        return result
    }

    private static func mergedEvaluationRows(
        existing: [EvaluationIndicatorRow],
        incoming: [EvaluationIndicatorRow]
    ) -> [EvaluationIndicatorRow] {
        var incomingByKey: [String: EvaluationIndicatorRow] = [:]
        for row in incoming {
            let key = normalizedEvaluationIndicatorKey(row.name)
            guard !key.isEmpty else { continue }
            incomingByKey[key] = row
        }

        var usedKeys: Set<String> = []
        var result: [EvaluationIndicatorRow] = []
        result.reserveCapacity(max(existing.count, incoming.count))

        for row in existing {
            let key = normalizedEvaluationIndicatorKey(row.name)
            guard !key.isEmpty else { continue }
            if let updated = incomingByKey[key] {
                result.append(updated)
            } else {
                result.append(row)
            }
            usedKeys.insert(key)
        }

        for row in incoming {
            let key = normalizedEvaluationIndicatorKey(row.name)
            guard !key.isEmpty, !usedKeys.contains(key) else { continue }
            result.append(row)
            usedKeys.insert(key)
        }

        return result
    }

    private static func normalizedEvaluationIndicatorKey(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
    }

    private static func normalizedEvaluationIndicatorType(from raw: String) -> String {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.contains("completion")
            || normalized.contains("complete")
            || normalized.contains("完成")
            || normalized.contains("达成") {
            return "completion"
        }
        return "score"
    }

    private static func normalizedEvaluationWeightText(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(trimmed), value > 0 else { return "1" }
        if value == value.rounded() {
            return "\(Int(value))"
        }
        return String(value)
    }

    private static func isSubstantiveEvaluationIndicatorName(_ raw: String) -> Bool {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return false }

        let rejectedMarkers = [
            "rubric details", "rubric detail", "rubric", "criteria", "scoring bands",
            "score band", "score range", "quantitative rule", "quantitative rules",
            "excellent", "good", "fair", "poor", "needs improvement",
            "评分细则", "评分标准", "量化细则", "量化规则", "评分档", "分档", "分数段",
            "优秀", "良好", "中等", "及格", "待改进"
        ]
        if rejectedMarkers.contains(where: { normalized.contains($0) }) {
            return false
        }

        let compact = normalized
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "－", with: "-")

        let numericRangePatterns = [
            #"^-?\d+\s*-\s*\d+$"#,
            #"^(below|under|lessthan|above|over)\d+$"#,
            #"^(低于|高于|不少于|不高于)\d+$"#
        ]
        if numericRangePatterns.contains(where: {
            compact.range(of: $0, options: .regularExpression) != nil
        }) {
            return false
        }

        return true
    }

    fileprivate static func resolvedNodeType(from raw: String) -> String? {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case EduNodeType.knowledge.lowercased(), "knowledge":
            return EduNodeType.knowledge
        case EduNodeType.evaluation.lowercased(), "evaluation":
            return EduNodeType.evaluation
        case EduNodeType.toolkitPerceptionInquiry.lowercased(), "toolkit_inquiry", "toolkit-perception-inquiry", "inquiry":
            return EduNodeType.toolkitPerceptionInquiry
        case EduNodeType.toolkitConstructionPrototype.lowercased(), "toolkit_construction", "construction":
            return EduNodeType.toolkitConstructionPrototype
        case EduNodeType.toolkitCommunicationNegotiation.lowercased(), "toolkit_negotiation", "negotiation", "communication":
            return EduNodeType.toolkitCommunicationNegotiation
        case EduNodeType.toolkitRegulationMetacognition.lowercased(), "toolkit_metacognition", "metacognition", "regulation":
            return EduNodeType.toolkitRegulationMetacognition
        default:
            return nil
        }
    }

    private static func resolveNodeID(
        from reference: String,
        document: GNodeDocument,
        tempNodeIDs: [String: UUID]
    ) -> UUID? {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        if let temp = tempNodeIDs[trimmed] {
            return temp
        }
        if let uuid = UUID(uuidString: trimmed),
           document.nodes.contains(where: { $0.id == uuid }) {
            return uuid
        }
        let lowered = trimmed.lowercased()
        let titleMatches = document.canvasState.compactMap { state -> UUID? in
            let title = state.customName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            return title == lowered ? state.nodeID : nil
        }
        if let first = titleMatches.first {
            return first
        }
        let referenceKey = normalizedReferenceKey(trimmed)
        if !referenceKey.isEmpty {
            let fuzzyMatches = document.nodes.compactMap { node -> (UUID, Int)? in
                let customTitle = document.canvasState.first(where: { $0.nodeID == node.id })?.customName ?? ""
                let candidates = [customTitle, node.attributes.name]
                let score = candidates.reduce(0) { current, candidate in
                    let candidateKey = normalizedReferenceKey(candidate)
                    guard !candidateKey.isEmpty else { return current }
                    if candidateKey == referenceKey {
                        return max(current, 100)
                    }
                    if candidateKey.contains(referenceKey) {
                        return max(current, 80)
                    }
                    if referenceKey.contains(candidateKey) {
                        return max(current, 60)
                    }
                    return current
                }
                guard score > 0 else { return nil }
                return (node.id, score)
            }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.uuidString < rhs.0.uuidString
                }
                return lhs.1 > rhs.1
            }

            if let best = fuzzyMatches.first,
               fuzzyMatches.dropFirst().first?.1 != best.1 {
                return best.0
            }
        }
        return document.nodes.first(where: { $0.attributes.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == lowered })?.id
    }

    private static func normalizedReferenceKey(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
    }

    private static func resolvedNodeTitle(_ nodeID: UUID, in document: GNodeDocument) -> String {
        if let state = document.canvasState.first(where: { $0.nodeID == nodeID }),
           let custom = state.customName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !custom.isEmpty {
            return custom
        }
        return document.nodes.first(where: { $0.id == nodeID })?.attributes.name ?? nodeID.uuidString
    }

    private static func suggestedPosition(
        for _: UUID,
        anchorRef: String?,
        placement: String?,
        document: GNodeDocument,
        tempNodeIDs: [String: UUID]
    ) -> CGPoint {
        let baseOffset = CGPoint(x: 260, y: 0)

        if let anchorRef,
           let anchorID = resolveNodeID(from: anchorRef, document: document, tempNodeIDs: tempNodeIDs),
           let anchor = document.canvasState.first(where: { $0.nodeID == anchorID }) {
            let normalizedPlacement = placement?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "right"
            let candidate: CGPoint
            switch normalizedPlacement {
            case "left":
                candidate = CGPoint(x: anchor.positionX - 260, y: anchor.positionY)
            case "above":
                candidate = CGPoint(x: anchor.positionX, y: anchor.positionY - 180)
            case "below":
                candidate = CGPoint(x: anchor.positionX, y: anchor.positionY + 180)
            default:
                candidate = CGPoint(x: anchor.positionX + baseOffset.x, y: anchor.positionY + baseOffset.y)
            }
            return firstAvailablePosition(near: candidate, in: document)
        }

        if let maxX = document.canvasState.map(\.positionX).max() {
            let count = Double(document.canvasState.count % 4)
            let candidate = CGPoint(x: maxX + 260, y: 40 + count * 190)
            return firstAvailablePosition(near: candidate, in: document)
        }
        return CGPoint(x: 40, y: 40)
    }

    private static func resolvedMovePosition(
        operation: EduAgentGraphOperation,
        currentPosition: CGPoint,
        document: GNodeDocument,
        tempNodeIDs: [String: UUID]
    ) -> CGPoint {
        if operation.positionX != nil || operation.positionY != nil {
            return CGPoint(
                x: operation.positionX ?? currentPosition.x,
                y: operation.positionY ?? currentPosition.y
            )
        }

        guard operation.anchorNodeRef != nil || operation.placement != nil else {
            return currentPosition
        }

        return suggestedPosition(
            for: UUID(),
            anchorRef: operation.anchorNodeRef,
            placement: operation.placement,
            document: document,
            tempNodeIDs: tempNodeIDs
        )
    }

    private static func firstAvailablePosition(
        near candidate: CGPoint,
        in document: GNodeDocument
    ) -> CGPoint {
        let offsets = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 0, y: 180),
            CGPoint(x: 0, y: -180),
            CGPoint(x: 260, y: 0),
            CGPoint(x: 260, y: 180),
            CGPoint(x: 260, y: -180),
            CGPoint(x: -260, y: 0),
            CGPoint(x: -260, y: 180),
            CGPoint(x: -260, y: -180)
        ]

        for offset in offsets {
            let proposed = CGPoint(x: candidate.x + offset.x, y: candidate.y + offset.y)
            let hasOverlap = document.canvasState.contains { state in
                abs(state.positionX - proposed.x) < 120 && abs(state.positionY - proposed.y) < 100
            }
            if !hasOverlap {
                return proposed
            }
        }

        return candidate
    }

    private static func resolveOutputPort(
        on node: SerializableNode,
        preferredName: String?
    ) -> SerializablePort? {
        if let preferredName = preferredName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !preferredName.isEmpty,
           let matched = node.outputPorts.first(where: { $0.name.lowercased() == preferredName }) {
            return matched
        }
        return node.outputPorts.first
    }

    private static func resolveInputPort(
        on node: SerializableNode,
        preferredName: String?
    ) -> SerializablePort? {
        if let preferredName = preferredName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !preferredName.isEmpty,
           let matched = node.inputPorts.first(where: { $0.name.lowercased() == preferredName }) {
            return matched
        }
        return node.inputPorts.first
    }

    private static func portMapping(
        from oldPorts: [SerializablePort],
        to newPorts: [SerializablePort]
    ) -> [UUID: UUID] {
        var result: [UUID: UUID] = [:]
        var remaining = newPorts

        for old in oldPorts {
            if let exactIndex = remaining.firstIndex(where: { $0.name == old.name }) {
                result[old.id] = remaining[exactIndex].id
                remaining.remove(at: exactIndex)
            }
        }

        for old in oldPorts where result[old.id] == nil {
            guard !remaining.isEmpty else { continue }
            result[old.id] = remaining.removeFirst().id
        }
        return result
    }
}

private extension String {
    func contains(anyOf tokens: [String]) -> Bool {
        tokens.contains { token in
            contains(token)
        }
    }
}
