import Foundation

enum KajiAgentStreamingMarkdownPartitioner {
    static func blocks(messageID: UUID, content: String, isComplete: Bool) -> [KajiAgentStreamingMarkdownBlock] {
        let text = content.replacingOccurrences(of: "\r", with: "")
        guard !text.isEmpty else { return [] }
        var blocks: [KajiAgentStreamingMarkdownBlock] = []
        var current: [String] = []
        var fence: KajiAgentMarkdownFence?
        var blockIndex = 0

        func appendBlock(live: Bool) {
            let value = current.joined().trimmingCharacters(in: .newlines)
            current.removeAll(keepingCapacity: true)
            guard !value.isEmpty else { return }
            blocks.append(KajiAgentStreamingMarkdownBlock(
                id: "message.\(messageID.uuidString).markdown.\(blockIndex)",
                content: value,
                isLive: live
            ))
            blockIndex += 1
        }

        for line in text.markdownLinesKeepingNewlines() {
            current.append(line)
            if let activeFence = fence {
                if activeFence.closes(line) {
                    fence = nil
                    appendBlock(live: false)
                }
                continue
            }
            if let nextFence = KajiAgentMarkdownFence(line: line) {
                fence = nextFence
                continue
            }
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                appendBlock(live: false)
            }
        }

        let hasTail = !current.isEmpty
        if hasTail {
            appendBlock(live: !isComplete)
        }
        if isComplete {
            return blocks.map(\.complete)
        }
        return blocks
    }
}

struct KajiAgentMarkdownFence: Hashable {
    let marker: Character
    let length: Int

    init?(line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~"), let first = trimmed.first else { return nil }
        marker = first
        length = trimmed.prefix { $0 == first }.count
    }

    func closes(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == marker else { return false }
        return trimmed.prefix { $0 == marker }.count >= length
    }
}

private extension KajiAgentStreamingMarkdownBlock {
    var complete: KajiAgentStreamingMarkdownBlock {
        KajiAgentStreamingMarkdownBlock(id: id, content: content, isLive: false)
    }
}

extension String {
    func markdownLinesKeepingNewlines() -> [String] {
        var lines: [String] = []
        var current = ""
        for character in self {
            current.append(character)
            if character == "\n" {
                lines.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            lines.append(current)
        }
        return lines
    }
}
