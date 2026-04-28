import Foundation

public struct EduServerSupabaseConfiguration: Sendable {
    public let urlString: String
    public let publishableKey: String

    public init(
        urlString: String,
        publishableKey: String
    ) {
        self.urlString = urlString
        self.publishableKey = publishableKey
    }

    public var trimmedURLString: String {
        urlString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var trimmedPublishableKey: String {
        publishableKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var isConfigured: Bool {
        !trimmedURLString.isEmpty && !trimmedPublishableKey.isEmpty
    }

    public var authBaseURL: URL? {
        guard var url = URL(string: trimmedURLString) else { return nil }
        url.append(path: "auth")
        url.append(path: "v1")
        return url
    }
}

public struct EduServerMinerUSettings: Sendable {
    public let apiToken: String
    public let applyUploadURL: URL
    public let batchResultURLPrefix: URL
    public let modelVersion: String
    public let language: String
    public let enableFormula: Bool
    public let enableTable: Bool
    public let enableOCR: Bool
    public let pollingIntervalNanoseconds: UInt64
    public let maxPollingAttempts: Int

    public init(
        apiToken: String,
        applyUploadURL: URL,
        batchResultURLPrefix: URL,
        modelVersion: String,
        language: String,
        enableFormula: Bool,
        enableTable: Bool,
        enableOCR: Bool,
        pollingIntervalNanoseconds: UInt64,
        maxPollingAttempts: Int
    ) {
        self.apiToken = apiToken
        self.applyUploadURL = applyUploadURL
        self.batchResultURLPrefix = batchResultURLPrefix
        self.modelVersion = modelVersion
        self.language = language
        self.enableFormula = enableFormula
        self.enableTable = enableTable
        self.enableOCR = enableOCR
        self.pollingIntervalNanoseconds = pollingIntervalNanoseconds
        self.maxPollingAttempts = maxPollingAttempts
    }

    public var isConfigured: Bool {
        !apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public enum EduServerEnvironmentLoader {
    public static var defaultLLMSettings: EduAgentProviderSettingsResolved {
        EduAgentProviderSettingsResolved(
            providerName: "",
            baseURLString: "",
            model: "",
            apiKey: "",
            temperature: 0.35,
            maxTokens: 3200,
            timeoutSeconds: 90,
            additionalSystemPrompt: ""
        )
    }

    public static func loadMergedEnvironment() -> [String: String] {
        var merged = ProcessInfo.processInfo.environment

        for candidate in candidateURLs() {
            guard let data = try? Data(contentsOf: candidate),
                  let text = String(data: data, encoding: .utf8) else {
                continue
            }
            for (key, value) in parse(text) {
                if merged[key]?.isEmpty ?? true {
                    merged[key] = value
                }
            }
        }

        return merged
    }

    public static func llmSettings(from env: [String: String]) -> EduAgentProviderSettingsResolved {
        let providerName = trimmed(env["EDUNODE_LLM_PROVIDER_NAME"])
        let baseURL = trimmed(env["EDUNODE_LLM_BASE_URL"])
        let model = trimmed(env["EDUNODE_LLM_MODEL"])
        let apiKey = trimmed(env["EDUNODE_LLM_API_KEY"])
        let extraPrompt = trimmed(env["EDUNODE_LLM_ADDITIONAL_SYSTEM_PROMPT"])

        return EduAgentProviderSettingsResolved(
            providerName: providerName.isEmpty ? "OpenAI-Compatible" : providerName,
            baseURLString: baseURL,
            model: model,
            apiKey: apiKey,
            temperature: double(env["EDUNODE_LLM_TEMPERATURE"], fallback: 0.35),
            maxTokens: int(env["EDUNODE_LLM_MAX_TOKENS"], fallback: 3200, minimum: 256),
            timeoutSeconds: double(env["EDUNODE_LLM_TIMEOUT_SECONDS"], fallback: 90),
            additionalSystemPrompt: extraPrompt
        )
    }

    public static func supabaseConfiguration(from env: [String: String]) -> EduServerSupabaseConfiguration {
        let publishableKey = trimmed(env["EDUNODE_SUPABASE_PUBLISHABLE_KEY"]).isEmpty
            ? trimmed(env["EDUNODE_SUPABASE_ANON_KEY"])
            : trimmed(env["EDUNODE_SUPABASE_PUBLISHABLE_KEY"])

        return EduServerSupabaseConfiguration(
            urlString: trimmed(env["EDUNODE_SUPABASE_URL"]),
            publishableKey: publishableKey
        )
    }

    public static func minerUSettings(from env: [String: String]) -> EduServerMinerUSettings? {
        let apiToken = trimmed(env["MINERU_API_TOKEN"])
        guard !apiToken.isEmpty else { return nil }

        let normalizedEnv = env.merging([
            "MINERU_API_BASE_URL": trimmed(env["MINERU_API_BASE_URL"]).isEmpty
                ? "https://mineru.net/api/v4"
                : trimmed(env["MINERU_API_BASE_URL"])
        ]) { current, _ in current }

        guard let applyUploadURL = resolvedURL(
            env: normalizedEnv,
            key: "MINERU_APPLY_UPLOAD_URL",
            fallbackKey: "MINERU_API_BASE_URL",
            fallbackSuffix: "/file-urls/batch"
        ),
        let batchResultURLPrefix = resolvedURL(
            env: normalizedEnv,
            key: "MINERU_BATCH_RESULT_URL_PREFIX",
            fallbackKey: "MINERU_API_BASE_URL",
            fallbackSuffix: "/extract-results/batch"
        ) else {
            return nil
        }

        let language = trimmed(env["MINERU_LANGUAGE"]).isEmpty
            ? inferredDefaultLanguage()
            : trimmed(env["MINERU_LANGUAGE"])
        let pollingSeconds = max(0.5, double(env["MINERU_POLLING_INTERVAL_SECONDS"], fallback: 2))

        return EduServerMinerUSettings(
            apiToken: apiToken,
            applyUploadURL: applyUploadURL,
            batchResultURLPrefix: batchResultURLPrefix,
            modelVersion: trimmed(env["MINERU_MODEL_VERSION"]).isEmpty ? "vlm" : trimmed(env["MINERU_MODEL_VERSION"]),
            language: language,
            enableFormula: bool(env["MINERU_ENABLE_FORMULA"], fallback: true),
            enableTable: bool(env["MINERU_ENABLE_TABLE"], fallback: true),
            enableOCR: bool(env["MINERU_ENABLE_OCR"], fallback: false),
            pollingIntervalNanoseconds: UInt64(pollingSeconds * 1_000_000_000),
            maxPollingAttempts: int(env["MINERU_MAX_POLLING_ATTEMPTS"], fallback: 40, minimum: 1)
        )
    }

    private static func candidateURLs() -> [URL] {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        return [
            cwd.appendingPathComponent("Server/.env"),
            cwd.appendingPathComponent(".env")
        ]
    }

    private static func parse(_ text: String) -> [String: String] {
        text
            .split(whereSeparator: \.isNewline)
            .reduce(into: [String: String]()) { partial, rawLine in
                let trimmedLine = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedLine.isEmpty, !trimmedLine.hasPrefix("#") else { return }

                let normalizedLine: String
                if trimmedLine.hasPrefix("export ") {
                    normalizedLine = String(trimmedLine.dropFirst("export ".count))
                } else {
                    normalizedLine = trimmedLine
                }

                let segments = normalizedLine.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard segments.count == 2 else { return }
                let key = segments[0].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty else { return }

                var value = segments[1].trimmingCharacters(in: .whitespacesAndNewlines)
                if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
                    value.removeFirst()
                    value.removeLast()
                }
                partial[key] = value
            }
    }

    private static func resolvedURL(
        env: [String: String],
        key: String,
        fallbackKey: String,
        fallbackSuffix: String
    ) -> URL? {
        let direct = trimmed(env[key])
        if let url = URL(string: direct), !direct.isEmpty {
            return url
        }

        let base = trimmed(env[fallbackKey])
        guard !base.isEmpty else { return nil }
        return URL(string: base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + fallbackSuffix)
    }

    private static func inferredDefaultLanguage() -> String {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true ? "ch" : "en"
    }

    private static func trimmed(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func double(_ value: String?, fallback: Double) -> Double {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              let parsed = Double(value) else {
            return fallback
        }
        return parsed
    }

    private static func int(_ value: String?, fallback: Int, minimum: Int) -> Int {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              let parsed = Int(value) else {
            return fallback
        }
        return max(minimum, parsed)
    }

    private static func bool(_ value: String?, fallback: Bool) -> Bool {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty else {
            return fallback
        }
        switch raw {
        case "1", "true", "yes", "y", "on":
            return true
        case "0", "false", "no", "n", "off":
            return false
        default:
            return fallback
        }
    }
}
