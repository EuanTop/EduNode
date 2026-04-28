import Foundation
import EduNodeContracts

public enum EduCanvasAgentServiceMode: String, Sendable {
    case live
    case mock
}

public struct EduCanvasAgentService: Sendable {
    private let mode: EduCanvasAgentServiceMode
    private let settings: EduAgentProviderSettingsResolved

    public init(
        mode: EduCanvasAgentServiceMode = .live,
        settings: EduAgentProviderSettingsResolved
    ) {
        self.mode = mode
        self.settings = settings
    }

    public func respond(
        _ request: EduCanvasAgentAutoRequest
    ) async throws -> EduAgentGraphOperationEnvelope {
        if mode == .mock {
            return EduCanvasAgentMockEngine.respond(to: request)
        }

        let client = EduBackendOpenAICompatibleClient(settings: settings)

        var planningArtifact: EduAgentThinkingPlanResponse?
        if request.thinkingEnabled,
           let planningReply = try? await client.complete(
                messages: EduCanvasAgentPromptBuilder.workspacePlanningMessages(
                    request: request,
                    settings: settings
                )
           ),
           let plan = try? EduBackendAgentJSONParser.decodeFirstJSONObject(
                EduAgentThinkingPlanResponse.self,
                from: planningReply
           ) {
            planningArtifact = plan
        }

        let reply = try await client.complete(
            messages: EduCanvasAgentPromptBuilder.workspaceAutoMessages(
                request: request,
                settings: settings,
                thinkingPlan: planningArtifact
            )
        )

        if let structured = try? EduBackendAgentJSONParser.decodeFirstJSONObject(
            EduAgentGraphOperationEnvelope.self,
            from: reply
        ) {
            return structured
        }

        return EduAgentGraphOperationEnvelope(
            assistantReply: reply,
            thinkingTraceMarkdown: planningArtifact?.thinkingTraceMarkdown,
            operations: []
        )
    }

    public func suggestedPrompts(
        _ request: EduCanvasSuggestedPromptsRequest
    ) async throws -> EduAgentSuggestedPromptsResponse {
        if mode == .mock {
            return EduCanvasAgentMockEngine.suggestedPrompts(for: request)
        }

        let client = EduBackendOpenAICompatibleClient(settings: settings)
        let reply = try await client.complete(
            messages: EduCanvasAgentPromptBuilder.workspaceSuggestedPromptMessages(
                request: request,
                settings: settings
            )
        )
        return try EduBackendAgentJSONParser.decodeFirstJSONObject(
            EduAgentSuggestedPromptsResponse.self,
            from: reply
        )
    }

    public func runtimeStatus() async -> EduAgentRuntimeStatusResponse {
        let trimmedProvider = settings.providerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = settings.trimmedModel
        let baseURLHost = settings.baseURLHost

        guard mode != .mock else {
            return EduAgentRuntimeStatusResponse(
                llmConfigured: true,
                providerReachable: true,
                providerName: trimmedProvider.isEmpty ? "Mock" : trimmedProvider,
                activeModel: trimmedModel.isEmpty ? "mock-model" : trimmedModel,
                baseURLHost: baseURLHost,
                availableModels: trimmedModel.isEmpty ? [] : [trimmedModel],
                message: "Mock agent mode is active."
            )
        }

        guard settings.isConfigured else {
            return EduAgentRuntimeStatusResponse(
                llmConfigured: false,
                providerReachable: false,
                providerName: trimmedProvider,
                activeModel: trimmedModel,
                baseURLHost: baseURLHost,
                availableModels: [],
                message: "Server-side LLM configuration is incomplete."
            )
        }

        let client = EduBackendOpenAICompatibleClient(settings: settings)
        do {
            let models = try await client.listModels()
            let message = models.isEmpty
                ? "Connected to the configured provider, but no models were returned."
                : "Connected to the configured provider."
            return EduAgentRuntimeStatusResponse(
                llmConfigured: true,
                providerReachable: true,
                providerName: trimmedProvider,
                activeModel: trimmedModel,
                baseURLHost: baseURLHost,
                availableModels: models,
                message: message
            )
        } catch {
            return EduAgentRuntimeStatusResponse(
                llmConfigured: true,
                providerReachable: false,
                providerName: trimmedProvider,
                activeModel: trimmedModel,
                baseURLHost: baseURLHost,
                availableModels: [],
                message: error.localizedDescription
            )
        }
    }
}
