import Foundation

enum EduBackendAPIError: LocalizedError {
    case backendNotConfigured
    case authenticationRequired
    case sessionExpired
    case requestFailed(String)
    case decodingFailed

    var errorDescription: String? {
        let isChinese = Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
        switch self {
        case .backendNotConfigured:
            return isChinese ? "当前应用尚未连接 EduNode 在线服务。" : "The app is not connected to EduNode online service yet."
        case .authenticationRequired:
            return isChinese ? "请先登录 EduNode 账户。" : "Please sign in to your EduNode account first."
        case .sessionExpired:
            return isChinese ? "账户登录态已失效，请重新登录。" : "The account session expired. Please sign in again."
        case .requestFailed(let message):
            return message
        case .decodingFailed:
            return isChinese ? "后端返回无法解析。" : "The backend response could not be decoded."
        }
    }
}

struct EduBackendAPIClient {
    let backendConfig: EduBackendServiceConfig

    init?(backendConfig: EduBackendServiceConfig? = EduBackendServiceConfig.loadOptional()) {
        guard let backendConfig else { return nil }
        self.backendConfig = backendConfig
    }

    func getJSON<ResponseBody: Decodable>(
        path: [String],
        requiresAuth: Bool = true,
        responseType: ResponseBody.Type
    ) async throws -> ResponseBody {
        let hadSessionBeforeRequest = EduBackendSessionStore.load() != nil
        let data = try await sendWithSessionRecovery(
            path: path,
            method: "GET",
            body: nil,
            timeout: 45,
            requiresAuth: requiresAuth,
            hadSessionBeforeRequest: requiresAuth && hadSessionBeforeRequest
        )
        do {
            return try JSONDecoder().decode(responseType, from: data)
        } catch {
            throw EduBackendAPIError.decodingFailed
        }
    }

    func postJSON<RequestBody: Encodable, ResponseBody: Decodable>(
        path: [String],
        requiresAuth: Bool = true,
        requestBody: RequestBody,
        responseType: ResponseBody.Type,
        timeout: TimeInterval = 105
    ) async throws -> ResponseBody {
        let body = try JSONEncoder().encode(requestBody)
        let hadSessionBeforeRequest = EduBackendSessionStore.load() != nil
        let data = try await sendWithSessionRecovery(
            path: path,
            method: "POST",
            body: body,
            timeout: timeout,
            requiresAuth: requiresAuth,
            hadSessionBeforeRequest: requiresAuth && hadSessionBeforeRequest
        )
        do {
            return try JSONDecoder().decode(responseType, from: data)
        } catch {
            throw EduBackendAPIError.decodingFailed
        }
    }

    private func makeRequest(
        path: [String],
        method: String,
        accessToken: String?,
        body: Data?,
        timeout: TimeInterval
    ) throws -> URLRequest {
        var url = backendConfig.baseURL
        for component in path {
            url.append(path: component)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = body
        return request
    }

    private func send(
        _ request: URLRequest,
        requiresAuth: Bool,
        hadSessionBeforeRequest: Bool,
        clearSessionOnUnauthorized: Bool
    ) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw EduBackendAPIError.requestFailed("Missing HTTP response from EduNode backend.")
        }

        if http.statusCode == 401 {
            if !requiresAuth {
                let message = String(data: data, encoding: .utf8) ?? "HTTP 401"
                throw EduBackendAPIError.requestFailed(message)
            }
            if clearSessionOnUnauthorized {
                EduBackendSessionStore.clear()
            }
            throw hadSessionBeforeRequest ? EduBackendAPIError.sessionExpired : EduBackendAPIError.authenticationRequired
        }

        guard (200..<300).contains(http.statusCode) else {
            let message = decodedBackendErrorMessage(from: data).nonEmpty ?? "HTTP \(http.statusCode)"
            throw EduBackendAPIError.requestFailed(message)
        }

        return data
    }

    private func sendWithSessionRecovery(
        path: [String],
        method: String,
        body: Data?,
        timeout: TimeInterval,
        requiresAuth: Bool,
        hadSessionBeforeRequest: Bool
    ) async throws -> Data {
        let accessToken = try await resolvedAccessTokenIfNeeded(requiresAuth: requiresAuth)
        let request = try makeRequest(
            path: path,
            method: method,
            accessToken: accessToken,
            body: body,
            timeout: timeout
        )

        do {
            return try await send(
                request,
                requiresAuth: requiresAuth,
                hadSessionBeforeRequest: hadSessionBeforeRequest,
                clearSessionOnUnauthorized: !hadSessionBeforeRequest
            )
        } catch EduBackendAPIError.sessionExpired where requiresAuth && hadSessionBeforeRequest {
            guard let authService = EduBackendAuthService(backendConfig: backendConfig) else {
                EduBackendSessionStore.clear()
                throw EduBackendAPIError.backendNotConfigured
            }

            do {
                let refreshedSession = try await authService.forceRefreshStoredSession()
                let retryRequest = try makeRequest(
                    path: path,
                    method: method,
                    accessToken: refreshedSession.accessToken,
                    body: body,
                    timeout: timeout
                )
                return try await send(
                    retryRequest,
                    requiresAuth: requiresAuth,
                    hadSessionBeforeRequest: true,
                    clearSessionOnUnauthorized: true
                )
            } catch let authError as EduBackendAuthError {
                switch authError {
                case .authenticationRequired, .refreshRequired:
                    EduBackendSessionStore.clear()
                    throw EduBackendAPIError.sessionExpired
                case .backendNotConfigured:
                    throw EduBackendAPIError.backendNotConfigured
                case .requestFailed(let message):
                    throw EduBackendAPIError.requestFailed(message)
                case .invalidResponse:
                    throw EduBackendAPIError.requestFailed("Failed to refresh the EduNode account session.")
                }
            } catch {
                throw EduBackendAPIError.requestFailed(error.localizedDescription)
            }
        }
    }

    private func resolvedAccessTokenIfNeeded(
        requiresAuth: Bool
    ) async throws -> String? {
        guard requiresAuth else { return nil }
        guard let authService = EduBackendAuthService() else {
            throw EduBackendAPIError.backendNotConfigured
        }
        do {
            let session = try await authService.ensureValidSession()
            return session.accessToken
        } catch EduBackendAuthError.authenticationRequired {
            throw EduBackendAPIError.authenticationRequired
        } catch EduBackendAuthError.refreshRequired {
            throw EduBackendAPIError.sessionExpired
        } catch EduBackendAuthError.backendNotConfigured {
            throw EduBackendAPIError.backendNotConfigured
        } catch EduBackendAuthError.requestFailed(let message) {
            throw EduBackendAPIError.requestFailed(message)
        } catch EduBackendAuthError.invalidResponse {
            throw EduBackendAPIError.requestFailed("Failed to refresh the EduNode account session.")
        } catch {
            throw EduBackendAPIError.requestFailed(error.localizedDescription)
        }
    }

    private func decodedBackendErrorMessage(from data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["reason", "message", "error_description", "error"] {
                if let message = object[key] as? String,
                   !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return message
                }
            }
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

struct EduBackendLLMService {
    let apiClient: EduBackendAPIClient

    init?(backendConfig: EduBackendServiceConfig? = EduBackendServiceConfig.loadOptional()) {
        guard let apiClient = EduBackendAPIClient(backendConfig: backendConfig) else {
            return nil
        }
        self.apiClient = apiClient
    }

    func complete(messages: [EduLLMMessage]) async throws -> String {
        let response: EduBackendLLMCompletionResponse = try await apiClient.postJSON(
            path: ["llm", "complete"],
            requestBody: EduBackendLLMCompletionRequest(messages: messages),
            responseType: EduBackendLLMCompletionResponse.self,
            timeout: 120
        )
        return response.content
    }

    func parseReferencePDF(
        data: Data,
        fileName: String
    ) async throws -> EduBackendReferenceParsePDFResponse {
        let response: EduBackendReferenceParsePDFResponse = try await apiClient.postJSON(
            path: ["reference", "parse-pdf"],
            requestBody: EduBackendReferenceParsePDFRequest(
                fileName: fileName,
                fileDataBase64: data.base64EncodedString()
            ),
            responseType: EduBackendReferenceParsePDFResponse.self,
            timeout: 240
        )
        return response
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
