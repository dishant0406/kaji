import Testing

@testable import Kaji

struct UserCommandShortcutParserTests {
    @Test
    func parsesDoubleColonShortcutState() {
        #expect(UserCommandShortcutParser.state(for: "::")?.slug == "")
        #expect(UserCommandShortcutParser.state(for: "::Run Tests")?.slug == "run")
        #expect(UserCommandShortcutParser.state(for: " ::runtests ")?.slug == "runtests")
        #expect(UserCommandShortcutParser.state(for: "::push origin main")?.arguments == ["origin", "main"])
        #expect(UserCommandShortcutParser.state(for: "::push \"feature branch\"")?.arguments == ["feature branch"])
    }

    @Test
    func ignoresBuiltInColonCommands() {
        #expect(UserCommandShortcutParser.state(for: ":git status") == nil)
        #expect(UserCommandShortcutParser.state(for: ":p:muxy") == nil)
        #expect(UserCommandShortcutParser.state(for: "/project") == nil)
    }
}
