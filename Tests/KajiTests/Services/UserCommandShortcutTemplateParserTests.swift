import Testing

@testable import Kaji

struct UserCommandShortcutTemplateParserTests {
    @Test
    func parsesNamedPositionalAndComputedVariables() throws {
        let named = try #require(UserCommandShortcutTemplateParser.parse("git push origin {branchName}").template)
        let positional = try #require(UserCommandShortcutTemplateParser.parse("git push {1} {2}").template)
        let computed = try #require(UserCommandShortcutTemplateParser.parse("git push origin {~git branch --show-current~}").template)

        #expect(named.inputVariables.map(\.displayName) == ["branchName"])
        #expect(positional.inputVariables.map(\.displayName) == ["1", "2"])
        #expect(computed.computedVariables.map(\.command) == ["git branch --show-current"])
    }

    @Test
    func deduplicatesRepeatedInputVariables() throws {
        let template = try #require(UserCommandShortcutTemplateParser.parse("echo {name} {name}").template)

        #expect(template.inputVariables.map(\.displayName) == ["name"])
    }

    @Test
    func rejectsInvalidTemplates() {
        #expect(UserCommandShortcutTemplateParser.parse("echo {branch-name}").errors.contains(.invalidVariableName("branch-name")))
        #expect(UserCommandShortcutTemplateParser.parse("echo {}").errors.contains(.emptyPlaceholder))
        #expect(UserCommandShortcutTemplateParser.parse("echo {name").errors.contains(.unclosedPlaceholder))
        #expect(UserCommandShortcutTemplateParser.parse("echo {~ ~}").errors.contains(.emptyComputedCommand))
        #expect(UserCommandShortcutTemplateParser.parse("echo {name} {1}").errors.contains(.mixedVariableStyles))
    }
}
