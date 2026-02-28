import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

func normalizedHex(_ raw: String, fallback: String) -> String {
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

extension Color {
    init(hex: String) {
        let normalized = normalizedHex(hex, fallback: "#FFFFFF")
        let cleaned = String(normalized.dropFirst())
        guard let value = UInt64(cleaned, radix: 16) else {
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
