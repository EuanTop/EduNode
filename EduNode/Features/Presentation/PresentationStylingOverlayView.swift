import SwiftUI
import GNodeKit
#if canImport(PhotosUI)
import PhotosUI
#endif
#if canImport(WebKit)
import WebKit
#endif

struct PresentationStylingOverlayView: View {
    let courseName: String
    let slide: EduPresentationComposedSlide
    let stylingState: PresentationSlideStylingState
    let pageStyle: PresentationPageStyle
    let textTheme: PresentationTextTheme
    let topPadding: CGFloat
    let bottomReservedHeight: CGFloat
    let isChinese: Bool
    let onBack: () -> Void
    let onReset: () -> Void
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onInsertText: () -> Void
    let onInsertRoundedRect: () -> Void
    let onInsertImage: (Data) -> Void
    let onClearSelection: () -> Void
    let onSelectOverlay: (UUID) -> Void
    let onMoveOverlay: (UUID, CGPoint) -> Void
    let onRotateOverlay: (UUID, Double) -> Void
    let onUpdateImageOverlayFrame: (UUID, CGPoint, CGFloat, CGFloat) -> Void
    let onScaleOverlay: (UUID, CGFloat) -> Void
    let onCropOverlay: (UUID, CGRect, String?) -> Void
    let onDeleteOverlay: (UUID) -> Void
    let onExtractSubject: (UUID) -> Void
    let onConvertToSVG: (UUID) -> Void
    let onApplyFilter: (UUID, SVGFilterStyle) -> Void
    let onUpdateStylization: (UUID, SVGStylizationParameters) -> Void
    let onUpdateImageVectorStyle: (UUID, String, String, Bool) -> Void
    let onUpdateImageCornerRadius: (UUID, Double) -> Void
    let onApplyImageStyleToAll: (UUID) -> Void
    let onUpdateTextOverlay: (UUID, PresentationTextEditingState) -> Void
    let onUpdateRoundedRectOverlay: (UUID, PresentationRoundedRectEditingState) -> Void
    let onUpdateIconOverlay: (UUID, PresentationIconEditingState) -> Void
    let onUpdateTextTheme: (PresentationTextTheme) -> Void
    let onUpdateNativeTextOverride: (PresentationNativeElement, PresentationTextStyleConfig?) -> Void
    let onUpdateNativeContentOverride: (PresentationNativeElement, String?) -> Void
    let onUpdateNativeLayoutOverride: (PresentationNativeElement, PresentationNativeLayoutOverride?) -> Void
    let onClearNativeTextOverrides: () -> Void
    let onApplyTemplate: (PresentationThemeTemplate) -> Void
    let onUpdatePageStyle: (PresentationPageStyle) -> Void
    let onUpdateVectorization: (PresentationVectorizationSettings) -> Void

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var activePanel: PresentationInspectorPanel = .page
    @State private var selectedPageTextPreset: PresentationTextStylePreset = .h1
    @State private var dragOffsets: [UUID: CGSize] = [:]
    @State private var pinchScales: [UUID: CGFloat] = [:]
    @State private var liveRotations: [UUID: Angle] = [:]
    @State private var activeHandleInteractionOverlayID: UUID?
    @State private var cropOriginX: Double = 0
    @State private var cropOriginY: Double = 0
    @State private var cropWidth: Double = 1
    @State private var cropHeight: Double = 1
    @State private var selectedNativeElement: PresentationNativeElement?
    @State private var nativeElementRects: [PresentationNativeElement: CGRect] = [:]
    @State private var imageDragActivationByOverlayID: [UUID: Bool] = [:]
    @State private var ignoreCanvasTapUntil: Date = .distantPast
    @State private var htmlCanvasReady = false
    @State private var nativeTextDraftElement: PresentationNativeElement?
    @State private var nativeTextDraft = ""

    private enum ImageCropEdge {
        case left
        case right
        case top
        case bottom
    }

    private var selectedOverlay: PresentationSlideOverlay? {
        guard let selectedID = stylingState.selectedOverlayID else { return nil }
        return stylingState.overlays.first(where: { $0.id == selectedID })
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.86)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                toolbar
                HStack(alignment: .top, spacing: 16) {
                    slideCanvas
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    rightSidebar
                        .frame(width: 332)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, topPadding + 36)
            .padding(.horizontal, 20)
            .padding(.bottom, bottomReservedHeight + 10)
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    await MainActor.run {
                        onInsertImage(data)
                        selectedNativeElement = nil
                        activePanel = .edit
                    }
                }
                await MainActor.run {
                    selectedPhotoItem = nil
                }
            }
        }
        .onChange(of: selectedOverlay?.id) { _, newID in
            if newID != nil {
                activePanel = .edit
            }
            resetCropInputs()
        }
        .onChange(of: selectedNativeElement) { _, newElement in
            syncNativeTextDraft(for: newElement)
        }
        .onAppear {
            resetCropInputs()
            htmlCanvasReady = false
            syncNativeTextDraft(for: selectedNativeElement)
        }
        .onChange(of: slide.id) { _, _ in
            selectedNativeElement = nil
            nativeElementRects = [:]
            htmlCanvasReady = false
            nativeTextDraftElement = nil
            nativeTextDraft = ""
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Label(isChinese ? "返回" : "Back", systemImage: "chevron.backward")
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(.ultraThinMaterial))
            }
            .buttonStyle(.plain)

            Spacer(minLength: 10)

            Button(action: onReset) {
                Label(isChinese ? "重置" : "Reset", systemImage: "arrow.counterclockwise")
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(.ultraThinMaterial))
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Button(action: onUndo) {
                    Image(systemName: "arrow.uturn.backward")
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(.ultraThinMaterial))
                }
                .buttonStyle(.plain)

                Button(action: onRedo) {
                    Image(systemName: "arrow.uturn.forward")
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(.ultraThinMaterial))
                }
                .buttonStyle(.plain)
            }

            if let selectedOverlay {
                Button {
                    onDeleteOverlay(selectedOverlay.id)
                } label: {
                    Label(isChinese ? "删除" : "Delete", systemImage: "trash")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(.ultraThinMaterial))
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(.white)
    }

    private var slideCanvas: some View {
        GeometryReader { container in
            let availableWidth = max(1, container.size.width)
            let availableHeight = max(1, container.size.height)
            let aspectRatio = max(0.75, pageStyle.aspectPreset.ratio)
            let canvasWidth = min(availableWidth, availableHeight * aspectRatio)
            let canvasHeight = canvasWidth / aspectRatio
            let canvasCornerRadius: CGFloat = 18
            let canvasSize = CGSize(width: canvasWidth, height: canvasHeight)

            ZStack {
                if !htmlCanvasReady {
                    canvasLoadingPlaceholder(canvasSize: canvasSize)
                        .transition(.opacity)
                }

                PresentationSlideCanvasHTMLView(
                    baseHTML: editorSlideHTMLRemovingInnerMask(
                        themedPresentationSlideHTML(
                            courseName: courseName,
                            slide: slide,
                            isChinese: isChinese,
                            pageStyle: pageStyle,
                            textTheme: textTheme,
                            nativeTextOverrides: stylingState.nativeTextOverrides,
                            nativeContentOverrides: stylingState.nativeContentOverrides,
                            nativeLayoutOverrides: stylingState.nativeLayoutOverrides
                        )
                    ),
                    textTheme: textTheme,
                    overlays: stylingState.overlays,
                    selectedOverlayID: stylingState.selectedOverlayID,
                    onLoadStateChange: { isReady in
                        withAnimation(.easeOut(duration: 0.16)) {
                            htmlCanvasReady = isReady
                        }
                    },
                    onSelectOverlay: { selectedID in
                        if let selectedID {
                            selectedNativeElement = nil
                            onSelectOverlay(selectedID)
                            activePanel = .edit
                        } else {
                            onClearSelection()
                        }
                    },
                    onCanvasTap: { normalizedPoint, hitNativeElement in
                        if let hitNativeElement {
                            selectedNativeElement = hitNativeElement
                            onClearSelection()
                            activePanel = .edit
                        } else if let hitElement = nativeElement(at: normalizedPoint) {
                            selectedNativeElement = hitElement
                            onClearSelection()
                            activePanel = .edit
                        } else {
                            selectedNativeElement = nil
                            onClearSelection()
                        }
                    },
                    onCommitOverlayFrame: { overlayID, center, normalizedWidth, normalizedHeight in
                        commitOverlayFrameFromHTML(
                            overlayID: overlayID,
                            center: center,
                            normalizedWidth: normalizedWidth,
                            normalizedHeight: normalizedHeight
                        )
                    },
                    onRotateOverlay: { overlayID, deltaDegrees in
                        onRotateOverlay(overlayID, deltaDegrees)
                    },
                    onCropOverlay: { overlayID, rect, handle in
                        onCropOverlay(overlayID, rect, handle)
                    },
                    onDeleteOverlay: { overlayID in
                        onDeleteOverlay(overlayID)
                    },
                    onExtractOverlaySubject: { overlayID in
                        onSelectOverlay(overlayID)
                        activePanel = .edit
                        onExtractSubject(overlayID)
                    },
                    onMoveNativeElement: { element, offset in
                        onUpdateNativeLayoutOverride(element, offset)
                    },
                    onNativeRectsUpdate: { rects in
                        if rects != nativeElementRects {
                            nativeElementRects = rects
                        }
                    }
                )
                .opacity(htmlCanvasReady ? 1 : 0.001)
                .allowsHitTesting(true)

                nativeElementHighlightOverlay(canvasSize: canvasSize)
            }
            .background(Color(hex: pageStyle.backgroundColorHex))
            .clipShape(RoundedRectangle(cornerRadius: canvasCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: canvasCornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .frame(width: canvasWidth, height: canvasHeight)
            .shadow(color: .black.opacity(0.45), radius: 20, y: 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func canvasLoadingPlaceholder(canvasSize: CGSize) -> some View {
        ZStack {
            Color(hex: pageStyle.backgroundColorHex)

            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(0.24))
                    .frame(width: canvasSize.width * 0.42, height: canvasSize.height * 0.06)
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(0.18))
                    .frame(width: canvasSize.width * 0.28, height: canvasSize.height * 0.04)
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.16))
                    .frame(height: canvasSize.height * 0.34)
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.14))
                    .frame(height: canvasSize.height * 0.24)
            }
            .padding(canvasSize.width * 0.06)

            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white.opacity(0.9))
        }
    }

    private func nativeElement(at normalizedPoint: CGPoint) -> PresentationNativeElement? {
        nativeElementRegions().first { _, normalizedRect in
            normalizedRect.contains(normalizedPoint)
        }?.0
    }

    private func commitOverlayFrameFromHTML(
        overlayID: UUID,
        center: CGPoint,
        normalizedWidth: CGFloat,
        normalizedHeight: CGFloat
    ) {
        guard let overlay = stylingState.overlays.first(where: { $0.id == overlayID }) else { return }
        let clampedCenter = CGPoint(
            x: clamp(center.x, min: 0.04, max: 0.96),
            y: clamp(center.y, min: 0.08, max: 0.92)
        )

        switch overlay.kind {
        case .text:
            onMoveOverlay(overlayID, clampedCenter)
            var editing = overlay.textEditingState
            editing.normalizedWidth = max(0.2, min(0.92, normalizedWidth))
            editing.normalizedHeight = max(0.08, min(0.72, normalizedHeight))
            onUpdateTextOverlay(overlayID, editing)
        case .roundedRect:
            onMoveOverlay(overlayID, clampedCenter)
            var editing = overlay.roundedRectEditingState
            editing.normalizedWidth = max(0.1, min(0.92, normalizedWidth))
            editing.normalizedHeight = max(0.08, min(0.72, normalizedHeight))
            onUpdateRoundedRectOverlay(overlayID, editing)
        case .icon:
            onMoveOverlay(overlayID, clampedCenter)
            var editing = overlay.iconEditingState
            editing.normalizedWidth = max(0.08, min(0.42, normalizedWidth))
            onUpdateIconOverlay(overlayID, editing)
        case .image:
            onUpdateImageOverlayFrame(
                overlayID,
                clampedCenter,
                max(0.08, min(0.92, normalizedWidth)),
                max(0.08, min(0.92, normalizedHeight))
            )
        }
    }

    private func clipShape(
        for overlay: PresentationSlideOverlay,
        overlayWidth: CGFloat,
        overlayHeight: CGFloat
    ) -> AnyShape {
        guard overlay.isRoundedRect else {
            return AnyShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }

        let minDimension = max(1, min(overlayWidth, overlayHeight))
        switch overlay.shapeStyle {
        case .rectangle:
            return AnyShape(RoundedRectangle(cornerRadius: 0, style: .continuous))
        case .roundedRect:
            let corner = max(0, minDimension * CGFloat(overlay.shapeCornerRadiusRatio))
            return AnyShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        case .capsule:
            return AnyShape(Capsule(style: .continuous))
        case .ellipse:
            return AnyShape(Ellipse())
        }
    }

    @ViewBuilder
    private func overlayView(overlay: PresentationSlideOverlay, canvasSize: CGSize) -> some View {
        let normalizedWidth = clamp(overlay.normalizedWidth, min: 0.08, max: 0.92)
        let normalizedHeight = clamp(overlay.normalizedHeight, min: 0.08, max: 0.92)
        let safeAspect = clamp(overlay.aspectRatio, min: 0.15, max: 10)
        let liveScale = pinchScales[overlay.id] ?? 1
        let liveRotation = liveRotations[overlay.id]?.degrees ?? 0
        let overlayWidth = max(overlay.isText ? 120 : 56, canvasSize.width * normalizedWidth * liveScale)
        let overlayHeight: CGFloat = {
            if overlay.isText {
                return max(42, canvasSize.height * normalizedHeight * liveScale)
            }
            if overlay.isRoundedRect {
                return max(34, canvasSize.height * normalizedHeight * liveScale)
            }
            if overlay.isIcon {
                return overlayWidth
            }
            return max(56, canvasSize.height * normalizedHeight * liveScale)
        }()
        let imageContentRect = imageOverlayContentRect(
            overlayWidth: overlayWidth,
            overlayHeight: overlayHeight,
            aspectRatio: safeAspect
        )
        let baseX = clamp(overlay.center.x, min: 0.04, max: 0.96) * canvasSize.width
        let baseY = clamp(overlay.center.y, min: 0.08, max: 0.92) * canvasSize.height
        let dragOffset = dragOffsets[overlay.id] ?? .zero
        let x = baseX + dragOffset.width
        let y = baseY + dragOffset.height
        let isSelected = overlay.id == stylingState.selectedOverlayID
        let overlayShape = clipShape(
            for: overlay,
            overlayWidth: overlayWidth,
            overlayHeight: overlayHeight
        )

        ZStack {
            if overlay.isText {
                Text(overlay.textContent.isEmpty ? (isChinese ? "文本" : "Text") : overlay.textContent)
                    .font(
                        .system(
                            size: max(12, min(64, overlay.textFontSize)),
                            weight: overlay.resolvedTextWeight,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(Color(hex: overlay.textColorHex))
                    .multilineTextAlignment(overlay.textAlignment.textAlignment)
                    .lineLimit(nil)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: overlay.textAlignment.frameAlignment)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            } else if overlay.isRoundedRect {
                overlayShape
                    .fill(Color(hex: overlay.shapeFillColorHex))
                    .overlay(
                        overlayShape
                            .stroke(
                                Color(hex: overlay.shapeBorderColorHex),
                                lineWidth: max(0.6, min(10, overlay.shapeBorderWidth))
                            )
                    )
            } else if overlay.isIcon {
                ZStack {
                    if overlay.iconHasBackground {
                        RoundedRectangle(cornerRadius: max(8, overlayWidth * 0.22), style: .continuous)
                            .fill(Color(hex: overlay.iconBackgroundColorHex))
                    }
                    Image(systemName: overlay.iconSystemName)
                        .font(.system(size: max(16, overlayWidth * 0.48), weight: .semibold))
                        .foregroundStyle(Color(hex: overlay.iconColorHex))
                }
            } else if let svg = overlay.renderedSVGString {
                ZStack {
                    if overlay.vectorBackgroundVisible {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(hex: overlay.vectorBackgroundColorHex))
                    }
                    PresentationSVGOverlayView(
                        svg: svg,
                        cssFilter: presentationImageCSSFilter(
                            style: overlay.selectedFilter,
                            params: overlay.stylization
                        ),
                        backgroundColorHex: overlay.vectorBackgroundColorHex,
                        backgroundVisible: overlay.vectorBackgroundVisible
                    )
                        .allowsHitTesting(false)
                }
            } else {
                #if canImport(UIKit)
                if let image = UIImage(data: overlay.displayImageData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black.opacity(0.08))
                }
                #else
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.08))
                #endif
            }

            if overlay.isExtracting {
                Color.black.opacity(0.26)
                ProgressView()
                    .tint(.white)
            }
        }
        .frame(width: overlayWidth, height: overlayHeight)
        .clipShape(overlayShape)
        .overlay(
            overlayShape
                .stroke(isSelected ? Color.cyan : Color.white.opacity(0.12), lineWidth: isSelected ? 2.4 : 1)
        )
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Button {
                    onDeleteOverlay(overlay.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(
                            Circle()
                                .fill(Color.black.opacity(0.75))
                        )
                }
                .buttonStyle(.plain)
                .padding(6)
            }
        }
        .overlay {
            if isSelected && overlay.isImage {
                imageDirectManipulationHandles(
                    overlay: overlay,
                    overlayWidth: overlayWidth,
                    overlayHeight: overlayHeight
                )
            }
        }
        .rotationEffect(.degrees(overlay.rotationDegrees + liveRotation))
        .position(x: x, y: y)
        .contentShape(Rectangle())
        .gesture(
            SpatialTapGesture()
                .onEnded { value in
                    if overlay.isImage {
                        let tapInsideImage = imageContentRect.insetBy(dx: -8, dy: -8).contains(value.location)
                        guard tapInsideImage else { return }
                    }
                    selectedNativeElement = nil
                    onSelectOverlay(overlay.id)
                    activePanel = .edit
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    guard activeHandleInteractionOverlayID != overlay.id else { return }
                    if overlay.isImage {
                        if imageDragActivationByOverlayID[overlay.id] == nil {
                            let startInside = imageContentRect.insetBy(dx: -10, dy: -10).contains(value.startLocation)
                            imageDragActivationByOverlayID[overlay.id] = startInside
                        }
                        guard imageDragActivationByOverlayID[overlay.id] == true else { return }
                    }
                    dragOffsets[overlay.id] = value.translation
                    if stylingState.selectedOverlayID != overlay.id {
                        selectedNativeElement = nil
                        onSelectOverlay(overlay.id)
                    }
                }
                .onEnded { value in
                    guard activeHandleInteractionOverlayID != overlay.id else {
                        dragOffsets[overlay.id] = nil
                        return
                    }
                    defer {
                        imageDragActivationByOverlayID[overlay.id] = nil
                    }
                    if overlay.isImage, imageDragActivationByOverlayID[overlay.id] != true {
                        dragOffsets[overlay.id] = nil
                        return
                    }
                    dragOffsets[overlay.id] = nil
                    let movedCenter = CGPoint(
                        x: clamp((baseX + value.translation.width) / canvasSize.width, min: 0.04, max: 0.96),
                        y: clamp((baseY + value.translation.height) / canvasSize.height, min: 0.08, max: 0.92)
                    )
                    onMoveOverlay(overlay.id, movedCenter)
                }
        )
        .simultaneousGesture(
            MagnificationGesture()
                .onChanged { value in
                    guard activeHandleInteractionOverlayID != overlay.id else { return }
                    pinchScales[overlay.id] = value
                    if stylingState.selectedOverlayID != overlay.id {
                        selectedNativeElement = nil
                        onSelectOverlay(overlay.id)
                        activePanel = .edit
                    }
                }
                .onEnded { value in
                    guard activeHandleInteractionOverlayID != overlay.id else {
                        pinchScales[overlay.id] = nil
                        return
                    }
                    pinchScales[overlay.id] = nil
                    let scale = max(0.5, min(2.4, value))
                    if abs(scale - 1) > 0.01 {
                        onScaleOverlay(overlay.id, scale)
                    }
                }
        )
        .simultaneousGesture(
            RotationGesture()
                .onChanged { value in
                    guard overlay.isImage else { return }
                    guard activeHandleInteractionOverlayID != overlay.id else { return }
                    liveRotations[overlay.id] = value
                    if stylingState.selectedOverlayID != overlay.id {
                        selectedNativeElement = nil
                        onSelectOverlay(overlay.id)
                        activePanel = .edit
                    }
                }
                .onEnded { value in
                    guard overlay.isImage else { return }
                    guard activeHandleInteractionOverlayID != overlay.id else {
                        liveRotations[overlay.id] = nil
                        return
                    }
                    liveRotations[overlay.id] = nil
                    let delta = value.degrees
                    if abs(delta) > 0.1 {
                        onRotateOverlay(overlay.id, delta)
                    }
                }
        )
        .onLongPressGesture(minimumDuration: 0.45) {
            guard overlay.isImage else { return }
            ignoreCanvasTapUntil = Date().addingTimeInterval(0.5)
            onExtractSubject(overlay.id)
        }
    }

    @ViewBuilder
    private func imageDirectManipulationHandles(
        overlay: PresentationSlideOverlay,
        overlayWidth: CGFloat,
        overlayHeight: CGFloat
    ) -> some View {
        let referenceLength = max(overlayWidth, overlayHeight)
        let handleInset: CGFloat = 10

        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.cyan.opacity(0.9), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))

            cornerResizeHandle(
                overlayID: overlay.id,
                signX: -1,
                signY: -1,
                referenceLength: referenceLength
            )
            .position(x: handleInset, y: handleInset)

            cornerResizeHandle(
                overlayID: overlay.id,
                signX: 1,
                signY: -1,
                referenceLength: referenceLength
            )
            .position(x: overlayWidth - handleInset, y: handleInset)

            cornerResizeHandle(
                overlayID: overlay.id,
                signX: -1,
                signY: 1,
                referenceLength: referenceLength
            )
            .position(x: handleInset, y: overlayHeight - handleInset)

            cornerResizeHandle(
                overlayID: overlay.id,
                signX: 1,
                signY: 1,
                referenceLength: referenceLength
            )
            .position(x: overlayWidth - handleInset, y: overlayHeight - handleInset)

            edgeCropHandle(
                overlayID: overlay.id,
                edge: .left,
                overlayWidth: overlayWidth,
                overlayHeight: overlayHeight
            )
            .position(x: 6, y: overlayHeight * 0.5)

            edgeCropHandle(
                overlayID: overlay.id,
                edge: .right,
                overlayWidth: overlayWidth,
                overlayHeight: overlayHeight
            )
            .position(x: overlayWidth - 6, y: overlayHeight * 0.5)

            edgeCropHandle(
                overlayID: overlay.id,
                edge: .top,
                overlayWidth: overlayWidth,
                overlayHeight: overlayHeight
            )
            .position(x: overlayWidth * 0.5, y: 6)

            edgeCropHandle(
                overlayID: overlay.id,
                edge: .bottom,
                overlayWidth: overlayWidth,
                overlayHeight: overlayHeight
            )
            .position(x: overlayWidth * 0.5, y: overlayHeight - 6)
        }
        .allowsHitTesting(true)
    }

    private func cornerResizeHandle(
        overlayID: UUID,
        signX: CGFloat,
        signY: CGFloat,
        referenceLength: CGFloat
    ) -> some View {
        Circle()
            .fill(Color.cyan)
            .frame(width: 12, height: 12)
            .shadow(color: .black.opacity(0.35), radius: 1.2, y: 0.6)
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        activeHandleInteractionOverlayID = overlayID
                        dragOffsets[overlayID] = .zero
                        let delta = (value.translation.width * signX + value.translation.height * signY) * 0.5
                        let scale = max(0.45, min(3.2, 1 + (delta / max(referenceLength, 1))))
                        pinchScales[overlayID] = scale
                    }
                    .onEnded { value in
                        activeHandleInteractionOverlayID = nil
                        pinchScales[overlayID] = nil
                        let delta = (value.translation.width * signX + value.translation.height * signY) * 0.5
                        let scale = max(0.45, min(3.2, 1 + (delta / max(referenceLength, 1))))
                        if abs(scale - 1) > 0.01 {
                            onScaleOverlay(overlayID, scale)
                        }
                    }
            )
    }

    private func edgeCropHandle(
        overlayID: UUID,
        edge: ImageCropEdge,
        overlayWidth: CGFloat,
        overlayHeight: CGFloat
    ) -> some View {
        let isHorizontal = edge == .left || edge == .right
        let size = CGSize(width: isHorizontal ? 12 : 30, height: isHorizontal ? 30 : 12)
        return Capsule()
            .fill(Color.white.opacity(0.92))
            .frame(width: size.width, height: size.height)
            .shadow(color: .black.opacity(0.28), radius: 1.1, y: 0.6)
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        activeHandleInteractionOverlayID = overlayID
                        dragOffsets[overlayID] = .zero
                    }
                    .onEnded { value in
                        activeHandleInteractionOverlayID = nil
                        let dx = value.translation.width / max(overlayWidth, 1)
                        let dy = value.translation.height / max(overlayHeight, 1)
                        if let cropRect = cropRectForEdge(edge, dx: dx, dy: dy) {
                            onCropOverlay(overlayID, cropRect, cropHandleName(for: edge))
                        }
                    }
            )
    }

    private func cropHandleName(for edge: ImageCropEdge) -> String {
        switch edge {
        case .left:
            return "crop-left"
        case .right:
            return "crop-right"
        case .top:
            return "crop-top"
        case .bottom:
            return "crop-bottom"
        }
    }

    private func cropRectForEdge(_ edge: ImageCropEdge, dx: CGFloat, dy: CGFloat) -> CGRect? {
        let maxCut: CGFloat = 0.82
        let minSize: CGFloat = 0.18
        var rect = CGRect(x: 0, y: 0, width: 1, height: 1)

        switch edge {
        case .left:
            let cut = max(0, min(maxCut, dx))
            rect.origin.x = cut
            rect.size.width = max(minSize, 1 - cut)
        case .right:
            let cut = max(0, min(maxCut, -dx))
            rect.size.width = max(minSize, 1 - cut)
        case .top:
            let cut = max(0, min(maxCut, dy))
            rect.origin.y = cut
            rect.size.height = max(minSize, 1 - cut)
        case .bottom:
            let cut = max(0, min(maxCut, -dy))
            rect.size.height = max(minSize, 1 - cut)
        }

        guard rect.width >= minSize, rect.height >= minSize else { return nil }
        return rect
    }

    private func imageOverlayHitRect(
        overlay: PresentationSlideOverlay,
        canvasSize: CGSize
    ) -> CGRect {
        let liveScale = pinchScales[overlay.id] ?? 1
        let normalizedWidth = clamp(overlay.normalizedWidth, min: 0.08, max: 0.92)
        let normalizedHeight = clamp(overlay.normalizedHeight, min: 0.08, max: 0.92)
        let overlayWidth = max(56, canvasSize.width * normalizedWidth * liveScale)
        let overlayHeight = max(56, canvasSize.height * normalizedHeight * liveScale)
        let contentRect = imageOverlayContentRect(
            overlayWidth: overlayWidth,
            overlayHeight: overlayHeight,
            aspectRatio: clamp(overlay.aspectRatio, min: 0.15, max: 10)
        )
        let baseX = clamp(overlay.center.x, min: 0.04, max: 0.96) * canvasSize.width
        let baseY = clamp(overlay.center.y, min: 0.08, max: 0.92) * canvasSize.height
        let dragOffset = dragOffsets[overlay.id] ?? .zero
        let centerX = baseX + dragOffset.width
        let centerY = baseY + dragOffset.height
        return CGRect(
            x: centerX - overlayWidth * 0.5 + contentRect.origin.x,
            y: centerY - overlayHeight * 0.5 + contentRect.origin.y,
            width: contentRect.width,
            height: contentRect.height
        )
        .insetBy(dx: -10, dy: -10)
    }

    private func imageOverlayContentRect(
        overlayWidth: CGFloat,
        overlayHeight: CGFloat,
        aspectRatio: CGFloat
    ) -> CGRect {
        guard overlayWidth > 0, overlayHeight > 0 else {
            return CGRect(origin: .zero, size: CGSize(width: overlayWidth, height: overlayHeight))
        }

        let safeAspect = clamp(aspectRatio, min: 0.15, max: 10)
        let frameAspect = overlayWidth / max(overlayHeight, 0.0001)

        if safeAspect >= frameAspect {
            let contentHeight = max(1, overlayWidth / safeAspect)
            let y = (overlayHeight - contentHeight) * 0.5
            return CGRect(x: 0, y: y, width: overlayWidth, height: contentHeight)
        } else {
            let contentWidth = max(1, overlayHeight * safeAspect)
            let x = (overlayWidth - contentWidth) * 0.5
            return CGRect(x: x, y: 0, width: contentWidth, height: overlayHeight)
        }
    }

    @ViewBuilder
    private func nativeElementHighlightOverlay(canvasSize: CGSize) -> some View {
        if let selectedNativeElement,
           let normalizedRect = normalizedRect(for: selectedNativeElement) {
            let rect = CGRect(
                x: normalizedRect.origin.x * canvasSize.width,
                y: normalizedRect.origin.y * canvasSize.height,
                width: normalizedRect.width * canvasSize.width,
                height: normalizedRect.height * canvasSize.height
            )
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    Color.cyan,
                    style: StrokeStyle(lineWidth: 2.0, dash: [5, 4])
                )
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .allowsHitTesting(false)
        }
    }

    private func nativeElementRegions() -> [(PresentationNativeElement, CGRect)] {
        if !nativeElementRects.isEmpty {
            return nativeElementRects
                .map { ($0.key, $0.value) }
                .sorted { lhs, rhs in
                    nativeElementPriority(lhs.0) < nativeElementPriority(rhs.0)
                }
        }
        return fallbackNativeElementRegions()
    }

    private func normalizedRect(for element: PresentationNativeElement) -> CGRect? {
        if let precise = nativeElementRects[element] {
            return precise
        }
        return fallbackNativeElementRegions().first(where: { $0.0 == element })?.1
    }

    private func nativeElementPriority(_ element: PresentationNativeElement) -> Int {
        switch element {
        case .toolkitIcon:
            return 0
        case .levelChip:
            return 1
        case .title:
            return 2
        case .subtitle:
            return 3
        case .toolkitContent:
            return 4
        case .mainContent:
            return 5
        case .activityCard:
            return 6
        case .mainCard:
            return 7
        }
    }

    private func fallbackNativeElementRegions() -> [(PresentationNativeElement, CGRect)] {
        var regions: [(PresentationNativeElement, CGRect)] = [
            (.title, CGRect(x: 0.05, y: 0.05, width: 0.70, height: 0.13)),
            (.subtitle, CGRect(x: 0.05, y: 0.16, width: 0.66, height: 0.1)),
            (.levelChip, CGRect(x: 0.05, y: 0.2, width: 0.24, height: 0.07)),
            (.mainContent, CGRect(x: 0.07, y: 0.38, width: 0.56, height: 0.45)),
            (.mainCard, CGRect(x: 0.05, y: 0.3, width: 0.60, height: 0.58))
        ]

        if !slide.toolkitItems.isEmpty {
            regions.append((.toolkitIcon, CGRect(x: 0.84, y: 0.06, width: 0.11, height: 0.11)))
            regions.append((.toolkitContent, CGRect(x: 0.69, y: 0.38, width: 0.24, height: 0.45)))
            regions.append((.activityCard, CGRect(x: 0.67, y: 0.3, width: 0.28, height: 0.58)))
        }
        return regions
    }

    @ViewBuilder
    private var rightSidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isChinese ? "演示设计" : "Presentation Design")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)

            inspectorPanelPicker

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    switch activePanel {
                    case .page:
                        pagePanel
                    case .edit:
                        editPanel
                            .modifier(PresentationKeyboardAdaptive())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    @ViewBuilder
    private func filterStrip(
        for overlay: PresentationSlideOverlay,
        includeBackground: Bool = true
    ) -> some View {
        let canApply = overlay.isImage && overlay.vectorDocument != nil
        let stripContent = VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SVGFilterStyle.allCases) { style in
                        let isActive = overlay.selectedFilter == style
                        Button {
                            onApplyFilter(overlay.id, style)
                        } label: {
                            Text(style.displayName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(
                                    isActive && canApply
                                        ? Color.black
                                        : Color.white.opacity(canApply ? 1 : 0.45)
                                )
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule()
                                        .fill(isActive && canApply ? Color.white : Color.white.opacity(0.14))
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(!canApply)
                    }
                }
                .padding(.horizontal, 2)
            }

            if !canApply {
                Text(isChinese ? "SVG 正在生成..." : "Building SVG...")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.65))
            }
        }

        if includeBackground {
            stripContent
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
        } else {
            stripContent
        }
    }

    private var inspectorPanelPicker: some View {
        Picker("", selection: $activePanel) {
            Text(isChinese ? "页面" : "Page")
                .tag(PresentationInspectorPanel.page)
            Text(isChinese ? "编辑" : "Edit")
                .tag(PresentationInspectorPanel.edit)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    @ViewBuilder
    private var editPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            editInsertPanel

            if let selectedOverlay {
                switch selectedOverlay.kind {
                case .text:
                    textOverlayPanel(for: selectedOverlay)
                case .roundedRect:
                    roundedRectOverlayPanel(for: selectedOverlay)
                case .icon:
                    iconOverlayPanel(for: selectedOverlay)
                case .image:
                    imagePanel(for: selectedOverlay)
                }
            } else if let selectedNativeElement {
                nativeElementPanel(for: selectedNativeElement)
            } else {
                Text(isChinese ? "先选择一个元素，再在这里编辑属性。" : "Select an element to edit its properties.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.82))
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
            }
        }
    }

    @ViewBuilder
    private var editInsertPanel: some View {
        let isTextActive = selectedOverlay?.isText == true
        let isRectActive = selectedOverlay?.isRoundedRect == true
        let isImageActive = selectedOverlay?.isImage == true
        VStack(alignment: .leading, spacing: 10) {
            Text(isChinese ? "新增元素" : "Insert")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))

            HStack(spacing: 8) {
                insertActionButton(title: isChinese ? "文本" : "Text", systemImage: "textformat", isActive: isTextActive) {
                    onInsertText()
                    activePanel = .edit
                }

                insertActionButton(title: isChinese ? "形状" : "Shape", systemImage: "rectangle.roundedtop.fill", isActive: isRectActive) {
                    onInsertRoundedRect()
                    activePanel = .edit
                }

                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    insertActionLabel(
                        title: isChinese ? "图片" : "Image",
                        systemImage: "photo",
                        isActive: isImageActive
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    private func insertActionButton(
        title: String,
        systemImage: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            insertActionLabel(title: title, systemImage: systemImage, isActive: isActive)
        }
        .buttonStyle(.plain)
    }

    private func insertActionLabel(title: String, systemImage: String, isActive: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .frame(height: 16)
            Text(title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .foregroundStyle(isActive ? Color.black : Color.white)
        .frame(maxWidth: .infinity, minHeight: 62, maxHeight: 62)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isActive ? Color.white : Color.white.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    isActive ? Color.clear : Color.white.opacity(0.24),
                    lineWidth: isActive ? 0 : 1
                )
        )
    }

    @ViewBuilder
    private func nativeElementPanel(for element: PresentationNativeElement) -> some View {
        let linkedPreset = nativeElementTextPreset(for: element)
        let selectedStyle = selectedNativeStyle(for: element)
        let isOverridden = stylingState.nativeTextOverrides[element] != nil
        let textEditable = nativeElementSupportsTextEditing(element)
        let hasTextContentOverride = stylingState.nativeContentOverrides[element] != nil
        let layoutOverride = stylingState.nativeLayoutOverrides[element]
        VStack(alignment: .leading, spacing: 10) {
            Text(isChinese ? "已选中原生课件元素" : "Selected Native Element")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))

            Text(nativeElementLabel(element))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)

            Text(
                isChinese
                    ? "该元素来自节点自动生成内容，可在这里直接调对应文本样式。"
                    : "This element is generated from node content. You can adjust its linked text style here."
            )
            .font(.caption)
            .foregroundStyle(.white.opacity(0.76))

            if let linkedPreset, let selectedStyle {
                nativeElementTextStyleEditor(
                    for: linkedPreset,
                    style: selectedStyle
                ) { nextStyle in
                    onUpdateNativeTextOverride(element, nextStyle)
                }
            }

            if textEditable {
                VStack(alignment: .leading, spacing: 6) {
                    Text(isChinese ? "文本内容" : "Content")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))

                    TextEditor(text: Binding(
                        get: { nativeTextDraftValue(for: element) },
                        set: { next in
                            nativeTextDraftElement = element
                            nativeTextDraft = next
                            commitNativeTextDraft(for: element)
                        }
                    ))
                    .font(.caption)
                    .foregroundStyle(.white)
                    .frame(minHeight: 88, maxHeight: 150)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )

                    HStack(spacing: 8) {
                        Button {
                            onUpdateNativeContentOverride(element, nil)
                            syncNativeTextDraft(for: element)
                        } label: {
                            Label(isChinese ? "重置文本" : "Reset Text", systemImage: "eraser")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.92))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(Color.white.opacity(0.16)))
                        }
                        .buttonStyle(.plain)
                        .disabled(!hasTextContentOverride)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(
                    isChinese
                        ? "在画布中直接拖动该元素可调整位置。"
                        : "Drag this native element directly on canvas to move it."
                )
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.72))

                if let layoutOverride, !layoutOverride.isZero {
                    Text(
                        String(
                            format: isChinese ? "偏移 x: %.3f, y: %.3f" : "Offset x: %.3f, y: %.3f",
                            layoutOverride.offsetX,
                            layoutOverride.offsetY
                        )
                    )
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))

                    Button {
                        onUpdateNativeLayoutOverride(element, nil)
                    } label: {
                        Label(isChinese ? "重置位置" : "Reset Position", systemImage: "arrow.uturn.backward")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.92))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.white.opacity(0.16)))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                Button {
                    onUpdateNativeTextOverride(element, nil)
                } label: {
                    Label(isChinese ? "重置当前元素" : "Reset Element", systemImage: "arrow.uturn.backward")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.16))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!isOverridden)

                if let linkedPreset {
                    Button {
                        selectedPageTextPreset = linkedPreset
                        activePanel = .page
                    } label: {
                        Label(isChinese ? "前往 Page 样式" : "Go to Page", systemImage: "slider.horizontal.3")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(Color.white)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    @ViewBuilder
    private func nativeElementTextStyleEditor(
        for preset: PresentationTextStylePreset,
        style: PresentationTextStyleConfig,
        onUpdate: @escaping (PresentationTextStyleConfig) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text((isChinese ? "关联样式：" : "Linked Style: ") + preset.label(isChinese: isChinese))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))

            vectorSlider(
                title: isChinese ? "字号（cqw）" : "Size (cqw)",
                value: style.sizeCqw,
                range: sizeRange(for: preset),
                step: 0.02
            ) { newValue in
                var next = style
                next.sizeCqw = newValue
                onUpdate(next)
            }

            vectorSlider(
                title: isChinese ? "字重" : "Weight",
                value: style.weightValue,
                range: 0...1,
                step: 0.01
            ) { newValue in
                var next = style
                next.weightValue = newValue
                onUpdate(next)
            }

            colorPaletteButtons(selectedHex: style.colorHex) { hex in
                var next = style
                next.colorHex = hex
                onUpdate(next)
            }

            ColorPicker(
                isChinese ? "自定义颜色" : "Custom Color",
                selection: colorPickerHexBinding(style.colorHex) { hex in
                    var next = style
                    next.colorHex = hex
                    onUpdate(next)
                },
                supportsOpacity: false
            )
            .font(.caption)
            .foregroundStyle(.white.opacity(0.84))
        }
    }

    private func selectedNativeStyle(for element: PresentationNativeElement) -> PresentationTextStyleConfig? {
        if let override = stylingState.nativeTextOverrides[element] {
            return override
        }
        guard let preset = nativeElementTextPreset(for: element) else {
            return nil
        }
        return textTheme.style(for: preset)
    }

    private func nativeElementSupportsTextEditing(_ element: PresentationNativeElement) -> Bool {
        switch element {
        case .title, .subtitle, .levelChip, .mainContent, .toolkitContent:
            return true
        case .toolkitIcon, .mainCard, .activityCard:
            return false
        }
    }

    private func nativeDefaultText(for element: PresentationNativeElement) -> String {
        switch element {
        case .title:
            return slide.title
        case .subtitle:
            return slide.subtitle
        case .levelChip:
            return levelChipDisplayText(from: slide.subtitle)
        case .mainContent:
            if !slide.knowledgeItems.isEmpty {
                return slide.knowledgeItems.joined(separator: "\n")
            }
            if !slide.keyPoints.isEmpty {
                return slide.keyPoints.joined(separator: "\n")
            }
            return ""
        case .toolkitContent:
            return slide.toolkitItems.joined(separator: "\n")
        case .toolkitIcon, .mainCard, .activityCard:
            return ""
        }
    }

    private func nativeEffectiveText(for element: PresentationNativeElement) -> String {
        stylingState.nativeContentOverrides[element] ?? nativeDefaultText(for: element)
    }

    private func levelChipDisplayText(from subtitle: String) -> String {
        let normalized = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "" }
        let lower = normalized.lowercased()
        if lower.hasPrefix("level") {
            return normalized
        }

        var index = normalized.startIndex
        while index < normalized.endIndex, normalized[index].isNumber {
            index = normalized.index(after: index)
        }
        guard index > normalized.startIndex else { return normalized }
        let levelNumber = String(normalized[..<index])
        while index < normalized.endIndex {
            let c = normalized[index]
            if c == "." || c == "、" || c == ")" || c == "）" || c.isWhitespace {
                index = normalized.index(after: index)
            } else {
                break
            }
        }
        let remainder = index < normalized.endIndex
            ? String(normalized[index...]).trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        return remainder.isEmpty ? "Level\(levelNumber)" : "Level\(levelNumber). \(remainder)"
    }

    private func syncNativeTextDraft(for element: PresentationNativeElement?) {
        guard let element else {
            nativeTextDraftElement = nil
            nativeTextDraft = ""
            return
        }
        guard nativeElementSupportsTextEditing(element) else {
            nativeTextDraftElement = element
            nativeTextDraft = ""
            return
        }
        nativeTextDraftElement = element
        nativeTextDraft = nativeEffectiveText(for: element)
    }

    private func nativeTextDraftValue(for element: PresentationNativeElement) -> String {
        if nativeTextDraftElement == element {
            return nativeTextDraft
        }
        return nativeEffectiveText(for: element)
    }

    private func commitNativeTextDraft(for element: PresentationNativeElement) {
        guard nativeElementSupportsTextEditing(element) else { return }
        let draft = nativeTextDraft.replacingOccurrences(of: "\r\n", with: "\n")
        let defaultValue = nativeDefaultText(for: element).replacingOccurrences(of: "\r\n", with: "\n")
        if draft == defaultValue {
            onUpdateNativeContentOverride(element, nil)
        } else {
            onUpdateNativeContentOverride(element, draft)
        }
    }

    @ViewBuilder
    private func imagePanel(for selectedOverlay: PresentationSlideOverlay) -> some View {
        if selectedOverlay.isImage {
            VStack(alignment: .leading, spacing: 10) {
                Text(isChinese ? "图片圆角" : "Image Corner Radius")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))

                deferredVectorSlider(
                    title: isChinese ? "圆角" : "Corner",
                    value: selectedOverlay.imageCornerRadiusRatio,
                    range: 0...0.5,
                    step: 0.01
                ) { newValue in
                    onUpdateImageCornerRadius(selectedOverlay.id, newValue)
                }

                Text(
                    isChinese
                        ? "缩放/切图控制点已放到图片外层。图片默认无圆角，可在这里单独设置。"
                        : "Resize/crop handles are outside the image now. Image defaults to no corner radius."
                )
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.72))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
            )

            if selectedOverlay.vectorDocument == nil {
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        onConvertToSVG(selectedOverlay.id)
                    } label: {
                        Label(
                            isChinese ? "转换为 SVG" : "Convert to SVG",
                            systemImage: "wand.and.stars"
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedOverlay.isExtracting)

                    Text(
                        isChinese
                            ? "当前保持原始位图。点击上方按钮后，才会显示 SVG Filter Controls 与 Bitmap to SVG 参数。"
                            : "Image stays bitmap until converted. SVG controls appear only after conversion."
                    )
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.76))

                    if selectedOverlay.isExtracting {
                        HStack(spacing: 8) {
                            ProgressView()
                                .tint(.white)
                            Text(isChinese ? "处理中…" : "Processing…")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.82))
                        }
                    }

                    Text(
                        isChinese
                            ? "直接在画布中拖拽图片可移动，四角圆点可缩放，四边白色把手可直接裁切。"
                            : "Directly manipulate image on canvas: drag to move, corner dots to resize, edge handles to crop."
                    )
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.72))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
            } else {
                vectorizationPanel
                filterAndStylizationPanel(for: selectedOverlay)
                VStack(alignment: .leading, spacing: 10) {
                    Text(isChinese ? "SVG 颜色" : "SVG Colors")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))

                    HStack(spacing: 8) {
                        Text(isChinese ? "线条颜色" : "Stroke Color")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.76))
                        Spacer(minLength: 8)
                        ColorPicker(
                            "",
                            selection: colorPickerHexBinding(selectedOverlay.vectorStrokeColorHex) { hex in
                                onUpdateImageVectorStyle(
                                    selectedOverlay.id,
                                    hex,
                                    selectedOverlay.vectorBackgroundColorHex,
                                    selectedOverlay.vectorBackgroundVisible
                                )
                            }
                        )
                        .labelsHidden()
                        .frame(width: 30, height: 22)
                    }
                    colorPaletteButtons(selectedHex: selectedOverlay.vectorStrokeColorHex) { hex in
                        onUpdateImageVectorStyle(
                            selectedOverlay.id,
                            hex,
                            selectedOverlay.vectorBackgroundColorHex,
                            selectedOverlay.vectorBackgroundVisible
                        )
                    }

                    Toggle(isOn: Binding(
                        get: { selectedOverlay.vectorBackgroundVisible },
                        set: { newValue in
                            onUpdateImageVectorStyle(
                                selectedOverlay.id,
                                selectedOverlay.vectorStrokeColorHex,
                                selectedOverlay.vectorBackgroundColorHex,
                                newValue
                            )
                        }
                    )) {
                        Text(isChinese ? "显示背景色" : "Show Background")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .tint(.cyan)

                    if selectedOverlay.vectorBackgroundVisible {
                        HStack(spacing: 8) {
                            Text(isChinese ? "背景颜色" : "Background Color")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.76))
                            Spacer(minLength: 8)
                            ColorPicker(
                                "",
                                selection: colorPickerHexBinding(selectedOverlay.vectorBackgroundColorHex) { hex in
                                    onUpdateImageVectorStyle(
                                        selectedOverlay.id,
                                        selectedOverlay.vectorStrokeColorHex,
                                        hex,
                                        selectedOverlay.vectorBackgroundVisible
                                    )
                                }
                            )
                            .labelsHidden()
                            .frame(width: 30, height: 22)
                        }
                        colorPaletteButtons(selectedHex: selectedOverlay.vectorBackgroundColorHex) { hex in
                            onUpdateImageVectorStyle(
                                selectedOverlay.id,
                                selectedOverlay.vectorStrokeColorHex,
                                hex,
                                selectedOverlay.vectorBackgroundVisible
                            )
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                Button {
                    onApplyImageStyleToAll(selectedOverlay.id)
                } label: {
                    Label(
                        isChinese ? "应用到全部图片" : "Apply to All Images",
                        systemImage: "square.stack.3d.up.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                Text(
                    isChinese
                        ? "长按图片可提取主体（若提取成功，会回到位图状态，可再次转换 SVG）。画布中可直接拖拽/缩放/裁切。"
                        : "Long press image to extract subject. After extraction, convert to SVG again if needed. Crop/resize directly on canvas."
                )
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.72))
                .padding(.horizontal, 4)
                .padding(.top, 2)
            }
        }
    }

    @ViewBuilder
    private func cropPanel(for overlay: PresentationSlideOverlay) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isChinese ? "切图区域" : "Crop")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))

            vectorSlider(
                title: "X",
                value: cropOriginX,
                range: 0...0.95,
                step: 0.01
            ) { newValue in
                cropOriginX = newValue
                normalizeCropInputs()
            }

            vectorSlider(
                title: "Y",
                value: cropOriginY,
                range: 0...0.95,
                step: 0.01
            ) { newValue in
                cropOriginY = newValue
                normalizeCropInputs()
            }

            vectorSlider(
                title: isChinese ? "宽度" : "Width",
                value: cropWidth,
                range: 0.05...1,
                step: 0.01
            ) { newValue in
                cropWidth = newValue
                normalizeCropInputs()
            }

            vectorSlider(
                title: isChinese ? "高度" : "Height",
                value: cropHeight,
                range: 0.05...1,
                step: 0.01
            ) { newValue in
                cropHeight = newValue
                normalizeCropInputs()
            }

            HStack(spacing: 8) {
                Button {
                    onCropOverlay(overlay.id, currentCropRect(), nil)
                } label: {
                    Text(isChinese ? "应用切图" : "Apply Crop")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color.white)
                        )
                }
                .buttonStyle(.plain)
                .disabled(overlay.isExtracting)

                Button {
                    resetCropInputs()
                } label: {
                    Text(isChinese ? "重置参数" : "Reset Inputs")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.16))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    @ViewBuilder
    private func textOverlayPanel(for overlay: PresentationSlideOverlay) -> some View {
        let editing = overlay.textEditingState
        VStack(alignment: .leading, spacing: 10) {
            Text(isChinese ? "文本设置" : "Text")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))

            TextEditor(
                text: Binding(
                    get: { editing.content },
                    set: { newValue in
                        var next = editing
                        next.content = newValue
                        onUpdateTextOverlay(overlay.id, next)
                    }
                )
            )
            .scrollContentBackground(.hidden)
            .foregroundStyle(.white)
            .frame(minHeight: 88, maxHeight: 140)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PresentationTextStylePreset.allCases) { preset in
                        let isActive = editing.stylePreset == preset
                        Button {
                            let next = themedTextEditingState(editing, applying: preset)
                            onUpdateTextOverlay(overlay.id, next)
                        } label: {
                            Text(preset.label(isChinese: isChinese))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(isActive ? Color.black : Color.white.opacity(0.9))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(isActive ? Color.white : Color.white.opacity(0.14))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 8) {
                ForEach(PresentationTextAlignment.allCases) { alignment in
                    let isActive = editing.alignment == alignment
                    Button {
                        var next = editing
                        next.alignment = alignment
                        onUpdateTextOverlay(overlay.id, next)
                    } label: {
                        Image(systemName: alignment.symbolName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isActive ? Color.black : Color.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(isActive ? Color.white : Color.white.opacity(0.14))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            vectorSlider(
                title: isChinese ? "宽度" : "Width",
                value: Double(editing.normalizedWidth),
                range: 0.2...0.92,
                step: 0.01
            ) { newValue in
                var next = editing
                next.normalizedWidth = CGFloat(newValue)
                onUpdateTextOverlay(overlay.id, next)
            }

            vectorSlider(
                title: isChinese ? "高度" : "Height",
                value: Double(editing.normalizedHeight),
                range: 0.08...0.72,
                step: 0.01
            ) { newValue in
                var next = editing
                next.normalizedHeight = CGFloat(newValue)
                onUpdateTextOverlay(overlay.id, next)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    private func themedTextEditingState(
        _ editing: PresentationTextEditingState,
        applying preset: PresentationTextStylePreset
    ) -> PresentationTextEditingState {
        var next = editing
        let style = textTheme.style(for: preset)
        next.stylePreset = preset
        next.colorHex = style.colorHex
        next.weightValue = style.weightValue
        next.fontSize = max(14, min(96, style.sizeCqw * 13.66))
        return next
    }

    @ViewBuilder
    private func roundedRectOverlayPanel(for overlay: PresentationSlideOverlay) -> some View {
        let editing = overlay.roundedRectEditingState
        VStack(alignment: .leading, spacing: 10) {
            Text(isChinese ? "形状设置" : "Shape")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PresentationShapeStyle.allCases) { style in
                        let isActive = editing.shapeStyle == style
                        Button {
                            var next = editing
                            next.shapeStyle = style
                            onUpdateRoundedRectOverlay(overlay.id, next)
                        } label: {
                            Label(style.label(isChinese: isChinese), systemImage: style.symbolName)
                                .labelStyle(.titleAndIcon)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(isActive ? Color.black : Color.white.opacity(0.9))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(isActive ? Color.white : Color.white.opacity(0.14))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Text(isChinese ? "填充色" : "Fill")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.76))
            colorPaletteButtons(selectedHex: editing.fillColorHex) { hex in
                var next = editing
                next.fillColorHex = hex
                onUpdateRoundedRectOverlay(overlay.id, next)
            }

            Text(isChinese ? "边框色" : "Border")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.76))
            colorPaletteButtons(selectedHex: editing.borderColorHex) { hex in
                var next = editing
                next.borderColorHex = hex
                onUpdateRoundedRectOverlay(overlay.id, next)
            }

            vectorSlider(
                title: isChinese ? "边框宽度" : "Border Width",
                value: editing.borderWidth,
                range: 0...10,
                step: 0.1
            ) { newValue in
                var next = editing
                next.borderWidth = newValue
                onUpdateRoundedRectOverlay(overlay.id, next)
            }

            if editing.shapeStyle == .roundedRect {
                vectorSlider(
                    title: isChinese ? "圆角比例" : "Corner Ratio",
                    value: editing.cornerRadiusRatio,
                    range: 0...0.5,
                    step: 0.01
                ) { newValue in
                    var next = editing
                    next.cornerRadiusRatio = newValue
                    onUpdateRoundedRectOverlay(overlay.id, next)
                }
            }

            vectorSlider(
                title: isChinese ? "宽度" : "Width",
                value: Double(editing.normalizedWidth),
                range: 0.1...0.92,
                step: 0.01
            ) { newValue in
                var next = editing
                next.normalizedWidth = CGFloat(newValue)
                onUpdateRoundedRectOverlay(overlay.id, next)
            }

            vectorSlider(
                title: isChinese ? "高度" : "Height",
                value: Double(editing.normalizedHeight),
                range: 0.08...0.72,
                step: 0.01
            ) { newValue in
                var next = editing
                next.normalizedHeight = CGFloat(newValue)
                onUpdateRoundedRectOverlay(overlay.id, next)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    @ViewBuilder
    private func iconOverlayPanel(for overlay: PresentationSlideOverlay) -> some View {
        let editing = overlay.iconEditingState
        VStack(alignment: .leading, spacing: 10) {
            Text(isChinese ? "图标设置" : "Icon")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(presentationIconPalette, id: \.self) { symbol in
                        let isActive = editing.systemName == symbol
                        Button {
                            var next = editing
                            next.systemName = symbol
                            onUpdateIconOverlay(overlay.id, next)
                        } label: {
                            Image(systemName: symbol)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(isActive ? Color.black : Color.white.opacity(0.92))
                                .frame(width: 32, height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(isActive ? Color.white : Color.white.opacity(0.14))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            TextField(
                isChinese ? "系统图标名 (SF Symbol)" : "SF Symbol name",
                text: Binding(
                    get: { editing.systemName },
                    set: { newValue in
                        var next = editing
                        next.systemName = newValue
                        onUpdateIconOverlay(overlay.id, next)
                    }
                )
            )
            .textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .foregroundStyle(.white)

            Text(isChinese ? "图标颜色" : "Icon Color")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.76))
            colorPaletteButtons(selectedHex: editing.colorHex) { hex in
                var next = editing
                next.colorHex = hex
                onUpdateIconOverlay(overlay.id, next)
            }

            Toggle(isOn: Binding(
                get: { editing.hasBackground },
                set: { newValue in
                    var next = editing
                    next.hasBackground = newValue
                    onUpdateIconOverlay(overlay.id, next)
                }
            )) {
                Text(isChinese ? "显示背景底" : "Show Background")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.9))
            }
            .tint(.cyan)

            if editing.hasBackground {
                Text(isChinese ? "背景色" : "Background")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.76))
                colorPaletteButtons(selectedHex: editing.backgroundColorHex) { hex in
                    var next = editing
                    next.backgroundColorHex = hex
                    onUpdateIconOverlay(overlay.id, next)
                }
            }

            vectorSlider(
                title: isChinese ? "图标大小" : "Icon Size",
                value: Double(editing.normalizedWidth),
                range: 0.08...0.42,
                step: 0.01
            ) { newValue in
                var next = editing
                next.normalizedWidth = CGFloat(newValue)
                onUpdateIconOverlay(overlay.id, next)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    @ViewBuilder
    private var textPanel: some View {
        let selectedStyle = textTheme.style(for: selectedPageTextPreset)
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PresentationTextStylePreset.allCases) { preset in
                        let isActive = selectedPageTextPreset == preset
                        Button {
                            selectedPageTextPreset = preset
                        } label: {
                            Text(preset.label(isChinese: isChinese))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(isActive ? Color.black : Color.white.opacity(0.9))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(isActive ? Color.white : Color.white.opacity(0.14))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }

            vectorSlider(
                title: isChinese ? "字号（cqw）" : "Size (cqw)",
                value: selectedStyle.sizeCqw,
                range: sizeRange(for: selectedPageTextPreset),
                step: 0.02
            ) { newValue in
                updateTextThemeStyle { style in
                    style.sizeCqw = newValue
                }
            }

            vectorSlider(
                title: isChinese ? "字重" : "Weight",
                value: selectedStyle.weightValue,
                range: 0...1,
                step: 0.01
            ) { newValue in
                updateTextThemeStyle { style in
                    style.weightValue = newValue
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], spacing: 8) {
                ForEach(textColorPalette, id: \.self) { hex in
                    let isActive = selectedStyle.colorHex.uppercased() == hex.uppercased()
                    Button {
                        updateTextThemeStyle { style in
                            style.colorHex = hex
                        }
                    } label: {
                        Circle()
                            .fill(Color(hex: hex))
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(isActive ? 1 : 0.35), lineWidth: isActive ? 2.2 : 1)
                            )
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    private func updateTextThemeStyle(_ update: (inout PresentationTextStyleConfig) -> Void) {
        updateTextThemeStyle(for: selectedPageTextPreset, update)
    }

    private func updateTextThemeStyle(
        for preset: PresentationTextStylePreset,
        _ update: (inout PresentationTextStyleConfig) -> Void
    ) {
        var nextTheme = textTheme
        var style = nextTheme.style(for: preset)
        update(&style)
        nextTheme.setStyle(style, for: preset)
        onUpdateTextTheme(nextTheme)
    }

    private func sizeRange(for preset: PresentationTextStylePreset) -> ClosedRange<Double> {
        switch preset {
        case .h1:
            return 2.2...6.4
        case .h2:
            return 1.0...3.0
        case .h3:
            return 0.9...2.6
        case .h4:
            return 0.8...2.2
        case .paragraph:
            return 0.8...2.4
        }
    }

    @ViewBuilder
    private var pagePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isChinese ? "模版" : "Template")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.88))

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(PresentationThemeTemplate.allCases) { template in
                    let isActive = pageStyle.templateID == template.rawValue
                    let previewStyle = template.pageStyle
                    let previewText = template.textTheme
                    Button {
                        onApplyTemplate(template)
                    } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            templatePreviewCard(
                                pageStyle: previewStyle,
                                textTheme: previewText
                            )
                            .frame(height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.white.opacity(isActive ? 0.95 : 0.35), lineWidth: isActive ? 1.6 : 1)
                            )

                            Text(template.label(isChinese: isChinese))
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .foregroundStyle(isActive ? Color.black : Color.white)
                            Text(template.subtitle(isChinese: isChinese))
                                .font(.caption2)
                                .lineLimit(1)
                                .foregroundStyle(isActive ? Color.black.opacity(0.72) : Color.white.opacity(0.72))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(isActive ? Color.white : Color.white.opacity(0.14))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(isChinese ? "页面比例" : "Page Ratio")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.88))

            HStack(spacing: 8) {
                ForEach(PresentationAspectPreset.allCases) { preset in
                    let isActive = pageStyle.aspectPreset == preset
                    Button {
                        var style = pageStyle
                        style.aspectPreset = preset
                        onUpdatePageStyle(style)
                    } label: {
                        Text(preset.label(isChinese: isChinese))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(isActive ? Color.black : Color.white.opacity(0.88))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(isActive ? Color.white : Color.white.opacity(0.14))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(isChinese ? "全局文本样式" : "Global Text Theme")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.88))

            textPanel

            Button {
                onClearNativeTextOverrides()
            } label: {
                Label(
                    isChinese ? "统一所有文本到全局样式" : "Unify All Text to Global Theme",
                    systemImage: "arrow.triangle.2.circlepath"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.95))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.14))
                )
            }
            .buttonStyle(.plain)
            .disabled(stylingState.nativeTextOverrides.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    @ViewBuilder
    private func templatePreviewCard(
        pageStyle: PresentationPageStyle,
        textTheme: PresentationTextTheme
    ) -> some View {
        let titleColor = Color(hex: textTheme.h1.colorHex)
        let paragraphColor = Color(hex: textTheme.paragraph.colorHex)
        let leftWeight = pageStyle.layoutPreset.columnRatio.0
        let rightWeight = pageStyle.layoutPreset.columnRatio.1
        let rightRatio = max(0.2, min(0.6, rightWeight / max(0.01, leftWeight + rightWeight)))

        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(hex: pageStyle.backgroundColorHex))

            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(hex: pageStyle.cardBackgroundColorHex))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color(hex: pageStyle.cardBorderColorHex), lineWidth: 1)
                    )
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 4) {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(titleColor.opacity(0.88))
                                .frame(width: 48, height: 4)
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(paragraphColor.opacity(0.72))
                                .frame(width: 58, height: 3)
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(paragraphColor.opacity(0.72))
                                .frame(width: 42, height: 3)
                        }
                        .padding(6)
                    }
                    .frame(maxWidth: .infinity)

                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(hex: pageStyle.cardBackgroundColorHex))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color(hex: pageStyle.cardBorderColorHex), lineWidth: 1)
                    )
                    .frame(width: 14 + rightRatio * 72)
            }
            .padding(6)

            if pageStyle.layoutPreset == .structured {
                VStack {
                    Spacer(minLength: 0)
                    Rectangle()
                        .fill(Color(hex: textTheme.h2.colorHex).opacity(0.22))
                        .frame(height: 5)
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
            }

            if pageStyle.layoutPreset == .showcase {
                Circle()
                    .fill(Color(hex: pageStyle.toolkitBadgeBackgroundHex).opacity(0.55))
                    .frame(width: 16, height: 16)
                    .offset(x: -27, y: 16)
            }

            HStack {
                Spacer()
                Circle()
                    .fill(Color(hex: pageStyle.toolkitBadgeBackgroundHex))
                    .overlay(
                        Circle()
                            .stroke(Color(hex: pageStyle.toolkitBadgeBorderHex), lineWidth: 1)
                    )
                    .frame(width: 11, height: 11)
            }
            .padding(7)
        }
    }

    @ViewBuilder
    private func stylizationPanel(
        for overlay: PresentationSlideOverlay,
        includeBackground: Bool = true
    ) -> some View {
        let panelContent = VStack(alignment: .leading, spacing: 12) {
            Text(isChinese ? "SVG 滤镜参数" : "SVG Filter Controls")
                .font(.headline)
                .foregroundStyle(.white)

            switch overlay.selectedFilter {
            case .original:
                Text(isChinese ? "选择一个滤镜后可调节参数。" : "Pick a filter to start tuning parameters.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))

            case .flowField:
                stylizationSlider(
                    title: isChinese ? "流动位移" : "Displacement",
                    value: overlay.stylization.flowDisplacement,
                    range: 0.2...18.0,
                    step: 0.1,
                    overlay: overlay
                ) { params, newValue in
                    params.flowDisplacement = newValue
                }
                stylizationSlider(
                    title: isChinese ? "噪声层级" : "Octaves",
                    value: overlay.stylization.flowOctaves,
                    range: 1...8,
                    step: 1,
                    overlay: overlay
                ) { params, newValue in
                    params.flowOctaves = newValue
                }

            case .crayonBrush:
                stylizationSlider(
                    title: isChinese ? "毛躁度" : "Roughness",
                    value: overlay.stylization.crayonRoughness,
                    range: 0.2...14.0,
                    step: 0.1,
                    overlay: overlay
                ) { params, newValue in
                    params.crayonRoughness = newValue
                }
                stylizationSlider(
                    title: isChinese ? "蜡质感" : "Wax",
                    value: overlay.stylization.crayonWax,
                    range: 0.05...1.6,
                    step: 0.01,
                    overlay: overlay
                ) { params, newValue in
                    params.crayonWax = newValue
                }
                stylizationSlider(
                    title: isChinese ? "排线密度" : "Hatch Density",
                    value: overlay.stylization.crayonHatchDensity,
                    range: 0.05...1.5,
                    step: 0.01,
                    overlay: overlay
                ) { params, newValue in
                    params.crayonHatchDensity = newValue
                }

            case .pixelPainter:
                stylizationSlider(
                    title: isChinese ? "点尺寸" : "Dot Size",
                    value: overlay.stylization.pixelDotSize,
                    range: 1...52,
                    step: 0.2,
                    overlay: overlay
                ) { params, newValue in
                    params.pixelDotSize = newValue
                }
                stylizationSlider(
                    title: isChinese ? "密度" : "Density",
                    value: overlay.stylization.pixelDensity,
                    range: 0.05...1.6,
                    step: 0.01,
                    overlay: overlay
                ) { params, newValue in
                    params.pixelDensity = newValue
                }
                stylizationSlider(
                    title: isChinese ? "抖动" : "Jitter",
                    value: overlay.stylization.pixelJitter,
                    range: 0...2.2,
                    step: 0.01,
                    overlay: overlay
                ) { params, newValue in
                    params.pixelJitter = newValue
                }

            case .equationField:
                stylizationSlider(
                    title: "n",
                    value: overlay.stylization.equationN,
                    range: 0.1...28,
                    step: 0.1,
                    overlay: overlay
                ) { params, newValue in
                    params.equationN = newValue
                }
                stylizationSlider(
                    title: "Theta",
                    value: overlay.stylization.equationTheta,
                    range: 0.2...24,
                    step: 0.1,
                    overlay: overlay
                ) { params, newValue in
                    params.equationTheta = newValue
                }
                stylizationSlider(
                    title: isChinese ? "缩放" : "Scale",
                    value: overlay.stylization.equationScale,
                    range: 0.15...4.0,
                    step: 0.05,
                    overlay: overlay
                ) { params, newValue in
                    params.equationScale = newValue
                }
                stylizationSlider(
                    title: isChinese ? "对比度" : "Contrast",
                    value: overlay.stylization.equationContrast,
                    range: 0.2...5.0,
                    step: 0.05,
                    overlay: overlay
                ) { params, newValue in
                    params.equationContrast = newValue
                }
            }
        }

        if includeBackground {
            panelContent
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
        } else {
            panelContent
        }
    }

    @ViewBuilder
    private func filterAndStylizationPanel(for overlay: PresentationSlideOverlay) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            filterStrip(for: overlay, includeBackground: false)
            stylizationPanel(for: overlay, includeBackground: false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    @ViewBuilder
    private func stylizationSlider(
        title: String,
        value: Double,
        range: ClosedRange<Double>,
        step: Double,
        overlay: PresentationSlideOverlay,
        onChangeParameters: @escaping (inout SVGStylizationParameters, Double) -> Void
    ) -> some View {
        deferredVectorSlider(title: title, value: value, range: range, step: step) { newValue in
            var params = overlay.stylization
            onChangeParameters(&params, newValue)
            onUpdateStylization(overlay.id, params)
        }
    }

    private var vectorizationPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isChinese ? "位图转 SVG 参数" : "Bitmap to SVG")
                .font(.headline)
                .foregroundStyle(.white)

            deferredVectorSlider(
                title: isChinese ? "边缘强度" : "Edge Intensity",
                value: stylingState.vectorization.edgeIntensity,
                range: 0.2...18.0,
                step: 0.1
            ) { newValue in
                var settings = stylingState.vectorization
                settings.edgeIntensity = newValue
                onUpdateVectorization(settings)
            }

            deferredVectorSlider(
                title: isChinese ? "阈值" : "Threshold",
                value: stylingState.vectorization.threshold,
                range: 1...254,
                step: 1
            ) { newValue in
                var settings = stylingState.vectorization
                settings.threshold = newValue
                onUpdateVectorization(settings)
            }

            deferredVectorSlider(
                title: isChinese ? "最小线段长度" : "Min Run Length",
                value: stylingState.vectorization.minRunLength,
                range: 1...24,
                step: 1
            ) { newValue in
                var settings = stylingState.vectorization
                settings.minRunLength = newValue
                onUpdateVectorization(settings)
            }

            deferredVectorSlider(
                title: isChinese ? "线宽" : "Stroke Width",
                value: stylingState.vectorization.strokeWidth,
                range: 0.2...8.0,
                step: 0.1
            ) { newValue in
                var settings = stylingState.vectorization
                settings.strokeWidth = newValue
                onUpdateVectorization(settings)
            }

            Text(isChinese ? "滑条松手后应用，并重建 SVG。" : "Changes apply when you release the slider, then SVG rebuilds.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.68))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    @ViewBuilder
    private func vectorSlider(
        title: String,
        value: Double,
        range: ClosedRange<Double>,
        step: Double,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.88))
                Spacer(minLength: 8)
                Text(formattedVectorValue(value, step: step))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.72))
            }
            Slider(
                value: Binding(
                    get: { value },
                    set: { onChange($0) }
                ),
                in: range,
                step: step
            )
            .tint(.cyan)
        }
    }

    @ViewBuilder
    private func deferredVectorSlider(
        title: String,
        value: Double,
        range: ClosedRange<Double>,
        step: Double,
        onCommit: @escaping (Double) -> Void
    ) -> some View {
        DeferredCommitVectorSlider(
            title: title,
            value: value,
            range: range,
            step: step,
            onCommit: onCommit
        )
    }

    private func formattedVectorValue(_ value: Double, step: Double) -> String {
        if step >= 1 {
            return "\(Int(value.rounded()))"
        }
        if step >= 0.1 {
            return String(format: "%.1f", value)
        }
        if step >= 0.01 {
            return String(format: "%.2f", value)
        }
        return String(format: "%.3f", value)
    }

    private func resetCropInputs() {
        cropOriginX = 0
        cropOriginY = 0
        cropWidth = 1
        cropHeight = 1
    }

    private func normalizeCropInputs() {
        cropOriginX = clampDouble(cropOriginX, min: 0, max: 0.95)
        cropOriginY = clampDouble(cropOriginY, min: 0, max: 0.95)
        cropWidth = clampDouble(cropWidth, min: 0.05, max: 1 - cropOriginX)
        cropHeight = clampDouble(cropHeight, min: 0.05, max: 1 - cropOriginY)
    }

    private func currentCropRect() -> CGRect {
        normalizeCropInputs()
        return CGRect(
            x: cropOriginX,
            y: cropOriginY,
            width: cropWidth,
            height: cropHeight
        )
    }

    private func clampDouble(_ value: Double, min: Double, max: Double) -> Double {
        Swift.max(min, Swift.min(max, value))
    }

    private var textColorPalette: [String] {
        [
            "#000000",
            "#1C1C1E",
            "#8E8E93",
            "#FFFFFF",
            "#007AFF",
            "#5856D6",
            "#AF52DE",
            "#FF2D55",
            "#FF3B30",
            "#FF9500",
            "#FFCC00",
            "#34C759",
            "#30D158",
            "#5AC8FA"
        ]
    }

    private var presentationIconPalette: [String] {
        [
            "wrench.adjustable",
            "book.fill",
            "lightbulb.fill",
            "star.fill",
            "graduationcap.fill",
            "person.2.fill",
            "sparkles",
            "paperplane.fill"
        ]
    }

    private func nativeElementLabel(_ element: PresentationNativeElement) -> String {
        switch element {
        case .title:
            return isChinese ? "标题（H1）" : "Title (H1)"
        case .subtitle:
            return isChinese ? "副标题（H3）" : "Subtitle (H3)"
        case .levelChip:
            return isChinese ? "层级标签（H4）" : "Level Chip (H4)"
        case .toolkitIcon:
            return isChinese ? "工具图标" : "Toolkit Icon"
        case .mainContent:
            return isChinese ? "主内容正文（P）" : "Main Content (P)"
        case .toolkitContent:
            return isChinese ? "Toolkit 内容（P）" : "Toolkit Content (P)"
        case .mainCard:
            return isChinese ? "主内容卡片" : "Main Content Card"
        case .activityCard:
            return isChinese ? "活动卡片" : "Activity Card"
        }
    }

    private func nativeElementTextPreset(for element: PresentationNativeElement) -> PresentationTextStylePreset? {
        switch element {
        case .title:
            return .h1
        case .subtitle:
            return .h3
        case .levelChip:
            return .h4
        case .mainContent, .toolkitContent:
            return .paragraph
        case .toolkitIcon, .mainCard, .activityCard:
            return nil
        }
    }

    @ViewBuilder
    private func colorPaletteButtons(
        selectedHex: String,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 28), spacing: 8)], spacing: 8) {
            ForEach(textColorPalette, id: \.self) { hex in
                let isActive = selectedHex.uppercased() == hex.uppercased()
                Button {
                    onSelect(hex)
                } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(isActive ? 1 : 0.35), lineWidth: isActive ? 2.2 : 1)
                        )
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func colorPickerHexBinding(
        _ currentHex: String,
        onChange: @escaping (String) -> Void
    ) -> Binding<Color> {
        Binding(
            get: {
                Color(hex: currentHex)
            },
            set: { newColor in
                #if canImport(UIKit)
                onChange(newColor.hexString)
                #else
                _ = newColor
                #endif
            }
        )
    }

    private func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.max(min, Swift.min(max, value))
    }
}
