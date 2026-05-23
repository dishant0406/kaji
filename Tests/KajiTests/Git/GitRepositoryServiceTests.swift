import Testing

@testable import Kaji

struct GitRepositoryServiceTests {
    @Test
    func normalizedBranchNameTrimsValidNames() {
        #expect(GitRepositoryService.normalizedBranchName(" feature/top-bar ") == "feature/top-bar")
    }

    @Test
    func normalizedBranchNameRejectsInvalidNames() {
        #expect(GitRepositoryService.normalizedBranchName("-feature") == nil)
        #expect(GitRepositoryService.normalizedBranchName("feature branch") == nil)
        #expect(GitRepositoryService.normalizedBranchName("") == nil)
    }
}
