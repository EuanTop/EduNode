import SwiftUI
import GNodeKit
import SwiftData

extension ContentView {
    func editorToolbarActions(for file: GNodeWorkspaceFile) -> [NodeEditorToolbarAction] {
        let isActive = isPresentationModeEngaged
        return [
            NodeEditorToolbarAction(
                id: "edunode.present",
                title: S("app.presentation.button"),
                systemImage: "play.rectangle.on.rectangle",
                accent: .orange,
                isActive: isActive,
                isPulsing: shouldPulsePresentButton,
                minWidth: 108
            ) {
                handlePresentationButtonTap(for: file)
            }
        ]
    }

    var isPresentationModeEngaged: Bool {
        activePresentationModeFileID != nil || presentationModeLoadingFileID != nil
    }

    @ViewBuilder
    var sidebarToggleButton: some View {
        let btn = Button {
            withAnimation { splitVisibility = .automatic }
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 38, height: 38)
        }

        if #available(iOS 26.0, macOS 26.0, *) {
            btn
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
        } else {
            btn
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
        }
    }

    func handlePresentationButtonTap(for file: GNodeWorkspaceFile) {
        guard !isHandlingPresentationButtonTap else { return }
        isHandlingPresentationButtonTap = true

        Task { @MainActor in
            // Coalesce duplicate callbacks generated from a single physical tap.
            await Task.yield()

            if isPresentationModeEngaged {
                exitPresentationMode()
            } else {
                togglePresentationMode(for: file)
            }

            await Task.yield()
            isHandlingPresentationButtonTap = false
        }
    }

    func editorConnectionAppearance(
        for connection: NodeConnection,
        sourceNodeType: String?,
        targetNodeType: String?
    ) -> NodeEditorConnectionAppearance? {
        if let previewState = connection.previewState {
            switch previewState {
            case "add":
                return NodeEditorConnectionAppearance(
                    color: Color.green.opacity(connection.previewIsFocused == true ? 0.98 : 0.86),
                    lineWidth: connection.previewIsFocused == true ? 5 : 4,
                    dash: []
                )
            case "remove":
                return NodeEditorConnectionAppearance(
                    color: Color.red.opacity(connection.previewIsFocused == true ? 0.96 : 0.84),
                    lineWidth: connection.previewIsFocused == true ? 4.6 : 3.8,
                    dash: [12, 8]
                )
            default:
                break
            }
        }
        let involvesEvaluation = sourceNodeType == EduNodeType.evaluation || targetNodeType == EduNodeType.evaluation
        guard involvesEvaluation else { return nil }
        return NodeEditorConnectionAppearance(
            color: Color.gray.opacity(0.78),
            lineWidth: 2.5,
            dash: [10, 7]
        )
    }

    func exitPresentationMode() {
        let activeID = activePresentationModeFileID
        let loadingID = presentationModeLoadingFileID

        activePresentationModeFileID = nil
        if let activeID, activePresentationStylingFileID == activeID {
            activePresentationStylingFileID = nil
        }
        presentationModeActivationToken = nil
        presentationModeLoadingFileID = nil

        if let activeID {
            pendingPresentationThumbnailIDsByFile[activeID] = nil
        }
        if let loadingID {
            pendingPresentationThumbnailIDsByFile[loadingID] = nil
        }
    }

    func togglePresentationMode(for file: GNodeWorkspaceFile) {
        // Guard against duplicate button callbacks in the same interaction cycle.
        // Enter action is idempotent; we never "toggle back" to exit from here.
        if activePresentationModeFileID != nil || presentationModeLoadingFileID != nil {
            return
        }

        activePresentationStylingFileID = nil
        workspaceAgentSidebarFileID = nil
        let activationToken = UUID()
        presentationModeActivationToken = activationToken
        presentationModeLoadingFileID = file.id

        Task { @MainActor in
            await Task.yield()
            guard presentationModeActivationToken == activationToken else { return }

            // Force a fresh restore each time user enters Present mode to avoid stale in-memory state.
            hydratePresentationState(for: file, force: true)

            let rawDeck = EduPresentationPlanner.makeDeck(graphData: file.data)
            let deck = filteredPresentationDeck(for: file.id, from: rawDeck)
            guard !deck.orderedSlides.isEmpty else {
                if presentationModeActivationToken == activationToken {
                    presentationModeLoadingFileID = nil
                    pendingPresentationThumbnailIDsByFile[file.id] = nil
                    showingPresentationEmptyAlert = true
                }
                return
            }
            let groups = presentationGroups(for: file.id, deck: deck)
            guard !groups.isEmpty else {
                if presentationModeActivationToken == activationToken {
                    presentationModeLoadingFileID = nil
                    pendingPresentationThumbnailIDsByFile[file.id] = nil
                    showingPresentationEmptyAlert = true
                }
                return
            }

            guard presentationModeActivationToken == activationToken else { return }
            let pendingThumbnailIDs = Set(groups.map(\.id))
            pendingPresentationThumbnailIDsByFile[file.id] = pendingThumbnailIDs
            activePresentationModeFileID = file.id
            if let firstGroup = groups.first {
                selectPresentationGroup(fileID: file.id, group: firstGroup)
            }
            if pendingThumbnailIDs.isEmpty {
                presentationModeLoadingFileID = nil
                pendingPresentationThumbnailIDsByFile[file.id] = nil
            } else {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    guard presentationModeActivationToken == activationToken,
                          presentationModeLoadingFileID == file.id else { return }
                    presentationModeLoadingFileID = nil
                    pendingPresentationThumbnailIDsByFile[file.id] = nil
                }
            }
        }
    }

    func markPresentationThumbnailLoaded(fileID: UUID, groupID: UUID) {
        guard presentationModeLoadingFileID == fileID else { return }
        guard var pendingIDs = pendingPresentationThumbnailIDsByFile[fileID] else { return }
        guard pendingIDs.contains(groupID) else { return }
        pendingIDs.remove(groupID)
        if pendingIDs.isEmpty {
            pendingPresentationThumbnailIDsByFile[fileID] = nil
            presentationModeLoadingFileID = nil
        } else {
            pendingPresentationThumbnailIDsByFile[fileID] = pendingIDs
        }
    }

    func openPresentationPreview(for file: GNodeWorkspaceFile, graphData: Data? = nil) {
        let sourceData = graphData ?? file.data
        let rawDeck = EduPresentationPlanner.makeDeck(graphData: sourceData)
        let deck = filteredPresentationDeck(for: file.id, from: rawDeck)
        guard !deck.orderedSlides.isEmpty else {
            showingPresentationEmptyAlert = true
            return
        }
        let groups = presentationGroups(for: file.id, deck: deck)
        let slides = EduPresentationPlanner.composeSlides(
            from: groups,
            isChinese: isChineseUI()
        )
        let overlayHTMLBySlideID = presentationOverlayHTMLBySlideID(fileID: file.id, groups: groups)
        let nativeTextOverridesBySlideID = presentationNativeTextOverridesBySlideID(fileID: file.id, groups: groups)
        let nativeContentOverridesBySlideID = presentationNativeContentOverridesBySlideID(fileID: file.id, groups: groups)
        let nativeLayoutOverridesBySlideID = presentationNativeLayoutOverridesBySlideID(fileID: file.id, groups: groups)
        let slideGroupIDBySlideID = Dictionary(uniqueKeysWithValues: zip(slides.map(\.id), groups.map(\.id)))
        presentationPreviewPayload = EduPresentationPreviewPayload(
            sourceFile: file,
            courseName: file.name,
            baseFileName: sanitizedExportBaseName(file.name),
            slides: slides,
            pageStyle: resolvedPresentationPageStyle(fileID: file.id),
            textTheme: resolvedPresentationTextTheme(fileID: file.id),
            overlayHTMLBySlideID: overlayHTMLBySlideID,
            nativeTextOverridesBySlideID: nativeTextOverridesBySlideID,
            nativeContentOverridesBySlideID: nativeContentOverridesBySlideID,
            nativeLayoutOverridesBySlideID: nativeLayoutOverridesBySlideID,
            slideGroupIDBySlideID: slideGroupIDBySlideID,
            onApplyOverrides: { overrides in
                applyPresentationAgentOverrides(
                    fileID: file.id,
                    slideGroupIDBySlideID: slideGroupIDBySlideID,
                    overridesBySlideID: overrides
                )
            }
        )
    }

    func openLessonPlanPreview(
        for file: GNodeWorkspaceFile,
        graphData: Data? = nil,
        context: EduLessonPlanContext? = nil,
        baseName: String? = nil
    ) {
        let sourceData = graphData ?? file.data
        let resolvedContext = context ?? EduLessonPlanContext(file: file)
        let resolvedBaseName = baseName ?? sanitizedExportBaseName(file.name)
        let evaluationSnapshot = evaluationScoreSnapshot(for: file, graphData: sourceData)
        lessonPlanSetupPayload = EduLessonPlanSetupPayload(
            sourceFile: file,
            context: resolvedContext,
            graphData: sourceData,
            baseFileName: resolvedBaseName,
            evaluationSnapshot: evaluationSnapshot
        )
    }

    func finishPresentationCourse(for file: GNodeWorkspaceFile, graphData: Data) {
        openLessonPlanPreview(for: file, graphData: graphData)
        if EduPlanning.hasEvaluationDesign(in: graphData) {
            file.lessonPlanMarkedDone = true
            file.evaluationMarkedDone = true
            try? modelContext.save()
        }
    }

    func evaluationScoreSnapshot(
        for file: GNodeWorkspaceFile,
        graphData: Data
    ) -> EduEvaluationScoreSnapshot? {
        let scoreMap = inlineEvaluationScoreValuesByFile[file.id] ?? [:]
        let completionMap = inlineEvaluationCompletionValuesByFile[file.id] ?? [:]
        guard !scoreMap.isEmpty || !completionMap.isEmpty else { return nil }
        guard let document = try? decodeDocument(from: graphData) else { return nil }

        let students = parsedStudentRosterEntries(from: file.studentProfile)
        guard !students.isEmpty else { return nil }

        let stateByNodeID = Dictionary(uniqueKeysWithValues: document.canvasState.map { ($0.nodeID, $0) })
        let evaluationNodes = document.nodes
            .filter { $0.nodeType == EduNodeType.evaluation }
            .sorted { lhs, rhs in
                let lhsState = stateByNodeID[lhs.id]
                let rhsState = stateByNodeID[rhs.id]
                let lx = lhsState?.positionX ?? 0
                let rx = rhsState?.positionX ?? 0
                if abs(lx - rx) > 0.5 { return lx < rx }
                let ly = lhsState?.positionY ?? 0
                let ry = rhsState?.positionY ?? 0
                if abs(ly - ry) > 0.5 { return ly < ry }
                return lhs.id.uuidString < rhs.id.uuidString
            }

        var entries: [EduEvaluationScoreEntry] = []
        for node in evaluationNodes {
            let customName = stateByNodeID[node.id]?.customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let evalTitle = customName.isEmpty ? node.attributes.name : customName
            let textFields = parseJSONStringDictionary(node.nodeData["evaluationTextFields"])
            let indicatorsRaw = textFields["evaluation_indicators"] ?? node.nodeData["evaluation_indicators"] ?? ""
            let indicators = parseEvaluationIndicators(from: indicatorsRaw, fallbackInputPorts: node.inputPorts)

            for indicator in indicators {
                for student in students {
                    let key = InlineEvaluationScoreKey(
                        nodeID: node.id,
                        indicatorID: indicator.id,
                        studentName: student.name
                    )
                    switch indicator.kind {
                    case .score:
                        guard let value = scoreMap[key] else { continue }
                        entries.append(
                            EduEvaluationScoreEntry(
                                evaluationTitle: evalTitle,
                                indicatorTitle: indicator.name,
                                indicatorKindLabel: isChineseUI() ? "分数制" : "Score",
                                studentName: "#\(student.sequence) \(studentNameLabel(student))",
                                valueText: value
                            )
                        )
                    case .completion:
                        guard let value = completionMap[key] else { continue }
                        entries.append(
                            EduEvaluationScoreEntry(
                                evaluationTitle: evalTitle,
                                indicatorTitle: indicator.name,
                                indicatorKindLabel: isChineseUI() ? "完成制" : "Completion",
                                studentName: "#\(student.sequence) \(studentNameLabel(student))",
                                valueText: value ? (isChineseUI() ? "5 ✓" : "5 ✓") : "0"
                            )
                        )
                    }
                }
            }
        }

        guard !entries.isEmpty else { return nil }
        return EduEvaluationScoreSnapshot(entries: entries)
    }

    func effectivePresentationBreaks(fileID: UUID, slideCount: Int) -> Set<Int> {
        guard slideCount > 1 else { return [] }
        let maxBreak = slideCount - 2
        let stored = presentationBreaksByFile[fileID] ?? EduPresentationPlanner.defaultBreaks(count: slideCount)
        return Set(stored.filter { $0 >= 0 && $0 <= maxBreak })
    }

    func presentationGroups(for fileID: UUID, deck: EduPresentationDeck) -> [EduPresentationSlideGroup] {
        EduPresentationPlanner.groupSlides(
            deck.orderedSlides,
            breaks: effectivePresentationBreaks(fileID: fileID, slideCount: deck.orderedSlides.count)
        )
    }

    func filteredPresentationDeck(for fileID: UUID, from rawDeck: EduPresentationDeck) -> EduPresentationDeck {
        let excludedNodeIDs = presentationExcludedNodeIDsByFile[fileID] ?? []
        guard !excludedNodeIDs.isEmpty else { return rawDeck }
        let visibleSlides = rawDeck.orderedSlides.filter { !excludedNodeIDs.contains($0.id) }
        return EduPresentationDeck(orderedSlides: visibleSlides)
    }

    func presentationOverlayHTMLBySlideID(
        fileID: UUID,
        groups: [EduPresentationSlideGroup]
    ) -> [UUID: String] {
        var result: [UUID: String] = [:]
        let slideAspect = max(0.75, resolvedPresentationPageStyle(fileID: fileID).aspectPreset.ratio)
        let textTheme = resolvedPresentationTextTheme(fileID: fileID)
        for group in groups {
            let overlays = presentationStylingState(fileID: fileID, groupID: group.id).overlays
            let html = presentationOverlayLayerHTML(
                overlays: overlays,
                slideAspect: slideAspect,
                textTheme: textTheme
            )
            if !html.isEmpty {
                result[group.id] = html
            }
        }
        return result
    }

    func presentationNativeTextOverridesBySlideID(
        fileID: UUID,
        groups: [EduPresentationSlideGroup]
    ) -> [UUID: [PresentationNativeElement: PresentationTextStyleConfig]] {
        groups.reduce(into: [:]) { partial, group in
            let map = presentationStylingState(fileID: fileID, groupID: group.id).nativeTextOverrides
            if !map.isEmpty {
                partial[group.id] = map
            }
        }
    }

    func presentationNativeContentOverridesBySlideID(
        fileID: UUID,
        groups: [EduPresentationSlideGroup]
    ) -> [UUID: [PresentationNativeElement: String]] {
        groups.reduce(into: [:]) { partial, group in
            let map = presentationStylingState(fileID: fileID, groupID: group.id).nativeContentOverrides
            if !map.isEmpty {
                partial[group.id] = map
            }
        }
    }

    func presentationNativeLayoutOverridesBySlideID(
        fileID: UUID,
        groups: [EduPresentationSlideGroup]
    ) -> [UUID: [PresentationNativeElement: PresentationNativeLayoutOverride]] {
        groups.reduce(into: [:]) { partial, group in
            let map = presentationStylingState(fileID: fileID, groupID: group.id).nativeLayoutOverrides
            if !map.isEmpty {
                partial[group.id] = map
            }
        }
    }

    func presentationOverlayLayerHTML(
        overlays: [PresentationSlideOverlay],
        slideAspect: CGFloat,
        textTheme: PresentationTextTheme
    ) -> String {
        overlays.compactMap { overlay in
            presentationOverlayNodeHTML(
                overlay,
                slideAspect: slideAspect,
                textTheme: textTheme
            )
        }.joined(separator: "\n")
    }

    func presentationOverlayNodeHTML(
        _ overlay: PresentationSlideOverlay,
        slideAspect: CGFloat,
        textTheme: PresentationTextTheme
    ) -> String? {
        _ = slideAspect
        let centerX = max(0.04, min(0.96, overlay.center.x)) * 100
        let centerY = max(0.08, min(0.92, overlay.center.y)) * 100
        let widthPercent = max(2.0, min(96.0, Double(overlay.normalizedWidth * 100)))
        let resolvedNormalizedHeight = overlay.normalizedHeight
        let heightPercent = max(2.0, min(96.0, Double(resolvedNormalizedHeight * 100)))
        let rotationDegrees = cssNumber(overlay.rotationDegrees)

        let basePositionStyle = "left:\(cssNumber(centerX))%;top:\(cssNumber(centerY))%;"
        let rotationTransformStyle = "transform:translate(-50%, -50%) rotate(\(rotationDegrees)deg);"

        if overlay.isText {
            let alignment: String
            switch overlay.textAlignment {
            case .leading:
                alignment = "left"
            case .center:
                alignment = "center"
            case .trailing:
                alignment = "right"
            }
            let themedText = textTheme.style(for: overlay.textStylePreset)
            let fontSizeCqw = max(0.7, min(8.5, themedText.sizeCqw))
            let textWeight = String(themedText.cssWeight)
            let textColor = normalizedOverlayHex(themedText.colorHex, fallback: "#111111")
            let content = escapeOverlayHTML(overlay.textContent)
                .replacingOccurrences(of: "\n", with: "<br/>")
            let style = [
                basePositionStyle,
                "width:\(cssNumber(widthPercent))%;",
                "height:\(cssNumber(heightPercent))%;",
                rotationTransformStyle,
                "color:\(textColor);",
                "font-size:\(cssNumber(fontSizeCqw))cqw;",
                "font-weight:\(textWeight);",
                "text-align:\(alignment);"
            ].joined()
            return "<div class=\"edunode-overlay text\" style=\"\(style)\">\(content)</div>"
        }

        if overlay.isRoundedRect {
            let cornerRatio = cssNumber(max(0.0, min(0.5, overlay.shapeCornerRadiusRatio)))
            let fillColor = normalizedOverlayHex(overlay.shapeFillColorHex, fallback: "#FFFFFF")
            let borderColor = normalizedOverlayHex(overlay.shapeBorderColorHex, fallback: "#D6DDE8")
            let borderWidth = cssNumber(max(0.4, overlay.shapeBorderWidth))
            let borderRadius: String
            switch overlay.shapeStyle {
            case .rectangle:
                borderRadius = "0"
            case .roundedRect:
                borderRadius = "calc(min(\(cssNumber(widthPercent))%, \(cssNumber(heightPercent))%) * \(cornerRatio))"
            case .capsule:
                borderRadius = "9999px"
            case .ellipse:
                borderRadius = "50%"
            }
            let style = [
                basePositionStyle,
                "width:\(cssNumber(widthPercent))%;",
                "height:\(cssNumber(heightPercent))%;",
                rotationTransformStyle,
                "background:\(fillColor);",
                "border:\(borderWidth)px solid \(borderColor);",
                "border-radius:\(borderRadius);"
            ].joined()
            return "<div class=\"edunode-overlay rect\" style=\"\(style)\"></div>"
        }

        if overlay.isIcon {
            let glyph = escapeOverlayHTML(iconFallbackGlyph(systemName: overlay.iconSystemName))
            let iconSizePercent = max(3.0, min(36.0, Double(overlay.normalizedWidth * 100)))
            let background = overlay.iconHasBackground
                ? normalizedOverlayHex(overlay.iconBackgroundColorHex, fallback: "#FFFFFF")
                : "transparent"
            let iconColor = normalizedOverlayHex(overlay.iconColorHex, fallback: "#111111")
            let style = [
                basePositionStyle,
                "width:\(cssNumber(iconSizePercent))%;",
                "height:\(cssNumber(iconSizePercent))%;",
                rotationTransformStyle,
                "background:\(background);",
                "color:\(iconColor);",
                "border:1px solid rgba(17,17,17,0.08);"
            ].joined()
            return "<div class=\"edunode-overlay icon\" style=\"\(style)\">\(glyph)</div>"
        }

        let aspect = max(0.15, overlay.aspectRatio)
        let imageCornerRatio = cssNumber(max(0.0, min(0.5, overlay.imageCornerRadiusRatio)))
        let imageCornerRadiusExpr = "calc(min(\(cssNumber(widthPercent))%, \(cssNumber(heightPercent))%) * \(imageCornerRatio))"
        let imageStyle = [
            basePositionStyle,
            "width:\(cssNumber(widthPercent))%;",
            "height:\(cssNumber(heightPercent))%;",
            rotationTransformStyle,
            "aspect-ratio:\(cssNumber(Double(aspect)))/1;"
        ].joined()

        let filter = presentationImageCSSFilter(style: overlay.selectedFilter, params: overlay.stylization)
        if let svg = overlay.renderedSVGString, !svg.isEmpty {
            let backgroundHex = normalizedOverlayHex(overlay.vectorBackgroundColorHex, fallback: "#FFFFFF")
            let backgroundDisplay = overlay.vectorBackgroundVisible ? "block" : "none"
            return """
            <div class="edunode-overlay vector" style="\(imageStyle)">
              <div class="edunode-image-frame" style="border-radius:\(imageCornerRadiusExpr);">
                <div class="edunode-svg-bg" style="background:\(backgroundHex);display:\(backgroundDisplay);"></div>
                <div class="edunode-svg-ink" style="filter:\(filter);">
                  <div class="edunode-svg-wrap">\(svg)</div>
                </div>
              </div>
            </div>
            """
        }

        let imageData = overlay.displayImageData
        guard !imageData.isEmpty else { return nil }
        let dataURI = presentationImageDataURI(imageData)
        let pixelatedClass = overlay.selectedFilter == .pixelPainter ? " pixelated" : ""
        return "<div class=\"edunode-overlay image\(pixelatedClass)\" style=\"\(imageStyle)\"><div class=\"edunode-image-frame\" style=\"border-radius:\(imageCornerRadiusExpr);\"><img style=\"filter:\(filter);\" src=\"\(dataURI)\" alt=\"Overlay Image\"/></div></div>"
    }

    func cssNumber(_ value: CGFloat) -> String {
        cssNumber(Double(value))
    }

    func cssNumber(_ value: Double) -> String {
        String(format: "%.3f", value)
            .replacingOccurrences(of: "\\.?0+$", with: "", options: .regularExpression)
    }

    func normalizedOverlayHex(_ value: String, fallback: String) -> String {
        var cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") {
            cleaned.removeFirst()
        }
        if cleaned.count == 3 {
            cleaned = cleaned.map { "\($0)\($0)" }.joined()
        }
        guard cleaned.count == 6, Int(cleaned, radix: 16) != nil else {
            return fallback
        }
        return "#\(cleaned.uppercased())"
    }

    func escapeOverlayHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    func iconFallbackGlyph(systemName: String) -> String {
        let key = systemName.lowercased()
        if key.contains("wrench") { return "🛠︎" }
        if key.contains("star") { return "★" }
        if key.contains("book") { return "📘" }
        if key.contains("person") { return "👤" }
        if key.contains("photo") { return "🖼︎" }
        return "●"
    }

    func mergeSlideGroupBackward(fileID: UUID, group: EduPresentationSlideGroup, slideCount: Int) {
        guard group.startIndex > 0 else { return }
        var breaks = effectivePresentationBreaks(fileID: fileID, slideCount: slideCount)
        breaks.remove(group.startIndex - 1)
        presentationBreaksByFile[fileID] = breaks
        persistPresentationState(fileID: fileID)
    }

    func mergeSlideGroupForward(fileID: UUID, group: EduPresentationSlideGroup, slideCount: Int) {
        guard group.endIndex < slideCount - 1 else { return }
        var breaks = effectivePresentationBreaks(fileID: fileID, slideCount: slideCount)
        breaks.remove(group.endIndex)
        presentationBreaksByFile[fileID] = breaks
        persistPresentationState(fileID: fileID)
    }

    func removeSlideGroupFromPresentation(fileID: UUID, group: EduPresentationSlideGroup) {
        guard !group.sourceSlides.isEmpty else { return }

        var excludedNodeIDs = presentationExcludedNodeIDsByFile[fileID] ?? Set<UUID>()
        for sourceSlide in group.sourceSlides {
            excludedNodeIDs.insert(sourceSlide.id)
        }
        presentationExcludedNodeIDsByFile[fileID] = excludedNodeIDs

        // Clear selection; the groups will be recomputed after this mutation.
        selectedPresentationGroupIDByFile[fileID] = nil

        guard activePresentationModeFileID == fileID,
              let file = workspaceFiles.first(where: { $0.id == fileID }) else { return }

        let rawDeck = EduPresentationPlanner.makeDeck(graphData: file.data)
        let filteredDeck = filteredPresentationDeck(for: fileID, from: rawDeck)
        if filteredDeck.orderedSlides.isEmpty {
            activePresentationModeFileID = nil
            if activePresentationStylingFileID == fileID {
                activePresentationStylingFileID = nil
            }
        } else if let firstGroup = presentationGroups(for: fileID, deck: filteredDeck).first {
            selectPresentationGroup(fileID: fileID, group: firstGroup)
        }
        persistPresentationState(fileID: fileID)
    }

    func focusOnSlideGroup(_ group: EduPresentationSlideGroup) {
        let targetPosition = group.sourceSlides.first?.position ?? group.anchorPosition
        cameraRequest = NodeEditorCameraRequest(canvasPosition: targetPosition)
        if let nodeID = group.sourceSlides.first?.id {
            selectionRequest = NodeEditorSelectionRequest(nodeID: nodeID)
        }
    }

    func selectPresentationGroup(fileID: UUID, group: EduPresentationSlideGroup) {
        selectedPresentationGroupIDByFile[fileID] = group.id
        // Push camera update to next runloop so selection state settles first.
        DispatchQueue.main.async {
            focusOnSlideGroup(group)
        }
        persistPresentationState(fileID: fileID)
    }

    func resolvedPresentationSelection(
        fileID: UUID,
        groups: [EduPresentationSlideGroup],
        slides: [EduPresentationComposedSlide]
    ) -> ResolvedPresentationSelection? {
        guard !groups.isEmpty, !slides.isEmpty else { return nil }

        let preferredID = selectedPresentationGroupIDByFile[fileID]
        let selectedIndex: Int
        if let preferredID,
           let index = groups.firstIndex(where: { $0.id == preferredID }) {
            selectedIndex = index
        } else {
            selectedIndex = 0
        }

        guard groups.indices.contains(selectedIndex),
              slides.indices.contains(selectedIndex) else {
            return nil
        }

        return ResolvedPresentationSelection(
            group: groups[selectedIndex],
            slide: slides[selectedIndex]
        )
    }

    @ViewBuilder
    func presentationStylingOverlay(
        file: GNodeWorkspaceFile,
        selectedGroup: EduPresentationSlideGroup,
        selectedSlide: EduPresentationComposedSlide,
        toolbarTopPadding: CGFloat,
        bottomSafeInset: CGFloat
    ) -> some View {
        PresentationStylingOverlayView(
            courseName: file.name,
            slide: selectedSlide,
            stylingState: presentationStylingState(fileID: file.id, groupID: selectedGroup.id),
            pageStyle: resolvedPresentationPageStyle(fileID: file.id),
            textTheme: resolvedPresentationTextTheme(fileID: file.id),
            topPadding: toolbarTopPadding,
            bottomReservedHeight: max(228, 208 + bottomSafeInset),
            isChinese: isChineseUI(),
            onBack: {
                activePresentationStylingFileID = nil
            },
            onReset: {
                resetPresentationStyling(fileID: file.id, groupID: selectedGroup.id)
            },
            onUndo: {
                undoPresentationStyling(fileID: file.id, groupID: selectedGroup.id)
            },
            onRedo: {
                redoPresentationStyling(fileID: file.id, groupID: selectedGroup.id)
            },
            onInsertText: {
                insertPresentationTextOverlay(fileID: file.id, groupID: selectedGroup.id)
            },
            onInsertRoundedRect: {
                insertPresentationRoundedRectOverlay(fileID: file.id, groupID: selectedGroup.id)
            },
            onInsertImage: { data in
                insertPresentationOverlayImage(fileID: file.id, groupID: selectedGroup.id, imageData: data)
            },
            onClearSelection: {
                clearPresentationOverlaySelection(fileID: file.id, groupID: selectedGroup.id)
            },
            onSelectOverlay: { overlayID in
                selectPresentationOverlay(fileID: file.id, groupID: selectedGroup.id, overlayID: overlayID)
            },
            onMoveOverlay: { overlayID, center in
                movePresentationOverlay(
                    fileID: file.id,
                    groupID: selectedGroup.id,
                    overlayID: overlayID,
                    center: center
                )
            },
            onRotateOverlay: { overlayID, deltaDegrees in
                rotatePresentationOverlay(
                    fileID: file.id,
                    groupID: selectedGroup.id,
                    overlayID: overlayID,
                    deltaDegrees: deltaDegrees
                )
            },
            onUpdateImageOverlayFrame: { overlayID, center, normalizedWidth, normalizedHeight in
                updatePresentationImageOverlayFrame(
                    fileID: file.id,
                    groupID: selectedGroup.id,
                    overlayID: overlayID,
                    center: center,
                    normalizedWidth: normalizedWidth,
                    normalizedHeight: normalizedHeight
                )
            },
            onScaleOverlay: { overlayID, scale in
                scalePresentationOverlay(
                    fileID: file.id,
                    groupID: selectedGroup.id,
                    overlayID: overlayID,
                    scale: scale
                )
            },
            onCropOverlay: { overlayID, cropRect, handle in
                cropPresentationOverlay(
                    fileID: file.id,
                    groupID: selectedGroup.id,
                    overlayID: overlayID,
                    normalizedRect: cropRect,
                    handleType: handle
                )
            },
            onDeleteOverlay: { overlayID in
                deletePresentationOverlay(
                    fileID: file.id,
                    groupID: selectedGroup.id,
                    overlayID: overlayID
                )
            },
            onExtractSubject: { overlayID in
                extractPresentationOverlaySubject(fileID: file.id, groupID: selectedGroup.id, overlayID: overlayID)
            },
            onConvertToSVG: { overlayID in
                convertPresentationOverlayToSVG(fileID: file.id, groupID: selectedGroup.id, overlayID: overlayID)
            },
            onApplyFilter: { overlayID, style in
                applyPresentationOverlayFilter(
                    fileID: file.id,
                    groupID: selectedGroup.id,
                    overlayID: overlayID,
                    style: style
                )
            },
            onUpdateStylization: { overlayID, stylization in
                updatePresentationOverlayStylization(
                    fileID: file.id,
                    groupID: selectedGroup.id,
                    overlayID: overlayID,
                    stylization: stylization
                )
            },
            onUpdateImageVectorStyle: { overlayID, strokeHex, backgroundHex, backgroundVisible in
                updatePresentationImageVectorStyle(
                    fileID: file.id,
                    groupID: selectedGroup.id,
                    overlayID: overlayID,
                    strokeHex: strokeHex,
                    backgroundHex: backgroundHex,
                    backgroundVisible: backgroundVisible
                )
            },
            onUpdateImageCornerRadius: { overlayID, cornerRadiusRatio in
                updatePresentationImageCornerRadius(
                    fileID: file.id,
                    groupID: selectedGroup.id,
                    overlayID: overlayID,
                    cornerRadiusRatio: cornerRadiusRatio
                )
            },
            onApplyImageStyleToAll: { overlayID in
                applyPresentationImageStyleToAll(
                    fileID: file.id,
                    sourceGroupID: selectedGroup.id,
                    sourceOverlayID: overlayID
                )
            },
            onUpdateTextOverlay: { overlayID, editingState in
                updatePresentationTextOverlay(
                    fileID: file.id,
                    groupID: selectedGroup.id,
                    overlayID: overlayID,
                    editingState: editingState
                )
            },
            onUpdateRoundedRectOverlay: { overlayID, editingState in
                updatePresentationRoundedRectOverlay(
                    fileID: file.id,
                    groupID: selectedGroup.id,
                    overlayID: overlayID,
                    editingState: editingState
                )
            },
            onUpdateIconOverlay: { overlayID, editingState in
                updatePresentationIconOverlay(
                    fileID: file.id,
                    groupID: selectedGroup.id,
                    overlayID: overlayID,
                    editingState: editingState
                )
            },
            onUpdateTextTheme: { textTheme in
                updatePresentationTextTheme(
                    fileID: file.id,
                    groupID: selectedGroup.id,
                    textTheme: textTheme
                )
            },
            onUpdateNativeTextOverride: { element, style in
                updatePresentationNativeTextOverride(
                    fileID: file.id,
                    groupID: selectedGroup.id,
                    element: element,
                    style: style
                )
            },
            onUpdateNativeContentOverride: { element, content in
                updatePresentationNativeContentOverride(
                    fileID: file.id,
                    groupID: selectedGroup.id,
                    element: element,
                    content: content
                )
            },
            onUpdateNativeLayoutOverride: { element, layout in
                updatePresentationNativeLayoutOverride(
                    fileID: file.id,
                    groupID: selectedGroup.id,
                    element: element,
                    layout: layout
                )
            },
            onClearNativeTextOverrides: {
                clearPresentationNativeTextOverrides(
                    fileID: file.id,
                    groupID: selectedGroup.id
                )
            },
            onApplyTemplate: { template in
                applyPresentationTemplate(
                    fileID: file.id,
                    groupID: selectedGroup.id,
                    template: template
                )
            },
            onUpdatePageStyle: { pageStyle in
                updatePresentationPageStyle(
                    fileID: file.id,
                    groupID: selectedGroup.id,
                    pageStyle: pageStyle
                )
            },
            onUpdateVectorization: { settings in
                updatePresentationVectorizationSettings(
                    fileID: file.id,
                    groupID: selectedGroup.id,
                    settings: settings
                )
            }
        )
        .transition(.opacity)
    }

    func presentationStylingState(fileID: UUID, groupID: UUID) -> PresentationSlideStylingState {
        var state = presentationStylingByFile[fileID]?[groupID] ?? .empty
        state.pageStyle = resolvedPresentationPageStyle(fileID: fileID)
        state.textTheme = resolvedPresentationTextTheme(fileID: fileID)
        return state
    }

    func resolvedPresentationPageStyle(fileID: UUID) -> PresentationPageStyle {
        presentationPageStyleByFile[fileID] ?? .default
    }

    func resolvedPresentationTextTheme(fileID: UUID) -> PresentationTextTheme {
        presentationTextThemeByFile[fileID] ?? .default
    }

    func mutatePresentationStylingState(
        fileID: UUID,
        groupID: UUID,
        markTouched: Bool = true,
        _ mutate: (inout PresentationSlideStylingState) -> Void
    ) {
        var byGroup = presentationStylingByFile[fileID] ?? [:]
        var state = byGroup[groupID] ?? .empty
        mutate(&state)

        if state.overlays.isEmpty &&
            state.undoStack.isEmpty &&
            state.redoStack.isEmpty &&
            state.selectedOverlayID == nil &&
            state.vectorization == .default &&
            state.nativeTextOverrides.isEmpty &&
            state.nativeContentOverrides.isEmpty &&
            state.nativeLayoutOverrides.isEmpty &&
            state.pageStyle == .default &&
            state.textTheme == .default {
            byGroup.removeValue(forKey: groupID)
        } else {
            byGroup[groupID] = state
        }

        if byGroup.isEmpty {
            presentationStylingByFile.removeValue(forKey: fileID)
        } else {
            presentationStylingByFile[fileID] = byGroup
        }
        if markTouched {
            presentationStylingTouchedFileIDs.insert(fileID)
        }
    }

    func pushPresentationStylingUndo(fileID: UUID, groupID: UUID) {
        let currentPageStyle = resolvedPresentationPageStyle(fileID: fileID)
        let currentTextTheme = resolvedPresentationTextTheme(fileID: fileID)
        mutatePresentationStylingState(fileID: fileID, groupID: groupID) { state in
            state.undoStack.append(
                PresentationStylingSnapshot(
                    overlays: state.overlays,
                    selectedOverlayID: state.selectedOverlayID,
                    vectorization: state.vectorization,
                    nativeTextOverrides: state.nativeTextOverrides,
                    nativeContentOverrides: state.nativeContentOverrides,
                    nativeLayoutOverrides: state.nativeLayoutOverrides,
                    pageStyle: currentPageStyle,
                    textTheme: currentTextTheme
                )
            )
            if state.undoStack.count > 40 {
                state.undoStack.removeFirst(state.undoStack.count - 40)
            }
            state.redoStack.removeAll()
        }
    }

    func resetPresentationStyling(fileID: UUID, groupID: UUID) {
        let state = presentationStylingState(fileID: fileID, groupID: groupID)
        guard !state.overlays.isEmpty ||
                state.vectorization != .default ||
                !state.nativeTextOverrides.isEmpty ||
                !state.nativeContentOverrides.isEmpty ||
                !state.nativeLayoutOverrides.isEmpty ||
                state.pageStyle != .default ||
                state.textTheme != .default else { return }
        pushPresentationStylingUndo(fileID: fileID, groupID: groupID)
        mutatePresentationStylingState(fileID: fileID, groupID: groupID) { editableState in
            editableState.overlays.removeAll()
            editableState.selectedOverlayID = nil
            editableState.vectorization = .default
            editableState.nativeTextOverrides.removeAll()
            editableState.nativeContentOverrides.removeAll()
            editableState.nativeLayoutOverrides.removeAll()
            editableState.pageStyle = .default
            editableState.textTheme = .default
        }
        presentationPageStyleByFile.removeValue(forKey: fileID)
        presentationTextThemeByFile.removeValue(forKey: fileID)
        persistPresentationState(fileID: fileID)
    }

    func undoPresentationStyling(fileID: UUID, groupID: UUID) {
        let currentPageStyle = resolvedPresentationPageStyle(fileID: fileID)
        let currentTextTheme = resolvedPresentationTextTheme(fileID: fileID)
        var restoredSnapshot: PresentationStylingSnapshot?
        mutatePresentationStylingState(fileID: fileID, groupID: groupID) { state in
            guard let previous = state.undoStack.popLast() else { return }
            state.redoStack.append(
                PresentationStylingSnapshot(
                    overlays: state.overlays,
                    selectedOverlayID: state.selectedOverlayID,
                    vectorization: state.vectorization,
                    nativeTextOverrides: state.nativeTextOverrides,
                    nativeContentOverrides: state.nativeContentOverrides,
                    nativeLayoutOverrides: state.nativeLayoutOverrides,
                    pageStyle: currentPageStyle,
                    textTheme: currentTextTheme
                )
            )
            if state.redoStack.count > 40 {
                state.redoStack.removeFirst(state.redoStack.count - 40)
            }
            state.overlays = previous.overlays
            state.selectedOverlayID = previous.selectedOverlayID
            state.vectorization = previous.vectorization
            state.nativeTextOverrides = previous.nativeTextOverrides
            state.nativeContentOverrides = previous.nativeContentOverrides
            state.nativeLayoutOverrides = previous.nativeLayoutOverrides
            if let selectedID = state.selectedOverlayID,
               !state.overlays.contains(where: { $0.id == selectedID }) {
                state.selectedOverlayID = state.overlays.last?.id
            }
            restoredSnapshot = previous
        }
        if let restoredSnapshot {
            presentationPageStyleByFile[fileID] = restoredSnapshot.pageStyle
            presentationTextThemeByFile[fileID] = restoredSnapshot.textTheme
        }
        persistPresentationState(fileID: fileID)
    }

    func redoPresentationStyling(fileID: UUID, groupID: UUID) {
        let currentPageStyle = resolvedPresentationPageStyle(fileID: fileID)
        let currentTextTheme = resolvedPresentationTextTheme(fileID: fileID)
        var restoredSnapshot: PresentationStylingSnapshot?
        mutatePresentationStylingState(fileID: fileID, groupID: groupID) { state in
            guard let next = state.redoStack.popLast() else { return }
            state.undoStack.append(
                PresentationStylingSnapshot(
                    overlays: state.overlays,
                    selectedOverlayID: state.selectedOverlayID,
                    vectorization: state.vectorization,
                    nativeTextOverrides: state.nativeTextOverrides,
                    nativeContentOverrides: state.nativeContentOverrides,
                    nativeLayoutOverrides: state.nativeLayoutOverrides,
                    pageStyle: currentPageStyle,
                    textTheme: currentTextTheme
                )
            )
            if state.undoStack.count > 40 {
                state.undoStack.removeFirst(state.undoStack.count - 40)
            }
            state.overlays = next.overlays
            state.selectedOverlayID = next.selectedOverlayID
            state.vectorization = next.vectorization
            state.nativeTextOverrides = next.nativeTextOverrides
            state.nativeContentOverrides = next.nativeContentOverrides
            state.nativeLayoutOverrides = next.nativeLayoutOverrides
            if let selectedID = state.selectedOverlayID,
               !state.overlays.contains(where: { $0.id == selectedID }) {
                state.selectedOverlayID = state.overlays.last?.id
            }
            restoredSnapshot = next
        }
        if let restoredSnapshot {
            presentationPageStyleByFile[fileID] = restoredSnapshot.pageStyle
            presentationTextThemeByFile[fileID] = restoredSnapshot.textTheme
        }
        persistPresentationState(fileID: fileID)
    }

    func insertPresentationOverlayImage(fileID: UUID, groupID: UUID, imageData: Data) {
        guard !imageData.isEmpty else { return }
        let storedImageData = normalizedPersistentImageData(imageData)
        pushPresentationStylingUndo(fileID: fileID, groupID: groupID)
        mutatePresentationStylingState(fileID: fileID, groupID: groupID) { state in
            let imageCount = state.overlays.filter(\.isImage).count
            let col = imageCount % 4
            let row = imageCount / 4
            let centerX = min(0.82, 0.46 + CGFloat(col) * 0.1)
            let centerY = min(0.8, 0.48 + CGFloat(row % 3) * 0.1)
            let aspect = presentationOverlayAspectRatio(from: storedImageData)
            let slideAspect = max(0.75, resolvedPresentationPageStyle(fileID: fileID).aspectPreset.ratio)
            let targetHeight: CGFloat = 0.24
            let width = max(0.1, min(0.44, targetHeight * aspect / slideAspect))
            let overlay = PresentationSlideOverlay(
                imageData: storedImageData,
                selectedFilter: .original,
                center: CGPoint(x: centerX, y: centerY),
                normalizedWidth: width,
                normalizedHeight: presentationImageNormalizedHeight(
                    fileID: fileID,
                    normalizedWidth: width,
                    aspectRatio: aspect
                ),
                aspectRatio: aspect
            )
            state.overlays.append(overlay)
            state.selectedOverlayID = overlay.id
        }
        persistPresentationState(fileID: fileID)
    }

    func insertPresentationTextOverlay(fileID: UUID, groupID: UUID) {
        pushPresentationStylingUndo(fileID: fileID, groupID: groupID)
        let h2Style = resolvedPresentationTextTheme(fileID: fileID).style(for: .h2)
        let h2FontSize = max(14, min(96, h2Style.sizeCqw * 13.66))
        mutatePresentationStylingState(fileID: fileID, groupID: groupID) { state in
            var overlay = PresentationSlideOverlay.makeText(
                center: CGPoint(x: 0.5, y: 0.6)
            )
            overlay.textStylePreset = .h2
            overlay.textColorHex = h2Style.colorHex
            overlay.textWeightValue = h2Style.weightValue
            overlay.textFontSize = h2FontSize
            state.overlays.append(overlay)
            state.selectedOverlayID = overlay.id
        }
        persistPresentationState(fileID: fileID)
    }

    func insertPresentationRoundedRectOverlay(fileID: UUID, groupID: UUID) {
        pushPresentationStylingUndo(fileID: fileID, groupID: groupID)
        mutatePresentationStylingState(fileID: fileID, groupID: groupID) { state in
            let overlay = PresentationSlideOverlay.makeRoundedRect(
                center: CGPoint(x: 0.5, y: 0.6)
            )
            state.overlays.append(overlay)
            state.selectedOverlayID = overlay.id
        }
        persistPresentationState(fileID: fileID)
    }

    func insertPresentationIconOverlay(fileID: UUID, groupID: UUID) {
        pushPresentationStylingUndo(fileID: fileID, groupID: groupID)
        mutatePresentationStylingState(fileID: fileID, groupID: groupID) { state in
            let overlay = PresentationSlideOverlay.makeIcon(
                center: CGPoint(x: 0.5, y: 0.6)
            )
            state.overlays.append(overlay)
            state.selectedOverlayID = overlay.id
        }
        persistPresentationState(fileID: fileID)
    }

    func selectPresentationOverlay(fileID: UUID, groupID: UUID, overlayID: UUID) {
        mutatePresentationStylingState(fileID: fileID, groupID: groupID, markTouched: false) { state in
            guard state.overlays.contains(where: { $0.id == overlayID }) else { return }
            state.selectedOverlayID = overlayID
        }
        persistPresentationState(fileID: fileID)
    }

    func clearPresentationOverlaySelection(fileID: UUID, groupID: UUID) {
        mutatePresentationStylingState(fileID: fileID, groupID: groupID, markTouched: false) { state in
            state.selectedOverlayID = nil
        }
        persistPresentationState(fileID: fileID)
    }

    func applyPresentationOverlayFilter(
        fileID: UUID,
        groupID: UUID,
        overlayID: UUID,
        style: SVGFilterStyle
    ) {
        let state = presentationStylingState(fileID: fileID, groupID: groupID)
        guard let overlay = state.overlays.first(where: { $0.id == overlayID }),
              overlay.isImage,
              overlay.vectorDocument != nil,
              overlay.selectedFilter != style else {
            return
        }
        pushPresentationStylingUndo(fileID: fileID, groupID: groupID)
        updatePresentationOverlay(fileID: fileID, groupID: groupID, overlayID: overlayID) { editable in
            editable.selectedFilter = style
        }
        persistPresentationState(fileID: fileID)
    }

    func movePresentationOverlay(
        fileID: UUID,
        groupID: UUID,
        overlayID: UUID,
        center: CGPoint
    ) {
        pushPresentationStylingUndo(fileID: fileID, groupID: groupID)
        updatePresentationOverlay(fileID: fileID, groupID: groupID, overlayID: overlayID) { editable in
            editable.center = center
        }
        persistPresentationState(fileID: fileID)
    }

    func rotatePresentationOverlay(
        fileID: UUID,
        groupID: UUID,
        overlayID: UUID,
        deltaDegrees: Double
    ) {
        guard deltaDegrees.isFinite, abs(deltaDegrees) > 0.05 else { return }
        let state = presentationStylingState(fileID: fileID, groupID: groupID)
        guard let overlay = state.overlays.first(where: { $0.id == overlayID }),
              overlay.isImage else {
            return
        }
        pushPresentationStylingUndo(fileID: fileID, groupID: groupID)
        updatePresentationOverlay(fileID: fileID, groupID: groupID, overlayID: overlayID) { editable in
            editable.rotationDegrees = normalizedRotationDegrees(editable.rotationDegrees + deltaDegrees)
        }
        persistPresentationState(fileID: fileID)
    }

    func scalePresentationOverlay(
        fileID: UUID,
        groupID: UUID,
        overlayID: UUID,
        scale: CGFloat
    ) {
        guard scale.isFinite else { return }
        let clampedScale = max(0.5, min(2.4, scale))
        guard abs(clampedScale - 1) > 0.01 else { return }

        let state = presentationStylingState(fileID: fileID, groupID: groupID)
        guard state.overlays.contains(where: { $0.id == overlayID }) else { return }

        pushPresentationStylingUndo(fileID: fileID, groupID: groupID)
        updatePresentationOverlay(fileID: fileID, groupID: groupID, overlayID: overlayID) { editable in
            let scaledWidth = editable.normalizedWidth * clampedScale
            editable.normalizedWidth = max(0.08, min(0.9, scaledWidth))
            if editable.isIcon {
                editable.normalizedHeight = editable.normalizedWidth
                editable.aspectRatio = 1
            } else if editable.isImage {
                editable.normalizedHeight = presentationImageNormalizedHeight(
                    fileID: fileID,
                    normalizedWidth: editable.normalizedWidth,
                    aspectRatio: editable.aspectRatio
                )
            } else if editable.isText || editable.isRoundedRect {
                let scaledHeight = editable.normalizedHeight * clampedScale
                editable.normalizedHeight = max(0.08, min(0.72, scaledHeight))
                editable.aspectRatio = max(0.15, editable.normalizedWidth / max(editable.normalizedHeight, 0.01))
            }
        }
        persistPresentationState(fileID: fileID)
    }

    func cropPresentationOverlay(
        fileID: UUID,
        groupID: UUID,
        overlayID: UUID,
        normalizedRect: CGRect,
        handleType: String? = nil
    ) {
        let state = presentationStylingState(fileID: fileID, groupID: groupID)
        guard let overlay = state.overlays.first(where: { $0.id == overlayID }),
              overlay.isImage else {
            return
        }

        let relativeRect = normalizedRect
        let currentCropRect = normalizedUnitCropRect(overlay.cumulativeCropRect)
        let nextCropRect = composedCropRect(current: currentCropRect, relative: relativeRect)
        guard nextCropRect.width > 0.02, nextCropRect.height > 0.02 else { return }

        let cropSourceData = overlay.cropSourceImageData ?? overlay.displayImageData
        guard let croppedData = cropImageData(cropSourceData, normalizedRect: nextCropRect) else { return }
        let persistedCroppedData = normalizedPersistentImageData(croppedData)
        let persistedCropSourceData = normalizedPersistentImageData(cropSourceData)
        let wasVectorized = overlay.vectorDocument != nil
        let preservedFilter = overlay.selectedFilter
        let vectorizationOptions = state.vectorization.svgOptions
        let currentWidth = max(0.08, min(0.92, overlay.normalizedWidth))
        let currentHeight = max(0.08, min(0.92, overlay.normalizedHeight))
        let slideAspect = max(0.75, resolvedPresentationPageStyle(fileID: fileID).aspectPreset.ratio)
        let oldLeft = overlay.center.x - currentWidth * 0.5
        let oldRight = overlay.center.x + currentWidth * 0.5
        let oldTop = overlay.center.y - currentHeight * 0.5
        let oldBottom = overlay.center.y + currentHeight * 0.5

        let nextAspect = presentationOverlayAspectRatio(from: persistedCroppedData)
        var nextWidth = currentWidth
        var nextHeight = currentHeight
        var anchoredCenter = overlay.center
        let normalizedHandle = handleType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let analysisRect = normalizedCropRect(relativeRect)
        let epsilon = 0.0001
        let nearFullWidth = analysisRect.origin.x <= epsilon && abs(analysisRect.width - 1) <= 0.002
        let nearFullHeight = analysisRect.origin.y <= epsilon && abs(analysisRect.height - 1) <= 0.002
        let resolvedHandle: String = {
            guard !normalizedHandle.isEmpty else {
                // Backward compatibility with legacy crop payloads that do not include handle info.
                if analysisRect.origin.x > epsilon && nearFullHeight {
                    return "crop-left"
                }
                if analysisRect.width < 0.999 && analysisRect.origin.x <= epsilon && nearFullHeight {
                    return "crop-right"
                }
                if analysisRect.origin.y > epsilon && nearFullWidth {
                    return "crop-top"
                }
                if analysisRect.height < 0.999 && analysisRect.origin.y <= epsilon && nearFullWidth {
                    return "crop-bottom"
                }
                return ""
            }
            return normalizedHandle
        }()

        if resolvedHandle == "crop-left" || resolvedHandle == "crop-right" {
            let estimatedWidth = currentHeight * nextAspect / max(0.75, slideAspect)
            nextWidth = max(0.08, min(0.92, estimatedWidth))
            nextHeight = currentHeight

            if resolvedHandle == "crop-left" {
                anchoredCenter.x = oldRight - nextWidth * 0.5
            } else {
                anchoredCenter.x = oldLeft + nextWidth * 0.5
            }
        } else if resolvedHandle == "crop-top" || resolvedHandle == "crop-bottom" {
            nextWidth = currentWidth
            nextHeight = presentationImageNormalizedHeight(
                fileID: fileID,
                normalizedWidth: nextWidth,
                aspectRatio: nextAspect
            )

            if resolvedHandle == "crop-bottom" {
                anchoredCenter.y = oldTop + nextHeight * 0.5
            } else {
                anchoredCenter.y = oldBottom - nextHeight * 0.5
            }
        } else {
            // Generic crop (e.g. panel input) keeps width stable and recomputes height.
            nextWidth = currentWidth
            nextHeight = presentationImageNormalizedHeight(
                fileID: fileID,
                normalizedWidth: nextWidth,
                aspectRatio: nextAspect
            )
        }

        let minCenterX = max(0.04, nextWidth * 0.5)
        let maxCenterX = min(0.96, 1.0 - nextWidth * 0.5)
        if minCenterX <= maxCenterX {
            anchoredCenter.x = max(minCenterX, min(maxCenterX, anchoredCenter.x))
        } else {
            anchoredCenter.x = max(0.04, min(0.96, anchoredCenter.x))
        }
        let minCenterY = max(0.08, nextHeight * 0.5)
        let maxCenterY = min(0.92, 1.0 - nextHeight * 0.5)
        if minCenterY <= maxCenterY {
            anchoredCenter.y = max(minCenterY, min(maxCenterY, anchoredCenter.y))
        } else {
            anchoredCenter.y = max(0.08, min(0.92, anchoredCenter.y))
        }

        pushPresentationStylingUndo(fileID: fileID, groupID: groupID)
        updatePresentationOverlay(fileID: fileID, groupID: groupID, overlayID: overlayID) { editable in
            if editable.extractedImageData != nil {
                editable.extractedImageData = persistedCroppedData
            } else {
                editable.imageData = persistedCroppedData
            }
            editable.cropSourceImageData = persistedCropSourceData
            editable.cumulativeCropRect = nextCropRect
            editable.center = anchoredCenter
            editable.normalizedWidth = nextWidth
            editable.aspectRatio = nextAspect
            editable.normalizedHeight = nextHeight
            if wasVectorized {
                editable.selectedFilter = preservedFilter
            } else {
                editable.vectorDocument = nil
                editable.selectedFilter = .original
            }
        }
        persistPresentationState(fileID: fileID)

        if wasVectorized {
            rebuildPresentationOverlaySVG(
                fileID: fileID,
                groupID: groupID,
                overlayID: overlayID,
                sourceData: persistedCroppedData,
                options: vectorizationOptions,
                resetFilterToOriginal: false
            )
        }
    }

    func updatePresentationImageOverlayFrame(
        fileID: UUID,
        groupID: UUID,
        overlayID: UUID,
        center: CGPoint,
        normalizedWidth: CGFloat,
        normalizedHeight: CGFloat
    ) {
        let state = presentationStylingState(fileID: fileID, groupID: groupID)
        guard let overlay = state.overlays.first(where: { $0.id == overlayID }),
              overlay.isImage else {
            return
        }
        pushPresentationStylingUndo(fileID: fileID, groupID: groupID)
        updatePresentationOverlay(fileID: fileID, groupID: groupID, overlayID: overlayID) { editable in
            editable.center = CGPoint(
                x: max(0.04, min(0.96, center.x)),
                y: max(0.08, min(0.92, center.y))
            )
            let width = max(0.08, min(0.92, normalizedWidth))
            let height = max(0.08, min(0.92, normalizedHeight))
            editable.normalizedWidth = width
            editable.normalizedHeight = height

            let slideAspect = max(0.75, resolvedPresentationPageStyle(fileID: fileID).aspectPreset.ratio)
            let derivedAspect = width * slideAspect / max(0.08, height)
            if derivedAspect.isFinite {
                editable.aspectRatio = max(0.15, min(12, derivedAspect))
            } else {
                editable.aspectRatio = max(0.15, editable.aspectRatio)
            }
        }
        persistPresentationState(fileID: fileID)
    }

    func deletePresentationOverlay(
        fileID: UUID,
        groupID: UUID,
        overlayID: UUID
    ) {
        let state = presentationStylingState(fileID: fileID, groupID: groupID)
        guard state.overlays.contains(where: { $0.id == overlayID }) else { return }
        pushPresentationStylingUndo(fileID: fileID, groupID: groupID)
        mutatePresentationStylingState(fileID: fileID, groupID: groupID) { editableState in
            editableState.overlays.removeAll { $0.id == overlayID }
            if editableState.selectedOverlayID == overlayID {
                editableState.selectedOverlayID = editableState.overlays.last?.id
            }
        }
        persistPresentationState(fileID: fileID)
    }

    func updatePresentationOverlayStylization(
        fileID: UUID,
        groupID: UUID,
        overlayID: UUID,
        stylization: SVGStylizationParameters
    ) {
        updatePresentationOverlay(fileID: fileID, groupID: groupID, overlayID: overlayID) { editable in
            guard editable.isImage else { return }
            editable.stylization = stylization
        }
        persistPresentationState(fileID: fileID)
    }

    func updatePresentationImageVectorStyle(
        fileID: UUID,
        groupID: UUID,
        overlayID: UUID,
        strokeHex: String,
        backgroundHex: String,
        backgroundVisible: Bool
    ) {
        updatePresentationOverlay(fileID: fileID, groupID: groupID, overlayID: overlayID) { editable in
            guard editable.isImage else { return }
            editable.vectorStrokeColorHex = strokeHex
            editable.vectorBackgroundColorHex = backgroundHex
            editable.vectorBackgroundVisible = backgroundVisible
        }
        persistPresentationState(fileID: fileID)
    }

    func updatePresentationImageCornerRadius(
        fileID: UUID,
        groupID: UUID,
        overlayID: UUID,
        cornerRadiusRatio: Double
    ) {
        let clamped = max(0, min(0.5, cornerRadiusRatio))
        let state = presentationStylingState(fileID: fileID, groupID: groupID)
        guard let overlay = state.overlays.first(where: { $0.id == overlayID }),
              overlay.isImage else {
            return
        }
        guard abs(overlay.imageCornerRadiusRatio - clamped) > 0.0005 else { return }
        pushPresentationStylingUndo(fileID: fileID, groupID: groupID)
        updatePresentationOverlay(fileID: fileID, groupID: groupID, overlayID: overlayID) { editable in
            guard editable.isImage else { return }
            editable.imageCornerRadiusRatio = clamped
        }
        persistPresentationState(fileID: fileID)
    }

    func applyPresentationImageStyleToAll(
        fileID: UUID,
        sourceGroupID: UUID,
        sourceOverlayID: UUID
    ) {
        guard var byGroup = presentationStylingByFile[fileID],
              let sourceState = byGroup[sourceGroupID],
              let sourceOverlay = sourceState.overlays.first(where: { $0.id == sourceOverlayID && $0.isImage }),
              sourceOverlay.vectorDocument != nil else {
            return
        }

        let sourceFilter = sourceOverlay.selectedFilter
        let sourceStylization = sourceOverlay.stylization
        let sourceStroke = sourceOverlay.vectorStrokeColorHex
        let sourceBackground = sourceOverlay.vectorBackgroundColorHex
        let sourceBackgroundVisible = sourceOverlay.vectorBackgroundVisible
        let sourceCornerRadius = sourceOverlay.imageCornerRadiusRatio
        let sourceVectorization = sourceState.vectorization

        var pendingRevectorization: [(groupID: UUID, overlayID: UUID, sourceData: Data)] = []

        for (groupID, var state) in byGroup {
            state.vectorization = sourceVectorization
            for index in state.overlays.indices {
                guard state.overlays[index].isImage else { continue }
                if groupID == sourceGroupID && state.overlays[index].id == sourceOverlayID {
                    continue
                }

                state.overlays[index].selectedFilter = sourceFilter
                state.overlays[index].stylization = sourceStylization
                state.overlays[index].vectorStrokeColorHex = sourceStroke
                state.overlays[index].vectorBackgroundColorHex = sourceBackground
                state.overlays[index].vectorBackgroundVisible = sourceBackgroundVisible
                state.overlays[index].imageCornerRadiusRatio = sourceCornerRadius

                if state.overlays[index].vectorDocument == nil {
                    pendingRevectorization.append((
                        groupID: groupID,
                        overlayID: state.overlays[index].id,
                        sourceData: state.overlays[index].displayImageData
                    ))
                }
            }
            byGroup[groupID] = state
        }

        presentationStylingByFile[fileID] = byGroup
        persistPresentationState(fileID: fileID)

        for pending in pendingRevectorization {
            rebuildPresentationOverlaySVG(
                fileID: fileID,
                groupID: pending.groupID,
                overlayID: pending.overlayID,
                sourceData: pending.sourceData,
                options: sourceVectorization.svgOptions,
                resetFilterToOriginal: false
            )
        }
    }

    func updatePresentationTextOverlay(
        fileID: UUID,
        groupID: UUID,
        overlayID: UUID,
        editingState: PresentationTextEditingState
    ) {
        updatePresentationOverlay(fileID: fileID, groupID: groupID, overlayID: overlayID) { editable in
            guard editable.isText else { return }
            editable.textEditingState = editingState
            editable.aspectRatio = max(0.15, editable.normalizedWidth / max(editable.normalizedHeight, 0.01))
        }
        persistPresentationState(fileID: fileID)
    }

    func updatePresentationRoundedRectOverlay(
        fileID: UUID,
        groupID: UUID,
        overlayID: UUID,
        editingState: PresentationRoundedRectEditingState
    ) {
        updatePresentationOverlay(fileID: fileID, groupID: groupID, overlayID: overlayID) { editable in
            guard editable.isRoundedRect else { return }
            editable.roundedRectEditingState = editingState
        }
        persistPresentationState(fileID: fileID)
    }

    func updatePresentationIconOverlay(
        fileID: UUID,
        groupID: UUID,
        overlayID: UUID,
        editingState: PresentationIconEditingState
    ) {
        updatePresentationOverlay(fileID: fileID, groupID: groupID, overlayID: overlayID) { editable in
            guard editable.isIcon else { return }
            editable.iconEditingState = editingState
        }
        persistPresentationState(fileID: fileID)
    }

    func updatePresentationPageStyle(
        fileID: UUID,
        groupID: UUID,
        pageStyle: PresentationPageStyle
    ) {
        let current = resolvedPresentationPageStyle(fileID: fileID)
        guard current != pageStyle else { return }
        pushPresentationStylingUndo(fileID: fileID, groupID: groupID)
        presentationPageStyleByFile[fileID] = pageStyle
        presentationStylingTouchedFileIDs.insert(fileID)
        persistPresentationState(fileID: fileID)
    }

    func updatePresentationTextTheme(
        fileID: UUID,
        groupID: UUID,
        textTheme: PresentationTextTheme
    ) {
        let current = resolvedPresentationTextTheme(fileID: fileID)
        guard current != textTheme else { return }
        pushPresentationStylingUndo(fileID: fileID, groupID: groupID)
        presentationTextThemeByFile[fileID] = textTheme
        presentationStylingTouchedFileIDs.insert(fileID)
        persistPresentationState(fileID: fileID)
    }

    func updatePresentationNativeTextOverride(
        fileID: UUID,
        groupID: UUID,
        element: PresentationNativeElement,
        style: PresentationTextStyleConfig?
    ) {
        let currentState = presentationStylingState(fileID: fileID, groupID: groupID)
        let currentValue = currentState.nativeTextOverrides[element]
        if currentValue == style { return }
        pushPresentationStylingUndo(fileID: fileID, groupID: groupID)
        mutatePresentationStylingState(fileID: fileID, groupID: groupID) { state in
            if let style {
                state.nativeTextOverrides[element] = style
            } else {
                state.nativeTextOverrides.removeValue(forKey: element)
            }
        }
        persistPresentationState(fileID: fileID)
    }

    func updatePresentationNativeContentOverride(
        fileID: UUID,
        groupID: UUID,
        element: PresentationNativeElement,
        content: String?
    ) {
        let normalized: String? = content?.replacingOccurrences(of: "\r\n", with: "\n")
        let currentState = presentationStylingState(fileID: fileID, groupID: groupID)
        let currentValue = currentState.nativeContentOverrides[element]
        if currentValue == normalized { return }
        pushPresentationStylingUndo(fileID: fileID, groupID: groupID)
        mutatePresentationStylingState(fileID: fileID, groupID: groupID) { state in
            if let normalized {
                state.nativeContentOverrides[element] = normalized
            } else {
                state.nativeContentOverrides.removeValue(forKey: element)
            }
        }
        persistPresentationState(fileID: fileID)
    }

    func updatePresentationNativeLayoutOverride(
        fileID: UUID,
        groupID: UUID,
        element: PresentationNativeElement,
        layout: PresentationNativeLayoutOverride?
    ) {
        let clampedLayout = layout?.clamped()
        let nextValue: PresentationNativeLayoutOverride? = {
            if let clampedLayout, !clampedLayout.isZero {
                return clampedLayout
            }
            return nil
        }()
        let currentState = presentationStylingState(fileID: fileID, groupID: groupID)
        let currentValue = currentState.nativeLayoutOverrides[element]
        if currentValue == nextValue { return }
        pushPresentationStylingUndo(fileID: fileID, groupID: groupID)
        mutatePresentationStylingState(fileID: fileID, groupID: groupID) { state in
            if let nextValue {
                state.nativeLayoutOverrides[element] = nextValue
            } else {
                state.nativeLayoutOverrides.removeValue(forKey: element)
            }
        }
        persistPresentationState(fileID: fileID)
    }

    func clearPresentationNativeTextOverrides(
        fileID: UUID,
        groupID: UUID
    ) {
        let currentState = presentationStylingState(fileID: fileID, groupID: groupID)
        guard !currentState.nativeTextOverrides.isEmpty else { return }
        pushPresentationStylingUndo(fileID: fileID, groupID: groupID)
        mutatePresentationStylingState(fileID: fileID, groupID: groupID) { state in
            state.nativeTextOverrides.removeAll()
        }
        persistPresentationState(fileID: fileID)
    }

    func applyPresentationTemplate(
        fileID: UUID,
        groupID: UUID,
        template: PresentationThemeTemplate
    ) {
        let aspect = resolvedPresentationPageStyle(fileID: fileID).aspectPreset
        var nextStyle = template.pageStyle
        nextStyle.aspectPreset = aspect
        let nextTextTheme = template.textTheme
        let currentStyle = resolvedPresentationPageStyle(fileID: fileID)
        let currentTextTheme = resolvedPresentationTextTheme(fileID: fileID)
        guard currentStyle != nextStyle || currentTextTheme != nextTextTheme else { return }
        pushPresentationStylingUndo(fileID: fileID, groupID: groupID)
        presentationPageStyleByFile[fileID] = nextStyle
        presentationTextThemeByFile[fileID] = nextTextTheme
        presentationStylingTouchedFileIDs.insert(fileID)
        persistPresentationState(fileID: fileID)
    }

    func updatePresentationOverlay(
        fileID: UUID,
        groupID: UUID,
        overlayID: UUID,
        _ mutate: (inout PresentationSlideOverlay) -> Void
    ) {
        mutatePresentationStylingState(fileID: fileID, groupID: groupID) { state in
            guard let index = state.overlays.firstIndex(where: { $0.id == overlayID }) else { return }
            mutate(&state.overlays[index])
        }
    }

    func updatePresentationVectorizationSettings(
        fileID: UUID,
        groupID: UUID,
        settings: PresentationVectorizationSettings
    ) {
        let previousState = presentationStylingState(fileID: fileID, groupID: groupID)
        mutatePresentationStylingState(fileID: fileID, groupID: groupID) { state in
            state.vectorization = settings
        }
        if let selectedID = previousState.selectedOverlayID,
           let overlay = previousState.overlays.first(where: { $0.id == selectedID }),
           overlay.isImage,
           overlay.vectorDocument != nil {
            rebuildPresentationOverlaySVG(
                fileID: fileID,
                groupID: groupID,
                overlayID: selectedID,
                sourceData: overlay.displayImageData,
                options: settings.svgOptions,
                resetFilterToOriginal: false
            )
        }
        persistPresentationState(fileID: fileID)
    }

    func extractPresentationOverlaySubject(fileID: UUID, groupID: UUID, overlayID: UUID) {
        let state = presentationStylingState(fileID: fileID, groupID: groupID)
        guard let overlay = state.overlays.first(where: { $0.id == overlayID }),
              overlay.isImage,
              !overlay.isExtracting else {
            return
        }

        updatePresentationOverlay(fileID: fileID, groupID: groupID, overlayID: overlayID) { editable in
            editable.isExtracting = true
            editable.activeVectorizationRequestID = nil
        }
        persistPresentationState(fileID: fileID)

        Task {
            let extractedImageData = await presentationOverlayExtractedSubject(imageData: overlay.imageData)
            await MainActor.run {
                updatePresentationOverlay(fileID: fileID, groupID: groupID, overlayID: overlayID) { editable in
                    editable.isExtracting = false
                    editable.activeVectorizationRequestID = nil
                    if let extractedImageData {
                        let persistedExtractedData = normalizedPersistentImageData(extractedImageData)
                        editable.extractedImageData = persistedExtractedData
                        editable.cropSourceImageData = nil
                        editable.cumulativeCropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
                        editable.aspectRatio = presentationOverlayAspectRatio(from: persistedExtractedData)
                        editable.normalizedHeight = presentationImageNormalizedHeight(
                            fileID: fileID,
                            normalizedWidth: editable.normalizedWidth,
                            aspectRatio: editable.aspectRatio
                        )
                        // Subject extraction should stay in bitmap mode until user taps Convert to SVG.
                        editable.vectorDocument = nil
                        editable.selectedFilter = .original
                    }
                }
                persistPresentationState(fileID: fileID)
            }
        }
    }

    func presentationOverlayExtractedSubject(imageData: Data) async -> Data? {
        #if canImport(UIKit) && canImport(CoreImage)
        if let sourceImage = UIImage(data: imageData),
           let extractedImage = await PresentationSubjectExtractor.extractSubject(from: sourceImage),
           let extractedPNG = extractedImage.pngData() {
            return extractedPNG
        }
        #endif
        return nil
    }

    func convertPresentationOverlayToSVG(fileID: UUID, groupID: UUID, overlayID: UUID) {
        let state = presentationStylingState(fileID: fileID, groupID: groupID)
        guard let overlay = state.overlays.first(where: { $0.id == overlayID }),
              overlay.isImage else {
            return
        }

        rebuildPresentationOverlaySVG(
            fileID: fileID,
            groupID: groupID,
            overlayID: overlayID,
            sourceData: overlay.displayImageData,
            options: state.vectorization.svgOptions,
            resetFilterToOriginal: true
        )
    }

    func rebuildPresentationOverlaySVG(
        fileID: UUID,
        groupID: UUID,
        overlayID: UUID,
        sourceData: Data,
        options: SVGVectorizationOptions,
        resetFilterToOriginal: Bool
    ) {
        let requestID = UUID()
        updatePresentationOverlay(fileID: fileID, groupID: groupID, overlayID: overlayID) { editable in
            editable.isExtracting = true
            editable.activeVectorizationRequestID = requestID
        }
        persistPresentationState(fileID: fileID)

        Task {
            let document = try? SVGBitmapConverter.vectorize(imageData: sourceData, options: options)

            await MainActor.run {
                updatePresentationOverlay(fileID: fileID, groupID: groupID, overlayID: overlayID) { editable in
                    guard editable.activeVectorizationRequestID == requestID else { return }
                    editable.isExtracting = false
                    editable.activeVectorizationRequestID = nil
                    guard let document else { return }
                    editable.vectorDocument = document
                    if resetFilterToOriginal {
                        editable.selectedFilter = .original
                    }
                }
                persistPresentationState(fileID: fileID)
            }
        }
    }

    func presentationOverlayAspectRatio(from imageData: Data) -> CGFloat {
        if let preciseAspect = presentationDisplayAspectRatio(from: imageData) {
            return preciseAspect
        }
        #if canImport(UIKit)
        if let image = UIImage(data: imageData),
           image.size.height > 0 {
            return max(0.15, image.size.width / image.size.height)
        }
        #endif
        return 1
    }

    func presentationDisplayAspectRatio(from imageData: Data) -> CGFloat? {
        #if canImport(ImageIO)
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }
        let rawWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue
            ?? (properties[kCGImagePropertyPixelWidth] as? Double)
        let rawHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue
            ?? (properties[kCGImagePropertyPixelHeight] as? Double)
        guard let rawWidth, let rawHeight, rawWidth > 0, rawHeight > 0 else {
            return nil
        }

        var width = CGFloat(rawWidth)
        var height = CGFloat(rawHeight)
        let orientationValue = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue
            ?? (properties[kCGImagePropertyOrientation] as? Int)
            ?? 1
        if orientationValue == 5 || orientationValue == 6 || orientationValue == 7 || orientationValue == 8 {
            swap(&width, &height)
        }
        guard height > 0 else { return nil }
        return max(0.15, width / height)
        #else
        _ = imageData
        return nil
        #endif
    }

    func presentationImageNormalizedHeight(
        fileID: UUID,
        normalizedWidth: CGFloat,
        aspectRatio: CGFloat
    ) -> CGFloat {
        let slideAspect = max(0.75, resolvedPresentationPageStyle(fileID: fileID).aspectPreset.ratio)
        let normalized = normalizedWidth * slideAspect / max(0.15, aspectRatio)
        return max(0.08, min(0.92, normalized))
    }

    func normalizedRotationDegrees(_ value: Double) -> Double {
        var next = value.truncatingRemainder(dividingBy: 360)
        if next <= -180 { next += 360 }
        if next > 180 { next -= 360 }
        return next
    }

    func normalizedCropRect(_ rect: CGRect) -> CGRect {
        normalizedUnitCropRect(rect)
    }

    func normalizedUnitCropRect(_ rect: CGRect) -> CGRect {
        let minSize: CGFloat = 0.02
        var x = rect.origin.x
        var y = rect.origin.y
        var width = rect.size.width
        var height = rect.size.height

        if x < 0 {
            width += x
            x = 0
        }
        if y < 0 {
            height += y
            y = 0
        }
        if x + width > 1 {
            width = 1 - x
        }
        if y + height > 1 {
            height = 1 - y
        }

        width = max(minSize, min(1, width))
        height = max(minSize, min(1, height))
        x = min(max(0, x), 1 - width)
        y = min(max(0, y), 1 - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    func composedCropRect(current: CGRect, relative: CGRect) -> CGRect {
        let currentRect = normalizedUnitCropRect(current)
        let composed = CGRect(
            x: currentRect.origin.x + relative.origin.x * currentRect.width,
            y: currentRect.origin.y + relative.origin.y * currentRect.height,
            width: currentRect.width * relative.width,
            height: currentRect.height * relative.height
        )
        return normalizedUnitCropRect(composed)
    }

    func cropImageData(_ imageData: Data, normalizedRect: CGRect) -> Data? {
        #if canImport(UIKit)
        guard let image = UIImage(data: imageData),
              let cgImage = image.cgImage else {
            return nil
        }

        let clamped = normalizedCropRect(normalizedRect)
        let pixelRect = CGRect(
            x: CGFloat(cgImage.width) * clamped.origin.x,
            y: CGFloat(cgImage.height) * clamped.origin.y,
            width: CGFloat(cgImage.width) * clamped.width,
            height: CGFloat(cgImage.height) * clamped.height
        ).integral

        guard pixelRect.width > 1, pixelRect.height > 1,
              let cropped = cgImage.cropping(to: pixelRect) else {
            return nil
        }

        let output = UIImage(cgImage: cropped, scale: image.scale, orientation: .up)
        return output.pngData()
        #else
        _ = imageData
        _ = normalizedRect
        return nil
        #endif
    }

    func togglePresentationStylingMode(
        fileID: UUID,
        groups: [EduPresentationSlideGroup],
        selectedGroupID: UUID?
    ) {
        if let file = workspaceFiles.first(where: { $0.id == fileID }) {
            hydratePresentationState(for: file, force: true)
        }
        if activePresentationStylingFileID == fileID {
            activePresentationStylingFileID = nil
            return
        }

        activePresentationStylingFileID = fileID
        if let target = groups.first(where: { $0.id == selectedGroupID }) ?? groups.first {
            selectPresentationGroup(fileID: fileID, group: target)
        }
    }

    @ViewBuilder
    func presentationStylingEntryButton(
        isActive: Bool,
        isPulsing: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Image(systemName: "paintpalette")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.96))
            }
            .frame(width: 58, height: 58)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(
                Circle()
                    .fill(Color.black.opacity(isActive ? 0.36 : 0.28))
            )
            .overlay(
                ZStack {
                    AnimatedGradientRing(lineWidth: isActive ? 3.6 : 3.0)
                        .blur(radius: isActive ? 4.6 : 3.6)
                        .opacity(isActive ? 0.95 : 0.78)
                    AnimatedGradientRing(lineWidth: isActive ? 2.2 : 1.8)
                        .opacity(0.82)
                }
            )
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(isActive ? 0.22 : 0.14), lineWidth: 0.9)
                    .blur(radius: 0.6)
            )
            .overlay(
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(isActive ? 0.24 : 0.16),
                                Color.white.opacity(0)
                            ],
                            center: .center,
                            startRadius: 6,
                            endRadius: 33
                        )
                    )
            )
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.26), radius: 9, y: 4)
        }
        .scaleEffect(isPulsing ? (tutorialHintPulsePhase ? 1.12 : 0.94) : 1)
        .opacity(isPulsing ? (tutorialHintPulsePhase ? 1 : 0.74) : 1)
        .buttonStyle(.plain)
    }

}
