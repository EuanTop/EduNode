import SwiftUI

enum EduFlowStep: String, CaseIterable, Identifiable {
    case basicInfo
    case modelSelection
    case knowledgeToolkit
    case evaluationDesign
    case lessonPlan
    case evaluationSummary

    var id: String { rawValue }

    func title(_ S: (String) -> String) -> String {
        switch self {
        case .basicInfo: return S("flow.basicInfo")
        case .modelSelection: return S("flow.modelSelection")
        case .knowledgeToolkit: return S("flow.knowledgeToolkit")
        case .evaluationDesign: return S("flow.evaluationDesign")
        case .lessonPlan: return S("flow.lessonPlan")
        case .evaluationSummary: return S("flow.evaluationSummary")
        }
    }
}

struct EduFlowStepState: Identifiable {
    let step: EduFlowStep
    let index: Int
    let isDone: Bool
    let isManual: Bool
    let canToggle: Bool

    var id: EduFlowStep { step }
}

struct EduFlowProgressView: View {
    let states: [EduFlowStepState]
    let onToggleManual: (EduFlowStep) -> Void

    private let containerBackground = Color(red: 0.10, green: 0.11, blue: 0.13)
    private let chipTextColor = Color.white.opacity(0.92)
    private let chipHintColor = Color.white.opacity(0.66)

    var body: some View {
        HStack(spacing: 8) {
            ForEach(states) { state in
                stepChip(state)
                .contentShape(Capsule())
                .onTapGesture {
                    guard state.isManual, state.canToggle else { return }
                    onToggleManual(state.step)
                }
                .allowsHitTesting(state.isManual ? state.canToggle : false)
                .opacity((state.isManual && !state.canToggle) ? 0.72 : 1.0)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .eduProgressContainerStyle(containerBackground: containerBackground)
        .environment(\.isEnabled, true)
        .opacity(1)
        .compositingGroup()
    }

    private func stepChip(_ state: EduFlowStepState) -> some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(state.isDone ? Color.green.opacity(0.9) : Color.white.opacity(0.16))
                    .frame(width: 18, height: 18)
                if state.isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(state.index)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }

            Text(state.step.title(S))
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(chipTextColor)

            if state.isManual {
                Text(state.isDone ? S("flow.marked") : S("flow.tapToMark"))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(chipHintColor)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(state.isDone ? Color.green.opacity(0.16) : Color.clear)
        )
    }

    private func S(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }
}

private extension View {
    @ViewBuilder
    func eduProgressContainerStyle(containerBackground: Color) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self
                .background {
                    Button(action: {}) {
                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .buttonStyle(GlassButtonStyle())
                    .allowsHitTesting(false)
                }
                .clipShape(Capsule())
        } else {
            self
                .background(
                    Capsule()
                        .fill(containerBackground)
                )
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
        }
    }
}
