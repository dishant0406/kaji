enum GitCommitNoVerifyPolicy {
    static func normalized(_ arguments: [String]) -> [String] {
        guard arguments.first == "commit" else { return arguments }

        let separatorIndex = arguments.firstIndex(of: "--") ?? arguments.endIndex
        let commitOptions = arguments[..<separatorIndex].filter { $0 != "--verify" && $0 != "--no-verify" }
        let pathspecs = arguments[separatorIndex...]
        return commitOptions.prefix(1) + ["--no-verify"] + commitOptions.dropFirst() + pathspecs
    }
}
