import Foundation
import WebKit

@MainActor
final class KajiBrowserDownloadDelegate: NSObject, WKDownloadDelegate {
    private var active: Set<ObjectIdentifier> = []
    var didChangeActivity: ((Bool) -> Void)?

    var isActive: Bool { !active.isEmpty }

    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping @MainActor @Sendable (URL?) -> Void
    ) {
        active.insert(ObjectIdentifier(download))
        didChangeActivity?(true)
        let directory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        completionHandler(uniqueURL(directory: directory, filename: suggestedFilename))
    }

    func downloadDidFinish(_ download: WKDownload) {
        active.remove(ObjectIdentifier(download))
        didChangeActivity?(isActive)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        active.remove(ObjectIdentifier(download))
        didChangeActivity?(isActive)
    }

    private func uniqueURL(directory: URL, filename: String) -> URL {
        let safeName = filename.isEmpty ? "download" : filename
        var candidate = directory.appendingPathComponent(safeName)
        let ext = candidate.pathExtension
        let base = candidate.deletingPathExtension().lastPathComponent
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(base)-\(index)" : "\(base)-\(index).\(ext)"
            candidate = directory.appendingPathComponent(name)
            index += 1
        }
        return candidate
    }
}
