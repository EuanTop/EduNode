import Foundation
#if canImport(PDFKit)
import PDFKit
#endif

enum EduLessonTemplateImportError: LocalizedError {
    case unreadableFile
    case unsupportedPDFExtraction
    case emptyTemplate

    var errorDescription: String? {
        let isChinese = Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
        switch self {
        case .unreadableFile:
            return isChinese ? "无法读取模板文件内容。" : "Unable to read the template file."
        case .unsupportedPDFExtraction:
            return isChinese ? "当前平台无法提取 PDF 模板文本。" : "This platform cannot extract text from the PDF template."
        case .emptyTemplate:
            return isChinese ? "模板内容为空，无法继续分析。" : "The template is empty and cannot be analyzed."
        }
    }
}

enum EduLessonTemplateSectionKind: String, Codable, Hashable, CaseIterable {
    case courseInfo
    case designRationale
    case textAnalysis
    case knowledgeStructure
    case unitPosition
    case textAnalysisWhat
    case textAnalysisWhy
    case textAnalysisHow
    case learnerAnalysis
    case priorKnowledge
    case missingKnowledge
    case learningObjectives
    case keyDifficulties
    case teachingResources
    case teachingProcess
    case homework
    case handout
    case sourceText
    case reflection
    case generic
}

struct EduLessonTemplateSection: Identifiable, Codable, Hashable {
    let id: String
    let kind: EduLessonTemplateSectionKind
    let title: String
    let order: Int
    let excerpt: String
}

struct EduLessonTemplateSchema: Codable, Hashable {
    let sourceName: String
    let detectedLanguageCode: String
    let sections: [EduLessonTemplateSection]
    let frontMatterFieldLabels: [String]
    let teachingProcessColumnTitles: [String]
    let analysisSubsectionTitles: [String]
    let learnerAnalysisFieldLabels: [String]
    let keyPointDifficultyLabels: [String]
    let styleNotes: [String]

    var outlineText: String {
        let hasLearnerAnalysis = sections.contains { $0.kind == .learnerAnalysis }
        return sections
            .filter {
                if $0.kind == .courseInfo && !frontMatterFieldLabels.isEmpty {
                    return false
                }
                if hasLearnerAnalysis && ($0.kind == .priorKnowledge || $0.kind == .missingKnowledge) {
                    return false
                }
                return true
            }
            .sorted { $0.order < $1.order }
            .map { "\($0.order + 1). \($0.title)" }
            .joined(separator: "\n")
    }
}

struct EduLessonTemplateDocument: Identifiable, Hashable {
    let id: UUID
    let fileName: String
    let rawText: String
    let schema: EduLessonTemplateSchema

    nonisolated init(
        id: UUID = UUID(),
        fileName: String,
        rawText: String,
        schema: EduLessonTemplateSchema
    ) {
        self.id = id
        self.fileName = fileName
        self.rawText = rawText
        self.schema = schema
    }
}

enum EduLessonTemplateDocumentLoader {
    static func load(from url: URL) throws -> EduLessonTemplateDocument {
        let rawText = try extractText(from: url)
        return try EduLessonTemplateParser.parse(
            text: rawText,
            sourceName: url.lastPathComponent
        )
    }

    static func extractText(from url: URL) throws -> String {
        let pathExtension = url.pathExtension.lowercased()
        if pathExtension == "pdf" {
            #if canImport(PDFKit)
            guard let document = PDFDocument(url: url) else {
                throw EduLessonTemplateImportError.unreadableFile
            }
            let rawText = (0..<document.pageCount).compactMap { pageIndex in
                document.page(at: pageIndex)?.string
            }.joined(separator: "\n\n")
            let normalized = normalizeRawText(rawText)
            guard !normalized.isEmpty else {
                throw EduLessonTemplateImportError.emptyTemplate
            }
            return normalized
            #else
            throw EduLessonTemplateImportError.unsupportedPDFExtraction
            #endif
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw EduLessonTemplateImportError.unreadableFile
        }

        for encoding in [String.Encoding.utf8, .unicode, .utf16LittleEndian, .utf16BigEndian] {
            if let string = String(data: data, encoding: encoding) {
                let normalized = normalizeRawText(string)
                if !normalized.isEmpty {
                    return normalized
                }
            }
        }

        throw EduLessonTemplateImportError.unreadableFile
    }

    private static func normalizeRawText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{000C}", with: "\n")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                line.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum EduLessonTemplateParser {
    nonisolated static func parse(
        text: String,
        sourceName: String
    ) throws -> EduLessonTemplateDocument {
        let normalizedText = normalize(text)
        guard !normalizedText.isEmpty else {
            throw EduLessonTemplateImportError.emptyTemplate
        }

        let focusedText = trimmedTemplateWindow(from: normalizedText)
        let sections = extractedSections(from: focusedText)
        let schema = EduLessonTemplateSchema(
            sourceName: sourceName,
            detectedLanguageCode: detectedLanguageCode(for: focusedText),
            sections: sections,
            frontMatterFieldLabels: frontMatterFieldLabels(from: focusedText),
            teachingProcessColumnTitles: teachingProcessColumnTitles(from: focusedText),
            analysisSubsectionTitles: analysisSubsectionTitles(from: sections),
            learnerAnalysisFieldLabels: learnerAnalysisFieldLabels(from: sections),
            keyPointDifficultyLabels: keyPointDifficultyLabels(from: focusedText),
            styleNotes: styleNotes(from: focusedText, sections: sections)
        )
        return EduLessonTemplateDocument(
            fileName: sourceName,
            rawText: focusedText,
            schema: schema
        )
    }

    private struct HeadingRule {
        let kind: EduLessonTemplateSectionKind
        let aliases: [String]
    }

    private nonisolated static let headingRules: [HeadingRule] = [
        HeadingRule(kind: .courseInfo, aliases: [
            "课程信息", "基本课程信息", "教师姓名", "学生年级", "教材版本", "单元及语篇", "课型及主题",
            "course info", "basic information", "lesson information"
        ]),
        HeadingRule(kind: .designRationale, aliases: [
            "指导思想/设计理念", "设计理念", "指导思想", "teaching philosophy", "design rationale", "rationale"
        ]),
        HeadingRule(kind: .knowledgeStructure, aliases: [
            "结构化知识图表", "知识图表", "structured knowledge map", "structured knowledge graph", "knowledge structure"
        ]),
        HeadingRule(kind: .unitPosition, aliases: [
            "本课在单元整体教学设计中的位置", "本课在单元整体教学中的位置", "position in the unit", "position within the unit"
        ]),
        HeadingRule(kind: .textAnalysis, aliases: [
            "文本分析", "教材分析", "内容分析", "text analysis", "material analysis"
        ]),
        HeadingRule(kind: .textAnalysisWhat, aliases: [
            "【what】", "[what]", "what"
        ]),
        HeadingRule(kind: .textAnalysisWhy, aliases: [
            "【why】", "[why]", "why"
        ]),
        HeadingRule(kind: .textAnalysisHow, aliases: [
            "【how】", "[how]", "how"
        ]),
        HeadingRule(kind: .learnerAnalysis, aliases: [
            "学情分析", "学生分析", "learner analysis", "student analysis"
        ]),
        HeadingRule(kind: .priorKnowledge, aliases: [
            "已有知识", "已有基础", "prior knowledge", "existing knowledge"
        ]),
        HeadingRule(kind: .missingKnowledge, aliases: [
            "未有知识", "欠缺知识", "缺失知识", "knowledge gaps", "missing knowledge"
        ]),
        HeadingRule(kind: .learningObjectives, aliases: [
            "学习目标", "教学目标", "learning objectives", "objectives"
        ]),
        HeadingRule(kind: .keyDifficulties, aliases: [
            "教学重点和难点", "重点和难点", "重难点", "key points and difficulties", "teaching focus"
        ]),
        HeadingRule(kind: .teachingResources, aliases: [
            "教学资源", "资源准备", "teaching resources", "materials"
        ]),
        HeadingRule(kind: .teachingProcess, aliases: [
            "教学过程", "教学流程", "课堂过程", "teaching process", "procedure"
        ]),
        HeadingRule(kind: .homework, aliases: [
            "作业", "课后作业", "assignment", "homework"
        ]),
        HeadingRule(kind: .handout, aliases: [
            "Handout", "讲义", "worksheet"
        ]),
        HeadingRule(kind: .sourceText, aliases: [
            "教学原文", "阅读原文", "文本原文", "source text", "teaching text"
        ]),
        HeadingRule(kind: .reflection, aliases: [
            "教学反思", "课后反思", "反思", "reflection", "post-lesson reflection"
        ])
    ]

    private nonisolated static func extractedSections(from text: String) -> [EduLessonTemplateSection] {
        let lines = text.components(separatedBy: .newlines)
        let processColumnHeadings = Set(
            teachingProcessColumnTitles(from: text).map(normalizedHeading)
        )
        var detected: [(kind: EduLessonTemplateSectionKind, title: String, order: Int, startLine: Int)] = []

        for (index, rawLine) in lines.enumerated() {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let match = matchedHeading(for: trimmed) else { continue }
            let normalizedLine = normalizedHeading(trimmed)
            if detected.contains(where: { $0.kind == .teachingProcess })
                && processColumnHeadings.contains(normalizedLine) {
                continue
            }
            let previous = detected.last
            if previous?.kind == match.kind {
                continue
            }
            detected.append((kind: match.kind, title: trimmed, order: detected.count, startLine: index))
        }

        if detected.isEmpty {
            return [
                EduLessonTemplateSection(
                    id: EduLessonTemplateSectionKind.generic.rawValue,
                    kind: .generic,
                    title: "Template Body",
                    order: 0,
                    excerpt: excerpt(from: text)
                )
            ]
        }

        var sections: [EduLessonTemplateSection] = []
        for (index, item) in detected.enumerated() {
            let endLine = index + 1 < detected.count ? detected[index + 1].startLine : lines.count
            let content = lines[item.startLine..<endLine].joined(separator: "\n")
            sections.append(
                EduLessonTemplateSection(
                    id: "\(item.kind.rawValue)-\(index)",
                    kind: item.kind,
                    title: item.title,
                    order: item.order,
                    excerpt: excerpt(from: content)
                )
            )
        }

        return sections
    }

    private nonisolated static func trimmedTemplateWindow(from text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        guard !lines.isEmpty else { return text }

        let courseInfoAnchors = [
            "教师姓名", "学生年级", "教材版本", "单元及语篇", "课型及主题",
            "Teacher Name", "Student Grade", "Textbook Version", "Unit and Text", "Lesson Type and Theme"
        ]
        let firstCourseInfoIndex = lines.firstIndex { line in
            courseInfoAnchors.contains { anchor in
                line.localizedCaseInsensitiveContains(anchor)
            }
        }
        let fallbackRelevantIndex = lines.firstIndex(where: isPotentialTemplateStartLine)
        guard let firstRelevantIndex = firstCourseInfoIndex ?? fallbackRelevantIndex else {
            return text
        }

        let trimmed = lines[firstRelevantIndex...]
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? text : trimmed
    }

    private nonisolated static func isPotentialTemplateStartLine(_ rawLine: String) -> Bool {
        let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if matchedHeading(for: trimmed) != nil {
            return true
        }
        let courseInfoAnchors = [
            "教师姓名", "学生年级", "教材版本", "单元及语篇", "课型及主题",
            "teacher", "student grade", "textbook", "unit", "lesson type", "theme"
        ]
        return courseInfoAnchors.contains { anchor in
            trimmed.localizedCaseInsensitiveContains(anchor)
        }
    }

    private nonisolated static func matchedHeading(for line: String) -> HeadingRule? {
        guard !line.isEmpty else { return nil }
        let normalized = normalizedHeading(line)
        guard !normalized.isEmpty else { return nil }

        return headingRules.first { rule in
            rule.aliases.contains { alias in
                let normalizedAlias = normalizedHeading(alias)
                if normalized == normalizedAlias {
                    return true
                }
                if requiresFieldStylePrefix(rule.kind) {
                    return hasFieldStylePrefix(line: line, alias: alias)
                }
                if normalized.hasPrefix(normalizedAlias)
                    && normalized.count <= normalizedAlias.count + 8 {
                    return true
                }
                return false
            }
        }
    }

    private nonisolated static func requiresFieldStylePrefix(
        _ kind: EduLessonTemplateSectionKind
    ) -> Bool {
        kind == .courseInfo || kind == .priorKnowledge || kind == .missingKnowledge
    }

    private nonisolated static func hasFieldStylePrefix(
        line: String,
        alias: String
    ) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let loweredLine = trimmed.lowercased()
        let loweredAlias = alias.lowercased()
        guard loweredLine.hasPrefix(loweredAlias) else { return false }
        let remainder = trimmed.dropFirst(alias.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return remainder.hasPrefix(":") || remainder.hasPrefix("：")
    }

    private nonisolated static func detectedLanguageCode(for text: String) -> String {
        let chineseScalars = text.unicodeScalars.filter {
            ($0.value >= 0x4E00 && $0.value <= 0x9FFF)
                || ($0.value >= 0x3400 && $0.value <= 0x4DBF)
        }.count
        return chineseScalars > max(text.count / 20, 12) ? "zh" : "en"
    }

    private nonisolated static func frontMatterFieldLabels(from text: String) -> [String] {
        let candidateLabels = [
            "教师姓名", "学生年级", "教材版本", "单元及语篇", "课型及主题",
            "Teacher Name", "Student Grade", "Textbook Version", "Unit and Text", "Lesson Type and Theme"
        ]
        let lines = text.components(separatedBy: .newlines)
        var results: [String] = []

        for line in lines.prefix(18) {
            for label in candidateLabels {
                let hasLabel = line.localizedCaseInsensitiveContains(label)
                    && (line.contains("：") || line.contains(":"))
                if hasLabel && !results.contains(label) {
                    results.append(label)
                }
            }
        }
        return results
    }

    private nonisolated static func teachingProcessColumnTitles(from text: String) -> [String] {
        let candidateHeaders = [
            "学习目标",
            "学习活动、活动层次及时间",
            "设计意图",
            "效果评价",
            "Learning Objectives",
            "Learning Activities, Levels, and Time",
            "Design Intent",
            "Evaluation"
        ]
        let lines = text.components(separatedBy: .newlines)
        var results: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            for header in candidateHeaders {
                let exactMatch = trimmed.localizedCaseInsensitiveCompare(header) == .orderedSame
                let containedMatch = trimmed.localizedCaseInsensitiveContains(header)
                if (exactMatch || containedMatch) && !results.contains(header) {
                    results.append(header)
                }
            }
        }
        return results
    }

    private nonisolated static func analysisSubsectionTitles(
        from sections: [EduLessonTemplateSection]
    ) -> [String] {
        sections
            .filter {
                $0.kind == .textAnalysisWhat
                    || $0.kind == .textAnalysisWhy
                    || $0.kind == .textAnalysisHow
            }
            .sorted { $0.order < $1.order }
            .map(\.title)
    }

    private nonisolated static func learnerAnalysisFieldLabels(
        from sections: [EduLessonTemplateSection]
    ) -> [String] {
        sections
            .filter {
                $0.kind == .priorKnowledge
                    || $0.kind == .missingKnowledge
            }
            .sorted { $0.order < $1.order }
            .map(\.title)
    }

    private nonisolated static func keyPointDifficultyLabels(
        from text: String
    ) -> [String] {
        let candidateLabels = [
            "（一）教学重点",
            "(一)教学重点",
            "一、教学重点",
            "（二）教学难点",
            "(二)教学难点",
            "二、教学难点"
        ]
        let lines = text.components(separatedBy: .newlines)
        var results: [String] = []
        var seenNormalized: Set<String> = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let normalizedLine = normalizedHeading(trimmed)
            for label in candidateLabels where trimmed.localizedCaseInsensitiveCompare(label) == .orderedSame {
                let normalizedLabel = normalizedHeading(label)
                if normalizedLine == normalizedLabel && !seenNormalized.contains(normalizedLine) {
                    results.append(trimmed)
                    seenNormalized.insert(normalizedLine)
                }
            }
        }
        return results
    }

    private nonisolated static func styleNotes(
        from text: String,
        sections: [EduLessonTemplateSection]
    ) -> [String] {
        let normalized = normalizedHeading(text)
        var notes: [String] = []

        if normalized.contains("what") && normalized.contains("why") && normalized.contains("how") {
            notes.append("Template includes a what/why/how analytical sub-structure.")
        }
        if normalized.contains("学习活动活动层次及时间")
            || normalized.contains("learningactivitiesactivitylevelandtime") {
            notes.append("Teaching process expects a time-annotated activity table.")
        }
        if normalized.contains("设计意图") || normalized.contains("designintent") {
            notes.append("Teaching process foregrounds explicit design intent for each activity.")
        }
        if normalized.contains("效果评价") || normalized.contains("evaluation") {
            notes.append("Teaching process explicitly asks for effect-evaluation evidence.")
        }
        if normalized.contains("教学重点和难点")
            || normalized.contains("keypointsanddifficulties") {
            notes.append("Template separates key teaching points from learning difficulties.")
        }
        if !frontMatterFieldLabels(from: text).isEmpty {
            notes.append("Template opens with a front-matter information block and the field labels should be preserved.")
        }
        if teachingProcessColumnTitles(from: text).count >= 4 {
            notes.append("Teaching process is organized as a multi-column table and the column titles should be preserved exactly.")
        }
        if sections.contains(where: { $0.kind == .knowledgeStructure }) {
            notes.append("Template includes a structured knowledge-map section before detailed analysis.")
        }
        if normalized.contains("在学习本课后学生能够")
            || normalized.contains("afterthislessonstudentswillbeableto") {
            notes.append("Learning objectives are introduced with an explicit learner-outcome lead sentence.")
        }
        if normalized.contains("一教学重点") && normalized.contains("二教学难点") {
            notes.append("Key points and difficulties are split into two numbered sub-parts.")
        }
        if sections.contains(where: { $0.kind == .homework }) {
            notes.append("Template keeps homework as an explicit post-lesson section.")
        }
        if sections.contains(where: { $0.kind == .handout }) {
            notes.append("Template includes a handout appendix section after the core lesson-plan body.")
        }
        if sections.contains(where: { $0.kind == .sourceText }) {
            notes.append("Template appends the teaching/source text as a final reference section.")
        }
        if normalized.contains("activity1") {
            notes.append("Teaching process uses numbered activity labels such as Activity 1, Activity 2, and so on.")
        }
        if hasLongParagraphStyle(text) {
            notes.append("The template favors formal expository paragraphs rather than terse note fragments.")
        }

        return notes
    }

    private nonisolated static func hasLongParagraphStyle(_ text: String) -> Bool {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return false }
        let proseLines = lines.filter {
            !$0.hasPrefix("1.") && !$0.hasPrefix("2.") && !$0.hasPrefix("3.")
                && !$0.hasPrefix("- ") && !$0.hasPrefix("* ")
        }
        guard !proseLines.isEmpty else { return false }
        let averageLength = proseLines.map(\.count).reduce(0, +) / proseLines.count
        return averageLength >= 32
    }

    private nonisolated static func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{000C}", with: "\n")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func normalizedHeading(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
            .replacingOccurrences(of: "：", with: ":")
            .replacingOccurrences(of: "[\\p{P}\\p{S}\\s]+", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func excerpt(from text: String) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\n\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if collapsed.count <= 360 {
            return collapsed
        }
        let endIndex = collapsed.index(collapsed.startIndex, offsetBy: 360)
        return String(collapsed[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}
