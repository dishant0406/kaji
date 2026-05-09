import Foundation

@MainActor
@Observable
final class BrowserPageState: Identifiable {
    let id: UUID
    var url: String
    var title: String
    var pageSummary: String

    init(id: UUID = UUID(), url: String = BrowserPaneState.defaultURL, title: String = "Browser", pageSummary: String = "") {
        self.id = id
        self.url = url
        self.title = title
        self.pageSummary = pageSummary
    }
}
