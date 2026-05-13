import Foundation

struct KajiLanguageConfiguration: Codable, Equatable {
    struct Comments: Codable, Equatable {
        let lineComment: String?
        let blockComment: [String]?
    }

    let comments: Comments?
    let brackets: [[String]]
    let autoClosingPairs: [[String]]
    let surroundingPairs: [[String]]
    let indentationRules: LanguageIndentationRules?
    let folding: LanguageFoldingRules?
}

struct LanguageIndentationRules: Codable, Equatable {
    let increaseIndentPattern: String?
    let decreaseIndentPattern: String?
    let indentNextLinePattern: String?
    let unIndentedLinePattern: String?
}

struct LanguageFoldingRules: Codable, Equatable {
    let markers: Markers?

    struct Markers: Codable, Equatable {
        let start: String
        let end: String
    }
}

struct LanguageSnippet: Codable, Equatable, Identifiable {
    let prefix: String
    let body: [String]
    let description: String?

    var id: String { prefix }
}

struct LanguageFormatterDefinition: Codable, Equatable {
    let command: String
    let arguments: [String]
    let stdin: Bool
}

struct LanguageSyntaxDefinition: Codable, Equatable {
    enum Engine: String, Codable {
        case builtInTokenizer
        case tokenizer
        case treeSitter
        case textMate
        case none
    }

    struct KeywordGroup: Codable, Equatable {
        let scope: String
        let words: [String]
    }

    struct Tokenizer: Codable, Equatable {
        struct StringRule: Codable, Equatable {
            let open: String
            let close: String
            let escape: String?
            let multiline: Bool?
            let scope: String?
        }

        let keywords: [KeywordGroup]
        let strings: [StringRule]
        let supportsNumbers: Bool?
        let supportsHashDirectives: Bool?
        let supportsAtAttributes: Bool?
        let highlightFunctionCalls: Bool?
        let highlightAllCapsAsConstant: Bool?
        let caseSensitiveKeywords: Bool?
    }

    struct BuiltInTokenizer: Codable, Equatable {
        let grammarID: String
    }

    struct TreeSitter: Codable, Equatable {
        struct Parser: Codable, Equatable {
            let id: String
            let version: String?
            let kind: String?
            let artifact: String?
            let sha256: String?
        }

        struct Queries: Codable, Equatable {
            let highlights: String?
            let injections: String?
            let locals: String?
            let folds: String?
        }

        let parser: Parser
        let queries: Queries
    }

    struct TextMate: Codable, Equatable {
        let grammar: String
        let scopeName: String?
    }

    let engine: Engine
    let builtInTokenizer: BuiltInTokenizer?
    let tokenizer: Tokenizer?
    let treeSitter: TreeSitter?
    let textMate: TextMate?
}

struct LanguageLSPDefinition: Codable, Equatable {
    let serverID: String
    let command: String
    let arguments: [String]
    let installHint: String?
}

struct LanguageDefinition: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let extensions: [String]
    let filenames: [String]
    let configuration: KajiLanguageConfiguration
    let syntax: LanguageSyntaxDefinition?
    let lsp: LanguageLSPDefinition?
    let snippets: [LanguageSnippet]
    let formatter: LanguageFormatterDefinition?
    let source: Source
    let rootPath: String?

    enum Source: String, Codable {
        case bundled
        case user
    }
}
