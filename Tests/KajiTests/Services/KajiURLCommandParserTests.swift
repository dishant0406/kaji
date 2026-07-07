import Foundation
import Testing

@testable import Kaji

@Suite("Kaji URL command parser")
struct KajiURLCommandParserTests {
    @Test("parses open project URL with base64url path")
    func parsesOpenProjectURL() throws {
        let path = "/Users/test/My Project"
        let payload = KajiURLCommandParser.encodePath(path)
        let url = try #require(URL(string: "kaji://open-project/\(payload)"))

        #expect(KajiURLCommandParser.parse(url) == .openProject(path: path))
    }

    @Test("rejects unknown URLs")
    func rejectsUnknownURLs() throws {
        let payload = KajiURLCommandParser.encodePath("/tmp/app")

        #expect(KajiURLCommandParser.parse(try #require(URL(string: "https://open-project/\(payload)"))) == nil)
        #expect(KajiURLCommandParser.parse(try #require(URL(string: "kaji://unknown/\(payload)"))) == nil)
        #expect(KajiURLCommandParser.parse(try #require(URL(string: "kaji://open-project/a/b"))) == nil)
        #expect(KajiURLCommandParser.parse(try #require(URL(string: "kaji://open-project/a"))) == nil)
    }
}
