@MainActor
struct ViewportVisualLineMap {
    private(set) var lines: [Int] = []
    private var foldedLines: Set<Int> = []
    private var backingLineIndex: [Int] = []
    private var usesIdentityLines = true

    func count(backingLineCount: Int) -> Int {
        if usesIdentityLines {
            return max(backingLineCount, 1)
        }
        return max(lines.count, 1)
    }

    mutating func rebuild(backingLineCount: Int, collapsedRegions: [EditorFoldRegion]) {
        guard !collapsedRegions.isEmpty else {
            foldedLines = []
            lines = []
            backingLineIndex = []
            usesIdentityLines = true
            return
        }
        usesIdentityLines = false
        let hidden = hiddenLines(from: collapsedRegions)
        foldedLines = hidden
        lines = []
        lines.reserveCapacity(backingLineCount)
        backingLineIndex = Array(repeating: -1, count: backingLineCount)
        for line in 0 ..< backingLineCount where !hidden.contains(line) {
            backingLineIndex[line] = lines.count
            lines.append(line)
        }
        if lines.isEmpty { lines = [0] }
    }

    func text(startLine: Int, endLine: Int, backingStore: TextBackingStore) -> String {
        if usesIdentityLines {
            let start = min(max(0, startLine), backingStore.lineCount)
            let end = min(max(start, endLine), backingStore.lineCount)
            return backingStore.textForRange(start ..< end)
        }
        let start = min(max(0, startLine), lines.count)
        let end = min(max(start, endLine), lines.count)
        return lines[start ..< end].map { backingStore.line(at: $0) }.joined(separator: "\n")
    }

    func backingLine(forVisualLine visualLine: Int, backingLineCount: Int) -> Int {
        if usesIdentityLines {
            return min(max(0, visualLine), max(0, backingLineCount - 1))
        }
        guard visualLine >= 0, visualLine < lines.count else { return lines.last ?? 0 }
        return lines[visualLine]
    }

    func visualIndex(forBackingLine backingLine: Int, backingLineCount: Int) -> Int? {
        if usesIdentityLines {
            guard backingLine >= 0, backingLine < backingLineCount else { return nil }
            return backingLine
        }
        guard backingLine >= 0, backingLine < backingLineIndex.count else { return nil }
        let index = backingLineIndex[backingLine]
        return index >= 0 ? index : nil
    }

    func insertionVisualIndex(forBackingLine backingLine: Int, backingLineCount: Int) -> Int {
        if usesIdentityLines {
            return min(max(0, backingLine), max(0, backingLineCount - 1))
        }
        var lowerBound = 0
        var upperBound = lines.count
        while lowerBound < upperBound {
            let middle = (lowerBound + upperBound) / 2
            if lines[middle] < backingLine {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }
        return max(0, lowerBound - 1)
    }

    func isFolded(_ backingLine: Int) -> Bool {
        foldedLines.contains(backingLine)
    }

    private func hiddenLines(from regions: [EditorFoldRegion]) -> Set<Int> {
        var hidden = Set<Int>()
        for region in regions where region.endLine > region.startLine {
            for line in (region.startLine + 1) ... region.endLine {
                hidden.insert(line)
            }
        }
        return hidden
    }
}
