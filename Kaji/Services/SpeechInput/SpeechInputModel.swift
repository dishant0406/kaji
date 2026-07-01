import Foundation

struct SpeechInputModel: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let title: String
    let detail: String
    let engine: SpeechModelEngine
    let registryBaseURL: String
    let repo: String
    let revision: String
    let subPath: String?
    let cachePath: String
    let chunkSize: SpeechModelChunkSize?
    let estimatedDownloadSize: String
    let recommended: Bool
    let requiredFiles: [String]
    let downloadBytes: Int64?
    let mode: SpeechModelMode?
    let languageSummary: String?
    let badges: [String]?
    let pros: [String]?
    let cons: [String]?
    let runtime: SpeechModelRuntimeConfig?

    init(
        id: String,
        title: String,
        detail: String,
        engine: SpeechModelEngine,
        registryBaseURL: String,
        repo: String,
        revision: String,
        subPath: String? = nil,
        cachePath: String,
        chunkSize: SpeechModelChunkSize? = nil,
        estimatedDownloadSize: String,
        recommended: Bool,
        requiredFiles: [String],
        downloadBytes: Int64? = nil,
        mode: SpeechModelMode? = nil,
        languageSummary: String? = nil,
        badges: [String]? = nil,
        pros: [String]? = nil,
        cons: [String]? = nil,
        runtime: SpeechModelRuntimeConfig? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.engine = engine
        self.registryBaseURL = registryBaseURL
        self.repo = repo
        self.revision = revision
        self.subPath = subPath
        self.cachePath = cachePath
        self.chunkSize = chunkSize
        self.estimatedDownloadSize = estimatedDownloadSize
        self.recommended = recommended
        self.requiredFiles = requiredFiles
        self.downloadBytes = downloadBytes
        self.mode = mode
        self.languageSummary = languageSummary
        self.badges = badges
        self.pros = pros
        self.cons = cons
        self.runtime = runtime
    }

    var cacheURL: URL {
        SpeechModelCacheRoot.url.appendingPathComponent(cachePath, isDirectory: true)
    }

    var isCached: Bool {
        requiredFiles.allSatisfy { file in
            FileManager.default.fileExists(atPath: cacheURL.appendingPathComponent(file).path)
        }
    }

    var downloadSizeTitle: String {
        guard let downloadBytes else { return estimatedDownloadSize }
        let mib = Double(downloadBytes) / 1_048_576
        return String(format: "%.2f MiB", mib)
    }

    var exactDownloadSizeTitle: String {
        guard let downloadBytes else { return estimatedDownloadSize }
        return "\(downloadSizeTitle) · \(downloadBytes.formatted()) bytes"
    }

    var displayMode: SpeechModelMode {
        mode ?? (engine == .fluidAudioParakeetEouStreaming ? .liveStreaming : .releaseTranscription)
    }

    var displayLanguageSummary: String {
        languageSummary ?? "English"
    }

    static let defaultID = "parakeet-eou-320ms"
}

enum SpeechModelEngine: String, Codable, Equatable, Hashable {
    case fluidAudioParakeetEouStreaming = "fluidAudio.parakeetEouStreaming"
    case fluidAudioParakeetTdt = "fluidAudio.parakeetTdt"
}

enum SpeechModelChunkSize: String, Codable, Equatable, Hashable {
    case ms160
    case ms320
    case ms1280
}

enum SpeechModelCacheRoot {
    static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }
}
