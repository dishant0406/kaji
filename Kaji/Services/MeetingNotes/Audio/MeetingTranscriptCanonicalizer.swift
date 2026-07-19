import Foundation

enum MeetingTranscriptCanonicalizer {
    private struct Token {
        let normalized: String
        let endIndex: String.Index
    }

    static func trimmingDuplicatePrefix(
        from laterSegment: MeetingTranscriptSegment,
        after earlierSegment: MeetingTranscriptSegment
    ) -> MeetingTranscriptSegment {
        guard earlierSegment.trackID == laterSegment.trackID,
              laterSegment.sampleRange.startFrame < earlierSegment.sampleRange.endFrame,
              laterSegment.sampleRange.endFrame > earlierSegment.sampleRange.startFrame
        else {
            return laterSegment
        }
        let earlierTokens = tokens(in: earlierSegment.text)
        let laterTokens = tokens(in: laterSegment.text)
        let maximumOverlap = min(earlierTokens.count, laterTokens.count)
        guard maximumOverlap > 0 else { return laterSegment }
        var overlapCount = 0
        for count in stride(from: maximumOverlap, through: 1, by: -1) {
            let earlierSuffix = earlierTokens.suffix(count).map(\.normalized)
            let laterPrefix = laterTokens.prefix(count).map(\.normalized)
            if earlierSuffix.elementsEqual(laterPrefix) {
                overlapCount = count
                break
            }
        }
        guard overlapCount > 0 else { return laterSegment }
        let duplicateEnd = laterTokens[overlapCount - 1].endIndex
        let retainedText = String(laterSegment.text[duplicateEnd...])
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return MeetingTranscriptSegment(
            id: laterSegment.id,
            trackID: laterSegment.trackID,
            sampleRange: laterSegment.sampleRange,
            startMilliseconds: laterSegment.startMilliseconds,
            endMilliseconds: laterSegment.endMilliseconds,
            text: retainedText,
            speakerLabel: laterSegment.speakerLabel,
            isFinal: laterSegment.isFinal,
            createdAtMilliseconds: laterSegment.createdAtMilliseconds
        )
    }

    private static func tokens(in text: String) -> [Token] {
        var result: [Token] = []
        var index = text.startIndex
        while index < text.endIndex {
            guard isTokenCharacter(text[index]) else {
                index = text.index(after: index)
                continue
            }
            let start = index
            while index < text.endIndex, isTokenCharacter(text[index]) {
                index = text.index(after: index)
            }
            let normalized = text[start ..< index]
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .lowercased()
            result.append(Token(normalized: normalized, endIndex: index))
        }
        return result
    }

    private static func isTokenCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0)
        }
    }
}
