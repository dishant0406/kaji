import Foundation

enum SpeechModelDownloadError: LocalizedError, Equatable {
    case invalidURL(String)
    case invalidResponse(String)
    case httpStatus(Int, String)
    case noFiles(String)
    case missingRequiredFile(String)
    case unsafePath(String)
    case downloadLimitExceeded

    var errorDescription: String? {
        switch self {
        case let .invalidURL(url):
            "Invalid speech model download URL: \(url)"
        case let .invalidResponse(path):
            "Speech model registry returned an invalid response for \(path)."
        case let .httpStatus(status, path):
            "Speech model download failed with HTTP \(status) for \(path)."
        case let .noFiles(modelID):
            "No downloadable files were found for speech model \(modelID)."
        case let .missingRequiredFile(file):
            "Speech model download is missing required file \(file)."
        case let .unsafePath(path):
            "Speech model registry returned an unsafe path: \(path)."
        case .downloadLimitExceeded:
            "Speech model download exceeded the allowed size or file count."
        }
    }
}
