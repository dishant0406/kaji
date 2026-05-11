import Foundation

enum ChromeIconButtonStylePolicy {
    static func borderOpacity(active: Bool, isTahoe: Bool) -> Double {
        guard active, !isTahoe else { return 0 }
        return 1
    }
}
