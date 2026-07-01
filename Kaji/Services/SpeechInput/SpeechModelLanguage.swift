import FluidAudio
import Foundation

enum SpeechModelLanguage: String, Codable, Equatable, Hashable, CaseIterable {
    case english = "en"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case italian = "it"
    case portuguese = "pt"
    case russian = "ru"
    case ukrainian = "uk"
    case greek = "el"

    var fluidAudioLanguage: Language {
        switch self {
        case .english: .english
        case .spanish: .spanish
        case .french: .french
        case .german: .german
        case .italian: .italian
        case .portuguese: .portuguese
        case .russian: .russian
        case .ukrainian: .ukrainian
        case .greek: .greek
        }
    }
}
