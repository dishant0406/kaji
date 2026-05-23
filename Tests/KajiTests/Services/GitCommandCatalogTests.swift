import Testing

@testable import Kaji

struct GitCommandCatalogTests {
    @Test
    func logAutoPreviewsAsCommitHistory() {
        let request = GitCommandParser.request(command: .git, input: "log --oneline")
        let descriptor = GitCommandCatalog.descriptor(for: request.arguments)

        #expect(descriptor.autoPreviews)
        #expect(descriptor.presentation == .commitLog)
    }

    @Test
    func branchListAutoPreviewsButBranchCreateDoesNot() {
        let list = GitCommandCatalog.descriptor(for: ["branch", "--list"])
        let create = GitCommandCatalog.descriptor(for: ["branch", "feature/test"])

        #expect(list.autoPreviews)
        #expect(list.presentation == .branchList)
        #expect(!create.autoPreviews)
        #expect(create.effect == .mutating)
    }

    @Test
    func stashListAutoPreviewsButStashPushDoesNot() {
        let list = GitCommandCatalog.descriptor(for: ["stash", "list"])
        let push = GitCommandCatalog.descriptor(for: ["stash"])

        #expect(list.autoPreviews)
        #expect(push.effect == .mutating)
        #expect(!push.autoPreviews)
    }
}
