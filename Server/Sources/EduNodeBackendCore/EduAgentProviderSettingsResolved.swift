import Foundation

public struct EduAgentProviderSettingsResolved: Sendable {
    public let providerName: String
    public let baseURLString: String
    public let model: String
    public let apiKey: String
    public let temperature: Double
    public let maxTokens: Int
    public let timeoutSeconds: Double
    public let additionalSystemPrompt: String

    public init(
        providerName: String,
        baseURLString: String,
        model: String,
        apiKey: String,
        temperature: Double,
        maxTokens: Int,
        timeoutSeconds: Double,
        additionalSystemPrompt: String
    ) {
        self.providerName = providerName
        self.baseURLString = baseURLString
        self.model = model
        self.apiKey = apiKey
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.timeoutSeconds = timeoutSeconds
        self.additionalSystemPrompt = additionalSystemPrompt
    }

    var trimmedBaseURLString: String {
        baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedModel: String {
        model.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isConfigured: Bool {
        !trimmedBaseURLString.isEmpty && !trimmedModel.isEmpty && !trimmedAPIKey.isEmpty
    }

    var baseURLHost: String {
        URL(string: trimmedBaseURLString)?.host ?? ""
    }
}
