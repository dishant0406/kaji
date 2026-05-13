import Testing

@testable import Kaji

@Suite("EditorSymbolParser")
@MainActor
struct EditorSymbolParserTests {
    @Test("Swift symbols include types functions and properties")
    func swiftSymbols() {
        let store = TextBackingStore()
        store.loadFromText("""
        final class Runner {
            static let shared = Runner()
            func start() {}
        }
        """)

        let symbols = EditorSymbolParser.symbols(in: store, languageID: "swift")

        #expect(symbols.map(\.name) == ["Runner", "shared", "start"])
        #expect(symbols.map(\.kind) == [.type, .property, .function])
        #expect(symbols.map(\.line) == [0, 1, 2])
    }

    @Test("Common parser finds markdown sections and JavaScript functions")
    func commonSymbols() {
        let store = TextBackingStore()
        store.loadFromText("""
        # Intro
        export function boot() {}
        const run = () => {}
        """)

        let symbols = EditorSymbolParser.symbols(in: store, languageID: nil)

        #expect(symbols.map(\.name) == ["Intro", "boot", "run"])
        #expect(symbols.map(\.kind) == [.section, .function, .function])
    }
}
