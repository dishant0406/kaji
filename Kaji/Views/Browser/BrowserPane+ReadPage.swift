import SwiftUI

extension BrowserPane {
    func readPage() async {
        isReading = true
        withAnimation(KajiMotion.preferred(KajiMotion.panel, reduceMotion: reduceMotion)) {
            showsPageText = true
        }
        defer { isReading = false }
        do {
            state.pageSummary = try await selectedController?.readPage() ?? ""
        } catch {
            state.pageSummary = error.localizedDescription
        }
    }
}
