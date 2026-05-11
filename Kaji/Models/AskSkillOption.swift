import Foundation

struct AskSkillOption: Hashable, Identifiable {
    let name: String
    let title: String
    let detail: String
    let path: String
    let source: String

    var id: String {
        path
    }
}
