import SwiftUI
import PhotosUI
import Combine
#if canImport(UIKit) && canImport(WebKit)
import UIKit
import WebKit
#endif
#if canImport(VisionKit)
import VisionKit
#endif
#if canImport(Vision)
import Vision
#endif
#if canImport(CoreImage)
import CoreImage
#endif
#if canImport(ImageIO)
import ImageIO
#endif

struct PresentationKeyboardAdaptive: ViewModifier {
    @State private var keyboardHeight: CGFloat = 0
    private var keyboardLift: CGFloat {
        let raw = max(0, keyboardHeight * 0.45)
        return min(200, raw)
    }

    func body(content: Content) -> some View {
        content
            .offset(y: -keyboardLift)
            .animation(.easeOut(duration: 0.22), value: keyboardLift)
            .onReceive(Publishers.edunodeKeyboardHeight) { height in
                keyboardHeight = max(0, height)
            }
    }
}

#if canImport(UIKit)
private extension Publishers {
    static var edunodeKeyboardHeight: AnyPublisher<CGFloat, Never> {
        let willShow = NotificationCenter.default.publisher(
            for: UIResponder.keyboardWillShowNotification
        )
        .map { $0.edunodeKeyboardHeight }

        let willHide = NotificationCenter.default.publisher(
            for: UIResponder.keyboardWillHideNotification
        )
        .map { _ in CGFloat(0) }

        return MergeMany(willShow, willHide)
            .eraseToAnyPublisher()
    }
}

private extension Notification {
    var edunodeKeyboardHeight: CGFloat {
        (userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect)?.height ?? 0
    }
}
#else
private extension Publishers {
    static var edunodeKeyboardHeight: AnyPublisher<CGFloat, Never> {
        Just(0).eraseToAnyPublisher()
    }
}
#endif

// MARK: - HTML-first image styling model (local, no SVGKit package dependency)

enum SVGFilterStyle: String, CaseIterable, Identifiable, Sendable, Codable {
    case original
    case flowField
    case crayonBrush
    case pixelPainter
    case equationField

    var id: String { rawValue }

    var displayName: String {
        let isChinese = Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
        switch self {
        case .original: return isChinese ? "原图" : "Original"
        case .flowField: return isChinese ? "流场笔触" : "Flow Field"
        case .crayonBrush: return isChinese ? "蜡笔笔触" : "Crayon Brush"
        case .pixelPainter: return isChinese ? "像素绘制" : "Pixel Painter"
        case .equationField: return isChinese ? "方程场" : "Equation Field"
        }
    }
}

struct SVGStylizationParameters: Sendable, Equatable, Codable {
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

    init(
        flowDisplacement: Double = 3.4,
        flowOctaves: Double = 3.0,
        crayonRoughness: Double = 2.8,
        crayonWax: Double = 0.62,
        crayonHatchDensity: Double = 0.56,
        pixelDotSize: Double = 8.0,
        pixelDensity: Double = 0.66,
        pixelJitter: Double = 0.52,
        equationN: Double = 4.8,
        equationTheta: Double = 5.0,
        equationScale: Double = 1.0,
        equationContrast: Double = 1.0
    ) {
        self.flowDisplacement = flowDisplacement
        self.flowOctaves = flowOctaves
        self.crayonRoughness = crayonRoughness
        self.crayonWax = crayonWax
        self.crayonHatchDensity = crayonHatchDensity
        self.pixelDotSize = pixelDotSize
        self.pixelDensity = pixelDensity
        self.pixelJitter = pixelJitter
        self.equationN = equationN
        self.equationTheta = equationTheta
        self.equationScale = equationScale
        self.equationContrast = equationContrast
    }

    static var `default`: SVGStylizationParameters {
        SVGStylizationParameters()
    }
}

struct SVGVectorizationOptions: Sendable, Codable {
    var maxDimension: Int
    var edgeIntensity: Double
    var threshold: UInt8
    var minRunLength: Int
    var strokeColorHex: String
    var strokeWidth: Double

    init(
        maxDimension: Int = 720,
        edgeIntensity: Double = 3.6,
        threshold: UInt8 = 62,
        minRunLength: Int = 2,
        strokeColorHex: String = "#0F172A",
        strokeWidth: Double = 1.3
    ) {
        self.maxDimension = max(64, maxDimension)
        self.edgeIntensity = max(0.1, edgeIntensity)
        self.threshold = threshold
        self.minRunLength = max(1, minRunLength)
        self.strokeColorHex = strokeColorHex
        self.strokeWidth = max(0.2, strokeWidth)
    }

    static var presentationDefault: SVGVectorizationOptions {
        SVGVectorizationOptions()
    }
}

struct SVGDocument: Sendable, Codable {
    var width: Int
    var height: Int
    var defs: [String]
    var body: String

    init(width: Int, height: Int, defs: [String] = [], body: String) {
        self.width = max(1, width)
        self.height = max(1, height)
        self.defs = defs
        self.body = body
    }

    func xmlString() -> String {
        let defsBlock = defs.isEmpty ? "" : "<defs>\(defs.joined(separator: "\n"))</defs>"
        return """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(width)" height="\(height)" viewBox="0 0 \(width) \(height)" fill="none">
        \(defsBlock)
        \(body)
        </svg>
        """
    }
}

enum SVGKitError: Error {
    case imageDecodeFailed
    case renderFailed
}

enum SVGBitmapConverter {
    static func vectorize(
        imageData: Data,
        options: SVGVectorizationOptions = .presentationDefault
    ) throws -> SVGDocument {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw SVGKitError.imageDecodeFailed
        }
        return try vectorize(cgImage: cgImage, options: options)
    }

    static func vectorize(
        cgImage: CGImage,
        options: SVGVectorizationOptions = .presentationDefault
    ) throws -> SVGDocument {
        #if canImport(CoreImage)
        let binary = try EdgeMaskGenerator.generate(from: cgImage, options: options)
        let pathData = SVGPathBuilder.runLengthPath(
            mask: binary.mask,
            width: binary.width,
            height: binary.height,
            targetWidth: cgImage.width,
            targetHeight: cgImage.height,
            minRunLength: options.minRunLength
        )

        let body: String
        if pathData.isEmpty {
            body = """
            <rect x="0" y="0" width="\(cgImage.width)" height="\(cgImage.height)" fill="none" stroke="\(options.strokeColorHex)" stroke-width="\(SVGNumberFormatter.f(options.strokeWidth))"/>
            """
        } else {
            body = """
            <g fill="none" stroke="\(options.strokeColorHex)" stroke-linecap="round" stroke-linejoin="round" stroke-width="\(SVGNumberFormatter.f(options.strokeWidth))">
              <path d="\(pathData)"/>
            </g>
            """
        }
        return SVGDocument(width: cgImage.width, height: cgImage.height, body: body)
        #else
        _ = options
        throw SVGKitError.renderFailed
        #endif
    }

    #if canImport(UIKit)
    static func vectorize(
        image: UIImage,
        options: SVGVectorizationOptions = .presentationDefault
    ) throws -> SVGDocument {
        guard let cgImage = image.cgImage else {
            throw SVGKitError.imageDecodeFailed
        }
        return try vectorize(cgImage: cgImage, options: options)
    }
    #endif
}

enum SVGPipeline {
    static func apply(
        style: SVGFilterStyle,
        to document: SVGDocument,
        parameters: SVGStylizationParameters = .default,
        strokeColorHex: String = "#111111"
    ) -> SVGDocument {
        let baseID = "svgkit_\(style.rawValue)"
        let strokeColor = normalizedStrokeHex(strokeColorHex)
        var defs = document.defs
        defs.append(
            contentsOf: styleDefinitions(
                for: style,
                baseID: baseID,
                parameters: parameters,
                strokeColor: strokeColor
            )
        )

        return SVGDocument(
            width: document.width,
            height: document.height,
            defs: defs,
            body: styledBody(
                for: style,
                baseID: baseID,
                content: document.body,
                width: document.width,
                height: document.height,
                parameters: parameters,
                strokeColor: strokeColor
            )
        )
    }

    private static func styleDefinitions(
        for style: SVGFilterStyle,
        baseID: String,
        parameters: SVGStylizationParameters,
        strokeColor: String
    ) -> [String] {
        let filterID = "\(baseID)_filter"
        switch style {
        case .original:
            return []
        case .flowField:
            let displacement = clamp(parameters.flowDisplacement, min: 0.2, max: 18.0)
            let octaves = Int(clamp(parameters.flowOctaves, min: 1, max: 8).rounded())
            return ["""
            <filter id="\(filterID)" x="-35%" y="-35%" width="170%" height="170%">
              <feTurbulence type="fractalNoise" baseFrequency="0.68" numOctaves="\(octaves)" seed="41" result="field"/>
              <feDisplacementMap in="SourceGraphic" in2="field" scale="\(n(displacement))" xChannelSelector="R" yChannelSelector="G" result="flow"/>
              <feGaussianBlur in="flow" stdDeviation="0.12"/>
            </filter>
            """]
        case .crayonBrush:
            let roughness = clamp(parameters.crayonRoughness, min: 0.2, max: 14.0)
            let wax = clamp(parameters.crayonWax, min: 0.05, max: 1.6)
            let hatchDensity = clamp(parameters.crayonHatchDensity, min: 0.05, max: 1.5)
            let hatchStep = 2.2 + (1.5 - hatchDensity) * 10.5
            let turbulenceFrequency = 0.42 + roughness * 0.12
            let displacement = 0.6 + roughness * 1.15
            let blur = 0.06 + (1.6 - wax) * 0.24
            return ["""
            <filter id="\(filterID)" x="-35%" y="-35%" width="170%" height="170%">
              <feMorphology in="SourceGraphic" operator="dilate" radius="0.62" result="thick"/>
              <feTurbulence type="fractalNoise" baseFrequency="\(n(turbulenceFrequency))" numOctaves="4" seed="19" result="grain"/>
              <feDisplacementMap in="thick" in2="grain" scale="\(n(displacement))" xChannelSelector="R" yChannelSelector="G" result="scribble"/>
              <feGaussianBlur in="scribble" stdDeviation="\(n(blur))"/>
            </filter>
            """,
            """
            <pattern id="\(baseID)_wax" width="\(n(hatchStep))" height="\(n(hatchStep))" patternUnits="userSpaceOnUse">
              <path d="M 0 \(n(hatchStep*0.35)) L \(n(hatchStep)) 0" stroke="\(strokeColor)" stroke-width="0.66" opacity="\(n(0.2 + wax * 0.46))"/>
              <path d="M 0 \(n(hatchStep*0.8)) L \(n(hatchStep*0.7)) 0" stroke="\(strokeColor)" stroke-width="0.54" opacity="\(n(0.15 + wax * 0.32))"/>
            </pattern>
            """]
        case .pixelPainter:
            let dotSize = clamp(parameters.pixelDotSize, min: 1.0, max: 52.0)
            let density = clamp(parameters.pixelDensity, min: 0.05, max: 1.6)
            let jitter = clamp(parameters.pixelJitter, min: 0.0, max: 2.2)
            let blur = 0.02 + (1.7 - density) * 0.16 + dotSize * 0.008
            let dilateRadius = max(0.15, dotSize * 0.12 + (1.3 - min(1.3, density)) * 1.5)
            let maskSoften = 0.08 + dotSize * 0.015 + jitter * 0.05
            let maskFilterID = "\(baseID)_maskFilter"
            return ["""
            <filter id="\(filterID)" x="-25%" y="-25%" width="150%" height="150%">
              <feGaussianBlur in="SourceGraphic" stdDeviation="\(n(blur))" result="softDots"/>
              <feComponentTransfer in="softDots">
                <feFuncA type="linear" slope="1.28" intercept="-0.02"/>
              </feComponentTransfer>
            </filter>
            """,
            """
            <filter id="\(maskFilterID)" x="-35%" y="-35%" width="170%" height="170%">
              <feMorphology in="SourceGraphic" operator="dilate" radius="\(n(dilateRadius))" result="expanded"/>
              <feGaussianBlur in="expanded" stdDeviation="\(n(maskSoften))" result="softExpanded"/>
              <feComponentTransfer in="softExpanded">
                <feFuncA type="gamma" amplitude="1.0" exponent="0.85" offset="0"/>
              </feComponentTransfer>
            </filter>
            """]
        case .equationField:
            let nValue = clamp(parameters.equationN, min: 0.1, max: 28.0)
            let thetaWeight = clamp(parameters.equationTheta, min: 0.2, max: 24.0)
            let scale = clamp(parameters.equationScale, min: 0.15, max: 4.0)
            let contrast = clamp(parameters.equationContrast, min: 0.2, max: 5.0)
            let octaves = Int(clamp(2.0 + (nValue / 3.2), min: 2.0, max: 6.0).rounded())
            let baseFrequency = 0.015 + (nValue / 12.0) * 0.055
            let displacement = 0.8 + thetaWeight * 0.46 + scale * 2.2
            return ["""
            <filter id="\(filterID)" x="-45%" y="-45%" width="190%" height="190%">
              <feTurbulence type="fractalNoise" baseFrequency="\(n(baseFrequency))" numOctaves="\(octaves)" seed="73" result="eqNoise"/>
              <feDisplacementMap in="SourceGraphic" in2="eqNoise" scale="\(n(displacement))" xChannelSelector="R" yChannelSelector="G" result="warped"/>
              <feGaussianBlur in="warped" stdDeviation="\(n(0.02 + (2.4 - scale) * 0.06))" result="smoothed"/>
              <feComponentTransfer in="smoothed">
                <feFuncR type="gamma" amplitude="1.0" exponent="\(n(1.0 / contrast))" offset="0"/>
                <feFuncG type="gamma" amplitude="1.0" exponent="\(n(1.0 / contrast))" offset="0"/>
                <feFuncB type="gamma" amplitude="1.0" exponent="\(n(1.0 / contrast))" offset="0"/>
              </feComponentTransfer>
            </filter>
            """]
        }
    }

    private static func styledBody(
        for style: SVGFilterStyle,
        baseID: String,
        content: String,
        width: Int,
        height: Int,
        parameters: SVGStylizationParameters,
        strokeColor: String
    ) -> String {
        let filterID = "\(baseID)_filter"
        let w = "\(width)"
        let h = "\(height)"

        switch style {
        case .original:
            return retinted(content: content, strokeColor: strokeColor)
        case .flowField:
            let displacement = clamp(parameters.flowDisplacement, min: 0.2, max: 18.0)
            let base = retinted(content: content, strokeColor: strokeColor)
            return """
            <g>
              <g filter="url(#\(filterID))">\(base)</g>
              <g transform="translate(1.7,-0.9) rotate(-0.6 \(w) \(h))" opacity="0.4" style="stroke-dasharray:\(n(2.0 + displacement*0.24)) \(n(1.1 + displacement*0.1)); stroke-linecap:round;">\(base)</g>
              <g transform="translate(-1.4,1.1) rotate(0.5 \(w) \(h))" opacity="0.28" style="stroke-dasharray:\(n(0.9 + displacement*0.14)) \(n(1.7 + displacement*0.16)); stroke-linecap:round;">\(base)</g>
            </g>
            """
        case .crayonBrush:
            let wax = clamp(parameters.crayonWax, min: 0.05, max: 1.6)
            let roughness = clamp(parameters.crayonRoughness, min: 0.2, max: 14.0)
            let hatchDensity = clamp(parameters.crayonHatchDensity, min: 0.05, max: 1.5)
            let jitterX = roughness * 0.65
            let jitterY = roughness * 0.42
            let hatchDash = 0.7 + (1.5 - hatchDensity) * 2.2
            let scribbleDash = 0.9 + roughness * 0.6
            let base = retinted(content: content, strokeColor: strokeColor)
            return """
            <g>
              <g filter="url(#\(filterID))" style="stroke:\(strokeColor);stroke-width:\(n(1.22 + roughness * 0.16));opacity:\(n(0.78 + wax * 0.16));">\(base)</g>
              <g opacity="\(n(0.2 + wax * 0.4))" style="stroke:url(#\(baseID)_wax);stroke-width:\(n(1.28 + roughness * 0.18));stroke-linecap:round;stroke-dasharray:\(n(hatchDash)) \(n(hatchDash * 1.6));">\(base)</g>
              <g transform="translate(\(n(jitterX)) \(n(-jitterY)))" opacity="\(n(0.26 + wax * 0.28))" style="stroke:\(strokeColor);stroke-width:\(n(0.92 + roughness * 0.12));stroke-dasharray:\(n(scribbleDash)) \(n(1.4 + roughness * 0.75));stroke-linecap:round;">\(base)</g>
              <g transform="translate(\(n(-jitterY)) \(n(jitterX * 0.74)))" opacity="\(n(0.14 + wax * 0.18))" style="stroke:\(strokeColor);stroke-width:\(n(0.72 + roughness * 0.08));stroke-dasharray:\(n(0.6 + roughness * 0.35)) \(n(1.05 + roughness * 0.55));stroke-linecap:round;">\(base)</g>
            </g>
            """
        case .pixelPainter:
            let density = clamp(parameters.pixelDensity, min: 0.05, max: 1.6)
            let maskID = "\(baseID)_lineMask"
            let maskFilterID = "\(baseID)_maskFilter"
            let base = retinted(content: content, strokeColor: strokeColor)
            let whiteBase = retinted(content: content, strokeColor: "#FFFFFF")
            let dots = pixelPainterDots(
                width: width,
                height: height,
                parameters: parameters,
                strokeColor: strokeColor
            )
            return """
            <g>
              <defs>
                <mask id="\(maskID)" maskUnits="userSpaceOnUse" x="0" y="0" width="\(w)" height="\(h)">
                  <rect x="0" y="0" width="\(w)" height="\(h)" fill="black"/>
                  <g filter="url(#\(maskFilterID))">\(whiteBase)</g>
                </mask>
              </defs>
              <g mask="url(#\(maskID))">
                <g filter="url(#\(filterID))" opacity="\(n(0.22 + min(0.5, density * 0.22)))">\(dots)</g>
                <g opacity="\(n(0.38 + min(0.44, density * 0.18)))">\(dots)</g>
              </g>
              <g opacity="\(n(0.16 + min(0.2, density * 0.09)))">\(base)</g>
            </g>
            """
        case .equationField:
            let nValue = clamp(parameters.equationN, min: 0.1, max: 28.0)
            let thetaWeight = clamp(parameters.equationTheta, min: 0.2, max: 24.0)
            let scale = clamp(parameters.equationScale, min: 0.15, max: 4.0)
            let contrast = clamp(parameters.equationContrast, min: 0.2, max: 5.0)
            let driftA = sin(nValue * cos(scale) + thetaWeight) * 2.3
            let driftB = cos(thetaWeight * 0.7) * 1.8
            let base = retinted(content: content, strokeColor: strokeColor)
            return """
            <g>
              <g filter="url(#\(filterID))" style="stroke:\(strokeColor);opacity:0.94;">\(base)</g>
              <g transform="translate(\(n(driftA)) \(n(-driftB))) rotate(\(n(thetaWeight * 0.42 - 2.2)) \(w) \(h))" opacity="\(n(0.22 + (contrast / 2.5) * 0.14))" style="stroke:\(strokeColor);stroke-dasharray:\(n(1.1 + scale * 0.9)) \(n(1.6 + (1.0 / contrast) * 1.5));stroke-linecap:round;">\(base)</g>
              <g transform="translate(\(n(-driftB)) \(n(driftA))) rotate(\(n(-thetaWeight * 0.33 + 1.7)) \(w) \(h))" opacity="\(n(0.13 + min(0.25, nValue / 50.0)))" style="stroke:\(strokeColor);stroke-dasharray:\(n(0.8 + scale * 0.5)) \(n(2.0 + thetaWeight * 0.12));stroke-linecap:round;">\(base)</g>
            </g>
            """
        }
    }

    private static func retinted(content: String, strokeColor: String) -> String {
        var result = content
        if let attrRegex = try? NSRegularExpression(pattern: #"stroke="[^"]*""#, options: []) {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = attrRegex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: #"stroke="\#(strokeColor)""#
            )
        }

        if let styleRegex = try? NSRegularExpression(pattern: #"stroke\s*:\s*[^;"]+"#, options: [.caseInsensitive]) {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = styleRegex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: "stroke:\(strokeColor)"
            )
        }
        return result
    }

    private static func normalizedStrokeHex(_ value: String) -> String {
        normalizedHex(value, fallback: "#111111")
    }

    private static func pixelPainterDots(
        width: Int,
        height: Int,
        parameters: SVGStylizationParameters,
        strokeColor: String
    ) -> String {
        let size = clamp(parameters.pixelDotSize, min: 1.0, max: 52.0)
        let density = clamp(parameters.pixelDensity, min: 0.05, max: 1.6)
        let jitter = clamp(parameters.pixelJitter, min: 0.0, max: 2.2)
        let normalizedDensity = min(1.0, density / 1.6)
        let step = max(2, Int((size * 0.88) + (1.0 - normalizedDensity) * 16.0))
        let radius = max(0.7, size * 0.24)
        let maxDotCount = max(
            1800,
            min(
                14000,
                Int(
                    (Double(width * height) / max(9.0, size * size * 0.68))
                    * (0.8 + normalizedDensity * 1.25)
                )
            )
        )

        var shapes: [String] = []
        shapes.reserveCapacity((width / step + 1) * (height / step + 1))

        outerLoop: for y in stride(from: 0, through: height, by: step) {
            for x in stride(from: 0, through: width, by: step) {
                if shapes.count >= maxDotCount {
                    break outerLoop
                }
                let gate = noise2D(x / step, y / step, seed: 21)
                if gate > normalizedDensity { continue }
                let jx = (noise2D(x / step, y / step, seed: 39) - 0.5) * 2.0 * jitter * size * 0.42
                let jy = (noise2D(x / step, y / step, seed: 57) - 0.5) * 2.0 * jitter * size * 0.42
                let localR = radius * (0.65 + noise2D(x / step, y / step, seed: 77) * 0.55)
                let densityBoost = max(0.0, density - 1.0)
                let opacity = min(0.95, 0.24 + noise2D(x / step, y / step, seed: 93) * 0.52 + densityBoost * 0.2)
                let px = Double(x) + jx
                let py = Double(y) + jy
                let shapeGate = noise2D(x / step, y / step, seed: 117)
                if shapeGate > 0.82 {
                    let side = localR * (1.8 + noise2D(x / step, y / step, seed: 133) * 0.75)
                    shapes.append(
                        "<rect x=\"\(n(px - side * 0.5))\" y=\"\(n(py - side * 0.5))\" width=\"\(n(side))\" height=\"\(n(side))\" rx=\"\(n(side * 0.24))\" fill=\"\(strokeColor)\" opacity=\"\(n(opacity))\"/>"
                    )
                } else {
                    shapes.append(
                        "<circle cx=\"\(n(px))\" cy=\"\(n(py))\" r=\"\(n(localR))\" fill=\"\(strokeColor)\" opacity=\"\(n(opacity))\"/>"
                    )
                }
            }
        }

        return """
        <g opacity="0.9">
          \(shapes.joined(separator: ""))
        </g>
        """
    }

    private static func noise2D(_ x: Int, _ y: Int, seed: Int) -> Double {
        var value = UInt64(bitPattern: Int64((x * 73856093) ^ (y * 19349663) ^ (seed * 83492791)))
        value ^= value >> 13
        value &*= 1274126177
        value ^= value >> 16
        return Double(value & 0xffff) / Double(0xffff)
    }

    private static func clamp(_ value: Double, min: Double, max: Double) -> Double {
        Swift.max(min, Swift.min(max, value))
    }

    private static func n(_ value: Double) -> String {
        SVGNumberFormatter.f(value)
    }
}

#if canImport(CoreImage)
private struct BinaryMask {
    let mask: [Bool]
    let width: Int
    let height: Int
}

private enum EdgeMaskGenerator {
    static func generate(from cgImage: CGImage, options: SVGVectorizationOptions) throws -> BinaryMask {
        let ciImage = CIImage(cgImage: cgImage)
        let maxSide = max(cgImage.width, cgImage.height)
        let scale = min(1, Double(options.maxDimension) / Double(maxSide))
        let transformed = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let grayscale = transformed.applyingFilter(
            "CIColorControls",
            parameters: [
                kCIInputSaturationKey: 0.0,
                kCIInputContrastKey: 1.4
            ]
        )
        let edges = grayscale.applyingFilter(
            "CIEdges",
            parameters: [kCIInputIntensityKey: options.edgeIntensity]
        )

        let extent = edges.extent.integral
        let width = max(1, Int(extent.width))
        let height = max(1, Int(extent.height))

        let context = CIContext(options: nil)
        guard let edgeImage = context.createCGImage(edges, from: extent) else {
            throw SVGKitError.renderFailed
        }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        guard let bitmapContext = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            throw SVGKitError.renderFailed
        }

        bitmapContext.draw(edgeImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var mask = [Bool](repeating: false, count: width * height)
        let threshold = options.threshold
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * bytesPerRow) + (x * bytesPerPixel)
                let r = pixels[offset]
                let g = pixels[offset + 1]
                let b = pixels[offset + 2]
                let luma = UInt8((UInt16(r) + UInt16(g) + UInt16(b)) / 3)
                mask[(y * width) + x] = luma >= threshold
            }
        }

        return BinaryMask(mask: mask, width: width, height: height)
    }
}
#endif

private enum SVGPathBuilder {
    static func runLengthPath(
        mask: [Bool],
        width: Int,
        height: Int,
        targetWidth: Int,
        targetHeight: Int,
        minRunLength: Int
    ) -> String {
        guard width > 0, height > 0, targetWidth > 0, targetHeight > 0 else {
            return ""
        }
        let sx = Double(targetWidth) / Double(width)
        let sy = Double(targetHeight) / Double(height)

        var commands: [String] = []
        commands.reserveCapacity(height * 2)

        for y in 0..<height {
            var x = 0
            while x < width {
                while x < width && !mask[(y * width) + x] {
                    x += 1
                }
                if x >= width { break }

                let start = x
                while x < width && mask[(y * width) + x] {
                    x += 1
                }
                let end = x - 1
                let runLength = end - start + 1
                if runLength < minRunLength { continue }

                let x1 = SVGNumberFormatter.f(Double(start) * sx)
                let x2 = SVGNumberFormatter.f(Double(end) * sx)
                let yy = SVGNumberFormatter.f(Double(y) * sy)
                commands.append("M \(x1) \(yy) L \(x2) \(yy)")
            }
        }

        return commands.joined(separator: " ")
    }
}

private enum SVGNumberFormatter {
    static func f(_ value: Double) -> String {
        String(format: "%.2f", value)
            .replacingOccurrences(of: "\\.?0+$", with: "", options: .regularExpression)
    }
}

func presentationImageMIMEType(_ data: Data) -> String {
    if data.count >= 4 {
        let bytes = [UInt8](data.prefix(12))
        if bytes[0] == 0xFF, bytes[1] == 0xD8 { return "image/jpeg" }
        if bytes[0] == 0x89, bytes[1] == 0x50, bytes[2] == 0x4E, bytes[3] == 0x47 { return "image/png" }
        if bytes[0] == 0x47, bytes[1] == 0x49, bytes[2] == 0x46 { return "image/gif" }
        if bytes[0] == 0x52, bytes[1] == 0x49, bytes[2] == 0x46, bytes[3] == 0x46 { return "image/webp" }
    }
    return "image/png"
}

func presentationImageDataURI(_ data: Data) -> String {
    "data:\(presentationImageMIMEType(data));base64,\(data.base64EncodedString())"
}

func presentationImageCSSFilter(style: SVGFilterStyle, params: SVGStylizationParameters) -> String {
    switch style {
    case .original:
        return "none"
    case .flowField:
        let contrast = 0.9 + min(2.4, params.flowDisplacement * 0.16)
        let hue = min(90, params.flowOctaves * 9)
        let saturate = 0.88 + min(2.0, params.flowDisplacement * 0.08)
        return "contrast(\(cssFilterNum(contrast))) saturate(\(cssFilterNum(saturate))) hue-rotate(\(cssFilterNum(hue))deg)"
    case .crayonBrush:
        let contrast = 1.0 + min(2.8, params.crayonRoughness * 0.12)
        let saturate = 0.72 + min(2.2, params.crayonWax * 0.8)
        let brightness = 0.92 + min(0.36, params.crayonHatchDensity * 0.2)
        return "contrast(\(cssFilterNum(contrast))) saturate(\(cssFilterNum(saturate))) brightness(\(cssFilterNum(brightness)))"
    case .pixelPainter:
        let contrast = 1.1 + min(3.4, params.pixelDensity * 1.8)
        let saturate = 0.7 + min(1.8, params.pixelJitter * 0.6)
        return "contrast(\(cssFilterNum(contrast))) saturate(\(cssFilterNum(saturate)))"
    case .equationField:
        let hue = min(160, params.equationTheta * 7.2)
        let contrast = 0.9 + min(3.6, params.equationContrast * 0.55)
        let brightness = 0.84 + min(0.9, params.equationScale * 0.15)
        return "hue-rotate(\(cssFilterNum(hue))deg) contrast(\(cssFilterNum(contrast))) brightness(\(cssFilterNum(brightness)))"
    }
}

private func cssFilterNum(_ value: Double) -> String {
    String(format: "%.3f", value)
        .replacingOccurrences(of: "\\.?0+$", with: "", options: .regularExpression)
}

enum PresentationOverlayKind: String, CaseIterable, Identifiable, Sendable, Codable {
    case image
    case text
    case roundedRect
    case icon

    var id: String { rawValue }
}

enum PresentationShapeStyle: String, CaseIterable, Identifiable, Sendable, Codable {
    case roundedRect
    case rectangle
    case capsule
    case ellipse

    var id: String { rawValue }

    func label(isChinese: Bool) -> String {
        switch self {
        case .roundedRect:
            return isChinese ? "圆角矩形" : "Rounded"
        case .rectangle:
            return isChinese ? "矩形" : "Rectangle"
        case .capsule:
            return isChinese ? "胶囊" : "Capsule"
        case .ellipse:
            return isChinese ? "椭圆" : "Ellipse"
        }
    }

    var symbolName: String {
        switch self {
        case .roundedRect:
            return "rectangle.roundedtop"
        case .rectangle:
            return "rectangle"
        case .capsule:
            return "capsule"
        case .ellipse:
            return "oval"
        }
    }
}

struct AnyShape: Shape {
    private let pathBuilder: @Sendable (CGRect) -> Path

    init<S: Shape & Sendable>(_ shape: S) {
        pathBuilder = { rect in
            shape.path(in: rect)
        }
    }

    func path(in rect: CGRect) -> Path {
        pathBuilder(rect)
    }
}

enum PresentationInspectorPanel: String, CaseIterable, Identifiable {
    case page
    case edit

    var id: String { rawValue }
}

enum PresentationNativeElement: String, Identifiable, CaseIterable {
    case title
    case subtitle
    case levelChip
    case toolkitIcon
    case mainContent
    case toolkitContent
    case mainCard
    case activityCard

    var id: String { rawValue }
}

struct PresentationNativeLayoutOverride: Equatable, Codable {
    var offsetX: Double
    var offsetY: Double

    static let zero = PresentationNativeLayoutOverride(offsetX: 0, offsetY: 0)

    var isZero: Bool {
        abs(offsetX) < 0.000_1 && abs(offsetY) < 0.000_1
    }

    func clamped() -> PresentationNativeLayoutOverride {
        PresentationNativeLayoutOverride(
            offsetX: max(-0.7, min(0.7, offsetX)),
            offsetY: max(-0.7, min(0.7, offsetY))
        )
    }
}

enum PresentationAspectPreset: String, CaseIterable, Identifiable, Codable {
    case ratio16x9
    case ratio4x3

    var id: String { rawValue }

    var ratio: CGFloat {
        switch self {
        case .ratio16x9:
            return 16.0 / 9.0
        case .ratio4x3:
            return 4.0 / 3.0
        }
    }

    func label(isChinese: Bool) -> String {
        switch self {
        case .ratio16x9:
            return "16:9"
        case .ratio4x3:
            return "4:3"
        }
    }
}

enum PresentationLayoutPreset: String, CaseIterable, Identifiable, Sendable, Codable {
    case balanced
    case structured
    case spacious
    case compact
    case showcase

    var id: String { rawValue }

    var columnRatio: (Double, Double) {
        switch self {
        case .balanced:
            return (1.0, 0.62)
        case .structured:
            return (1.24, 0.46)
        case .spacious:
            return (0.94, 0.70)
        case .compact:
            return (1.16, 0.54)
        case .showcase:
            return (0.86, 0.82)
        }
    }

    var sheetPaddingCqw: Double {
        switch self {
        case .balanced:
            return 4.8
        case .structured:
            return 4.1
        case .spacious:
            return 5.2
        case .compact:
            return 4.1
        case .showcase:
            return 5.9
        }
    }

    var sheetGapCqw: Double {
        switch self {
        case .balanced:
            return 1.8
        case .structured:
            return 1.35
        case .spacious:
            return 2.1
        case .compact:
            return 1.3
        case .showcase:
            return 2.5
        }
    }

    var contentGapCqw: Double {
        switch self {
        case .balanced:
            return 1.25
        case .structured:
            return 0.96
        case .spacious:
            return 1.42
        case .compact:
            return 0.96
        case .showcase:
            return 1.7
        }
    }

    var cardRadiusCqw: Double {
        switch self {
        case .balanced:
            return 1.05
        case .structured:
            return 0.66
        case .spacious:
            return 1.22
        case .compact:
            return 0.82
        case .showcase:
            return 1.62
        }
    }

    var cardPaddingY: Double {
        switch self {
        case .balanced:
            return 1.1
        case .structured:
            return 0.88
        case .spacious:
            return 1.22
        case .compact:
            return 0.9
        case .showcase:
            return 1.4
        }
    }

    var cardPaddingX: Double {
        switch self {
        case .balanced:
            return 1.35
        case .structured:
            return 1.08
        case .spacious:
            return 1.44
        case .compact:
            return 1.05
        case .showcase:
            return 1.74
        }
    }
}

enum PresentationThemeTemplate: String, CaseIterable, Identifiable, Sendable, Codable {
    case white
    case dark
    case business
    case warm
    case artistic

    var id: String { rawValue }

    func label(isChinese: Bool) -> String {
        switch self {
        case .white:
            return isChinese ? "白色简洁" : "White"
        case .dark:
            return isChinese ? "暗色沉浸" : "Dark"
        case .business:
            return isChinese ? "商务演示" : "Business"
        case .warm:
            return isChinese ? "温暖课堂" : "Warm"
        case .artistic:
            return isChinese ? "艺术创意" : "Artistic"
        }
    }

    func subtitle(isChinese: Bool) -> String {
        switch self {
        case .white:
            return isChinese ? "干净、通用" : "Clean and neutral"
        case .dark:
            return isChinese ? "高对比、聚焦" : "Immersive contrast"
        case .business:
            return isChinese ? "结构化、稳重" : "Structured and formal"
        case .warm:
            return isChinese ? "柔和、亲和" : "Soft and friendly"
        case .artistic:
            return isChinese ? "创意、展示感" : "Expressive visual"
        }
    }
}

struct PresentationPageStyle: Equatable, Codable {
    var aspectPreset: PresentationAspectPreset = .ratio16x9
    var templateID: String = PresentationThemeTemplate.white.rawValue
    var layoutPreset: PresentationLayoutPreset = .balanced
    var backgroundColorHex: String = "#FFFFFF"
    var cardBackgroundColorHex: String = "#FFFFFF"
    var cardBorderColorHex: String = "#D6DDE8"
    var chipBackgroundColorHex: String = "#1D8F5A"
    var chipTextColorHex: String = "#FFFFFF"
    var toolkitBadgeBackgroundHex: String = "#E8EEFB"
    var toolkitBadgeBorderHex: String = "#CAD7F3"

    static let `default` = PresentationPageStyle()
}

enum PresentationTextStylePreset: String, CaseIterable, Identifiable, Sendable, Codable {
    case h1
    case h2
    case h3
    case h4
    case paragraph

    var id: String { rawValue }

    func label(isChinese: Bool) -> String {
        switch self {
        case .h1:
            return "H1"
        case .h2:
            return "H2"
        case .h3:
            return "H3"
        case .h4:
            return "H4"
        case .paragraph:
            return isChinese ? "正文" : "P"
        }
    }

    var defaultFontSize: Double {
        switch self {
        case .h1:
            return 56
        case .h2:
            return 44
        case .h3:
            return 36
        case .h4:
            return 30
        case .paragraph:
            return 24
        }
    }

    var defaultWeightValue: Double {
        switch self {
        case .h1:
            return 0.95
        case .h2:
            return 0.9
        case .h3:
            return 0.8
        case .h4:
            return 0.72
        case .paragraph:
            return 0.5
        }
    }
}

enum PresentationTextAlignment: String, CaseIterable, Identifiable, Sendable, Codable {
    case leading
    case center
    case trailing

    var id: String { rawValue }

    var textAlignment: TextAlignment {
        switch self {
        case .leading:
            return .leading
        case .center:
            return .center
        case .trailing:
            return .trailing
        }
    }

    var frameAlignment: Alignment {
        switch self {
        case .leading:
            return .leading
        case .center:
            return .center
        case .trailing:
            return .trailing
        }
    }

    var symbolName: String {
        switch self {
        case .leading:
            return "text.alignleft"
        case .center:
            return "text.aligncenter"
        case .trailing:
            return "text.alignright"
        }
    }
}

struct PresentationTextEditingState: Equatable {
    var content: String
    var stylePreset: PresentationTextStylePreset
    var colorHex: String
    var alignment: PresentationTextAlignment
    var fontSize: Double
    var weightValue: Double
    var normalizedWidth: CGFloat
    var normalizedHeight: CGFloat
}

struct PresentationRoundedRectEditingState: Equatable {
    var shapeStyle: PresentationShapeStyle
    var fillColorHex: String
    var borderColorHex: String
    var borderWidth: Double
    var cornerRadiusRatio: Double
    var normalizedWidth: CGFloat
    var normalizedHeight: CGFloat
}

struct PresentationIconEditingState: Equatable {
    var systemName: String
    var colorHex: String
    var hasBackground: Bool
    var backgroundColorHex: String
    var normalizedWidth: CGFloat
}

struct PresentationTextStyleConfig: Equatable, Codable {
    var sizeCqw: Double
    var weightValue: Double
    var colorHex: String

    init(sizeCqw: Double, weightValue: Double, colorHex: String) {
        self.sizeCqw = sizeCqw
        self.weightValue = weightValue
        self.colorHex = colorHex
    }

    var cssWeight: Int {
        let clamped = max(0, min(1, weightValue))
        return Int((clamped * 800).rounded()) + 100
    }
}

struct PresentationTextTheme: Equatable, Codable {
    var h1: PresentationTextStyleConfig = .init(sizeCqw: 5.0, weightValue: 0.95, colorHex: "#111111")
    var h2: PresentationTextStyleConfig = .init(sizeCqw: 1.44, weightValue: 0.82, colorHex: "#1F2F52")
    var h3: PresentationTextStyleConfig = .init(sizeCqw: 1.72, weightValue: 0.64, colorHex: "#465062")
    var h4: PresentationTextStyleConfig = .init(sizeCqw: 1.22, weightValue: 0.52, colorHex: "#7A8496")
    var paragraph: PresentationTextStyleConfig = .init(sizeCqw: 1.46, weightValue: 0.48, colorHex: "#111111")

    static let `default` = PresentationTextTheme()

    func style(for preset: PresentationTextStylePreset) -> PresentationTextStyleConfig {
        switch preset {
        case .h1:
            return h1
        case .h2:
            return h2
        case .h3:
            return h3
        case .h4:
            return h4
        case .paragraph:
            return paragraph
        }
    }

    mutating func setStyle(_ style: PresentationTextStyleConfig, for preset: PresentationTextStylePreset) {
        switch preset {
        case .h1:
            h1 = style
        case .h2:
            h2 = style
        case .h3:
            h3 = style
        case .h4:
            h4 = style
        case .paragraph:
            paragraph = style
        }
    }
}

extension PresentationThemeTemplate {
    var pageStyle: PresentationPageStyle {
        switch self {
        case .white:
            return PresentationPageStyle(
                aspectPreset: .ratio16x9,
                templateID: rawValue,
                layoutPreset: .balanced,
                backgroundColorHex: "#FFFFFF",
                cardBackgroundColorHex: "#FFFFFF",
                cardBorderColorHex: "#D6DDE8",
                chipBackgroundColorHex: "#1D8F5A",
                chipTextColorHex: "#FFFFFF",
                toolkitBadgeBackgroundHex: "#E8EEFB",
                toolkitBadgeBorderHex: "#CAD7F3"
            )
        case .dark:
            return PresentationPageStyle(
                aspectPreset: .ratio16x9,
                templateID: rawValue,
                layoutPreset: .compact,
                backgroundColorHex: "#000000",
                cardBackgroundColorHex: "#111111",
                cardBorderColorHex: "#2A2A2A",
                chipBackgroundColorHex: "#4F46E5",
                chipTextColorHex: "#FFFFFF",
                toolkitBadgeBackgroundHex: "#1C1C1C",
                toolkitBadgeBorderHex: "#3A3A3A"
            )
        case .business:
            return PresentationPageStyle(
                aspectPreset: .ratio16x9,
                templateID: rawValue,
                layoutPreset: .structured,
                backgroundColorHex: "#E3ECF9",
                cardBackgroundColorHex: "#F7FAFF",
                cardBorderColorHex: "#9FB8E2",
                chipBackgroundColorHex: "#0B4DB7",
                chipTextColorHex: "#FFFFFF",
                toolkitBadgeBackgroundHex: "#D7E6FF",
                toolkitBadgeBorderHex: "#95B5EA"
            )
        case .warm:
            return PresentationPageStyle(
                aspectPreset: .ratio16x9,
                templateID: rawValue,
                layoutPreset: .spacious,
                backgroundColorHex: "#FFF8EE",
                cardBackgroundColorHex: "#FFFCF7",
                cardBorderColorHex: "#E6D8C2",
                chipBackgroundColorHex: "#B45309",
                chipTextColorHex: "#FFFFFF",
                toolkitBadgeBackgroundHex: "#F5E6D6",
                toolkitBadgeBorderHex: "#DFCAA8"
            )
        case .artistic:
            return PresentationPageStyle(
                aspectPreset: .ratio16x9,
                templateID: rawValue,
                layoutPreset: .showcase,
                backgroundColorHex: "#FFF3C5",
                cardBackgroundColorHex: "#FFE8F6",
                cardBorderColorHex: "#F0A6D8",
                chipBackgroundColorHex: "#B230B8",
                chipTextColorHex: "#FFF7D8",
                toolkitBadgeBackgroundHex: "#FFE16B",
                toolkitBadgeBorderHex: "#FF9D3D"
            )
        }
    }

    var textTheme: PresentationTextTheme {
        switch self {
        case .white:
            return PresentationTextTheme(
                h1: .init(sizeCqw: 5.0, weightValue: 0.95, colorHex: "#111111"),
                h2: .init(sizeCqw: 1.44, weightValue: 0.82, colorHex: "#1F2F52"),
                h3: .init(sizeCqw: 1.72, weightValue: 0.64, colorHex: "#465062"),
                h4: .init(sizeCqw: 1.22, weightValue: 0.52, colorHex: "#7A8496"),
                paragraph: .init(sizeCqw: 1.46, weightValue: 0.48, colorHex: "#111111")
            )
        case .dark:
            return PresentationTextTheme(
                h1: .init(sizeCqw: 4.9, weightValue: 0.9, colorHex: "#FFFFFF"),
                h2: .init(sizeCqw: 1.4, weightValue: 0.8, colorHex: "#C7D2FE"),
                h3: .init(sizeCqw: 1.66, weightValue: 0.64, colorHex: "#D1D5DB"),
                h4: .init(sizeCqw: 1.2, weightValue: 0.56, colorHex: "#A5B4FC"),
                paragraph: .init(sizeCqw: 1.4, weightValue: 0.46, colorHex: "#F3F4F6")
            )
        case .business:
            return PresentationTextTheme(
                h1: .init(sizeCqw: 4.75, weightValue: 0.92, colorHex: "#0E2A57"),
                h2: .init(sizeCqw: 1.34, weightValue: 0.84, colorHex: "#113F8A"),
                h3: .init(sizeCqw: 1.5, weightValue: 0.64, colorHex: "#2A558E"),
                h4: .init(sizeCqw: 1.08, weightValue: 0.56, colorHex: "#3E679F"),
                paragraph: .init(sizeCqw: 1.3, weightValue: 0.52, colorHex: "#16335F")
            )
        case .warm:
            return PresentationTextTheme(
                h1: .init(sizeCqw: 4.95, weightValue: 0.9, colorHex: "#3A2510"),
                h2: .init(sizeCqw: 1.45, weightValue: 0.8, colorHex: "#7C3A10"),
                h3: .init(sizeCqw: 1.66, weightValue: 0.62, colorHex: "#7A5A3C"),
                h4: .init(sizeCqw: 1.24, weightValue: 0.54, colorHex: "#9A6F45"),
                paragraph: .init(sizeCqw: 1.42, weightValue: 0.48, colorHex: "#3A2510")
            )
        case .artistic:
            return PresentationTextTheme(
                h1: .init(sizeCqw: 5.6, weightValue: 0.94, colorHex: "#5C1DB5"),
                h2: .init(sizeCqw: 1.72, weightValue: 0.84, colorHex: "#C72D83"),
                h3: .init(sizeCqw: 1.94, weightValue: 0.68, colorHex: "#A13A6E"),
                h4: .init(sizeCqw: 1.38, weightValue: 0.6, colorHex: "#A66A12"),
                paragraph: .init(sizeCqw: 1.58, weightValue: 0.54, colorHex: "#5F2A88")
            )
        }
    }
}

struct PresentationStylingSnapshot {
    var overlays: [PresentationSlideOverlay]
    var selectedOverlayID: UUID?
    var vectorization: PresentationVectorizationSettings
    var nativeTextOverrides: [PresentationNativeElement: PresentationTextStyleConfig]
    var nativeContentOverrides: [PresentationNativeElement: String]
    var nativeLayoutOverrides: [PresentationNativeElement: PresentationNativeLayoutOverride]
    var pageStyle: PresentationPageStyle
    var textTheme: PresentationTextTheme
}

struct PresentationSlideOverlay: Identifiable {
    let id: UUID
    var kind: PresentationOverlayKind
    var imageData: Data
    var extractedImageData: Data?
    var cropSourceImageData: Data?
    var cumulativeCropRect: CGRect
    var vectorDocument: SVGDocument?
    var selectedFilter: SVGFilterStyle
    var stylization: SVGStylizationParameters
    var center: CGPoint
    var normalizedWidth: CGFloat
    var normalizedHeight: CGFloat
    var aspectRatio: CGFloat
    var rotationDegrees: Double
    var isExtracting: Bool
    var activeVectorizationRequestID: UUID?
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
    var shapeStyle: PresentationShapeStyle
    var iconSystemName: String
    var iconColorHex: String
    var iconHasBackground: Bool
    var iconBackgroundColorHex: String
    var imageCornerRadiusRatio: Double
    var vectorStrokeColorHex: String
    var vectorBackgroundColorHex: String
    var vectorBackgroundVisible: Bool

    init(
        id: UUID = UUID(),
        kind: PresentationOverlayKind = .image,
        imageData: Data,
        extractedImageData: Data? = nil,
        cropSourceImageData: Data? = nil,
        cumulativeCropRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1),
        vectorDocument: SVGDocument? = nil,
        selectedFilter: SVGFilterStyle = .original,
        stylization: SVGStylizationParameters = .default,
        center: CGPoint = CGPoint(x: 0.5, y: 0.58),
        normalizedWidth: CGFloat = 0.28,
        normalizedHeight: CGFloat = 0.2,
        aspectRatio: CGFloat = 1,
        rotationDegrees: Double = 0,
        isExtracting: Bool = false,
        activeVectorizationRequestID: UUID? = nil,
        textContent: String = "",
        textStylePreset: PresentationTextStylePreset = .paragraph,
        textColorHex: String = "#111111",
        textAlignment: PresentationTextAlignment = .leading,
        textFontSize: Double = 24,
        textWeightValue: Double = 0.5,
        shapeFillColorHex: String = "#FFFFFF",
        shapeBorderColorHex: String = "#D6DDE8",
        shapeBorderWidth: Double = 1.2,
        shapeCornerRadiusRatio: Double = 0.18,
        shapeStyle: PresentationShapeStyle = .roundedRect,
        iconSystemName: String = "star.fill",
        iconColorHex: String = "#111111",
        iconHasBackground: Bool = true,
        iconBackgroundColorHex: String = "#FFFFFF",
        imageCornerRadiusRatio: Double = 0,
        vectorStrokeColorHex: String = "#0F172A",
        vectorBackgroundColorHex: String = "#FFFFFF",
        vectorBackgroundVisible: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.imageData = imageData
        self.extractedImageData = extractedImageData
        self.cropSourceImageData = cropSourceImageData
        self.cumulativeCropRect = normalizedUnitCropRect(cumulativeCropRect)
        self.vectorDocument = vectorDocument
        self.selectedFilter = selectedFilter
        self.stylization = stylization
        self.center = center
        self.normalizedWidth = max(0.12, normalizedWidth)
        self.normalizedHeight = max(0.08, normalizedHeight)
        self.aspectRatio = max(0.15, aspectRatio)
        self.rotationDegrees = rotationDegrees
        self.isExtracting = isExtracting
        self.activeVectorizationRequestID = activeVectorizationRequestID
        self.textContent = textContent
        self.textStylePreset = textStylePreset
        self.textColorHex = textColorHex
        self.textAlignment = textAlignment
        self.textFontSize = textFontSize
        self.textWeightValue = textWeightValue
        self.shapeFillColorHex = shapeFillColorHex
        self.shapeBorderColorHex = shapeBorderColorHex
        self.shapeBorderWidth = max(0, min(12, shapeBorderWidth))
        self.shapeCornerRadiusRatio = max(0, min(0.5, shapeCornerRadiusRatio))
        self.shapeStyle = shapeStyle
        self.iconSystemName = iconSystemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "star.fill"
            : iconSystemName
        self.iconColorHex = iconColorHex
        self.iconHasBackground = iconHasBackground
        self.iconBackgroundColorHex = iconBackgroundColorHex
        self.imageCornerRadiusRatio = max(0, min(0.5, imageCornerRadiusRatio))
        self.vectorStrokeColorHex = vectorStrokeColorHex
        self.vectorBackgroundColorHex = vectorBackgroundColorHex
        self.vectorBackgroundVisible = vectorBackgroundVisible
    }

    static func makeText(
        id: UUID = UUID(),
        center: CGPoint = CGPoint(x: 0.5, y: 0.62)
    ) -> PresentationSlideOverlay {
        PresentationSlideOverlay(
            id: id,
            kind: .text,
            imageData: Data(),
            selectedFilter: .original,
            stylization: .default,
            center: center,
            normalizedWidth: 0.54,
            normalizedHeight: 0.18,
            aspectRatio: 3.2,
            textContent: "",
            textStylePreset: .h2,
            textColorHex: "#111111",
            textAlignment: .leading,
            textFontSize: PresentationTextStylePreset.h2.defaultFontSize,
            textWeightValue: PresentationTextStylePreset.h2.defaultWeightValue
        )
    }

    static func makeRoundedRect(
        id: UUID = UUID(),
        shapeStyle: PresentationShapeStyle = .roundedRect,
        center: CGPoint = CGPoint(x: 0.5, y: 0.62)
    ) -> PresentationSlideOverlay {
        PresentationSlideOverlay(
            id: id,
            kind: .roundedRect,
            imageData: Data(),
            selectedFilter: .original,
            stylization: .default,
            center: center,
            normalizedWidth: 0.4,
            normalizedHeight: 0.18,
            aspectRatio: 2.2,
            shapeFillColorHex: "#FFFFFF",
            shapeBorderColorHex: "#D6DDE8",
            shapeBorderWidth: 1.4,
            shapeCornerRadiusRatio: 0.18,
            shapeStyle: shapeStyle
        )
    }

    static func makeIcon(
        id: UUID = UUID(),
        center: CGPoint = CGPoint(x: 0.5, y: 0.62)
    ) -> PresentationSlideOverlay {
        PresentationSlideOverlay(
            id: id,
            kind: .icon,
            imageData: Data(),
            selectedFilter: .original,
            stylization: .default,
            center: center,
            normalizedWidth: 0.14,
            normalizedHeight: 0.14,
            aspectRatio: 1,
            iconSystemName: "wrench.adjustable",
            iconColorHex: "#111111",
            iconHasBackground: false,
            iconBackgroundColorHex: "#FFFFFF"
        )
    }

    var isImage: Bool {
        kind == .image
    }

    var isText: Bool {
        kind == .text
    }

    var isRoundedRect: Bool {
        kind == .roundedRect
    }

    var isIcon: Bool {
        kind == .icon
    }

    var displayImageData: Data {
        extractedImageData ?? imageData
    }

    var renderedSVGString: String? {
        guard kind == .image, let vectorDocument else { return nil }
        return SVGPipeline.apply(
            style: selectedFilter,
            to: vectorDocument,
            parameters: stylization,
            strokeColorHex: vectorStrokeColorHex
        ).xmlString()
    }

    var resolvedTextWeight: Font.Weight {
        switch textWeightValue {
        case ..<0.15:
            return .thin
        case ..<0.3:
            return .light
        case ..<0.45:
            return .regular
        case ..<0.62:
            return .medium
        case ..<0.78:
            return .semibold
        case ..<0.9:
            return .bold
        default:
            return .heavy
        }
    }

    var textEditingState: PresentationTextEditingState {
        get {
            PresentationTextEditingState(
                content: textContent,
                stylePreset: textStylePreset,
                colorHex: textColorHex,
                alignment: textAlignment,
                fontSize: textFontSize,
                weightValue: textWeightValue,
                normalizedWidth: normalizedWidth,
                normalizedHeight: normalizedHeight
            )
        }
        set {
            textContent = newValue.content
            textStylePreset = newValue.stylePreset
            textColorHex = newValue.colorHex
            textAlignment = newValue.alignment
            textFontSize = max(12, min(96, newValue.fontSize))
            textWeightValue = max(0, min(1, newValue.weightValue))
            normalizedWidth = max(0.2, min(0.92, newValue.normalizedWidth))
            normalizedHeight = max(0.08, min(0.72, newValue.normalizedHeight))
        }
    }

    var roundedRectEditingState: PresentationRoundedRectEditingState {
        get {
            PresentationRoundedRectEditingState(
                shapeStyle: shapeStyle,
                fillColorHex: shapeFillColorHex,
                borderColorHex: shapeBorderColorHex,
                borderWidth: shapeBorderWidth,
                cornerRadiusRatio: shapeCornerRadiusRatio,
                normalizedWidth: normalizedWidth,
                normalizedHeight: normalizedHeight
            )
        }
        set {
            shapeStyle = newValue.shapeStyle
            shapeFillColorHex = newValue.fillColorHex
            shapeBorderColorHex = newValue.borderColorHex
            shapeBorderWidth = max(0, min(12, newValue.borderWidth))
            shapeCornerRadiusRatio = max(0, min(0.5, newValue.cornerRadiusRatio))
            normalizedWidth = max(0.1, min(0.92, newValue.normalizedWidth))
            normalizedHeight = max(0.08, min(0.72, newValue.normalizedHeight))
            aspectRatio = max(0.15, normalizedWidth / max(normalizedHeight, 0.01))
        }
    }

    var iconEditingState: PresentationIconEditingState {
        get {
            PresentationIconEditingState(
                systemName: iconSystemName,
                colorHex: iconColorHex,
                hasBackground: iconHasBackground,
                backgroundColorHex: iconBackgroundColorHex,
                normalizedWidth: normalizedWidth
            )
        }
        set {
            iconSystemName = newValue.systemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? iconSystemName
                : newValue.systemName
            iconColorHex = newValue.colorHex
            iconHasBackground = newValue.hasBackground
            iconBackgroundColorHex = newValue.backgroundColorHex
            normalizedWidth = max(0.08, min(0.42, newValue.normalizedWidth))
            normalizedHeight = normalizedWidth
            aspectRatio = 1
        }
    }
}

struct PresentationVectorizationSettings: Equatable, Codable {
    var edgeIntensity: Double
    var threshold: Double
    var minRunLength: Double
    var strokeWidth: Double

    static let `default` = PresentationVectorizationSettings(
        edgeIntensity: SVGVectorizationOptions.presentationDefault.edgeIntensity,
        threshold: Double(SVGVectorizationOptions.presentationDefault.threshold),
        minRunLength: Double(SVGVectorizationOptions.presentationDefault.minRunLength),
        strokeWidth: SVGVectorizationOptions.presentationDefault.strokeWidth
    )

    var svgOptions: SVGVectorizationOptions {
        SVGVectorizationOptions(
            maxDimension: SVGVectorizationOptions.presentationDefault.maxDimension,
            edgeIntensity: edgeIntensity,
            threshold: UInt8(max(0, min(255, Int(threshold.rounded())))),
            minRunLength: Int(max(1, min(24, Int(minRunLength.rounded())))),
            strokeColorHex: SVGVectorizationOptions.presentationDefault.strokeColorHex,
            strokeWidth: strokeWidth
        )
    }
}

struct PresentationSlideStylingState {
    var overlays: [PresentationSlideOverlay] = []
    var selectedOverlayID: UUID?
    var undoStack: [PresentationStylingSnapshot] = []
    var redoStack: [PresentationStylingSnapshot] = []
    var vectorization = PresentationVectorizationSettings.default
    var nativeTextOverrides: [PresentationNativeElement: PresentationTextStyleConfig] = [:]
    var nativeContentOverrides: [PresentationNativeElement: String] = [:]
    var nativeLayoutOverrides: [PresentationNativeElement: PresentationNativeLayoutOverride] = [:]
    var pageStyle = PresentationPageStyle.default
    var textTheme = PresentationTextTheme.default

    static let empty = PresentationSlideStylingState()
}

func themedPresentationSlideHTML(
    courseName: String,
    slide: EduPresentationComposedSlide,
    isChinese: Bool,
    pageStyle: PresentationPageStyle,
    textTheme: PresentationTextTheme,
    nativeTextOverrides: [PresentationNativeElement: PresentationTextStyleConfig] = [:],
    nativeContentOverrides: [PresentationNativeElement: String] = [:],
    nativeLayoutOverrides: [PresentationNativeElement: PresentationNativeLayoutOverride] = [:]
) -> String {
    let base = EduPresentationHTMLExporter.singleSlideHTML(
        courseName: courseName,
        slide: slide,
        isChinese: isChinese
    )
    let themed = applyPresentationTheme(
        to: base,
        pageStyle: pageStyle,
        textTheme: textTheme
    )
    let stylePatched = applyNativeTextOverrides(
        to: themed,
        overridesBySlideID: [slide.id: nativeTextOverrides]
    )
    let contentPatched = applyNativeContentOverrides(
        to: stylePatched,
        overridesBySlideID: [slide.id: nativeContentOverrides]
    )
    return applyNativeLayoutOverrides(
        to: contentPatched,
        overridesBySlideID: [slide.id: nativeLayoutOverrides]
    )
}

func editorSlideHTMLRemovingInnerMask(_ html: String) -> String {
    let css = """
    /* Editor canvas already has a SwiftUI rounded mask. */
    .slide-sheet {
      border-radius: 0 !important;
    }
    """
    guard let styleEnd = html.range(of: "</style>") else {
        return html
    }
    return html.replacingCharacters(in: styleEnd.lowerBound..<styleEnd.lowerBound, with: css + "\n")
}

func themedPresentationDeckHTML(
    courseName: String,
    slides: [EduPresentationComposedSlide],
    isChinese: Bool,
    pageStyle: PresentationPageStyle,
    textTheme: PresentationTextTheme,
    overlayHTMLBySlideID: [UUID: String] = [:],
    nativeTextOverridesBySlideID: [UUID: [PresentationNativeElement: PresentationTextStyleConfig]] = [:],
    nativeContentOverridesBySlideID: [UUID: [PresentationNativeElement: String]] = [:],
    nativeLayoutOverridesBySlideID: [UUID: [PresentationNativeElement: PresentationNativeLayoutOverride]] = [:]
) -> String {
    let base = EduPresentationHTMLExporter.printHTML(
        courseName: courseName,
        slides: slides,
        isChinese: isChinese,
        overlayHTMLBySlideID: overlayHTMLBySlideID
    )
    let themed = applyPresentationTheme(
        to: base,
        pageStyle: pageStyle,
        textTheme: textTheme
    )
    let stylePatched = applyNativeTextOverrides(
        to: themed,
        overridesBySlideID: nativeTextOverridesBySlideID
    )
    let contentPatched = applyNativeContentOverrides(
        to: stylePatched,
        overridesBySlideID: nativeContentOverridesBySlideID
    )
    return applyNativeLayoutOverrides(
        to: contentPatched,
        overridesBySlideID: nativeLayoutOverridesBySlideID
    )
}

private func applyPresentationTheme(
    to html: String,
    pageStyle: PresentationPageStyle,
    textTheme: PresentationTextTheme
) -> String {
    let css = presentationThemeOverrideCSS(pageStyle: pageStyle, textTheme: textTheme)
    guard let styleEnd = html.range(of: "</style>") else {
        return html
    }
    return html.replacingCharacters(in: styleEnd.lowerBound..<styleEnd.lowerBound, with: css + "\n")
}

private func applyNativeTextOverrides(
    to html: String,
    overridesBySlideID: [UUID: [PresentationNativeElement: PresentationTextStyleConfig]]
) -> String {
    guard !overridesBySlideID.isEmpty else { return html }
    let css = nativeTextOverrideCSS(overridesBySlideID: overridesBySlideID)
    guard !css.isEmpty, let styleEnd = html.range(of: "</style>") else {
        return html
    }
    return html.replacingCharacters(in: styleEnd.lowerBound..<styleEnd.lowerBound, with: css + "\n")
}

private func nativeTextOverrideCSS(
    overridesBySlideID: [UUID: [PresentationNativeElement: PresentationTextStyleConfig]]
) -> String {
    let lines: [String] = overridesBySlideID
        .sorted(by: { $0.key.uuidString < $1.key.uuidString })
        .flatMap { (slideID, map) -> [String] in
            map.compactMap { element, style -> String? in
                let selectorText = nativeTextSelector(for: element)
                guard !selectorText.isEmpty else { return nil }
                let prefixed = prefixedSelectorList(
                    selectorText,
                    prefix: ".slide[data-slide-id=\"\(slideID.uuidString)\"]"
                )
                guard !prefixed.isEmpty else { return nil }
                return """
                \(prefixed) {
                  font-size: \(f2(style.sizeCqw))cqw !important;
                  font-weight: \(style.cssWeight) !important;
                  color: \(normalizedHex(style.colorHex, fallback: "#111111")) !important;
                }
                """
            }
        }
    guard !lines.isEmpty else { return "" }
    return "/* EduNode native text element overrides */\n" + lines.joined(separator: "\n")
}

private func applyNativeContentOverrides(
    to html: String,
    overridesBySlideID: [UUID: [PresentationNativeElement: String]]
) -> String {
    let sanitized: [String: [String: String]] = overridesBySlideID.reduce(into: [:]) { partial, entry in
        let slideID = entry.key.uuidString
        let map = entry.value.reduce(into: [String: String]()) { mapPartial, value in
            let cleaned = value.value.replacingOccurrences(of: "\r\n", with: "\n")
            mapPartial[value.key.rawValue] = cleaned
        }
        if !map.isEmpty {
            partial[slideID] = map
        }
    }
    guard !sanitized.isEmpty else { return html }
    guard let json = jsonString(sanitized) else { return html }

    let script = """
    <script id="edunode-native-content-overrides">
    (function () {
      const contentBySlide = \(json);
      const singleSelectorMap = {
        title: '.hero h1',
        subtitle: '.hero .lead',
        levelChip: '.hero .level-chip'
      };

      function splitLines(value) {
        return String(value || '')
          .replace(/\\r\\n/g, '\\n')
          .split('\\n')
          .map(line => line.trim())
          .filter(line => line.length > 0);
      }

      function replaceCardContent(scope, cardSelector, rawText, mode) {
        const card = scope.querySelector(cardSelector);
        if (!card) { return; }
        card.querySelectorAll('.knowledge-content, .activity-content, .empty').forEach(node => node.remove());

        const lines = splitLines(rawText);
        if (!lines.length) {
          const empty = document.createElement('p');
          empty.className = 'empty';
          empty.textContent = '';
          card.appendChild(empty);
          return;
        }

        const useActivity = mode === 'toolkit' || card.classList.contains('activity-main');
        const wrapper = document.createElement('div');
        wrapper.className = useActivity ? 'activity-content' : 'knowledge-content';
        if (!useActivity && lines.length === 1 && card.classList.contains('center-brief')) {
          wrapper.classList.add('centered');
        }

        lines.forEach(line => {
          const p = document.createElement('p');
          p.className = useActivity ? 'activity-line' : 'knowledge-line';
          p.textContent = line;
          wrapper.appendChild(p);
        });
        card.appendChild(wrapper);
      }

      function applyScopeOverrides(scope, overrides) {
        Object.keys(singleSelectorMap).forEach((key) => {
          if (!(key in overrides)) { return; }
          const target = scope.querySelector(singleSelectorMap[key]);
          if (target) {
            target.textContent = String(overrides[key] || '');
          }
        });

        if ('mainContent' in overrides) {
          replaceCardContent(scope, '.main-card', overrides.mainContent, 'main');
        }
        if ('toolkitContent' in overrides) {
          replaceCardContent(scope, '.activity-card', overrides.toolkitContent, 'toolkit');
        }
      }

      function applyAll() {
        const slides = document.querySelectorAll('.slide[data-slide-id]');
        if (slides.length === 0) {
          const first = Object.keys(contentBySlide)[0];
          if (first) {
            applyScopeOverrides(document, contentBySlide[first]);
          }
          return;
        }
        slides.forEach((slide) => {
          const sid = slide.getAttribute('data-slide-id');
          if (!sid || !contentBySlide[sid]) { return; }
          applyScopeOverrides(slide, contentBySlide[sid]);
        });
      }

      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', applyAll, { once: true });
      } else {
        applyAll();
      }
    })();
    </script>
    """
    return insertBeforeBodyEnd(html, snippet: script)
}

private func applyNativeLayoutOverrides(
    to html: String,
    overridesBySlideID: [UUID: [PresentationNativeElement: PresentationNativeLayoutOverride]]
) -> String {
    let sanitized: [String: [String: PresentationNativeLayoutOverride]] = overridesBySlideID.reduce(into: [:]) { partial, entry in
        let map = entry.value.reduce(into: [String: PresentationNativeLayoutOverride]()) { mapPartial, item in
            let clamped = item.value.clamped()
            guard !clamped.isZero else { return }
            mapPartial[item.key.rawValue] = clamped
        }
        if !map.isEmpty {
            partial[entry.key.uuidString] = map
        }
    }
    guard !sanitized.isEmpty else { return html }
    guard let json = jsonString(sanitized) else { return html }

    let script = """
    <script id="edunode-native-layout-overrides">
    (function () {
      const offsetBySlide = \(json);
      const selectorMap = {
        title: ['.hero h1'],
        subtitle: ['.hero .lead'],
        levelChip: ['.hero .level-chip'],
        toolkitIcon: ['.hero .toolkit-icon'],
        mainCard: ['.main-layout .main-card'],
        activityCard: ['.main-layout .activity-card'],
        mainContent: ['.main-card .knowledge-content', '.main-card .activity-content', '.main-card .empty'],
        toolkitContent: ['.activity-card .activity-content', '.activity-card .empty']
      };

      function applyOffsetsForScope(scope, map) {
        const sheet = scope.querySelector('.slide-sheet') || scope;
        const frame = sheet.getBoundingClientRect();
        if (!frame || frame.width <= 0 || frame.height <= 0) { return; }
        Object.keys(map).forEach((id) => {
          const offset = map[id] || {};
          const tx = (Number(offset.offsetX) || 0) * frame.width;
          const ty = (Number(offset.offsetY) || 0) * frame.height;
          const selectors = selectorMap[id] || [];
          selectors.forEach((selector) => {
            scope.querySelectorAll(selector).forEach((node) => {
              const key = 'edunodeNativeBaseTransform';
              if (node.dataset[key] === undefined) {
                node.dataset[key] = node.style.transform || '';
              }
              const base = node.dataset[key] || '';
              node.style.transform = (base ? (base + ' ') : '') + 'translate(' + tx + 'px, ' + ty + 'px)';
              node.style.willChange = 'transform';
            });
          });
        });
      }

      function applyAll() {
        const slides = document.querySelectorAll('.slide[data-slide-id]');
        if (slides.length === 0) {
          const first = Object.keys(offsetBySlide)[0];
          if (first) {
            applyOffsetsForScope(document, offsetBySlide[first]);
          }
          return;
        }
        slides.forEach((slide) => {
          const sid = slide.getAttribute('data-slide-id');
          if (!sid || !offsetBySlide[sid]) { return; }
          applyOffsetsForScope(slide, offsetBySlide[sid]);
        });
      }

      window.__edunodeNativeOffsets = offsetBySlide;

      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', applyAll, { once: true });
      } else {
        applyAll();
      }
      window.addEventListener('resize', () => {
        window.requestAnimationFrame(applyAll);
      });
    })();
    </script>
    """
    return insertBeforeBodyEnd(html, snippet: script)
}

private func nativeTextSelector(for element: PresentationNativeElement) -> String {
    switch element {
    case .title:
        return ".hero h1"
    case .subtitle:
        return ".hero .lead"
    case .levelChip:
        return ".hero .level-chip"
    case .mainContent:
        return ".main-card .knowledge-line, .main-card .activity-line, .main-card .activity-ordered li, .main-card .empty"
    case .toolkitContent:
        return ".activity-card .activity-line, .activity-card .activity-ordered li, .activity-card .empty"
    case .toolkitIcon, .mainCard, .activityCard:
        return ""
    }
}

private func prefixedSelectorList(_ selectorList: String, prefix: String) -> String {
    selectorList
        .split(separator: ",")
        .map { selector in
            let trimmed = selector.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return "" }
            return "\(prefix) \(trimmed)"
        }
        .filter { !$0.isEmpty }
        .joined(separator: ", ")
}

private func jsonString<T: Encodable>(_ value: T) -> String? {
    guard let data = try? JSONEncoder().encode(value),
          var text = String(data: data, encoding: .utf8) else {
        return nil
    }
    text = text.replacingOccurrences(of: "</", with: "<\\/")
    return text
}

private func insertBeforeBodyEnd(_ html: String, snippet: String) -> String {
    guard let bodyEnd = html.range(of: "</body>") else { return html }
    return html.replacingCharacters(in: bodyEnd.lowerBound..<bodyEnd.lowerBound, with: snippet + "\n")
}

private func presentationThemeOverrideCSS(
    pageStyle: PresentationPageStyle,
    textTheme: PresentationTextTheme
) -> String {
    let ratio = max(0.5, min(3.0, pageStyle.aspectPreset.ratio))
    let bg = normalizedHex(pageStyle.backgroundColorHex, fallback: "#FFFFFF")
    let cardBG = normalizedHex(pageStyle.cardBackgroundColorHex, fallback: "#FFFFFF")
    let cardBorder = normalizedHex(pageStyle.cardBorderColorHex, fallback: "#D6DDE8")
    let chipBG = normalizedHex(pageStyle.chipBackgroundColorHex, fallback: "#1D8F5A")
    let chipText = normalizedHex(pageStyle.chipTextColorHex, fallback: "#FFFFFF")
    let badgeBG = normalizedHex(pageStyle.toolkitBadgeBackgroundHex, fallback: "#E8EEFB")
    let badgeBorder = normalizedHex(pageStyle.toolkitBadgeBorderHex, fallback: "#CAD7F3")
    let layout = pageStyle.layoutPreset
    let columns = layout.columnRatio
    let h1 = textTheme.h1
    let h2 = textTheme.h2
    let h3 = textTheme.h3
    let h4 = textTheme.h4
    let p = textTheme.paragraph

    return """
    /* EduNode runtime theme overrides */
    .slide-sheet {
      aspect-ratio: \(f2(ratio)) / 1 !important;
      background: \(bg) !important;
      padding: \(f2(layout.sheetPaddingCqw))cqw \(f2(layout.sheetPaddingCqw - 0.2))cqw \(f2(layout.sheetPaddingCqw - 0.9))cqw !important;
      gap: \(f2(layout.sheetGapCqw))cqw !important;
    }
    body.embedded .slide-sheet {
      width: min(100vw, calc(100vh * \(f2(ratio)) / 1)) !important;
    }
    body.interactive .slide-sheet {
      width: min(92vw, calc(92vh * \(f2(ratio)) / 1)) !important;
    }
    .main-layout {
      grid-template-columns: minmax(0, \(f2(columns.0))fr) minmax(0, \(f2(columns.1))fr) !important;
      gap: \(f2(layout.contentGapCqw))cqw !important;
    }
    .main-card, .activity-card {
      background: \(cardBG) !important;
      border-color: \(cardBorder) !important;
      border-radius: \(f2(layout.cardRadiusCqw))cqw !important;
      padding: \(f2(layout.cardPaddingY))cqw \(f2(layout.cardPaddingX))cqw !important;
    }
    .toolkit-icon {
      background: \(badgeBG) !important;
      border-color: \(badgeBorder) !important;
    }
    .hero h1 {
      font-size: \(f2(h1.sizeCqw))cqw !important;
      font-weight: \(h1.cssWeight) !important;
      color: \(normalizedHex(h1.colorHex, fallback: "#111111")) !important;
    }
    .main-card h2, .activity-card h2 {
      font-size: \(f2(h2.sizeCqw))cqw !important;
      font-weight: \(h2.cssWeight) !important;
      color: \(normalizedHex(h2.colorHex, fallback: "#1F2F52")) !important;
    }
    .lead {
      font-size: \(f2(h3.sizeCqw))cqw !important;
      font-weight: \(h3.cssWeight) !important;
      color: \(normalizedHex(h3.colorHex, fallback: "#465062")) !important;
    }
    .level-chip {
      font-size: \(f2(h4.sizeCqw))cqw !important;
      font-weight: \(h4.cssWeight) !important;
      color: \(chipText) !important;
      background: \(chipBG) !important;
      border-color: \(chipBG) !important;
    }
    .slide-index {
      font-size: \(f2(h4.sizeCqw))cqw !important;
      font-weight: \(h4.cssWeight) !important;
      color: \(normalizedHex(h4.colorHex, fallback: "#7A8496")) !important;
    }
    .knowledge-line, .activity-line, .activity-ordered li, .empty, .cue {
      font-size: \(f2(p.sizeCqw))cqw !important;
      font-weight: \(p.cssWeight) !important;
      color: \(normalizedHex(p.colorHex, fallback: "#111111")) !important;
    }
    """
}

private func f2(_ value: Double) -> String {
    String(format: "%.2f", value)
        .replacingOccurrences(of: "\\.?0+$", with: "", options: .regularExpression)
}

private func normalizedUnitCropRect(_ rect: CGRect) -> CGRect {
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
