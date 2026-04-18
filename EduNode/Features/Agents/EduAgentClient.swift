import Foundation

struct EduLLMMessage: Codable, Hashable, Sendable {
    let role: String
    let content: String
}

enum EduAgentClientError: LocalizedError {
    case incompleteConfiguration
    case invalidBaseURL
    case emptyResponse
    case requestFailed(String)
    case invalidStructuredResponse

    var errorDescription: String? {
        let isChinese = Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
        switch self {
        case .incompleteConfiguration:
            return isChinese ? "Agent 配置不完整，请先填写 Base URL / Model / API Key。" : "Agent configuration is incomplete. Please fill in Base URL / Model / API Key first."
        case .invalidBaseURL:
            return isChinese ? "Base URL 无效，无法拼接 OpenAI-compatible endpoint。" : "Base URL is invalid and cannot form an OpenAI-compatible endpoint."
        case .emptyResponse:
            return isChinese ? "模型返回为空。" : "The model returned an empty response."
        case .requestFailed(let message):
            return message
        case .invalidStructuredResponse:
            return isChinese ? "模型返回的结构化内容无法解析。" : "The model returned a structured response that could not be parsed."
        }
    }
}

struct EduOpenAICompatibleClient {
    let settings: EduAgentProviderSettings

    func listModels() async throws -> [String] {
        let trimmedBaseURL = settings.trimmedBaseURLString
        let trimmedAPIKey = settings.trimmedAPIKey
        guard !trimmedBaseURL.isEmpty, !trimmedAPIKey.isEmpty else {
            throw EduAgentClientError.incompleteConfiguration
        }
        guard let url = resolvedModelsURL(from: trimmedBaseURL) else {
            throw EduAgentClientError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = settings.timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(trimmedAPIKey)", forHTTPHeaderField: "Authorization")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw EduAgentClientError.requestFailed(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw EduAgentClientError.requestFailed("Missing HTTP response.")
        }

        guard (200..<300).contains(http.statusCode) else {
            let serverMessage = (try? JSONDecoder().decode(OpenAIErrorEnvelope.self, from: data).error.message)
                ?? String(data: data, encoding: .utf8)
                ?? "HTTP \(http.statusCode)"
            throw EduAgentClientError.requestFailed(serverMessage)
        }

        let payload = try JSONDecoder().decode(ModelsListResponse.self, from: data)
        return payload.data
            .map(\.id)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted()
    }

    func complete(messages: [EduLLMMessage]) async throws -> String {
        guard settings.isConfigured else {
            throw EduAgentClientError.incompleteConfiguration
        }
        guard let url = resolvedChatCompletionsURL(from: settings.trimmedBaseURLString) else {
            throw EduAgentClientError.invalidBaseURL
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

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw EduAgentClientError.requestFailed(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw EduAgentClientError.requestFailed("Missing HTTP response.")
        }

        guard (200..<300).contains(http.statusCode) else {
            let serverMessage = (try? JSONDecoder().decode(OpenAIErrorEnvelope.self, from: data).error.message)
                ?? String(data: data, encoding: .utf8)
                ?? "HTTP \(http.statusCode)"
            throw EduAgentClientError.requestFailed(serverMessage)
        }

        let payload = try JSONDecoder().decode(ChatCompletionsResponse.self, from: data)
        let content = payload.choices
            .compactMap { $0.message.flattenedContent }
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })

        guard let content else {
            throw EduAgentClientError.emptyResponse
        }
        return content
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
}

enum EduAgentJSONParser {
    static func decodeFirstJSONObject<T: Decodable>(_ type: T.Type, from raw: String) throws -> T {
        let normalized = stripCodeFenceIfNeeded(raw)
        if let data = normalized.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(T.self, from: data) {
            return decoded
        }

        guard let range = firstJSONObjectRange(in: normalized) else {
            throw EduAgentClientError.invalidStructuredResponse
        }
        let snippet = String(normalized[range])
        guard let data = snippet.data(using: .utf8) else {
            throw EduAgentClientError.invalidStructuredResponse
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw EduAgentClientError.invalidStructuredResponse
        }
    }

    private static func stripCodeFenceIfNeeded(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }
        let lines = trimmed.components(separatedBy: .newlines)
        let filtered = lines.dropFirst().dropLast()
        return filtered.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstJSONObjectRange(in text: String) -> Range<String.Index>? {
        var start: String.Index?
        var depth = 0
        var isInString = false
        var isEscaped = false

        for index in text.indices {
            let char = text[index]

            if isEscaped {
                isEscaped = false
                continue
            }

            if char == "\\" {
                isEscaped = true
                continue
            }

            if char == "\"" {
                isInString.toggle()
                continue
            }

            guard !isInString else { continue }

            if char == "{" {
                if start == nil { start = index }
                depth += 1
            } else if char == "}" {
                depth -= 1
                if depth == 0, let start {
                    return start..<text.index(after: index)
                }
            }
        }

        return nil
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

private struct OpenAIErrorEnvelope: Decodable {
    struct Payload: Decodable {
        let message: String
    }

    let error: Payload
}

private struct ModelsListResponse: Decodable {
    struct ModelInfo: Decodable {
        let id: String
    }

    let data: [ModelInfo]
}
