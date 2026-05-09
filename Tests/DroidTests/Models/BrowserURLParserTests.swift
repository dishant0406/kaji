import Foundation
import Testing

@testable import Droid

@Suite("BrowserURLParser")
struct BrowserURLParserTests {
    @Test("preserves about blank for child browser windows")
    func preservesAboutBlank() {
        #expect(BrowserURLParser.url(from: "about:blank")?.absoluteString == "about:blank")
    }

    @Test("adds https for bare domains")
    func addsHTTPSScheme() {
        #expect(BrowserURLParser.url(from: "example.com")?.absoluteString == "https://example.com")
    }
}
