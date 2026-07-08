import Testing

@testable import Kaji

@Suite("Kaji app menu commands")
struct KajiAppMenuCommandTests {
    @Test("menu titles are stable and visible")
    func menuTitlesAreStableAndVisible() {
        #expect(KajiAppMenuCommand.allCases.map(\.title) == [
            "Settings...",
            "Open Configuration...",
            "Reload Configuration",
            "Check for Updates...",
        ])
    }

    @Test("menu titles are never blank or icon only")
    func menuTitlesAreNeverBlankOrIconOnly() {
        for command in KajiAppMenuCommand.allCases {
            let title = command.title.trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(!title.isEmpty)
            #expect(title.contains { $0.isLetter })
            #expect(title.count <= 30)
        }
    }
}
