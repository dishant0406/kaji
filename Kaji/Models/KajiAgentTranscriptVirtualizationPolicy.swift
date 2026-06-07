import Foundation

struct KajiAgentTranscriptVirtualizationPolicy {
    static let liveTailTurnLimit = 3

    static func split(_ turns: [KajiAgentTurn]) -> KajiAgentTranscriptSections {
        guard turns.count > liveTailTurnLimit else {
            return KajiAgentTranscriptSections(history: [], liveTail: turns)
        }
        let splitIndex = turns.index(turns.endIndex, offsetBy: -liveTailTurnLimit)
        return KajiAgentTranscriptSections(
            history: Array(turns[..<splitIndex]),
            liveTail: Array(turns[splitIndex...])
        )
    }
}

struct KajiAgentTranscriptSections: Hashable {
    var history: [KajiAgentTurn]
    var liveTail: [KajiAgentTurn]
}
