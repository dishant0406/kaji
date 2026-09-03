enum KajiAgentMarkdownParser {
    static func parse(_ content: String) -> [KajiAgentMarkdownBlock] {
        var blocks: [KajiAgentMarkdownBlock] = []
        var paragraph: [String] = []
        var code: [String] = []
        var codeLanguage: String?

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(block(from: paragraph))
            paragraph.removeAll()
        }

        for line in content.replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if codeLanguage != nil || !code.isEmpty {
                    blocks.append(.code(language: codeLanguage, text: code.joined(separator: "\n")))
                    code.removeAll()
                    codeLanguage = nil
                } else {
                    flushParagraph()
                    codeLanguage = fenceLanguage(trimmed)
                }
                continue
            }
            if codeLanguage != nil || !code.isEmpty {
                code.append(line)
                continue
            }
            if trimmed.isEmpty {
                flushParagraph()
                continue
            }
            paragraph.append(line)
        }
        if codeLanguage != nil || !code.isEmpty {
            blocks.append(.code(language: codeLanguage, text: code.joined(separator: "\n")))
        }
        flushParagraph()
        return blocks
    }

    private static func block(from lines: [String]) -> KajiAgentMarkdownBlock {
        let trimmed = lines.map { $0.trimmingCharacters(in: .whitespaces) }
        if trimmed.count == 1, let line = trimmed.first {
            if line == "---" || line == "***" {
                return .divider
            }
            if let heading = heading(line) {
                return heading
            }
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

    private static func fenceLanguage(_ line: String) -> String? {
        let value = line.dropFirst(3).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func heading(_ line: String) -> KajiAgentMarkdownBlock? {
        let level = line.prefix(while: { $0 == "#" }).count
        guard level > 0, level <= 4, line.dropFirst(level).hasPrefix(" ") else { return nil }
        return .heading(level: level, text: String(line.dropFirst(level + 1)))
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
