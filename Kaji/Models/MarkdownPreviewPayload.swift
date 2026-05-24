import CoreGraphics
import Foundation

struct MarkdownPreviewPayload: Codable, Equatable {
    let content: String
    let baseURL: String?
    let allowedRootURL: String?
    let allowRemoteImages: Bool
    let anchors: [MarkdownSyncAnchor]
    let theme: MarkdownPreviewTheme
    let typography: MarkdownPreviewTypography
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

struct MarkdownPreviewTypography: Codable, Equatable {
    let fontFamily: String
    let fontSize: CGFloat
    let lineHeight: CGFloat
}

struct MarkdownPreviewMetrics: Codable, Equatable {
    let geometries: [MarkdownPreviewAnchorGeometry]
    let maxScrollTop: CGFloat
    let viewportHeight: CGFloat
}
