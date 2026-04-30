import Foundation

struct EduDotEnvDocument {
    let sourceDescription: String
    let values: [String: String]
}

enum EduDotEnvLoader {
    private static let sourceAnchorPath = #filePath
    private static let allowedFrontendKeys: Set<String> = [
        "EDUNODE_ENV",
        "EDUNODE_BACKEND_BASE_URL",
        "EDUNODE_SERVER_HOST",
        "PORT"
    ]

    static func loadFirstAvailable() -> EduDotEnvDocument? {
        let environmentValues = filteredProcessEnvironment()

        for candidate in candidateURLs() {
            guard let data = try? Data(contentsOf: candidate),
                  let text = String(data: data, encoding: .utf8) else {
                continue
            }

            var values = parse(text)
            for (key, value) in environmentValues {
                values[key] = value
            }
            values = sanitized(values)

            guard !values.isEmpty else { continue }

            return EduDotEnvDocument(
                sourceDescription: candidate.path,
                values: values
            )
        }

        let sanitizedEnvironmentValues = sanitized(environmentValues)
        guard !sanitizedEnvironmentValues.isEmpty else { return nil }
        return EduDotEnvDocument(
            sourceDescription: "process-environment",
            values: sanitizedEnvironmentValues
        )
    }

    private static func filteredProcessEnvironment() -> [String: String] {
        ProcessInfo.processInfo.environment.reduce(into: [:]) { partial, pair in
            let key = pair.key.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = pair.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { return }
            guard allowedFrontendKeys.contains(key) else { return }
            partial[key] = value
        }
    }

    private static func sanitized(_ values: [String: String]) -> [String: String] {
        values.reduce(into: [:]) { partial, pair in
            guard allowedFrontendKeys.contains(pair.key) else { return }
            partial[pair.key] = pair.value
        }
    }

    private static func candidateURLs() -> [URL] {
        var urls: [URL] = []
        let fileManager = FileManager.default

        if let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            for name in environmentSpecificDotEnvNames() {
                urls.append(documents.appendingPathComponent(name))
            }
            urls.append(documents.appendingPathComponent(".env"))
        }

        let currentDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        #if DEBUG
        for name in environmentSpecificDotEnvNames() {
            urls.append(currentDirectory.appendingPathComponent(name))
            urls.append(currentDirectory.appendingPathComponent("EduNode/\(name)"))
        }
        urls.append(currentDirectory.appendingPathComponent(".env"))
        urls.append(currentDirectory.appendingPathComponent("EduNode/.env"))
        urls.append(currentDirectory.appendingPathComponent("Server/.env"))

        var sourceDirectory = URL(fileURLWithPath: sourceAnchorPath).deletingLastPathComponent()
        for _ in 0..<8 {
            for name in environmentSpecificDotEnvNames() {
                urls.append(sourceDirectory.appendingPathComponent(name))
                urls.append(sourceDirectory.appendingPathComponent("EduNode/\(name)"))
            }
            urls.append(sourceDirectory.appendingPathComponent(".env"))
            urls.append(sourceDirectory.appendingPathComponent("EduNode/.env"))
            urls.append(sourceDirectory.appendingPathComponent("Server/.env"))
            sourceDirectory.deleteLastPathComponent()
        }
        #endif

        if let resourceURL = Bundle.main.resourceURL {
            urls.append(resourceURL.appendingPathComponent("frontend.env"))
            for name in environmentSpecificDotEnvNames() {
                urls.append(resourceURL.appendingPathComponent(name))
            }
            urls.append(resourceURL.appendingPathComponent(".env"))
        }

        urls.append(Bundle.main.bundleURL.appendingPathComponent(".env"))

        var seen: Set<String> = []
        return urls.filter { url in
            let normalized = url.standardizedFileURL.path
            return seen.insert(normalized).inserted
        }
    }

    private static func environmentSpecificDotEnvNames() -> [String] {
        let raw = ProcessInfo.processInfo.environment["EDUNODE_ENV"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        guard !raw.isEmpty else { return [] }
        let normalized: String
        switch raw {
        case "prod", "production", "release":
            normalized = "production"
        case "dev", "development", "debug":
            normalized = "dev"
        default:
            normalized = raw
        }
        return [".env.\(normalized)"]
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

struct EduBackendServiceConfig {
    let baseURL: URL

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    static func loadOptional() -> EduBackendServiceConfig? {
        let values = EduDotEnvLoader.loadFirstAvailable()?.values ?? [:]
        let rawBaseURL = values["EDUNODE_BACKEND_BASE_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let derivedBaseURL = rawBaseURL.isEmpty
            ? derivedLocalBackendURL(from: values)
            : rawBaseURL

        let resolvedBaseURLString = resolvedBaseURLString(from: derivedBaseURL)
        guard let baseURL = URL(string: resolvedBaseURLString) else { return nil }

        return EduBackendServiceConfig(
            baseURL: baseURL
        )
    }

    private static func resolvedBaseURLString(from configuredOrDerived: String) -> String {
        let trimmed = configuredOrDerived.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }

        return "https://api.euantop.work"
    }

    private static func derivedLocalBackendURL(from values: [String: String]) -> String {
        let host = values["EDUNODE_SERVER_HOST"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let port = values["PORT"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !host.isEmpty, !port.isEmpty else { return "" }
        return "http://\(host):\(port)"
    }
}
