import Foundation

enum EduReferenceDocumentServiceConfigError: LocalizedError {
    case missingDotEnv
    case missingValue(String)
    case invalidURL(String)

    var errorDescription: String? {
        let isChinese = Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
        switch self {
        case .missingDotEnv:
            return isChinese
                ? "未找到参考文档解析服务的 .env 配置文件。请在 App 的 Documents 目录或应用资源目录中提供 .env。"
                : "The reference-document parser .env file was not found. Add .env to the app Documents directory or bundled resources."
        case .missingValue(let key):
            return isChinese
                ? "参考文档解析服务缺少配置项：\(key)。"
                : "The reference-document parser is missing the required setting: \(key)."
        case .invalidURL(let key):
            return isChinese
                ? "参考文档解析服务的 URL 配置无效：\(key)。"
                : "The reference-document parser URL is invalid for: \(key)."
        }
    }
}

struct EduReferenceDocumentServiceConfig {
    let apiToken: String
    let applyUploadURL: URL
    let batchResultURLPrefix: URL
    let modelVersion: String
    let language: String
    let enableFormula: Bool
    let enableTable: Bool
    let enableOCR: Bool
    let pollingIntervalNanoseconds: UInt64
    let maxPollingAttempts: Int

    static func load() throws -> EduReferenceDocumentServiceConfig {
        guard let dotEnv = EduDotEnvLoader.loadFirstAvailable() else {
            throw EduReferenceDocumentServiceConfigError.missingDotEnv
        }

        let values = dotEnv.values
        let apiToken = try requiredString(values: values, key: "MINERU_API_TOKEN")
        let applyUploadURL = try requiredURL(
            values: values,
            key: "MINERU_APPLY_UPLOAD_URL",
            fallback: derivedURL(
                values: values,
                baseKey: "MINERU_API_BASE_URL",
                suffix: "/file-urls/batch"
            )
        )
        let batchResultURLPrefix = try requiredURL(
            values: values,
            key: "MINERU_BATCH_RESULT_URL_PREFIX",
            fallback: derivedURL(
                values: values,
                baseKey: "MINERU_API_BASE_URL",
                suffix: "/extract-results/batch"
            )
        )

        let language = stringValue(values, key: "MINERU_LANGUAGE")
            ?? inferredDefaultLanguage()

        let pollingSeconds = max(0.5, doubleValue(values, key: "MINERU_POLLING_INTERVAL_SECONDS") ?? 2)
        let pollingIntervalNanoseconds = UInt64(pollingSeconds * 1_000_000_000)

        return EduReferenceDocumentServiceConfig(
            apiToken: apiToken,
            applyUploadURL: applyUploadURL,
            batchResultURLPrefix: batchResultURLPrefix,
            modelVersion: stringValue(values, key: "MINERU_MODEL_VERSION") ?? "vlm",
            language: language,
            enableFormula: boolValue(values, key: "MINERU_ENABLE_FORMULA") ?? true,
            enableTable: boolValue(values, key: "MINERU_ENABLE_TABLE") ?? true,
            enableOCR: boolValue(values, key: "MINERU_ENABLE_OCR") ?? false,
            pollingIntervalNanoseconds: pollingIntervalNanoseconds,
            maxPollingAttempts: max(1, intValue(values, key: "MINERU_MAX_POLLING_ATTEMPTS") ?? 40)
        )
    }

    var authorizationHeaderValue: String {
        "Bearer \(apiToken)"
    }

    private static func requiredURL(
        values: [String: String],
        key: String,
        fallback: String?
    ) throws -> URL {
        let raw = stringValue(values, key: key) ?? fallback
        guard let raw, !raw.isEmpty else {
            throw EduReferenceDocumentServiceConfigError.missingValue(key)
        }
        guard let url = URL(string: raw) else {
            throw EduReferenceDocumentServiceConfigError.invalidURL(key)
        }
        return url
    }

    private static func requiredString(
        values: [String: String],
        key: String,
        fallback: String? = nil
    ) throws -> String {
        let raw = stringValue(values, key: key) ?? fallback
        guard let raw, !raw.isEmpty else {
            throw EduReferenceDocumentServiceConfigError.missingValue(key)
        }
        return raw
    }

    private static func derivedURL(
        values: [String: String],
        baseKey: String,
        suffix: String
    ) -> String? {
        guard let base = stringValue(values, key: baseKey), !base.isEmpty else { return nil }
        return base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + suffix
    }

    private static func inferredDefaultLanguage() -> String {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true ? "ch" : "en"
    }

    private static func stringValue(_ values: [String: String], key: String) -> String? {
        let raw = values[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? nil : raw
    }

    private static func boolValue(_ values: [String: String], key: String) -> Bool? {
        guard let raw = stringValue(values, key: key)?.lowercased() else { return nil }
        switch raw {
        case "1", "true", "yes", "y", "on":
            return true
        case "0", "false", "no", "n", "off":
            return false
        default:
            return nil
        }
    }

    private static func intValue(_ values: [String: String], key: String) -> Int? {
        guard let raw = stringValue(values, key: key) else { return nil }
        return Int(raw)
    }

    private static func doubleValue(_ values: [String: String], key: String) -> Double? {
        guard let raw = stringValue(values, key: key) else { return nil }
        return Double(raw)
    }
}

private struct EduDotEnvDocument {
    let url: URL
    let values: [String: String]
}

private enum EduDotEnvLoader {
    static func loadFirstAvailable() -> EduDotEnvDocument? {
        for candidate in candidateURLs() {
            guard let data = try? Data(contentsOf: candidate),
                  let text = String(data: data, encoding: .utf8) else {
                continue
            }
            return EduDotEnvDocument(
                url: candidate,
                values: parse(text)
            )
        }
        return nil
    }

    private static func candidateURLs() -> [URL] {
        var urls: [URL] = []
        let fileManager = FileManager.default

        if let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            urls.append(documents.appendingPathComponent(".env"))
        }

        if let resourceURL = Bundle.main.resourceURL {
            urls.append(resourceURL.appendingPathComponent(".env"))
        }

        urls.append(Bundle.main.bundleURL.appendingPathComponent(".env"))
        return urls
    }

    private static func parse(_ text: String) -> [String: String] {
        text
            .split(whereSeparator: \.isNewline)
            .reduce(into: [String: String]()) { partial, rawLine in
                let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return }

                let normalizedLine: String
                if trimmed.hasPrefix("export ") {
                    normalizedLine = String(trimmed.dropFirst("export ".count))
                } else {
                    normalizedLine = trimmed
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
}
