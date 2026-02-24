import Foundation
import CoreGraphics
import GNodeKit
#if canImport(UIKit)
import UIKit
#endif
#if canImport(UIKit) && canImport(WebKit)
import WebKit
#endif

struct EduPresentationDeck {
    let orderedSlides: [EduPresentationBaseSlide]
}

struct EduPresentationBaseSlide: Identifiable {
    enum Kind: String {
        case knowledge
        case toolkit
    }

    let id: UUID
    let position: CGPoint
    let nodeType: String
    let kind: Kind
    let title: String
    let subtitle: String
    let summary: String
    let knowledgeText: String
    let keyPoints: [String]
    let isChinese: Bool

    var kindLabel: String {
        switch kind {
        case .knowledge:
            return isChinese ? "知识讲授" : "Knowledge"
        case .toolkit:
            return isChinese ? "课堂活动" : "Activity"
        }
    }
}

struct EduPresentationSlideGroup: Identifiable {
    let id: UUID
    let sourceSlides: [EduPresentationBaseSlide]
    let startIndex: Int
    let endIndex: Int
    let anchorPosition: CGPoint
    let slideTitle: String
    let subtitle: String
    let keyline: String
}

struct EduPresentationComposedSlide: Identifiable {
    let id: UUID
    let index: Int
    let title: String
    let subtitle: String
    let knowledgeItems: [String]
    let toolkitItems: [String]
    let keyPoints: [String]
    let speakerNotes: [String]
}

enum EduPresentationPlanner {
    private static let columnThreshold: CGFloat = 240

    static func makeDeck(graphData: Data) -> EduPresentationDeck {
        guard let document = try? decodeDocument(from: graphData) else {
            return EduPresentationDeck(orderedSlides: [])
        }

        let isChinese = Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
        let stateByID = Dictionary(uniqueKeysWithValues: document.canvasState.map { ($0.nodeID, $0) })

        let slides = document.nodes.compactMap { serialized -> EduPresentationBaseSlide? in
            guard serialized.nodeType == EduNodeType.knowledge || EduNodeType.allToolkitTypes.contains(serialized.nodeType) else {
                return nil
            }

            let state = stateByID[serialized.id]
            let customName = (state?.customName ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let title = customName.isEmpty ? serialized.attributes.name : customName
            let position = CGPoint(
                x: state?.positionX ?? 0,
                y: state?.positionY ?? 0
            )

            let parsed = parseLiveNode(serialized: serialized)

            if serialized.nodeType == EduNodeType.knowledge {
                let knowledge = normalized(parsed.textValue).isEmpty
                    ? (isChinese ? "（未填写知识点）" : "(Knowledge point not filled)")
                    : normalized(parsed.textValue)
                let level = normalized(parsed.selectedOption)
                let subtitle = level
                return EduPresentationBaseSlide(
                    id: serialized.id,
                    position: position,
                    nodeType: serialized.nodeType,
                    kind: .knowledge,
                    title: title,
                    subtitle: subtitle,
                    summary: knowledge,
                    knowledgeText: knowledge,
                    keyPoints: knowledgeKeyPoints(
                        knowledge: knowledge,
                        level: level,
                        isChinese: isChinese
                    ),
                    isChinese: isChinese
                )
            }

            let summary = toolkitSummary(
                textValue: parsed.textValue,
                textFields: parsed.formTextFields,
                optionFields: parsed.formOptionFields,
                isChinese: isChinese
            )
            let subtitle = toolkitSubtitle(
                selectedOption: parsed.selectedOption,
                nodeType: serialized.nodeType,
                isChinese: isChinese
            )
            let keyPoints = toolkitKeyPoints(
                textFields: parsed.formTextFields,
                optionFields: parsed.formOptionFields,
                summary: summary,
                method: subtitle,
                isChinese: isChinese
            )

            return EduPresentationBaseSlide(
                id: serialized.id,
                position: position,
                nodeType: serialized.nodeType,
                kind: .toolkit,
                title: title,
                subtitle: subtitle,
                summary: summary,
                knowledgeText: "",
                keyPoints: keyPoints,
                isChinese: isChinese
            )
        }

        return EduPresentationDeck(orderedSlides: orderByColumns(slides))
    }

    static func defaultBreaks(count: Int) -> Set<Int> {
        guard count > 1 else { return [] }
        return Set(0..<(count - 1))
    }

    static func groupSlides(_ slides: [EduPresentationBaseSlide], breaks: Set<Int>) -> [EduPresentationSlideGroup] {
        guard !slides.isEmpty else { return [] }

        let validBreaks = Set(breaks.filter { $0 >= 0 && $0 < slides.count - 1 })
        var groups: [EduPresentationSlideGroup] = []
        var start = 0

        for idx in slides.indices {
            let isBoundary = idx == slides.count - 1 || validBreaks.contains(idx)
            guard isBoundary else { continue }

            let source = Array(slides[start...idx])
            let anchor = averagePosition(of: source.map(\.position))
            let firstTitle = source.first?.title ?? "Slide"
            let title = source.count == 1 ? firstTitle : "\(firstTitle) +\(source.count - 1)"
            let subtitle = source
                .map(\.subtitle)
                .map { normalized($0) }
                .first(where: { !$0.isEmpty })
                ?? ""
            let keyline = source
                .map(\.summary)
                .first(where: { !normalized($0).isEmpty })
                ?? ""

            groups.append(
                EduPresentationSlideGroup(
                    id: source.first?.id ?? UUID(),
                    sourceSlides: source,
                    startIndex: start,
                    endIndex: idx,
                    anchorPosition: anchor,
                    slideTitle: title,
                    subtitle: subtitle,
                    keyline: normalized(keyline)
                )
            )

            start = idx + 1
        }

        return groups
    }

    static func composeSlides(from groups: [EduPresentationSlideGroup], isChinese: Bool) -> [EduPresentationComposedSlide] {
            groups.enumerated().map { index, group in
                let resolvedChinese = group.sourceSlides.first?.isChinese ?? isChinese

                let knowledgeItems = deduplicated(
                    group.sourceSlides
                        .filter { $0.kind == .knowledge }
                        .flatMap { splitLines($0.knowledgeText) }
                        .map { normalized($0) }
                        .filter { !normalized($0).isEmpty }
                )

                let toolkitContentItems = deduplicated(
                    group.sourceSlides
                        .filter { $0.kind == .toolkit }
                        .flatMap(\.keyPoints)
                        .flatMap { splitLines($0) }
                        .map { normalized($0) }
                        .filter { !normalized($0).isEmpty }
                )

                let toolkitItems = deduplicated(
                    group.sourceSlides
                        .filter { $0.kind == .toolkit }
                        .flatMap { toolkitPresentationItems(for: $0, isChinese: resolvedChinese) }
                        .map { normalized($0) }
                        .filter { !normalized($0).isEmpty }
                )

                let keyPoints: [String]
                if !knowledgeItems.isEmpty {
                    keyPoints = knowledgeItems
                } else if !toolkitContentItems.isEmpty {
                    keyPoints = toolkitContentItems
                } else {
                    keyPoints = toolkitItems
                }

                let speakerNotes = presentationSpeakerNotes(
                    knowledgeItems: knowledgeItems,
                    toolkitItems: toolkitItems,
                    isChinese: resolvedChinese
                )

                return EduPresentationComposedSlide(
                    id: group.id,
                    index: index + 1,
                    title: group.slideTitle,
                    subtitle: group.subtitle,
                    knowledgeItems: knowledgeItems,
                    toolkitItems: toolkitItems,
                    keyPoints: keyPoints,
                    speakerNotes: Array(speakerNotes.prefix(2))
                )
            }
        }

    private static func parseLiveNode(serialized: SerializableNode) -> ParsedLiveNode {
        var textValue = normalized(serialized.nodeData["content"] ?? serialized.nodeData["value"] ?? "")
        var selectedOption = normalized(serialized.nodeData["level"] ?? serialized.nodeData["toolkitType"] ?? "")
        var formTextFields: [NodeEditorTextFieldSpec] = []
        var formOptionFields: [NodeEditorOptionFieldSpec] = []

        if let liveNode = try? deserializeNode(serialized) {
            if let textEditable = liveNode as? NodeTextEditable {
                textValue = normalized(textEditable.editorTextValue)
            }
            if let optionSelectable = liveNode as? NodeOptionSelectable {
                selectedOption = normalized(optionSelectable.editorSelectedOption)
            }
            if let formEditable = liveNode as? NodeFormEditable {
                formTextFields = formEditable.editorFormTextFields
                formOptionFields = formEditable.editorFormOptionFields
            }
        }

        return ParsedLiveNode(
            textValue: textValue,
            selectedOption: selectedOption,
            formTextFields: formTextFields,
            formOptionFields: formOptionFields
        )
    }

    private static func toolkitSummary(
        textValue: String,
        textFields: [NodeEditorTextFieldSpec],
        optionFields: [NodeEditorOptionFieldSpec],
        isChinese: Bool
    ) -> String {
        if !normalized(textValue).isEmpty {
            return normalized(textValue)
        }
        if let firstField = textFields.first(where: { !normalized($0.value).isEmpty }) {
            return normalized(firstField.value)
        }
        if let firstOption = optionFields.first(where: { !normalized($0.selectedOption).isEmpty }) {
            return normalized(firstOption.selectedOption)
        }
        return isChinese ? "（待补充课堂内容）" : "(Class content pending)"
    }

    private static func toolkitSubtitle(selectedOption: String, nodeType: String, isChinese: Bool) -> String {
        let option = normalized(selectedOption)
        if !option.isEmpty {
            return option
        }
        switch nodeType {
        case EduNodeType.toolkitPerceptionInquiry:
            return isChinese ? "Inquiry" : "Inquiry"
        case EduNodeType.toolkitConstructionPrototype:
            return isChinese ? "Prototype" : "Prototype"
        case EduNodeType.toolkitCommunicationNegotiation:
            return isChinese ? "Negotiation" : "Negotiation"
        case EduNodeType.toolkitRegulationMetacognition:
            return isChinese ? "Metacognition" : "Metacognition"
        default:
            return isChinese ? "Toolkit" : "Toolkit"
        }
    }

    private static func toolkitKeyPoints(
        textFields: [NodeEditorTextFieldSpec],
        optionFields: [NodeEditorOptionFieldSpec],
        summary: String,
        method: String,
        isChinese: Bool
    ) -> [String] {
        var points: [String] = []
        let normalizedMethod = normalized(method)
        let normalizedSummary = normalized(summary)

        if !normalizedMethod.isEmpty {
            points.append(isChinese ? "方法：\(normalizedMethod)" : "Method: \(normalizedMethod)")
        }
        if !normalizedSummary.isEmpty {
            points.append(normalizedSummary)
        }

        for field in optionFields {
            let selected = normalized(field.selectedOption)
            guard !selected.isEmpty else { continue }
            points.append(selected)
        }

        for field in textFields {
            let excerpt = fieldValueExcerpt(field)
            guard !excerpt.isEmpty else { continue }
            points.append(excerpt)
        }

        if points.isEmpty {
            points.append(summary)
        }

        return deduplicated(points)
    }

    private static func knowledgeKeyPoints(knowledge: String, level: String, isChinese: Bool) -> [String] {
        let normalizedKnowledge = normalized(knowledge)
        guard !normalizedKnowledge.isEmpty else {
            return [isChinese ? "先澄清本页核心概念。" : "Clarify the core idea of this slide first."]
        }

        let normalizedLevel = normalized(level)
        if normalizedLevel.isEmpty {
            return splitLines(normalizedKnowledge)
        }

        var lines = splitLines(normalizedKnowledge)
        if lines.isEmpty { lines = [normalizedKnowledge] }
        lines.insert(isChinese ? "知识层级：\(normalizedLevel)" : "Knowledge level: \(normalizedLevel)", at: 0)
        return lines
    }

    private static func groupLeadline(for source: [EduPresentationBaseSlide]) -> String {
        guard !source.isEmpty else { return "" }
        let isChinese = source.first?.isChinese ?? false
        let knowledgeCount = source.filter { $0.kind == .knowledge }.count
        let toolkitCount = source.filter { $0.kind == .toolkit }.count

        if knowledgeCount > 0 && toolkitCount > 0 {
            return isChinese
                ? "先明确本页关键知识，再用课堂活动完成理解、练习与表达。"
                : "Anchor key knowledge first, then use class activity for understanding and expression."
        }
        if knowledgeCount > 0 {
            return isChinese
                ? "聚焦核心知识点，强调概念理解与迁移应用。"
                : "Focus on core knowledge with conceptual understanding and transfer."
        }
        return isChinese
            ? "以活动驱动学习推进，强调协作、表达与反思。"
            : "Drive learning through activity with collaboration, expression, and reflection."
    }

    private static func toolkitPresentationItems(for slide: EduPresentationBaseSlide, isChinese: Bool) -> [String] {
        var lines: [String] = []

        let summaryLines = splitLines(slide.summary)
        if summaryLines.isEmpty {
            if !normalized(slide.summary).isEmpty {
                lines.append(normalized(slide.summary))
            }
        } else {
            lines.append(contentsOf: summaryLines)
        }

        for keyPoint in slide.keyPoints {
            let normalizedPoint = normalized(keyPoint)
            guard !normalizedPoint.isEmpty else { continue }
            if normalizedPoint.hasPrefix("Method:") || normalizedPoint.hasPrefix("方法：") {
                continue
            }
            lines.append(contentsOf: splitLines(normalizedPoint))
        }

        if lines.isEmpty {
            lines.append(isChinese ? "未填写活动内容。" : "Activity content not filled.")
        }
        return deduplicated(lines)
    }

    private static func presentationSpeakerNotes(
        knowledgeItems: [String],
        toolkitItems: [String],
        isChinese: Bool
    ) -> [String] {
        let knowledgeAnchor = normalized(knowledgeItems.first ?? "")
        let toolkitAnchor = normalized(toolkitItems.first ?? "")

        if toolkitItems.isEmpty {
            return [
                isChinese
                ? (knowledgeAnchor.isEmpty ? "先用一个问题激活已有经验，再讲本页核心。" : "先追问“\(knowledgeAnchor)”相关经验，再讲本页核心。")
                : (knowledgeAnchor.isEmpty ? "Activate prior experience with one question, then teach the core idea." : "Open with one question on \(knowledgeAnchor), then teach the core idea."),
                isChinese
                ? "结尾用1个应用问题检查学生是否能迁移。"
                : "Close with one transfer question to check understanding."
            ]
        }

        return [
            isChinese
            ? (knowledgeAnchor.isEmpty ? "先给活动目标和成功标准，再示范第一步。" : "先围绕“\(knowledgeAnchor)”明确目标，再示范第一步。")
            : (knowledgeAnchor.isEmpty ? "State goal and success criteria first, then model step one." : "Frame the goal around \(knowledgeAnchor), then model step one."),
            isChinese
            ? (toolkitAnchor.isEmpty ? "活动后让学生解释依据，并进行同伴互评。" : "活动后围绕“\(toolkitAnchor)”进行依据说明与同伴互评。")
            : (toolkitAnchor.isEmpty ? "After activity, ask students to explain evidence and peer-review." : "After \(toolkitAnchor), ask for evidence-based explanation and peer feedback.")
        ]
    }

    private static func fieldValueExcerpt(_ field: NodeEditorTextFieldSpec) -> String {
        switch field.editorKind {
        case .text:
            return normalized(field.value)
        case .tags:
            let tags = splitLines(field.value)
            return tags.joined(separator: "、")
        case .orderedList:
            let items = splitLines(field.value)
            return items.enumerated()
                .map { "\($0.offset + 1). \($0.element)" }
                .joined(separator: "\n")
        case .keyValueTable:
            let rows = parseTableRows(from: field.value)
            let rendered = rows.map { row in
                let left = normalized(row.0)
                let right = normalized(row.1)
                if left.isEmpty { return right }
                if right.isEmpty { return left }
                return "\(left)：\(right)"
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            return rendered
        }
    }

    private static func splitLines(_ raw: String) -> [String] {
        raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func parseTableRows(from raw: String) -> [(String, String)] {
        splitLines(raw).map { line in
            if line.contains("|") || line.contains("｜") {
                let normalized = line.replacingOccurrences(of: "｜", with: "|")
                let components = normalized
                    .split(separator: "|", omittingEmptySubsequences: false)
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                let left = components.first ?? ""
                let right = components.dropFirst().filter { !$0.isEmpty }.joined(separator: " / ")
                return (left, right)
            }
            if line.contains(":") || line.contains("：") {
                let normalized = line.replacingOccurrences(of: "：", with: ":")
                let components = normalized
                    .split(separator: ":", omittingEmptySubsequences: false)
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                let left = components.first ?? ""
                let right = components.dropFirst().filter { !$0.isEmpty }.joined(separator: " / ")
                return (left, right)
            }
            return (line, "")
        }
    }

    private static func orderByColumns(_ slides: [EduPresentationBaseSlide]) -> [EduPresentationBaseSlide] {
        guard !slides.isEmpty else { return [] }

        struct Column {
            var anchorX: CGFloat
            var members: [EduPresentationBaseSlide]
        }

        var columns: [Column] = []
        let sortedByX = slides.sorted {
            if $0.position.x == $1.position.x {
                return $0.position.y < $1.position.y
            }
            return $0.position.x < $1.position.x
        }

        for slide in sortedByX {
            var candidateIndex: Int?
            var candidateDistance: CGFloat = .greatestFiniteMagnitude

            for idx in columns.indices {
                let distance = abs(slide.position.x - columns[idx].anchorX)
                if distance < candidateDistance {
                    candidateDistance = distance
                    candidateIndex = idx
                }
            }

            if let candidateIndex, candidateDistance <= columnThreshold {
                columns[candidateIndex].members.append(slide)
                let xs = columns[candidateIndex].members.map { $0.position.x }
                columns[candidateIndex].anchorX = xs.reduce(0, +) / CGFloat(xs.count)
            } else {
                columns.append(Column(anchorX: slide.position.x, members: [slide]))
            }
        }

        columns.sort { $0.anchorX < $1.anchorX }

        return columns.flatMap { column in
            column.members.sorted { lhs, rhs in
                if lhs.position.y == rhs.position.y {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                return lhs.position.y < rhs.position.y
            }
        }
    }

    private static func averagePosition(of points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        let sx = points.reduce(CGFloat.zero) { $0 + $1.x }
        let sy = points.reduce(CGFloat.zero) { $0 + $1.y }
        return CGPoint(x: sx / CGFloat(points.count), y: sy / CGFloat(points.count))
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func deduplicated(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            if seen.insert(value).inserted {
                result.append(value)
            }
        }
        return result
    }
}

enum EduPresentationHTMLExporter {
    static func html(courseName: String, slides: [EduPresentationComposedSlide], isChinese: Bool) -> String {
        renderedHTML(
            courseName: courseName,
            slides: slides,
            isChinese: isChinese,
            interactive: true,
            embedded: false,
            overlayHTMLBySlideID: [:]
        )
    }

    static func printHTML(
        courseName: String,
        slides: [EduPresentationComposedSlide],
        isChinese: Bool,
        overlayHTMLBySlideID: [UUID: String] = [:]
    ) -> String {
        renderedHTML(
            courseName: courseName,
            slides: slides,
            isChinese: isChinese,
            interactive: false,
            embedded: false,
            overlayHTMLBySlideID: overlayHTMLBySlideID
        )
    }

    static func singleSlideHTML(courseName: String, slide: EduPresentationComposedSlide, isChinese: Bool) -> String {
        renderedHTML(
            courseName: courseName,
            slides: [slide],
            isChinese: isChinese,
            interactive: false,
            embedded: true,
            overlayHTMLBySlideID: [:]
        )
    }

    static func pdfData(courseName: String, slides: [EduPresentationComposedSlide], isChinese: Bool) -> Data? {
        let rendered = printHTML(courseName: courseName, slides: slides, isChinese: isChinese)
        let title = courseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (isChinese ? "课程演讲" : "Course Presentation")
            : courseName
        return renderPDF(markupHTML: rendered, title: title)
    }

    static func pdfData(markupHTML: String, title: String) -> Data? {
        renderPDF(markupHTML: markupHTML, title: title)
    }

    @MainActor
    static func pdfDataAsync(markupHTML: String, title: String) async -> Data? {
        #if canImport(UIKit) && canImport(WebKit)
        if #available(iOS 14.0, *) {
            if let fastData = await renderPDFWithWebView(markupHTML: markupHTML) {
                return fastData
            }
        }
        #endif
        return renderPDF(markupHTML: markupHTML, title: title)
    }

    private static func renderedHTML(
        courseName: String,
        slides: [EduPresentationComposedSlide],
        isChinese: Bool,
        interactive: Bool,
        embedded: Bool,
        overlayHTMLBySlideID: [UUID: String]
    ) -> String {
        let bodyClass: String = {
            if embedded { return "embedded" }
            if interactive { return "interactive" }
            return "preview"
        }()

        let title = courseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (isChinese ? "课程演讲" : "Course Presentation")
            : courseName

        let toolkitContentTitle = isChinese ? "活动设计" : "Toolkit Content"
        let activityTitle = isChinese ? "课堂活动" : "Class Activity"
        let cuePrefix = isChinese ? "讲述提示：" : "Presenter cue: "
        let emptyMessage = isChinese ? "当前没有可生成的演讲页面。" : "No slide content available."
        let emptyMainFallback = isChinese ? "请先补充节点内容后生成课件页面。" : "Add node content to generate a meaningful slide."
        let emptyActivityFallback = isChinese ? "可在画布中连接对应课堂活动节点。" : "Connect a class activity node in the canvas to populate this panel."
        let prevLabel = isChinese ? "上一页" : "Prev"
        let nextLabel = isChinese ? "下一页" : "Next"

        let renderedSlides: String = {
            guard !slides.isEmpty else {
                return """
                <section class="slide \(interactive ? "active" : "")">
                  <article class="slide-sheet">
                    <header class="hero">
                      <div class="hero-row">
                        <h1>\(escapeHTML(title))</h1>
                      </div>
                      <div class="hero-meta">
                        <p class="lead">\(escapeHTML(emptyMessage))</p>
                      </div>
                    </header>
                    <section class="main-layout solo">
                      <article class="main-card knowledge-card">
                        \(knowledgeBodyHTML(items: [], fallback: emptyMainFallback, centerIfSingleParagraph: false))
                      </article>
                    </section>
                    <footer class="foot">
                      <span class="cue-spacer"></span>
                      <span class="slide-index">01</span>
                    </footer>
                  </article>
                </section>
                """
            }

            return slides.enumerated().map { index, slide in
                let hasKnowledge = !slide.knowledgeItems.isEmpty
                let hasToolkit = !slide.toolkitItems.isEmpty
                let subtitle = slide.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
                let levelChip = hasKnowledge ? levelChipHTML(from: subtitle) : ""
                let leadHTML = (!hasKnowledge && !subtitle.isEmpty)
                    ? "<p class=\"lead\">\(escapeHTML(subtitle))</p>"
                    : ""
                let heroMeta = levelChip + leadHTML
                let heroMetaHTML = heroMeta.isEmpty ? "" : "<div class=\"hero-meta\">\(heroMeta)</div>"
                let toolkitIconBadgeHTML = hasToolkit ? toolkitIconHTML() : ""
                let showActivityAside = hasKnowledge && hasToolkit
                let showToolkitDualPanel = hasToolkit && !hasKnowledge
                let layoutClass = (showActivityAside || showToolkitDualPanel) ? "main-layout" : "main-layout solo"

                let mainCardClass: String
                let mainBodyHTML: String
                let mainHeaderHTML: String
                if hasKnowledge {
                    let centerSingleParagraph = !hasToolkit && slide.knowledgeItems.count == 1
                    mainCardClass = centerSingleParagraph
                        ? "main-card knowledge-card center-brief"
                        : "main-card knowledge-card"
                    mainBodyHTML = knowledgeBodyHTML(
                        items: slide.knowledgeItems,
                        fallback: emptyMainFallback,
                        centerIfSingleParagraph: centerSingleParagraph
                    )
                    mainHeaderHTML = ""
                } else {
                    let densityClass = activityDensityClass(for: slide.keyPoints)
                    mainCardClass = densityClass.isEmpty
                        ? "main-card activity-main"
                        : "main-card activity-main \(densityClass)"
                    mainBodyHTML = activityBodyHTML(
                        items: slide.keyPoints,
                        fallback: emptyMainFallback
                    )
                    mainHeaderHTML = "<h2>\(escapeHTML(toolkitContentTitle))</h2>"
                }

                let activityBlock: String
                if showActivityAside || showToolkitDualPanel {
                    let densityClass = activityDensityClass(for: slide.toolkitItems)
                    let activityCardClass = densityClass.isEmpty
                        ? "activity-card"
                        : "activity-card \(densityClass)"
                    let activityHTML = activityBodyHTML(
                        items: slide.toolkitItems,
                        fallback: emptyActivityFallback
                    )
                    activityBlock = """
                    <aside class="\(activityCardClass)">
                      <h2>\(escapeHTML(activityTitle))</h2>
                      \(activityHTML)
                    </aside>
                    """
                } else {
                    activityBlock = ""
                }
                let cueLine = slide.speakerNotes.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let cueHTML = cueLine.isEmpty
                    ? "<span class=\"cue-spacer\"></span>"
                    : "<p class=\"cue\">\(escapeHTML(cuePrefix + cueLine))</p>"
                let indexLabel = String(format: "%02d", slide.index)
                let overlayHTML = overlayHTMLBySlideID[slide.id]
                    .map { "<div class=\"edunode-overlay-layer\">\($0)</div>" }
                    ?? ""

                return """
                <section class="slide\(interactive && index == 0 ? " active" : "")" data-slide-id="\(slide.id.uuidString)">
                  <article class="slide-sheet">
                    <header class="hero">
                      <div class="hero-row">
                        <h1>\(escapeHTML(slide.title))</h1>
                        \(toolkitIconBadgeHTML)
                      </div>
                      \(heroMetaHTML)
                    </header>

                    <section class="\(layoutClass)">
                      <article class="\(mainCardClass)">
                        \(mainHeaderHTML)
                        \(mainBodyHTML)
                      </article>
                      \(activityBlock)
                    </section>
                    \(overlayHTML)

                    <footer class="foot">
                      \(cueHTML)
                      <span class="slide-index">\(indexLabel)</span>
                    </footer>
                  </article>
                </section>
                """
            }.joined(separator: "\n")
        }()

        let controlsHTML = interactive ? """
        <div class="controls">
          <button id="prevBtn">← \(escapeHTML(prevLabel))</button>
          <span id="counter">1 / \(max(slides.count, 1))</span>
          <button id="nextBtn">\(escapeHTML(nextLabel)) →</button>
        </div>
        """ : ""

        let scriptHTML = interactive ? """
        <script>
          (function () {
            const slides = Array.from(document.querySelectorAll('.slide'));
            const counter = document.getElementById('counter');
            let current = 0;
            function show(index) {
              if (!slides.length) return;
              current = Math.max(0, Math.min(index, slides.length - 1));
              slides.forEach((el, i) => el.classList.toggle('active', i === current));
              if (counter) counter.textContent = (current + 1) + ' / ' + slides.length;
            }
            const prevBtn = document.getElementById('prevBtn');
            const nextBtn = document.getElementById('nextBtn');
            if (prevBtn) prevBtn.addEventListener('click', () => show(current - 1));
            if (nextBtn) nextBtn.addEventListener('click', () => show(current + 1));
            document.addEventListener('keydown', (event) => {
              if (event.key === 'ArrowLeft') show(current - 1);
              if (event.key === 'ArrowRight') show(current + 1);
            });
            show(0);
          })();
        </script>
        """ : ""

        return """
        <!doctype html>
        <html lang="\(isChinese ? "zh-Hans" : "en")">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(escapeHTML(title))</title>
          <style>
            :root { color-scheme: light; }
            * { box-sizing: border-box; }
            html, body {
              width: 100%;
              height: 100%;
            }
            body {
              margin: 0;
              background: #0f1115;
              color: #111111;
              font: 16px/1.35 -apple-system, BlinkMacSystemFont, "SF Pro Text", "PingFang SC", "Helvetica Neue", Arial, sans-serif;
              -webkit-text-size-adjust: 100%;
              text-size-adjust: 100%;
            }
            body.preview {
              overflow: auto;
              scrollbar-gutter: stable both-edges;
              padding: 8px 0 24px;
            }
            body.interactive {
              overflow: hidden;
            }
            body.embedded {
              overflow: hidden;
              background: transparent;
            }
            .deck {
              width: 100%;
              min-height: 100%;
              position: relative;
              display: flex;
              flex-direction: column;
              align-items: center;
              gap: 14px;
              padding: 0 0 20px;
            }
            body.interactive .deck {
              height: 100vh;
              display: block;
              padding: 0;
              gap: 0;
            }
            body.embedded .deck {
              height: 100%;
              display: flex;
              align-items: center;
              justify-content: center;
              padding: 0;
              gap: 0;
            }
            .slide {
              position: relative;
              display: flex;
              width: 100%;
              min-height: 0;
              padding: 2px 0;
              align-items: center;
              justify-content: center;
            }
            body.interactive .slide {
              position: absolute;
              inset: 0;
              display: none;
              padding: 18px;
            }
            body.embedded .slide {
              width: 100%;
              height: 100%;
              padding: 0;
            }
            .slide.active { display: flex; }
            .slide-sheet {
              width: min(86vw, 1366px);
              height: auto;
              aspect-ratio: 16 / 9;
              margin: 0 auto;
              position: relative;
              background: #ffffff;
              border: 1px solid #dbe1ea;
              border-radius: 14px;
              box-shadow: 0 16px 34px rgba(6, 10, 18, 0.30);
              padding: 4.8cqw 4.6cqw 3.9cqw;
              display: grid;
              grid-template-rows: auto auto minmax(0, 1fr) auto;
              gap: 1.8cqw;
              overflow: visible;
              container-type: size;
            }
            .edunode-overlay-layer {
              position: absolute;
              inset: 0;
              pointer-events: none;
              z-index: 8;
            }
            .edunode-overlay {
              position: absolute;
              transform: translate(-50%, -50%);
              display: flex;
              align-items: center;
              justify-content: center;
              overflow: visible;
              pointer-events: none;
            }
            .edunode-image-frame,
            .edunode-overlay.image img,
            .edunode-overlay.vector .edunode-svg-wrap,
            .edunode-overlay.vector .edunode-svg-bg,
            .edunode-overlay.vector .edunode-svg-ink {
              width: 100%;
              height: 100%;
            }
            .edunode-image-frame {
              position: relative;
              overflow: hidden;
            }
            .edunode-overlay.image img {
              object-fit: contain;
              display: block;
            }
            .edunode-overlay.image.pixelated img {
              image-rendering: pixelated;
            }
            .edunode-overlay.vector svg {
              width: 100%;
              height: 100%;
              display: block;
            }
            .edunode-overlay.vector {
              isolation: isolate;
            }
            .edunode-overlay.vector .edunode-svg-bg,
            .edunode-overlay.vector .edunode-svg-ink {
              position: absolute;
              inset: 0;
            }
            .edunode-overlay.vector .edunode-svg-bg {
              z-index: 0;
            }
            .edunode-overlay.vector .edunode-svg-ink {
              z-index: 1;
            }
            .edunode-overlay.text {
              color: #111111;
              white-space: pre-wrap;
              word-break: break-word;
            }
            .edunode-overlay.rect {
              border-radius: 0.68cqw;
            }
            .edunode-overlay.icon {
              border-radius: 999px;
              font-size: 1.82cqw;
              line-height: 1;
            }
            body.interactive .slide-sheet {
              width: min(92vw, 1366px);
            }
            body.embedded .slide-sheet {
              width: min(100vw, calc(100vh * 16 / 9));
            }
            .hero-row {
              display: flex;
              align-items: flex-start;
              justify-content: space-between;
              gap: 1.2cqw;
            }
            .hero h1 {
              margin: 0;
              font-size: 5.0cqw;
              line-height: 1.08;
              color: #111111;
              white-space: pre-wrap;
              word-break: break-word;
            }
            .hero-meta {
              display: flex;
              flex-wrap: wrap;
              align-items: center;
              gap: 0.68cqw;
              margin-top: 0.78cqw;
            }
            .lead {
              margin: 0;
              color: #465062;
              font-size: 1.82cqw;
              white-space: pre-wrap;
              word-break: break-word;
            }
            .toolkit-icon {
              width: 3.45cqw;
              height: 3.45cqw;
              border-radius: 999px;
              display: inline-flex;
              align-items: center;
              justify-content: center;
              background: #e8eefb;
              border: 1px solid #cad7f3;
              font-size: 1.78cqw;
              line-height: 1;
              flex-shrink: 0;
            }
            .toolkit-icon img {
              width: 2.05cqw;
              height: 2.05cqw;
              display: block;
            }
            .level-chip {
              margin: 0;
              display: inline-flex;
              align-items: center;
              padding: 0.26cqw 0.78cqw;
              border-radius: 999px;
              background: #1d8f5a;
              border: 1px solid #1a7e4f;
              color: #ffffff;
              font-size: 1.26cqw;
              line-height: 1.1;
              letter-spacing: 0.01em;
            }
            .main-layout {
              display: grid;
              grid-template-columns: minmax(0, 1fr) minmax(0, 0.62fr);
              gap: 1.25cqw;
              min-height: 0;
            }
            .main-layout.solo {
              grid-template-columns: 1fr;
            }
            .main-card, .activity-card {
              border: 1px solid #d6dde8;
              border-radius: 1.05cqw;
              background: #ffffff;
              padding: 1.1cqw 1.35cqw;
              min-height: 0;
              overflow: visible;
            }
            .knowledge-card.center-brief {
              display: flex;
            }
            .knowledge-content {
              width: 100%;
              display: flex;
              flex-direction: column;
              gap: 0.44cqw;
            }
            .knowledge-card.center-brief .knowledge-content {
              min-height: 100%;
              justify-content: center;
              align-items: center;
            }
            .knowledge-line {
              margin: 0;
              color: #111111;
              font-size: 1.58cqw;
              line-height: 1.34;
              white-space: pre-wrap;
              word-break: break-word;
              text-align: left;
            }
            .knowledge-card.center-brief .knowledge-line {
              text-align: center;
              font-size: 1.84cqw;
              line-height: 1.4;
            }
            .activity-content {
              width: 100%;
              display: flex;
              flex-direction: column;
              gap: 0.34cqw;
            }
            .activity-line {
              margin: 0;
              color: #111111;
              font-size: 1.38cqw;
              line-height: 1.26;
              white-space: pre-wrap;
              word-break: break-word;
            }
            .activity-ordered {
              margin: 0.16cqw 0 0.24cqw;
              padding-left: 1.34cqw;
            }
            .activity-ordered li {
              margin: 0.2cqw 0;
              color: #111111;
              font-size: 1.38cqw;
              line-height: 1.24;
              white-space: pre-wrap;
              word-break: break-word;
            }
            .activity-card.compact,
            .main-card.compact {
              padding: 1.0cqw 1.18cqw;
            }
            .activity-card.tight,
            .main-card.tight {
              padding: 0.92cqw 1.06cqw;
            }
            .activity-card.ultra,
            .main-card.ultra {
              padding: 0.86cqw 1cqw;
            }
            .activity-card.compact .activity-line,
            .activity-card.compact .activity-ordered li,
            .main-card.compact .activity-line,
            .main-card.compact .activity-ordered li {
              font-size: 1.24cqw;
              line-height: 1.2;
            }
            .activity-card.tight .activity-line,
            .activity-card.tight .activity-ordered li,
            .main-card.tight .activity-line,
            .main-card.tight .activity-ordered li {
              font-size: 1.1cqw;
              line-height: 1.16;
            }
            .activity-card.ultra .activity-line,
            .activity-card.ultra .activity-ordered li,
            .main-card.ultra .activity-line,
            .main-card.ultra .activity-ordered li {
              font-size: 0.98cqw;
              line-height: 1.12;
            }
            .main-card h2,
            .activity-card h2 {
              margin: 0 0 0.65cqw;
              font-size: 1.44cqw;
              line-height: 1.15;
              color: #1f2f52;
              letter-spacing: 0.02em;
            }
            .empty {
              margin: 0;
              color: #677488;
              font-size: 1.48cqw;
              line-height: 1.36;
              white-space: pre-wrap;
              word-break: break-word;
            }
            .foot {
              display: flex;
              align-items: flex-end;
              justify-content: space-between;
              gap: 1.1cqw;
              min-height: 2.2cqw;
            }
            .cue {
              margin: 0;
              color: #5d6777;
              font-size: 1.32cqw;
              line-height: 1.3;
              white-space: pre-wrap;
              word-break: break-word;
            }
            .cue-spacer {
              min-height: 1px;
            }
            .slide-index {
              font-size: 1.22cqw;
              line-height: 1;
              color: #7a8496;
              letter-spacing: 0.08em;
              flex-shrink: 0;
            }
            .controls {
              position: fixed;
              left: 50%;
              bottom: 14px;
              transform: translateX(-50%);
              display: inline-flex;
              align-items: center;
              gap: 10px;
              padding: 8px 12px;
              border-radius: 999px;
              background: rgba(255, 255, 255, 0.92);
              border: 1px solid #d7dde8;
              box-shadow: 0 8px 22px rgba(0, 0, 0, 0.08);
              color: #111111;
            }
            .controls button {
              border: 1px solid #ccd3e0;
              color: #111111;
              background: #ffffff;
              border-radius: 999px;
              padding: 6px 12px;
              cursor: pointer;
            }
            .controls button:hover {
              background: #f3f6fc;
            }
            @media print {
              @page { size: landscape; margin: 0; }
              body {
                background: #ffffff;
                overflow: visible;
              }
              .deck {
                width: 100%;
                height: auto;
                display: block;
                padding: 0;
                gap: 0;
              }
              .slide {
                position: relative;
                inset: auto;
                display: block !important;
                padding: 0;
                margin: 0;
                page-break-after: always;
              }
              .slide:last-child { page-break-after: auto; }
              .slide-sheet {
                width: 100%;
                max-width: none;
                min-height: 100%;
                height: 100%;
                aspect-ratio: auto;
                border: none;
                border-radius: 0;
                box-shadow: none;
                padding: 14mm 16mm;
                overflow: visible;
              }
              .controls { display: none !important; }
            }
          </style>
        </head>
        <body class="\(bodyClass)">
          <main class="deck">
            \(renderedSlides)
          </main>
          \(controlsHTML)
          \(scriptHTML)
        </body>
        </html>
        """
    }

    private static func knowledgeBodyHTML(
        items: [String],
        fallback: String,
        centerIfSingleParagraph: Bool
    ) -> String {
        let lines = items
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else {
            return "<p class=\"empty\">\(escapeHTML(fallback))</p>"
        }

        let paragraphs = lines.map { line in
            "<p class=\"knowledge-line\">\(escapeHTML(line))</p>"
        }.joined()

        if centerIfSingleParagraph && lines.count == 1 {
            return "<div class=\"knowledge-content centered\">\(paragraphs)</div>"
        }
        return "<div class=\"knowledge-content\">\(paragraphs)</div>"
    }

    private static func activityBodyHTML(items: [String], fallback: String) -> String {
        let lines = items
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else {
            return "<p class=\"empty\">\(escapeHTML(fallback))</p>"
        }

        enum ActivityBlock {
            case paragraph(String)
            case ordered([String])
        }

        var blocks: [ActivityBlock] = []
        var orderedBuffer: [String] = []

        func flushOrderedBuffer() {
            guard !orderedBuffer.isEmpty else { return }
            blocks.append(.ordered(orderedBuffer))
            orderedBuffer.removeAll()
        }

        for line in lines {
            if let orderedItem = orderedLineContent(from: line) {
                orderedBuffer.append(orderedItem)
            } else {
                flushOrderedBuffer()
                blocks.append(.paragraph(line))
            }
        }
        flushOrderedBuffer()

        let html = blocks.map { block -> String in
            switch block {
            case .paragraph(let text):
                return "<p class=\"activity-line\">\(escapeHTML(text))</p>"
            case .ordered(let values):
                let itemsHTML = values.map { "<li>\(escapeHTML($0))</li>" }.joined()
                return "<ol class=\"activity-ordered\">\(itemsHTML)</ol>"
            }
        }.joined()

        return "<div class=\"activity-content\">\(html)</div>"
    }

    private static func orderedLineContent(from rawLine: String) -> String? {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return nil }

        var index = line.startIndex
        while index < line.endIndex, line[index].isNumber {
            index = line.index(after: index)
        }

        guard index > line.startIndex else { return nil }

        while index < line.endIndex {
            let character = line[index]
            if character == "." || character == "、" || character == ")" || character == "）" ||
                character == ":" || character == "：" || character == "-" || character.isWhitespace {
                index = line.index(after: index)
            } else {
                break
            }
        }

        guard index < line.endIndex else { return nil }
        let content = String(line[index...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return content.isEmpty ? nil : content
    }

    private static func levelChipHTML(from subtitle: String) -> String {
        let normalizedSubtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSubtitle.isEmpty else { return "" }

        let lowercased = normalizedSubtitle.lowercased()
        if lowercased.hasPrefix("level") {
            return "<p class=\"level-chip\">\(escapeHTML(normalizedSubtitle))</p>"
        }

        var index = normalizedSubtitle.startIndex
        while index < normalizedSubtitle.endIndex, normalizedSubtitle[index].isNumber {
            index = normalizedSubtitle.index(after: index)
        }

        guard index > normalizedSubtitle.startIndex else { return "" }

        let levelNumber = String(normalizedSubtitle[..<index])
        while index < normalizedSubtitle.endIndex {
            let character = normalizedSubtitle[index]
            if character == "." || character == "、" || character == ")" || character == "）" || character.isWhitespace {
                index = normalizedSubtitle.index(after: index)
            } else {
                break
            }
        }

        let remainder = index < normalizedSubtitle.endIndex
            ? String(normalizedSubtitle[index...]).trimmingCharacters(in: .whitespacesAndNewlines)
            : ""

        let label = remainder.isEmpty
            ? "Level\(levelNumber)"
            : "Level\(levelNumber). \(remainder)"
        return "<p class=\"level-chip\">\(escapeHTML(label))</p>"
    }

    private static func activityDensityClass(for items: [String]) -> String {
        let lines = items
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return "" }

        let weight = lines.reduce(into: 0) { partialResult, line in
            partialResult += max(1, Int(ceil(Double(line.count) / 44.0)))
        }

        switch weight {
        case 20...:
            return "ultra"
        case 14...:
            return "tight"
        case 9...:
            return "compact"
        default:
            return ""
        }
    }

    private static func toolkitIconHTML() -> String {
        if let dataURI = toolkitSymbolDataURI {
            return "<span class=\"toolkit-icon\" aria-label=\"Toolkit\" title=\"Toolkit\"><img src=\"\(dataURI)\" alt=\"Toolkit\"></span>"
        }
        return "<span class=\"toolkit-icon\" aria-label=\"Toolkit\" title=\"Toolkit\">🛠︎</span>"
    }

    private static let toolkitSymbolDataURI: String? = {
        #if canImport(UIKit)
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 23, weight: .semibold, scale: .large)
        guard let baseSymbol = UIImage(systemName: "wrench.adjustable", withConfiguration: symbolConfig) else {
            return nil
        }

        let symbol = baseSymbol.withTintColor(
            UIColor(red: 0.11, green: 0.23, blue: 0.51, alpha: 1),
            renderingMode: .alwaysOriginal
        )

        let imageSize = CGSize(width: 34, height: 34)
        let rendererFormat = UIGraphicsImageRendererFormat.default()
        rendererFormat.scale = 2
        rendererFormat.opaque = false
        let renderer = UIGraphicsImageRenderer(size: imageSize, format: rendererFormat)
        let rendered = renderer.image { _ in
            symbol.draw(in: CGRect(x: 3.2, y: 3.2, width: 27.6, height: 27.6))
        }

        guard let pngData = rendered.pngData() else {
            return nil
        }
        return "data:image/png;base64,\(pngData.base64EncodedString())"
        #else
        return nil
        #endif
    }()

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    #if canImport(UIKit)
    private static func renderPDF(markupHTML: String, title: String) -> Data? {
        // 16:9 landscape page
        let pageRect = CGRect(x: 0, y: 0, width: 960, height: 540)
        let printableRect = pageRect.insetBy(dx: 12, dy: 12)

        let formatter = UIMarkupTextPrintFormatter(markupText: markupHTML)
        formatter.startPage = 0
        formatter.perPageContentInsets = .zero

        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(formatter, startingAtPageAt: 0)
        renderer.setValue(NSValue(cgRect: pageRect), forKey: "paperRect")
        renderer.setValue(NSValue(cgRect: printableRect), forKey: "printableRect")

        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(
            data,
            pageRect,
            [kCGPDFContextTitle as String: title]
        )
        let pageCount = max(renderer.numberOfPages, 1)
        for pageIndex in 0..<pageCount {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: pageIndex, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()
        return data as Data
    }
    #else
    private static func renderPDF(markupHTML: String, title: String) -> Data? {
        _ = markupHTML
        _ = title
        return nil
    }
    #endif

    #if canImport(UIKit) && canImport(WebKit)
    @MainActor
    @available(iOS 14.0, *)
    private static func renderPDFWithWebView(markupHTML: String) async -> Data? {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1366, height: 768))
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        let delegate = PDFWebViewLoadDelegate()
        webView.navigationDelegate = delegate
        webView.loadHTMLString(markupHTML, baseURL: nil)

        let loaded = await delegate.waitForLoad(timeoutNanoseconds: 18_000_000_000)
        guard loaded else {
            webView.navigationDelegate = nil
            return nil
        }

        // Give WebKit one layout pass before PDF capture.
        try? await Task.sleep(nanoseconds: 120_000_000)

        let configuration = WKPDFConfiguration()
        let contentSize = webView.scrollView.contentSize
        if contentSize.width > 1, contentSize.height > 1 {
            configuration.rect = CGRect(origin: .zero, size: contentSize)
        }

        let pdfData = try? await webView.edunodeCreatePDF(configuration: configuration)
        webView.navigationDelegate = nil
        return pdfData
    }
    #endif
}

#if canImport(UIKit) && canImport(WebKit)
@available(iOS 14.0, *)
private final class PDFWebViewLoadDelegate: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Bool, Never>?
    private var resolved = false
    private var didFinishLoad = false

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        didFinishLoad = true
        resolve(with: true)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        resolve(with: false)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        resolve(with: false)
    }

    @MainActor
    func waitForLoad(timeoutNanoseconds: UInt64) async -> Bool {
        if didFinishLoad {
            return true
        }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            Task { [weak self] in
                guard let self else { return }
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                await MainActor.run {
                    self.resolve(with: false)
                }
            }
        }
    }

    private func resolve(with value: Bool) {
        guard !resolved else { return }
        resolved = true
        continuation?.resume(returning: value)
        continuation = nil
    }
}

@available(iOS 14.0, *)
private extension WKWebView {
    @MainActor
    func edunodeCreatePDF(configuration: WKPDFConfiguration) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            createPDF(configuration: configuration) { result in
                switch result {
                case .success(let data):
                    continuation.resume(returning: data)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
#endif

private struct ParsedLiveNode {
    let textValue: String
    let selectedOption: String
    let formTextFields: [NodeEditorTextFieldSpec]
    let formOptionFields: [NodeEditorOptionFieldSpec]
}
