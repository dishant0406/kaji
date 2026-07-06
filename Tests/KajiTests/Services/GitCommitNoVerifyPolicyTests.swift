import Testing

@testable import Kaji

struct GitCommitNoVerifyPolicyTests {
    @Test
    func insertsNoVerifyForCommit() {
        let arguments = GitCommitNoVerifyPolicy.normalized(["commit", "-m", "hello"])

        #expect(arguments == ["commit", "--no-verify", "-m", "hello"])
    }

    @Test
    func keepsSingleNoVerifyForCommit() {
        let arguments = GitCommitNoVerifyPolicy.normalized(["commit", "--no-verify", "-m", "hello"])

        #expect(arguments == ["commit", "--no-verify", "-m", "hello"])
    }

    @Test
    func replacesVerifyForCommit() {
        let arguments = GitCommitNoVerifyPolicy.normalized(["commit", "--verify", "-m", "hello"])

        #expect(arguments == ["commit", "--no-verify", "-m", "hello"])
    }

    @Test
    func preservesPathspecsAfterSeparator() {
        let arguments = GitCommitNoVerifyPolicy.normalized(["commit", "-m", "hello", "--", "--verify", "--no-verify"])

        #expect(arguments == ["commit", "--no-verify", "-m", "hello", "--", "--verify", "--no-verify"])
    }

    @Test
    func leavesNonCommitCommandsUnchanged() {
        let arguments = GitCommitNoVerifyPolicy.normalized(["status", "--short"])

        #expect(arguments == ["status", "--short"])
    }
}
