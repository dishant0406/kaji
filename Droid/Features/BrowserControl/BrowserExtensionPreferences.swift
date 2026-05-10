import Foundation

enum BrowserExtensionPreferences {
    static let enabledKey = "droid.browser.extensionEnabled"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }
}
