import Foundation

enum SpeechModelCacheState: Equatable {
    case missing
    case partial
    case ready

    var isReady: Bool {
        self == .ready
    }

    var title: String {
        switch self {
        case .missing: "Not downloaded"
        case .partial: "Incomplete download"
        case .ready: "Downloaded"
        }
    }

    var statusColorIsReady: Bool {
        self == .ready
    }

    static func state(for model: SpeechInputModel) -> SpeechModelCacheState {
        state(requiredFiles: model.requiredFiles, baseURL: model.cacheURL) { url in
            FileManager.default.fileExists(atPath: url.path)
        }
    }

    static func state(
        requiredFiles: [String],
        baseURL: URL,
        fileExists: (URL) -> Bool
    ) -> SpeechModelCacheState {
        let existing = requiredFiles.filter { fileExists(baseURL.appendingPathComponent($0)) }
        if existing.count == requiredFiles.count {
            return .ready
        }
        guard fileExists(baseURL) || !existing.isEmpty else { return .missing }
        return .partial
    }
}

extension SpeechInputModel {
    var cacheState: SpeechModelCacheState {
        SpeechModelCacheState.state(for: self)
    }
}
