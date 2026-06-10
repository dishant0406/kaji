import Foundation

enum KajiAgentMarkdownBlock: Hashable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullets([String])
    case ordered([String])
    case quote(String)
    case code(language: String?, text: String)
    case divider
}

enum KajiAgentInlineToken: Hashable {
    case text(String)
    case strong(String)
    case emphasis(String)
    case inlineCode(String)
    case link(title: String, url: String)
    case image(alt: String, source: String)
    case filePath(String)
    case command(String)
    case symbol(String)
}
