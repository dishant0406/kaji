import Foundation

enum EditorSymbolParser {
    @MainActor
    static func symbols(in backingStore: TextBackingStore, languageID: String?) -> [EditorSymbol] {
        let patterns = patterns(for: languageID)
        var symbols: [EditorSymbol] = []
        for lineIndex in 0 ..< backingStore.lineCount {
            let line = backingStore.line(at: lineIndex)
            let nsLine = line as NSString
            let range = NSRange(location: 0, length: nsLine.length)
            for pattern in patterns {
                guard let match = pattern.regex.firstMatch(in: line, range: range), match.numberOfRanges > 1 else { continue }
                let nameRange = match.range(at: 1)
                guard nameRange.location != NSNotFound else { continue }
                symbols.append(EditorSymbol(
                    name: nsLine.substring(with: nameRange),
                    kind: pattern.kind,
                    line: lineIndex,
                    column: nameRange.location
                ))
                break
            }
        }
        return symbols
    }

    private static func patterns(for languageID: String?) -> [Pattern] {
        switch languageID {
        case "swift": swiftPatterns
        case "python": pythonPatterns
        case "ruby": rubyPatterns
        case "shell": shellPatterns
        default: commonPatterns
        }
    }

    private static let commonPatterns = [
        Pattern(#"^\s*(?:export\s+)?(?:async\s+)?function\s+([A-Za-z_$][\w$]*)"#, .function),
        Pattern(#"^\s*(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*(?:async\s*)?\("#, .function),
        Pattern(#"^\s*class\s+([A-Za-z_$][\w$]*)"#, .type),
        Pattern(#"^\s*struct\s+([A-Za-z_$][\w$]*)"#, .type),
        Pattern(#"^\s*enum\s+([A-Za-z_$][\w$]*)"#, .type),
        Pattern(#"^\s*#{1,6}\s+(.+)$"#, .section),
    ]

    private static let swiftPatterns = [
        Pattern(#"^\s*(?:public|private|internal|fileprivate|open)?\s*(?:static\s+)?func\s+([A-Za-z_][\w]*)"#, .function),
        Pattern(
            #"^\s*(?:public|private|internal|fileprivate|open)?\s*(?:final\s+)?(?:class|struct|enum|actor|protocol)\s+([A-Za-z_][\w]*)"#,
            .type
        ),
        Pattern(#"^\s*(?:public|private|internal|fileprivate|open)?\s*(?:static\s+)?(?:let|var)\s+([A-Za-z_][\w]*)"#, .property),
    ]

    private static let pythonPatterns = [
        Pattern(#"^\s*def\s+([A-Za-z_][\w]*)"#, .function),
        Pattern(#"^\s*class\s+([A-Za-z_][\w]*)"#, .type),
    ]

    private static let rubyPatterns = [
        Pattern(#"^\s*def\s+([A-Za-z_][\w!?=]*)"#, .function),
        Pattern(#"^\s*class\s+([A-Za-z_][\w:]*)"#, .type),
        Pattern(#"^\s*module\s+([A-Za-z_][\w:]*)"#, .type),
    ]

    private static let shellPatterns = [
        Pattern(#"^\s*([A-Za-z_][\w]*)\s*\(\)\s*\{"#, .function),
        Pattern(#"^\s*function\s+([A-Za-z_][\w]*)"#, .function),
    ]

    private struct Pattern {
        let regex: NSRegularExpression
        let kind: EditorSymbol.Kind

        init(_ pattern: String, _ kind: EditorSymbol.Kind) {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                preconditionFailure("Invalid editor symbol pattern")
            }
            self.regex = regex
            self.kind = kind
        }
    }
}
