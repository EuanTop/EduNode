import Foundation

enum EduCanvasRecommendationEngine {
    static func recommendations(
        for file: GNodeWorkspaceFile,
        limit: Int = 3
    ) -> [EduCanvasRecommendation] {
        let isChinese = Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
        let snapshot = EduAgentContextBuilder.workspaceSnapshot(file: file)
        let course = EduAgentLogicAdapter.courseContext(file: file)
        let graph = EduAgentLogicAdapter.graphContext(snapshot: snapshot)
        return EduCanvasRecommendationCoreEngine.recommendations(
            course: course,
            graph: graph,
            isChinese: isChinese,
            limit: limit
        )
    }
}
