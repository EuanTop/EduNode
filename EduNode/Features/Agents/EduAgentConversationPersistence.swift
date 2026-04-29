import Foundation

enum EduAgentConversationPersistence {
    private struct WorkspaceStore: Codable {
        var conversations: [UUID: [EduAgentConversationMessage]]
    }

    struct LessonPlanSnapshot: Codable {
        var conversation: [EduAgentConversationMessage]
        var generatedMarkdown: String?
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder = JSONDecoder()

    static func loadWorkspaceConversations() -> [UUID: [EduAgentConversationMessage]] {
        guard let data = try? Data(contentsOf: workspaceConversationsURL),
              let store = try? decoder.decode(WorkspaceStore.self, from: data) else {
            return [:]
        }
        return store.conversations
    }

    static func saveWorkspaceConversations(_ conversations: [UUID: [EduAgentConversationMessage]]) {
        let trimmed = conversations.compactMapValues { messages in
            let limited = messages.suffix(80)
            return limited.isEmpty ? nil : Array(limited)
        }
        write(WorkspaceStore(conversations: trimmed), to: workspaceConversationsURL)
    }

    static func loadLessonPlanSnapshot(fileID: UUID) -> LessonPlanSnapshot? {
        let url = lessonPlanConversationURL(fileID: fileID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(LessonPlanSnapshot.self, from: data)
    }

    static func saveLessonPlanSnapshot(_ snapshot: LessonPlanSnapshot, fileID: UUID) {
        let trimmed = LessonPlanSnapshot(
            conversation: Array(snapshot.conversation.suffix(80)),
            generatedMarkdown: snapshot.generatedMarkdown
        )
        write(trimmed, to: lessonPlanConversationURL(fileID: fileID))
    }

    private static func write<T: Encodable>(_ value: T, to url: URL) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(value)
            try data.write(to: url, options: [.atomic])
        } catch {
            NSLog("EduNode conversation persistence failed: %@", error.localizedDescription)
        }
    }

    private static var workspaceConversationsURL: URL {
        storageDirectory.appendingPathComponent("workspace-agent-conversations.json")
    }

    private static func lessonPlanConversationURL(fileID: UUID) -> URL {
        storageDirectory
            .appendingPathComponent("lesson-plan-conversations", isDirectory: true)
            .appendingPathComponent("\(fileID.uuidString).json")
    }

    private static var storageDirectory: URL {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base
            .appendingPathComponent("EduNode", isDirectory: true)
            .appendingPathComponent("AgentConversations", isDirectory: true)
    }
}
