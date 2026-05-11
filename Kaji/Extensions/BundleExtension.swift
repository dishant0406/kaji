import Foundation

extension Bundle {
    static let appResources: Bundle = {
        let bundleName = "Kaji_Kaji.bundle"

        let candidates: [URL?] = [
            Bundle.main.resourceURL?.appendingPathComponent(bundleName),
            Bundle.main.bundleURL.appendingPathComponent(bundleName),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/\(bundleName)"),
        ]

        for case let url? in candidates {
            if let bundle = Bundle(url: url) {
                return bundle
            }
        }

        return Bundle.main
    }()

    static var providerIconsURL: URL? {
        var candidates: [URL] = []

        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent("ProviderIcons"))
        }
        candidates.append(contentsOf: [
            Bundle.main.bundleURL.appendingPathComponent("ProviderIcons"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/ProviderIcons"),
        ])

        for candidate in candidates {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
               isDirectory.boolValue
            {
                return candidate
            }
        }

        return nil
    }

    static func hugeIconResourceURL(forResource name: String, withExtension ext: String) -> URL? {
        if let url = appResources.url(forResource: name, withExtension: ext, subdirectory: "HugeIcons") {
            return url
        }
        return appResources.url(forResource: name, withExtension: ext)
    }
}
