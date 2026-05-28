import Foundation

enum BrowserDeviceFamily: String, Codable, CaseIterable {
    case desktop
    case iOS
    case android
}

struct BrowserDeviceProfile: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let family: BrowserDeviceFamily
    let width: Int
    let height: Int
    let deviceScaleFactor: Double
    let userAgent: String
    let isMobile: Bool
    let hasTouch: Bool

    var viewportDescription: String {
        isDesktop ? "Responsive" : "\(width) x \(height)"
    }

    var isDesktop: Bool {
        family == .desktop
    }
}

enum BrowserDeviceProfiles {
    static let desktopID = "desktop"
    private static let mobileSafari = "Mozilla/5.0 (%@) AppleWebKit/605.1.15 " +
        "(KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    private static let androidChrome = "Mozilla/5.0 (%@) AppleWebKit/537.36 " +
        "(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36"

    static let all: [BrowserDeviceProfile] = [
        BrowserDeviceProfile(
            id: desktopID,
            title: "Desktop",
            family: .desktop,
            width: 0,
            height: 0,
            deviceScaleFactor: 1,
            userAgent: "",
            isMobile: false,
            hasTouch: false
        ),
        BrowserDeviceProfile(
            id: "iphone-15-pro",
            title: "iPhone 15 Pro",
            family: .iOS,
            width: 393,
            height: 852,
            deviceScaleFactor: 3,
            userAgent: String(format: mobileSafari, "iPhone; CPU iPhone OS 17_0 like Mac OS X"),
            isMobile: true,
            hasTouch: true
        ),
        BrowserDeviceProfile(
            id: "iphone-se",
            title: "iPhone SE",
            family: .iOS,
            width: 375,
            height: 667,
            deviceScaleFactor: 2,
            userAgent: String(format: mobileSafari, "iPhone; CPU iPhone OS 17_0 like Mac OS X"),
            isMobile: true,
            hasTouch: true
        ),
        BrowserDeviceProfile(
            id: "ipad-pro-11",
            title: "iPad Pro 11",
            family: .iOS,
            width: 834,
            height: 1194,
            deviceScaleFactor: 2,
            userAgent: String(format: mobileSafari, "iPad; CPU OS 17_0 like Mac OS X"),
            isMobile: true,
            hasTouch: true
        ),
        BrowserDeviceProfile(
            id: "pixel-8",
            title: "Pixel 8",
            family: .android,
            width: 412,
            height: 915,
            deviceScaleFactor: 2.625,
            userAgent: String(format: androidChrome, "Linux; Android 14; Pixel 8"),
            isMobile: true,
            hasTouch: true
        ),
        BrowserDeviceProfile(
            id: "galaxy-s24",
            title: "Galaxy S24",
            family: .android,
            width: 384,
            height: 854,
            deviceScaleFactor: 3,
            userAgent: String(format: androidChrome, "Linux; Android 14; SM-S921B"),
            isMobile: true,
            hasTouch: true
        ),
    ]

    static func profile(for id: String) -> BrowserDeviceProfile {
        all.first { $0.id == id } ?? all[0]
    }
}
