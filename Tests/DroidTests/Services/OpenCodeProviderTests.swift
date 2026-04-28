import Foundation
import Testing

@testable import Droid

struct OpenCodeProviderTests {
    @Test
    func pluginPathsIncludeCurrentAndLegacyDirectories() {
        let paths = OpenCodeProvider.pluginPaths(homeDirectory: "/tmp/home")

        #expect(paths == [
            "/tmp/home/.config/opencode/plugins/droid-notify.js",
            "/tmp/home/.opencode/plugins/droid-notify.js",
        ])
    }
}
