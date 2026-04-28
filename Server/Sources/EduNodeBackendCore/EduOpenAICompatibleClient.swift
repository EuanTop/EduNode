import Foundation
import EduNodeContracts
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum EduBackendAgentClientError: LocalizedError {
    case incompleteConfiguration
    case invalidBaseURL
    case emptyResponse
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .incompleteConfiguration:
            return "LLM configuration is incomplete."
        case .invalidBaseURL:
            return "The configured LLM base URL is invalid."
        case .emptyResponse:
            return "The model returned an empty response."
        case .requestFailed(let message):
            return message
        }
    }
}

public struct EduBackendOpenAICompatibleClient {
    let settings: EduAgentProviderSettingsResolved
    private let retryableStatusCodes: Set<Int> = [502, 503, 504]
    private let maxRequestAttempts = 3

    public init(settings: EduAgentProviderSettingsResolved) {
        self.settings = settings
    }

    public func listModels() async throws -> [String] {
        guard settings.isConfigured else {
            throw EduBackendAgentClientError.incompleteConfiguration
        }
        guard let url = resolvedModelsURL(from: settings.trimmedBaseURLString) else {
            throw EduBackendAgentClientError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = settings.timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(settings.trimmedAPIKey)", forHTTPHeaderField: "Authorization")
        if shouldUseClaudeMessagesAPI {
            request.setValue(settings.trimmedAPIKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }

        let (data, http) = try await sendWithRetry(request)
        guard (200..<300).contains(http.statusCode) else {
            throw EduBackendAgentClientError.requestFailed(serverMessage(from: data, statusCode: http.statusCode))
        }

        let payload = try JSONDecoder().decode(ModelsListResponse.self, from: data)
        return payload.data
            .map(\.id)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted()
    }

    public func complete(messages: [EduLLMMessage]) async throws -> String {
        guard settings.isConfigured else {
            throw EduBackendAgentClientError.incompleteConfiguration
        }

        if shouldUseClaudeMessagesAPI,
           let url = resolvedClaudeMessagesURL(from: settings.trimmedBaseURLString) {
            return try await completeViaClaudeMessages(url: url, messages: messages)
        }

        guard let url = resolvedChatCompletionsURL(from: settings.trimmedBaseURLString) else {
            throw EduBackendAgentClientError.invalidBaseURL
        }

        let requestBody = ChatCompletionsRequest(
            model: settings.trimmedModel,
            messages: messages,
            temperature: settings.temperature,
            maxTokens: settings.maxTokens,
            stream: false
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = settings.timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(settings.trimmedAPIKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, http) = try await sendWithRetry(request)
        guard (200..<300).contains(http.statusCode) else {
            throw EduBackendAgentClientError.requestFailed(serverMessage(from: data, statusCode: http.statusCode))
        }

        let payload = try JSONDecoder().decode(ChatCompletionsResponse.self, from: data)
        let content = payload.choices
            .compactMap { $0.message.flattenedContent }
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })

        guard let content else {
            throw EduBackendAgentClientError.emptyResponse
        }
        return content
    }

    private var shouldUseClaudeMessagesAPI: Bool {
        let lowerProvider = settings.providerName.lowercased()
        let lowerURL = settings.trimmedBaseURLString.lowercased()
        return lowerProvider.contains("claude") || lowerURL.contains("/messages")
    }

    private func completeViaClaudeMessages(url: URL, messages: [EduLLMMessage]) async throws -> String {
        let requestBody = ClaudeMessagesRequest.from(
            model: settings.trimmedModel,
            messages: messages,
            temperature: settings.temperature,
            maxTokens: settings.maxTokens
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = settings.timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(settings.trimmedAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue(settings.trimmedAPIKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, http) = try await sendWithRetry(request)
        guard (200..<300).contains(http.statusCode) else {
            throw EduBackendAgentClientError.requestFailed(serverMessage(from: data, statusCode: http.statusCode))
        }

        let payload = try JSONDecoder().decode(ClaudeMessagesResponse.self, from: data)
        let mergedText = payload.content
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !mergedText.isEmpty else {
            throw EduBackendAgentClientError.emptyResponse
        }
        return mergedText
    }

    private func resolvedChatCompletionsURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard var url = URL(string: trimmed) else { return nil }

        if trimmed.lowercased().contains("/chat/completions") {
            return url
        }

        if url.path.hasSuffix("/v1") {
            url.append(path: "chat")
            url.append(path: "completions")
            return url
        }

        if url.path.hasSuffix("/v1/") {
            url.deleteLastPathComponent()
            url.append(path: "v1")
            url.append(path: "chat")
            url.append(path: "completions")
            return url
        }

        url.append(path: "v1")
        url.append(path: "chat")
        url.append(path: "completions")
        return url
    }

    private func resolvedModelsURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard var url = URL(string: trimmed) else { return nil }

        if url.path.hasSuffix("/v1/messages") {
            url.deleteLastPathComponent()
            url.append(path: "models")
            return url
        }

        if url.path.hasSuffix("/v1/messages/") {
            url.deleteLastPathComponent()
            url.deleteLastPathComponent()
            url.append(path: "v1")
            url.append(path: "models")
            return url
        }

        if trimmed.lowercased().contains("/models") {
            return url
        }

        if url.path.hasSuffix("/v1") {
            url.append(path: "models")
            return url
        }

        if url.path.hasSuffix("/v1/") {
            url.deleteLastPathComponent()
            url.append(path: "v1")
            url.append(path: "models")
            return url
        }

        url.append(path: "v1")
        url.append(path: "models")
        return url
    }

    private func resolvedClaudeMessagesURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard var url = URL(string: trimmed) else { return nil }

        if trimmed.lowercased().contains("/messages") {
            return url
        }

        if url.path.hasSuffix("/v1") {
            url.append(path: "messages")
            return url
        }

        if url.path.hasSuffix("/v1/") {
            url.deleteLastPathComponent()
            url.append(path: "v1")
            url.append(path: "messages")
            return url
        }

        url.append(path: "v1")
        url.append(path: "messages")
        return url
    }

    private func sendWithRetry(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        for attempt in 0..<maxRequestAttempts {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw EduBackendAgentClientError.requestFailed("Missing HTTP response.")
                }

                if retryableStatusCodes.contains(http.statusCode), attempt < maxRequestAttempts - 1 {
                    try await Task.sleep(nanoseconds: retryDelayNanoseconds(for: attempt))
                    continue
                }

                return (data, http)
            } catch {
                guard shouldRetry(for: error), attempt < maxRequestAttempts - 1 else {
                    if let backendError = error as? EduBackendAgentClientError {
                        throw backendError
                    }
                    throw EduBackendAgentClientError.requestFailed(error.localizedDescription)
                }
                try await Task.sleep(nanoseconds: retryDelayNanoseconds(for: attempt))
            }
        }

        throw EduBackendAgentClientError.requestFailed("Request failed after retries.")
    }

    private func retryDelayNanoseconds(for attempt: Int) -> UInt64 {
        let baseSeconds: Double = 0.8
        let seconds = baseSeconds * pow(2.0, Double(attempt))
        return UInt64(seconds * 1_000_000_000)
    }

    private func shouldRetry(for error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .networkConnectionLost,
             .notConnectedToInternet,
             .internationalRoamingOff,
             .callIsActive,
             .dataNotAllowed:
            return true
        default:
            return false
        }
    }

    private func serverMessage(from data: Data, statusCode: Int) -> String {
        if let message = try? JSONDecoder().decode(ClaudeErrorEnvelope.self, from: data).error.message,
           !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return message
        }
        if let message = try? JSONDecoder().decode(OpenAIErrorEnvelope.self, from: data).error.message,
           !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return message
        }
        guard let raw = String(data: data, encoding: .utf8), !raw.isEmpty else {
            return "HTTP \(statusCode)"
        }
        let excerpt = String(raw.prefix(320)).replacingOccurrences(of: "\n", with: "\\n")
        return "HTTP \(statusCode): \(excerpt)"
    }
}

private struct ChatCompletionsRequest: Encodable {
    let model: String
    let messages: [EduLLMMessage]
    let temperature: Double
    let maxTokens: Int
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
        case stream
    }
}

private struct ClaudeMessagesRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let system: String?
    let messages: [Message]
    let temperature: Double
    let maxTokens: Int

    enum CodingKeys: String, CodingKey {
        case model
        case system
        case messages
        case temperature
        case maxTokens = "max_tokens"
    }

    static func from(
        model: String,
        messages: [EduLLMMessage],
        temperature: Double,
        maxTokens: Int
    ) -> ClaudeMessagesRequest {
        let systemPrompt = messages
            .filter { $0.role == "system" }
            .map(\.content)
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let convertedMessages = messages
            .filter { $0.role != "system" }
            .map { message -> Message in
                let role = message.role == "assistant" ? "assistant" : "user"
                return Message(role: role, content: message.content)
            }

        let fallbackMessages = convertedMessages.isEmpty
            ? [Message(role: "user", content: "OK")]
            : convertedMessages

        return ClaudeMessagesRequest(
            model: model,
            system: systemPrompt.isEmpty ? nil : systemPrompt,
            messages: fallbackMessages,
            temperature: temperature,
            maxTokens: maxTokens
        )
    }
}

private struct ChatCompletionsResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            enum Content: Decodable {
                struct Part: Decodable {
                    let type: String?
                    let text: String?
                }

                case string(String)
                case parts([Part])

                init(from decoder: Decoder) throws {
                    let container = try decoder.singleValueContainer()
                    if let string = try? container.decode(String.self) {
                        self = .string(string)
                    } else if let parts = try? container.decode([Part].self) {
                        self = .parts(parts)
                    } else {
                        self = .string("")
                    }
                }
            }

            let content: Content

            var flattenedContent: String {
                switch content {
                case .string(let text):
                    return text
                case .parts(let parts):
                    return parts.compactMap(\.text).joined()
                }
            }
        }

        let message: Message
    }

    let choices: [Choice]
}

private struct ModelsListResponse: Decodable {
    struct ModelEntry: Decodable {
        let id: String
    }

    let data: [ModelEntry]
}

private struct ClaudeMessagesResponse: Decodable {
    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }

    let content: [ContentBlock]
}

private struct OpenAIErrorEnvelope: Decodable {
    struct Payload: Decodable {
        let message: String
    }

    let error: Payload
}

private struct ClaudeErrorEnvelope: Decodable {
    struct Payload: Decodable {
        let message: String
    }

    let error: Payload
}
