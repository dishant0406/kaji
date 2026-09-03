import Foundation

extension BrowserWebController {
    func waitUntilReady(timeout: Duration = .seconds(10)) async throws -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if try await pageIsReady() {
                return true
            }
            try await Task.sleep(for: .milliseconds(150))
        }
        return false
    }

    private func pageIsReady() async throws -> Bool {
        guard let browserView else { return false }
        if browserView.isLoading {
            return false
        }
        let readyState = try await string(script: "document.readyState")
        return readyState == "complete" || readyState == "interactive"
    }
}
