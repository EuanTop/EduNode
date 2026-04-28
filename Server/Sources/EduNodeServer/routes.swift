import Vapor
import EduNodeContracts
import EduNodeBackendCore

private struct EduHealthResponse: Content {
    let status: String
    let service: String
}

private struct EduAuthenticatedSessionStorageKey: StorageKey {
    typealias Value = EduAuthenticatedSession
}

private extension Request {
    var eduAuthenticatedSession: EduAuthenticatedSession? {
        get { storage[EduAuthenticatedSessionStorageKey.self] }
        set { storage[EduAuthenticatedSessionStorageKey.self] = newValue }
    }
}

private struct EduServerSessionAuthMiddleware: AsyncMiddleware {
    let authManager: EduServerAuthManager

    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let receivedToken = request.headers.bearerAuthorization?.token
        guard let receivedToken, !receivedToken.isEmpty else {
            throw Abort(.unauthorized, reason: "Missing account access token.")
        }

        do {
            request.eduAuthenticatedSession = try await authManager.validate(token: receivedToken)
        } catch EduServerAuthError.authNotConfigured {
            throw Abort(.serviceUnavailable, reason: "Account authentication is not configured on the server.")
        } catch EduServerAuthError.expiredToken {
            throw Abort(.unauthorized, reason: "Account session expired.")
        } catch {
            throw Abort(.unauthorized, reason: "Invalid account access token.")
        }
        return try await next.respond(to: request)
    }
}

func routes(_ app: Application) throws {
    app.get("health") { _ in
        EduHealthResponse(status: "ok", service: "EduNodeServer")
    }

    let authManager = EduServerAuthManager(
        configuration: app.eduServerRuntimeConfiguration.supabaseConfiguration
    )
    let protectedGroup = app.grouped(
        EduServerSessionAuthMiddleware(authManager: authManager)
    )

    let service = EduCanvasAgentService(
        mode: app.eduServerRuntimeConfiguration.agentMode,
        settings: app.eduServerRuntimeConfiguration.llmSettings
    )

    app.post("auth", "sign-in") { request async throws -> EduBackendAuthTokenSessionResponse in
        let payload = try request.content.decode(EduBackendAuthEmailPasswordRequest.self)
        do {
            return try await authManager.signIn(
                email: payload.email,
                password: payload.password
            )
        } catch EduServerAuthError.authNotConfigured {
            throw Abort(.serviceUnavailable, reason: "Account authentication is not configured on the server.")
        } catch EduServerAuthError.upstreamUnavailable(let message) {
            throw Abort(.badRequest, reason: message)
        } catch {
            throw Abort(.badRequest, reason: error.localizedDescription)
        }
    }

    app.post("auth", "sign-up") { request async throws -> EduBackendAuthSignUpResponse in
        let payload = try request.content.decode(EduBackendAuthEmailPasswordRequest.self)
        do {
            return try await authManager.signUp(
                email: payload.email,
                password: payload.password
            )
        } catch EduServerAuthError.authNotConfigured {
            throw Abort(.serviceUnavailable, reason: "Account authentication is not configured on the server.")
        } catch EduServerAuthError.upstreamUnavailable(let message) {
            throw Abort(.badRequest, reason: message)
        } catch {
            throw Abort(.badRequest, reason: error.localizedDescription)
        }
    }

    app.post("auth", "refresh") { request async throws -> EduBackendAuthTokenSessionResponse in
        let payload = try request.content.decode(EduBackendAuthRefreshRequest.self)
        do {
            return try await authManager.refresh(refreshToken: payload.refreshToken)
        } catch EduServerAuthError.authNotConfigured {
            throw Abort(.serviceUnavailable, reason: "Account authentication is not configured on the server.")
        } catch EduServerAuthError.invalidToken {
            throw Abort(.unauthorized, reason: "Invalid refresh token.")
        } catch EduServerAuthError.upstreamUnavailable(let message) {
            let status: HTTPResponseStatus = message.lowercased().contains("refresh token") ? .unauthorized : .badRequest
            throw Abort(status, reason: message)
        } catch {
            throw Abort(.unauthorized, reason: error.localizedDescription)
        }
    }

    protectedGroup.get("auth", "session") { request async throws -> EduBackendAuthSessionStatusResponse in
        guard let accessToken = request.headers.bearerAuthorization?.token else {
            throw Abort(.unauthorized)
        }
        do {
            return try await authManager.sessionStatus(for: accessToken)
        } catch EduServerAuthError.expiredToken {
            throw Abort(.unauthorized, reason: "Account session expired.")
        } catch EduServerAuthError.invalidToken {
            throw Abort(.unauthorized, reason: "Invalid account access token.")
        } catch EduServerAuthError.authNotConfigured {
            throw Abort(.serviceUnavailable, reason: "Account authentication is not configured on the server.")
        } catch {
            throw Abort(.unauthorized)
        }
    }

    protectedGroup.post("auth", "sign-out") { request async -> HTTPStatus in
        if let accessToken = request.headers.bearerAuthorization?.token {
            await authManager.signOut(accessToken: accessToken)
        }
        return .ok
    }

    protectedGroup.get("agent", "runtime") { _ async -> EduAgentRuntimeStatusResponse in
        await service.runtimeStatus()
    }

    protectedGroup.on(.POST, "llm", "complete", body: .collect(maxSize: "8mb")) { request async throws -> EduBackendLLMCompletionResponse in
        let payload = try request.content.decode(EduBackendLLMCompletionRequest.self)
        let client = EduBackendOpenAICompatibleClient(
            settings: app.eduServerRuntimeConfiguration.llmSettings
        )
        do {
            let content = try await client.complete(messages: payload.messages)
            return EduBackendLLMCompletionResponse(content: content)
        } catch {
            throw Abort(.badGateway, reason: error.localizedDescription)
        }
    }

    protectedGroup.on(.POST, "reference", "parse-pdf", body: .collect(maxSize: "20mb")) { request async throws -> EduBackendReferenceParsePDFResponse in
        let payload = try request.content.decode(EduBackendReferenceParsePDFRequest.self)
        guard let minerUSettings = app.eduServerRuntimeConfiguration.minerUSettings else {
            throw Abort(.serviceUnavailable, reason: "MinerU is not configured on the backend.")
        }
        let client = EduBackendMinerUClient(settings: minerUSettings)
        do {
            return try await client.parseReferencePDF(
                base64EncodedFileData: payload.fileDataBase64,
                fileName: payload.fileName
            )
        } catch {
            throw Abort(.badGateway, reason: error.localizedDescription)
        }
    }

    let canvas = protectedGroup.grouped("canvas")

    canvas.post("respond") { request async throws -> EduAgentGraphOperationEnvelope in
        let payload = try request.content.decode(EduCanvasAgentAutoRequest.self)
        do {
            return try await service.respond(payload)
        } catch {
            throw Abort(.badGateway, reason: error.localizedDescription)
        }
    }

    canvas.post("suggested-prompts") { request async throws -> EduAgentSuggestedPromptsResponse in
        let payload = try request.content.decode(EduCanvasSuggestedPromptsRequest.self)
        do {
            return try await service.suggestedPrompts(payload)
        } catch {
            throw Abort(.badGateway, reason: error.localizedDescription)
        }
    }
}
