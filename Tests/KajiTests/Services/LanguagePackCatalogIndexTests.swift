import Foundation
import Testing

@testable import Kaji

@Suite("LanguagePackCatalogIndex")
struct LanguagePackCatalogIndexTests {
    @Test("resolves filenames and extensions without rescanning entries")
    func resolvesFilenamesAndExtensions() {
        let ruby = entry(id: "ruby", extensions: ["rb"], filenames: ["Gemfile"])
        let zig = entry(id: "zig", extensions: ["zig", "zon"], filenames: [])
        let index = LanguagePackCatalogIndex(entries: [ruby, zig])

        #expect(index.entry(forFile: "/tmp/Gemfile")?.id == "ruby")
        #expect(index.entry(forFile: "/tmp/app.RB")?.id == "ruby")
        #expect(index.entry(forFile: "/tmp/build.zon")?.id == "zig")
        #expect(index.entry(forFile: "/tmp/Makefile") == nil)
    }

    @Test("keeps first catalog entry for duplicate identifiers")
    func keepsFirstCatalogEntryForDuplicateIdentifiers() {
        let first = entry(id: "first", extensions: ["foo"], filenames: ["Toolfile"])
        let second = entry(id: "second", extensions: ["FOO"], filenames: ["toolfile"])
        let index = LanguagePackCatalogIndex(entries: [first, second])

        #expect(index.entry(forFile: "/tmp/a.foo")?.id == "first")
        #expect(index.entry(forFile: "/tmp/Toolfile")?.id == "first")
    }

    private func entry(
        id: String,
        extensions: [String],
        filenames: [String]
    ) -> LanguagePackCatalogEntry {
        LanguagePackCatalogEntry(
            id: id,
            name: id,
            extensions: extensions,
            filenames: filenames,
            manifestPath: "packs/\(id)/manifest.json",
            sha256: nil,
            version: "1.0.0"
        )
    }
}
