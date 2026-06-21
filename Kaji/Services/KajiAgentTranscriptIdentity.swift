import Foundation

enum KajiAgentTranscriptIdentity {
    static func uuid(_ parts: String...) -> UUID {
        uuid(parts.joined(separator: "\u{1f}"))
    }

    static func uuid(_ value: String) -> UUID {
        var first: UInt64 = 0xCBF2_9CE4_8422_2325
        var second: UInt64 = 0x9E37_79B9_7F4A_7C15
        for byte in value.utf8 {
            first ^= UInt64(byte)
            first &*= 0x100_0000_01B3
            second ^= UInt64(byte) &+ first
            second = (second << 7) | (second >> 57)
            second &*= 0x100_0000_01B3
        }
        return UUID(uuid: (
            UInt8((first >> 56) & 0xFF),
            UInt8((first >> 48) & 0xFF),
            UInt8((first >> 40) & 0xFF),
            UInt8((first >> 32) & 0xFF),
            UInt8((first >> 24) & 0xFF),
            UInt8((first >> 16) & 0xFF),
            UInt8((first >> 8) & 0xFF),
            UInt8(first & 0xFF),
            UInt8((second >> 56) & 0xFF),
            UInt8((second >> 48) & 0xFF),
            UInt8((second >> 40) & 0xFF),
            UInt8((second >> 32) & 0xFF),
            UInt8((second >> 24) & 0xFF),
            UInt8((second >> 16) & 0xFF),
            UInt8((second >> 8) & 0xFF),
            UInt8(second & 0xFF)
        ))
    }
}
