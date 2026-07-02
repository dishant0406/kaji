import Foundation
import Testing

@testable import Kaji

struct TerminalSettingsStoreTests {
    @Test
    @MainActor
    func migratesMissingTerminalFontToBundledPromptFont() {
        let suiteName = "TerminalSettingsStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Could not create user defaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = TerminalSettingsStore(defaults: defaults)

        #expect(store.fontFamily == TerminalBundledFont.familyName)
        #expect(defaults.string(forKey: "kaji.terminal.fontFamily") == TerminalBundledFont.familyName)
    }

    @Test
    @MainActor
    func migratesLegacySFMonoTerminalFontToBundledPromptFontOnce() {
        let suiteName = "TerminalSettingsStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Could not create user defaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(TerminalBundledFont.legacyDefaultFamily, forKey: "kaji.terminal.fontFamily")

        let migrated = TerminalSettingsStore(defaults: defaults)
        #expect(migrated.fontFamily == TerminalBundledFont.familyName)
        #expect(defaults.string(forKey: "kaji.terminal.fontFamily") == TerminalBundledFont.familyName)

        defaults.set(TerminalBundledFont.legacyDefaultFamily, forKey: "kaji.terminal.fontFamily")

        let userSelectedLegacy = TerminalSettingsStore(defaults: defaults)
        #expect(userSelectedLegacy.fontFamily == TerminalBundledFont.legacyDefaultFamily)
    }

    @Test
    @MainActor
    func preservesCustomTerminalFontDuringMigration() {
        let suiteName = "TerminalSettingsStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Could not create user defaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("Menlo", forKey: "kaji.terminal.fontFamily")

        let store = TerminalSettingsStore(defaults: defaults)

        #expect(store.fontFamily == "Menlo")
    }
}
