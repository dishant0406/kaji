import Foundation

enum ProjectLifecyclePreferences {
    static let keepOpenWhenNoTabsKey = "droid.projects.keepOpenWhenNoTabs"

    static var keepOpenWhenNoTabs: Bool {
        get {
            if let value = UserDefaults.standard.object(forKey: keepOpenWhenNoTabsKey) as? Bool {
                return value
            }
            return true
        }
        set { UserDefaults.standard.set(newValue, forKey: keepOpenWhenNoTabsKey) }
    }
}
