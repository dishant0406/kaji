import Foundation

struct EditorSymbol: Identifiable, Equatable {
    enum Kind: String {
        case function
        case type
        case property
        case section
    }

    let name: String
    let kind: Kind
    let line: Int
    let column: Int

    var id: String { "\(kind.rawValue):\(line):\(column):\(name)" }
}
