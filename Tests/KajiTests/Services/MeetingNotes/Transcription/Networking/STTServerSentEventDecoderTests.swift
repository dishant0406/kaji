import Foundation
import Testing

@testable import Kaji

@Suite("STT server-sent event decoding")
struct STTServerSentEventDecoderTests {
    @Test("incremental decoder handles CRLF and multi-line data")
    func incrementalEvent() throws {
        let limits = try STTSSEDecoderLimits(
            maximumLineBytes: 64,
            maximumEventDataBytes: 128,
            maximumBufferedBytes: 256,
            maximumEventsPerBatch: 4
        )
        var decoder = STTServerSentEventDecoder(limits: limits)

        #expect(try decoder.append(Data("event: transcript\r\ndata: hel".utf8)).isEmpty)
        let events = try decoder.append(Data("lo\r\ndata: world\r\nid: 7\r\nretry: 1000\r\n\r\n".utf8))

        #expect(events == [STTServerSentEvent(
            event: "transcript",
            data: "hello\nworld",
            id: "7",
            retryMilliseconds: 1000
        )])
    }

    @Test("decoder rejects oversized lines")
    func lineLimit() throws {
        let limits = try STTSSEDecoderLimits(
            maximumLineBytes: 8,
            maximumEventDataBytes: 16,
            maximumBufferedBytes: 32,
            maximumEventsPerBatch: 2
        )
        var decoder = STTServerSentEventDecoder(limits: limits)

        #expect(throws: STTSSEDecoderError.lineTooLong) {
            try decoder.append(Data("data: 123456789".utf8))
        }
    }

    @Test("decoder rejects cumulative event data exhaustion")
    func eventLimit() throws {
        let limits = try STTSSEDecoderLimits(
            maximumLineBytes: 16,
            maximumEventDataBytes: 16,
            maximumBufferedBytes: 32,
            maximumEventsPerBatch: 2
        )
        var decoder = STTServerSentEventDecoder(limits: limits)

        #expect(throws: STTSSEDecoderError.eventTooLarge) {
            try decoder.append(Data("data: 12345678\ndata: abcdefgh\n".utf8))
        }
    }

    @Test("decoder bounds events emitted by one batch")
    func eventCountLimit() throws {
        let limits = try STTSSEDecoderLimits(
            maximumLineBytes: 16,
            maximumEventDataBytes: 16,
            maximumBufferedBytes: 64,
            maximumEventsPerBatch: 1
        )
        var decoder = STTServerSentEventDecoder(limits: limits)

        #expect(throws: STTSSEDecoderError.tooManyEvents) {
            try decoder.append(Data("data: 1\n\ndata: 2\n\n".utf8))
        }
    }

    @Test("decoder rejects invalid UTF-8")
    func invalidUTF8() throws {
        let limits = try STTSSEDecoderLimits(
            maximumLineBytes: 16,
            maximumEventDataBytes: 16,
            maximumBufferedBytes: 32,
            maximumEventsPerBatch: 1
        )
        var decoder = STTServerSentEventDecoder(limits: limits)

        #expect(throws: STTSSEDecoderError.invalidEncoding) {
            try decoder.append(Data([0x64, 0x61, 0x74, 0x61, 0x3A, 0x20, 0xFF, 0x0A]))
        }
    }
}
