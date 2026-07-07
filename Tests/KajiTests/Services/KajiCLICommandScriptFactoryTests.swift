import Testing

@testable import Kaji

@Suite("Kaji CLI command script")
struct KajiCLICommandScriptFactoryTests {
    @Test("script opens current directory by default through kaji URL")
    func scriptOpensCurrentDirectoryByDefault() {
        let script = KajiCLICommandScriptFactory.script()

        #expect(script.hasPrefix("#!/bin/sh"))
        #expect(script.contains("target=\"${1:-.}\""))
        #expect(script.contains("pwd -P"))
        #expect(script.contains("tr '+/' '-_'"))
        #expect(script.contains("open \"kaji://open-project/$payload\""))
        #expect(!script.contains("python"))
    }

    @Test("script rejects multiple paths")
    func scriptRejectsMultiplePaths() {
        let script = KajiCLICommandScriptFactory.script()

        #expect(script.contains("expected zero or one path argument"))
        #expect(script.contains("exit 64"))
    }
}
