import FluidAudio
import Foundation

struct SpeechModelRuntimeConfig: Codable, Equatable, Hashable {
    let asrVersion: SpeechModelAsrVersion?
    let encoderPrecision: SpeechModelEncoderPrecision?
    let language: SpeechModelLanguage?
    let melChunkContext: Bool?
}

enum SpeechModelAsrVersion: String, Codable, Equatable, Hashable {
    case v2
    case v3
    case tdtCtc110m
    case tdtJa

    var fluidAudioVersion: AsrModelVersion {
        switch self {
        case .v2: .v2
        case .v3: .v3
        case .tdtCtc110m: .tdtCtc110m
        case .tdtJa: .tdtJa
        }
    }

    var decoderLayers: Int {
        self == .tdtCtc110m ? 1 : 2
    }

    var encoderHiddenSize: Int {
        self == .tdtCtc110m ? 512 : 1024
    }
}

enum SpeechModelEncoderPrecision: String, Codable, Equatable, Hashable {
    case int8
    case int4

    var fluidAudioPrecision: ParakeetEncoderPrecision {
        switch self {
        case .int8: .int8
        case .int4: .int4
        }
    }
}
