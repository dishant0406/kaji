import Foundation
import Testing

@testable import Kaji

@Suite("GitCommitMessageSettingsStore")
struct GitCommitMessageSettingsStoreTests {
    @MainActor
    @Test("defaults to fast context and empty instructions")
    func defaults() {
        let suiteName = "GitCommitMessageSettingsStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = GitCommitMessageSettingsStore(defaults: defaults)

        #expect(store.selectedContextLevel == .fast)
        #expect(store.customInstructions.isEmpty)
        #expect(store.snapshot().contextLevel == .fast)
    }

    @MainActor
    @Test("persists context and instructions")
    func persistence() {
        let suiteName = "GitCommitMessageSettingsStoreTests.Persistence.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = GitCommitMessageSettingsStore(defaults: defaults)
        store.contextLevel = GitCommitMessageContextLevel.detailed.rawValue
        store.customInstructions = "Use conventional commits."

        let reloaded = GitCommitMessageSettingsStore(defaults: defaults)

        #expect(reloaded.selectedContextLevel == .detailed)
        #expect(reloaded.customInstructions == "Use conventional commits.")
    }

    @Test("context levels map to snippet policies")
    func contextPolicies() {
        #expect(GitCommitMessageContextLevel.fast.snippetPolicy == nil)
        #expect(GitCommitMessageContextLevel.medium.snippetPolicy?.maxFiles == 4)
        #expect(GitCommitMessageContextLevel.detailed.snippetPolicy?.contextLineCount == 3)
    }
}
