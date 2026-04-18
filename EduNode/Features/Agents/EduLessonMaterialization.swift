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

    enum CodingKeys: String, CodingKey {
        case planningSummary = "planning_summary"
        case groundedEvidence = "grounded_evidence"
        case cautionPoints = "caution_points"
    }
}

struct EduLessonFollowUpSuggestionResponse: Decodable {
    let suggestedAnswer: String

    enum CodingKeys: String, CodingKey {
        case suggestedAnswer = "suggested_answer"
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
        referenceDocument: EduLessonReferenceDocument? = nil
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

        let rawTemplateText = template.rawText.count > 9000
            ? String(template.rawText.prefix(9000)) + "\n..."
            : template.rawText
        let directive = userDirective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? defaultDirective
            : userDirective.trimmingCharacters(in: .whitespacesAndNewlines)
        let referenceExcerpt = referenceDocument?.markdownExcerptForPrompt ?? "(none)"
        let referenceStyleProfile = referenceDocument.map {
            EduAgentContextBuilder.encodedJSONString($0.styleProfile)
        } ?? "(none)"
        let referenceSchema = referenceDocument.map {
            EduAgentContextBuilder.encodedJSONString($0.templateDocument.schema)
        } ?? "(none)"
        let referenceSectionOrder = referenceDocument?.templateDocument.schema.outlineText ?? "(none)"
        let referenceFrontMatter = referenceDocument.map {
            EduAgentContextBuilder.encodedJSONString($0.templateDocument.schema.frontMatterFieldLabels)
        } ?? "(none)"
        let referenceProcessColumns = referenceDocument.map {
            EduAgentContextBuilder.encodedJSONString($0.templateDocument.schema.teachingProcessColumnTitles)
        } ?? "(none)"
        let referenceSectionExemplars = referenceDocument.map {
            EduAgentContextBuilder.encodedJSONString($0.styleProfile.sectionExemplars)
        } ?? "(none)"
        let referenceChecklist = referenceDocument?.complianceChecklistText ?? "(none)"
        let referenceSource = referenceDocument?.sourceName ?? "(none)"

        return [
            .init(
                role: "system",
                content: mergedSystemPrompt(
                    base: """
                    You materialize a teacher-facing lesson plan from a pedagogical graph and a teacher-provided template.
                    Treat the template as a genre and section-structure constraint with high priority.
                    Stay grounded in the graph, the course metadata, and the teacher's follow-up answers.
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
                    Before finalizing, silently verify that every template section title appears once and in the correct order.
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
                Workspace snapshot JSON:
                \(EduAgentContextBuilder.encodedJSONString(snapshot))

                Additional course metadata JSON:
                \(EduAgentContextBuilder.encodedJSONString(metadata))

                Template schema JSON:
                \(EduAgentContextBuilder.encodedJSONString(template.schema))

                Template outline text:
                \(template.schema.outlineText)

                Teacher follow-up answers JSON:
                \(EduAgentContextBuilder.encodedJSONString(teacherResponses))

                Auto-generated baseline markdown:
                \(baselineMarkdown)

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
                \(normalizedSupplementaryMaterial(supplementaryMaterial))
                """
            ),
            .init(role: "user", content: directive)
        ]
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
                    Use a silent plan-and-solve workflow internally: diagnose the compliance gaps, map them onto the exact reference schema, repair the affected slots, and then re-check the repaired draft before returning it.
                    Do not add new top-level sections beyond the reference list.
                    Do not paraphrase template titles.
                    If the reference includes a structured-knowledge-map section, keep it even if you can only render it textually.
                    Use the matching section exemplars to restore the reference register and opening style without copying institution-specific details.
                    If the reference includes supplementary sections after the teaching process, keep those trailing sections in the repaired result.
                    For administrative values not provided by the teacher, keep the field blank instead of inventing facts.
                    Fix only what is necessary to satisfy the compliance issues and preserve quality.
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
        let targetExemplar = referenceDocument.styleProfile.sectionExemplars.first {
            $0.title == targetItem.sectionTitle
        }?.opening ?? "(none)"
        let targetTemplateExcerpt = referenceDocument.templateDocument.schema.sections.first {
            $0.title == targetItem.sectionTitle
        }?.excerpt ?? "(none)"

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
                Workspace snapshot JSON:
                \(EduAgentContextBuilder.encodedJSONString(snapshot))

                Additional course metadata JSON:
                \(EduAgentContextBuilder.encodedJSONString(metadata))

                Current baseline lesson-plan markdown:
                \(baselineMarkdown)

                Reference lesson-plan source:
                \(referenceDocument.sourceName)

                Reference lesson-plan schema JSON:
                \(EduAgentContextBuilder.encodedJSONString(referenceDocument.templateDocument.schema))

                Reference compliance checklist:
                \(referenceDocument.complianceChecklistText)

                Target missing item JSON:
                \(EduAgentContextBuilder.encodedJSONString(targetItem))

                Target template excerpt:
                \(targetTemplateExcerpt)

                Matching section exemplar opening:
                \(targetExemplar)

                Teacher follow-up answers JSON:
                \(EduAgentContextBuilder.encodedJSONString(teacherResponses))
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

        return [
            .init(
                role: "system",
                content: mergedSystemPrompt(
                    base: """
                    You draft one teacher-editable answer for a missing lesson-plan item.
                    Use the provided planning summary as an internal scaffold, but do not restate hidden reasoning.
                    Keep the answer grounded, concise, and immediately editable by the teacher.
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
                \(EduAgentContextBuilder.encodedJSONString(snapshot))

                Target missing item JSON:
                \(EduAgentContextBuilder.encodedJSONString(targetItem))

                Target template excerpt:
                \(targetTemplateExcerpt)

                Matching section exemplar opening:
                \(targetExemplar)

                Planning summary:
                \(planning.planningSummary)

                Grounded evidence:
                \(planning.groundedEvidence.joined(separator: "\n- "))

                Caution points:
                \(planning.cautionPoints.joined(separator: "\n- "))
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
