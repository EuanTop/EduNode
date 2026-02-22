import Foundation
import CoreGraphics
import GNodeKit
#if canImport(UIKit)
import UIKit
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
            return isChinese ? "Knowledge" : "Knowledge"
        case .toolkit:
            return isChinese ? "Toolkit" : "Toolkit"
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
                let subtitle = level.isEmpty ? (isChinese ? "Knowledge" : "Knowledge") : level
                return EduPresentationBaseSlide(
                    id: serialized.id,
                    position: position,
                    nodeType: serialized.nodeType,
                    kind: .knowledge,
                    title: title,
                    subtitle: subtitle,
                    summary: compact(knowledge, maxLength: 120),
                    knowledgeText: compact(knowledge, maxLength: 220),
                    keyPoints: [compact(knowledge, maxLength: 180)],
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
                summary: summary
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
                .map(\.kindLabel)
                .reduce(into: [String]()) { result, next in
                    if !result.contains(next) { result.append(next) }
                }
                .joined(separator: " + ")
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
                    keyline: compact(keyline, maxLength: 150)
                )
            )

            start = idx + 1
        }

        return groups
    }

    static func composeSlides(from groups: [EduPresentationSlideGroup], isChinese: Bool) -> [EduPresentationComposedSlide] {
        groups.enumerated().map { index, group in
            let knowledgeItems = group.sourceSlides
                .filter { $0.kind == .knowledge }
                .map(\.knowledgeText)
                .map { compact($0, maxLength: 72) }
                .filter { !normalized($0).isEmpty }
            let limitedKnowledgeItems = Array(knowledgeItems.prefix(2))

            let toolkitItems = group.sourceSlides
                .filter { $0.kind == .toolkit }
                .map { slide in
                    if normalized(slide.subtitle).isEmpty {
                        return compact(slide.title, maxLength: 72)
                    }
                    return compact("\(slide.title) · \(slide.subtitle)", maxLength: 72)
                }
            let limitedToolkitItems = Array(toolkitItems.prefix(2))

            let keyPoints = deduplicated(
                group.sourceSlides.flatMap(\.keyPoints)
                    .map { compact($0, maxLength: 88) }
                    .filter { !normalized($0).isEmpty }
            )
            let fallbackKeyPoints: [String]
            if keyPoints.isEmpty {
                fallbackKeyPoints = group.sourceSlides
                    .map(\.summary)
                    .map { compact($0, maxLength: 88) }
                    .filter { !normalized($0).isEmpty }
            } else {
                fallbackKeyPoints = keyPoints
            }
            let limitedKeyPoints = Array(fallbackKeyPoints.prefix(4))

            let knowledgePrompt = limitedKnowledgeItems.first ?? group.sourceSlides.first?.summary ?? ""
            let toolkitPrompt = limitedToolkitItems.isEmpty
                ? (isChinese ? "围绕核心知识进行讲授互动。" : "Run guided discussion around the key idea.")
                : limitedToolkitItems.joined(separator: isChinese ? "、" : ", ")
            let speakerNotes = [
                isChinese
                    ? "开场先聚焦：\(compact(knowledgePrompt, maxLength: 62))"
                    : "Open with focus: \(compact(knowledgePrompt, maxLength: 62))",
                isChinese
                    ? "实施活动：\(compact(toolkitPrompt, maxLength: 68))"
                    : "Run activity: \(compact(toolkitPrompt, maxLength: 68))",
                isChinese
                    ? "结尾追问并收束本页核心产出。"
                    : "Close with check questions and explicit outcomes."
            ]
            let limitedSpeakerNotes = speakerNotes.map { compact($0, maxLength: 72) }

            return EduPresentationComposedSlide(
                id: group.id,
                index: index + 1,
                title: compact(group.slideTitle, maxLength: 54),
                subtitle: compact(group.subtitle, maxLength: 40),
                knowledgeItems: limitedKnowledgeItems,
                toolkitItems: limitedToolkitItems,
                keyPoints: limitedKeyPoints,
                speakerNotes: limitedSpeakerNotes
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
            return compact(textValue, maxLength: 120)
        }
        if let firstField = textFields.first(where: { !normalized($0.value).isEmpty }) {
            return compact("\(firstField.label): \(firstField.value)", maxLength: 120)
        }
        if let firstOption = optionFields.first(where: { !normalized($0.selectedOption).isEmpty }) {
            return compact("\(firstOption.label): \(firstOption.selectedOption)", maxLength: 120)
        }
        return isChinese ? "（待补充活动内容）" : "(Activity details pending)"
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
        summary: String
    ) -> [String] {
        var points: [String] = []

        for field in optionFields {
            let selected = normalized(field.selectedOption)
            guard !selected.isEmpty else { continue }
            points.append(compact("\(field.label): \(selected)", maxLength: 110))
        }

        for field in textFields {
            let value = normalized(field.value)
            guard !value.isEmpty else { continue }
            points.append(compact("\(field.label): \(value)", maxLength: 130))
        }

        if points.isEmpty {
            points.append(compact(summary, maxLength: 120))
        }

        return Array(deduplicated(points).prefix(6))
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

    private static func compact(_ value: String, maxLength: Int) -> String {
        let cleaned = value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " / ")
        if cleaned.count <= maxLength { return cleaned }
        return String(cleaned.prefix(maxLength)) + "..."
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
        renderedHTML(courseName: courseName, slides: slides, isChinese: isChinese, interactive: true, embedded: false)
    }

    static func printHTML(courseName: String, slides: [EduPresentationComposedSlide], isChinese: Bool) -> String {
        renderedHTML(courseName: courseName, slides: slides, isChinese: isChinese, interactive: false, embedded: false)
    }

    static func singleSlideHTML(courseName: String, slide: EduPresentationComposedSlide, isChinese: Bool) -> String {
        renderedHTML(courseName: courseName, slides: [slide], isChinese: isChinese, interactive: false, embedded: true)
    }

    static func pdfData(courseName: String, slides: [EduPresentationComposedSlide], isChinese: Bool) -> Data? {
        let rendered = printHTML(courseName: courseName, slides: slides, isChinese: isChinese)
        let title = courseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (isChinese ? "课程演讲" : "Course Presentation")
            : courseName
        return renderPDF(markupHTML: rendered, title: title)
    }

    private static func renderedHTML(
        courseName: String,
        slides: [EduPresentationComposedSlide],
        isChinese: Bool,
        interactive: Bool,
        embedded: Bool
    ) -> String {
        let bodyClass: String = {
            if embedded { return "embedded" }
            if interactive { return "interactive" }
            return "preview"
        }()

        let title = courseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (isChinese ? "课程演讲" : "Course Presentation")
            : courseName

        let knowledgeTitle = isChinese ? "知识点" : "Knowledge"
        let toolkitTitle = isChinese ? "工具方法" : "Toolkit"
        let coreTitle = isChinese ? "核心要点" : "Core Points"
        let notesTitle = isChinese ? "讲述备注" : "Speaker Notes"
        let emptyMessage = isChinese ? "当前没有可生成的演讲页面。" : "No slide content available."
        let prevLabel = isChinese ? "上一页" : "Prev"
        let nextLabel = isChinese ? "下一页" : "Next"

        let renderedSlides: String = {
            guard !slides.isEmpty else {
                return """
                <section class="slide \(interactive ? "active" : "")">
                  <article class="slide-sheet">
                    <header class="hero">
                      <div class="meta">Slide 1</div>
                      <h1>\(escapeHTML(title))</h1>
                      <p>\(escapeHTML(emptyMessage))</p>
                    </header>
                  </article>
                </section>
                """
            }

            return slides.enumerated().map { index, slide in
                let knowledgeHTML = listHTML(
                    items: slide.knowledgeItems,
                    fallback: isChinese ? "本页无独立知识讲授条目。" : "No standalone knowledge item on this slide."
                )
                let toolkitHTML = listHTML(
                    items: slide.toolkitItems,
                    fallback: isChinese ? "本页无工具活动配置。" : "No toolkit activity on this slide."
                )
                let keyPointsHTML = listHTML(
                    items: slide.keyPoints,
                    fallback: isChinese ? "待补充关键要点。" : "Key points pending."
                )
                let notesHTML = listHTML(
                    items: slide.speakerNotes,
                    fallback: isChinese ? "待补充讲述备注。" : "Speaker notes pending."
                )

                return """
                <section class="slide\(interactive && index == 0 ? " active" : "")">
                  <article class="slide-sheet">
                    <header class="hero">
                      <div class="meta">Slide \(slide.index)</div>
                      <h1>\(escapeHTML(slide.title))</h1>
                      <p>\(escapeHTML(slide.subtitle))</p>
                    </header>

                    <section class="grid-two">
                      <article class="card">
                        <h2>\(escapeHTML(knowledgeTitle))</h2>
                        \(knowledgeHTML)
                      </article>
                      <article class="card">
                        <h2>\(escapeHTML(toolkitTitle))</h2>
                        \(toolkitHTML)
                      </article>
                    </section>

                    <section class="grid-two">
                      <article class="card">
                        <h2>\(escapeHTML(coreTitle))</h2>
                        \(keyPointsHTML)
                      </article>
                      <article class="card">
                        <h2>\(escapeHTML(notesTitle))</h2>
                        \(notesHTML)
                      </article>
                    </section>
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
              background: #eef1f5;
              color: #111111;
              font: 16px/1.38 -apple-system, BlinkMacSystemFont, "SF Pro Text", "PingFang SC", "Helvetica Neue", Arial, sans-serif;
              -webkit-text-size-adjust: 100%;
              text-size-adjust: 100%;
            }
            body.preview {
              overflow: auto;
              scrollbar-gutter: stable both-edges;
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
              gap: 18px;
              padding: 8px 0 24px;
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
              padding: 0;
              align-items: center;
              justify-content: center;
            }
            body.interactive .slide {
              position: absolute;
              inset: 0;
              display: none;
              padding: 20px;
            }
            body.embedded .slide {
              width: 100%;
              height: 100%;
            }
            .slide.active { display: flex; }
            .slide-sheet {
              width: min(82vw, 1280px);
              height: auto;
              aspect-ratio: 16 / 9;
              margin: 0 auto;
              background: #ffffff;
              border: 1px solid #d7dde8;
              border-radius: 16px;
              box-shadow: 0 16px 36px rgba(13, 19, 34, 0.14);
              padding: clamp(8px, 1.8cqw, 24px) clamp(10px, 2cqw, 28px);
              display: grid;
              grid-template-rows: auto minmax(0, 1fr) minmax(0, 1fr);
              gap: clamp(6px, 1cqw, 12px);
              overflow: hidden;
              container-type: inline-size;
            }
            body.interactive .slide-sheet {
              width: min(90vw, 1280px);
            }
            body.embedded .slide-sheet {
              width: min(100vw, calc(100vh * 16 / 9));
            }
            .hero h1 {
              margin: 6px 0 4px;
              font-size: clamp(12px, 2.6cqw, 34px);
              line-height: 1.12;
              color: #111111;
              display: -webkit-box;
              -webkit-line-clamp: 2;
              -webkit-box-orient: vertical;
              overflow: hidden;
            }
            .hero p {
              margin: 0;
              color: #4a5567;
              font-size: clamp(10px, 1.15cqw, 16px);
              display: -webkit-box;
              -webkit-line-clamp: 1;
              -webkit-box-orient: vertical;
              overflow: hidden;
            }
            .meta {
              display: inline-block;
              font-size: clamp(8px, 0.9cqw, 12px);
              border-radius: 999px;
              padding: clamp(2px, 0.3cqw, 4px) clamp(6px, 0.8cqw, 10px);
              background: #111111;
              color: #ffffff;
            }
            .grid-two {
              display: grid;
              grid-template-columns: 1fr 1fr;
              gap: clamp(6px, 1cqw, 10px);
              min-height: 0;
            }
            .card {
              border: 1px solid #d7dde8;
              border-radius: 10px;
              padding: clamp(6px, 1cqw, 12px) clamp(8px, 1.2cqw, 14px);
              min-height: 0;
              overflow: hidden;
              background: #ffffff;
            }
            .card h2 {
              margin: 0 0 6px;
              font-size: clamp(8px, 0.95cqw, 12px);
              letter-spacing: 0.24px;
              text-transform: uppercase;
              color: #1e2f55;
              display: -webkit-box;
              -webkit-line-clamp: 1;
              -webkit-box-orient: vertical;
              overflow: hidden;
            }
            ul {
              margin: 0;
              padding-left: clamp(10px, 1.4cqw, 18px);
              max-height: 100%;
              overflow: hidden;
            }
            li {
              margin: clamp(2px, 0.5cqw, 6px) 0;
              font-size: clamp(9px, 0.95cqw, 14px);
              color: #111111;
              display: -webkit-box;
              -webkit-line-clamp: 2;
              -webkit-box-orient: vertical;
              overflow: hidden;
            }
            .muted {
              color: #677488;
              font-style: italic;
              font-size: clamp(9px, 0.95cqw, 14px);
              display: -webkit-box;
              -webkit-line-clamp: 3;
              -webkit-box-orient: vertical;
              overflow: hidden;
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
                overflow: hidden;
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

    private static func listHTML(items: [String], fallback: String) -> String {
        if items.isEmpty {
            return "<p class=\"muted\">\(escapeHTML(fallback))</p>"
        }
        let li = items.map { "<li>\(escapeHTML($0))</li>" }.joined()
        return "<ul>\(li)</ul>"
    }

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
}

private struct ParsedLiveNode {
    let textValue: String
    let selectedOption: String
    let formTextFields: [NodeEditorTextFieldSpec]
    let formOptionFields: [NodeEditorOptionFieldSpec]
}
