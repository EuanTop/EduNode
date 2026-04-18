import SwiftUI

struct EduWorkspaceAgentFloatingButton: View {
    let isChinese: Bool
    let containerSize: CGSize
    let safeAreaInsets: EdgeInsets
    let action: () -> Void

    private let diameter: CGFloat = 60
    private let trailingInset: CGFloat = 22
    private let bottomInset: CGFloat = 68

    var body: some View {
        let origin = CGPoint(
            x: baseCenter.x - (diameter / 2),
            y: baseCenter.y - (diameter / 2)
        )

        ZStack(alignment: .topLeading) {
            buttonFace
                .offset(x: origin.x, y: origin.y)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var buttonFace: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )

            EduAgentBotGlyph()
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: .black.opacity(0.26), radius: 14, y: 8)
        .contentShape(Circle())
        .onTapGesture(perform: action)
        .accessibilityLabel(isChinese ? "打开 Agent 侧栏" : "Open Agent sidebar")
        .accessibilityHint(isChinese ? "固定在右下角的 Agent 入口" : "Fixed bottom-right Agent entry")
    }

    private var baseCenter: CGPoint {
        CGPoint(
            x: containerSize.width - safeAreaInsets.trailing - trailingInset - (diameter / 2),
            y: containerSize.height - safeAreaInsets.bottom - bottomInset - (diameter / 2)
        )
    }
}

private struct EduAgentBotGlyph: View {
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                Capsule()
                    .fill(Color.teal.opacity(0.95))
                    .frame(width: 3, height: 6)
                Circle()
                    .fill(Color.teal.opacity(0.95))
                    .frame(width: 6, height: 6)
                    .offset(y: -1)
            }
            .offset(y: -15)

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.teal.opacity(0.95), Color.cyan.opacity(0.84)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 30, height: 24)

            HStack(spacing: 8) {
                Circle()
                    .fill(Color.white.opacity(0.96))
                    .frame(width: 4.5, height: 4.5)
                Circle()
                    .fill(Color.white.opacity(0.96))
                    .frame(width: 4.5, height: 4.5)
            }
            .offset(y: -2)

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.white.opacity(0.92))
                .frame(width: 12, height: 3)
                .offset(y: 6)
        }
        .frame(width: 34, height: 34)
    }
}
