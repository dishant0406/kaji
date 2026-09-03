import Testing
@testable import Kaji

struct DroidDataMigrationTests {
    @Test func mapsStorageNamesWithoutChangingAndroidWords() {
        let value = "/Users/me/.droid/bin/droid-browser/droid-tools.js android Droid DROID droid.activeProjectID"
        let mapped = DroidDataMigrationMapper.mappedString(value)

        #expect(mapped.contains("/Users/me/.kaji/bin/kaji-browser/kaji-tools.js"))
        #expect(mapped.contains("android"))
        #expect(mapped.contains("Kaji"))
        #expect(mapped.contains("KAJI"))
        #expect(mapped.contains("kaji.activeProjectID"))
    }

    @Test func mapsNestedDefaultsValues() {
        let value: [String: Any] = [
            "droid.activeWorktreeIDs": [
                "project": "/Users/me/.droid/extensions/droid-tools"
            ],
            "items": ["Droid", "DROID_BROWSER_TOKEN"]
        ]

        let mapped = DroidDataMigrationMapper.mappedValue(value) as? [String: Any]
        let worktrees = mapped?["kaji.activeWorktreeIDs"] as? [String: Any]
        let items = mapped?["items"] as? [String]

        #expect(worktrees?["project"] as? String == "/Users/me/.kaji/extensions/droid-tools")
        #expect(items == ["Kaji", "KAJI_BROWSER_TOKEN"])
    }
}
