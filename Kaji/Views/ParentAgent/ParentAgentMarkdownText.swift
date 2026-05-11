import SwiftUI

struct ParentAgentMarkdownText: View {
    let content: String
    var size: CGFloat = 13
    var color: Color = KajiTheme.fgMuted

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .textSelection(.enabled)
    }

    private var blocks: [ParentAgentMarkdownBlock] {
        ParentAgentMarkdownParser.parse(content)
    }

    @ViewBuilder
    private func blockView(_ block: ParentAgentMarkdownBlock) -> some View {
        switch block {
        case let .heading(level, text):
            MarkdownInlineText(content: text, size: headingSize(level), color: KajiTheme.fg)
                .fontWeight(.semibold)
                .padding(.top, level == 1 ? 8 : 4)
        case let .paragraph(text):
            MarkdownInlineText(content: text, size: size, color: color)
        case let .bullets(items):
            list(items: items, ordered: false)
        case let .ordered(items):
            list(items: items, ordered: true)
        case let .quote(text):
            HStack(alignment: .top, spacing: 10) {
                Rectangle()
                    .fill(KajiTheme.border)
                    .frame(width: 2)
                MarkdownInlineText(content: text, size: size, color: KajiTheme.fgDim)
            }
            .padding(.vertical, 2)
        case let .code(text):
            ScrollView(.horizontal, showsIndicators: true) {
                Text(text)
                    .font(.system(size: max(11, size - 1), design: .monospaced))
                    .foregroundStyle(KajiTheme.fg)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(KajiTheme.bg.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(KajiTheme.border.opacity(0.7)))
        case .divider:
            Rectangle()
                .fill(KajiTheme.border.opacity(0.8))
                .frame(height: 1)
                .padding(.vertical, 4)
        }
    }

    private func list(items: [String], ordered: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 8) {
                    Text(ordered ? "\(index + 1)." : "•")
                        .kajiFont(size: size)
                        .foregroundStyle(KajiTheme.fgDim)
                        .frame(width: ordered ? 24 : 14, alignment: .trailing)
                    MarkdownInlineText(content: item, size: size, color: color)
                }
            }
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: size + 5
        case 2: size + 3
        case 3: size + 1
        default: size
        }
    }
}

enum ParentAgentMarkdownBlock: Hashable {
    case heading(Int, String)
    case paragraph(String)
    case bullets([String])
    case ordered([String])
    case quote(String)
    case code(String)
    case divider
}

enum ParentAgentMarkdownParser {
    static func parse(_ content: String) -> [ParentAgentMarkdownBlock] {
        var blocks: [ParentAgentMarkdownBlock] = []
        var paragraph: [String] = []
        var code: [String] = []
        var inCode = false

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(block(from: paragraph))
            paragraph.removeAll()
        }

        for line in content.replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if inCode {
                    blocks.append(.code(code.joined(separator: "\n")))
                    code.removeAll()
                    inCode = false
                } else {
                    flushParagraph()
                    inCode = true
                }
                continue
            }
            if inCode {
                code.append(line)
                continue
            }
            if trimmed.isEmpty {
                flushParagraph()
                continue
            }
            paragraph.append(line)
        }
        if inCode {
            blocks.append(.code(code.joined(separator: "\n")))
        }
        flushParagraph()
        return blocks
    }

    private static func block(from lines: [String]) -> ParentAgentMarkdownBlock {
        let trimmed = lines.map { $0.trimmingCharacters(in: .whitespaces) }
        if trimmed.count == 1, let line = trimmed.first {
            if line == "---" || line == "***" { return .divider }
            if let heading = heading(line) { return heading }
        }
        if trimmed.allSatisfy(isBullet) {
            return .bullets(trimmed.map { String($0.dropFirst(2)) })
        }
        if trimmed.allSatisfy(isOrdered) {
            return .ordered(trimmed.map(orderedText))
        }
        if trimmed.allSatisfy({ $0.hasPrefix(">") }) {
            return .quote(trimmed.map { $0.dropFirst().trimmingCharacters(in: .whitespaces) }.joined(separator: "\n"))
        }
        return .paragraph(trimmed.joined(separator: "\n"))
    }

    private static func heading(_ line: String) -> ParentAgentMarkdownBlock? {
        let level = line.prefix(while: { $0 == "#" }).count
        guard level > 0, level <= 6, line.dropFirst(level).hasPrefix(" ") else { return nil }
        return .heading(level, String(line.dropFirst(level + 1)))
    }

    private static func isBullet(_ line: String) -> Bool {
        line.hasPrefix("- ") || line.hasPrefix("* ")
    }

    private static func isOrdered(_ line: String) -> Bool {
        guard let dot = line.firstIndex(of: ".") else { return false }
        let prefix = line[..<dot]
        return !prefix.isEmpty && prefix.allSatisfy(\.isNumber) && line[line.index(after: dot)...].hasPrefix(" ")
    }

    private static func orderedText(_ line: String) -> String {
        guard let dot = line.firstIndex(of: ".") else { return line }
        return String(line[line.index(dot, offsetBy: 2)...])
    }
}
