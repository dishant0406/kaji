import Foundation

struct AskSessionOption: Identifiable, Hashable {
    let projectID: UUID
    let worktreeID: UUID
    let areaID: UUID
    let tabID: UUID
    let paneID: UUID
    let title: String
    let provider: AskProvider
    let worktreeName: String

    var id: UUID { paneID }

    var providerTitle: String {
        provider.title
    }
}
