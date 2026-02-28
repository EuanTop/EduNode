import SwiftUI
import GNodeKit
import UniformTypeIdentifiers

extension ContentView {
    func presentationFilmstrip(
        fileID: UUID,
        courseName: String,
        deck: EduPresentationDeck,
        groups: [EduPresentationSlideGroup],
        slides: [EduPresentationComposedSlide]
    ) -> some View {
        let storedSelectedID = selectedPresentationGroupIDByFile[fileID]
        let selectedGroupID: UUID? = {
            if groups.contains(where: { $0.id == storedSelectedID }) {
                return storedSelectedID
            }
            return groups.first?.id
        }()
        let stripHeight: CGFloat = presentationFilmstripHeight
        let stripVerticalPadding: CGFloat = 8

        return VStack(spacing: 0) {
            Spacer(minLength: 0)

            ScrollViewReader { scrollProxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                        let isSelected = group.id == selectedGroupID
                        let styleState = presentationStylingState(fileID: fileID, groupID: group.id)
                        let overlays = styleState.overlays
                        let pageStyle = styleState.pageStyle
                        let textTheme = styleState.textTheme
                        ZStack(alignment: .topTrailing) {
                            Button {
                                selectPresentationGroup(fileID: fileID, group: group)
                            } label: {
                                presentationSlideThumbnail(
                                    courseName: courseName,
                                    slide: slides.indices.contains(index) ? slides[index] : nil,
                                    overlays: overlays,
                                    nativeTextOverrides: styleState.nativeTextOverrides,
                                    nativeContentOverrides: styleState.nativeContentOverrides,
                                    nativeLayoutOverrides: styleState.nativeLayoutOverrides,
                                    pageStyle: pageStyle,
                                    textTheme: textTheme,
                                    fallbackGroup: group,
                                    displayIndex: index + 1,
                                    isSelected: isSelected,
                                    onLoaded: {
                                        markPresentationThumbnailLoaded(fileID: fileID, groupID: group.id)
                                    }
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    removeSlideGroupFromPresentation(fileID: fileID, group: group)
                                } label: {
                                    Label(
                                        "Remove",
                                        systemImage: "trash"
                                    )
                                }
                            }

                            HStack(spacing: 4) {
                                presentationMergeBadgeButton(
                                    systemName: "arrow.left",
                                    isEnabled: group.startIndex > 0
                                ) {
                                    mergeSlideGroupBackward(
                                        fileID: fileID,
                                        group: group,
                                        slideCount: deck.orderedSlides.count
                                    )
                                }

                                presentationMergeBadgeButton(
                                    systemName: "arrow.right",
                                    isEnabled: group.endIndex < deck.orderedSlides.count - 1
                                ) {
                                    mergeSlideGroupForward(
                                        fileID: fileID,
                                        group: group,
                                        slideCount: deck.orderedSlides.count
                                    )
                                }
                            }
                            .padding(7)
                        }
                        .id(group.id)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, stripVerticalPadding)
                .frame(height: stripHeight, alignment: .center)
            }
            .frame(height: stripHeight, alignment: .center)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.white.opacity(0.16))
                    .frame(height: 1)
            }
            .onChange(of: selectedGroupID) { _, newID in
                guard let newID else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    scrollProxy.scrollTo(newID, anchor: .center)
                }
            }
            .onAppear {
                if let id = selectedGroupID {
                    scrollProxy.scrollTo(id, anchor: .center)
                }
            }
            } // ScrollViewReader
        }
        .ignoresSafeArea(edges: .bottom)
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    @ViewBuilder
    func presentationStylingFloatingEntryButton(
        fileID: UUID,
        groups: [EduPresentationSlideGroup]
    ) -> some View {
        let storedSelectedID = selectedPresentationGroupIDByFile[fileID]
        let selectedGroupID: UUID? = {
            if groups.contains(where: { $0.id == storedSelectedID }) {
                return storedSelectedID
            }
            return groups.first?.id
        }()

        VStack {
            Spacer(minLength: 0)
            HStack {
                presentationStylingEntryButton(
                    isActive: false,
                    isPulsing: shouldPulseDesignEntryButton
                ) {
                    togglePresentationStylingMode(
                        fileID: fileID,
                        groups: groups,
                        selectedGroupID: selectedGroupID
                    )
                }
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .preference(
                                key: TutorialDesignButtonFramePreferenceKey.self,
                                value: proxy.frame(in: .named(tutorialRootCoordinateSpaceName))
                            )
                    }
                )
                Spacer(minLength: 0)
            }
            .padding(.leading, 20)
            .padding(.bottom, presentationFilmstripHeight - 14)
        }
        .ignoresSafeArea(edges: .bottom)
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    @ViewBuilder
    func presentationSlideThumbnail(
        courseName: String,
        slide: EduPresentationComposedSlide?,
        overlays: [PresentationSlideOverlay],
        nativeTextOverrides: [PresentationNativeElement: PresentationTextStyleConfig],
        nativeContentOverrides: [PresentationNativeElement: String],
        nativeLayoutOverrides: [PresentationNativeElement: PresentationNativeLayoutOverride],
        pageStyle: PresentationPageStyle,
        textTheme: PresentationTextTheme,
        fallbackGroup: EduPresentationSlideGroup,
        displayIndex: Int,
        isSelected: Bool,
        onLoaded: @escaping () -> Void
    ) -> some View {
        let thumbnailWidth: CGFloat = 286
        let thumbnailHeight: CGFloat = thumbnailWidth / max(0.7, pageStyle.aspectPreset.ratio)
        let title = slide?.title ?? fallbackGroup.slideTitle

        ZStack(alignment: .topLeading) {
            if let slide {
                PresentationSlideThumbnailHTMLView(
                    html: presentationSlideThumbnailHTML(
                        courseName: courseName,
                        slide: slide,
                        overlays: overlays,
                        nativeTextOverrides: nativeTextOverrides,
                        nativeContentOverrides: nativeContentOverrides,
                        nativeLayoutOverrides: nativeLayoutOverrides,
                        pageStyle: pageStyle,
                        textTheme: textTheme
                    ),
                    onLoaded: onLoaded
                )
                .allowsHitTesting(false)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.black)
                        .lineLimit(2)
                    Text(fallbackGroup.subtitle)
                        .font(.system(size: 8, weight: .regular))
                        .foregroundStyle(.black.opacity(0.75))
                        .lineLimit(1)
                }
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(hex: pageStyle.backgroundColorHex))
                .onAppear {
                    onLoaded()
                }
            }

            Text("\(displayIndex)")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.75))
                )
                .padding(7)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: thumbnailWidth, height: thumbnailHeight, alignment: .leading)
        .background(Color(hex: pageStyle.backgroundColorHex))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isSelected ? Color.cyan : Color.black.opacity(0.1), lineWidth: isSelected ? 2.6 : 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }

    func presentationSlideThumbnailHTML(
        courseName: String,
        slide: EduPresentationComposedSlide,
        overlays: [PresentationSlideOverlay],
        nativeTextOverrides: [PresentationNativeElement: PresentationTextStyleConfig],
        nativeContentOverrides: [PresentationNativeElement: String],
        nativeLayoutOverrides: [PresentationNativeElement: PresentationNativeLayoutOverride],
        pageStyle: PresentationPageStyle,
        textTheme: PresentationTextTheme
    ) -> String {
        let baseHTML = themedPresentationSlideHTML(
            courseName: courseName,
            slide: slide,
            isChinese: isChineseUI(),
            pageStyle: pageStyle,
            textTheme: textTheme,
            nativeTextOverrides: nativeTextOverrides,
            nativeContentOverrides: nativeContentOverrides,
            nativeLayoutOverrides: nativeLayoutOverrides
        )
        let slideAspect = max(0.75, pageStyle.aspectPreset.ratio)
        let overlayNodesHTML = presentationOverlayLayerHTML(
            overlays: overlays,
            slideAspect: slideAspect,
            textTheme: textTheme
        )
        guard !overlayNodesHTML.isEmpty else { return baseHTML }

        let layerHTML = "<div class=\"edunode-overlay-layer\">\(overlayNodesHTML)</div>"
        guard let insertion = baseHTML.range(of: "</article>", options: .backwards) else {
            return baseHTML
        }
        return baseHTML.replacingCharacters(
            in: insertion.lowerBound..<insertion.lowerBound,
            with: layerHTML
        )
    }

    @ViewBuilder
    func presentationMergeBadgeButton(
        systemName: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.55))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(isEnabled ? 0.75 : 0.45))
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    func editorExportActions(for file: GNodeWorkspaceFile) -> [NodeEditorExportAction] {
        let context = EduLessonPlanContext(file: file)
        let baseName = sanitizedExportBaseName(file.name)

        return [
            NodeEditorExportAction(
                id: "edunode.courseware",
                title: S("app.export.courseware"),
                systemImage: "rectangle.on.rectangle",
                defaultFilename: "",
                contentType: .data,
                buildData: { graphData in
                    openPresentationPreview(for: file, graphData: graphData)
                    return nil
                }
            ),
            NodeEditorExportAction(
                id: "edunode.lesson.preview",
                title: S("app.export.lessonPlan"),
                systemImage: "doc.text.magnifyingglass",
                defaultFilename: "",
                contentType: .plainText,
                buildData: { graphData in
                    openLessonPlanPreview(
                        for: file,
                        graphData: graphData,
                        context: context,
                        baseName: baseName
                    )
                    return nil
                }
            )
        ]
    }

    func sanitizedExportBaseName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = S("app.files.defaultName").contains("%d")
            ? String(format: S("app.files.defaultName"), 1)
            : "Course"
        let source = trimmed.isEmpty ? fallback : trimmed
        let sanitized = source
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "Course" : sanitized
    }

    func S(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    func emptyDocumentData() -> Data {
        let document = GNodeDocument(nodes: [], connections: [], canvasState: [])
        return (try? encodeDocument(document)) ?? Data()
    }

}
