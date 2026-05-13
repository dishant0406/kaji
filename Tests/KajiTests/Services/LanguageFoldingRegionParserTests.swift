import Testing

@testable import Kaji

@Suite("LanguageFoldingRegionParser")
@MainActor
struct LanguageFoldingRegionParserTests {
    @Test("folding markers produce nested regions")
    func markerRegions() {
        let store = TextBackingStore()
        store.loadFromText("""
        // region outer
        let a = 1
        // region inner
        let b = 2
        // endregion
        // endregion
        """)
        let config = KajiLanguageConfiguration(
            comments: nil,
            brackets: [],
            autoClosingPairs: [],
            surroundingPairs: [],
            indentationRules: nil,
            folding: LanguageFoldingRules(markers: .init(start: #"//\s*region"#, end: #"//\s*endregion"#))
        )

        let regions = LanguageFoldingRegionParser.regions(in: store, configuration: config)

        #expect(regions == [
            EditorFoldRegion(startLine: 2, endLine: 4),
            EditorFoldRegion(startLine: 0, endLine: 5),
        ])
    }

    @Test("missing folding configuration returns no regions")
    func missingConfiguration() {
        let store = TextBackingStore()
        store.loadFromText("// region\n// endregion")

        #expect(LanguageFoldingRegionParser.regions(in: store, configuration: nil).isEmpty)
    }
}
