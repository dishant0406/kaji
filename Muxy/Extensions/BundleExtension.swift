import Foundation

extension Bundle {
    static let appResources: Bundle = {
        let bundleName = "Muxy_Muxy"

        let candidates = [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL,
        ]

        for candidate in candidates {
            guard let candidate else { continue }
            let path = candidate.appendingPathComponent(bundleName + ".bundle")
            if let bundle = Bundle(path: path.path) {
                return bundle
            }
        }

        return .module
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
}
