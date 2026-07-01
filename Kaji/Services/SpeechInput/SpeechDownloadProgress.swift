import Foundation

struct SpeechDownloadProgress: Equatable {
    let fraction: Double
    let phaseTitle: String

    static let listing = SpeechDownloadProgress(fraction: 0, phaseTitle: "Listing files")
    static let starting = SpeechDownloadProgress(fraction: 0, phaseTitle: "Starting download")
    static let preparing = SpeechDownloadProgress(fraction: 0.5, phaseTitle: "Preparing model")

    var clampedFraction: Double {
        min(max(fraction, 0), 1)
    }

    var percentTitle: String {
        "\(Int((clampedFraction * 100).rounded()))%"
    }
}
