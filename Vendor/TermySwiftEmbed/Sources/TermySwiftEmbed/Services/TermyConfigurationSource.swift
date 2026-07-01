import Foundation

public enum TermyConfigurationSource: Equatable {
    case defaultConfig
    case path(String)
    case contents(String)
}
