import Foundation

@MainActor
protocol SpeechInserting {
    func insert(_ text: String) throws
}
