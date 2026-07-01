import Foundation

struct SpeechInsertionPolicy {
    let insertTrailingSpace: Bool

    func preparedText(_ transcript: String) -> String {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard insertTrailingSpace else { return trimmed }
        guard let last = trimmed.unicodeScalars.last, !CharacterSet.punctuationCharacters.contains(last) else {
            return trimmed
        }
        return trimmed + " "
    }
}
