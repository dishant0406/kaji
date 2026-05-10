import Foundation

enum BrowserExtensionPreferences {
    static let enabledKey = "droid.browser.extensionEnabled"
    static let unsafeToolsEnabledKey = "droid.browser.allowUnsafeTools"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var allowsUnsafeTools: Bool {
        get { UserDefaults.standard.bool(forKey: unsafeToolsEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: unsafeToolsEnabledKey) }
    }
}
