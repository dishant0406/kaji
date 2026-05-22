import Foundation

extension Bundle {
    static let appResources: Bundle = {
        let bundleName = "Kaji_Kaji.bundle"

        var candidates: [URL?] = [
            Bundle.main.resourceURL?.appendingPathComponent(bundleName),
            Bundle.main.bundleURL.appendingPathComponent(bundleName),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/\(bundleName)"),
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(bundleName),
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent(bundleName),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Kaji/Resources", isDirectory: true),
        ]

        candidates.append(contentsOf: Bundle.allBundles.flatMap { bundle in
            [
                bundle.resourceURL?.appendingPathComponent(bundleName),
                bundle.bundleURL.appendingPathComponent(bundleName),
                bundle.bundleURL.deletingLastPathComponent().appendingPathComponent(bundleName),
            ]
        })

        var seen = Set<String>()

        for case let url? in candidates {
            guard seen.insert(url.path).inserted else { continue }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
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
