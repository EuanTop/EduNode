import SwiftUI
import PhotosUI
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

// MARK: - HTML-first image styling model (local, no SVGKit package dependency)

enum SVGFilterStyle: String, CaseIterable, Identifiable, Sendable, Codable {
    case original
    case flowField
    case crayonBrush
    case pixelPainter
    case equationField

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .original: return "Original"
        case .flowField: return "Flow Field"
        case .crayonBrush: return "Crayon Brush"
        case .pixelPainter: return "Pixel Painter"
        case .equationField: return "Equation Field"
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
        let strokeColor = normalizedHex(strokeColorHex)
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

    private static func normalizedHex(_ value: String) -> String {
        var cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") {
            cleaned.removeFirst()
        }
        if cleaned.count == 3 {
            cleaned = cleaned.map { "\($0)\($0)" }.joined()
        }
        guard cleaned.count == 6, Int(cleaned, radix: 16) != nil else {
            return "#111111"
        }
        return "#\(cleaned.uppercased())"
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

enum PresentationNativeElement: String, Identifiable {
    case title
    case subtitle
    case levelChip
    case toolkitIcon
    case mainCard
    case activityCard

    var id: String { rawValue }
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
            return (1.08, 0.58)
        case .spacious:
            return (0.94, 0.70)
        case .compact:
            return (1.16, 0.54)
        case .showcase:
            return (0.9, 0.74)
        }
    }

    var sheetPaddingCqw: Double {
        switch self {
        case .balanced:
            return 4.8
        case .structured:
            return 4.4
        case .spacious:
            return 5.2
        case .compact:
            return 4.1
        case .showcase:
            return 5.5
        }
    }

    var sheetGapCqw: Double {
        switch self {
        case .balanced:
            return 1.8
        case .structured:
            return 1.55
        case .spacious:
            return 2.1
        case .compact:
            return 1.3
        case .showcase:
            return 2.25
        }
    }

    var contentGapCqw: Double {
        switch self {
        case .balanced:
            return 1.25
        case .structured:
            return 1.12
        case .spacious:
            return 1.42
        case .compact:
            return 0.96
        case .showcase:
            return 1.58
        }
    }

    var cardRadiusCqw: Double {
        switch self {
        case .balanced:
            return 1.05
        case .structured:
            return 0.92
        case .spacious:
            return 1.22
        case .compact:
            return 0.82
        case .showcase:
            return 1.35
        }
    }

    var cardPaddingY: Double {
        switch self {
        case .balanced:
            return 1.1
        case .structured:
            return 1.02
        case .spacious:
            return 1.22
        case .compact:
            return 0.9
        case .showcase:
            return 1.28
        }
    }

    var cardPaddingX: Double {
        switch self {
        case .balanced:
            return 1.35
        case .structured:
            return 1.25
        case .spacious:
            return 1.44
        case .compact:
            return 1.05
        case .showcase:
            return 1.52
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
                backgroundColorHex: "#EEF4FF",
                cardBackgroundColorHex: "#F8FBFF",
                cardBorderColorHex: "#BFD3F7",
                chipBackgroundColorHex: "#1D4ED8",
                chipTextColorHex: "#FFFFFF",
                toolkitBadgeBackgroundHex: "#DFEAFF",
                toolkitBadgeBorderHex: "#AFC6F2"
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
                backgroundColorHex: "#FFF2D9",
                cardBackgroundColorHex: "#FFEAFE",
                cardBorderColorHex: "#F6B7FF",
                chipBackgroundColorHex: "#FF3E95",
                chipTextColorHex: "#FFF8CC",
                toolkitBadgeBackgroundHex: "#FFE27A",
                toolkitBadgeBorderHex: "#FFB24E"
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
                h1: .init(sizeCqw: 4.8, weightValue: 0.92, colorHex: "#0A2A67"),
                h2: .init(sizeCqw: 1.42, weightValue: 0.82, colorHex: "#1D4ED8"),
                h3: .init(sizeCqw: 1.64, weightValue: 0.62, colorHex: "#274B87"),
                h4: .init(sizeCqw: 1.18, weightValue: 0.56, colorHex: "#4A6FAE"),
                paragraph: .init(sizeCqw: 1.38, weightValue: 0.5, colorHex: "#102A5A")
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
                h1: .init(sizeCqw: 5.35, weightValue: 0.94, colorHex: "#7A00D9"),
                h2: .init(sizeCqw: 1.56, weightValue: 0.84, colorHex: "#FF4FA3"),
                h3: .init(sizeCqw: 1.78, weightValue: 0.66, colorHex: "#C6367A"),
                h4: .init(sizeCqw: 1.32, weightValue: 0.58, colorHex: "#B06A00"),
                paragraph: .init(sizeCqw: 1.48, weightValue: 0.52, colorHex: "#5A1D89")
            )
        }
    }
}

struct PresentationSlideOverlay: Identifiable {
    let id: UUID
    var kind: PresentationOverlayKind
    var imageData: Data
    var extractedImageData: Data?
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
    var vectorStrokeColorHex: String
    var vectorBackgroundColorHex: String
    var vectorBackgroundVisible: Bool

    init(
        id: UUID = UUID(),
        kind: PresentationOverlayKind = .image,
        imageData: Data,
        extractedImageData: Data? = nil,
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
        vectorStrokeColorHex: String = "#0F172A",
        vectorBackgroundColorHex: String = "#FFFFFF",
        vectorBackgroundVisible: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.imageData = imageData
        self.extractedImageData = extractedImageData
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
    var undoStack: [[PresentationSlideOverlay]] = []
    var redoStack: [[PresentationSlideOverlay]] = []
    var vectorization = PresentationVectorizationSettings.default
    var pageStyle = PresentationPageStyle.default
    var textTheme = PresentationTextTheme.default

    static let empty = PresentationSlideStylingState()
}

func themedPresentationSlideHTML(
    courseName: String,
    slide: EduPresentationComposedSlide,
    isChinese: Bool,
    pageStyle: PresentationPageStyle,
    textTheme: PresentationTextTheme
) -> String {
    let base = EduPresentationHTMLExporter.singleSlideHTML(
        courseName: courseName,
        slide: slide,
        isChinese: isChinese
    )
    return applyPresentationTheme(
        to: base,
        pageStyle: pageStyle,
        textTheme: textTheme
    )
}

func themedPresentationDeckHTML(
    courseName: String,
    slides: [EduPresentationComposedSlide],
    isChinese: Bool,
    pageStyle: PresentationPageStyle,
    textTheme: PresentationTextTheme,
    overlayHTMLBySlideID: [UUID: String] = [:]
) -> String {
    let base = EduPresentationHTMLExporter.printHTML(
        courseName: courseName,
        slides: slides,
        isChinese: isChinese,
        overlayHTMLBySlideID: overlayHTMLBySlideID
    )
    return applyPresentationTheme(
        to: base,
        pageStyle: pageStyle,
        textTheme: textTheme
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

private func normalizedHex(_ raw: String, fallback: String) -> String {
    var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.hasPrefix("#") {
        value.removeFirst()
    }
    if value.count == 3 {
        value = value.map { "\($0)\($0)" }.joined()
    }
    guard value.count == 6, Int(value, radix: 16) != nil else {
        return fallback
    }
    return "#\(value.uppercased())"
}

private func f2(_ value: Double) -> String {
    String(format: "%.2f", value)
        .replacingOccurrences(of: "\\.?0+$", with: "", options: .regularExpression)
}

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
    let onCropOverlay: (UUID, CGRect) -> Void
    let onDeleteOverlay: (UUID) -> Void
    let onExtractSubject: (UUID) -> Void
    let onConvertToSVG: (UUID) -> Void
    let onApplyFilter: (UUID, SVGFilterStyle) -> Void
    let onUpdateStylization: (UUID, SVGStylizationParameters) -> Void
    let onUpdateImageVectorStyle: (UUID, String, String, Bool) -> Void
    let onApplyImageStyleToAll: (UUID) -> Void
    let onUpdateTextOverlay: (UUID, PresentationTextEditingState) -> Void
    let onUpdateRoundedRectOverlay: (UUID, PresentationRoundedRectEditingState) -> Void
    let onUpdateIconOverlay: (UUID, PresentationIconEditingState) -> Void
    let onUpdateTextTheme: (PresentationTextTheme) -> Void
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
    @State private var imageDragActivationByOverlayID: [UUID: Bool] = [:]
    @State private var ignoreCanvasTapUntil: Date = .distantPast

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
        .onAppear {
            resetCropInputs()
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

            ZStack {
                PresentationSlideCanvasHTMLView(
                    baseHTML: themedPresentationSlideHTML(
                        courseName: courseName,
                        slide: slide,
                        isChinese: isChinese,
                        pageStyle: pageStyle,
                        textTheme: textTheme
                    ),
                    textTheme: textTheme,
                    overlays: stylingState.overlays,
                    selectedOverlayID: stylingState.selectedOverlayID,
                    onSelectOverlay: { selectedID in
                        selectedNativeElement = nil
                        if let selectedID {
                            onSelectOverlay(selectedID)
                            activePanel = .edit
                        } else {
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
                    onCropOverlay: { overlayID, rect in
                        onCropOverlay(overlayID, rect)
                    },
                    onDeleteOverlay: { overlayID in
                        onDeleteOverlay(overlayID)
                    },
                    onExtractOverlaySubject: { overlayID in
                        onSelectOverlay(overlayID)
                        activePanel = .edit
                        onExtractSubject(overlayID)
                    }
                )
                .allowsHitTesting(true)
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
                            onCropOverlay(overlayID, cropRect)
                        }
                    }
            )
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
    private func nativeElementInteractionLayer(canvasSize: CGSize) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onEnded { value in
                        // Treat as tap only; real drags are handled by overlay gestures.
                        let dragDistance = hypot(value.translation.width, value.translation.height)
                        guard dragDistance <= 6 else { return }

                        let hitElement = nativeElementRegions().first { pair in
                            let normalized = pair.1
                            let rect = CGRect(
                                x: normalized.origin.x * canvasSize.width,
                                y: normalized.origin.y * canvasSize.height,
                                width: normalized.width * canvasSize.width,
                                height: normalized.height * canvasSize.height
                            )
                            return rect.contains(value.location)
                        }?.0

                        if let hitElement {
                            selectedNativeElement = hitElement
                            onClearSelection()
                            activePanel = .edit
                        } else {
                            selectedNativeElement = nil
                            onClearSelection()
                        }
                    }
            )
    }

    @ViewBuilder
    private func nativeElementHighlightOverlay(canvasSize: CGSize) -> some View {
        if let selectedNativeElement,
           let normalizedRect = nativeElementRegions().first(where: { $0.0 == selectedNativeElement })?.1 {
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
        var regions: [(PresentationNativeElement, CGRect)] = [
            (.title, CGRect(x: 0.05, y: 0.05, width: 0.70, height: 0.13)),
            (.subtitle, CGRect(x: 0.05, y: 0.16, width: 0.66, height: 0.1)),
            (.levelChip, CGRect(x: 0.05, y: 0.2, width: 0.24, height: 0.07)),
            (.mainCard, CGRect(x: 0.05, y: 0.3, width: 0.60, height: 0.58))
        ]

        if !slide.toolkitItems.isEmpty {
            regions.append((.toolkitIcon, CGRect(x: 0.84, y: 0.06, width: 0.11, height: 0.11)))
            regions.append((.activityCard, CGRect(x: 0.67, y: 0.3, width: 0.28, height: 0.58)))
        }
        return regions
    }

    @ViewBuilder
    private var rightSidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isChinese ? "Presentation Design" : "Presentation Design")
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
            Text(isChinese ? "Page" : "Page")
                .tag(PresentationInspectorPanel.page)
            Text(isChinese ? "Edit" : "Edit")
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
                insertActionButton(title: "Text", systemImage: "textformat", isActive: isTextActive) {
                    onInsertText()
                    activePanel = .edit
                }

                insertActionButton(title: "Shape", systemImage: "rectangle.roundedtop.fill", isActive: isRectActive) {
                    onInsertRoundedRect()
                    activePanel = .edit
                }

                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    insertActionLabel(
                        title: "Image",
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
        VStack(alignment: .leading, spacing: 10) {
            Text(isChinese ? "已选中原生课件元素" : "Selected Native Element")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))

            Text(nativeElementLabel(element))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)

            Text(
                isChinese
                    ? "该元素由节点内容自动生成，可在 Page 里修改对应的全局样式。"
                    : "This element is generated from node content. Use Page to adjust global style."
            )
            .font(.caption)
            .foregroundStyle(.white.opacity(0.76))

            Button {
                switch element {
                case .title:
                    selectedPageTextPreset = .h1
                case .subtitle:
                    selectedPageTextPreset = .h3
                case .levelChip:
                    selectedPageTextPreset = .h4
                case .toolkitIcon, .mainCard, .activityCard:
                    break
                }
                activePanel = .page
            } label: {
                Label(isChinese ? "跳转到 Page 样式" : "Go to Page Style", systemImage: "slider.horizontal.3")
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
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    @ViewBuilder
    private func imagePanel(for selectedOverlay: PresentationSlideOverlay) -> some View {
        if selectedOverlay.isImage {
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
                    onCropOverlay(overlay.id, currentCropRect())
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
        var nextTheme = textTheme
        var style = nextTheme.style(for: selectedPageTextPreset)
        update(&style)
        nextTheme.setStyle(style, for: selectedPageTextPreset)
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

                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(hex: pageStyle.cardBackgroundColorHex))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color(hex: pageStyle.cardBorderColorHex), lineWidth: 1)
                    )
                    .frame(width: 28)
            }
            .padding(6)

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
        case .mainCard:
            return isChinese ? "主内容卡片" : "Main Content Card"
        case .activityCard:
            return isChinese ? "活动卡片" : "Activity Card"
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

private struct DeferredCommitVectorSlider: View {
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

private extension Color {
    init(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleaned.hasPrefix("#") {
            cleaned.removeFirst()
        }
        if cleaned.count == 3 {
            cleaned = cleaned.map { "\($0)\($0)" }.joined()
        }
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else {
            self = Color.white
            return
        }
        let r = Double((value & 0xFF0000) >> 16) / 255.0
        let g = Double((value & 0x00FF00) >> 8) / 255.0
        let b = Double(value & 0x0000FF) / 255.0
        self = Color(red: r, green: g, blue: b)
    }

    #if canImport(UIKit)
    var hexString: String {
        let uiColor = UIColor(self)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        guard uiColor.getRed(&r, green: &g, blue: &b, alpha: &a) else {
            return "#FFFFFF"
        }
        return String(
            format: "#%02X%02X%02X",
            Int((r * 255).rounded()),
            Int((g * 255).rounded()),
            Int((b * 255).rounded())
        )
    }
    #endif
}

#if canImport(UIKit) && canImport(WebKit)
private struct PresentationSlideCanvasHTMLView: UIViewRepresentable {
    let baseHTML: String
    let textTheme: PresentationTextTheme
    let overlays: [PresentationSlideOverlay]
    let selectedOverlayID: UUID?
    let onSelectOverlay: (UUID?) -> Void
    let onCommitOverlayFrame: (UUID, CGPoint, CGFloat, CGFloat) -> Void
    let onRotateOverlay: (UUID, Double) -> Void
    let onCropOverlay: (UUID, CGRect) -> Void
    let onDeleteOverlay: (UUID) -> Void
    let onExtractOverlaySubject: (UUID) -> Void

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: PresentationSlideCanvasHTMLView
        var lastBaseHTML = ""
        var pendingPayloadBase64 = ""
        var pendingSelectedID = ""
        var isPageReady = false

        init(parent: PresentationSlideCanvasHTMLView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isPageReady = true
            pushPendingStateIfReady(webView)
        }

        func pushPendingStateIfReady(_ webView: WKWebView) {
            guard isPageReady else { return }
            let script = "window.__edunodeUpdate && window.__edunodeUpdate('\(pendingPayloadBase64)','\(pendingSelectedID)');"
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
                    self.parent.onCropOverlay(
                        id,
                        CGRect(x: x, y: y, width: width, height: height)
                    )
                case "delete":
                    guard let idString = body["id"] as? String,
                          let id = UUID(uuidString: idString) else { return }
                    self.parent.onDeleteOverlay(id)
                case "extract":
                    guard let idString = body["id"] as? String,
                          let id = UUID(uuidString: idString) else { return }
                    self.parent.onExtractOverlaySubject(id)
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
        context.coordinator.lastBaseHTML = baseHTML
        context.coordinator.pendingPayloadBase64 = payloadBase64
        context.coordinator.pendingSelectedID = selectedID
        context.coordinator.isPageReady = false
        let html = editorHTML(payloadBase64: payloadBase64, selectedID: selectedID)
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.parent = self
        let payloadBase64 = overlayPayloadBase64()
        let selectedID = selectedOverlayID?.uuidString ?? ""
        context.coordinator.pendingPayloadBase64 = payloadBase64
        context.coordinator.pendingSelectedID = selectedID

        if context.coordinator.lastBaseHTML != baseHTML {
            context.coordinator.lastBaseHTML = baseHTML
            context.coordinator.isPageReady = false
            let html = editorHTML(payloadBase64: payloadBase64, selectedID: selectedID)
            uiView.loadHTMLString(html, baseURL: nil)
            return
        }

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

    private func editorHTML(payloadBase64: String, selectedID: String) -> String {
        let baseHTMLBase64 = Data(baseHTML.utf8).base64EncodedString()

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
              border-radius: 18px;
              background: #000;
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
              overflow: hidden;
              border-radius: 10px;
              border: 1px solid rgba(255,255,255,0.14);
              will-change: left, top, width, height, transform;
            }
            .ov.selected {
              border: 2px solid #22d3ee;
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
            }
            .ov.rect { }
            .ov.icon {
              border-radius: 999px;
              font-size: 1.9cqw;
              line-height: 1;
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
            .ov.image.vectorized .svg-host {
              width: 100%;
              height: 100%;
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
              baseFrame.srcdoc = b64ToUtf8('\(baseHTMLBase64)');

              let overlays = JSON.parse(b64ToUtf8('\(payloadBase64)'));
              let selectedID = '\(selectedID)';
              const layer = document.getElementById('overlayLayer');

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
                pendingSelectedID: null
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
                const minSize = 0.18;
                const rect = { x: 0, y: 0, width: 1, height: 1 };
                switch (handleType) {
                  case 'crop-left': {
                    const cut = clamp(dx, 0, maxCut);
                    rect.x = cut;
                    rect.width = Math.max(minSize, 1 - cut);
                    break;
                  }
                  case 'crop-right': {
                    const cut = clamp(-dx, 0, maxCut);
                    rect.width = Math.max(minSize, 1 - cut);
                    break;
                  }
                  case 'crop-top': {
                    const cut = clamp(dy, 0, maxCut);
                    rect.y = cut;
                    rect.height = Math.max(minSize, 1 - cut);
                    break;
                  }
                  case 'crop-bottom': {
                    const cut = clamp(-dy, 0, maxCut);
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
                    el.style.fontSize = Math.max(12, Math.min(96, ov.textSize)) + 'px';
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
                    if (ov.svgMarkup && ov.svgMarkup.trim().length > 0) {
                      el.classList.add('vectorized');
                      const svgBG = document.createElement('div');
                      svgBG.className = 'svg-bg';
                      svgBG.style.background = ov.vectorBackgroundVisible
                        ? (ov.vectorBackgroundColor || '#FFFFFF')
                        : 'transparent';
                      svgBG.style.filter = ov.imageFilter || 'none';

                      const svgHost = document.createElement('div');
                      svgHost.className = 'svg-host';
                      svgHost.innerHTML = ov.svgMarkup;
                      svgBG.appendChild(svgHost);
                      el.appendChild(svgBG);
                    } else {
                      if (ov.pixelated) {
                        el.classList.add('pixelated');
                      }
                      const img = document.createElement('img');
                      img.src = ov.imageDataURI || '';
                      img.alt = 'Overlay Image';
                      img.style.filter = ov.imageFilter || 'none';
                      el.appendChild(img);
                    }
                  }

                  if (ov.id === selectedID) {
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
                  }
                });
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

              layer.addEventListener('pointerdown', (event) => {
                const ovEl = event.target.closest('.ov');
                if (!ovEl) {
                  select('');
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

                if (ov.kind === 'image' && !isResize && !isRotate && !isCrop && !pointerHitsImageContent(event, ov, ovEl)) {
                  select('');
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
                const longPressEligible = ov.kind === 'image' && !isResize && !isRotate && !isCrop;
                const longPressDuration = 460;
                dragRuntime.active = true;
                dragRuntime.pendingPayloadBase64 = null;
                dragRuntime.pendingSelectedID = null;

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
                      height: latestCropRect.height
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
                    dragRuntime.pendingPayloadBase64 = null;
                    dragRuntime.pendingSelectedID = null;
                  }
                  render();
                }

                window.addEventListener('pointermove', onMove);
                window.addEventListener('pointerup', onEnd, { once: true });
                window.addEventListener('pointercancel', onEnd, { once: true });
                event.preventDefault();
              });

              layer.addEventListener('click', (event) => {
                if (!event.target.closest('.ov')) {
                  select('');
                }
              });

              window.addEventListener('keydown', (event) => {
                if ((event.key === 'Backspace' || event.key === 'Delete') && selectedID) {
                  post({ type: 'delete', id: selectedID });
                  selectedID = '';
                  render();
                }
              });

              window.__edunodeUpdate = function (payloadBase64, nextSelectedID) {
                if (dragRuntime.active) {
                  dragRuntime.pendingPayloadBase64 = payloadBase64;
                  dragRuntime.pendingSelectedID = (nextSelectedID || '');
                  return;
                }
                try {
                  overlays = JSON.parse(b64ToUtf8(payloadBase64));
                } catch (_) {
                  overlays = [];
                }
                selectedID = (nextSelectedID || '');
                render();
              };

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

private struct PresentationSVGOverlayView: UIViewRepresentable {
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
private struct PresentationSlideCanvasHTMLView: View {
    let baseHTML: String
    let overlays: [PresentationSlideOverlay]
    let selectedOverlayID: UUID?
    let onSelectOverlay: (UUID?) -> Void
    let onCommitOverlayFrame: (UUID, CGPoint, CGFloat, CGFloat) -> Void
    let onDeleteOverlay: (UUID) -> Void
    let onExtractOverlaySubject: (UUID) -> Void

    var body: some View {
        Text(baseHTML)
            .font(.caption2.monospaced())
    }
}

private struct PresentationSVGOverlayView: View {
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
