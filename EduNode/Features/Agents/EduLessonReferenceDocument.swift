import Foundation

struct EduLessonReferenceSectionExemplar: Codable, Hashable {
    let title: String
    let opening: String
}

struct EduLessonReferenceStyleProfile: Codable, Hashable {
    let sectionCount: Int
    let sectionTitles: [String]
    let frontMatterFieldLabels: [String]
    let teachingProcessColumnTitles: [String]
    let analysisSubsectionTitles: [String]
    let learnerAnalysisFieldLabels: [String]
    let keyPointDifficultyLabels: [String]
    let sectionExemplars: [EduLessonReferenceSectionExemplar]
    let styleNotes: [String]
    let featureHints: [String]
    let prefersTableStructure: Bool
    let prefersBulletLists: Bool
    let usesExplicitReflection: Bool
    let prefersFormalParagraphs: Bool
}

struct EduLessonReferenceDocument: Identifiable, Hashable {
    let id: UUID
    let sourceName: String
    let sourceKind: String
    let extractedMarkdown: String
    let templateDocument: EduLessonTemplateDocument
    let styleProfile: EduLessonReferenceStyleProfile

    init(
        id: UUID = UUID(),
        sourceName: String,
        sourceKind: String = "mineru_v4",
        extractedMarkdown: String,
        templateDocument: EduLessonTemplateDocument,
        styleProfile: EduLessonReferenceStyleProfile
    ) {
        self.id = id
        self.sourceName = sourceName
        self.sourceKind = sourceKind
        self.extractedMarkdown = extractedMarkdown
        self.templateDocument = templateDocument
        self.styleProfile = styleProfile
    }

    var markdownExcerptForPrompt: String {
        let trimmed = templateDocument.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 12_000 else { return trimmed }
        return String(trimmed.prefix(12_000)) + "\n..."
    }

    var complianceChecklistText: String {
        var lines: [String] = []

        if !styleProfile.frontMatterFieldLabels.isEmpty {
            lines.append("Front matter field order: \(styleProfile.frontMatterFieldLabels.joined(separator: " | "))")
        }

        if !styleProfile.sectionTitles.isEmpty {
            lines.append("Top-level section titles must appear in this order:")
            for (index, title) in styleProfile.sectionTitles.enumerated() {
                lines.append("\(index + 1). \(title)")
            }
        }

        if !styleProfile.analysisSubsectionTitles.isEmpty {
            lines.append("Text-analysis subsection titles to preserve: \(styleProfile.analysisSubsectionTitles.joined(separator: " | "))")
        }

        if !styleProfile.learnerAnalysisFieldLabels.isEmpty {
            lines.append("Learner-analysis internal labels to preserve: \(styleProfile.learnerAnalysisFieldLabels.joined(separator: " | "))")
        }

        if !styleProfile.keyPointDifficultyLabels.isEmpty {
            lines.append("Key-point / difficulty labels to preserve: \(styleProfile.keyPointDifficultyLabels.joined(separator: " | "))")
        }

        if !styleProfile.teachingProcessColumnTitles.isEmpty {
            lines.append("Teaching-process column titles to preserve exactly: \(styleProfile.teachingProcessColumnTitles.joined(separator: " | "))")
        }

        if styleProfile.featureHints.contains(where: { $0.localizedCaseInsensitiveContains("prior knowledge") || $0.localizedCaseInsensitiveContains("已有知识") }) {
            lines.append("Inside learner analysis, keep labeled subfields such as prior knowledge and missing knowledge.")
        }

        if styleProfile.prefersFormalParagraphs {
            lines.append("Prefer formal expository paragraphs over short note fragments in core narrative sections.")
        }

        if styleProfile.prefersTableStructure {
            lines.append("When markdown allows, preserve table-like organization rather than flattening everything into bullet lists.")
        }

        if templateDocument.schema.sections.contains(where: { $0.kind == .knowledgeStructure }) {
            lines.append("Keep the structured knowledge-map section even if the diagram must be described textually.")
        }

        return lines.joined(separator: "\n")
    }

    static func build(
        sourceName: String,
        extractedMarkdown: String
    ) throws -> EduLessonReferenceDocument {
        let normalized = extractedMarkdown
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let templateDocument = try EduLessonTemplateParser.parse(
            text: normalized,
            sourceName: sourceName
        )
        let styleProfile = makeStyleProfile(
            markdown: normalized,
            templateDocument: templateDocument
        )
        return EduLessonReferenceDocument(
            sourceName: sourceName,
            extractedMarkdown: normalized,
            templateDocument: templateDocument,
            styleProfile: styleProfile
        )
    }

    private static func makeStyleProfile(
        markdown: String,
        templateDocument: EduLessonTemplateDocument
    ) -> EduLessonReferenceStyleProfile {
        let focusedText = templateDocument.rawText
        let lines = focusedText.components(separatedBy: .newlines)
        let trimmedLines = lines.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let nonEmptyLines = trimmedLines.filter { !$0.isEmpty }

        let tableLineCount = nonEmptyLines.filter { $0.contains("|") }.count
        let bulletLineCount = nonEmptyLines.filter {
            $0.hasPrefix("- ") || $0.hasPrefix("* ") || Self.isOrderedListLine($0)
        }.count
        let reflectionAliases = [
            "reflection", "教学反思", "课后反思", "反思"
        ]
        let usesExplicitReflection = reflectionAliases.contains { alias in
            markdown.localizedCaseInsensitiveContains(alias)
        }

        var featureHints: [String] = []
        if tableLineCount >= 4 {
            featureHints.append(Self.localizedFeature(
                zh: "模板包含较明显的表格式结构，生成时宜保持栏目化表达。",
                en: "The reference uses visible table-like structures; preserve column-oriented organization."
            ))
        }
        if bulletLineCount >= 6 {
            featureHints.append(Self.localizedFeature(
                zh: "模板倾向以项目符号或分点条目组织教学信息。",
                en: "The reference tends to organize teaching information as bullet-style items."
            ))
        }
        if usesExplicitReflection {
            featureHints.append(Self.localizedFeature(
                zh: "模板显式包含 reflection / 教学反思部分，生成稿中不应省略。",
                en: "The reference explicitly includes a reflection section and it should be preserved."
            ))
        }
        if templateDocument.schema.sections.contains(where: { $0.kind == .courseInfo }) {
            featureHints.append(Self.localizedFeature(
                zh: "模板开头包含课程基本信息区块，应以前置字段表或等价结构完整保留。",
                en: "The reference opens with lesson metadata and should preserve that front matter as an explicit field block."
            ))
        }
        if !templateDocument.schema.analysisSubsectionTitles.isEmpty {
            featureHints.append(Self.localizedFeature(
                zh: "文本分析部分采用固定子标题推进，生成稿应保留这些子标题而不是改写成普通段落标题。",
                en: "The text-analysis section uses fixed subsection titles and they should be preserved rather than paraphrased."
            ))
        }
        if !templateDocument.schema.teachingProcessColumnTitles.isEmpty {
            featureHints.append(Self.localizedFeature(
                zh: "教学过程采用固定列表头组织，生成稿应以同名栏目展开而不是改写成普通叙述。",
                en: "The teaching process is organized by fixed table columns, which should be preserved instead of being flattened into free prose."
            ))
        }
        if templateDocument.schema.styleNotes.contains(where: {
            $0.localizedCaseInsensitiveContains("formal expository paragraphs")
        }) {
            featureHints.append(Self.localizedFeature(
                zh: "模板偏好正式说明型段落写法，关键章节不宜压缩成过短的碎片句。",
                en: "The template favors formal expository paragraphs, so key sections should not collapse into overly short fragments."
            ))
        }
        if templateDocument.schema.sections.contains(where: { $0.kind == .priorKnowledge || $0.kind == .missingKnowledge }) {
            featureHints.append(Self.localizedFeature(
                zh: "学情分析内部包含“已有知识/未有知识”之类的标签化子项，生成稿应保留这种分项表达。",
                en: "Learner analysis contains labeled subfields such as prior knowledge and missing knowledge, and the generated draft should preserve that internal labeling."
            ))
        }
        if templateDocument.schema.sections.contains(where: { $0.kind == .knowledgeStructure }) {
            featureHints.append(Self.localizedFeature(
                zh: "模板包含结构化知识图表部分，即便无法绘制图，也应保留该章节并提供文本化替代。",
                en: "The template includes a structured knowledge-map section; keep the section even if the diagram must be rendered textually."
            ))
        }
        if !templateDocument.schema.keyPointDifficultyLabels.isEmpty {
            featureHints.append(Self.localizedFeature(
                zh: "“教学重点和难点”内部还细分了编号小标题，生成稿应保留这一层级。",
                en: "The key-points-and-difficulties section contains numbered internal labels that should be preserved."
            ))
        }
        if templateDocument.schema.sections.contains(where: { $0.kind == .homework || $0.kind == .handout || $0.kind == .sourceText }) {
            featureHints.append(Self.localizedFeature(
                zh: "模板在教学过程后还保留了作业、Handout 或教学原文等补充章节，生成稿不应在教学过程处提前结束。",
                en: "The template continues with supplementary sections such as homework, handout, or source text after the teaching process, so the generated draft should not stop at the process table."
            ))
        }
        if featureHints.isEmpty {
            featureHints.append(Self.localizedFeature(
                zh: "模板整体偏向规范化教师教案文体，应保持章节稳定与字段清晰。",
                en: "The reference follows a conventional teacher-facing lesson-plan genre with stable sections and explicit fields."
            ))
        }

        let hasLearnerAnalysis = templateDocument.schema.sections.contains { $0.kind == .learnerAnalysis }
        let contentSections = templateDocument.schema.sections
            .sorted { $0.order < $1.order }
            .filter {
                if $0.kind == .courseInfo && !templateDocument.schema.frontMatterFieldLabels.isEmpty {
                    return false
                }
                if hasLearnerAnalysis && ($0.kind == .priorKnowledge || $0.kind == .missingKnowledge) {
                    return false
                }
                return true
            }
        let sectionExemplars = contentSections
            .map {
                EduLessonReferenceSectionExemplar(
                    title: $0.title,
                    opening: $0.excerpt
                )
            }

        return EduLessonReferenceStyleProfile(
            sectionCount: contentSections.count,
            sectionTitles: contentSections.map(\.title),
            frontMatterFieldLabels: templateDocument.schema.frontMatterFieldLabels,
            teachingProcessColumnTitles: templateDocument.schema.teachingProcessColumnTitles,
            analysisSubsectionTitles: templateDocument.schema.analysisSubsectionTitles,
            learnerAnalysisFieldLabels: templateDocument.schema.learnerAnalysisFieldLabels,
            keyPointDifficultyLabels: templateDocument.schema.keyPointDifficultyLabels,
            sectionExemplars: sectionExemplars,
            styleNotes: templateDocument.schema.styleNotes,
            featureHints: featureHints,
            prefersTableStructure: tableLineCount >= 4,
            prefersBulletLists: bulletLineCount >= 6,
            usesExplicitReflection: usesExplicitReflection,
            prefersFormalParagraphs: templateDocument.schema.styleNotes.contains {
                $0.localizedCaseInsensitiveContains("formal expository paragraphs")
            }
        )
    }

    private static func localizedFeature(zh: String, en: String) -> String {
        let isChinese = Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
        return isChinese ? zh : en
    }

    private static func isOrderedListLine(_ line: String) -> Bool {
        var digits = ""
        for character in line {
            if character.isNumber {
                digits.append(character)
                continue
            }
            if (character == "." || character == ")") && !digits.isEmpty {
                return true
            }
            return false
        }
        return false
    }
}
