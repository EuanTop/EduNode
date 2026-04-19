import Foundation
import PDFKit

struct Env {
    let baseURL: String
    let model: String
    let apiKey: String
    let referenceTemplatePath: String
}

struct AttemptRecord: Encodable {
    let attempt: Int
    let maxTokens: Int
    let structuredDecoded: Bool
    let skeletonRisk: Bool
    let assistantReplyHead: String
    let generatedMarkdownChars: Int
    let error: String?
}

struct ClaudeRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let system: String?
    let messages: [Message]
    let temperature: Double
    let max_tokens: Int
}

struct PromptBundle {
    let system: String
    let user: String
}

struct ClaudeResponse: Decodable {
    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }

    let content: [ContentBlock]
}

struct MaterializationResponse: Decodable {
    let assistant_reply: String
    let generated_markdown: String
}

@main
struct LLMMaterializationSmoke {
    static func main() async {
        do {
            let env = try loadEnv()
            let templateText = try extractPDFText(path: env.referenceTemplatePath)
            let maxAttempts = 3
            var attempts: [AttemptRecord] = []
            var lastRaw = ""
            var lastStructured: MaterializationResponse?
            var lastReport: QualityReport?

            for attempt in 1...maxAttempts {
                let maxTokens = recommendedMaxTokens(attempt: attempt)
                let prompt = buildPromptBundle(
                    templateText: templateText,
                    attempt: attempt
                )

                do {
                    let raw = try await sendClaudeRequest(
                        env: env,
                        prompt: prompt,
                        maxTokens: maxTokens
                    )
                    lastRaw = raw
                    try raw.write(
                        toFile: "/tmp/edunode_llm_smoke_response_attempt_\(attempt).txt",
                        atomically: true,
                        encoding: .utf8
                    )

                    let structured = try decodeFirstJSONObject(MaterializationResponse.self, from: raw)
                    let report = evaluateSkeletonRisk(
                        assistantReply: structured.assistant_reply,
                        markdown: structured.generated_markdown
                    )
                    lastStructured = structured
                    lastReport = report

                    attempts.append(
                        AttemptRecord(
                            attempt: attempt,
                            maxTokens: maxTokens,
                            structuredDecoded: true,
                            skeletonRisk: report.isLikelySkeleton,
                            assistantReplyHead: String(structured.assistant_reply.prefix(160)),
                            generatedMarkdownChars: structured.generated_markdown.count,
                            error: nil
                        )
                    )

                    if !report.isLikelySkeleton {
                        break
                    }
                } catch {
                    attempts.append(
                        AttemptRecord(
                            attempt: attempt,
                            maxTokens: maxTokens,
                            structuredDecoded: false,
                            skeletonRisk: true,
                            assistantReplyHead: "",
                            generatedMarkdownChars: 0,
                            error: error.localizedDescription
                        )
                    )
                }
            }

            try saveAttemptArtifacts(attempts)
            if let structured = lastStructured, let report = lastReport {
                try saveArtifacts(raw: lastRaw, structured: structured, report: report)
            }

            print("SMOKE_PROVIDER_BASE=\(env.baseURL)")
            print("SMOKE_MODEL=\(env.model)")
            print("SMOKE_TEMPLATE=\(env.referenceTemplatePath)")
            print("SMOKE_ATTEMPTS=\(attempts.count)")
            print("SMOKE_ATTEMPT_ARTIFACT=/tmp/edunode_llm_smoke_attempts.json")
            print("SMOKE_ARTIFACT_JSON=/tmp/edunode_llm_smoke_response.json")
            print("SMOKE_ARTIFACT_MD=/tmp/edunode_llm_smoke_markdown.md")

            guard let finalStructured = lastStructured, let finalReport = lastReport else {
                fputs("FAIL | All attempts failed before structured decode.\n", stderr)
                exit(1)
            }

            print("SMOKE_ASSISTANT_REPLY_HEAD=\(finalStructured.assistant_reply.prefix(140))")
            print("SMOKE_MARKDOWN_CHARS=\(finalStructured.generated_markdown.count)")
            print("SMOKE_SUBSTANTIVE_LINES=\(finalReport.substantiveLines)")
            print("SMOKE_HEADING_LINES=\(finalReport.headingLines)")
            print("SMOKE_MISSING_CONTEXT_SIGNAL=\(finalReport.hasMissingContextSignal)")
            print("SMOKE_SKELETON_RISK=\(finalReport.isLikelySkeleton)")

            if finalReport.isLikelySkeleton {
                fputs("FAIL | Generated draft is likely a template skeleton after retries.\n", stderr)
                exit(1)
            }
            print("PASS | Generated draft contains substantive content.")
        } catch {
            fputs("FAIL | \(error.localizedDescription)\n", stderr)
            exit(2)
        }
    }

    private static func loadEnv() throws -> Env {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let envPath = root.appendingPathComponent("EduNode/.env").path
        let content = try String(contentsOfFile: envPath, encoding: .utf8)
        let parsed = parseDotEnv(content)

        func pick(_ key: String) -> String {
            let runtime = ProcessInfo.processInfo.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !runtime.isEmpty { return runtime }
            return parsed[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        let baseURL = pick("EDUNODE_LLM_BASE_URL")
        let model = pick("EDUNODE_LLM_MODEL")
        let apiKey = pick("EDUNODE_LLM_API_KEY")
        let templatePath = pick("EDUNODE_REFERENCE_TEMPLATE_PATH")

        guard !baseURL.isEmpty, !model.isEmpty, !apiKey.isEmpty, !templatePath.isEmpty else {
            throw NSError(domain: "smoke", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing required env in EduNode/.env"])
        }
        return Env(baseURL: baseURL, model: model, apiKey: apiKey, referenceTemplatePath: templatePath)
    }

    private static func parseDotEnv(_ text: String) -> [String: String] {
        var output: [String: String] = [:]
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let line: String
            if trimmed.hasPrefix("export ") {
                line = String(trimmed.dropFirst("export ".count))
            } else {
                line = trimmed
            }
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count != 2 { continue }
            let key = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            var value = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
                value.removeFirst()
                value.removeLast()
            }
            output[key] = value
        }
        return output
    }

    private static func extractPDFText(path: String) throws -> String {
        guard let document = PDFDocument(url: URL(fileURLWithPath: path)) else {
            throw NSError(domain: "smoke", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot open PDF at \(path)"])
        }
        var chunks: [String] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index), let text = page.string else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                chunks.append(trimmed)
            }
        }
        let merged = chunks.joined(separator: "\n\n")
        if merged.isEmpty {
            throw NSError(domain: "smoke", code: 3, userInfo: [NSLocalizedDescriptionKey: "Extracted empty template text from PDF"])
        }
        return String(merged.prefix(7000))
    }

    private static func buildPromptBundle(templateText: String, attempt: Int) -> PromptBundle {
        let zhuhaiContext = """
        课程名称：珠海观鸟美育工作坊
        学科：综合实践（美育）
        学习者：28人，年龄6-13，低龄组需要更明确支架。
        课时：120分钟
        资源约束：望远镜6台、鸟类图鉴3套、巢材包28份；室内+户外场地。

        目标：
        1) 识别7种那洲常见鸟并完成留鸟/候鸟分类。
        2) 解释气候地形对鸟类分布的影响。
        3) 选择合适巢型并说明依据。
        4) 完成巢搭建与展览讲解。
        5) 课后完成至少1次拍图识鸟记录。

        流程草图：
        - 导入：观鸟情境 + 任务说明
        - 知识建构：常见鸟种与分类、栖息环境关系
        - 实践活动：分组观察记录 + 巢材设计搭建
        - 展示交流：作品讲解 + 同伴反馈
        - 迁移延伸：拍图识鸟持续观察任务
        """

        let systemPrompt = """
        You materialize a teacher-facing lesson plan from live pedagogical graph context and a reference template.
        Treat reference/template text as structural and stylistic guidance only, not as authoritative topic facts.
        If reference topic conflicts with live graph topic, always follow the live graph topic.
        Never ask for clarification and never ask the user to choose between multiple topics.
        Do not claim missing context unless the prompt is actually empty.
        Keep section order and labels aligned with the template where possible.
        Each major section must contain substantive content, not title-only placeholders.
        Output strict JSON only with keys assistant_reply and generated_markdown.
        """

        var userPrompt = """
        Live graph context (authoritative):
        \(zhuhaiContext)

        Reference template excerpt (structure/style only, non-authoritative topic facts):
        \(templateText)

        Required sections to preserve when feasible:
        指导思想/设计理念
        文本分析
        学情分析
        学习目标
        教学重点和难点
        教学资源
        教学过程
        作业
        Handout
        教学原文
        """

        if attempt > 1 {
            userPrompt += "\n\nRetry instruction: your previous response was invalid for production. Return complete JSON now. Do not ask questions, do not request extra materials, and fill generated_markdown with substantive lesson-plan content."
        }

        return PromptBundle(system: systemPrompt, user: userPrompt)
    }

    private static func resolvedMessagesURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var url = URL(string: trimmed) else { return nil }
        let lower = trimmed.lowercased()
        if lower.contains("/messages") { return url }
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

    private static func sendClaudeRequest(
        env: Env,
        prompt: PromptBundle,
        maxTokens: Int
    ) async throws -> String {
        guard let url = resolvedMessagesURL(from: env.baseURL) else {
            throw NSError(domain: "smoke", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid base URL"])
        }

        let body = ClaudeRequest(
            model: env.model,
            system: prompt.system,
            messages: [.init(role: "user", content: prompt.user)],
            temperature: 0.2,
            max_tokens: maxTokens
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 240
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(env.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "smoke", code: 5, userInfo: [NSLocalizedDescriptionKey: "Missing HTTP response"])
        }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw NSError(domain: "smoke", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        if let raw = String(data: data, encoding: .utf8), looksLikeHTML(raw) {
            let excerpt = String(raw.prefix(280)).replacingOccurrences(of: "\n", with: "\\n")
            throw NSError(domain: "smoke", code: 8, userInfo: [NSLocalizedDescriptionKey: "Received HTML instead of API JSON: \(excerpt)"])
        }

        let payload = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        let text = payload.content
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if text.isEmpty {
            throw NSError(domain: "smoke", code: 6, userInfo: [NSLocalizedDescriptionKey: "Model returned empty text"])
        }
        return text
    }

    private static func looksLikeHTML(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("<html") || lower.contains("<!doctype html")
    }

    private static func recommendedMaxTokens(attempt: Int) -> Int {
        switch attempt {
        case 1:
            return 6000
        case 2:
            return 10000
        default:
            return 14000
        }
    }

    private static func decodeFirstJSONObject<T: Decodable>(_ type: T.Type, from raw: String) throws -> T {
        let normalized = stripCodeFence(raw)
        if let data = normalized.data(using: .utf8), let decoded = try? JSONDecoder().decode(T.self, from: data) {
            return decoded
        }
        guard let range = firstJSONObjectRange(in: normalized) else {
            throw NSError(domain: "smoke", code: 7, userInfo: [NSLocalizedDescriptionKey: "No JSON object found in model response"])
        }
        let snippet = String(normalized[range])
        let data = Data(snippet.utf8)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func stripCodeFence(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }
        let lines = trimmed.components(separatedBy: .newlines)
        if lines.count >= 3 {
            return lines.dropFirst().dropLast().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    private static func firstJSONObjectRange(in text: String) -> Range<String.Index>? {
        var start: String.Index?
        var depth = 0
        var inString = false
        var escaped = false

        for index in text.indices {
            let ch = text[index]
            if escaped {
                escaped = false
                continue
            }
            if ch == "\\" {
                escaped = true
                continue
            }
            if ch == "\"" {
                inString.toggle()
                continue
            }
            if inString { continue }
            if ch == "{" {
                if start == nil { start = index }
                depth += 1
            } else if ch == "}" {
                depth -= 1
                if depth == 0, let s = start {
                    return s..<text.index(after: index)
                }
            }
        }
        return nil
    }

    struct QualityReport {
        let isLikelySkeleton: Bool
        let hasMissingContextSignal: Bool
        let headingLines: Int
        let substantiveLines: Int
    }

    private static func evaluateSkeletonRisk(assistantReply: String, markdown: String) -> QualityReport {
        let lines = markdown.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let headingLines = lines.filter { $0.hasPrefix("#") || $0.hasPrefix("【") || $0.hasPrefix("[") }.count
        let substantiveLines = lines.filter { line in
            if line.hasPrefix("#") { return false }
            if line.hasSuffix(":") || line.hasSuffix("：") { return false }
            if line == "[what]" || line == "[why]" || line == "[how]" { return false }
            return line.count >= 8
        }.count

        let lowerReply = assistantReply.lowercased()
        let hasMissingContextSignal = lowerReply.contains("no pedagogical graph")
            || lowerReply.contains("no template")
            || lowerReply.contains("no course metadata")
            || lowerReply.contains("please share")
            || lowerReply.contains("could you clarify")
            || lowerReply.contains("which lesson plan")
            || lowerReply.contains("separate projects")
            || assistantReply.contains("请提供")
            || assistantReply.contains("未提供")
            || assistantReply.contains("请粘贴")

        let plainChars = lines.filter { !$0.hasPrefix("#") }.joined().count
        let isLikelySkeleton = hasMissingContextSignal
            || plainChars < 220
            || substantiveLines < 8
            || headingLines >= max(1, substantiveLines)

        return QualityReport(
            isLikelySkeleton: isLikelySkeleton,
            hasMissingContextSignal: hasMissingContextSignal,
            headingLines: headingLines,
            substantiveLines: substantiveLines
        )
    }

    private static func saveArtifacts(
        raw: String,
        structured: MaterializationResponse,
        report: QualityReport
    ) throws {
        try raw.write(toFile: "/tmp/edunode_llm_smoke_response.txt", atomically: true, encoding: .utf8)
        try structured.generated_markdown.write(toFile: "/tmp/edunode_llm_smoke_markdown.md", atomically: true, encoding: .utf8)

        let envelope: [String: Any] = [
            "assistant_reply": structured.assistant_reply,
            "generated_markdown_chars": structured.generated_markdown.count,
            "skeleton_risk": report.isLikelySkeleton,
            "missing_context_signal": report.hasMissingContextSignal,
            "heading_lines": report.headingLines,
            "substantive_lines": report.substantiveLines
        ]
        let data = try JSONSerialization.data(withJSONObject: envelope, options: [.prettyPrinted])
        try data.write(to: URL(fileURLWithPath: "/tmp/edunode_llm_smoke_response.json"))
    }

    private static func saveAttemptArtifacts(_ attempts: [AttemptRecord]) throws {
        let data = try JSONEncoder().encode(attempts)
        try data.write(to: URL(fileURLWithPath: "/tmp/edunode_llm_smoke_attempts.json"))
    }
}
