import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum EduMarkdownDocumentRenderer {
    static func html(
        markdown: String,
        title: String,
        isChinese: Bool
    ) -> String {
        let blocks = parseBlocks(markdown)
        let body = blocks.map { renderHTML(for: $0) }.joined(separator: "\n")
        let language = isChinese ? "zh" : "en"

        return """
        <!doctype html>
        <html lang="\(language)">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            :root {
              color-scheme: dark;
              --bg: #0d1117;
              --panel: #121821;
              --line: rgba(255,255,255,0.10);
              --text: #eef2f7;
              --muted: rgba(238,242,247,0.74);
              --accent: #3cc7be;
            }
            * { box-sizing: border-box; }
            body {
              margin: 0;
              padding: 32px 36px 48px;
              background: linear-gradient(180deg, #0b1118 0%, #0d1117 100%);
              color: var(--text);
              font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "PingFang SC", sans-serif;
              line-height: 1.68;
            }
            .document {
              max-width: 980px;
              margin: 0 auto;
              background: rgba(18, 24, 33, 0.88);
              border: 1px solid var(--line);
              border-radius: 24px;
              padding: 28px 30px 34px;
              box-shadow: 0 18px 44px rgba(0,0,0,0.28);
            }
            .doc-title {
              font-size: 13px;
              letter-spacing: 0.08em;
              text-transform: uppercase;
              color: var(--accent);
              margin-bottom: 10px;
            }
            h1, h2, h3, h4, h5, h6 {
              color: #ffffff;
              margin: 1.25em 0 0.52em;
              line-height: 1.25;
            }
            h1 { font-size: 1.95rem; }
            h2 {
              font-size: 1.45rem;
              padding-bottom: 0.28em;
              border-bottom: 1px solid var(--line);
            }
            h3 { font-size: 1.18rem; }
            p { margin: 0.68em 0; color: var(--text); white-space: pre-wrap; }
            ul, ol { margin: 0.62em 0 0.86em 1.2em; padding: 0; }
            li { margin: 0.34em 0; }
            hr {
              border: none;
              border-top: 1px solid var(--line);
              margin: 1.2em 0;
            }
            table {
              width: 100%;
              border-collapse: collapse;
              margin: 1em 0;
              overflow: hidden;
              border-radius: 14px;
              background: rgba(255,255,255,0.02);
            }
            th, td {
              border: 1px solid rgba(255,255,255,0.08);
              padding: 10px 12px;
              vertical-align: top;
              text-align: left;
            }
            thead th {
              background: rgba(60,199,190,0.10);
              color: #ffffff;
            }
            pre {
              margin: 1em 0;
              padding: 14px 16px;
              border-radius: 14px;
              background: rgba(0,0,0,0.26);
              border: 1px solid rgba(255,255,255,0.08);
              overflow-x: auto;
              color: #d8f5f3;
            }
            code {
              font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
              font-size: 0.92em;
            }
            .empty {
              color: var(--muted);
            }
          </style>
        </head>
        <body>
          <article class="document">
            <div class="doc-title">\(escapeHTML(title))</div>
            \(body.isEmpty ? "<p class=\"empty\">\(escapeHTML(isChinese ? "暂无可预览内容。" : "No preview content yet."))</p>" : body)
          </article>
        </body>
        </html>
        """
    }

    #if canImport(UIKit)
    static func pdfData(
        markdown: String,
        title: String,
        isChinese: Bool
    ) -> Data? {
        let htmlString = html(markdown: markdown, title: title, isChinese: isChinese)
        let pageRect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
        let printableRect = pageRect.insetBy(dx: 28, dy: 30)

        let formatter = UIMarkupTextPrintFormatter(markupText: htmlString)
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
    static func pdfData(
        markdown: String,
        title: String,
        isChinese: Bool
    ) -> Data? {
        _ = markdown
        _ = title
        _ = isChinese
        return nil
    }
    #endif

    private struct MarkdownBlock {
        enum Kind {
            case heading(level: Int, text: String)
            case paragraph(text: String)
            case unorderedList(items: [String])
            case orderedList(items: [String])
            case horizontalRule
            case table(headers: [String], rows: [[String]])
            case codeBlock(language: String?, code: String)
        }

        let kind: Kind
    }

    private static func parseBlocks(_ markdown: String) -> [MarkdownBlock] {
        let lines = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: .newlines)

        var blocks: [MarkdownBlock] = []
        var index = 0

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                let language = trimmed.dropFirst(3).trimmingCharacters(in: .whitespacesAndNewlines)
                var codeLines: [String] = []
                index += 1
                while index < lines.count {
                    let next = lines[index]
                    if next.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        index += 1
                        break
                    }
                    codeLines.append(next)
                    index += 1
                }
                blocks.append(
                    MarkdownBlock(
                        kind: .codeBlock(
                            language: language.isEmpty ? nil : language,
                            code: codeLines.joined(separator: "\n")
                        )
                    )
                )
                continue
            }

            if let heading = headingBlock(from: trimmed) {
                blocks.append(heading)
                index += 1
                continue
            }

            if isHorizontalRule(trimmed) {
                blocks.append(MarkdownBlock(kind: .horizontalRule))
                index += 1
                continue
            }

            if index + 1 < lines.count,
               isTableRow(trimmed),
               isTableSeparator(lines[index + 1]) {
                let headers = parseTableRow(trimmed)
                var rows: [[String]] = []
                index += 2
                while index < lines.count {
                    let next = lines[index].trimmingCharacters(in: .whitespaces)
                    guard isTableRow(next), !next.isEmpty else { break }
                    rows.append(parseTableRow(next))
                    index += 1
                }
                blocks.append(MarkdownBlock(kind: .table(headers: headers, rows: rows)))
                continue
            }

            if let unordered = listItems(in: lines, startAt: index, ordered: false) {
                blocks.append(MarkdownBlock(kind: .unorderedList(items: unordered.items)))
                index = unordered.nextIndex
                continue
            }

            if let ordered = listItems(in: lines, startAt: index, ordered: true) {
                blocks.append(MarkdownBlock(kind: .orderedList(items: ordered.items)))
                index = ordered.nextIndex
                continue
            }

            var paragraphLines: [String] = [trimmed]
            index += 1
            while index < lines.count {
                let next = lines[index].trimmingCharacters(in: .whitespaces)
                if next.isEmpty
                    || next.hasPrefix("```")
                    || headingBlock(from: next) != nil
                    || isHorizontalRule(next)
                    || (isTableRow(next) && index + 1 < lines.count && isTableSeparator(lines[index + 1]))
                    || listItems(in: lines, startAt: index, ordered: false) != nil
                    || listItems(in: lines, startAt: index, ordered: true) != nil {
                    break
                }
                paragraphLines.append(next)
                index += 1
            }
            blocks.append(MarkdownBlock(kind: .paragraph(text: paragraphLines.joined(separator: "\n"))))
        }

        return blocks
    }

    private static func renderHTML(for block: MarkdownBlock) -> String {
        switch block.kind {
        case .heading(let level, let text):
            let tag = "h\(min(max(level, 1), 6))"
            return "<\(tag)>\(renderInlineMarkdown(text))</\(tag)>"
        case .paragraph(let text):
            return "<p>\(renderInlineMarkdown(text))</p>"
        case .unorderedList(let items):
            let renderedItems = items.map { "<li>\(renderInlineMarkdown($0))</li>" }.joined()
            return "<ul>\(renderedItems)</ul>"
        case .orderedList(let items):
            let renderedItems = items.map { "<li>\(renderInlineMarkdown($0))</li>" }.joined()
            return "<ol>\(renderedItems)</ol>"
        case .horizontalRule:
            return "<hr>"
        case .table(let headers, let rows):
            let headerHTML = headers.map { "<th>\(renderInlineMarkdown($0))</th>" }.joined()
            let rowHTML = rows.map { row in
                let cells = row.map { "<td>\(renderInlineMarkdown($0))</td>" }.joined()
                return "<tr>\(cells)</tr>"
            }.joined()
            return """
            <table>
              <thead><tr>\(headerHTML)</tr></thead>
              <tbody>\(rowHTML)</tbody>
            </table>
            """
        case .codeBlock(let language, let code):
            let header = language.map { "<div>\(escapeHTML($0))</div>" } ?? ""
            return "<pre>\(header)<code>\(escapeHTML(code))</code></pre>"
        }
    }

    private static func renderInlineMarkdown(_ text: String) -> String {
        var html = escapeHTML(text)

        let replacements: [(pattern: String, template: String)] = [
            ("\\*\\*(.+?)\\*\\*", "<strong>$1</strong>"),
            ("__(.+?)__", "<strong>$1</strong>"),
            ("(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)", "<em>$1</em>"),
            ("(?<!_)_(?!_)(.+?)(?<!_)_(?!_)", "<em>$1</em>"),
            ("`([^`]+)`", "<code>$1</code>")
        ]

        for replacement in replacements {
            html = html.replacingOccurrences(
                of: replacement.pattern,
                with: replacement.template,
                options: .regularExpression
            )
        }

        html = html.replacingOccurrences(of: "\n", with: "<br>")
        return html
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func headingBlock(from line: String) -> MarkdownBlock? {
        let prefixCount = line.prefix { $0 == "#" }.count
        guard (1...6).contains(prefixCount) else { return nil }
        let text = line.dropFirst(prefixCount).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return MarkdownBlock(kind: .heading(level: prefixCount, text: text))
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3 else { return false }
        return Set(compact) == ["-"] || Set(compact) == ["*"] || Set(compact) == ["_"]
    }

    private static func isTableRow(_ line: String) -> Bool {
        line.contains("|")
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let cells = parseTableRow(line)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let trimmed = cell.trimmingCharacters(in: CharacterSet(charactersIn: " :-"))
            return trimmed.isEmpty && cell.contains("-")
        }
    }

    private static func parseTableRow(_ line: String) -> [String] {
        line
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private static func listItems(
        in lines: [String],
        startAt index: Int,
        ordered: Bool
    ) -> (items: [String], nextIndex: Int)? {
        guard index < lines.count else { return nil }
        var items: [String] = []
        var current = index

        while current < lines.count {
            let line = lines[current].trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { break }

            let itemText: String?
            if ordered {
                itemText = orderedListItemText(from: line)
            } else {
                itemText = unorderedListItemText(from: line)
            }

            guard let itemText, !itemText.isEmpty else { break }
            items.append(itemText)
            current += 1
        }

        guard !items.isEmpty else { return nil }
        return (items, current)
    }

    private static func unorderedListItemText(from line: String) -> String? {
        guard let marker = line.first, ["-", "*", "+"].contains(marker) else { return nil }
        return String(line.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func orderedListItemText(from line: String) -> String? {
        var digits = ""
        var index = line.startIndex
        while index < line.endIndex, line[index].isNumber {
            digits.append(line[index])
            index = line.index(after: index)
        }
        guard !digits.isEmpty, index < line.endIndex else { return nil }
        let marker = line[index]
        guard marker == "." || marker == ")" else { return nil }
        return String(line[line.index(after: index)...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
