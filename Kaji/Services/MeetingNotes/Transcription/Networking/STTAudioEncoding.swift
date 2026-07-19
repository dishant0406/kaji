import Foundation

enum STTAudioEncodingError: Error, Equatable {
    case invalidFormat
    case invalidSamples
    case sizeLimitExceeded
    case invalidMultipartValue
}

enum STTPCM16SampleRate: Int, CaseIterable {
    case hertz16000 = 16000
    case hertz24000 = 24000
}

enum STTPCM16LittleEndianEncoder {
    static func encode(
        samples: [Float],
        sampleRate: STTPCM16SampleRate,
        maximumFrames: Int
    ) throws -> Data {
        guard maximumFrames >= 1,
              maximumFrames <= sampleRate.rawValue * 60 * 30,
              !samples.isEmpty,
              samples.count <= maximumFrames,
              samples.allSatisfy(\.isFinite)
        else {
            throw samples.count > maximumFrames ?
                STTAudioEncodingError.sizeLimitExceeded : STTAudioEncodingError.invalidSamples
        }
        var data = Data(capacity: samples.count * MemoryLayout<Int16>.size)
        for sample in samples {
            let value: Int16 = if sample <= -1 {
                .min
            } else if sample >= 1 {
                .max
            } else {
                Int16((sample * Float(Int16.max)).rounded())
            }
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }
}

struct STTBoundedPCM16FrameEncoder {
    let sampleRate: STTPCM16SampleRate
    let maximumFramesPerChunk: Int
    let maximumTotalFrames: Int
    private(set) var encodedFrameCount = 0

    init(
        sampleRate: STTPCM16SampleRate,
        maximumFramesPerChunk: Int,
        maximumTotalFrames: Int
    ) throws {
        guard maximumFramesPerChunk >= 1,
              maximumTotalFrames >= maximumFramesPerChunk,
              maximumTotalFrames <= sampleRate.rawValue * 60 * 30
        else {
            throw STTAudioEncodingError.invalidFormat
        }
        self.sampleRate = sampleRate
        self.maximumFramesPerChunk = maximumFramesPerChunk
        self.maximumTotalFrames = maximumTotalFrames
    }

    mutating func encode(_ samples: [Float]) throws -> Data {
        guard samples.count <= maximumTotalFrames - encodedFrameCount else {
            throw STTAudioEncodingError.sizeLimitExceeded
        }
        let data = try STTPCM16LittleEndianEncoder.encode(
            samples: samples,
            sampleRate: sampleRate,
            maximumFrames: maximumFramesPerChunk
        )
        encodedFrameCount += samples.count
        return data
    }
}

enum STTMultipartWAVEncoder {
    static let maximumWAVBytes = 32 * 1024 * 1024
    static let maximumMultipartBytes = 34 * 1024 * 1024

    static func wav(
        pcm16: Data,
        sampleRate: STTPCM16SampleRate,
        channelCount: UInt16 = 1,
        maximumBytes: Int = maximumWAVBytes
    ) throws -> Data {
        guard maximumBytes >= 44,
              maximumBytes <= maximumWAVBytes,
              channelCount >= 1,
              channelCount <= 2,
              !pcm16.isEmpty,
              pcm16.count.isMultiple(of: Int(channelCount) * MemoryLayout<Int16>.size),
              pcm16.count <= maximumBytes - 44,
              pcm16.count <= Int(UInt32.max) - 36
        else {
            throw pcm16.count > maximumBytes - 44 ?
                STTAudioEncodingError.sizeLimitExceeded : STTAudioEncodingError.invalidFormat
        }
        let byteRate = UInt32(sampleRate.rawValue) * UInt32(channelCount) * 2
        let blockAlign = channelCount * 2
        var data = Data(capacity: pcm16.count + 44)
        data.append(Data("RIFF".utf8))
        append(UInt32(36 + pcm16.count), to: &data)
        data.append(Data("WAVEfmt ".utf8))
        append(UInt32(16), to: &data)
        append(UInt16(1), to: &data)
        append(channelCount, to: &data)
        append(UInt32(sampleRate.rawValue), to: &data)
        append(byteRate, to: &data)
        append(blockAlign, to: &data)
        append(UInt16(16), to: &data)
        data.append(Data("data".utf8))
        append(UInt32(pcm16.count), to: &data)
        data.append(pcm16)
        return data
    }

    static func multipart(
        wav: Data,
        filename: String,
        fieldName: String = "file",
        boundary: String,
        maximumBytes: Int = maximumMultipartBytes
    ) throws -> Data {
        guard maximumBytes >= 1,
              maximumBytes <= maximumMultipartBytes,
              isSafeToken(fieldName, maximumLength: 64),
              isSafeFilename(filename),
              isSafeBoundary(boundary),
              wav.count <= maximumWAVBytes
        else {
            throw STTAudioEncodingError.invalidMultipartValue
        }
        let disposition = "Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(filename)\"\r\n"
        let prefix = Data(("--\(boundary)\r\n" + disposition + "Content-Type: audio/wav\r\n\r\n").utf8)
        let suffix = Data("\r\n--\(boundary)--\r\n".utf8)
        guard prefix.count <= maximumBytes,
              wav.count <= maximumBytes - prefix.count,
              suffix.count <= maximumBytes - prefix.count - wav.count
        else {
            throw STTAudioEncodingError.sizeLimitExceeded
        }
        var body = Data(capacity: prefix.count + wav.count + suffix.count)
        body.append(prefix)
        body.append(wav)
        body.append(suffix)
        return body
    }

    private static func append(_ value: some FixedWidthInteger, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    private static func isSafeFilename(_ value: String) -> Bool {
        guard value.lowercased().hasSuffix(".wav"), isSafeToken(value, maximumLength: 100) else {
            return false
        }
        return value != ".wav" && !value.hasPrefix(".")
    }

    private static func isSafeToken(_ value: String, maximumLength: Int) -> Bool {
        guard !value.isEmpty, value.count <= maximumLength else { return false }
        return value.utf8.allSatisfy { byte in
            byte >= 0x41 && byte <= 0x5A ||
                byte >= 0x61 && byte <= 0x7A ||
                byte >= 0x30 && byte <= 0x39 ||
                byte == 0x2D || byte == 0x2E || byte == 0x5F
        }
    }

    private static func isSafeBoundary(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 70 else { return false }
        let allowed = Set("'()+_,-./:=?".utf8)
        return value.utf8.allSatisfy { byte in
            byte >= 0x41 && byte <= 0x5A ||
                byte >= 0x61 && byte <= 0x7A ||
                byte >= 0x30 && byte <= 0x39 || allowed.contains(byte)
        }
    }
}
