import Foundation
import Testing

@testable import Kaji

@Suite("GitCommitMessageSettingsStore")
struct GitCommitMessageSettingsStoreTests {
    @MainActor
    @Test("defaults to commit role fallback, fast context, and empty instructions")
    func defaults() {
        let suiteName = "GitCommitMessageSettingsStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = GitCommitMessageSettingsStore(defaults: defaults)

        #expect(store.modelSelector.isEmpty)
        #expect(store.selectedModelLabel == "Kaji Agent commit role")
        #expect(store.selectedContextLevel == .fast)
        #expect(store.customInstructions.isEmpty)
        #expect(store.snapshot().providerID.isEmpty)
        #expect(store.snapshot().modelID.isEmpty)
        #expect(store.snapshot().modelLabel == "Kaji Agent commit role")
    }

    @MainActor
    @Test("persists model selector context and instructions")
    func persistence() {
        let suiteName = "GitCommitMessageSettingsStoreTests.Persistence.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = GitCommitMessageSettingsStore(defaults: defaults)
        store.modelSelector = "anthropic/claude-sonnet-4-5"
        store.contextLevel = GitCommitMessageContextLevel.detailed.rawValue
        store.customInstructions = "Use conventional commits."

        let reloaded = GitCommitMessageSettingsStore(defaults: defaults)

        #expect(reloaded.modelSelector == "anthropic/claude-sonnet-4-5")
        #expect(reloaded.selectedContextLevel == .detailed)
        #expect(reloaded.customInstructions == "Use conventional commits.")
        #expect(reloaded.snapshot().providerID == "anthropic")
        #expect(reloaded.snapshot().modelID == "claude-sonnet-4-5")
    }

    @MainActor
    @Test("migrates legacy provider and model keys")
    func migratesLegacySelection() {
        let suiteName = "GitCommitMessageSettingsStoreTests.Migration.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("openrouter", forKey: GitCommitMessageSettingsStore.providerIDKey)
        defaults.set("anthropic/claude-sonnet-4.5", forKey: GitCommitMessageSettingsStore.modelIDKey)

        let store = GitCommitMessageSettingsStore(defaults: defaults)

        #expect(store.modelSelector == "openrouter/anthropic/claude-sonnet-4.5")
        #expect(store.snapshot().providerID == "openrouter")
        #expect(store.snapshot().modelID == "anthropic/claude-sonnet-4.5")
    }

    @MainActor
    @Test("normalizes invalid selector values")
    func normalizesInvalidValues() {
        let suiteName = "GitCommitMessageSettingsStoreTests.Normalize.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("missing", forKey: GitCommitMessageSettingsStore.modelSelectorKey)

        let store = GitCommitMessageSettingsStore(defaults: defaults)
        #expect(store.modelSelector.isEmpty)

        store.modelSelector = "openrouter/anthropic/claude-sonnet-4.5:low"
        #expect(store.modelSelector == "openrouter/anthropic/claude-sonnet-4.5")
    }

    @Test("selection prefers current selector then commit role then first model")
    func selectionPreference() {
        let anthropic = KajiAgentModelOption(id: "anthropic/claude-sonnet-4-5", provider: "anthropic", modelID: "claude-sonnet-4-5", title: "anthropic / claude-sonnet-4-5")
        let openrouter = KajiAgentModelOption(id: "openrouter/anthropic/claude-sonnet-4.5", provider: "openrouter", modelID: "anthropic/claude-sonnet-4.5", title: "openrouter / anthropic/claude-sonnet-4.5")
        let role = KajiAgentModelRoleAssignment(json: .object([
            "role": .string("commit"),
            "name": .string("Commit"),
            "selector": .string("openrouter/anthropic/claude-sonnet-4.5:low"),
        ]))

        let selected = GitCommitMessageModelSelection.recommendedSelector(
            currentSelector: "missing/model",
            modelOptions: [anthropic, openrouter],
            modelRoles: [role].compactMap(\.self)
        )

        #expect(selected?.providerID == "openrouter")
        #expect(selected?.modelID == "anthropic/claude-sonnet-4.5")
    }

    @Test("context levels map to snippet policies")
    func contextPolicies() {
        #expect(GitCommitMessageContextLevel.fast.snippetPolicy == nil)
        #expect(GitCommitMessageContextLevel.medium.snippetPolicy?.maxFiles == 4)
        #expect(GitCommitMessageContextLevel.detailed.snippetPolicy?.contextLineCount == 3)
    }
}
