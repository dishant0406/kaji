extension GitRepositoryService {
    static func commitArguments(message: String) -> [String] {
        GitCommitNoVerifyPolicy.normalized(["commit", "-m", message])
    }
}
