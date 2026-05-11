import Foundation

struct AskMentionOption: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case file
        case folder
    }

    let path: String
    let kind: Kind

    var id: String { "\(kind.rawValue):\(path)" }
    var title: String { URL(fileURLWithPath: path).lastPathComponent.isEmpty ? path : URL(fileURLWithPath: path).lastPathComponent }
    var detail: String { path }
}

struct AskActiveMention: Equatable {
    let range: Range<String.Index>
    let query: String
}
