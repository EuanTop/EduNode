import Foundation

enum EduAgentLogicAdapter {
    static func courseContext(
        file: GNodeWorkspaceFile,
        modelFocus: String = ""
    ) -> EduAgentCourseContext {
        EduAgentCourseContext(
            subject: file.subject,
            goals: normalizedLines(file.goalsText),
            modelFocus: modelFocus,
            teachingStyle: file.teachingStyle,
            formativeCheckIntensity: file.formativeCheckIntensity,
            emphasizeInquiryExperiment: file.emphasizeInquiryExperiment,
            emphasizeExperienceReflection: file.emphasizeExperienceReflection,
            requireStructuredFlow: file.requireStructuredFlow,
            studentCount: file.studentCount,
            studentPriorKnowledgeScore: Int(file.studentPriorKnowledgeLevel) ?? 70,
            studentMotivationScore: Int(file.studentMotivationLevel) ?? 75,
            studentSupportNotes: file.studentSupportNotes,
            resourceConstraints: file.resourceConstraints,
            lessonDurationMinutes: file.lessonDurationMinutes
        )
    }

    static func graphContext(snapshot: EduAgentWorkspaceSnapshot) -> EduAgentGraphContext {
        EduAgentGraphContext(
            nodes: snapshot.nodes.map { node in
                EduAgentGraphNodeContext(
                    id: node.id,
                    nodeFamily: node.nodeFamily,
                    title: node.title,
                    textValue: node.textValue,
                    selectedOption: node.selectedOption,
                    selectedMethodID: node.selectedMethodID,
                    incomingNodeIDs: node.incomingNodeIDs,
                    outgoingNodeIDs: node.outgoingNodeIDs,
                    incomingTitles: node.incomingTitles,
                    outgoingTitles: node.outgoingTitles,
                    textFields: node.textFields.map {
                        EduAgentGraphFieldContext(id: $0.id, label: $0.label, value: $0.value)
                    },
                    optionFields: node.optionFields.map {
                        EduAgentGraphFieldContext(id: $0.id, label: $0.label, value: $0.value)
                    }
                )
            },
            totalConnections: snapshot.connections.count
        )
    }

    private static func normalizedLines(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
