import AppKit
import Foundation

@MainActor
final class FileIconImageCache {
    static let shared = FileIconImageCache()

    private let cache = NSCache<NSString, NSImage>()

    func image(for icon: FileIcon) -> NSImage? {
        let key = icon.relativePath as NSString
        if let image = cache.object(forKey: key) {
            return image
        }

        guard let url = resourceURL(for: icon.relativePath), let image = NSImage(contentsOf: url) else {
            return nil
        }

        cache.setObject(image, forKey: key)
        return image
    }

    func hasImage(for icon: FileIcon) -> Bool {
        resourceURL(for: icon.relativePath) != nil
    }

    private func resourceURL(for relativePath: String) -> URL? {
        let cleanPath = relativePath
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty && $0 != "." && $0 != ".." }
            .joined(separator: "/")
        guard !cleanPath.isEmpty else { return nil }

        let subpath = "FileIcons/MaterialIconTheme/\(cleanPath)"
        let candidates = [
            Bundle.appResources.resourceURL?.appendingPathComponent(subpath),
            Bundle.main.resourceURL?.appendingPathComponent(subpath),
        ]

        for case let url? in candidates where FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        return nil
    }
}
