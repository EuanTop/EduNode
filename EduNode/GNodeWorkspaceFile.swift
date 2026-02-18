import Foundation
import SwiftData

@Model
final class GNodeWorkspaceFile {
    @Attribute(.unique) var id: UUID
    var name: String
    var data: Data
    var createdAt: Date
    var updatedAt: Date
    var gradeLevel: String
    var gradeMode: String
    var gradeMin: Int
    var gradeMax: Int
    var subject: String
    var lessonDurationMinutes: Int
    var allowOvertime: Bool
    var periodRange: String
    var studentCount: Int
    var studentProfile: String
    var studentPriorKnowledgeLevel: String
    var studentMotivationLevel: String
    var studentSupportNotes: String
    var goalsText: String
    var modelID: String
    var teacherTeam: String
    var leadTeacherCount: Int
    var assistantTeacherCount: Int
    var teacherRolePlan: String
    var learningScenario: String
    var curriculumStandard: String
    var resourceConstraints: String
    var lessonPlanMarkedDone: Bool
    var evaluationMarkedDone: Bool

    init(
        id: UUID = UUID(),
        name: String,
        data: Data,
        gradeLevel: String = "",
        gradeMode: String = "grade",
        gradeMin: Int = 1,
        gradeMax: Int = 1,
        subject: String = "",
        lessonDurationMinutes: Int = 45,
        allowOvertime: Bool = false,
        periodRange: String = "",
        studentCount: Int = 0,
        studentProfile: String = "",
        studentPriorKnowledgeLevel: String = "medium",
        studentMotivationLevel: String = "medium",
        studentSupportNotes: String = "",
        goalsText: String = "",
        modelID: String = "",
        teacherTeam: String = "",
        leadTeacherCount: Int = 1,
        assistantTeacherCount: Int = 0,
        teacherRolePlan: String = "",
        learningScenario: String = "",
        curriculumStandard: String = "",
        resourceConstraints: String = "",
        lessonPlanMarkedDone: Bool = false,
        evaluationMarkedDone: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.data = data
        self.gradeLevel = gradeLevel
        self.gradeMode = gradeMode
        self.gradeMin = gradeMin
        self.gradeMax = gradeMax
        self.subject = subject
        self.lessonDurationMinutes = lessonDurationMinutes
        self.allowOvertime = allowOvertime
        self.periodRange = periodRange
        self.studentCount = studentCount
        self.studentProfile = studentProfile
        self.studentPriorKnowledgeLevel = studentPriorKnowledgeLevel
        self.studentMotivationLevel = studentMotivationLevel
        self.studentSupportNotes = studentSupportNotes
        self.goalsText = goalsText
        self.modelID = modelID
        self.teacherTeam = teacherTeam
        self.leadTeacherCount = leadTeacherCount
        self.assistantTeacherCount = assistantTeacherCount
        self.teacherRolePlan = teacherRolePlan
        self.learningScenario = learningScenario
        self.curriculumStandard = curriculumStandard
        self.resourceConstraints = resourceConstraints
        self.lessonPlanMarkedDone = lessonPlanMarkedDone
        self.evaluationMarkedDone = evaluationMarkedDone
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
