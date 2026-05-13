import Foundation

enum LanguageFoldingRegionParser {
    @MainActor
    static func regions(in backingStore: TextBackingStore, configuration: KajiLanguageConfiguration?) -> [EditorFoldRegion] {
        guard let markers = configuration?.folding?.markers,
              let startRegex = try? NSRegularExpression(pattern: markers.start),
              let endRegex = try? NSRegularExpression(pattern: markers.end)
        else { return [] }

        var stack: [Int] = []
        var regions: [EditorFoldRegion] = []
        for lineIndex in 0 ..< backingStore.lineCount {
            let line = backingStore.line(at: lineIndex)
            let range = NSRange(location: 0, length: (line as NSString).length)
            if startRegex.firstMatch(in: line, range: range) != nil {
                stack.append(lineIndex)
                continue
            }
            if endRegex.firstMatch(in: line, range: range) != nil, let start = stack.popLast(), lineIndex > start {
                regions.append(EditorFoldRegion(startLine: start, endLine: lineIndex))
            }
        }
        return regions
    }
}
