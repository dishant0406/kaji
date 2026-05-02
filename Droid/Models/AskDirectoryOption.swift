import Foundation

struct AskDirectoryOption: Identifiable, Hashable {
    let path: String

    var id: String { path }
    var title: String { URL(fileURLWithPath: path).lastPathComponent.isEmpty ? path : URL(fileURLWithPath: path).lastPathComponent }
    var detail: String { path }
}
