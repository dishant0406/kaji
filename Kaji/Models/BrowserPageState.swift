import Foundation

@MainActor
@Observable
final class BrowserPageState: Identifiable {
    let id: UUID
    var url: String
    var title: String
    private var storedPageSummary: String

    init(id: UUID = UUID(), url: String = BrowserPaneState.defaultURL, title: String = "Browser", pageSummary: String = "") {
        self.id = id
        self.url = url
        self.title = title
        self.storedPageSummary = Self.truncatedPageSummary(pageSummary)
    }

    var pageSummary: String {
        get { storedPageSummary }
        set { storedPageSummary = Self.truncatedPageSummary(newValue) }
    }

    private static func truncatedPageSummary(_ value: String) -> String {
        let maxLength = 120_000
        guard value.count > maxLength else { return value }
        return String(value.prefix(maxLength))
    }
}
