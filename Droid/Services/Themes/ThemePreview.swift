import Foundation

struct ThemePreview: Identifiable, Equatable, Sendable {
    enum Source: String, Sendable {
        case bundled
        case external
    }

    let identifier: String
    let name: String
    let source: Source
    let draft: ThemeDraft
    let content: String

    var id: String { identifier }

    var sourceLabel: String {
        source == .bundled ? "Bundled" : "Custom"
    }
}
