import Foundation

struct EduLessonTemplateComplianceReport: Hashable, Sendable {
    let missingFrontMatterFields: [String]
    let frontMatterOrderMismatches: [String]
    let missingSectionTitles: [String]
    let sectionOrderMismatches: [String]
    let missingAnalysisSubsectionTitles: [String]
    let analysisOrderMismatches: [String]
    let missingTeachingProcessColumns: [String]
    let missingLearnerAnalysisLabels: [String]
    let missingKeyPointDifficultyLabels: [String]

    var isCompliant: Bool {
        missingFrontMatterFields.isEmpty
            && frontMatterOrderMismatches.isEmpty
            && missingSectionTitles.isEmpty
            && sectionOrderMismatches.isEmpty
            && missingAnalysisSubsectionTitles.isEmpty
            && analysisOrderMismatches.isEmpty
            && missingTeachingProcessColumns.isEmpty
            && missingLearnerAnalysisLabels.isEmpty
            && missingKeyPointDifficultyLabels.isEmpty
    }

    var repairGuidanceText: String {
        var lines: [String] = []

        if !missingFrontMatterFields.isEmpty {
            lines.append("Missing front-matter labels: \(missingFrontMatterFields.joined(separator: " | "))")
        }
        if !frontMatterOrderMismatches.isEmpty {
            lines.append("Front-matter label order mismatch: \(frontMatterOrderMismatches.joined(separator: " -> "))")
        }
        if !missingSectionTitles.isEmpty {
            lines.append("Missing top-level section titles: \(missingSectionTitles.joined(separator: " | "))")
        }
        if !sectionOrderMismatches.isEmpty {
            lines.append("Top-level section order mismatch: \(sectionOrderMismatches.joined(separator: " -> "))")
        }
        if !missingAnalysisSubsectionTitles.isEmpty {
            lines.append("Missing analysis subsection titles: \(missingAnalysisSubsectionTitles.joined(separator: " | "))")
        }
        if !analysisOrderMismatches.isEmpty {
            lines.append("Analysis subsection order mismatch: \(analysisOrderMismatches.joined(separator: " -> "))")
        }
        if !missingTeachingProcessColumns.isEmpty {
            lines.append("Missing teaching-process columns: \(missingTeachingProcessColumns.joined(separator: " | "))")
        }
        if !missingLearnerAnalysisLabels.isEmpty {
            lines.append("Missing learner-analysis labels: \(missingLearnerAnalysisLabels.joined(separator: " | "))")
        }
        if !missingKeyPointDifficultyLabels.isEmpty {
            lines.append("Missing key-point / difficulty labels: \(missingKeyPointDifficultyLabels.joined(separator: " | "))")
        }

        return lines.joined(separator: "\n")
    }

    func withAdditionalMissingTitles(_ titles: [String]) -> EduLessonTemplateComplianceReport {
        guard !titles.isEmpty else { return self }
        let mergedMissingTitles = Array(NSOrderedSet(array: missingSectionTitles + titles)) as? [String]
            ?? (missingSectionTitles + titles)
        return EduLessonTemplateComplianceReport(
            missingFrontMatterFields: missingFrontMatterFields,
            frontMatterOrderMismatches: frontMatterOrderMismatches,
            missingSectionTitles: mergedMissingTitles,
            sectionOrderMismatches: sectionOrderMismatches,
            missingAnalysisSubsectionTitles: missingAnalysisSubsectionTitles,
            analysisOrderMismatches: analysisOrderMismatches,
            missingTeachingProcessColumns: missingTeachingProcessColumns,
            missingLearnerAnalysisLabels: missingLearnerAnalysisLabels,
            missingKeyPointDifficultyLabels: missingKeyPointDifficultyLabels
        )
    }
}

enum EduLessonTemplateComplianceChecker {
    nonisolated static func validate(
        markdown: String,
        referenceDocument: EduLessonReferenceDocument
    ) -> EduLessonTemplateComplianceReport {
        let lines = markdown.components(separatedBy: .newlines)
        let canonicalLines = lines.map(canonicalLine)
        let schema = referenceDocument.templateDocument.schema

        let frontMatterReport = orderedPresenceReport(
            targets: schema.frontMatterFieldLabels,
            in: Array(lines.prefix(18))
        )

        let sectionTitles = referenceDocument.styleProfile.sectionTitles
        let sectionReport = orderedPresenceReport(
            targets: sectionTitles,
            inCanonicalLines: canonicalLines
        )

        let analysisReport = orderedPresenceReport(
            targets: schema.analysisSubsectionTitles,
            inCanonicalLines: canonicalLines
        )

        let processColumns = schema.teachingProcessColumnTitles.filter { !containsTableSeparator($0) }
        let missingProcessColumns = processColumns.filter { column in
            !markdown.localizedCaseInsensitiveContains(column)
        }

        let learnerLabels = requiredLearnerAnalysisLabels(from: referenceDocument)
        let missingLearnerLabels = learnerLabels.filter { label in
            !markdown.localizedCaseInsensitiveContains(label)
        }

        let keyPointDifficultyLabels = schema.keyPointDifficultyLabels.map(trimmedLabel)
        let missingKeyPointDifficultyLabels = keyPointDifficultyLabels.filter { label in
            !markdown.localizedCaseInsensitiveContains(label)
        }

        return EduLessonTemplateComplianceReport(
            missingFrontMatterFields: frontMatterReport.missingTargets,
            frontMatterOrderMismatches: frontMatterReport.orderMismatchTargets,
            missingSectionTitles: sectionReport.missingTargets,
            sectionOrderMismatches: sectionReport.orderMismatchTargets,
            missingAnalysisSubsectionTitles: analysisReport.missingTargets,
            analysisOrderMismatches: analysisReport.orderMismatchTargets,
            missingTeachingProcessColumns: missingProcessColumns,
            missingLearnerAnalysisLabels: missingLearnerLabels,
            missingKeyPointDifficultyLabels: missingKeyPointDifficultyLabels
        )
    }

    private nonisolated static func orderedPresenceReport(
        targets: [String],
        in lines: [String]
    ) -> OrderedPresenceReport {
        let canonicalLines = lines.map(canonicalLine)
        return orderedPresenceReport(targets: targets, inCanonicalLines: canonicalLines)
    }

    private nonisolated static func orderedPresenceReport(
        targets: [String],
        inCanonicalLines canonicalLines: [String]
    ) -> OrderedPresenceReport {
        guard !targets.isEmpty else {
            return OrderedPresenceReport(missingTargets: [], orderMismatchTargets: [])
        }

        var matchedIndexes: [Int] = []
        var matchedTargets: [String] = []
        var missingTargets: [String] = []

        for target in targets {
            let normalizedTarget = normalizedHeading(target)
            guard !normalizedTarget.isEmpty else { continue }
            if let index = canonicalLines.firstIndex(where: { line in
                let normalizedLine = normalizedHeading(line)
                return normalizedLine == normalizedTarget
                    || normalizedLine.hasPrefix(normalizedTarget)
            }) {
                matchedIndexes.append(index)
                matchedTargets.append(target)
            } else {
                missingTargets.append(target)
            }
        }

        var orderMismatchTargets: [String] = []
        var maxSeen = Int.min
        for (index, target) in zip(matchedIndexes, matchedTargets) {
            if index < maxSeen {
                orderMismatchTargets.append(target)
            } else {
                maxSeen = index
            }
        }

        return OrderedPresenceReport(
            missingTargets: missingTargets,
            orderMismatchTargets: orderMismatchTargets
        )
    }

    private nonisolated static func requiredLearnerAnalysisLabels(
        from referenceDocument: EduLessonReferenceDocument
    ) -> [String] {
        let schema = referenceDocument.templateDocument.schema
        var labels: [String] = []

        if schema.sections.contains(where: { $0.kind == .priorKnowledge }) {
            let raw = schema.sections.first(where: { $0.kind == .priorKnowledge })?.title ?? "已有知识"
            labels.append(trimmedLabel(raw))
        }
        if schema.sections.contains(where: { $0.kind == .missingKnowledge }) {
            let raw = schema.sections.first(where: { $0.kind == .missingKnowledge })?.title ?? "未有知识"
            labels.append(trimmedLabel(raw))
        }

        if labels.isEmpty,
           referenceDocument.styleProfile.featureHints.contains(where: {
               $0.localizedCaseInsensitiveContains("prior knowledge")
                   || $0.localizedCaseInsensitiveContains("已有知识")
           }) {
            labels.append(contentsOf: ["已有知识", "未有知识"])
        }

        return Array(NSOrderedSet(array: labels)) as? [String] ?? labels
    }

    private nonisolated static func containsTableSeparator(_ value: String) -> Bool {
        value.contains("|")
    }

    private nonisolated static func canonicalLine(_ rawLine: String) -> String {
        var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.hasPrefix("#") {
            line = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
            line = String(line.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let match = line.range(of: #"^\d+[\.\)]\s*"#, options: .regularExpression) {
            line.removeSubrange(match)
            line = line.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if line.hasPrefix("|"), line.hasSuffix("|") {
            line = line.trimmingCharacters(in: CharacterSet(charactersIn: "|"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return line
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

    private nonisolated static func trimmedLabel(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet(charactersIn: ":：").union(.whitespacesAndNewlines))
    }
}

enum EduLessonTemplateStructuralNormalizer {
    static func normalize(
        markdown: String,
        referenceDocument: EduLessonReferenceDocument
    ) -> String {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = trimmed.components(separatedBy: .newlines)
        let schema = referenceDocument.templateDocument.schema
        let sectionSpecs = orderedSectionSpecs(from: referenceDocument)
        let extractedBodies = extractSectionBodies(
            from: lines,
            sectionSpecs: sectionSpecs
        )
        let frontMatterLines = extractFrontMatterLines(
            from: lines,
            labels: schema.frontMatterFieldLabels
        )

        var output: [String] = []
        if !frontMatterLines.isEmpty {
            output.append(contentsOf: frontMatterLines)
            output.append("")
        }

        for spec in sectionSpecs {
            output.append(headingLine(for: spec))
            let body = normalizedBody(
                for: spec,
                rawBody: extractedBodies[spec.title] ?? "",
                referenceDocument: referenceDocument
            )
            if !body.isEmpty {
                output.append(body)
            }
            output.append("")
        }

        return compactMarkdown(output.joined(separator: "\n"))
    }

    private struct SectionSpec: Hashable {
        let title: String
        let kind: EduLessonTemplateSectionKind
    }

    private static func orderedSectionSpecs(
        from referenceDocument: EduLessonReferenceDocument
    ) -> [SectionSpec] {
        var sectionLookup: [String: EduLessonTemplateSectionKind] = [:]
        for section in referenceDocument.templateDocument.schema.sections {
            let key = normalizedTitle(section.title)
            if sectionLookup[key] == nil {
                sectionLookup[key] = section.kind
            }
        }

        return referenceDocument.styleProfile.sectionTitles.map { title in
            SectionSpec(
                title: title,
                kind: sectionLookup[normalizedTitle(title)] ?? .generic
            )
        }
    }

    private static func extractFrontMatterLines(
        from lines: [String],
        labels: [String]
    ) -> [String] {
        guard !labels.isEmpty else { return [] }

        return labels.map { label in
            if let existing = lines.first(where: { matchesFieldLine($0, label: label) }) {
                return canonicalFieldLine(existing, label: label)
            }
            let separator = label.containsChineseCharacters ? "：" : ":"
            return "\(label)\(separator)"
        }
    }

    private static func extractSectionBodies(
        from lines: [String],
        sectionSpecs: [SectionSpec]
    ) -> [String: String] {
        guard !lines.isEmpty, !sectionSpecs.isEmpty else { return [:] }

        var boundaries: [(spec: SectionSpec, lineIndex: Int)] = []
        var seenTitles = Set<String>()

        for (index, line) in lines.enumerated() {
            guard let spec = matchedSectionSpec(
                for: line,
                sectionSpecs: sectionSpecs,
                seenTitles: seenTitles
            ) else {
                continue
            }
            let normalized = normalizedTitle(spec.title)
            guard !seenTitles.contains(normalized) else { continue }
            seenTitles.insert(normalized)
            boundaries.append((spec, index))
        }

        guard !boundaries.isEmpty else { return [:] }

        var bodies: [String: String] = [:]
        for (offset, boundary) in boundaries.enumerated() {
            let endIndex = offset + 1 < boundaries.count
                ? boundaries[offset + 1].lineIndex
                : lines.count
            let rawBody = lines[(boundary.lineIndex + 1)..<endIndex].joined(separator: "\n")
            let cleaned = cleanedSectionBody(rawBody, title: boundary.spec.title)
            bodies[boundary.spec.title] = cleaned
        }
        return bodies
    }

    private static func matchedSectionSpec(
        for line: String,
        sectionSpecs: [SectionSpec],
        seenTitles: Set<String>
    ) -> SectionSpec? {
        let canonical = canonicalizedLine(line)
        let normalizedLine = normalizedTitle(canonical)
        guard !normalizedLine.isEmpty else { return nil }

        return sectionSpecs.first { spec in
            let normalizedSpecTitle = normalizedTitle(spec.title)
            guard !seenTitles.contains(normalizedSpecTitle) else { return false }
            if normalizedLine == normalizedSpecTitle {
                return true
            }
            if aliases(for: spec.kind).contains(where: { normalizedTitle($0) == normalizedLine }) {
                return true
            }
            if spec.kind == .learnerAnalysis,
               let labels = learnerAnalysisLabels(for: sectionSpecs, spec: spec),
               labels.contains(where: { normalizedLine.hasPrefix(normalizedTitle(trimmedTitleLabel($0))) }) {
                return true
            }
            return false
        }
    }

    private static func cleanedSectionBody(
        _ body: String,
        title: String
    ) -> String {
        var lines = body.components(separatedBy: .newlines)
        while let first = lines.first,
              normalizedTitle(canonicalizedLine(first)) == normalizedTitle(title) {
            lines.removeFirst()
        }
        return compactMarkdown(lines.joined(separator: "\n"))
    }

    private static func normalizedBody(
        for spec: SectionSpec,
        rawBody: String,
        referenceDocument: EduLessonReferenceDocument
    ) -> String {
        let schema = referenceDocument.templateDocument.schema
        var body = rawBody.trimmingCharacters(in: .whitespacesAndNewlines)

        switch spec.kind {
        case .learnerAnalysis:
            body = cleanedLearnerAnalysisBody(
                body,
                labels: schema.learnerAnalysisFieldLabels
            )
        case .keyDifficulties:
            body = ensuringBlockLabels(
                in: body,
                labels: schema.keyPointDifficultyLabels
            )
        case .learningObjectives:
            if body.isEmpty,
               schema.styleNotes.contains(where: {
                   $0.localizedCaseInsensitiveContains("learner-outcome lead sentence")
               }) {
                body = schema.detectedLanguageCode == "zh"
                    ? "在学习本课后，学生能够："
                    : "After this lesson, students will be able to:"
            }
        case .teachingProcess:
            body = ensuringProcessTable(
                in: body,
                columns: schema.teachingProcessColumnTitles
            )
        default:
            break
        }

        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func ensuringInlineLabels(
        in body: String,
        labels: [String]
    ) -> String {
        guard !labels.isEmpty else { return body }
        var blocks: [String] = []
        if !body.isEmpty {
            blocks.append(body)
        }
        for label in labels {
            let trimmed = trimmedTitleLabel(label)
            guard !trimmed.isEmpty else { continue }
            if !body.localizedCaseInsensitiveContains(trimmed) {
                let display = label.hasSuffix("：") || label.hasSuffix(":")
                    ? label
                    : label + "："
                blocks.append(display)
            }
        }
        return compactMarkdown(blocks.joined(separator: "\n\n"))
    }

    private static func cleanedLearnerAnalysisBody(
        _ body: String,
        labels: [String]
    ) -> String {
        guard !labels.isEmpty else { return body }

        let lines = body.components(separatedBy: .newlines)
        var introLines: [String] = []
        var firstLineByLabel: [String: String] = [:]
        var seenAnyLabel = false

        for rawLine in lines {
            let line = canonicalizedLine(rawLine)
            guard !line.isEmpty else { continue }
            if let matchedLabel = labels.first(where: { label in
                line.localizedCaseInsensitiveContains(trimmedTitleLabel(label))
            }) {
                let key = normalizedTitle(trimmedTitleLabel(matchedLabel))
                if firstLineByLabel[key] == nil {
                    firstLineByLabel[key] = line
                }
                seenAnyLabel = true
            } else if !seenAnyLabel {
                introLines.append(line)
            }
        }

        if firstLineByLabel.isEmpty {
            return ensuringInlineLabels(in: body, labels: labels)
        }

        var blocks = introLines
        for label in labels {
            let key = normalizedTitle(trimmedTitleLabel(label))
            if let line = firstLineByLabel[key] {
                blocks.append(line)
            } else {
                let display = label.hasSuffix("：") || label.hasSuffix(":") ? label : label + "："
                blocks.append(display)
            }
        }
        return compactMarkdown(blocks.joined(separator: "\n\n"))
    }

    private static func ensuringBlockLabels(
        in body: String,
        labels: [String]
    ) -> String {
        guard !labels.isEmpty else { return body }
        var blocks: [String] = []
        if !body.isEmpty {
            blocks.append(body)
        }
        for label in labels where !body.localizedCaseInsensitiveContains(trimmedTitleLabel(label)) {
            blocks.append(label)
        }
        return compactMarkdown(blocks.joined(separator: "\n\n"))
    }

    private static func ensuringProcessTable(
        in body: String,
        columns: [String]
    ) -> String {
        let filtered = columns.filter { !containsTableMarker($0) }
        guard !filtered.isEmpty else { return body }

        let hasAllColumns = filtered.allSatisfy { column in
            body.localizedCaseInsensitiveContains(column)
        }
        if hasAllColumns {
            return body
        }

        let header = "| " + filtered.joined(separator: " | ") + " |"
        let separator = "| " + Array(repeating: "---", count: filtered.count).joined(separator: " | ") + " |"
        let placeholderRow = "| " + Array(repeating: "-", count: filtered.count).joined(separator: " | ") + " |"
        let table = [header, separator, placeholderRow].joined(separator: "\n")

        if body.isEmpty {
            return table
        }
        return compactMarkdown(body + "\n\n" + table)
    }

    private static func headingLine(for spec: SectionSpec) -> String {
        switch spec.kind {
        case .textAnalysisWhat, .textAnalysisWhy, .textAnalysisHow, .unitPosition:
            return "### \(spec.title)"
        default:
            return "## \(spec.title)"
        }
    }

    private static func matchesFieldLine(
        _ line: String,
        label: String
    ) -> Bool {
        let canonical = canonicalizedLine(line)
        let normalizedLine = normalizedTitle(canonical)
        let normalizedLabel = normalizedTitle(label)
        return normalizedLine.hasPrefix(normalizedLabel)
            && (canonical.contains("：") || canonical.contains(":"))
    }

    private static func canonicalFieldLine(
        _ line: String,
        label: String
    ) -> String {
        let canonical = canonicalizedLine(line)
        let separator = canonical.contains("：") ? "：" : ":"
        guard let range = canonical.range(of: separator) else {
            let fallbackSeparator = label.containsChineseCharacters ? "：" : ":"
            return "\(label)\(fallbackSeparator)"
        }
        let value = String(canonical[range.upperBound...])
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        return value.isEmpty ? "\(label)\(separator)" : "\(label)\(separator) \(value)"
    }

    private static func compactMarkdown(_ markdown: String) -> String {
        markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func canonicalizedLine(_ rawLine: String) -> String {
        var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.hasPrefix("#") {
            line = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
            line = String(line.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let match = line.range(of: #"^\d+[\.\)]\s*"#, options: .regularExpression) {
            line.removeSubrange(match)
            line = line.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if line.hasPrefix("|"), line.hasSuffix("|") {
            line = line.trimmingCharacters(in: CharacterSet(charactersIn: "|"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return line
    }

    private static func normalizedTitle(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
            .replacingOccurrences(of: "：", with: ":")
            .replacingOccurrences(of: "[\\p{P}\\p{S}\\s]+", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func trimmedTitleLabel(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet(charactersIn: ":：").union(.whitespacesAndNewlines))
    }

    private static func containsTableMarker(_ value: String) -> Bool {
        value.contains("|")
    }

    private static func aliases(for kind: EduLessonTemplateSectionKind) -> [String] {
        switch kind {
        case .designRationale:
            return ["设计理念", "指导思想"]
        case .textAnalysis:
            return ["教材分析", "内容分析"]
        case .unitPosition:
            return ["本课在单元整体教学中的位置", "position in the unit", "position within the unit"]
        case .textAnalysisWhat:
            return ["[what]", "what"]
        case .textAnalysisWhy:
            return ["[why]", "why"]
        case .textAnalysisHow:
            return ["[how]", "how"]
        case .learnerAnalysis:
            return ["学生分析", "learner analysis", "student analysis"]
        case .learningObjectives:
            return ["教学目标", "learning objectives", "objectives"]
        case .keyDifficulties:
            return ["重点和难点", "重难点", "key points and difficulties", "teaching focus"]
        case .teachingResources:
            return ["资源准备", "teaching resources", "materials"]
        case .teachingProcess:
            return ["教学过程", "教学流程", "课堂过程", "teaching process", "procedure"]
        case .homework:
            return ["课后作业", "assignment", "homework"]
        case .handout:
            return ["讲义", "worksheet"]
        case .sourceText:
            return ["教学原文", "阅读原文", "文本原文", "source text", "teaching text"]
        default:
            return []
        }
    }

    private static func learnerAnalysisLabels(
        for sectionSpecs: [SectionSpec],
        spec: SectionSpec
    ) -> [String]? {
        guard spec.kind == .learnerAnalysis else { return nil }
        return sectionSpecs
            .filter { $0.kind == .priorKnowledge || $0.kind == .missingKnowledge }
            .map(\.title)
    }
}

private struct OrderedPresenceReport: Hashable, Sendable {
    let missingTargets: [String]
    let orderMismatchTargets: [String]
}

private extension String {
    var containsChineseCharacters: Bool {
        unicodeScalars.contains {
            ($0.value >= 0x4E00 && $0.value <= 0x9FFF)
                || ($0.value >= 0x3400 && $0.value <= 0x4DBF)
        }
    }
}
