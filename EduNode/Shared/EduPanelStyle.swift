import SwiftUI

enum EduPanelStyle {
    static let sheetCornerRadius: CGFloat = 22
    static let cardCornerRadius: CGFloat = 16

    static let sheetBase = Color(white: 0.075)
    static let headerBase = Color(white: 0.085)
    static let sidebarBase = Color(white: 0.09)
    static let divider = Color.white.opacity(0.08)
    static let cardFill = Color.white.opacity(0.055)
    static let cardStroke = Color.white.opacity(0.10)
    static let controlFill = Color.white.opacity(0.08)

    static var sheetBackground: some View {
        ZStack {
            sheetBase
            LinearGradient(
                colors: [
                    Color.white.opacity(0.035),
                    Color.black.opacity(0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

extension View {
    func eduSheetChrome() -> some View {
        background(EduPanelStyle.sheetBackground)
            .preferredColorScheme(.dark)
    }

    func eduPanelCard(cornerRadius: CGFloat = EduPanelStyle.cardCornerRadius) -> some View {
        background(EduPanelStyle.cardFill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(EduPanelStyle.cardStroke, lineWidth: 1)
            )
    }

}
