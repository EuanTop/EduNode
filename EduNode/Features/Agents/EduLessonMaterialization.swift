import Foundation

struct EduLessonMaterializationResponse: Decodable {
    let assistantReply: String
    let generatedMarkdown: String

    enum CodingKeys: String, CodingKey {
        case assistantReply = "assistant_reply"
        case generatedMarkdown = "generated_markdown"
    }
}

struct EduLessonFollowUpPlanningResponse: Decodable {
    let planningSummary: String
    let groundedEvidence: [String]
    let cautionPoints: [String]

    init(
        planningSummary: String,
        groundedEvidence: [String],
        cautionPoints: [String]
    ) {
        self.planningSummary = planningSummary
        self.groundedEvidence = groundedEvidence
        self.cautionPoints = cautionPoints
    }

    enum CodingKeys: String, CodingKey {
        case planningSummary = "planning_summary"
        case groundedEvidence = "grounded_evidence"
        case cautionPoints = "caution_points"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        planningSummary = ((try? container.decode(String.self, forKey: .planningSummary))?
            .trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
        groundedEvidence = Self.decodeStringArray(container: container, key: .groundedEvidence)
        cautionPoints = Self.decodeStringArray(container: container, key: .cautionPoints)
    }

    private static func decodeStringArray(
        container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> [String] {
        if let value = try? container.decode([String].self, forKey: key) {
            return value.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        if let single = try? container.decode(String.self, forKey: key) {
            let trimmed = single.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? [] : [trimmed]
        }
        return []
    }
}

struct EduLessonFollowUpSuggestionResponse: Decodable {
    let suggestedAnswer: String

    init(suggestedAnswer: String) {
        self.suggestedAnswer = suggestedAnswer
    }

    private enum CodingKeys: String, CodingKey {
        case suggestedAnswer = "suggested_answer"
        case answer
        case draft
        case text
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let candidates: [CodingKeys] = [.suggestedAnswer, .answer, .draft, .text]
        for key in candidates {
            if let value = try? container.decode(String.self, forKey: key) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    suggestedAnswer = trimmed
                    return
                }
            }
        }
        suggestedAnswer = ""
    }
}

private struct EduLessonMaterializationMetadataSnapshot: Encodable {
    let lessonType: String
    let totalSessions: Int
    let teachingStyle: String
    let formativeCheckIntensity: String
    let emphasizeInquiryExperiment: Bool
    let emphasizeExperienceReflection: Bool
    let requireStructuredFlow: Bool
    let studentProfile: String
    let teacherRolePlan: String
    let learningScenario: String
    let curriculumStandard: String
}

private struct EduLessonMaterializationTeacherResponse: Encodable {
    let itemID: String
    let title: String
    let question: String
    let answer: String
    let status: String
}

enum EduLessonMaterializationAnalyzer {
    static func missingInfoItems(
        template: EduLessonTemplateDocument,
        file: GNodeWorkspaceFile,
        baselineMarkdown: String
    ) -> [EduLessonMissingInfoItem] {
        let modelRules = EduPlanning.loadModelRules()
        let modelFocus = modelRules.first(where: { $0.id == file.modelID })?.templateFocus(
            isChinese: isChineseUI
        ) ?? ""
        let snapshot = EduAgentContextBuilder.workspaceSnapshot(
            file: file,
            lessonPlanMarkdown: baselineMarkdown
        )
        let course = EduAgentLogicAdapter.courseContext(file: file, modelFocus: modelFocus)
        let graph = EduAgentLogicAdapter.graphContext(snapshot: snapshot)
        return EduLessonMaterializationCoreAnalyzer.missingInfoItems(
            template: template,
            course: course,
            graph: graph,
            baselineMarkdown: baselineMarkdown,
            isChinese: isChineseUI
        )
    }

    static func readiness(
        items: [EduLessonMissingInfoItem],
        answersByID: [String: String],
        skippedItemIDs: Set<String>
    ) -> EduLessonGenerationReadiness {
        EduLessonMaterializationCoreAnalyzer.readiness(
            items: items,
            answersByID: answersByID,
            skippedItemIDs: skippedItemIDs
        )
    }

    private static var isChineseUI: Bool {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
    }
}

enum EduLessonPlanMaterializationPromptBuilder {
    static func materializationMessages(
        settings: EduAgentProviderSettings,
        file: GNodeWorkspaceFile,
        baselineMarkdown: String,
        template: EduLessonTemplateDocument,
        missingItems: [EduLessonMissingInfoItem],
        answersByID: [String: String],
        skippedItemIDs: Set<String>,
        supplementaryMaterial: String,
        userDirective: String,
        referenceDocument: EduLessonReferenceDocument? = nil,
        compactContext: Bool = false
    ) -> [EduLLMMessage] {
        let snapshot = EduAgentContextBuilder.workspaceSnapshot(
            file: file,
            lessonPlanMarkdown: baselineMarkdown
        )
        let metadata = metadataSnapshot(for: file)
        let teacherResponses = teacherResponsesPayload(
            missingItems: missingItems,
            answersByID: answersByID,
            skippedItemIDs: skippedItemIDs
        )
        let highPriorityDigestText = highPriorityContextDigest(
            file: file,
            template: template,
            teacherResponses: teacherResponses
        )

        let rawTemplateMax = compactContext ? 2600 : 5200
        let rawTemplateText = template.rawText.count > rawTemplateMax
            ? String(template.rawText.prefix(rawTemplateMax)) + "\n..."
            : template.rawText
        let directive = userDirective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? defaultDirective
            : userDirective.trimmingCharacters(in: .whitespacesAndNewlines)
        let referenceExcerpt = compactContext
            ? boundedPromptText(referenceDocument?.markdownExcerptForPrompt ?? "(none)", maxChars: 2200)
            : boundedPromptText(referenceDocument?.markdownExcerptForPrompt ?? "(none)", maxChars: 9000)
        let referenceStyleProfile = referenceDocument.map {
            boundedPromptText(
                EduAgentContextBuilder.encodedJSONString($0.styleProfile),
                maxChars: compactContext ? 2000 : 8000
            )
        } ?? "(none)"
        let referenceSchema = referenceDocument.map {
            boundedPromptText(
                EduAgentContextBuilder.encodedJSONString($0.templateDocument.schema),
                maxChars: compactContext ? 2400 : 7600
            )
        } ?? "(none)"
        let referenceSectionOrder = referenceDocument?.templateDocument.schema.outlineText ?? "(none)"
        let referenceFrontMatter = referenceDocument.map {
            boundedPromptText(
                EduAgentContextBuilder.encodedJSONString($0.templateDocument.schema.frontMatterFieldLabels),
                maxChars: compactContext ? 1200 : 10000
            )
        } ?? "(none)"
        let referenceProcessColumns = referenceDocument.map {
            boundedPromptText(
                EduAgentContextBuilder.encodedJSONString($0.templateDocument.schema.teachingProcessColumnTitles),
                maxChars: compactContext ? 1200 : 10000
            )
        } ?? "(none)"
        let referenceSectionExemplars = referenceDocument.map {
            boundedPromptText(
                EduAgentContextBuilder.encodedJSONString($0.styleProfile.sectionExemplars),
                maxChars: compactContext ? 2000 : 6200
            )
        } ?? "(none)"
        let referenceChecklist = referenceDocument?.complianceChecklistText ?? "(none)"
        let referenceSource = referenceDocument?.sourceName ?? "(none)"
        let workspaceSnapshotText = boundedPromptText(
            EduAgentContextBuilder.encodedJSONString(snapshot),
            maxChars: compactContext ? 2600 : 14000
        )
        let metadataText = boundedPromptText(
            EduAgentContextBuilder.encodedJSONString(metadata),
            maxChars: compactContext ? 1400 : 10000
        )
        let templateSchemaText = boundedPromptText(
            EduAgentContextBuilder.encodedJSONString(template.schema),
            maxChars: compactContext ? 2200 : 9000
        )
        let teacherResponsesText = boundedPromptText(
            EduAgentContextBuilder.encodedJSONString(teacherResponses),
            maxChars: compactContext ? 2000 : 9000
        )
        let baselineMarkdownText = boundedPromptText(
            baselineMarkdown,
            maxChars: compactContext ? 2600 : 12000
        )
        let supplementaryText = boundedPromptText(
            normalizedSupplementaryMaterial(supplementaryMaterial),
            maxChars: compactContext ? 1800 : 12000
        )

        return [
            .init(
                role: "system",
                content: mergedSystemPrompt(
                    base: """
                    You materialize a teacher-facing lesson plan from a pedagogical graph and a teacher-provided template.
                    Treat the template as a genre and section-structure constraint with high priority.
                    Stay grounded in the graph, the course metadata, and the teacher's follow-up answers.
                    Treat the reference/template text as structural and stylistic guidance only, not as ground-truth topic facts.
                    If the reference/template topic conflicts with the live graph topic, always follow the live graph topic and keep only the reference structure/style.
                    Use a silent plan-and-solve workflow internally: first map every required template slot, then ground each slot in graph/metadata/teacher evidence, then draft, and finally run a structural compliance check.
                    If a reference lesson-plan document is provided, align your section logic, wording register, field expectations, and section openings with it without copying institution-specific identifiers.
                    Use the section exemplar with the same title to imitate rhetorical opening, paragraph density, and wording register without copying its concrete facts.
                    Use the exact section titles from the template when provided. Do not paraphrase those titles.
                    Preserve the template section order exactly and do not insert extra top-level sections unless the user explicitly asks.
                    When the template provides an explicit top-level section list, the final markdown must contain that same list and no substitute top-level headings.
                    If front-matter field labels are provided, open with an explicit metadata block that preserves those labels in order; for administrative values not provided by the teacher, keep them blank instead of inventing facts.
                    If teaching-process column titles are provided, render the teaching process as a markdown table or table-like structure using those exact column titles.
                    If the template contains internal labeled subfields such as 已有知识 / 未有知识 or numbered key-point subparts, preserve those labels explicitly instead of flattening them into prose.
                    If the template continues with supplementary sections such as 作业, Handout, or 教学原文 after the teaching-process table, preserve those sections instead of stopping early.
                    If the template contains diagram-oriented sections that cannot be rendered visually in markdown, keep the exact section title and provide a compact text-based substitute instead of dropping the section.
                    If a teacher skipped an item, do not invent detailed facts. Use a concise neutral placeholder only when the section would otherwise collapse.
                    Preserve explicit alignment among goals, activity flow, and evaluation evidence.
                    Prioritize the "High-priority context digest JSON" block first when context is long, then use larger JSON blocks as supporting evidence.
                    Before finalizing, silently verify that every template section title appears once and in the correct order.
                    Never ask the user to choose between multiple topics or provide additional context; resolve conflicts internally and generate directly.
                    Do not wrap JSON in markdown fences.
                    Output strict JSON only:
                    {
                      "assistant_reply": "brief summary",
                      "generated_markdown": "full markdown lesson plan"
                    }
                    """,
                    settings: settings
                )
            ),
            .init(
                role: "user",
                content: """
                High-priority context digest JSON:
                \(highPriorityDigestText)

                Workspace snapshot JSON:
                \(workspaceSnapshotText)

                Additional course metadata JSON:
                \(metadataText)

                Template schema JSON:
                \(templateSchemaText)

                Template outline text:
                \(template.schema.outlineText)

                Teacher follow-up answers JSON:
                \(teacherResponsesText)

                Auto-generated baseline markdown:
                \(baselineMarkdownText)

                Template raw text excerpt:
                \(rawTemplateText)

                Reference lesson-plan source:
                \(referenceSource)

                Reference lesson-plan schema JSON:
                \(referenceSchema)

                Reference exact section order:
                \(referenceSectionOrder)

                Reference front-matter field labels JSON:
                \(referenceFrontMatter)

                Reference teaching-process column titles JSON:
                \(referenceProcessColumns)

                Reference lesson-plan style profile JSON:
                \(referenceStyleProfile)

                Reference section exemplars JSON:
                \(referenceSectionExemplars)

                Reference compliance checklist:
                \(referenceChecklist)

                Reference lesson-plan markdown excerpt:
                \(referenceExcerpt)

                Supplementary material:
                \(supplementaryText)

                User directive:
                \(directive)
                """
            )
        ]
    }

    private static func highPriorityContextDigest(
        file: GNodeWorkspaceFile,
        template: EduLessonTemplateDocument,
        teacherResponses: [EduLessonMaterializationTeacherResponse]
    ) -> String {
        let goals = file.goalsText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let answered = teacherResponses
            .filter { $0.status == "answered" }
            .map { item in
                EduLessonPromptTeacherAnswerDigest(
                    itemID: item.itemID,
                    title: item.title,
                    answer: boundedPromptText(item.answer, maxChars: 360)
                )
            }

        let unresolved = teacherResponses
            .filter { $0.status != "answered" }
            .map { item in
                EduLessonPromptUnresolvedDigest(
                    itemID: item.itemID,
                    status: item.status,
                    question: boundedPromptText(item.question, maxChars: 220)
                )
            }

        let digest = EduLessonPromptHighPriorityDigest(
            courseName: file.name,
            subject: file.subject,
            gradeMode: file.gradeMode,
            gradeMin: file.gradeMin,
            gradeMax: file.gradeMax,
            durationMinutes: file.lessonDurationMinutes,
            studentCount: file.studentCount,
            lessonType: file.lessonType,
            teachingStyle: file.teachingStyle,
            requireStructuredFlow: file.requireStructuredFlow,
            goals: goals,
            templateSectionOrder: template.schema.outlineText,
            templateFrontMatterLabels: template.schema.frontMatterFieldLabels,
            templateTeachingProcessColumns: template.schema.teachingProcessColumnTitles,
            answeredTeacherItems: answered,
            unresolvedTeacherItems: unresolved
        )

        return boundedPromptText(
            EduAgentContextBuilder.encodedJSONString(digest),
            maxChars: 7200
        )
    }

    static func repairMessages(
        settings: EduAgentProviderSettings,
        file: GNodeWorkspaceFile,
        currentMarkdown: String,
        referenceDocument: EduLessonReferenceDocument,
        complianceReport: EduLessonTemplateComplianceReport
    ) -> [EduLLMMessage] {
        let snapshot = EduAgentContextBuilder.workspaceSnapshot(
            file: file,
            lessonPlanMarkdown: currentMarkdown
        )

        return [
            .init(
                role: "system",
                content: mergedSystemPrompt(
                    base: """
                    You repair a teacher-facing lesson plan so it fully complies with a reference lesson-plan template.
                    Keep the pedagogical content grounded in the live graph and keep previously written lesson-specific substance whenever possible.
                    Your main goal is structural fidelity: section titles, section order, front-matter labels, internal subsection labels, and teaching-process columns must match the reference exactly.
                    Keep topic facts anchored to the live graph context; do not import unrelated topic facts from the reference text.
                    Use a silent plan-and-solve workflow internally: diagnose the compliance gaps, map them onto the exact reference schema, repair the affected slots, and then re-check the repaired draft before returning it.
                    Do not add new top-level sections beyond the reference list.
                    Do not paraphrase template titles.
                    If the reference includes a structured-knowledge-map section, keep it even if you can only render it textually.
                    Use the matching section exemplars to restore the reference register and opening style without copying institution-specific details.
                    If the reference includes supplementary sections after the teaching process, keep those trailing sections in the repaired result.
                    For administrative values not provided by the teacher, keep the field blank instead of inventing facts.
                    Fix only what is necessary to satisfy the compliance issues and preserve quality.
                    Do not ask clarification questions.
                    Do not wrap JSON in markdown fences.
                    Output strict JSON only:
                    {
                      "assistant_reply": "brief summary",
                      "generated_markdown": "full repaired markdown lesson plan"
                    }
                    """,
                    settings: settings
                )
            ),
            .init(
                role: "user",
                content: """
                Workspace snapshot JSON:
                \(EduAgentContextBuilder.encodedJSONString(snapshot))

                Current markdown to repair:
                \(currentMarkdown)

                Reference lesson-plan source:
                \(referenceDocument.sourceName)

                Reference schema JSON:
                \(EduAgentContextBuilder.encodedJSONString(referenceDocument.templateDocument.schema))

                Reference exact section order:
                \(referenceDocument.templateDocument.schema.outlineText)

                Reference front-matter field labels JSON:
                \(EduAgentContextBuilder.encodedJSONString(referenceDocument.templateDocument.schema.frontMatterFieldLabels))

                Reference teaching-process column titles JSON:
                \(EduAgentContextBuilder.encodedJSONString(referenceDocument.templateDocument.schema.teachingProcessColumnTitles))

                Reference lesson-plan style profile JSON:
                \(EduAgentContextBuilder.encodedJSONString(referenceDocument.styleProfile))

                Reference section exemplars JSON:
                \(EduAgentContextBuilder.encodedJSONString(referenceDocument.styleProfile.sectionExemplars))

                Compliance issues to fix:
                \(complianceReport.repairGuidanceText)
                """
            )
        ]
    }

    static func followUpPlanningMessages(
        settings: EduAgentProviderSettings,
        file: GNodeWorkspaceFile,
        baselineMarkdown: String,
        referenceDocument: EduLessonReferenceDocument,
        missingItems: [EduLessonMissingInfoItem],
        answersByID: [String: String],
        skippedItemIDs: Set<String>,
        targetItem: EduLessonMissingInfoItem
    ) -> [EduLLMMessage] {
        let snapshot = EduAgentContextBuilder.workspaceSnapshot(
            file: file,
            lessonPlanMarkdown: baselineMarkdown
        )
        let metadata = metadataSnapshot(for: file)
        let teacherResponses = teacherResponsesPayload(
            missingItems: missingItems,
            answersByID: answersByID,
            skippedItemIDs: skippedItemIDs
        )
        let highPriorityDigestText = highPriorityContextDigest(
            file: file,
            template: referenceDocument.templateDocument,
            teacherResponses: teacherResponses
        )
        let targetExemplar = referenceDocument.styleProfile.sectionExemplars.first {
            $0.title == targetItem.sectionTitle
        }?.opening ?? "(none)"
        let targetTemplateExcerpt = referenceDocument.templateDocument.schema.sections.first {
            $0.title == targetItem.sectionTitle
        }?.excerpt ?? "(none)"
        let workspaceSnapshotText = boundedPromptText(
            EduAgentContextBuilder.encodedJSONString(snapshot),
            maxChars: 2800
        )
        let metadataText = boundedPromptText(
            EduAgentContextBuilder.encodedJSONString(metadata),
            maxChars: 1600
        )
        let baselineMarkdownText = boundedPromptText(
            baselineMarkdown,
            maxChars: 3200
        )
        let referenceSchemaText = boundedPromptText(
            EduAgentContextBuilder.encodedJSONString(referenceDocument.templateDocument.schema),
            maxChars: 2600
        )
        let referenceChecklistText = boundedPromptText(
            referenceDocument.complianceChecklistText,
            maxChars: 1800
        )
        let targetItemText = boundedPromptText(
            EduAgentContextBuilder.encodedJSONString(targetItem),
            maxChars: 1200
        )
        let targetTemplateExcerptText = boundedPromptText(
            targetTemplateExcerpt,
            maxChars: 500
        )
        let targetExemplarText = boundedPromptText(
            targetExemplar,
            maxChars: 500
        )
        let teacherResponsesText = boundedPromptText(
            EduAgentContextBuilder.encodedJSONString(teacherResponses),
            maxChars: 2200
        )

        return [
            .init(
                role: "system",
                content: mergedSystemPrompt(
                    base: """
                    You prepare a model-assisted follow-up plan for one missing lesson-plan item in a teacher workbench.
                    Work in a hidden plan-and-solve manner, but do not expose raw chain-of-thought.
                    Instead, return only a concise planning summary, grounded evidence list, and caution list that can be shown to the teacher.
                    Ground the plan in the live graph, course metadata, the baseline lesson-plan draft, the reference template, and any already answered follow-up items.
                    Do not draft the final teacher answer yet.
                    Use the user's UI language when inferable from the prompt context.
                    Do not wrap JSON in markdown fences.
                    Output strict JSON only:
                    {
                      "planning_summary": "2-4 concise sentences",
                      "grounded_evidence": ["fact 1", "fact 2"],
                      "caution_points": ["uncertainty 1", "uncertainty 2"]
                    }
                    """,
                    settings: settings
                )
            ),
            .init(
                role: "user",
                content: """
                High-priority context digest JSON:
                \(highPriorityDigestText)

                Workspace snapshot JSON:
                \(workspaceSnapshotText)

                Additional course metadata JSON:
                \(metadataText)

                Current baseline lesson-plan markdown:
                \(baselineMarkdownText)

                Reference lesson-plan source:
                \(referenceDocument.sourceName)

                Reference lesson-plan schema JSON:
                \(referenceSchemaText)

                Reference compliance checklist:
                \(referenceChecklistText)

                Target missing item JSON:
                \(targetItemText)

                Target template excerpt:
                \(targetTemplateExcerptText)

                Matching section exemplar opening:
                \(targetExemplarText)

                Teacher follow-up answers JSON:
                \(teacherResponsesText)
                """
            )
        ]
    }

    static func followUpSuggestionMessages(
        settings: EduAgentProviderSettings,
        file: GNodeWorkspaceFile,
        baselineMarkdown: String,
        referenceDocument: EduLessonReferenceDocument,
        targetItem: EduLessonMissingInfoItem,
        planning: EduLessonFollowUpPlanningResponse
    ) -> [EduLLMMessage] {
        let snapshot = EduAgentContextBuilder.workspaceSnapshot(
            file: file,
            lessonPlanMarkdown: baselineMarkdown
        )
        let targetExemplar = referenceDocument.styleProfile.sectionExemplars.first {
            $0.title == targetItem.sectionTitle
        }?.opening ?? "(none)"
        let targetTemplateExcerpt = referenceDocument.templateDocument.schema.sections.first {
            $0.title == targetItem.sectionTitle
        }?.excerpt ?? "(none)"
        let workspaceSnapshotText = boundedPromptText(
            EduAgentContextBuilder.encodedJSONString(snapshot),
            maxChars: 2200
        )
        let targetItemText = boundedPromptText(
            EduAgentContextBuilder.encodedJSONString(targetItem),
            maxChars: 1000
        )
        let targetTemplateExcerptText = boundedPromptText(
            targetTemplateExcerpt,
            maxChars: 420
        )
        let targetExemplarText = boundedPromptText(
            targetExemplar,
            maxChars: 420
        )
        let planningSummaryText = boundedPromptText(
            planning.planningSummary,
            maxChars: 800
        )
        let groundedEvidenceText = boundedPromptText(
            planning.groundedEvidence.joined(separator: "\n- "),
            maxChars: 900
        )
        let cautionPointsText = boundedPromptText(
            planning.cautionPoints.joined(separator: "\n- "),
            maxChars: 700
        )

        return [
            .init(
                role: "system",
                content: mergedSystemPrompt(
                    base: """
                    You draft one teacher-editable answer for a missing lesson-plan item.
                    Use the provided planning summary as an internal scaffold, but do not restate hidden reasoning.
                    Keep the answer grounded, concise, and immediately editable by the teacher.
                    Keep the suggested_answer concise: <= 220 Chinese characters (or <= 120 English words).
                    Match the reference section's wording register and genre expectations without copying institution-specific facts.
                    If key specifics are still missing, keep the answer neutrally editable instead of inventing details.
                    Use the user's UI language when inferable from the prompt context.
                    Do not wrap JSON in markdown fences.
                    Output strict JSON only:
                    {
                      "suggested_answer": "teacher-editable answer draft"
                    }
                    """,
                    settings: settings
                )
            ),
            .init(
                role: "user",
                content: """
                Workspace snapshot JSON:
                \(workspaceSnapshotText)

                Target missing item JSON:
                \(targetItemText)

                Target template excerpt:
                \(targetTemplateExcerptText)

                Matching section exemplar opening:
                \(targetExemplarText)

                Planning summary:
                \(planningSummaryText)

                Grounded evidence:
                \(groundedEvidenceText)

                Caution points:
                \(cautionPointsText)
                """
            )
        ]
    }

    private static var defaultDirective: String {
        let isChinese = Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
        if isChinese {
            return "请基于当前图谱、模板结构和教师补充答案，生成一份完整中文教案。章节标题尽量与模板完全一致，章节顺序必须一致；教学过程若模板给出栏目，则按同名栏目组织；整体文风尽量贴近参考教案。"
        }
        return "Generate a complete teacher-facing lesson plan that preserves the exact template section titles and order, uses any provided process-table column titles, stays executable in classroom terms, and keeps goals, activities, and assessment observable and aligned."
    }

    private static func mergedSystemPrompt(
        base: String,
        settings: EduAgentProviderSettings
    ) -> String {
        let extra = settings.additionalSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !extra.isEmpty else { return base }
        return base + "\n\nAdditional provider-specific guidance:\n" + extra
    }

    private static func normalizedSupplementaryMaterial(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "(none)" : trimmed
    }

    private static func boundedPromptText(_ text: String, maxChars: Int) -> String {
        guard maxChars > 0 else { return "" }
        guard text.count > maxChars else { return text }
        return String(text.prefix(maxChars)) + "\n...[truncated]"
    }

    private static func metadataSnapshot(for file: GNodeWorkspaceFile) -> EduLessonMaterializationMetadataSnapshot {
        EduLessonMaterializationMetadataSnapshot(
            lessonType: file.lessonType,
            totalSessions: file.totalSessions,
            teachingStyle: file.teachingStyle,
            formativeCheckIntensity: file.formativeCheckIntensity,
            emphasizeInquiryExperiment: file.emphasizeInquiryExperiment,
            emphasizeExperienceReflection: file.emphasizeExperienceReflection,
            requireStructuredFlow: file.requireStructuredFlow,
            studentProfile: file.studentProfile,
            teacherRolePlan: file.teacherRolePlan,
            learningScenario: file.learningScenario,
            curriculumStandard: file.curriculumStandard
        )
    }

    private static func teacherResponsesPayload(
        missingItems: [EduLessonMissingInfoItem],
        answersByID: [String: String],
        skippedItemIDs: Set<String>
    ) -> [EduLessonMaterializationTeacherResponse] {
        missingItems.map { item in
            let answer = answersByID[item.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let status: String
            if skippedItemIDs.contains(item.id) {
                status = "skipped"
            } else if answer.isEmpty {
                status = "unanswered"
            } else {
                status = "answered"
            }
            return EduLessonMaterializationTeacherResponse(
                itemID: item.id,
                title: item.title,
                question: item.question,
                answer: answer,
                status: status
            )
        }
    }
}

private struct EduLessonPromptTeacherAnswerDigest: Encodable {
    let itemID: String
    let title: String
    let answer: String
}

private struct EduLessonPromptUnresolvedDigest: Encodable {
    let itemID: String
    let status: String
    let question: String
}

private struct EduLessonPromptHighPriorityDigest: Encodable {
    let courseName: String
    let subject: String
    let gradeMode: String
    let gradeMin: Int
    let gradeMax: Int
    let durationMinutes: Int
    let studentCount: Int
    let lessonType: String
    let teachingStyle: String
    let requireStructuredFlow: Bool
    let goals: [String]
    let templateSectionOrder: String
    let templateFrontMatterLabels: [String]
    let templateTeachingProcessColumns: [String]
    let answeredTeacherItems: [EduLessonPromptTeacherAnswerDigest]
    let unresolvedTeacherItems: [EduLessonPromptUnresolvedDigest]
}
