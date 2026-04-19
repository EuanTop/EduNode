import Foundation

enum EduLessonTemplateAlignmentService {
    static func align(
        markdown candidateMarkdown: String,
        settings: EduAgentProviderSettings,
        file: GNodeWorkspaceFile,
        referenceDocument: EduLessonReferenceDocument
    ) async throws -> String {
        let initialReport = EduLessonTemplateComplianceChecker.validate(
            markdown: candidateMarkdown,
            referenceDocument: referenceDocument
        )
        guard !initialReport.isCompliant else {
            return candidateMarkdown
        }

        let structurallyAligned = EduLessonTemplateStructuralNormalizer.normalize(
            markdown: candidateMarkdown,
            referenceDocument: referenceDocument
        )
        let structuralReport = EduLessonTemplateComplianceChecker.validate(
            markdown: structurallyAligned,
            referenceDocument: referenceDocument
        )
        let emptyInitiallyMissingTitles = emptyBodyTitlesRequiringRepair(
            originalReport: initialReport,
            alignedMarkdown: structurallyAligned,
            referenceDocument: referenceDocument
        )
        if structuralReport.isCompliant && emptyInitiallyMissingTitles.isEmpty {
            return structurallyAligned
        }

        do {
            let client = EduOpenAICompatibleClient(settings: settings)
            let repairReply = try await client.complete(
                messages: EduLessonPlanMaterializationPromptBuilder.repairMessages(
                    settings: settings,
                    file: file,
                    currentMarkdown: structurallyAligned,
                    referenceDocument: referenceDocument,
                    complianceReport: structuralReport.withAdditionalMissingTitles(
                        emptyInitiallyMissingTitles
                    )
                )
            )
            let repaired = try EduAgentJSONParser.decodeFirstJSONObject(
                EduLessonMaterializationResponse.self,
                from: repairReply
            )
            return EduLessonTemplateStructuralNormalizer.normalize(
                markdown: repaired.generatedMarkdown,
                referenceDocument: referenceDocument
            )
        } catch {
            return structurallyAligned
        }
    }

    private nonisolated static func emptyBodyTitlesRequiringRepair(
        originalReport: EduLessonTemplateComplianceReport,
        alignedMarkdown: String,
        referenceDocument: EduLessonReferenceDocument
    ) -> [String] {
        let candidateTitles = Array(
            NSOrderedSet(array: originalReport.missingSectionTitles + originalReport.missingAnalysisSubsectionTitles)
        ) as? [String] ?? (originalReport.missingSectionTitles + originalReport.missingAnalysisSubsectionTitles)

        guard !candidateTitles.isEmpty else { return [] }

        let lines = alignedMarkdown.components(separatedBy: .newlines)
        let sectionTitles = referenceDocument.styleProfile.sectionTitles
        let normalizedSectionTitles = sectionTitles.map(normalizedSectionTitle)

        var titleIndexByNormalized: [String: Int] = [:]
        for (index, title) in normalizedSectionTitles.enumerated() where titleIndexByNormalized[title] == nil {
            titleIndexByNormalized[title] = index
        }

        var boundaries: [(title: String, lineIndex: Int)] = []
        for (lineIndex, rawLine) in lines.enumerated() {
            let normalized = normalizedSectionTitle(canonicalSectionLine(rawLine))
            guard let sectionIndex = titleIndexByNormalized[normalized] else { continue }
            boundaries.append((sectionTitles[sectionIndex], lineIndex))
        }

        let bodyByTitle = Dictionary(uniqueKeysWithValues: boundaries.enumerated().map { offset, boundary in
            let end = offset + 1 < boundaries.count ? boundaries[offset + 1].lineIndex : lines.count
            let bodyLines = lines[(boundary.lineIndex + 1)..<end]
                .map(canonicalSectionLine)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            return (boundary.title, bodyLines)
        })

        return candidateTitles.filter { title in
            (bodyByTitle[title] ?? []).isEmpty
        }
    }

    private nonisolated static func canonicalSectionLine(_ rawLine: String) -> String {
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

    private nonisolated static func normalizedSectionTitle(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
            .replacingOccurrences(of: "：", with: ":")
            .replacingOccurrences(of: "[\\p{P}\\p{S}\\s]+", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
