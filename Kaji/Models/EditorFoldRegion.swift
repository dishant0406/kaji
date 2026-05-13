import Foundation

struct EditorFoldRegion: Identifiable, Equatable {
    let startLine: Int
    let endLine: Int

    var id: String { "\(startLine):\(endLine)" }
}
