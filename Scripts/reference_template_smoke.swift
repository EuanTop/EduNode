import Foundation
import Darwin

@main
struct ReferenceTemplateSmoke {
    static func main() throws {
        var arguments = CommandLine.arguments.dropFirst()
        if let first = arguments.first, first == "--" {
            arguments = arguments.dropFirst()
        }

        guard let path = arguments.first else {
            fputs("usage: reference_template_smoke.swift <template.pdf>\n", stderr)
            exit(2)
        }

        let url = URL(fileURLWithPath: path)
        let rawText = try EduLessonTemplateDocumentLoader.extractText(from: url)
        let reference = try EduLessonReferenceDocument.build(
            sourceName: url.lastPathComponent,
            extractedMarkdown: rawText
        )

        print("SOURCE:", reference.sourceName)
        print("SOURCE_KIND:", reference.sourceKind)
        print("SECTION_TITLES:")
        for title in reference.styleProfile.sectionTitles {
            print("-", title)
        }
        print("FRONT_MATTER_FIELDS:", reference.styleProfile.frontMatterFieldLabels.joined(separator: " | "))
        print("PROCESS_COLUMNS:", reference.styleProfile.teachingProcessColumnTitles.joined(separator: " | "))
        print("ANALYSIS_SUBSECTIONS:", reference.styleProfile.analysisSubsectionTitles.joined(separator: " | "))
        print("STYLE_NOTES:")
        for note in reference.styleProfile.styleNotes {
            print("-", note)
        }
        print("FEATURE_HINTS:")
        for hint in reference.styleProfile.featureHints {
            print("-", hint)
        }
        print("SECTION_EXEMPLARS:")
        for exemplar in reference.styleProfile.sectionExemplars.prefix(8) {
            print("- [\(exemplar.title)] \(exemplar.opening)")
        }
        print("PROMPT_EXCERPT_HEAD:")
        print(String(reference.markdownExcerptForPrompt.prefix(1500)))
    }
}
