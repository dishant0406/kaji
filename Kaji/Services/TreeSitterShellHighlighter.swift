import Foundation
import SwiftTreeSitter
import TreeSitterBash

struct TreeSitterHighlightSpan: Hashable {
    let range: NSRange
    let scope: SyntaxScope
}

enum TreeSitterShellHighlighter {
    static func spans(in source: String) -> [TreeSitterHighlightSpan] {
        let config = LanguageConfiguration(tree_sitter_bash(), name: "Bash", queries: [:])
        guard !source.isEmpty,
              let data = bashHighlights.data(using: .utf8),
              let query = try? Query(language: config.language, data: data)
        else { return [] }

        let parser = Parser()
        guard (try? parser.setLanguage(config.language)) != nil,
              let tree = parser.parse(source)
        else { return [] }

        let context = Predicate.Context(textProvider: source.predicateTextProvider)
        return query.execute(in: tree)
            .resolve(with: context)
            .highlights()
            .compactMap { namedRange in
                let range = namedRange.range
                guard range.location >= 0, range.upperBound <= source.utf16.count else { return nil }
                return TreeSitterHighlightSpan(range: range, scope: scope(for: namedRange.name))
            }
    }

    private static func scope(for name: String) -> SyntaxScope {
        switch name {
        case "keyword": .keyword
        case "function": .function
        case "property",
             "variable",
             "variable.parameter": .variable
        case "string": .string
        case "comment": .comment
        case "number": .number
        case "constant": .constant
        case "operator": .op
        case "embedded": .preprocessor
        default: .punctuation
        }
    }

    private static let bashHighlights = #"""
    [(string) (raw_string) (heredoc_body) (heredoc_start)] @string
    (command_name) @function
    (variable_name) @variable
    ["case" "do" "done" "elif" "else" "esac" "export" "fi" "for" "function" "if" "in" "select" "then" "unset" "until" "while"] @keyword
    (comment) @comment
    (function_definition name: (word) @function)
    (file_descriptor) @number
    [(command_substitution) (process_substitution) (expansion)] @embedded
    ["$" "&&" ">" ">>" "<" "|"] @operator
    ((command (_) @constant) (#match? @constant "^-"))
    """#
}
