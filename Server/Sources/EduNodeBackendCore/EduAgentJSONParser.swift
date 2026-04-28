import Foundation

enum EduBackendAgentJSONParser {
    static func decodeFirstJSONObject<T: Decodable>(_ type: T.Type, from raw: String) throws -> T {
        let normalized = stripCodeFenceIfNeeded(raw)
        if let data = normalized.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(T.self, from: data) {
            return decoded
        }

        guard let range = firstJSONObjectRange(in: normalized) else {
            throw EduBackendAgentClientError.requestFailed(
                "Structured parse failed (no-json-object, type=\(String(describing: T.self)))."
            )
        }

        let snippet = String(normalized[range])
        guard let data = snippet.data(using: .utf8) else {
            throw EduBackendAgentClientError.requestFailed(
                "Structured parse failed (snippet-encoding-failed, type=\(String(describing: T.self)))."
            )
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw EduBackendAgentClientError.requestFailed(
                "Structured parse failed (snippet-decode-failed, type=\(String(describing: T.self)))."
            )
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
