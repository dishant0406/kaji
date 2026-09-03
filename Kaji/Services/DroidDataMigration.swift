import Foundation

enum DroidDataMigration {
    private static let markerName = ".droid-migration-complete"
    private static let defaultsMarkerKey = "kaji.migration.droidDefaultsImported"

    static func run() {
        guard ProcessInfo.processInfo.environment["KAJI_DISABLE_DROID_MIGRATION"] != "1" else { return }
        migrateApplicationSupport()
        migrateDefaults()
    }

    private static func migrateApplicationSupport(fileManager: FileManager = .default) {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let source = appSupport.appendingPathComponent("Droid", isDirectory: true)
        let target = appSupport.appendingPathComponent("Kaji", isDirectory: true)
        let marker = target.appendingPathComponent(markerName)
        guard fileManager.fileExists(atPath: source.path) else { return }
        guard !fileManager.fileExists(atPath: marker.path) else { return }
        guard targetIsFresh(target, fileManager: fileManager) else { return }

        try? fileManager.removeItem(at: target)
        try? fileManager.createDirectory(at: target, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        copyTree(from: source, to: target, fileManager: fileManager)
        rewriteTextFiles(in: target, fileManager: fileManager)
        fileManager.createFile(atPath: marker.path, contents: Data(), attributes: [.posixPermissions: 0o600])
    }

    private static func targetIsFresh(_ target: URL, fileManager: FileManager) -> Bool {
        guard fileManager.fileExists(atPath: target.path) else { return true }
        let projectsURL = target.appendingPathComponent("projects.json")
        guard let data = try? Data(contentsOf: projectsURL), !data.isEmpty else { return true }
        guard let value = try? JSONSerialization.jsonObject(with: data) else { return true }
        if let projects = value as? [Any] {
            return projects.isEmpty
        }
        return false
    }

    private static func copyTree(from source: URL, to target: URL, fileManager: FileManager) {
        guard let enumerator = fileManager.enumerator(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )
        else { return }

        for case let sourceURL as URL in enumerator {
            let relativePath = sourceURL.path.replacingOccurrences(of: source.path + "/", with: "")
            if shouldSkip(relativePath) {
                if (try? sourceURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    enumerator.skipDescendants()
                }
                continue
            }

            let mappedPath = DroidDataMigrationMapper.mappedPath(relativePath)
            let targetURL = target.appendingPathComponent(mappedPath)
            let isDirectory = (try? sourceURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if isDirectory {
                try? fileManager.createDirectory(
                    at: targetURL,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
                continue
            }

            try? fileManager.createDirectory(
                at: targetURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try? fileManager.copyItem(at: sourceURL, to: targetURL)
        }
    }

    private static func shouldSkip(_ relativePath: String) -> Bool {
        let name = URL(fileURLWithPath: relativePath).lastPathComponent
        return name.hasSuffix(".sock") || name == "LOCK" || name.hasPrefix("Singleton")
    }

    private static func rewriteTextFiles(in root: URL, fileManager: FileManager) {
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) else { return }
        for case let url as URL in enumerator {
            guard shouldRewrite(url) else { continue }
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]), (values.fileSize ?? 0) < 5_000_000 else {
                continue
            }
            guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else { continue }
            let mapped = DroidDataMigrationMapper.mappedString(text)
            guard mapped != text else { continue }
            guard let mappedData = mapped.data(using: .utf8) else { continue }
            try? mappedData.write(to: url, options: .atomic)
        }
    }

    private static func shouldRewrite(_ url: URL) -> Bool {
        let names = ["Preferences", "Local State", "Secure Preferences"]
        let extensions = ["json", "conf", "md", "txt", "plist"]
        return names.contains(url.lastPathComponent) || extensions.contains(url.pathExtension.lowercased())
    }

    private static func migrateDefaults() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: defaultsMarkerKey) else { return }
        let oldDomains = ["com.droid.app", "com.droid.dev", "app.droid.dev", "com.droid.swift-run", "Droid"]
        var migrated = false
        for domainName in oldDomains {
            guard let domain = defaults.persistentDomain(forName: domainName) else { continue }
            for (key, value) in domain {
                defaults.set(DroidDataMigrationMapper.mappedValue(value), forKey: DroidDataMigrationMapper.mappedString(key))
            }
            migrated = true
        }
        if migrated {
            defaults.set(true, forKey: defaultsMarkerKey)
        }
    }
}

enum DroidDataMigrationMapper {
    static func mappedPath(_ path: String) -> String {
        path
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { mappedString(String($0)) }
            .joined(separator: "/")
    }

    static func mappedString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "DROID", with: "KAJI")
            .replacingOccurrences(of: "Droid", with: "Kaji")
            .replacingOccurrences(of: ".droid", with: ".kaji")
            .replacingOccurrences(of: "/droid", with: "/kaji")
            .replacingOccurrences(of: "droid-", with: "kaji-")
            .replacingOccurrences(of: "droid_", with: "kaji_")
            .replacingOccurrences(of: "droid.", with: "kaji.")
    }

    static func mappedValue(_ value: Any) -> Any {
        if let string = value as? String {
            return mappedString(string)
        }
        if let array = value as? [Any] {
            return array.map(mappedValue)
        }
        if let dictionary = value as? [String: Any] {
            return dictionary.reduce(into: [String: Any]()) { result, pair in
                result[mappedString(pair.key)] = mappedValue(pair.value)
            }
        }
        return value
    }
}
