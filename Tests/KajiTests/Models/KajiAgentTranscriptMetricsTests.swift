import Testing

@testable import Kaji

struct KajiAgentTranscriptMetricsTests {
    @Test
    func usesReadableTranscriptWidthsAndTypeScale() {
        #expect(KajiAgentTranscriptMetrics.columnWidth >= 840)
        #expect(KajiAgentTranscriptMetrics.proseWidth < KajiAgentTranscriptMetrics.columnWidth)
        #expect(KajiAgentTranscriptMetrics.assistantFont > KajiAgentTranscriptMetrics.thinkingFont)
        #expect(KajiAgentTranscriptMetrics.codeMaxHeight >= 360)
    }
}
