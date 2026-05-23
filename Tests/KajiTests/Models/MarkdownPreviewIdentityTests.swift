import Foundation
import Testing

@testable import Kaji

@Suite("MarkdownPreviewIdentity")
struct MarkdownPreviewIdentityTests {
    @Test("keeps split and preview identities separate for one editor tab")
    func separatesSplitAndPreviewIdentities() {
        let tabID = UUID()

        let split = MarkdownPreviewIdentity.editor(tabID: tabID, mode: .split)
        let preview = MarkdownPreviewIdentity.editor(tabID: tabID, mode: .preview)

        #expect(split != preview)
        #expect(split.hasSuffix("-split"))
        #expect(preview.hasSuffix("-preview"))
    }
}
