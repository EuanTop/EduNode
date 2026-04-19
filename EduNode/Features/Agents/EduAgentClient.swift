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
            return isChinese ? "Base URL 无效，无法拼接可兼容的模型服务 endpoint。" : "Base URL is invalid and cannot form a compatible model endpoint."
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
    private let retryableStatusCodes: Set<Int> = [502, 503, 504]
    private let maxRequestAttempts = 3

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
        if shouldUseClaudeMessagesAPI {
            request.setValue(trimmedAPIKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }

        let (data, http) = try await sendWithRetry(request)

        guard (200..<300).contains(http.statusCode) else {
            let serverMessage = serverMessage(from: data, statusCode: http.statusCode)
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

        if shouldUseClaudeMessagesAPI,
           let url = resolvedClaudeMessagesURL(from: settings.trimmedBaseURLString) {
            return try await completeViaClaudeMessages(url: url, messages: messages)
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

        let (data, http) = try await sendWithRetry(request)

        guard (200..<300).contains(http.statusCode) else {
            let serverMessage = serverMessage(from: data, statusCode: http.statusCode)
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
            let serverMessage = serverMessage(from: data, statusCode: http.statusCode)
            throw EduAgentClientError.requestFailed(serverMessage)
        }

        let payload = try JSONDecoder().decode(ClaudeMessagesResponse.self, from: data)
        let mergedText = payload.content
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !mergedText.isEmpty else {
            throw EduAgentClientError.emptyResponse
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
                    throw EduAgentClientError.requestFailed("Missing HTTP response.")
                }

                if retryableStatusCodes.contains(http.statusCode), attempt < maxRequestAttempts - 1 {
#if DEBUG
                    print("[EduNode][LLM][Retry] status=\(http.statusCode) attempt=\(attempt + 1)/\(maxRequestAttempts)")
#endif
                    try await Task.sleep(nanoseconds: retryDelayNanoseconds(for: attempt))
                    continue
                }

                return (data, http)
            } catch {
                guard shouldRetry(for: error), attempt < maxRequestAttempts - 1 else {
                    if let clientError = error as? EduAgentClientError {
                        throw clientError
                    }
                    throw EduAgentClientError.requestFailed(error.localizedDescription)
                }
#if DEBUG
                print("[EduNode][LLM][Retry] network error attempt=\(attempt + 1)/\(maxRequestAttempts): \(error.localizedDescription)")
#endif
                try await Task.sleep(nanoseconds: retryDelayNanoseconds(for: attempt))
            }
        }

        throw EduAgentClientError.requestFailed("Request failed after retries.")
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

        if looksLikeHTML(raw) {
            return summarizeHTMLError(raw, statusCode: statusCode)
        }

        let excerpt = String(raw.prefix(320)).replacingOccurrences(of: "\n", with: "\\n")
        return "HTTP \(statusCode): \(excerpt)"
    }

    private func looksLikeHTML(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("<html") || lower.contains("<!doctype html")
    }

    private func summarizeHTMLError(_ html: String, statusCode: Int) -> String {
        let isChinese = Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
        let title = firstMatch(in: html, pattern: "<title>(.*?)</title>")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rayID = firstMatch(in: html, pattern: "Ray ID:\\s*</strong>\\s*([A-Za-z0-9-]+)")
            ?? firstMatch(in: html, pattern: "Ray ID[:\\s]+([A-Za-z0-9-]+)")
        let hasCloudflare = html.lowercased().contains("cloudflare")

        if isChinese {
            var message = "网关暂时不可用（HTTP \(statusCode)）"
            if let title, !title.isEmpty {
                message += "：\(title)"
            }
            if hasCloudflare {
                message += "（Cloudflare）"
            }
            if let rayID, !rayID.isEmpty {
                message += "，Ray ID: \(rayID)"
            }
            message += "。请稍后重试。"
            return message
        }

        var message = "Gateway temporarily unavailable (HTTP \(statusCode))"
        if let title, !title.isEmpty {
            message += ": \(title)"
        }
        if hasCloudflare {
            message += " (Cloudflare)"
        }
        if let rayID, !rayID.isEmpty {
            message += ", Ray ID: \(rayID)"
        }
        message += ". Please retry shortly."
        return message
    }

    private func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let nsrange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: nsrange), match.numberOfRanges >= 2,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
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
            let message = structuredParseFailureMessage(
                stage: "no-json-object",
                typeName: String(describing: T.self),
                raw: raw,
                normalized: normalized
            )
            debugStructuredDecodeFailure(
                stage: "no-json-object",
                typeName: String(describing: T.self),
                raw: raw,
                normalized: normalized
            )
            throw EduAgentClientError.requestFailed(message)
        }
        let snippet = String(normalized[range])
        guard let data = snippet.data(using: .utf8) else {
            let message = structuredParseFailureMessage(
                stage: "snippet-encoding-failed",
                typeName: String(describing: T.self),
                raw: raw,
                normalized: normalized
            )
            debugStructuredDecodeFailure(
                stage: "snippet-encoding-failed",
                typeName: String(describing: T.self),
                raw: raw,
                normalized: normalized
            )
            throw EduAgentClientError.requestFailed(message)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            let message = structuredParseFailureMessage(
                stage: "snippet-decode-failed",
                typeName: String(describing: T.self),
                raw: raw,
                normalized: normalized
            )
            debugStructuredDecodeFailure(
                stage: "snippet-decode-failed",
                typeName: String(describing: T.self),
                raw: raw,
                normalized: normalized
            )
            throw EduAgentClientError.requestFailed(message)
        }
    }

    private static func structuredParseFailureMessage(
        stage: String,
        typeName: String,
        raw: String,
        normalized: String
    ) -> String {
        let isChinese = Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
        let excerpt = String(normalized.prefix(280)).replacingOccurrences(of: "\n", with: "\\n")
        let fallback = String(raw.prefix(280)).replacingOccurrences(of: "\n", with: "\\n")
        let payload = excerpt.isEmpty ? fallback : excerpt
        let likelyTruncated = !normalized.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("}")
        if isChinese {
            if likelyTruncated {
                return "结构化解析失败（\(stage), type=\(typeName)），回复可能被截断。请提高 Max Tokens 后重试。回复片段：\(payload)"
            }
            return "结构化解析失败（\(stage), type=\(typeName)）。回复片段：\(payload)"
        }
        if likelyTruncated {
            return "Structured parse failed (\(stage), type=\(typeName)); the reply appears truncated. Increase Max Tokens and retry. Reply excerpt: \(payload)"
        }
        return "Structured parse failed (\(stage), type=\(typeName)). Reply excerpt: \(payload)"
    }

    private static func debugStructuredDecodeFailure(
        stage: String,
        typeName: String,
        raw: String,
        normalized: String
    ) {
#if DEBUG
        let rawExcerpt = String(raw.prefix(700)).replacingOccurrences(of: "\n", with: "\\n")
        let normalizedExcerpt = String(normalized.prefix(700)).replacingOccurrences(of: "\n", with: "\\n")
        print("[EduNode][StructuredParse][\(stage)] type=\(typeName)")
        print("[EduNode][StructuredParse][raw]\(rawExcerpt)")
        print("[EduNode][StructuredParse][normalized]\(normalizedExcerpt)")
#endif
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

        let fallbackMessages: [Message]
        if convertedMessages.isEmpty {
            fallbackMessages = [Message(role: "user", content: "OK")]
        } else {
            fallbackMessages = convertedMessages
        }

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

private struct ModelsListResponse: Decodable {
    struct ModelInfo: Decodable {
        let id: String
    }

    let data: [ModelInfo]
}
