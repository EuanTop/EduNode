import SwiftUI
import GNodeKit
import SwiftData

extension ContentView {
    func applyTutorialPracticeGuidedFill() {
        guard activeTutorial == .practice,
              let fileID = tutorialPracticeFileID,
              let file = workspaceFiles.first(where: { $0.id == fileID }),
              let document = try? decodeDocument(from: file.data),
              let targetNodeID = resolvedTutorialPracticeKnowledgeTargetNodeID(in: document),
              let fillText = tutorialPracticeAutofillTextForCurrentStep(isChinese: isChineseUI()) else {
            return
        }

        var updatedDocument = document
        guard let nodeIndex = updatedDocument.nodes.firstIndex(where: { $0.id == targetNodeID }) else { return }
        let sourceNode = updatedDocument.nodes[nodeIndex]
        var nodeData = sourceNode.nodeData
        nodeData["content"] = fillText
        let updatedNode = SerializableNode(
            id: sourceNode.id,
            nodeType: sourceNode.nodeType,
            attributes: sourceNode.attributes,
            inputPorts: sourceNode.inputPorts,
            outputPorts: sourceNode.outputPorts,
            nodeData: nodeData
        )
        updatedDocument.nodes[nodeIndex] = updatedNode
        guard let encoded = try? encodeDocument(updatedDocument) else { return }

        if let targetState = updatedDocument.canvasState.first(where: { $0.nodeID == targetNodeID }) {
            selectedFileID = fileID
            selectionRequest = NodeEditorSelectionRequest(nodeID: targetNodeID)
            cameraRequest = NodeEditorCameraRequest(
                canvasPosition: CGPoint(x: targetState.positionX, y: targetState.positionY)
            )
        }
        persistWorkspaceFileData(id: fileID, data: encoded)

        let token = UUID()
        tutorialPracticeGuidedFillToken = token
        tutorialPracticeGuidedFillPendingStepIndex = tutorialStepIndex
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            guard tutorialPracticeGuidedFillToken == token else { return }
            guard activeTutorial == .practice else { return }
            guard tutorialStepIndex < practiceSteps.count else { return }
            let mode = practiceSteps[tutorialStepIndex].advanceMode
            guard mode == .waitForKnowledgeKeywordEdit || mode == .waitForAdditionalKnowledgeEdit else {
                return
            }
            tutorialPracticeGuidedFillPendingStepIndex = nil
            advanceTutorialStep()
        }
    }

    func advanceTutorialStep() {
        let steps = currentTutorialSteps
        if tutorialStepIndex < steps.count - 1 {
            tutorialPracticeGuidedFillToken = UUID()
            tutorialPracticeGuidedFillPendingStepIndex = nil
            withAnimation(.easeInOut(duration: 0.25)) {
                tutorialStepIndex += 1
            }
            snapshotTutorialCounts()
            // Execute demo action if the new step has one
            let newStep = steps[tutorialStepIndex]
            if let demoAction = newStep.demoAction {
                executeDemoAction(demoAction)
            }
            runPracticeStepVisualAssistIfNeeded()
            scheduleTutorialAutoAdvanceIfNeeded()
        }
    }

    func runPracticeStepVisualAssistIfNeeded() {
        guard activeTutorial == .practice else { return }
        guard tutorialStepIndex < practiceSteps.count else { return }
        let mode = practiceSteps[tutorialStepIndex].advanceMode
        if tutorialStepIndex == 3, mode == .tapAnywhere {
            spotlightTutorialPracticeUbDChain()
            return
        }
        if mode == .waitForKnowledgeKeywordEdit || mode == .waitForAdditionalKnowledgeEdit {
            spotlightTutorialPracticeKnowledgeTarget()
            return
        }
        if mode == .waitForKnowledgeToSpecificToolkitConnectionAdded {
            spotlightTutorialPracticeConnectionTargets()
        }
    }

    func tutorialPracticeKnowledgeTargetIndexForCurrentStep() -> Int? {
        switch tutorialStepIndex {
        case 4: return 0
        case 5: return 1
        case 6: return 2
        default: return nil
        }
    }

    func resolvedTutorialPracticeKnowledgeTargetNodeID(in document: GNodeDocument) -> UUID? {
        if tutorialPracticeTopKnowledgeNodeIDs.isEmpty {
            tutorialPracticeTopKnowledgeNodeIDs = tutorialPracticeTopKnowledgeNodeIDs(in: document)
        }
        guard let targetIndex = tutorialPracticeKnowledgeTargetIndexForCurrentStep(),
              tutorialPracticeTopKnowledgeNodeIDs.indices.contains(targetIndex) else {
            return nil
        }
        let targetNodeID = tutorialPracticeTopKnowledgeNodeIDs[targetIndex]
        if document.nodes.contains(where: { $0.id == targetNodeID }) {
            return targetNodeID
        }
        tutorialPracticeTopKnowledgeNodeIDs = tutorialPracticeTopKnowledgeNodeIDs(in: document)
        guard tutorialPracticeTopKnowledgeNodeIDs.indices.contains(targetIndex) else { return nil }
        return tutorialPracticeTopKnowledgeNodeIDs[targetIndex]
    }

    func spotlightTutorialPracticeKnowledgeTarget() {
        guard let fileID = tutorialPracticeFileID,
              let file = workspaceFiles.first(where: { $0.id == fileID }),
              let document = try? decodeDocument(from: file.data),
              let targetNodeID = resolvedTutorialPracticeKnowledgeTargetNodeID(in: document),
              let targetState = document.canvasState.first(where: { $0.nodeID == targetNodeID }) else {
            return
        }
        let position = CGPoint(x: targetState.positionX, y: targetState.positionY)
        selectedFileID = fileID
        selectionRequest = NodeEditorSelectionRequest(nodeID: targetNodeID)
        cameraRequest = NodeEditorCameraRequest(canvasPosition: position)
    }

    func tutorialPracticeConnectionSourceNodeID(in document: GNodeDocument) -> UUID? {
        if let stage2 = document.nodes.first(where: { node in
            guard node.nodeType == EduNodeType.knowledge else { return false }
            let lowerName = node.attributes.name.lowercased()
            return (lowerName.contains("ubd") && lowerName.contains("stage 2"))
                || node.attributes.name.contains("UbD 阶段2")
        }) {
            return stage2.id
        }

        if tutorialPracticeTopKnowledgeNodeIDs.isEmpty {
            tutorialPracticeTopKnowledgeNodeIDs = tutorialPracticeTopKnowledgeNodeIDs(in: document)
        }
        guard tutorialPracticeTopKnowledgeNodeIDs.indices.contains(1) else { return nil }
        let nodeID = tutorialPracticeTopKnowledgeNodeIDs[1]
        if document.nodes.contains(where: { $0.id == nodeID }) {
            return nodeID
        }
        tutorialPracticeTopKnowledgeNodeIDs = tutorialPracticeTopKnowledgeNodeIDs(in: document)
        guard tutorialPracticeTopKnowledgeNodeIDs.indices.contains(1) else { return nil }
        return tutorialPracticeTopKnowledgeNodeIDs[1]
    }

    func tutorialPracticeLearningPlanSourceNodeID(in document: GNodeDocument) -> UUID? {
        if let stage3 = document.nodes.first(where: { node in
            guard node.nodeType == EduNodeType.knowledge else { return false }
            let lowerName = node.attributes.name.lowercased()
            return (lowerName.contains("ubd") && lowerName.contains("stage 3"))
                || lowerName.contains("learning plan")
                || node.attributes.name.contains("UbD 阶段3")
                || node.attributes.name.contains("学习体验规划")
        }) {
            return stage3.id
        }

        if tutorialPracticeTopKnowledgeNodeIDs.isEmpty {
            tutorialPracticeTopKnowledgeNodeIDs = tutorialPracticeTopKnowledgeNodeIDs(in: document)
        }
        guard tutorialPracticeTopKnowledgeNodeIDs.indices.contains(2) else { return nil }
        let nodeID = tutorialPracticeTopKnowledgeNodeIDs[2]
        if document.nodes.contains(where: { $0.id == nodeID }) {
            return nodeID
        }
        tutorialPracticeTopKnowledgeNodeIDs = tutorialPracticeTopKnowledgeNodeIDs(in: document)
        guard tutorialPracticeTopKnowledgeNodeIDs.indices.contains(2) else { return nil }
        return tutorialPracticeTopKnowledgeNodeIDs[2]
    }

    func tutorialSourceAnalysisToolkitNodeIDs(in document: GNodeDocument) -> Set<UUID> {
        Set(
            document.nodes.compactMap { node in
                guard node.nodeType == EduNodeType.toolkitPerceptionInquiry else { return nil }
                guard !tutorialPracticeInitialNodeIDs.contains(node.id) else { return nil }
                guard (node.nodeData["toolkitMethodID"] ?? "").lowercased() == "source_analysis" else { return nil }
                return node.id
            }
        )
    }

    func tutorialPrimarySourceAnalysisToolkitNodeID(in document: GNodeDocument) -> UUID? {
        let toolkitIDs = tutorialSourceAnalysisToolkitNodeIDs(in: document)
        guard !toolkitIDs.isEmpty else { return nil }
        if let configured = tutorialPracticeConfiguredToolkitNodeID,
           toolkitIDs.contains(configured) {
            return configured
        }
        for node in document.nodes.reversed() where toolkitIDs.contains(node.id) {
            return node.id
        }
        return nil
    }

    func spotlightTutorialPracticeConnectionTargets() {
        guard let fileID = tutorialPracticeFileID,
              let file = workspaceFiles.first(where: { $0.id == fileID }),
              let document = try? decodeDocument(from: file.data),
              let sourceNodeID = tutorialPracticeConnectionSourceNodeID(in: document) else {
            return
        }
        let toolkitNodeID = tutorialPrimarySourceAnalysisToolkitNodeID(in: document)
        guard let toolkitNodeID else { return }

        let positionByNodeID = Dictionary(
            uniqueKeysWithValues: document.canvasState.map { state in
                (state.nodeID, CGPoint(x: state.positionX, y: state.positionY))
            }
        )
        guard let sourcePosition = positionByNodeID[sourceNodeID],
              let toolkitPosition = positionByNodeID[toolkitNodeID] else {
            return
        }

        let focusPosition = CGPoint(
            x: (sourcePosition.x + toolkitPosition.x) * 0.5,
            y: (sourcePosition.y + toolkitPosition.y) * 0.5
        )

        selectedFileID = fileID
        selectionRequest = NodeEditorSelectionRequest(nodeID: toolkitNodeID)
        cameraRequest = NodeEditorCameraRequest(canvasPosition: focusPosition)
    }

    func spotlightTutorialPracticeUbDChain() {
        guard let fileID = tutorialPracticeFileID,
              let file = workspaceFiles.first(where: { $0.id == fileID }),
              let document = try? decodeDocument(from: file.data) else {
            return
        }

        let positionByNodeID = Dictionary(
            uniqueKeysWithValues: document.canvasState.map { canvasState in
                (canvasState.nodeID, CGPoint(x: canvasState.positionX, y: canvasState.positionY))
            }
        )
        let knowledgeCandidates = document.nodes
            .compactMap { node -> (nodeID: UUID, position: CGPoint)? in
                guard node.nodeType == EduNodeType.knowledge else { return nil }
                guard let position = positionByNodeID[node.id] else { return nil }
                return (node.id, position)
            }

        let spotlightCandidates: [(nodeID: UUID, position: CGPoint)]
        if let minY = knowledgeCandidates.map(\.position.y).min() {
            let topBand = knowledgeCandidates.filter { $0.position.y <= minY + 220 }
            spotlightCandidates = topBand.isEmpty ? knowledgeCandidates : topBand
        } else {
            spotlightCandidates = []
        }

        let spotlightNodes = spotlightCandidates
            .sorted { lhs, rhs in
                if abs(lhs.position.x - rhs.position.x) < 1 {
                    return lhs.position.y < rhs.position.y
                }
                return lhs.position.x < rhs.position.x
            }
            .prefix(3)

        for (offset, target) in spotlightNodes.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.42 * Double(offset)) {
                guard activeTutorial == .practice else { return }
                guard tutorialStepIndex < practiceSteps.count else { return }
                guard practiceSteps[tutorialStepIndex].advanceMode == .tapAnywhere else { return }
                selectedFileID = fileID
                selectionRequest = NodeEditorSelectionRequest(nodeID: target.nodeID)
                cameraRequest = NodeEditorCameraRequest(canvasPosition: target.position)
            }
        }
    }

    func tutorialPracticeTopKnowledgeNodeIDs(in document: GNodeDocument) -> [UUID] {
        let positionByNodeID = Dictionary(
            uniqueKeysWithValues: document.canvasState.map { state in
                (state.nodeID, CGPoint(x: state.positionX, y: state.positionY))
            }
        )
        let knowledgeNodes = document.nodes
            .compactMap { node -> (id: UUID, position: CGPoint)? in
                guard node.nodeType == EduNodeType.knowledge,
                      let position = positionByNodeID[node.id] else { return nil }
                return (node.id, position)
            }
        guard !knowledgeNodes.isEmpty else { return [] }

        let minY = knowledgeNodes.map(\.position.y).min() ?? 0
        let topBand = knowledgeNodes.filter { $0.position.y <= minY + 220 }
        let candidates = topBand.isEmpty ? knowledgeNodes : topBand

        return candidates
            .sorted { lhs, rhs in
                if abs(lhs.position.x - rhs.position.x) < 1 {
                    return lhs.position.y < rhs.position.y
                }
                return lhs.position.x < rhs.position.x
            }
            .map(\.id)
    }

    func snapshotTutorialCounts() {
        if let fileID = selectedFileID,
           let stats = editorStatsByFileID[fileID] {
            tutorialPreviousNodeCount = stats.nodeCount
            tutorialPreviousConnectionCount = stats.connectionCount
        } else {
            tutorialPreviousNodeCount = 0
            tutorialPreviousConnectionCount = 0
        }
    }

    func scheduleTutorialAutoAdvanceIfNeeded() {
        tutorialAutoAdvanceToken = UUID()
        guard let tutorial = activeTutorial else { return }
        let steps = currentTutorialSteps
        guard tutorialStepIndex < steps.count else { return }
        let step = steps[tutorialStepIndex]
        guard step.advanceMode == .animationAuto else { return }

        let token = tutorialAutoAdvanceToken
        let targetIndex = tutorialStepIndex
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.35) {
            guard tutorialAutoAdvanceToken == token else { return }
            guard activeTutorial == tutorial else { return }
            guard tutorialStepIndex == targetIndex else { return }

            if tutorialStepIndex >= steps.count - 1 {
                endTutorial(completed: true)
            } else {
                advanceTutorialStep()
            }
        }
    }

    func startTutorial(_ kind: TutorialKind) {
        activeTutorial = kind
        tutorialStepIndex = 0
        tutorialAutoAdvanceToken = UUID()
        snapshotTutorialCounts()

        switch kind {
        case .aboutDemo:
            createTutorialFile()
            // aboutDemo第1步如果有demoAction，立即执行（如自动插入Knowledge节点）
            let steps = aboutDemoSteps
            if let demoAction = steps.first?.demoAction {
                executeDemoAction(demoAction)
            }
        case .canvasBasics:
            // Clear the tutorial canvas for fresh hands-on practice
            if let fileID = tutorialDedicatedFileID,
               let file = workspaceFiles.first(where: { $0.id == fileID }) {
                file.data = emptyDocumentData()
                selectedFileID = fileID
                tutorialPreviousNodeCount = 0
                tutorialPreviousConnectionCount = 0
                selectionRequest = nil
                cameraRequest = NodeEditorCameraRequest(canvasPosition: Self.demoKnowledgePosition)
            }
            tutorialCanvasEvaluationCountBeforeDelete = nil
            tutorialCanvasConnectionCountBeforeDelete = nil
        case .modelsIntro:
            // User already opened docs; overlay will show inside docs
            docsPreferredNodeType = nil
        case .practice:
            splitVisibility = .all
            tutorialPracticeFileID = nil
            tutorialPracticeBaselineSemanticData = nil
            tutorialPracticeHasEnteredPresentation = false
            tutorialPracticeInitialToolkitCount = 0
            tutorialPracticeInitialConnections = []
            tutorialPracticeInitialNodeIDs = []
            tutorialPracticeInitialKnowledgeContentByNodeID = [:]
            tutorialPracticeTopKnowledgeNodeIDs = []
            tutorialPracticeKnowledgeModificationBaseline = nil
            tutorialPracticeKnowledgeStepTargetNodeID = nil
            tutorialPracticeKnowledgeStepEntryContent = nil
            tutorialPracticeConfiguredToolkitNodeID = nil
            tutorialPracticeConnectionStepBaseline = nil
            tutorialPracticeGuidedFillToken = UUID()
            tutorialPracticeGuidedFillPendingStepIndex = nil
            tutorialPracticeInitialZoomPercent = 100
            tutorialPracticeZoomStepBaseline = nil
        case .explore:
            break
        }

        scheduleTutorialAutoAdvanceIfNeeded()
    }

    func endTutorial(completed: Bool) {
        let kind = activeTutorial
        tutorialAutoAdvanceToken = UUID()
        withAnimation(.easeInOut(duration: 0.25)) {
            activeTutorial = nil
        }
        tutorialStepIndex = 0

        // Close docs if we were showing them
        if kind == .modelsIntro {
            showingDocs = false
        }

        if completed {
            switch kind {
            case .aboutDemo:
                // Chain immediately to canvasBasics on the same file
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    startTutorial(.canvasBasics)
                }
            case .canvasBasics:
                // Last step told user to open Docs — we wait, detection handled by showingDocs onChange
                // But if they tapped "Done" on last step (shouldn't happen with waitForDocs), still chain
                break
            case .modelsIntro:
                didCompleteBasics = true
                // Delete tutorial practice file
                deleteTutorialFile()
                // Show welcome overlay so user can start Practice
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    showingOnboardingGuide = true
                }
            case .practice:
                didCompletePractice = true
                // Prompt to explore bird example
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    showingOnboardingGuide = true
                }
            case .explore:
                didCompleteExplore = true
                didCompleteOnboarding = true
            case .none:
                break
            }
        } else {
            // User exited early — still clean up tutorial file if exiting aboutDemo/canvasBasics
            if kind == .aboutDemo || kind == .canvasBasics {
                deleteTutorialFile()
            }
        }
    }

    func createTutorialFile() {
        let tutorialFile = GNodeWorkspaceFile(
            name: isChineseUI() ? "教程练习" : "Tutorial Practice",
            data: emptyDocumentData()
        )
        modelContext.insert(tutorialFile)
        tutorialDedicatedFileID = tutorialFile.id
        selectedFileID = tutorialFile.id
        selectionRequest = nil
        cameraRequest = NodeEditorCameraRequest(canvasPosition: Self.demoKnowledgePosition)
    }

    func deleteTutorialFile() {
        guard let fileID = tutorialDedicatedFileID else { return }
        if let file = workspaceFiles.first(where: { $0.id == fileID }) {
            modelContext.delete(file)
            try? modelContext.save()
        }
        if selectedFileID == fileID {
            selectedFileID = workspaceFiles.first(where: { $0.id != fileID })?.id
        }
        tutorialDedicatedFileID = nil
    }

    // MARK: - Tutorial Demo Animations

    /// IDs for the demo nodes placed during aboutDemo
    private static let demoKnowledgeID = UUID(uuidString: "00000000-DE00-0001-0000-000000000001")!
    private static let demoToolkitID   = UUID(uuidString: "00000000-DE00-0002-0000-000000000002")!
    private static let demoEvaluationID = UUID(uuidString: "00000000-DE00-0003-0000-000000000003")!
    private static let demoKnowledgePosition = CGPoint(x: 400, y: 300)
    private static let demoToolkitPosition = CGPoint(x: 860, y: 300)
    private static let demoEvaluationPosition = CGPoint(x: 1320, y: 300)

    func executeDemoAction(_ action: TutorialDemoAction) {
        guard let fileID = tutorialDedicatedFileID,
              let file = workspaceFiles.first(where: { $0.id == fileID }) else { return }

        var focusPoint: CGPoint?
        var focusNodeID: UUID?
        let doc: GNodeDocument

        switch action {
        case .showKnowledgeNode:
            doc = makeAboutDemoDocument(
                includeKnowledge: true,
                includeToolkit: false,
                includeEvaluation: false,
                connectKnowledgeToolkit: false,
                connectToolkitEvaluation: false
            )
            focusPoint = Self.demoKnowledgePosition
            focusNodeID = Self.demoKnowledgeID

        case .showToolkitNode:
            doc = makeAboutDemoDocument(
                includeKnowledge: true,
                includeToolkit: true,
                includeEvaluation: false,
                connectKnowledgeToolkit: false,
                connectToolkitEvaluation: false
            )
            focusPoint = Self.demoToolkitPosition
            focusNodeID = Self.demoToolkitID

        case .showEvaluationNode:
            doc = makeAboutDemoDocument(
                includeKnowledge: true,
                includeToolkit: true,
                includeEvaluation: true,
                connectKnowledgeToolkit: false,
                connectToolkitEvaluation: false
            )
            focusPoint = Self.demoEvaluationPosition
            focusNodeID = Self.demoEvaluationID

        case .connectKnowledgeToToolkit:
            doc = makeAboutDemoDocument(
                includeKnowledge: true,
                includeToolkit: true,
                includeEvaluation: true,
                connectKnowledgeToolkit: true,
                connectToolkitEvaluation: false
            )
            focusPoint = Self.demoToolkitPosition
            focusNodeID = Self.demoToolkitID

        case .connectToolkitToEvaluation:
            doc = makeAboutDemoDocument(
                includeKnowledge: true,
                includeToolkit: true,
                includeEvaluation: true,
                connectKnowledgeToolkit: true,
                connectToolkitEvaluation: true
            )
            focusPoint = Self.demoEvaluationPosition
            focusNodeID = Self.demoEvaluationID
        }

        if let encoded = try? encodeDocument(doc) {
            selectedFileID = fileID
            file.data = encoded
            if let focusNodeID {
                selectionRequest = NodeEditorSelectionRequest(nodeID: focusNodeID)
            } else {
                selectionRequest = nil
            }
            if let focusPoint {
                cameraRequest = NodeEditorCameraRequest(canvasPosition: focusPoint)
                // Re-emit camera focus on next runloop to avoid occasional empty viewport race.
                DispatchQueue.main.async {
                    selectedFileID = fileID
                    cameraRequest = NodeEditorCameraRequest(canvasPosition: focusPoint)
                }
            }
        }
    }

    func makeAboutDemoDocument(
        includeKnowledge: Bool,
        includeToolkit: Bool,
        includeEvaluation: Bool,
        connectKnowledgeToolkit: Bool,
        connectToolkitEvaluation: Bool
    ) -> GNodeDocument {
        var nodes: [SerializableNode] = []
        var canvasState: [CanvasNodeState] = []

        if includeKnowledge {
            nodes.append(
                makeDemoSerializableNode(
                    id: Self.demoKnowledgeID,
                    type: EduNodeType.knowledge
                )
            )
            canvasState.append(
                CanvasNodeState(nodeID: Self.demoKnowledgeID, position: Self.demoKnowledgePosition)
            )
        }

        if includeToolkit {
            nodes.append(
                makeDemoSerializableNode(
                    id: Self.demoToolkitID,
                    type: EduNodeType.toolkitPerceptionInquiry
                )
            )
            canvasState.append(
                CanvasNodeState(nodeID: Self.demoToolkitID, position: Self.demoToolkitPosition)
            )
        }

        if includeEvaluation {
            nodes.append(
                makeDemoSerializableEvaluationNode(id: Self.demoEvaluationID)
            )
            canvasState.append(
                CanvasNodeState(nodeID: Self.demoEvaluationID, position: Self.demoEvaluationPosition)
            )
        }

        let nodeByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        var connections: [NodeConnection] = []

        if connectKnowledgeToolkit,
           let connection = makeDemoConnection(
            sourceNodeID: Self.demoKnowledgeID,
            targetNodeID: Self.demoToolkitID,
            nodeByID: nodeByID
           ) {
            connections.append(connection)
        }

        if connectToolkitEvaluation,
           let connection = makeDemoConnection(
            sourceNodeID: Self.demoToolkitID,
            targetNodeID: Self.demoEvaluationID,
            nodeByID: nodeByID
           ) {
            connections.append(connection)
        }

        return GNodeDocument(
            nodes: nodes,
            connections: connections,
            canvasState: canvasState
        )
    }

    func makeDemoConnection(
        sourceNodeID: UUID,
        targetNodeID: UUID,
        nodeByID: [UUID: SerializableNode]
    ) -> NodeConnection? {
        guard let sourceNode = nodeByID[sourceNodeID],
              let targetNode = nodeByID[targetNodeID],
              let sourcePort = sourceNode.outputPorts.first,
              let targetPort = targetNode.inputPorts.first else {
            return nil
        }

        return NodeConnection(
            sourceNode: sourceNodeID,
            sourcePort: sourcePort.id,
            targetNode: targetNodeID,
            targetPort: targetPort.id,
            dataType: "Any"
        )
    }

    func makeDemoSerializableEvaluationNode(id: UUID) -> SerializableNode {
        let demoNode = EduEvaluationNode(
            name: isChineseUI() ? "评价" : "Evaluation",
            textFieldValues: [
                "evaluation_indicators": "Quick Check | score"
            ],
            optionFieldValues: [
                "evaluation_formula": "average",
                "evaluation_grouping": "individual",
                "evaluation_output_scale": "score100"
            ]
        )
        let serialized = SerializableNode(from: demoNode, nodeType: EduNodeType.evaluation)
        return SerializableNode._withID(id, from: serialized)
    }

    /// Create a SerializableNode by instantiating a real GNode, then serializing it
    func makeDemoSerializableNode(id: UUID, type: String) -> SerializableNode {
        if let realNode = GNodeNodeKit.gnodeNodeKit.createNode(type: type) {
            // Use the real node's ports and attributes, but replace its ID
            let sNode = SerializableNode(from: realNode, nodeType: type)
            // SerializableNode.id is let, so we create a wrapper
            return SerializableNode._withID(id, from: sNode)
        }
        // Fallback: minimal node
        return SerializableNode._minimal(id: id, nodeType: type)
    }

    var isTutorialPracticeAwaitingCourseCreation: Bool {
        guard activeTutorial == .practice else { return false }
        guard tutorialStepIndex < practiceSteps.count else { return false }
        let mode = practiceSteps[tutorialStepIndex].advanceMode
        return mode == .waitForCreateCourseSheet || mode == .waitForCourseCreated
    }

    var tutorialPracticeRequiredModelID: String {
        let chinese = isChineseUI()
        let fallbackID = modelRules.first(where: { $0.id == "ubd" })?.id ?? (modelRules.first?.id ?? "")
        guard !modelRules.isEmpty else { return fallbackID }

        let ranked = modelRules.map { rule in
            let nodeCount = tutorialTemplateNodeCount(for: rule, isChinese: chinese)
            return (id: rule.id, nodeCount: nodeCount)
        }

        guard let minimal = ranked.min(by: { lhs, rhs in
            if lhs.nodeCount == rhs.nodeCount {
                return lhs.id < rhs.id
            }
            return lhs.nodeCount < rhs.nodeCount
        }) else {
            return fallbackID
        }

        return minimal.id
    }

    func tutorialTemplateNodeCount(for rule: EduModelRule, isChinese: Bool) -> Int {
        let draft = tutorialPracticeDraft(for: rule.id, isChinese: isChinese)
        let data = EduPlanning.makeInitialDocumentData(
            draft: draft,
            modelRule: rule,
            isChinese: isChinese
        )
        guard let document = try? decodeDocument(from: data) else {
            return Int.max
        }
        return document.nodes.count
    }

    func tutorialPracticeDraft(for modelID: String, isChinese: Bool) -> CourseCreationDraft {
        var draft = CourseCreationDraft()
        draft.courseName = isChinese ? "中学科学微课（引导练习）" : "Middle-School Science Micro-Lesson (Guided Practice)"
        draft.gradeInputMode = .grade
        draft.gradeMinText = "7"
        draft.gradeMaxText = "8"
        draft.subject = isChinese ? "科学" : "Science"
        draft.lessonDurationMinutesText = "20"
        draft.lessonType = .singleLesson
        draft.totalSessionsText = "1"
        draft.periodRange = isChinese ? "引导练习：单课时科学课设计" : "Guided practice: single-lesson science class design"
        draft.studentCountText = "32"
        draft.priorAssessmentScoreText = "68"
        draft.assignmentCompletionRateText = "80"
        draft.supportNeedCountText = "6"
        draft.learningOrganization = .mixed
        draft.teachingStyle = .inquiryDriven
        draft.emphasizeInquiryExperiment = true
        draft.emphasizeExperienceReflection = false
        draft.requireStructuredFlow = false
        draft.formativeCheckIntensity = .medium
        draft.expectedOutputIDs = ["lessonHandout", "presentation", "worksheet"]
        draft.goals = isChinese
            ? [
                "概念理解：解释核心科学规律并识别关键概念。",
                "证据表达：基于可观察现象给出证据说明。",
                "迁移应用：把规律迁移到新的生活情境。"
            ]
            : [
                "Concept understanding: explain a core science principle and key concepts.",
                "Evidence expression: justify claims with observable evidence.",
                "Transfer: apply the principle to new real-world contexts."
            ]
        draft.modelID = modelID
        draft.leadTeacherCountText = "1"
        draft.assistantTeacherCountText = "1"
        draft.teacherRolePlan = isChinese
            ? """
            主讲 | 王老师 | 引导现象分析与关键追问，组织课堂收束
            助教 | 李老师 | 组织分组记录证据，支持 Source Analysis 讨论
            """
            : """
            Lead | Ms. Wang | Lead phenomenon analysis and synthesize key findings
            Assistant | Mr. Li | Facilitate evidence recording and Source Analysis discussion
            """
        draft.studentRosterText = isChinese
            ? """
            林晨|A组|13
            陈雨|A组|13
            张宁|B组|14
            赵敏|B组|14
            王涵|C组|13
            李哲|C组|13
            """
            : """
            Alex Chen|Group A|13
            Mia Lin|Group A|13
            Noah Zhang|Group B|14
            Emma Zhao|Group B|14
            Ethan Wang|Group C|13
            Olivia Li|Group C|13
            """

        switch modelID {
        case "fivee":
            draft.lessonType = .singleLesson
            draft.totalSessionsText = "1"
            draft.teachingStyle = .inquiryDriven
            draft.learningOrganization = .group
            draft.emphasizeInquiryExperiment = true
            draft.formativeCheckIntensity = .medium
            draft.periodRange = isChinese
                ? "单课时探究：现象观察→解释→迁移"
                : "Single-lesson inquiry: observe -> explain -> transfer"
            draft.expectedOutputIDs = ["experimentLog", "worksheet", "presentation"]
            draft.goals = isChinese
                ? [
                    "观察现象：从实验现象中提出关键问题。",
                    "概念解释：用证据解释光合作用影响因素。",
                    "迁移应用：把解释迁移到新的生长情境。"
                ]
                : [
                    "Observation: raise key questions from experimental evidence.",
                    "Explanation: explain photosynthesis factors with evidence.",
                    "Transfer: apply explanation to a new growth context."
                ]

        case "kolb":
            draft.lessonType = .unitSeries
            draft.totalSessionsText = "3"
            draft.teachingStyle = .experientialReflective
            draft.learningOrganization = .group
            draft.emphasizeExperienceReflection = true
            draft.formativeCheckIntensity = .low
            draft.periodRange = isChinese
                ? "体验-反思-概念-再实践循环"
                : "Experience-reflection-concept-practice cycle"
            draft.expectedOutputIDs = ["experimentLog", "projectArtifact", "lessonHandout"]
            draft.goals = isChinese
                ? [
                    "具体体验：记录真实观察并形成问题。",
                    "反思抽象：把观察转化为概念解释。",
                    "主动实验：用新任务验证并修正理解。"
                ]
                : [
                    "Concrete experience: capture observations and questions.",
                    "Reflective abstraction: build conceptual explanations from observations.",
                    "Active experimentation: validate and refine understanding in new tasks."
                ]

        case "boppps":
            draft.lessonType = .singleLesson
            draft.totalSessionsText = "1"
            draft.teachingStyle = .lectureDriven
            draft.learningOrganization = .mixed
            draft.requireStructuredFlow = true
            draft.formativeCheckIntensity = .high
            draft.periodRange = isChinese
                ? "单课时结构化流程（Bridge-in 到 Summary）"
                : "Single-lesson structured flow (Bridge-in to Summary)"
            draft.expectedOutputIDs = ["worksheet", "lessonHandout", "presentation"]
            draft.goals = isChinese
                ? [
                    "明确目标：学生清楚本课学习目标与成功标准。",
                    "参与实践：在参与活动中输出可观察结果。",
                    "课末收束：通过后测与总结确认达成。"
                ]
                : [
                    "Objective clarity: learners understand success criteria.",
                    "Participatory performance: produce observable learning outputs.",
                    "Closure: confirm achievement through post-assessment and summary."
                ]

        case "gagne9":
            draft.lessonType = .singleLesson
            draft.totalSessionsText = "1"
            draft.teachingStyle = .lectureDriven
            draft.learningOrganization = .individual
            draft.requireStructuredFlow = true
            draft.formativeCheckIntensity = .high
            draft.periodRange = isChinese
                ? "九事件流程：从注意到保持与迁移"
                : "Nine-event flow: from attention to retention/transfer"
            draft.expectedOutputIDs = ["worksheet", "lessonHandout", "presentation"]
            draft.goals = isChinese
                ? [
                    "注意与目标：快速进入任务并明确目标。",
                    "指导与表现：在指导后完成关键表现任务。",
                    "反馈与迁移：通过反馈修正并迁移应用。"
                ]
                : [
                    "Attention & objectives: enter task quickly with clear objective.",
                    "Guidance & performance: complete key performance task with scaffolds.",
                    "Feedback & transfer: refine through feedback and transfer learning."
                ]

        default:
            break
        }

        return draft
    }

    func tutorialPracticeDraft() -> CourseCreationDraft {
        let chinese = isChineseUI()
        let minimalModelID = tutorialPracticeRequiredModelID
        return tutorialPracticeDraft(for: minimalModelID, isChinese: chinese)
    }

    func tutorialPracticeAutofillTextForCurrentStep(isChinese: Bool) -> String? {
        switch tutorialStepIndex {
        case 4:
            return isChinese
                ? "聚焦牛顿第一定律：学生能够解释“物体在不受外力或合力为零时保持静止或匀速直线运动”的规律，并能用“惯性”解释常见现象。"
                : "Focus on Newton's First Law: students explain that an object remains at rest or in uniform straight-line motion when net force is zero, and use inertia to explain everyday phenomena."
        case 5:
            return isChinese
                ? "证据设计：使用“公交车急刹前倾、抽桌布实验、滑板滑行”三个案例。每个案例记录三项证据：受力情况、运动状态变化、是否符合惯性解释。"
                : "Evidence design: use three cases (bus sudden braking, tablecloth pull, skateboard glide). Capture three points per case: force condition, motion-state change, and inertia consistency."
        case 6:
            return isChinese
                ? "活动安排：先做现象实验并记录，再分组讨论证据与结论，最后全班汇总形成牛顿第一定律表述并完成即时小结。"
                : "Activity flow: run phenomenon experiments and record observations, then group discussion on evidence and claims, then whole-class synthesis of Newton's First Law with a quick exit summary."
        default:
            return nil
        }
    }

    /// Called when user opens docs — detect if we should chain from canvasBasics to modelsIntro
    func handleDocsOpenedDuringTutorial() {
        if activeTutorial == .canvasBasics {
            let steps = canvasBasicsSteps
            if tutorialStepIndex < steps.count,
               steps[tutorialStepIndex].advanceMode == .waitForDocs {
                // User opened docs as instructed — chain to modelsIntro
                withAnimation(.easeInOut(duration: 0.25)) {
                    activeTutorial = nil
                }
                tutorialStepIndex = 0
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    startTutorial(.modelsIntro)
                }
            }
        }
    }

    func handleDocsSelectionDuringTutorial(_ selectedType: String?) {
        guard activeTutorial == .modelsIntro else { return }
        let steps = modelsIntroSteps
        guard tutorialStepIndex < steps.count else { return }
        guard steps[tutorialStepIndex].advanceMode == .waitForModelDocSelection else { return }
        guard let selectedType, selectedType.hasPrefix("EduModelTemplate") else { return }
        advanceTutorialStep()
    }

    func handleTutorialStatsChange(fileID: UUID, stats: NodeEditorCanvasStats) {
        guard activeTutorial != nil else { return }
        tutorialPreviousNodeCount = stats.nodeCount
        tutorialPreviousConnectionCount = stats.connectionCount

        guard activeTutorial == .practice else { return }
        guard fileID == tutorialPracticeFileID else { return }
        guard tutorialStepIndex < practiceSteps.count else { return }
        let mode = practiceSteps[tutorialStepIndex].advanceMode
        guard mode == .waitForCanvasZoomOut else {
            tutorialPracticeZoomStepBaseline = nil
            return
        }

        if tutorialPracticeZoomStepBaseline == nil {
            tutorialPracticeZoomStepBaseline = stats.zoomPercent
            return
        }
        let baseline = tutorialPracticeZoomStepBaseline ?? tutorialPracticeInitialZoomPercent
        let threshold = max(55, baseline - 10)
        guard stats.zoomPercent <= threshold else { return }
        tutorialPracticeZoomStepBaseline = nil
        advanceTutorialStep()
    }

    func transitionFromCanvasBasicsToModelsIntro() {
        guard activeTutorial == .canvasBasics else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            activeTutorial = nil
        }
        tutorialStepIndex = 0

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            showingDocs = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                startTutorial(.modelsIntro)
            }
        }
    }

    func tutorialSemanticSnapshotData(from data: Data) -> Data? {
        guard let document = try? decodeDocument(from: data) else { return nil }
        let snapshot = TutorialSemanticSnapshot(
            nodes: document.nodes,
            connections: document.connections,
            canvasState: document.canvasState
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(snapshot)
    }

    func handleTutorialDocumentDataPersisted(fileID: UUID, data: Data) {
        guard let tutorial = activeTutorial else { return }
        guard let document = try? decodeDocument(from: data) else { return }

        switch tutorial {
        case .canvasBasics:
            guard fileID == tutorialDedicatedFileID else { return }
            evaluateCanvasBasicsProgress(document)
        case .practice:
            guard fileID == tutorialPracticeFileID else { return }
            evaluatePracticeDocumentProgress(fileID: fileID, data: data)
        case .aboutDemo, .modelsIntro, .explore:
            break
        }
    }

    func evaluateCanvasBasicsProgress(_ document: GNodeDocument) {
        guard activeTutorial == .canvasBasics else { return }

        for _ in 0..<8 {
            guard tutorialStepIndex < canvasBasicsSteps.count else { return }

            switch tutorialStepIndex {
            case 0:
                guard document.nodes.contains(where: { $0.nodeType == EduNodeType.knowledge }) else { return }
                advanceTutorialStep()

            case 1:
                guard document.nodes.contains(where: { EduNodeType.allToolkitTypes.contains($0.nodeType) }) else { return }
                advanceTutorialStep()

            case 2:
                let hasExpectedConnection = EduNodeType.allToolkitTypes.contains { toolkitType in
                    hasTutorialConnection(
                        in: document,
                        sourceType: EduNodeType.knowledge,
                        sourcePortName: S("edu.knowledge.output.content"),
                        targetType: toolkitType,
                        targetPortName: S("edu.toolkit.input.knowledge")
                    )
                }
                guard hasExpectedConnection else { return }
                advanceTutorialStep()

            case 3:
                let isReady = document.nodes.contains { node in
                    node.nodeType == EduNodeType.evaluation && !node.inputPorts.isEmpty
                }
                guard isReady else { return }
                advanceTutorialStep()

            case 4:
                let hasExpectedConnection = EduNodeType.allToolkitTypes.contains { toolkitType in
                    hasTutorialConnection(
                        in: document,
                        sourceType: toolkitType,
                        sourcePortName: S("edu.output.toolkit"),
                        targetType: EduNodeType.evaluation,
                        targetPortName: nil
                    )
                }
                guard hasExpectedConnection else { return }
                tutorialCanvasEvaluationCountBeforeDelete = document.nodes.filter { $0.nodeType == EduNodeType.evaluation }.count
                advanceTutorialStep()

            case 5:
                let currentEvaluationCount = document.nodes.filter { $0.nodeType == EduNodeType.evaluation }.count
                let baseline = tutorialCanvasEvaluationCountBeforeDelete ?? currentEvaluationCount
                tutorialCanvasEvaluationCountBeforeDelete = baseline
                guard currentEvaluationCount < baseline else { return }
                tutorialCanvasConnectionCountBeforeDelete = document.connections.count
                advanceTutorialStep()

            case 6:
                let currentConnectionCount = document.connections.count
                let baseline = tutorialCanvasConnectionCountBeforeDelete ?? currentConnectionCount
                tutorialCanvasConnectionCountBeforeDelete = baseline
                guard currentConnectionCount < baseline else { return }
                transitionFromCanvasBasicsToModelsIntro()
                return

            default:
                return
            }
        }
    }

    func evaluatePracticeDocumentProgress(fileID: UUID, data: Data) {
        guard activeTutorial == .practice else { return }
        guard let document = try? decodeDocument(from: data) else { return }

        for _ in 0..<8 {
            guard tutorialStepIndex < practiceSteps.count else { return }
            let step = practiceSteps[tutorialStepIndex]

            if step.advanceMode != .waitForAdditionalKnowledgeEdit {
                tutorialPracticeKnowledgeModificationBaseline = nil
            }
            if step.advanceMode != .waitForKnowledgeToSpecificToolkitConnectionAdded {
                tutorialPracticeConnectionStepBaseline = nil
            }
            if step.advanceMode != .waitForKnowledgeKeywordEdit && step.advanceMode != .waitForAdditionalKnowledgeEdit {
                tutorialPracticeKnowledgeStepTargetNodeID = nil
                tutorialPracticeKnowledgeStepEntryContent = nil
            }

            switch step.advanceMode {
            case .waitForCourseCreated:
                guard tutorialPracticeFileID == fileID else { return }
                advanceTutorialStep()

            case .waitForKnowledgeKeywordEdit:
                guard let targetNodeID = resolvedTutorialPracticeKnowledgeTargetNodeID(in: document) else { return }
                let currentContent = tutorialKnowledgeContent(in: document, nodeID: targetNodeID)
                if tutorialPracticeKnowledgeStepTargetNodeID != targetNodeID {
                    tutorialPracticeKnowledgeStepTargetNodeID = targetNodeID
                    tutorialPracticeKnowledgeStepEntryContent = currentContent
                    spotlightTutorialPracticeKnowledgeTarget()
                    return
                }
                if tutorialPracticeGuidedFillPendingStepIndex == tutorialStepIndex {
                    return
                }
                let baselineContent = tutorialPracticeKnowledgeStepEntryContent ?? currentContent
                guard currentContent != baselineContent else { return }
                guard containsTutorialNewtonKeyword(currentContent) else { return }
                tutorialPracticeKnowledgeModificationBaseline = nil
                tutorialPracticeKnowledgeStepTargetNodeID = nil
                tutorialPracticeKnowledgeStepEntryContent = nil
                advanceTutorialStep()

            case .waitForAdditionalKnowledgeEdit:
                guard let targetNodeID = resolvedTutorialPracticeKnowledgeTargetNodeID(in: document) else { return }
                let currentContent = tutorialKnowledgeContent(in: document, nodeID: targetNodeID)
                if tutorialPracticeKnowledgeStepTargetNodeID != targetNodeID {
                    tutorialPracticeKnowledgeStepTargetNodeID = targetNodeID
                    tutorialPracticeKnowledgeStepEntryContent = currentContent
                    spotlightTutorialPracticeKnowledgeTarget()
                    return
                }
                if tutorialPracticeGuidedFillPendingStepIndex == tutorialStepIndex {
                    return
                }
                let baselineContent = tutorialPracticeKnowledgeStepEntryContent ?? currentContent
                guard currentContent != baselineContent else { return }
                guard !currentContent.isEmpty else { return }
                tutorialPracticeKnowledgeModificationBaseline = nil
                tutorialPracticeKnowledgeStepTargetNodeID = nil
                tutorialPracticeKnowledgeStepEntryContent = nil
                advanceTutorialStep()

            case .waitForSpecificToolkitConfigured:
                guard let toolkitNodeID = tutorialPreparedSourceAnalysisToolkitNodeID(
                    fileID: fileID,
                    data: data,
                    document: document
                ) else { return }
                tutorialPracticeConfiguredToolkitNodeID = toolkitNodeID
                tutorialPracticeConnectionStepBaseline = nil
                advanceTutorialStep()

            case .waitForKnowledgeToSpecificToolkitConnectionAdded:
                let targetToolkitNodeID = tutorialPracticeConfiguredToolkitNodeID
                    ?? tutorialConfiguredSourceAnalysisToolkitNodeID(in: document)
                guard let targetToolkitNodeID else { return }
                tutorialPracticeConfiguredToolkitNodeID = targetToolkitNodeID
                let requiredSourceNodeID = tutorialPracticeConnectionSourceNodeID(in: document)
                let targetToolkitNodeIDs = tutorialSourceAnalysisToolkitNodeIDs(in: document)
                guard !targetToolkitNodeIDs.isEmpty else { return }
                if hasTutorialKnowledgeConnection(
                    toAny: targetToolkitNodeIDs,
                    in: document,
                    requiredSourceNodeID: requiredSourceNodeID
                ) {
                    tutorialPracticeConnectionStepBaseline = nil
                    advanceTutorialStep()
                    return
                }
                let currentConnections = tutorialConnectionSignatures(in: document)
                if tutorialPracticeConnectionStepBaseline == nil {
                    tutorialPracticeConnectionStepBaseline = currentConnections
                    return
                }
                let baselineConnections = tutorialPracticeConnectionStepBaseline ?? currentConnections
                if !hasNewTutorialKnowledgeConnection(
                    toAny: targetToolkitNodeIDs,
                    in: document,
                    baselineConnections: baselineConnections,
                    requiredSourceNodeID: requiredSourceNodeID
                ) {
                    return
                }
                tutorialPracticeConnectionStepBaseline = nil
                advanceTutorialStep()

            default:
                return
            }
        }
    }

    func hasTutorialConnection(
        in document: GNodeDocument,
        sourceType: String,
        sourcePortName: String,
        targetType: String,
        targetPortName: String?
    ) -> Bool {
        let nodesByID = Dictionary(uniqueKeysWithValues: document.nodes.map { ($0.id, $0) })

        for connection in document.connections {
            guard let sourceNode = nodesByID[connection.sourceNodeID],
                  let targetNode = nodesByID[connection.targetNodeID],
                  sourceNode.nodeType == sourceType,
                  targetNode.nodeType == targetType else {
                continue
            }

            guard let sourcePort = sourceNode.outputPorts.first(where: { $0.id == connection.sourcePortID }),
                  sourcePort.name == sourcePortName else {
                continue
            }

            guard let targetPort = targetNode.inputPorts.first(where: { $0.id == connection.targetPortID }) else {
                continue
            }
            if let targetPortName, targetPort.name != targetPortName {
                continue
            }
            return true
        }

        return false
    }

    func tutorialKnowledgeContentByNodeID(in document: GNodeDocument) -> [UUID: String] {
        Dictionary(uniqueKeysWithValues: document.nodes.compactMap { node in
            guard node.nodeType == EduNodeType.knowledge else { return nil }
            let content = (node.nodeData["content"] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (node.id, content)
        })
    }

    func tutorialKnowledgeContent(in document: GNodeDocument, nodeID: UUID) -> String {
        document.nodes.first(where: { $0.id == nodeID })?.nodeData["content"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func containsTutorialNewtonKeyword(_ raw: String) -> Bool {
        let normalized = raw.lowercased()
        let tokens = [
            "牛顿第一定律",
            "牛顿第一运动定律",
            "惯性定律",
            "newton's first law",
            "newton first law",
            "law of inertia"
        ]
        return tokens.contains(where: { normalized.contains($0) })
    }

    func tutorialPreparedSourceAnalysisToolkitNodeID(
        fileID: UUID,
        data: Data,
        document: GNodeDocument
    ) -> UUID? {
        let candidateIndex = document.nodes.indices.reversed().first { index in
            let node = document.nodes[index]
            return node.nodeType == EduNodeType.toolkitPerceptionInquiry
                && !tutorialPracticeInitialNodeIDs.contains(node.id)
        }
        guard let candidateIndex else { return nil }

        let node = document.nodes[candidateIndex]
        var nodeData = node.nodeData
        var changed = false

        if (nodeData["toolkitMethodID"] ?? "").lowercased() != "source_analysis" {
            nodeData["toolkitMethodID"] = "source_analysis"
            changed = true
        }

        var textFields = parseJSONStringDictionary(nodeData["toolkitTextFields"])
        let defaultSourceSet = isChineseUI()
            ? "公交车急刹/桌布抽拉/滑板滑行案例"
            : "Bus sudden brake / tablecloth pull / skateboard glide cases"
        let defaultRule = isChineseUI()
            ? "提取每个案例的“受力情况、运动状态变化、是否符合惯性”三条证据"
            : "Extract three evidence points per case: force condition, motion-state change, inertia consistency"
        let defaultMatrix = isChineseUI()
            ? "惯性存在 | 急刹前后乘客前倾 | 高\n受力改变运动 | 外力改变速度方向 | 高"
            : "Inertia exists | Passenger leans forward during braking | High\nForce changes motion | External force changes velocity direction | High"

        if (textFields["source_analysis_set"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            textFields["source_analysis_set"] = defaultSourceSet
            changed = true
        }
        if (textFields["source_analysis_rule"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            textFields["source_analysis_rule"] = defaultRule
            changed = true
        }
        if (textFields["source_analysis_matrix"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            textFields["source_analysis_matrix"] = defaultMatrix
            changed = true
        }

        var updatedDocument = document
        if let stage3NodeID = tutorialPracticeLearningPlanSourceNodeID(in: updatedDocument),
           let sourceNode = updatedDocument.nodes.first(where: { $0.id == stage3NodeID }) {
            let sourcePort = sourceNode.outputPorts.first(where: { $0.name == S("edu.knowledge.output.content") })
                ?? sourceNode.outputPorts.first
            let targetPort = node.inputPorts.first(where: { $0.name == S("edu.toolkit.input.knowledge") })
                ?? node.inputPorts.first

            if let sourcePort, let targetPort {
                let exists = updatedDocument.connections.contains { connection in
                    connection.sourceNodeID == stage3NodeID
                        && connection.targetNodeID == node.id
                        && connection.sourcePortID == sourcePort.id
                        && connection.targetPortID == targetPort.id
                }
                if !exists {
                    updatedDocument.connections.append(
                        NodeConnection(
                            sourceNode: stage3NodeID,
                            sourcePort: sourcePort.id,
                            targetNode: node.id,
                            targetPort: targetPort.id,
                            dataType: sourcePort.dataType
                        )
                    )
                    changed = true
                }
            }
        }

        if changed {
            nodeData["toolkitTextFields"] = encodeJSONStringDictionary(textFields)
            let updatedNode = SerializableNode(
                id: node.id,
                nodeType: node.nodeType,
                attributes: node.attributes,
                inputPorts: node.inputPorts,
                outputPorts: node.outputPorts,
                nodeData: nodeData
            )
            updatedDocument.nodes[candidateIndex] = updatedNode
            if let encoded = try? encodeDocument(updatedDocument), encoded != data {
                persistWorkspaceFileData(id: fileID, data: encoded)
            }
            return nil
        }

        return node.id
    }

    func encodeJSONStringDictionary(_ dictionary: [String: String]) -> String {
        guard let data = try? JSONEncoder().encode(dictionary),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    func tutorialConfiguredSourceAnalysisToolkitNodeID(in document: GNodeDocument) -> UUID? {
        for node in document.nodes {
            guard node.nodeType == EduNodeType.toolkitPerceptionInquiry else { continue }
            guard !tutorialPracticeInitialNodeIDs.contains(node.id) else { continue }
            guard (node.nodeData["toolkitMethodID"] ?? "").lowercased() == "source_analysis" else { continue }
            return node.id
        }
        return nil
    }

    func hasTutorialKnowledgeConnection(
        toAny toolkitNodeIDs: Set<UUID>,
        in document: GNodeDocument,
        requiredSourceNodeID: UUID?
    ) -> Bool {
        hasNewTutorialKnowledgeConnection(
            toAny: toolkitNodeIDs,
            in: document,
            baselineConnections: [],
            requiredSourceNodeID: requiredSourceNodeID
        )
    }

    func hasNewTutorialKnowledgeConnection(
        toAny toolkitNodeIDs: Set<UUID>,
        in document: GNodeDocument,
        baselineConnections: Set<TutorialConnectionSignature>,
        requiredSourceNodeID: UUID?
    ) -> Bool {
        guard !toolkitNodeIDs.isEmpty else { return false }
        let nodesByID = Dictionary(uniqueKeysWithValues: document.nodes.map { ($0.id, $0) })
        let currentConnections = tutorialConnectionSignatures(in: document)

        for signature in currentConnections.subtracting(baselineConnections) {
            guard let sourceNode = nodesByID[signature.sourceNodeID],
                  let targetNode = nodesByID[signature.targetNodeID],
                  toolkitNodeIDs.contains(signature.targetNodeID),
                  sourceNode.nodeType == EduNodeType.knowledge,
                  EduNodeType.allToolkitTypes.contains(targetNode.nodeType) else {
                continue
            }
            if let requiredSourceNodeID,
               signature.sourceNodeID != requiredSourceNodeID {
                continue
            }
            guard let sourcePort = sourceNode.outputPorts.first(where: { $0.id == signature.sourcePortID }),
                  sourcePort.name == S("edu.knowledge.output.content") else {
                continue
            }
            guard let targetPort = targetNode.inputPorts.first(where: { $0.id == signature.targetPortID }),
                  targetPort.name == S("edu.toolkit.input.knowledge") else {
                continue
            }
            return true
        }

        return false
    }

    func tutorialConnectionSignatures(in document: GNodeDocument) -> Set<TutorialConnectionSignature> {
        Set(
            document.connections.map { connection in
                TutorialConnectionSignature(
                    sourceNodeID: connection.sourceNodeID,
                    sourcePortID: connection.sourcePortID,
                    targetNodeID: connection.targetNodeID,
                    targetPortID: connection.targetPortID
                )
            }
        )
    }

    func handleTutorialSheetStateChange() {
        guard activeTutorial == .practice else { return }
        guard tutorialStepIndex < practiceSteps.count else { return }
        let mode = practiceSteps[tutorialStepIndex].advanceMode
        guard mode == .waitForCreateCourseSheet else { return }
        guard showingCreateCourseSheet else { return }
        advanceTutorialStep()
    }

    func handleTutorialPresentationStateChange() {
        guard activeTutorial == .practice else { return }
        guard tutorialStepIndex < practiceSteps.count else { return }
        let mode = practiceSteps[tutorialStepIndex].advanceMode

        switch mode {
        case .waitForPresentationEnter:
            guard let practiceFileID = tutorialPracticeFileID,
                  activePresentationModeFileID == practiceFileID else {
                return
            }
            tutorialPracticeHasEnteredPresentation = true
            advanceTutorialStep()

        case .waitForStylingPanelEnter:
            guard let practiceFileID = tutorialPracticeFileID,
                  activePresentationStylingFileID == practiceFileID else {
                return
            }
            advanceTutorialStep()

        case .waitForPresentationExit:
            guard tutorialPracticeHasEnteredPresentation else { return }
            guard activePresentationModeFileID == nil else { return }
            advanceTutorialStep()

        default:
            break
        }
    }

    func handleTutorialPreviewStateChange() {
        guard activeTutorial == .practice else { return }
        guard tutorialStepIndex < practiceSteps.count else { return }
        let mode = practiceSteps[tutorialStepIndex].advanceMode

        switch mode {
        case .waitForLessonPlanPreview:
            guard lessonPlanPreviewPayload != nil else { return }
            advanceTutorialStep()

        case .waitForPresentationPreview:
            guard presentationPreviewPayload != nil else { return }
            advanceTutorialStep()

        default:
            break
        }
    }

    func handleTutorialSelectionChange() {
        guard activeTutorial == .explore else { return }
        guard tutorialStepIndex < exploreSteps.count else { return }
        let mode = exploreSteps[tutorialStepIndex].advanceMode
        guard mode == .waitForBirdExampleSelection else { return }
        guard let file = selectedWorkspaceFile, isBirdExampleFile(file) else { return }
        advanceTutorialStep()
    }

    func isBirdExampleFile(_ file: GNodeWorkspaceFile) -> Bool {
        file.subject.contains("美育")
            || file.subject.contains("Aesthetic")
            || file.name.contains("Bird")
            || file.name.contains("观鸟")
    }

}
