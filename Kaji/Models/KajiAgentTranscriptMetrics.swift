import CoreGraphics

enum KajiAgentTranscriptMetrics {
    static let columnWidth: CGFloat = 860
    static let proseWidth: CGFloat = 720
    static let userWidth: CGFloat = 600
    static let assistantFont: CGFloat = 14.5
    static let userFont: CGFloat = 13.5
    static let thinkingFont: CGFloat = 12.75
    static let systemFont: CGFloat = 12.5
    static let metadataFont: CGFloat = 12
    static let toolFont: CGFloat = 12
    static let toolDetailFont: CGFloat = 11.5
    static let codeFont: CGFloat = 12
    static let inlineCodeDelta: CGFloat = 1
    static let lineSpacing: CGFloat = 4
    static let paragraphSpacing: CGFloat = 12
    static let turnSpacing: CGFloat = 22
    static let sameTurnSpacing: CGFloat = 8
    static let nestedIndent: CGFloat = 34
    static let nestedRowSpacing: CGFloat = 7
    static let nestedRailWidth: CGFloat = 1
    static let controlRadius: CGFloat = 8
    static let messageRadius: CGFloat = 10
    static let codeMaxHeight: CGFloat = 420
    static let thinkingPreviewCharacters = 3600
}
