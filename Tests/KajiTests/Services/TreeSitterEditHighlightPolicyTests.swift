import Testing

@testable import Kaji

@Suite("TreeSitterEditHighlightPolicy")
struct TreeSitterEditHighlightPolicyTests {
    @Test("keeps full reparses for small edits")
    func keepsFullReparseForSmallEdits() {
        #expect(!TreeSitterEditHighlightPolicy.shouldUseLineHighlighterForEdit(
            utf16Length: TreeSitterEditHighlightPolicy.maximumFullTreeReparseUTF16Length
        ))
    }

    @Test("uses line highlighter for larger edited files")
    func usesLineHighlighterForLargerEditedFiles() {
        #expect(TreeSitterEditHighlightPolicy.shouldUseLineHighlighterForEdit(
            utf16Length: TreeSitterEditHighlightPolicy.maximumFullTreeReparseUTF16Length + 1
        ))
    }
}
