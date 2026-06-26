import Testing

@testable import Kaji

struct GitHubAccountParserTests {
    @Test
    func parsesAccountsForPreferredHostWithActiveFirst() {
        let accounts = GitHubAccountParser.parseStatus(
            """
            {
              "hosts": {
                "github.com": [
                  {
                    "state": "success",
                    "active": false,
                    "host": "github.com",
                    "login": "work",
                    "tokenSource": "oauth",
                    "gitProtocol": "ssh"
                  },
                  {
                    "state": "success",
                    "active": true,
                    "host": "github.com",
                    "login": "personal",
                    "tokenSource": "oauth",
                    "gitProtocol": "https"
                  }
                ],
                "enterprise.internal": [
                  {
                    "state": "Logged in",
                    "active": true,
                    "host": "enterprise.internal",
                    "login": "enterprise",
                    "tokenSource": "oauth",
                    "gitProtocol": "ssh"
                  }
                ]
              }
            }
            """,
            preferredHost: "github.com"
        )

        #expect(accounts.map(\.login) == ["personal", "work"])
        #expect(accounts.allSatisfy { $0.host == "github.com" })
    }

    @Test
    func ignoresUnusableAccounts() {
        let accounts = GitHubAccountParser.parseStatus(
            """
            {
              "hosts": {
                "github.com": [
                  {"state": "Failed to log in", "active": false, "login": "broken"},
                  {"state": "Logged in", "active": true, "login": "ready"}
                ]
              }
            }
            """
        )

        #expect(accounts.map(\.login) == ["ready"])
    }

    @Test
    func parsesRemoteHosts() {
        #expect(GitHubRemoteURLParser.host(from: "git@github.com:owner/repo.git") == "github.com")
        #expect(GitHubRemoteURLParser.host(from: "https://github.company.com/owner/repo.git") == "github.company.com")
        #expect(GitHubRemoteURLParser.host(from: "ssh://git@enterprise.internal/owner/repo.git") == "enterprise.internal")
    }

    @Test
    func createPullRequestRouteDoesNotParticipateInGlobalModalAnimation() {
        #expect(KajiModalRoute.createPullRequest.animatedID == nil)
    }
}
