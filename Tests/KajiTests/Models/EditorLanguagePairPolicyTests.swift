import Testing

@testable import Kaji

@Suite("EditorLanguagePairPolicy")
struct EditorLanguagePairPolicyTests {
    @Test("falls back to default pairs when configuration is empty")
    func fallsBackToDefaultPairs() {
        let set = EditorLanguagePairPolicy.makePairSet(configuredPairs: [])

        #expect(set.pairs.contains(EditorLanguagePair(open: "(", close: ")")))
        #expect(set.openingPairs["(".utf16.first!] == ")".utf16.first!)
        #expect(set.closingPairs[")".utf16.first!] == "(".utf16.first!)
    }

    @Test("uses configured single character pairs")
    func usesConfiguredSingleCharacterPairs() {
        let set = EditorLanguagePairPolicy.makePairSet(configuredPairs: [["<", ">"], ["bad", "x"]])

        #expect(set.pairs == [EditorLanguagePair(open: "<", close: ">")])
        #expect(set.openingPairs["<".utf16.first!] == ">".utf16.first!)
        #expect(set.closingPairs[">".utf16.first!] == "<".utf16.first!)
    }
}
