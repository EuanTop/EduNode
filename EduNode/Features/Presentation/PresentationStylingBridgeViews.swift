import SwiftUI
import GNodeKit
#if canImport(UIKit)
import UIKit
#endif
#if canImport(CoreImage)
import CoreImage
#endif
#if canImport(Vision)
import Vision
#endif
#if canImport(VisionKit)
import VisionKit
#endif
#if canImport(WebKit)
import WebKit
#endif

struct DeferredCommitVectorSlider: View {
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    let onCommit: (Double) -> Void

    @State private var draftValue: Double
    @State private var isEditing = false

    init(
        title: String,
        value: Double,
        range: ClosedRange<Double>,
        step: Double,
        onCommit: @escaping (Double) -> Void
    ) {
        self.title = title
        self.value = value
        self.range = range
        self.step = step
        self.onCommit = onCommit
        _draftValue = State(initialValue: value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.88))
                Spacer(minLength: 8)
                Text(formattedValue(draftValue))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.72))
            }
            Slider(
                value: $draftValue,
                in: range,
                step: step,
                onEditingChanged: { editing in
                    if editing {
                        isEditing = true
                        draftValue = value
                    } else {
                        isEditing = false
                        let committed = max(range.lowerBound, min(range.upperBound, draftValue))
                        draftValue = committed
                        onCommit(committed)
                    }
                }
            )
            .tint(.cyan)
        }
        .onChange(of: value) { _, newValue in
            if !isEditing {
                draftValue = max(range.lowerBound, min(range.upperBound, newValue))
            }
        }
    }

    private func formattedValue(_ current: Double) -> String {
        if step >= 1 {
            return "\(Int(current.rounded()))"
        }
        if step >= 0.1 {
            return String(format: "%.1f", current)
        }
        if step >= 0.01 {
            return String(format: "%.2f", current)
        }
        return String(format: "%.3f", current)
    }
}

#if canImport(UIKit) && canImport(WebKit)
struct PresentationSlideCanvasHTMLView: UIViewRepresentable {
    let baseHTML: String
    let textTheme: PresentationTextTheme
    let overlays: [PresentationSlideOverlay]
    let selectedOverlayID: UUID?
    let onLoadStateChange: (Bool) -> Void
    let onSelectOverlay: (UUID?) -> Void
    let onCanvasTap: (CGPoint, PresentationNativeElement?) -> Void
    let onCommitOverlayFrame: (UUID, CGPoint, CGFloat, CGFloat) -> Void
    let onRotateOverlay: (UUID, Double) -> Void
    let onCropOverlay: (UUID, CGRect, String?) -> Void
    let onDeleteOverlay: (UUID) -> Void
    let onExtractOverlaySubject: (UUID) -> Void
    let onMoveNativeElement: (PresentationNativeElement, PresentationNativeLayoutOverride?) -> Void
    let onNativeRectsUpdate: ([PresentationNativeElement: CGRect]) -> Void

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: PresentationSlideCanvasHTMLView
        var pendingPayloadBase64 = ""
        var pendingSelectedID = ""
        var pendingBaseHTMLBase64 = ""
        var lastAppliedBaseHTMLBase64 = ""
        var isPageReady = false

        init(parent: PresentationSlideCanvasHTMLView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isPageReady = true
            pushPendingStateIfReady(webView)
            DispatchQueue.main.async {
                self.parent.onLoadStateChange(true)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            isPageReady = true
            DispatchQueue.main.async {
                self.parent.onLoadStateChange(true)
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            isPageReady = true
            DispatchQueue.main.async {
                self.parent.onLoadStateChange(true)
            }
        }

        func pushPendingStateIfReady(_ webView: WKWebView) {
            guard isPageReady else { return }
            let script = "window.__edunodeUpdate && window.__edunodeUpdate('\(pendingPayloadBase64)','\(pendingSelectedID)','\(pendingBaseHTMLBase64)');"
            webView.evaluateJavaScript(script, completionHandler: nil)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "edunodeCanvas" else { return }
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String else { return }

            DispatchQueue.main.async {
                switch type {
                case "select":
                    if let idString = body["id"] as? String,
                       let id = UUID(uuidString: idString) {
                        self.parent.onSelectOverlay(id)
                    } else {
                        self.parent.onSelectOverlay(nil)
                    }
                case "clear":
                    self.parent.onSelectOverlay(nil)
                case "canvasTap":
                    guard let x = body["x"] as? Double,
                          let y = body["y"] as? Double else { return }
                    let nativeElement: PresentationNativeElement?
                    if let nativeID = body["nativeID"] as? String,
                       !nativeID.isEmpty {
                        nativeElement = PresentationNativeElement(rawValue: nativeID)
                    } else {
                        nativeElement = nil
                    }
                    self.parent.onCanvasTap(CGPoint(x: x, y: y), nativeElement)
                case "frame":
                    guard let idString = body["id"] as? String,
                          let id = UUID(uuidString: idString),
                          let centerX = body["centerX"] as? Double,
                          let centerY = body["centerY"] as? Double,
                          let width = body["width"] as? Double,
                          let height = body["height"] as? Double else {
                        return
                    }
                    self.parent.onCommitOverlayFrame(
                        id,
                        CGPoint(x: centerX, y: centerY),
                        CGFloat(width),
                        CGFloat(height)
                    )
                case "rotate":
                    guard let idString = body["id"] as? String,
                          let id = UUID(uuidString: idString),
                          let delta = body["delta"] as? Double else { return }
                    self.parent.onRotateOverlay(id, delta)
                case "crop":
                    guard let idString = body["id"] as? String,
                          let id = UUID(uuidString: idString),
                          let x = body["x"] as? Double,
                          let y = body["y"] as? Double,
                          let width = body["width"] as? Double,
                          let height = body["height"] as? Double else { return }
                    let handle = body["handle"] as? String
                    self.parent.onCropOverlay(
                        id,
                        CGRect(x: x, y: y, width: width, height: height),
                        handle
                    )
                case "nativeRects":
                    guard let items = body["items"] as? [[String: Any]] else { return }
                    var rects: [PresentationNativeElement: CGRect] = [:]
                    for item in items {
                        guard let id = item["id"] as? String,
                              let element = PresentationNativeElement(rawValue: id),
                              let x = item["x"] as? Double,
                              let y = item["y"] as? Double,
                              let width = item["width"] as? Double,
                              let height = item["height"] as? Double else {
                            continue
                        }
                        rects[element] = CGRect(x: x, y: y, width: width, height: height)
                    }
                    self.parent.onNativeRectsUpdate(rects)
                case "baseLoaded":
                    self.parent.onLoadStateChange(true)
                case "delete":
                    guard let idString = body["id"] as? String,
                          let id = UUID(uuidString: idString) else { return }
                    self.parent.onDeleteOverlay(id)
                case "extract":
                    guard let idString = body["id"] as? String,
                          let id = UUID(uuidString: idString) else { return }
                    self.parent.onExtractOverlaySubject(id)
                case "nativeMove":
                    guard let rawID = body["id"] as? String,
                          let element = PresentationNativeElement(rawValue: rawID) else { return }
                    let offsetX = (body["offsetX"] as? Double) ?? 0
                    let offsetY = (body["offsetY"] as? Double) ?? 0
                    let next = PresentationNativeLayoutOverride(offsetX: offsetX, offsetY: offsetY).clamped()
                    self.parent.onMoveNativeElement(element, next.isZero ? nil : next)
                default:
                    break
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.preferredContentMode = .mobile
        configuration.userContentController.add(context.coordinator, name: "edunodeCanvas")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.isUserInteractionEnabled = true
        let payloadBase64 = overlayPayloadBase64()
        let selectedID = selectedOverlayID?.uuidString ?? ""
        let baseHTMLBase64 = Data(baseHTML.utf8).base64EncodedString()
        context.coordinator.pendingPayloadBase64 = payloadBase64
        context.coordinator.pendingSelectedID = selectedID
        context.coordinator.pendingBaseHTMLBase64 = baseHTMLBase64
        context.coordinator.lastAppliedBaseHTMLBase64 = baseHTMLBase64
        context.coordinator.isPageReady = false
        onLoadStateChange(false)
        let html = editorHTML(payloadBase64: payloadBase64, selectedID: selectedID, baseHTMLBase64: baseHTMLBase64)
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.parent = self
        let payloadBase64 = overlayPayloadBase64()
        let selectedID = selectedOverlayID?.uuidString ?? ""
        let baseHTMLBase64 = Data(baseHTML.utf8).base64EncodedString()
        context.coordinator.pendingPayloadBase64 = payloadBase64
        context.coordinator.pendingSelectedID = selectedID
        if context.coordinator.lastAppliedBaseHTMLBase64 != baseHTMLBase64 {
            context.coordinator.lastAppliedBaseHTMLBase64 = baseHTMLBase64
            onLoadStateChange(false)
        }
        context.coordinator.pendingBaseHTMLBase64 = baseHTMLBase64

        context.coordinator.pushPendingStateIfReady(uiView)
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "edunodeCanvas")
        uiView.navigationDelegate = nil
    }

    private struct OverlayPayload: Codable {
        var id: String
        var kind: String
        var centerX: Double
        var centerY: Double
        var width: Double
        var height: Double
        var aspect: Double
        var rotation: Double
        var text: String
        var textColor: String
        var textAlign: String
        var textSize: Double
        var textSizeCqw: Double
        var textWeight: Double
        var rectFill: String
        var rectBorder: String
        var rectBorderWidth: Double
        var rectCorner: Double
        var rectShape: String
        var iconGlyph: String
        var iconColor: String
        var iconHasBackground: Bool
        var iconBackground: String
        var imageCornerRadius: Double
        var imageDataURI: String
        var imageFilter: String
        var pixelated: Bool
        var svgMarkup: String
        var vectorBackgroundVisible: Bool
        var vectorBackgroundColor: String
    }

    private func overlayPayloadBase64() -> String {
        let payloads = overlays.map { overlay in
            let themedText = textTheme.style(for: overlay.textStylePreset)
            let themedTextSize = max(14, min(96, themedText.sizeCqw * 13.66))
            return OverlayPayload(
                id: overlay.id.uuidString,
                kind: overlay.kind.rawValue,
                centerX: Double(max(0.04, min(0.96, overlay.center.x))),
                centerY: Double(max(0.08, min(0.92, overlay.center.y))),
                width: Double(max(0.08, min(0.96, overlay.normalizedWidth))),
                height: Double(max(0.08, min(0.96, overlay.normalizedHeight))),
                aspect: Double(max(0.15, overlay.aspectRatio)),
                rotation: overlay.rotationDegrees,
                text: overlay.textContent,
                textColor: themedText.colorHex,
                textAlign: overlay.textAlignment.rawValue,
                textSize: themedTextSize,
                textSizeCqw: themedText.sizeCqw,
                textWeight: themedText.weightValue,
                rectFill: overlay.shapeFillColorHex,
                rectBorder: overlay.shapeBorderColorHex,
                rectBorderWidth: overlay.shapeBorderWidth,
                rectCorner: overlay.shapeCornerRadiusRatio,
                rectShape: overlay.shapeStyle.rawValue,
                iconGlyph: htmlIconGlyph(systemName: overlay.iconSystemName),
                iconColor: overlay.iconColorHex,
                iconHasBackground: overlay.iconHasBackground,
                iconBackground: overlay.iconBackgroundColorHex,
                imageCornerRadius: overlay.imageCornerRadiusRatio,
                imageDataURI: presentationImageDataURI(overlay.displayImageData),
                imageFilter: presentationImageCSSFilter(style: overlay.selectedFilter, params: overlay.stylization),
                pixelated: overlay.selectedFilter == .pixelPainter,
                svgMarkup: overlay.renderedSVGString ?? "",
                vectorBackgroundVisible: overlay.vectorBackgroundVisible,
                vectorBackgroundColor: overlay.vectorBackgroundColorHex
            )
        }
        let payloadData = (try? JSONEncoder().encode(payloads)) ?? Data("[]".utf8)
        return payloadData.base64EncodedString()
    }

    private func editorHTML(payloadBase64: String, selectedID: String, baseHTMLBase64: String) -> String {
        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            html, body {
              margin: 0;
              padding: 0;
              width: 100%;
              height: 100%;
              overflow: hidden;
              background: transparent;
            }
            #root {
              width: 100%;
              height: 100%;
              position: relative;
              overflow: hidden;
              border-radius: 0;
              background: transparent;
            }
            #baseFrame {
              position: absolute;
              inset: 0;
              width: 100%;
              height: 100%;
              border: 0;
              pointer-events: none;
              background: transparent;
            }
            #overlayLayer {
              position: absolute;
              inset: 0;
              z-index: 4;
            }
            .ov {
              position: absolute;
              transform: translate(-50%, -50%);
              display: flex;
              align-items: center;
              justify-content: center;
              user-select: none;
              touch-action: none;
              overflow: visible;
              border-radius: 10px;
              border: 0;
              box-shadow: none;
              will-change: left, top, width, height, transform;
            }
            .ov.selected {
              box-shadow:
                0 0 0 2px #22d3ee,
                0 0 0 4px rgba(34, 211, 238, 0.25);
            }
            .ov .control-handle {
              position: absolute;
              z-index: 6;
              user-select: none;
              -webkit-user-select: none;
              touch-action: none;
            }
            .ov .control-handle::before {
              content: '';
              position: absolute;
              inset: -12px;
            }
            .ov .control-handle.resize {
              width: 18px;
              height: 18px;
              border-radius: 999px;
              background: #22d3ee;
              border: 1.3px solid rgba(255,255,255,0.92);
              box-shadow: 0 0 0 1px rgba(0,0,0,0.18);
            }
            .ov .control-handle[data-handle='resize-nw'] {
              left: -9px;
              top: -9px;
              cursor: nwse-resize;
            }
            .ov .control-handle[data-handle='resize-ne'] {
              right: -9px;
              top: -9px;
              cursor: nesw-resize;
            }
            .ov .control-handle[data-handle='resize-sw'] {
              left: -9px;
              bottom: -9px;
              cursor: nesw-resize;
            }
            .ov .control-handle[data-handle='resize-se'] {
              right: -9px;
              bottom: -9px;
              cursor: nwse-resize;
            }
            .ov .control-handle.rotate {
              left: 50%;
              top: -36px;
              transform: translateX(-50%);
              width: 22px;
              height: 22px;
              border-radius: 999px;
              background: #111827;
              border: 2px solid rgba(255,255,255,0.92);
              box-shadow: 0 2px 8px rgba(0,0,0,0.3);
              cursor: grab;
            }
            .ov .control-handle.rotate:active {
              cursor: grabbing;
            }
            .ov .control-handle.delete {
              right: 10px;
              top: -14px;
              width: 20px;
              height: 20px;
              border-radius: 999px;
              background: rgba(17,24,39,0.9);
              color: rgba(255,255,255,0.96);
              border: 1.6px solid rgba(255,255,255,0.9);
              box-shadow: 0 2px 7px rgba(0,0,0,0.28);
              display: flex;
              align-items: center;
              justify-content: center;
              font-size: 12px;
              font-weight: 700;
              line-height: 1;
              cursor: pointer;
            }
            .ov .control-handle.crop {
              background: rgba(255,255,255,0.98);
              border: 1px solid rgba(17,24,39,0.55);
              box-shadow: 0 1px 4px rgba(0,0,0,0.24);
            }
            .ov .control-handle[data-handle='crop-left'],
            .ov .control-handle[data-handle='crop-right'] {
              width: 18px;
              height: 44px;
              border-radius: 999px;
              cursor: ew-resize;
              top: 50%;
              transform: translateY(-50%);
            }
            .ov .control-handle[data-handle='crop-left'] { left: -12px; }
            .ov .control-handle[data-handle='crop-right'] { right: -12px; }
            .ov .control-handle[data-handle='crop-top'],
            .ov .control-handle[data-handle='crop-bottom'] {
              width: 44px;
              height: 18px;
              border-radius: 999px;
              cursor: ns-resize;
              left: 50%;
              transform: translateX(-50%);
            }
            .ov .control-handle[data-handle='crop-top'] { top: -12px; }
            .ov .control-handle[data-handle='crop-bottom'] { bottom: -12px; }
            .ov .crop-guide {
              position: absolute;
              border: 1.4px dashed rgba(255,255,255,0.96);
              background: rgba(34, 211, 238, 0.12);
              border-radius: 6px;
              pointer-events: none;
              display: none;
              z-index: 5;
            }
            .ov.text {
              padding: 6px 8px;
              white-space: pre-wrap;
              word-break: break-word;
              border: 0;
              background: transparent;
              overflow: visible;
            }
            .ov.text.selected {
              border: 2px dashed rgba(34, 211, 238, 0.95);
              border-radius: 8px;
              background: rgba(34, 211, 238, 0.08);
              box-shadow: none;
            }
            .ov.rect {
              border-style: solid;
            }
            .ov.rect.selected {
              border: 2.6px solid #22d3ee !important;
              box-shadow:
                0 0 0 2px rgba(8, 145, 178, 0.38),
                0 0 18px rgba(34, 211, 238, 0.28);
            }
            .ov.icon {
              border-radius: 999px;
              font-size: 1.9cqw;
              line-height: 1;
            }
            .ov.image {
              border-radius: 0;
              overflow: visible;
            }
            .ov.image .image-media {
              position: absolute;
              inset: 0;
              overflow: hidden;
            }
            .ov.image img {
              width: 100%;
              height: 100%;
              object-fit: contain;
              display: block;
            }
            .ov.image.pixelated img {
              image-rendering: pixelated;
            }
            .ov.image.vectorized .svg-bg,
            .ov.image.vectorized .svg-host,
            .ov.image.vectorized .svg-ink {
              width: 100%;
              height: 100%;
            }
            .ov.image.vectorized .svg-bg,
            .ov.image.vectorized .svg-ink {
              position: absolute;
              inset: 0;
            }
            .ov.image.vectorized svg {
              width: 100%;
              height: 100%;
              display: block;
            }
          </style>
        </head>
        <body>
          <div id="root">
            <iframe id="baseFrame"></iframe>
            <div id="overlayLayer"></div>
          </div>
          <script>
            (function () {
              function b64ToUtf8(base64) {
                const bytes = atob(base64);
                const arr = [];
                for (let i = 0; i < bytes.length; i++) {
                  arr.push('%' + ('00' + bytes.charCodeAt(i).toString(16)).slice(-2));
                }
                return decodeURIComponent(arr.join(''));
              }
              const baseFrame = document.getElementById('baseFrame');
              var currentBaseHTMLBase64 = '\(baseHTMLBase64)';
              baseFrame.srcdoc = b64ToUtf8(currentBaseHTMLBase64);

              let overlays = JSON.parse(b64ToUtf8('\(payloadBase64)'));
              let selectedID = '\(selectedID)';
              const layer = document.getElementById('overlayLayer');
              let nativeRects = [];
              let nativeOffsetMap = {};

              const clamp = (v, min, max) => Math.max(min, Math.min(max, v));
              const post = (payload) => {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.edunodeCanvas) {
                  window.webkit.messageHandlers.edunodeCanvas.postMessage(payload);
                }
              };
              const find = (id) => overlays.find(o => o.id === id);
              const stageRect = () => layer.getBoundingClientRect();
              const dragRuntime = {
                active: false,
                pendingPayloadBase64: null,
                pendingSelectedID: null,
                pendingBaseHTMLBase64: null
              };
              const pointInRect = (x, y, rect, padding = 0) => (
                x >= rect.x - padding &&
                x <= rect.x + rect.width + padding &&
                y >= rect.y - padding &&
                y <= rect.y + rect.height + padding
              );

              function imageContentRect(ov, ovEl) {
                const frame = ovEl.getBoundingClientRect();
                const width = Math.max(1, frame.width);
                const height = Math.max(1, frame.height);
                const aspect = Math.max(0.15, Number(ov.aspect) || 1.0);
                const frameAspect = width / Math.max(1, height);

                if (aspect >= frameAspect) {
                  const contentHeight = width / aspect;
                  return {
                    x: 0,
                    y: (height - contentHeight) * 0.5,
                    width,
                    height: contentHeight
                  };
                }

                const contentWidth = height * aspect;
                return {
                  x: (width - contentWidth) * 0.5,
                  y: 0,
                  width: contentWidth,
                  height
                };
              }

              function pointerHitsImageContent(event, ov, ovEl, tolerance = 20) {
                const frame = ovEl.getBoundingClientRect();
                const localX = event.clientX - frame.left;
                const localY = event.clientY - frame.top;
                const content = imageContentRect(ov, ovEl);
                return pointInRect(localX, localY, content, tolerance);
              }

              function rectUnion(rects) {
                if (!rects.length) { return null; }
                let minX = Number.POSITIVE_INFINITY;
                let minY = Number.POSITIVE_INFINITY;
                let maxX = Number.NEGATIVE_INFINITY;
                let maxY = Number.NEGATIVE_INFINITY;
                for (const rect of rects) {
                  if (!rect || rect.width <= 0 || rect.height <= 0) { continue; }
                  minX = Math.min(minX, rect.left);
                  minY = Math.min(minY, rect.top);
                  maxX = Math.max(maxX, rect.right);
                  maxY = Math.max(maxY, rect.bottom);
                }
                if (!Number.isFinite(minX) || !Number.isFinite(minY) || !Number.isFinite(maxX) || !Number.isFinite(maxY)) {
                  return null;
                }
                return {
                  left: minX,
                  top: minY,
                  width: Math.max(0, maxX - minX),
                  height: Math.max(0, maxY - minY)
                };
              }

              function normalizedRectFromDOMRect(domRect) {
                const stage = stageRect();
                if (!domRect || stage.width <= 0 || stage.height <= 0) { return null; }
                const x = clamp((domRect.left - stage.left) / stage.width, 0, 1);
                const y = clamp((domRect.top - stage.top) / stage.height, 0, 1);
                const maxW = 1 - x;
                const maxH = 1 - y;
                const width = clamp(domRect.width / stage.width, 0, maxW);
                const height = clamp(domRect.height / stage.height, 0, maxH);
                if (width <= 0.001 || height <= 0.001) { return null; }
                return { x, y, width, height };
              }

              function nativeSelectorMap() {
                return {
                  title: ['.hero h1'],
                  subtitle: ['.hero .lead'],
                  levelChip: ['.hero .level-chip'],
                  toolkitIcon: ['.hero .toolkit-icon'],
                  mainCard: ['.main-layout .main-card'],
                  activityCard: ['.main-layout .activity-card'],
                  mainContent: [
                    '.main-card .knowledge-line',
                    '.main-card .activity-line',
                    '.main-card .activity-ordered',
                    '.main-card .empty'
                  ],
                  toolkitContent: [
                    '.activity-card .activity-line',
                    '.activity-card .activity-ordered',
                    '.activity-card .empty'
                  ]
                };
              }

              function nativeLayoutSelectorMap() {
                return {
                  title: ['.hero h1'],
                  subtitle: ['.hero .lead'],
                  levelChip: ['.hero .level-chip'],
                  toolkitIcon: ['.hero .toolkit-icon'],
                  mainCard: ['.main-layout .main-card'],
                  activityCard: ['.main-layout .activity-card'],
                  mainContent: ['.main-card .knowledge-content', '.main-card .activity-content', '.main-card .empty'],
                  toolkitContent: ['.activity-card .activity-content', '.activity-card .empty']
                };
              }

              function loadNativeOffsetsFromFrame() {
                const frameWindow = baseFrame.contentWindow;
                const value = frameWindow ? frameWindow.__edunodeNativeOffsets : null;
                if (!value || typeof value !== 'object') {
                  Object.keys(nativeOffsetMap).forEach((key) => delete nativeOffsetMap[key]);
                  return;
                }
                const firstSlideKey = Object.keys(value)[0];
                const scoped = firstSlideKey ? value[firstSlideKey] : {};
                Object.keys(nativeOffsetMap).forEach((key) => delete nativeOffsetMap[key]);
                if (scoped && typeof scoped === 'object') {
                  Object.keys(scoped).forEach((key) => {
                    nativeOffsetMap[key] = scoped[key];
                  });
                }
              }

              function applySingleNativeOffsetInFrame(nativeID, offset) {
                const doc = baseFrame.contentDocument;
                if (!doc) { return; }
                const selectors = nativeLayoutSelectorMap()[nativeID] || [];
                if (!selectors.length) { return; }
                const stage = stageRect();
                const tx = (Number(offset && offset.offsetX) || 0) * Math.max(1, stage.width);
                const ty = (Number(offset && offset.offsetY) || 0) * Math.max(1, stage.height);
                selectors.forEach((selector) => {
                  doc.querySelectorAll(selector).forEach((node) => {
                    const key = 'edunodeNativeBaseTransform';
                    if (node.dataset[key] === undefined) {
                      node.dataset[key] = node.style.transform || '';
                    }
                    const base = node.dataset[key] || '';
                    node.style.transform = (base ? (base + ' ') : '') + 'translate(' + tx + 'px, ' + ty + 'px)';
                    node.style.willChange = 'transform';
                  });
                });
              }

              function applyAllNativeOffsetsInFrame() {
                Object.keys(nativeOffsetMap).forEach((key) => {
                  applySingleNativeOffsetInFrame(key, nativeOffsetMap[key]);
                });
              }

              function collectNativeRects() {
                const doc = baseFrame.contentDocument;
                if (!doc) {
                  nativeRects = [];
                  post({ type: 'nativeRects', items: [] });
                  return;
                }
                const selectors = nativeSelectorMap();
                const items = [];
                Object.keys(selectors).forEach((id) => {
                  const rects = [];
                  selectors[id].forEach((selector) => {
                    doc.querySelectorAll(selector).forEach((node) => {
                      const rect = node.getBoundingClientRect();
                      if (rect.width > 0 && rect.height > 0) {
                        rects.push(rect);
                      }
                    });
                  });
                  const union = rectUnion(rects);
                  const normalized = normalizedRectFromDOMRect(union);
                  if (normalized) {
                    items.push({
                      id,
                      x: normalized.x,
                      y: normalized.y,
                      width: normalized.width,
                      height: normalized.height
                    });
                  }
                });
                nativeRects = items;
                post({ type: 'nativeRects', items });
              }

              function scheduleNativeRectCollection() {
                window.requestAnimationFrame(() => {
                  collectNativeRects();
                });
              }

              function hitNativeElementID(nx, ny) {
                if (!nativeRects.length) { return null; }
                const sorted = nativeRects
                  .slice()
                  .sort((a, b) => (a.width * a.height) - (b.width * b.height));
                for (const item of sorted) {
                  if (pointInRect(nx, ny, item, 0)) {
                    return item.id || null;
                  }
                }
                return null;
              }

              function updateBaseHTMLIfNeeded(nextBaseHTMLBase64) {
                if (!nextBaseHTMLBase64 || nextBaseHTMLBase64 === currentBaseHTMLBase64) { return; }
                currentBaseHTMLBase64 = nextBaseHTMLBase64;
                baseFrame.srcdoc = b64ToUtf8(nextBaseHTMLBase64);
              }

              function applyImageCornerRadius(ov, ovEl) {
                const media = ovEl.querySelector('.image-media');
                if (!media) { return; }
                const rect = ovEl.getBoundingClientRect();
                const minDim = Math.max(1, Math.min(rect.width, rect.height));
                const ratio = clamp(Number(ov.imageCornerRadius || 0), 0, 0.5);
                media.style.borderRadius = (minDim * ratio) + 'px';
              }

              function alignToStyle(el, ov) {
                el.style.left = (ov.centerX * 100) + '%';
                el.style.top = (ov.centerY * 100) + '%';
                el.style.width = (ov.width * 100) + '%';
                el.style.height = (ov.height * 100) + '%';
                el.style.transform = 'translate(-50%, -50%) rotate(' + (ov.rotation || 0) + 'deg)';
              }

              function textWeight(v) {
                if (v < 0.15) return '200';
                if (v < 0.3) return '300';
                if (v < 0.45) return '400';
                if (v < 0.62) return '500';
                if (v < 0.78) return '600';
                if (v < 0.9) return '700';
                return '800';
              }

              function applyRectShapeStyle(el, ov) {
                const shape = ov.rectShape || 'roundedRect';
                const rect = el.getBoundingClientRect();
                const width = Math.max(1, rect.width);
                const height = Math.max(1, rect.height);
                const minDim = Math.max(1, Math.min(width, height));
                const ratio = clamp(Number(ov.rectCorner) || 0.18, 0, 0.5);
                const cornerPx = clamp(minDim * ratio, 0, minDim * 0.5);

                if (shape === 'rectangle') {
                  el.style.borderRadius = '0px';
                } else if (shape === 'capsule') {
                  el.style.borderRadius = (minDim * 0.5) + 'px';
                } else if (shape === 'ellipse') {
                  el.style.borderRadius = '50%';
                } else {
                  el.style.borderRadius = cornerPx + 'px';
                }
              }

              function appendHandle(el, handleType, classes) {
                const handle = document.createElement('div');
                handle.className = 'control-handle ' + classes;
                handle.dataset.handle = handleType;
                if (handleType === 'delete') {
                  handle.textContent = '×';
                }
                el.appendChild(handle);
              }

              function resizeDirection(handleType) {
                switch (handleType) {
                  case 'resize-nw': return { x: -1, y: -1 };
                  case 'resize-ne': return { x: 1, y: -1 };
                  case 'resize-sw': return { x: -1, y: 1 };
                  default: return { x: 1, y: 1 };
                }
              }

              function normalizeAngle(degrees) {
                let value = degrees;
                while (value > 180) { value -= 360; }
                while (value < -180) { value += 360; }
                return value;
              }

              function overlayCenterAngle(clientX, clientY, ovEl) {
                const frame = ovEl.getBoundingClientRect();
                const cx = frame.left + frame.width * 0.5;
                const cy = frame.top + frame.height * 0.5;
                return Math.atan2(clientY - cy, clientX - cx) * 180 / Math.PI;
              }

              function cropRectForHandle(handleType, dx, dy) {
                const maxCut = 0.82;
                const maxExpand = 0.82;
                const minSize = 0.18;
                const rect = { x: 0, y: 0, width: 1, height: 1 };
                switch (handleType) {
                  case 'crop-left': {
                    const cut = clamp(dx, -maxExpand, maxCut);
                    rect.x = cut;
                    rect.width = Math.max(minSize, 1 - cut);
                    break;
                  }
                  case 'crop-right': {
                    const cut = clamp(-dx, -maxExpand, maxCut);
                    rect.width = Math.max(minSize, 1 - cut);
                    break;
                  }
                  case 'crop-top': {
                    const cut = clamp(dy, -maxExpand, maxCut);
                    rect.y = cut;
                    rect.height = Math.max(minSize, 1 - cut);
                    break;
                  }
                  case 'crop-bottom': {
                    const cut = clamp(-dy, -maxExpand, maxCut);
                    rect.height = Math.max(minSize, 1 - cut);
                    break;
                  }
                  default:
                    return null;
                }
                if (rect.width < minSize || rect.height < minSize) {
                  return null;
                }
                return rect;
              }

              function updateCropGuide(ovEl, ov, cropRect) {
                const guide = ovEl.querySelector('.crop-guide');
                if (!guide) { return; }
                if (!cropRect) {
                  guide.style.display = 'none';
                  return;
                }
                const content = imageContentRect(ov, ovEl);
                guide.style.display = 'block';
                guide.style.left = (content.x + cropRect.x * content.width) + 'px';
                guide.style.top = (content.y + cropRect.y * content.height) + 'px';
                guide.style.width = (cropRect.width * content.width) + 'px';
                guide.style.height = (cropRect.height * content.height) + 'px';
              }

              function render() {
                layer.innerHTML = '';
                overlays.forEach(ov => {
                  const el = document.createElement('div');
                  el.className = 'ov ' + ov.kind + (ov.id === selectedID ? ' selected' : '');
                  el.dataset.id = ov.id;
                  alignToStyle(el, ov);

                  if (ov.kind === 'text') {
                    el.classList.add('text');
                    el.style.color = ov.textColor || '#111111';
                    const textSizeCqw = Number(ov.textSizeCqw || 0);
                    if (Number.isFinite(textSizeCqw) && textSizeCqw > 0) {
                      el.style.fontSize = clamp(textSizeCqw, 0.6, 9.8) + 'cqw';
                    } else {
                      el.style.fontSize = Math.max(12, Math.min(96, ov.textSize)) + 'px';
                    }
                    el.style.fontWeight = textWeight(ov.textWeight);
                    el.style.textAlign = ov.textAlign === 'center' ? 'center' : (ov.textAlign === 'trailing' ? 'right' : 'left');
                    el.textContent = ov.text || 'Text';
                  } else if (ov.kind === 'roundedRect') {
                    el.classList.add('rect');
                    el.style.background = ov.rectFill || '#FFFFFF';
                    el.style.borderColor = ov.rectBorder || '#D6DDE8';
                    el.style.borderWidth = Math.max(0.2, ov.rectBorderWidth) + 'px';
                  } else if (ov.kind === 'icon') {
                    el.classList.add('icon');
                    el.style.color = ov.iconColor || '#111111';
                    el.style.background = ov.iconHasBackground ? (ov.iconBackground || '#FFFFFF') : 'transparent';
                    el.textContent = ov.iconGlyph || '✦';
                  } else {
                    el.classList.add('image');
                    const mediaHost = document.createElement('div');
                    mediaHost.className = 'image-media';
                    if (ov.svgMarkup && ov.svgMarkup.trim().length > 0) {
                      el.classList.add('vectorized');
                      const svgBG = document.createElement('div');
                      svgBG.className = 'svg-bg';
                      svgBG.style.background = ov.vectorBackgroundVisible
                        ? (ov.vectorBackgroundColor || '#FFFFFF')
                        : 'transparent';

                      const svgInk = document.createElement('div');
                      svgInk.className = 'svg-ink';
                      svgInk.style.filter = ov.imageFilter || 'none';

                      const svgHost = document.createElement('div');
                      svgHost.className = 'svg-host';
                      svgHost.innerHTML = ov.svgMarkup;
                      svgInk.appendChild(svgHost);
                      mediaHost.appendChild(svgBG);
                      mediaHost.appendChild(svgInk);
                    } else {
                      if (ov.pixelated) {
                        el.classList.add('pixelated');
                      }
                      const img = document.createElement('img');
                      img.src = ov.imageDataURI || '';
                      img.alt = 'Overlay Image';
                      img.style.filter = ov.imageFilter || 'none';
                      mediaHost.appendChild(img);
                    }
                    el.appendChild(mediaHost);
                  }

                  if (ov.id === selectedID) {
                    appendHandle(el, 'delete', 'delete');
                    appendHandle(el, 'resize-nw', 'resize');
                    appendHandle(el, 'resize-ne', 'resize');
                    appendHandle(el, 'resize-sw', 'resize');
                    appendHandle(el, 'resize-se', 'resize');

                    if (ov.kind === 'image') {
                      appendHandle(el, 'rotate', 'rotate');
                      appendHandle(el, 'crop-left', 'crop');
                      appendHandle(el, 'crop-right', 'crop');
                      appendHandle(el, 'crop-top', 'crop');
                      appendHandle(el, 'crop-bottom', 'crop');
                      const cropGuide = document.createElement('div');
                      cropGuide.className = 'crop-guide';
                      el.appendChild(cropGuide);
                    }
                  }

                  layer.appendChild(el);
                  if (ov.kind === 'roundedRect') {
                    applyRectShapeStyle(el, ov);
                  } else if (ov.kind === 'image') {
                    applyImageCornerRadius(ov, el);
                  }
                });
                scheduleNativeRectCollection();
              }

              function select(id, notify = true) {
                const nextID = id || '';
                const changed = nextID !== selectedID;
                selectedID = nextID;
                if (changed) {
                  render();
                }
                if (notify) {
                  if (selectedID) {
                    post({ type: 'select', id: selectedID });
                  } else {
                    post({ type: 'clear' });
                  }
                }
              }

              function beginNativeInteraction(event, nativeID, nx, ny) {
                if (!nativeID) {
                  post({ type: 'canvasTap', x: nx, y: ny, nativeID: '' });
                  return;
                }
                dragRuntime.active = true;
                dragRuntime.pendingPayloadBase64 = null;
                dragRuntime.pendingSelectedID = null;
                dragRuntime.pendingBaseHTMLBase64 = null;
                post({ type: 'canvasTap', x: nx, y: ny, nativeID: nativeID });
                const rect = stageRect();
                const startX = event.clientX;
                const startY = event.clientY;
                const current = nativeOffsetMap[nativeID] || { offsetX: 0, offsetY: 0 };
                const startOffsetX = Number(current.offsetX) || 0;
                const startOffsetY = Number(current.offsetY) || 0;
                let moved = false;
                let ended = false;
                let latestOffset = { offsetX: startOffsetX, offsetY: startOffsetY };

                function onMove(e) {
                  if (ended) { return; }
                  e.preventDefault();
                  const dx = (e.clientX - startX) / Math.max(1, rect.width);
                  const dy = (e.clientY - startY) / Math.max(1, rect.height);
                  const travel = Math.hypot(e.clientX - startX, e.clientY - startY);
                  if (travel > 2.5) {
                    moved = true;
                  }
                  latestOffset = {
                    offsetX: clamp(startOffsetX + dx, -0.7, 0.7),
                    offsetY: clamp(startOffsetY + dy, -0.7, 0.7)
                  };
                  nativeOffsetMap[nativeID] = latestOffset;
                  applySingleNativeOffsetInFrame(nativeID, latestOffset);
                  scheduleNativeRectCollection();
                }

                function onEnd() {
                  if (ended) { return; }
                  ended = true;
                  window.removeEventListener('pointermove', onMove);
                  window.removeEventListener('pointercancel', onEnd);
                  if (moved) {
                    post({
                      type: 'nativeMove',
                      id: nativeID,
                      offsetX: latestOffset.offsetX,
                      offsetY: latestOffset.offsetY
                    });
                  }
                  dragRuntime.active = false;
                  if (dragRuntime.pendingPayloadBase64 !== null) {
                    try {
                      overlays = JSON.parse(b64ToUtf8(dragRuntime.pendingPayloadBase64));
                    } catch (_) {
                      overlays = [];
                    }
                    selectedID = (dragRuntime.pendingSelectedID || '');
                    updateBaseHTMLIfNeeded(dragRuntime.pendingBaseHTMLBase64);
                    dragRuntime.pendingPayloadBase64 = null;
                    dragRuntime.pendingSelectedID = null;
                    dragRuntime.pendingBaseHTMLBase64 = null;
                  }
                  render();
                }

                window.addEventListener('pointermove', onMove);
                window.addEventListener('pointerup', onEnd, { once: true });
                window.addEventListener('pointercancel', onEnd, { once: true });
                event.preventDefault();
              }

              layer.addEventListener('pointerdown', (event) => {
                const ovEl = event.target.closest('.ov');
                if (!ovEl) {
                  const rect = stageRect();
                  const nx = clamp((event.clientX - rect.left) / Math.max(1, rect.width), 0, 1);
                  const ny = clamp((event.clientY - rect.top) / Math.max(1, rect.height), 0, 1);
                  const nativeID = hitNativeElementID(nx, ny);
                  select('', false);
                  beginNativeInteraction(event, nativeID, nx, ny);
                  return;
                }
                const id = ovEl.dataset.id;
                const ov = find(id);
                if (!ov) return;
                const handleEl = event.target.closest('.control-handle');
                const handleType = handleEl ? (handleEl.dataset.handle || '') : '';
                const isResize = handleType.startsWith('resize-');
                const isRotate = handleType === 'rotate';
                const isCrop = handleType.startsWith('crop-');
                const isDelete = handleType === 'delete';

                if (isDelete) {
                  post({ type: 'delete', id: ov.id });
                  selectedID = '';
                  render();
                  event.preventDefault();
                  return;
                }

                if (ov.kind === 'image' && !isResize && !isRotate && !isCrop && !isDelete && !pointerHitsImageContent(event, ov, ovEl)) {
                  const rect = stageRect();
                  const nx = clamp((event.clientX - rect.left) / Math.max(1, rect.width), 0, 1);
                  const ny = clamp((event.clientY - rect.top) / Math.max(1, rect.height), 0, 1);
                  const nativeID = hitNativeElementID(nx, ny);
                  select('', false);
                  beginNativeInteraction(event, nativeID, nx, ny);
                  return;
                }

                select(id, false);
                const activeEl = layer.querySelector('.ov[data-id="' + id + '"]') || ovEl;
                if (event.pointerId !== undefined && activeEl.setPointerCapture) {
                  try { activeEl.setPointerCapture(event.pointerId); } catch (_) { }
                }
                const rect = stageRect();
                const startX = event.clientX;
                const startY = event.clientY;
                const startCenterX = ov.centerX;
                const startCenterY = ov.centerY;
                const startW = ov.width;
                const startH = ov.height;
                const stageRatio = rect.width / Math.max(1, rect.height);
                const startRotation = Number(ov.rotation || 0);
                const startPointerAngle = overlayCenterAngle(startX, startY, activeEl);
                let latestRotationDelta = 0;
                let latestCropRect = null;
                let moved = false;
                let longPressTriggered = false;
                let active = true;
                let longPressToken = null;
                const longPressEligible = ov.kind === 'image' && !isResize && !isRotate && !isCrop && !isDelete;
                const longPressDuration = 460;
                dragRuntime.active = true;
                dragRuntime.pendingPayloadBase64 = null;
                dragRuntime.pendingSelectedID = null;
                dragRuntime.pendingBaseHTMLBase64 = null;

                if (longPressEligible) {
                  longPressToken = window.setTimeout(() => {
                    if (!active || moved) { return; }
                    longPressTriggered = true;
                    post({ type: 'extract', id: ov.id });
                  }, longPressDuration);
                }

                function clearLongPress() {
                  if (longPressToken !== null) {
                    window.clearTimeout(longPressToken);
                    longPressToken = null;
                  }
                }

                function onMove(e) {
                  if (!active) { return; }
                  e.preventDefault();
                  const dx = (e.clientX - startX) / Math.max(1, rect.width);
                  const dy = (e.clientY - startY) / Math.max(1, rect.height);
                  if (!moved) {
                    const travel = Math.hypot(e.clientX - startX, e.clientY - startY);
                    if (travel > 4) {
                      moved = true;
                      clearLongPress();
                    }
                  }
                  if (longPressTriggered) { return; }
                  if (isResize) {
                    const direction = resizeDirection(handleType);
                    if (ov.kind === 'image' || ov.kind === 'icon') {
                      const projected = (dx * direction.x + dy * direction.y) * 0.5;
                      const targetW = clamp(startW + projected, ov.kind === 'icon' ? 0.08 : 0.08, ov.kind === 'icon' ? 0.42 : 0.92);
                      ov.width = targetW;
                      const targetH = clamp(targetW * stageRatio / Math.max(0.15, ov.aspect), 0.08, 0.92);
                      ov.height = targetH;
                    } else {
                      ov.width = clamp(startW + dx * direction.x, 0.1, 0.92);
                      ov.height = clamp(startH + dy * direction.y, 0.08, 0.72);
                    }
                  } else if (isRotate) {
                    const angle = overlayCenterAngle(e.clientX, e.clientY, activeEl);
                    latestRotationDelta = normalizeAngle(angle - startPointerAngle);
                    ov.rotation = startRotation + latestRotationDelta;
                  } else if (isCrop) {
                    const activeRect = activeEl.getBoundingClientRect();
                    const localDX = (e.clientX - startX) / Math.max(1, activeRect.width);
                    const localDY = (e.clientY - startY) / Math.max(1, activeRect.height);
                    latestCropRect = cropRectForHandle(handleType, localDX, localDY);
                    updateCropGuide(activeEl, ov, latestCropRect);
                  } else {
                    ov.centerX = clamp(startCenterX + dx, 0.04, 0.96);
                    ov.centerY = clamp(startCenterY + dy, 0.08, 0.92);
                  }
                  const liveEl = layer.querySelector('.ov[data-id="' + ov.id + '"]') || activeEl;
                  alignToStyle(liveEl, ov);
                  if (ov.kind === 'image') {
                    applyImageCornerRadius(ov, liveEl);
                  }
                }

                function onEnd() {
                  active = false;
                  clearLongPress();
                  window.removeEventListener('pointermove', onMove);
                  window.removeEventListener('pointercancel', onEnd);
                  if (event.pointerId !== undefined && activeEl.releasePointerCapture) {
                    try { activeEl.releasePointerCapture(event.pointerId); } catch (_) { }
                  }
                  const frameChanged = (!isResize && !isRotate && !isCrop && moved) || isResize;
                  if (!longPressTriggered && frameChanged) {
                    post({
                      type: 'frame',
                      id: ov.id,
                      centerX: ov.centerX,
                      centerY: ov.centerY,
                      width: ov.width,
                      height: ov.height
                    });
                  }
                  if (!longPressTriggered && isRotate && Math.abs(latestRotationDelta) > 0.1) {
                    post({
                      type: 'rotate',
                      id: ov.id,
                      delta: latestRotationDelta
                    });
                  }
                  if (!longPressTriggered && isCrop && latestCropRect) {
                    post({
                      type: 'crop',
                      id: ov.id,
                      x: latestCropRect.x,
                      y: latestCropRect.y,
                      width: latestCropRect.width,
                      height: latestCropRect.height,
                      handle: handleType
                    });
                  }
                  if (isCrop) {
                    updateCropGuide(activeEl, ov, null);
                  }
                  if (selectedID) {
                    post({ type: 'select', id: selectedID });
                  } else {
                    post({ type: 'clear' });
                  }
                  dragRuntime.active = false;
                  if (dragRuntime.pendingPayloadBase64 !== null) {
                    try {
                      overlays = JSON.parse(b64ToUtf8(dragRuntime.pendingPayloadBase64));
                    } catch (_) {
                      overlays = [];
                    }
                    selectedID = (dragRuntime.pendingSelectedID || '');
                    updateBaseHTMLIfNeeded(dragRuntime.pendingBaseHTMLBase64);
                    dragRuntime.pendingPayloadBase64 = null;
                    dragRuntime.pendingSelectedID = null;
                    dragRuntime.pendingBaseHTMLBase64 = null;
                  }
                  render();
                }

                window.addEventListener('pointermove', onMove);
                window.addEventListener('pointerup', onEnd, { once: true });
                window.addEventListener('pointercancel', onEnd, { once: true });
                event.preventDefault();
              });

              window.addEventListener('keydown', (event) => {
                if ((event.key === 'Backspace' || event.key === 'Delete') && selectedID) {
                  post({ type: 'delete', id: selectedID });
                  selectedID = '';
                  render();
                }
              });

              window.__edunodeUpdate = function (payloadBase64, nextSelectedID, nextBaseHTMLBase64) {
                if (dragRuntime.active) {
                  dragRuntime.pendingPayloadBase64 = payloadBase64;
                  dragRuntime.pendingSelectedID = (nextSelectedID || '');
                  dragRuntime.pendingBaseHTMLBase64 = (nextBaseHTMLBase64 || '');
                  return;
                }
                try {
                  overlays = JSON.parse(b64ToUtf8(payloadBase64));
                } catch (_) {
                  overlays = [];
                }
                selectedID = (nextSelectedID || '');
                updateBaseHTMLIfNeeded(nextBaseHTMLBase64 || '');
                render();
              };

              baseFrame.addEventListener('load', () => {
                loadNativeOffsetsFromFrame();
                applyAllNativeOffsetsInFrame();
                post({ type: 'baseLoaded' });
                scheduleNativeRectCollection();
              });
              window.addEventListener('resize', () => {
                scheduleNativeRectCollection();
              });

              render();
            })();
          </script>
        </body>
        </html>
        """
    }

    private func htmlIconGlyph(systemName: String) -> String {
        let key = systemName.lowercased()
        if key.contains("wrench") { return "🛠" }
        if key.contains("sparkles") { return "✦" }
        if key.contains("star") { return "★" }
        if key.contains("book") { return "📘" }
        if key.contains("bolt") { return "⚡︎" }
        if key.contains("camera") { return "📷" }
        if key.contains("lightbulb") { return "💡" }
        if key.contains("mic") { return "🎤" }
        return "✦"
    }
}

struct PresentationSVGOverlayView: UIViewRepresentable {
    let svg: String
    let cssFilter: String
    let backgroundColorHex: String
    let backgroundVisible: Bool

    final class Coordinator {
        var lastHTML = ""
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.isUserInteractionEnabled = false
        let html = wrapperHTML(
            svg: svg,
            cssFilter: cssFilter,
            backgroundColorHex: backgroundColorHex,
            backgroundVisible: backgroundVisible
        )
        context.coordinator.lastHTML = html
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        let html = wrapperHTML(
            svg: svg,
            cssFilter: cssFilter,
            backgroundColorHex: backgroundColorHex,
            backgroundVisible: backgroundVisible
        )
        guard context.coordinator.lastHTML != html else { return }
        context.coordinator.lastHTML = html
        uiView.loadHTMLString(html, baseURL: nil)
    }

    private func wrapperHTML(
        svg: String,
        cssFilter: String,
        backgroundColorHex: String,
        backgroundVisible: Bool
    ) -> String {
        let bg = backgroundVisible ? normalizedHex(backgroundColorHex, fallback: "#FFFFFF") : "transparent"
        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            html, body {
              margin: 0;
              padding: 0;
              width: 100%;
              height: 100%;
              overflow: hidden;
              background: transparent;
            }
            body {
              position: relative;
            }
            .svg-stage {
              position: absolute;
              inset: 0;
              overflow: hidden;
            }
            .svg-bg,
            .svg-ink {
              position: absolute;
              inset: 0;
            }
            .svg-bg {
              background: \(bg);
            }
            .svg-ink {
              filter: \(cssFilter);
            }
            .svg-wrap {
              width: 100%;
              height: 100%;
            }
            .svg-wrap > svg,
            svg {
              width: 100%;
              height: 100%;
            }
          </style>
        </head>
        <body>
          <div class="svg-stage">
            <div class="svg-bg"></div>
            <div class="svg-ink">
              <div class="svg-wrap">\(svg)</div>
            </div>
          </div>
        </body>
        </html>
        """
    }
}
#else
struct PresentationSlideCanvasHTMLView: View {
    let baseHTML: String
    let textTheme: PresentationTextTheme
    let overlays: [PresentationSlideOverlay]
    let selectedOverlayID: UUID?
    let onLoadStateChange: (Bool) -> Void
    let onSelectOverlay: (UUID?) -> Void
    let onCanvasTap: (CGPoint, PresentationNativeElement?) -> Void
    let onCommitOverlayFrame: (UUID, CGPoint, CGFloat, CGFloat) -> Void
    let onRotateOverlay: (UUID, Double) -> Void
    let onCropOverlay: (UUID, CGRect, String?) -> Void
    let onDeleteOverlay: (UUID) -> Void
    let onExtractOverlaySubject: (UUID) -> Void
    let onNativeRectsUpdate: ([PresentationNativeElement: CGRect]) -> Void

    var body: some View {
        Text(baseHTML)
            .font(.caption2.monospaced())
            .onAppear {
                onLoadStateChange(true)
            }
    }
}

struct PresentationSVGOverlayView: View {
    let svg: String
    let cssFilter: String
    let backgroundColorHex: String
    let backgroundVisible: Bool

    var body: some View {
        Text(svg)
            .font(.caption2.monospaced())
    }
}
#endif

#if canImport(UIKit) && canImport(CoreImage)
enum PresentationSubjectExtractor {
    nonisolated static func extractSubject(from image: UIImage) async -> UIImage? {
        #if canImport(VisionKit)
        if #available(iOS 17.0, *) {
            if let visionKitSubject = await extractSubjectWithVisionKit(from: image) {
                return cropToVisibleAlphaIfNeeded(visionKitSubject)
            }
        }
        #endif

        #if canImport(Vision)
        if let visionSubject = await Task.detached(priority: .userInitiated, operation: {
            extractSubjectSync(from: image)
        }).value {
            return cropToVisibleAlphaIfNeeded(visionSubject)
        }
        #endif

        return nil
    }

    #if canImport(VisionKit)
    @available(iOS 17.0, *)
    @MainActor
    private static func extractSubjectWithVisionKit(from image: UIImage) async -> UIImage? {
        guard ImageAnalyzer.isSupported else { return nil }

        let analyzer = ImageAnalyzer()
        let configuration = ImageAnalyzer.Configuration([.visualLookUp])
        guard let analysis = try? await analyzer.analyze(image, configuration: configuration) else {
            return nil
        }

        let interaction = ImageAnalysisInteraction()
        interaction.preferredInteractionTypes = [.imageSubject, .visualLookUp]
        interaction.analysis = analysis

        // Attach interaction to a host image view so subject APIs can resolve image context.
        let imageView = UIImageView(image: image)
        imageView.frame = CGRect(origin: .zero, size: image.size)
        imageView.isUserInteractionEnabled = true
        imageView.addInteraction(interaction)

        let center = CGPoint(x: image.size.width * 0.5, y: image.size.height * 0.5)
        if let centerSubject = await interaction.subject(at: center),
           let extracted = try? await centerSubject.image {
            return extracted
        }

        let subjects = await interaction.subjects
        if let dominant = subjects.max(by: { lhs, rhs in
            (lhs.bounds.width * lhs.bounds.height) < (rhs.bounds.width * rhs.bounds.height)
        }), let extracted = try? await dominant.image {
            return extracted
        }

        if !subjects.isEmpty,
           let combined = try? await interaction.image(for: subjects) {
            return combined
        }

        return nil
    }
    #endif

    #if canImport(Vision)
    nonisolated private static func extractSubjectSync(from image: UIImage) -> UIImage? {
        guard #available(iOS 17.0, *),
              let cgImage = image.cgImage else {
            return nil
        }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: image.cgImagePropertyOrientation
        )
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let observation = request.results?.first else {
            return nil
        }

        let instances = observation.allInstances
        guard let maskBuffer = try? observation.generateScaledMaskForImage(
            forInstances: instances,
            from: handler
        ) else {
            return nil
        }
        let original = CIImage(cgImage: cgImage)
        let cropRect = subjectBoundsFromMask(maskBuffer, imageSize: original.extent.size)
        let mask = CIImage(cvPixelBuffer: maskBuffer)
        let transparent = CIImage(color: .clear).cropped(to: original.extent)

        guard let blend = CIFilter(name: "CIBlendWithMask") else {
            return nil
        }
        blend.setValue(original, forKey: kCIInputImageKey)
        blend.setValue(transparent, forKey: kCIInputBackgroundImageKey)
        blend.setValue(mask, forKey: kCIInputMaskImageKey)

        guard let output = blend.outputImage else {
            return nil
        }

        let context = CIContext(options: nil)
        guard let outputCGImage = context.createCGImage(output, from: original.extent) else {
            return nil
        }
        if let cropRect,
           let croppedCGImage = outputCGImage.cropping(to: cropRect) {
            return UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)
        }
        return UIImage(cgImage: outputCGImage, scale: image.scale, orientation: image.imageOrientation)
    }
    #endif

    nonisolated private static func cropToVisibleAlphaIfNeeded(_ image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 1, height > 1 else { return image }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            return image
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * bytesPerRow) + (x * bytesPerPixel)
                let alpha = pixels[offset + 3]
                if alpha > 8 {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }

        guard maxX >= minX, maxY >= minY else { return image }
        let rect = CGRect(
            x: minX,
            y: minY,
            width: (maxX - minX + 1),
            height: (maxY - minY + 1)
        )
        guard let cropped = cgImage.cropping(to: rect) else { return image }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: .up)
    }

    #if canImport(Vision)
    nonisolated private static func subjectBoundsFromMask(_ maskBuffer: CVPixelBuffer, imageSize: CGSize) -> CGRect? {
        CVPixelBufferLockBaseAddress(maskBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(maskBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(maskBuffer) else { return nil }

        let width = CVPixelBufferGetWidth(maskBuffer)
        let height = CVPixelBufferGetHeight(maskBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(maskBuffer)
        guard width > 0, height > 0 else { return nil }

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1

        for y in 0..<height {
            let row = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                if row[x] > 8 {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }

        guard maxX >= minX, maxY >= minY else { return nil }

        let scaleX = imageSize.width / CGFloat(width)
        let scaleY = imageSize.height / CGFloat(height)
        return CGRect(
            x: CGFloat(minX) * scaleX,
            y: CGFloat(minY) * scaleY,
            width: CGFloat(maxX - minX + 1) * scaleX,
            height: CGFloat(maxY - minY + 1) * scaleY
        ).integral
    }
    #endif
}

private extension UIImage {
    nonisolated var cgImagePropertyOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
#endif
