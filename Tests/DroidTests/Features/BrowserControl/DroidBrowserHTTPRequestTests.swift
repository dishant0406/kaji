import Testing

@testable import Droid

struct DroidBrowserHTTPRequestTests {
    @Test
    func parsesMethodPathHeadersAndBody() throws {
        let request = try #require(DroidBrowserHTTPRequest(raw: [
            "POST /browser HTTP/1.1",
            "Authorization: Bearer token",
            "Content-Type: application/json",
            "",
            "{\"action\":\"current\"}",
        ].joined(separator: "\r\n")))

        #expect(request.method == "POST")
        #expect(request.path == "/browser")
        #expect(request.headers["authorization"] == "Bearer token")
        #expect(request.body == "{\"action\":\"current\"}")
    }
}
