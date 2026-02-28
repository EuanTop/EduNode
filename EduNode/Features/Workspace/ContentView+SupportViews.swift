import SwiftUI
import GNodeKit
#if canImport(WebKit)
import WebKit
#endif

#if canImport(UIKit) && canImport(WebKit)
struct PresentationSlideThumbnailHTMLView: UIViewRepresentable {
    let html: String
    let onLoaded: () -> Void

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: PresentationSlideThumbnailHTMLView
        var lastHTML = ""
        var hasReportedLoadForCurrentHTML = false

        init(parent: PresentationSlideThumbnailHTMLView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            reportLoadedIfNeeded()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            reportLoadedIfNeeded()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
            reportLoadedIfNeeded()
        }

        private func reportLoadedIfNeeded() {
            guard !hasReportedLoadForCurrentHTML else { return }
            hasReportedLoadForCurrentHTML = true
            DispatchQueue.main.async {
                self.parent.onLoaded()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.isUserInteractionEnabled = false
        context.coordinator.lastHTML = html
        context.coordinator.hasReportedLoadForCurrentHTML = false
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.parent = self
        guard context.coordinator.lastHTML != html else { return }
        context.coordinator.lastHTML = html
        context.coordinator.hasReportedLoadForCurrentHTML = false
        uiView.loadHTMLString(html, baseURL: nil)
    }
}
#else
struct PresentationSlideThumbnailHTMLView: View {
    let html: String
    let onLoaded: () -> Void

    var body: some View {
        Color.white.overlay(
            Text(html)
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.black)
                .lineLimit(8)
                .padding(8),
            alignment: .topLeading
        )
        .onAppear {
            onLoaded()
        }
    }
}
#endif

struct PresentationPersistedState: Codable {
    var version: Int = 1
    var breaks: [Int]
    var excludedNodeIDs: [UUID]
    var selectedGroupID: UUID?
    var selectedGroupSignature: String?
    var pageStyle: PresentationPageStyle
    var textTheme: PresentationTextTheme
    var updatedAt: Date?
    var groups: [PresentationPersistedGroupState]
}

struct PresentationPersistedGroupState: Codable {
    var groupID: UUID
    var groupSignature: String?
    var selectedOverlayID: UUID?
    var vectorization: PresentationVectorizationSettings
    var nativeTextOverrides: [String: PresentationTextStyleConfig]
    var nativeContentOverrides: [String: String]
    var nativeLayoutOverrides: [String: PresentationNativeLayoutOverride]
    var overlays: [PresentationPersistedOverlay]

    init(
        groupID: UUID,
        groupSignature: String?,
        selectedOverlayID: UUID?,
        vectorization: PresentationVectorizationSettings,
        nativeTextOverrides: [String: PresentationTextStyleConfig] = [:],
        nativeContentOverrides: [String: String] = [:],
        nativeLayoutOverrides: [String: PresentationNativeLayoutOverride] = [:],
        overlays: [PresentationPersistedOverlay]
    ) {
        self.groupID = groupID
        self.groupSignature = groupSignature
        self.selectedOverlayID = selectedOverlayID
        self.vectorization = vectorization
        self.nativeTextOverrides = nativeTextOverrides
        self.nativeContentOverrides = nativeContentOverrides
        self.nativeLayoutOverrides = nativeLayoutOverrides
        self.overlays = overlays
    }

    private enum CodingKeys: String, CodingKey {
        case groupID
        case groupSignature
        case selectedOverlayID
        case vectorization
        case nativeTextOverrides
        case nativeContentOverrides
        case nativeLayoutOverrides
        case overlays
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        groupID = try container.decode(UUID.self, forKey: .groupID)
        groupSignature = try? container.decode(String.self, forKey: .groupSignature)
        selectedOverlayID = try? container.decode(UUID.self, forKey: .selectedOverlayID)
        vectorization = (try? container.decode(PresentationVectorizationSettings.self, forKey: .vectorization)) ?? .default
        nativeTextOverrides = (try? container.decode([String: PresentationTextStyleConfig].self, forKey: .nativeTextOverrides)) ?? [:]
        nativeContentOverrides = (try? container.decode([String: String].self, forKey: .nativeContentOverrides)) ?? [:]
        nativeLayoutOverrides = (try? container.decode([String: PresentationNativeLayoutOverride].self, forKey: .nativeLayoutOverrides)) ?? [:]
        overlays = (try? container.decode([PresentationPersistedOverlay].self, forKey: .overlays)) ?? []
    }
}

struct PresentationPersistedOverlay: Codable {
    var id: UUID
    var kindRaw: String
    var imageData: Data
    var extractedImageData: Data?
    var cropSourceImageData: Data?
    var cropOriginX: Double
    var cropOriginY: Double
    var cropWidth: Double
    var cropHeight: Double
    var vectorDocument: PresentationPersistedSVGDocument?
    var selectedFilterRaw: String
    var stylization: PresentationPersistedStylization
    var centerX: Double
    var centerY: Double
    var normalizedWidth: Double
    var normalizedHeight: Double
    var aspectRatio: Double
    var rotationDegrees: Double
    var textContent: String
    var textStylePreset: PresentationTextStylePreset
    var textColorHex: String
    var textAlignment: PresentationTextAlignment
    var textFontSize: Double
    var textWeightValue: Double
    var shapeFillColorHex: String
    var shapeBorderColorHex: String
    var shapeBorderWidth: Double
    var shapeCornerRadiusRatio: Double
    var shapeStyleRaw: String
    var iconSystemName: String
    var iconColorHex: String
    var iconHasBackground: Bool
    var iconBackgroundColorHex: String
    var imageCornerRadiusRatio: Double
    var vectorStrokeColorHex: String
    var vectorBackgroundColorHex: String
    var vectorBackgroundVisible: Bool

    init(
        id: UUID,
        kindRaw: String,
        imageData: Data,
        extractedImageData: Data?,
        cropSourceImageData: Data?,
        cropOriginX: Double,
        cropOriginY: Double,
        cropWidth: Double,
        cropHeight: Double,
        vectorDocument: PresentationPersistedSVGDocument?,
        selectedFilterRaw: String,
        stylization: PresentationPersistedStylization,
        centerX: Double,
        centerY: Double,
        normalizedWidth: Double,
        normalizedHeight: Double,
        aspectRatio: Double,
        rotationDegrees: Double,
        textContent: String,
        textStylePreset: PresentationTextStylePreset,
        textColorHex: String,
        textAlignment: PresentationTextAlignment,
        textFontSize: Double,
        textWeightValue: Double,
        shapeFillColorHex: String,
        shapeBorderColorHex: String,
        shapeBorderWidth: Double,
        shapeCornerRadiusRatio: Double,
        shapeStyleRaw: String,
        iconSystemName: String,
        iconColorHex: String,
        iconHasBackground: Bool,
        iconBackgroundColorHex: String,
        imageCornerRadiusRatio: Double,
        vectorStrokeColorHex: String,
        vectorBackgroundColorHex: String,
        vectorBackgroundVisible: Bool
    ) {
        self.id = id
        self.kindRaw = kindRaw
        self.imageData = imageData
        self.extractedImageData = extractedImageData
        self.cropSourceImageData = cropSourceImageData
        self.cropOriginX = cropOriginX
        self.cropOriginY = cropOriginY
        self.cropWidth = cropWidth
        self.cropHeight = cropHeight
        self.vectorDocument = vectorDocument
        self.selectedFilterRaw = selectedFilterRaw
        self.stylization = stylization
        self.centerX = centerX
        self.centerY = centerY
        self.normalizedWidth = normalizedWidth
        self.normalizedHeight = normalizedHeight
        self.aspectRatio = aspectRatio
        self.rotationDegrees = rotationDegrees
        self.textContent = textContent
        self.textStylePreset = textStylePreset
        self.textColorHex = textColorHex
        self.textAlignment = textAlignment
        self.textFontSize = textFontSize
        self.textWeightValue = textWeightValue
        self.shapeFillColorHex = shapeFillColorHex
        self.shapeBorderColorHex = shapeBorderColorHex
        self.shapeBorderWidth = shapeBorderWidth
        self.shapeCornerRadiusRatio = shapeCornerRadiusRatio
        self.shapeStyleRaw = shapeStyleRaw
        self.iconSystemName = iconSystemName
        self.iconColorHex = iconColorHex
        self.iconHasBackground = iconHasBackground
        self.iconBackgroundColorHex = iconBackgroundColorHex
        self.imageCornerRadiusRatio = imageCornerRadiusRatio
        self.vectorStrokeColorHex = vectorStrokeColorHex
        self.vectorBackgroundColorHex = vectorBackgroundColorHex
        self.vectorBackgroundVisible = vectorBackgroundVisible
    }

    private enum CodingKeys: String, CodingKey {
        case id, kindRaw, imageData, extractedImageData, cropSourceImageData, cropOriginX, cropOriginY, cropWidth, cropHeight, vectorDocument, selectedFilterRaw, stylization
        case centerX, centerY, normalizedWidth, normalizedHeight, aspectRatio, rotationDegrees
        case textContent, textStylePreset, textColorHex, textAlignment, textFontSize, textWeightValue
        case shapeFillColorHex, shapeBorderColorHex, shapeBorderWidth, shapeCornerRadiusRatio, shapeStyleRaw
        case iconSystemName, iconColorHex, iconHasBackground, iconBackgroundColorHex
        case imageCornerRadiusRatio
        case vectorStrokeColorHex, vectorBackgroundColorHex, vectorBackgroundVisible
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kindRaw = try container.decode(String.self, forKey: .kindRaw)
        imageData = (try? container.decode(Data.self, forKey: .imageData)) ?? Data()
        extractedImageData = try? container.decode(Data.self, forKey: .extractedImageData)
        cropSourceImageData = try? container.decode(Data.self, forKey: .cropSourceImageData)
        cropOriginX = (try? container.decode(Double.self, forKey: .cropOriginX)) ?? 0
        cropOriginY = (try? container.decode(Double.self, forKey: .cropOriginY)) ?? 0
        cropWidth = (try? container.decode(Double.self, forKey: .cropWidth)) ?? 1
        cropHeight = (try? container.decode(Double.self, forKey: .cropHeight)) ?? 1
        vectorDocument = try? container.decode(PresentationPersistedSVGDocument.self, forKey: .vectorDocument)
        selectedFilterRaw = (try? container.decode(String.self, forKey: .selectedFilterRaw)) ?? SVGFilterStyle.original.rawValue
        stylization = (try? container.decode(PresentationPersistedStylization.self, forKey: .stylization))
            ?? PresentationPersistedStylization(from: .default)
        centerX = (try? container.decode(Double.self, forKey: .centerX)) ?? 0.5
        centerY = (try? container.decode(Double.self, forKey: .centerY)) ?? 0.58
        normalizedWidth = (try? container.decode(Double.self, forKey: .normalizedWidth)) ?? 0.28
        normalizedHeight = (try? container.decode(Double.self, forKey: .normalizedHeight)) ?? 0.2
        aspectRatio = (try? container.decode(Double.self, forKey: .aspectRatio)) ?? 1
        rotationDegrees = (try? container.decode(Double.self, forKey: .rotationDegrees)) ?? 0
        textContent = (try? container.decode(String.self, forKey: .textContent)) ?? ""
        textStylePreset = (try? container.decode(PresentationTextStylePreset.self, forKey: .textStylePreset)) ?? .paragraph
        textColorHex = (try? container.decode(String.self, forKey: .textColorHex)) ?? "#111111"
        textAlignment = (try? container.decode(PresentationTextAlignment.self, forKey: .textAlignment)) ?? .leading
        textFontSize = (try? container.decode(Double.self, forKey: .textFontSize)) ?? 24
        textWeightValue = (try? container.decode(Double.self, forKey: .textWeightValue)) ?? 0.5
        shapeFillColorHex = (try? container.decode(String.self, forKey: .shapeFillColorHex)) ?? "#FFFFFF"
        shapeBorderColorHex = (try? container.decode(String.self, forKey: .shapeBorderColorHex)) ?? "#D6DDE8"
        shapeBorderWidth = (try? container.decode(Double.self, forKey: .shapeBorderWidth)) ?? 1.2
        shapeCornerRadiusRatio = (try? container.decode(Double.self, forKey: .shapeCornerRadiusRatio)) ?? 0.18
        shapeStyleRaw = (try? container.decode(String.self, forKey: .shapeStyleRaw)) ?? PresentationShapeStyle.roundedRect.rawValue
        iconSystemName = (try? container.decode(String.self, forKey: .iconSystemName)) ?? "wrench.adjustable"
        iconColorHex = (try? container.decode(String.self, forKey: .iconColorHex)) ?? "#111111"
        iconHasBackground = (try? container.decode(Bool.self, forKey: .iconHasBackground)) ?? true
        iconBackgroundColorHex = (try? container.decode(String.self, forKey: .iconBackgroundColorHex)) ?? "#FFFFFF"
        imageCornerRadiusRatio = (try? container.decode(Double.self, forKey: .imageCornerRadiusRatio)) ?? 0
        vectorStrokeColorHex = (try? container.decode(String.self, forKey: .vectorStrokeColorHex)) ?? "#0F172A"
        vectorBackgroundColorHex = (try? container.decode(String.self, forKey: .vectorBackgroundColorHex)) ?? "#FFFFFF"
        vectorBackgroundVisible = (try? container.decode(Bool.self, forKey: .vectorBackgroundVisible)) ?? false
    }
}

struct PresentationPersistedSVGDocument: Codable {
    var width: Int
    var height: Int
    var body: String
}

struct PresentationPersistedStylization: Codable {
    var flowDisplacement: Double
    var flowOctaves: Double
    var crayonRoughness: Double
    var crayonWax: Double
    var crayonHatchDensity: Double
    var pixelDotSize: Double
    var pixelDensity: Double
    var pixelJitter: Double
    var equationN: Double
    var equationTheta: Double
    var equationScale: Double
    var equationContrast: Double

    init(from source: SVGStylizationParameters) {
        flowDisplacement = source.flowDisplacement
        flowOctaves = source.flowOctaves
        crayonRoughness = source.crayonRoughness
        crayonWax = source.crayonWax
        crayonHatchDensity = source.crayonHatchDensity
        pixelDotSize = source.pixelDotSize
        pixelDensity = source.pixelDensity
        pixelJitter = source.pixelJitter
        equationN = source.equationN
        equationTheta = source.equationTheta
        equationScale = source.equationScale
        equationContrast = source.equationContrast
    }

    var value: SVGStylizationParameters {
        SVGStylizationParameters(
            flowDisplacement: flowDisplacement,
            flowOctaves: flowOctaves,
            crayonRoughness: crayonRoughness,
            crayonWax: crayonWax,
            crayonHatchDensity: crayonHatchDensity,
            pixelDotSize: pixelDotSize,
            pixelDensity: pixelDensity,
            pixelJitter: pixelJitter,
            equationN: equationN,
            equationTheta: equationTheta,
            equationScale: equationScale,
            equationContrast: equationContrast
        )
    }
}

struct AnimatedGradientRing: View {
    let lineWidth: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let rotation = Angle.degrees(
                (timeline.date.timeIntervalSinceReferenceDate * 72.0)
                    .truncatingRemainder(dividingBy: 360)
            )
            Circle()
                .stroke(
                    AngularGradient(
                        gradient: Gradient(
                            colors: [
                                Color(red: 0.99, green: 0.37, blue: 0.54),
                                Color(red: 0.99, green: 0.70, blue: 0.26),
                                Color(red: 0.28, green: 0.89, blue: 0.70),
                                Color(red: 0.27, green: 0.67, blue: 0.98),
                                Color(red: 0.72, green: 0.49, blue: 0.98),
                                Color(red: 0.99, green: 0.37, blue: 0.54)
                            ]
                        ),
                        center: .center,
                        angle: rotation
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                )
        }
        .padding(1)
    }
}

private struct AnimatedGradientScreenBorder: View {
    let lineWidth: CGFloat
    let inset: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let corner = max(20, min(proxy.size.width, proxy.size.height) * 0.035)
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let rotation = Angle.degrees(
                    (timeline.date.timeIntervalSinceReferenceDate * 58.0)
                        .truncatingRemainder(dividingBy: 360)
                )
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(
                                colors: [
                                    Color(red: 0.99, green: 0.35, blue: 0.53),
                                    Color(red: 1.00, green: 0.76, blue: 0.25),
                                    Color(red: 0.28, green: 0.88, blue: 0.72),
                                    Color(red: 0.25, green: 0.66, blue: 0.98),
                                    Color(red: 0.74, green: 0.50, blue: 0.99),
                                    Color(red: 0.99, green: 0.35, blue: 0.53)
                                ]
                            ),
                            center: .center,
                            angle: rotation
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                    )
                    .padding(inset)
            }
        }
    }
}

#Preview {
    ContentView()
}
