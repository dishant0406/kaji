import Foundation

struct MarkdownPreviewPayload: Codable, Equatable {
    let content: String
    let baseURL: String?
    let allowRemoteImages: Bool
    let anchors: [MarkdownSyncAnchor]
    let theme: MarkdownPreviewTheme
}

struct MarkdownPreviewTheme: Codable, Equatable {
    let bg: String
    let fg: String
    let muted: String
    let dim: String
    let surface: String
    let border: String
    let accent: String
    let soft: String
}
