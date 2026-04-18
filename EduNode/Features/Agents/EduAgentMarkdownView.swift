import Foundation
import SwiftUI

struct EduAgentMarkdownBubbleContent: View {
    let markdown: String
    let maxWidth: CGFloat

    private var blocks: [EduAgentMarkdownBlock] {
        EduAgentMarkdownParser.parse(markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(blocks) { block in
                EduAgentMarkdownBlockView(
                    block: block,
                    maxWidth: maxWidth - 24
                )
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct EduAgentMarkdownBlock: Identifiable {
    enum Kind {
        case heading(level: Int, text: String)
        case paragraph(text: String)
        case unorderedList(items: [String])
        case orderedList(items: [String])
        case horizontalRule
        case table(headers: [String], rows: [[String]])
        case codeBlock(language: String?, code: String)
    }

    let id = UUID()
    let kind: Kind
}

private enum EduAgentMarkdownParser {
    static func parse(_ markdown: String) -> [EduAgentMarkdownBlock] {
        let lines = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: .newlines)

        var blocks: [EduAgentMarkdownBlock] = []
        var index = 0

        while index < lines.count {
            let rawLine = lines[index]
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                let language = trimmed.dropFirst(3).trimmingCharacters(in: .whitespacesAndNewlines)
                var codeLines: [String] = []
                index += 1
                while index < lines.count {
                    let line = lines[index]
                    if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        index += 1
                        break
                    }
                    codeLines.append(line)
                    index += 1
                }
                blocks.append(
                    EduAgentMarkdownBlock(
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
                blocks.append(EduAgentMarkdownBlock(kind: .horizontalRule))
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
                    let rowLine = lines[index].trimmingCharacters(in: .whitespaces)
                    guard isTableRow(rowLine), !rowLine.isEmpty else { break }
                    rows.append(parseTableRow(rowLine))
                    index += 1
                }
                blocks.append(EduAgentMarkdownBlock(kind: .table(headers: headers, rows: rows)))
                continue
            }

            if let unordered = listItems(in: lines, startAt: index, ordered: false) {
                blocks.append(EduAgentMarkdownBlock(kind: .unorderedList(items: unordered.items)))
                index = unordered.nextIndex
                continue
            }

            if let ordered = listItems(in: lines, startAt: index, ordered: true) {
                blocks.append(EduAgentMarkdownBlock(kind: .orderedList(items: ordered.items)))
                index = ordered.nextIndex
                continue
            }

            var paragraphLines: [String] = [trimmed]
            index += 1
            while index < lines.count {
                let nextTrimmed = lines[index].trimmingCharacters(in: .whitespaces)
                if nextTrimmed.isEmpty
                    || nextTrimmed.hasPrefix("```")
                    || headingBlock(from: nextTrimmed) != nil
                    || isHorizontalRule(nextTrimmed)
                    || (isTableRow(nextTrimmed) && index + 1 < lines.count && isTableSeparator(lines[index + 1]))
                    || listItems(in: lines, startAt: index, ordered: false) != nil
                    || listItems(in: lines, startAt: index, ordered: true) != nil {
                    break
                }
                paragraphLines.append(nextTrimmed)
                index += 1
            }

            blocks.append(
                EduAgentMarkdownBlock(
                    kind: .paragraph(text: paragraphLines.joined(separator: "\n"))
                )
            )
        }

        return blocks.isEmpty
            ? [EduAgentMarkdownBlock(kind: .paragraph(text: markdown.trimmingCharacters(in: .whitespacesAndNewlines)))]
            : blocks
    }

    private static func headingBlock(from line: String) -> EduAgentMarkdownBlock? {
        let prefixCount = line.prefix { $0 == "#" }.count
        guard (1...6).contains(prefixCount) else { return nil }
        let text = line.dropFirst(prefixCount).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return EduAgentMarkdownBlock(kind: .heading(level: prefixCount, text: text))
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3 else { return false }
        if Set(compact) == ["-"] || Set(compact) == ["*"] || Set(compact) == ["_"] {
            return true
        }
        return false
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

            guard let item = itemText else { break }
            items.append(item)
            current += 1
        }

        guard !items.isEmpty else { return nil }
        return (items, current)
    }

    private static func unorderedListItemText(from line: String) -> String? {
        guard let marker = line.first, ["-", "*", "+"].contains(marker) else { return nil }
        let text = line.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
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
        let text = line[line.index(after: index)...].trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

private struct EduAgentMarkdownBlockView: View {
    let block: EduAgentMarkdownBlock
    let maxWidth: CGFloat

    var body: some View {
        switch block.kind {
        case .heading(let level, let text):
            inlineText(text, font: headingFont(level))

        case .paragraph(let text):
            inlineText(text, font: .subheadline)

        case .unorderedList(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { entry in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.top, 1)
                        inlineText(entry.element, font: .subheadline)
                    }
                }
            }

        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1).")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.top, 1)
                        inlineText(item, font: .subheadline)
                    }
                }
            }

        case .horizontalRule:
            Rectangle()
                .fill(Color.white.opacity(0.16))
                .frame(height: 1)
                .padding(.vertical, 2)

        case .table(let headers, let rows):
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                        GridRow {
                            ForEach(Array(headers.enumerated()), id: \.offset) { entry in
                                inlineText(entry.element, font: .caption.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.96))
                            }
                        }

                        Rectangle()
                            .fill(Color.white.opacity(0.14))
                            .frame(height: 1)
                            .gridCellColumns(max(headers.count, 1))

                        ForEach(Array(rows.enumerated()), id: \.offset) { rowEntry in
                            GridRow {
                                ForEach(Array(normalizedRow(rowEntry.element, columns: headers.count).enumerated()), id: \.offset) { cellEntry in
                                    inlineText(cellEntry.element, font: .caption)
                                        .foregroundStyle(.white.opacity(0.88))
                                }
                            }
                        }
                    }
                    .padding(10)
                }
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
            }

        case .codeBlock(let language, let code):
            VStack(alignment: .leading, spacing: 6) {
                if let language, !language.isEmpty {
                    Text(language.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(code)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.92))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .padding(10)
            .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private func inlineText(_ source: String, font: Font) -> some View {
        if let attributed = try? AttributedString(
            markdown: source,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            Text(attributed)
                .font(font)
                .foregroundStyle(.white.opacity(0.92))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(source)
                .font(font)
                .foregroundStyle(.white.opacity(0.92))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1:
            return .title3.weight(.bold)
        case 2:
            return .headline.weight(.bold)
        default:
            return .subheadline.weight(.bold)
        }
    }

    private func normalizedRow(_ row: [String], columns: Int) -> [String] {
        guard row.count < columns else { return row }
        return row + Array(repeating: "", count: columns - row.count)
    }
}
