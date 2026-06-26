import Foundation

struct GitHubAccountService {
    func accounts(repoPath: String) async -> [GitHubAccount] {
        guard let ghPath = GitProcessRunner.resolveExecutable("gh") else { return [] }
        let host = await remoteHost(repoPath: repoPath) ?? "github.com"
        let result = try? await GitProcessRunner.runCommand(
            executable: ghPath,
            arguments: ["auth", "status", "--json", "hosts", "--hostname", host],
            workingDirectory: repoPath
        )
        guard let output = result?.stdout, !output.isEmpty else { return [] }
        return GitHubAccountParser.parseStatus(output, preferredHost: host)
    }

    private func remoteHost(repoPath: String) async -> String? {
        let result = try? await GitProcessRunner.runGit(
            repoPath: repoPath,
            arguments: ["remote", "get-url", "origin"]
        )
        guard let url = result?.stdout else { return nil }
        return GitHubRemoteURLParser.host(from: url)
    }
}
