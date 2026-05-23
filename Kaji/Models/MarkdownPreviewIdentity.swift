import Foundation

enum MarkdownPreviewIdentity {
    static func editor(tabID: UUID, mode: EditorMarkdownViewMode) -> String {
        "\(tabID.uuidString)-\(mode.rawValue)"
    }
}
