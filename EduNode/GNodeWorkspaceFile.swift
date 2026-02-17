import Foundation
import SwiftData

@Model
final class GNodeWorkspaceFile {
    @Attribute(.unique) var id: UUID
    var name: String
    var data: Data
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        data: Data,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.data = data
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
