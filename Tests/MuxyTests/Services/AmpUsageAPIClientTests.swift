import Foundation
import Testing

@testable import Muxy

@Suite("AmpUsageProvider")
struct AmpUsageProviderTests {
    @Test("reads token from env")
    func readTokenFromEnv() throws {
        let token = try AmpUsageProvider.readToken(env: ["AMP_API_KEY": "amp_token"])
        #expect(token == "amp_token")
    }
}
