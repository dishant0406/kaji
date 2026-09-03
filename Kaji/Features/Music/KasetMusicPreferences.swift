import Foundation

enum KasetMusicPreferences {
    static let enabledKey = "kaji.kasetMusic.enabled"
    static let showFooterIconKey = "kaji.kasetMusic.showFooterIcon"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var showsFooterIcon: Bool {
        get {
            if UserDefaults.standard.object(forKey: showFooterIconKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: showFooterIconKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: showFooterIconKey) }
    }
}
