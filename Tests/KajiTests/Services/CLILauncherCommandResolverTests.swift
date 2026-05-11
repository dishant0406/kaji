import Foundation
import Testing
@testable import Kaji

struct CLILauncherCommandResolverTests {
    @Test
    func leavesUnknownCommandUnchanged() {
        #expect(CLILauncherCommandResolver.resolve("missing-agent --flag") == "missing-agent --flag")
    }

    @Test
    func preservesAbsoluteCommand() {
        #expect(CLILauncherCommandResolver.resolve("/usr/bin/env pi") == "/usr/bin/env pi")
    }
}
