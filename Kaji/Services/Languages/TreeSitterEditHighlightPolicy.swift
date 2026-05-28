import Foundation

enum TreeSitterEditHighlightPolicy {
    static let maximumFullTreeReparseUTF16Length = 80000

    static func shouldUseLineHighlighterForEdit(utf16Length: Int) -> Bool {
        utf16Length > maximumFullTreeReparseUTF16Length
    }
}
