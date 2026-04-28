import Foundation

struct EduWorkspaceAgentService {
    let apiClient: EduBackendAPIClient

    init?(backendConfig: EduBackendServiceConfig? = EduBackendServiceConfig.loadOptional()) {
        guard let apiClient = EduBackendAPIClient(backendConfig: backendConfig) else { return nil }
        self.apiClient = apiClient
    }

    func send(
        file: GNodeWorkspaceFile,
        conversation: [EduAgentConversationMessage],
        userRequest: String,
        supplementaryMaterial: String,
        thinkingEnabled: Bool
    ) async throws -> EduAgentGraphOperationEnvelope {
        let payload = EduCanvasAgentAutoRequest(
            workspace: EduAgentContextBuilder.workspaceSnapshot(file: file),
            schema: EduAgentContextBuilder.canvasSchema(),
            conversation: conversationPayload(from: conversation),
            userRequest: userRequest,
            supplementaryMaterial: supplementaryMaterial,
            thinkingEnabled: thinkingEnabled,
            interfaceLanguageCode: interfaceLanguageCode
        )

        return try await apiClient.postJSON(
            path: ["canvas", "respond"],
            requestBody: payload,
            responseType: EduAgentGraphOperationEnvelope.self
        )
    }

    func suggestedPrompts(
        file: GNodeWorkspaceFile,
        supplementaryMaterial: String
    ) async throws -> [String] {
        let payload = EduCanvasSuggestedPromptsRequest(
            workspace: EduAgentContextBuilder.workspaceSnapshot(file: file),
            supplementaryMaterial: supplementaryMaterial,
            interfaceLanguageCode: interfaceLanguageCode
        )

        let response: EduAgentSuggestedPromptsResponse = try await apiClient.postJSON(
            path: ["canvas", "suggested-prompts"],
            requestBody: payload,
            responseType: EduAgentSuggestedPromptsResponse.self
        )
        return response.suggestions
    }

    func runtimeStatus() async throws -> EduAgentRuntimeStatusResponse {
        let response: EduAgentRuntimeStatusResponse = try await apiClient.getJSON(
            path: ["agent", "runtime"],
            responseType: EduAgentRuntimeStatusResponse.self
        )
        EduBackendRuntimeStatusStore.save(response)
        return response
    }

    private var interfaceLanguageCode: String {
        Locale.preferredLanguages.first ?? "en"
    }

    private func conversationPayload(
        from messages: [EduAgentConversationMessage]
    ) -> [EduAgentConversationTurn] {
        messages.map {
            EduAgentConversationTurn(
                role: $0.role.rawValue,
                content: $0.content
            )
        }
    }
}
