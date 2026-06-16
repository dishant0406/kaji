import AppKit
import Foundation

@MainActor
enum MonacoEditorOptionsMapper {
    static func options(settings: EditorSettings, typography: AppTypographySettings) -> [String: MonacoJSONValue] {
        let font = typography.nsFont(size: AppTypographySettings.defaultFontSize)
        return [
            "showsLineNumbers": .bool(settings.showsLineNumbers),
            "highlightsActiveLine": .bool(settings.highlightsActiveLine),
            "showsIndentGuides": .bool(settings.showsIndentGuides),
            "rendersWhitespace": .bool(settings.rendersWhitespace),
            "highlightsMatchingBrackets": .bool(settings.highlightsMatchingBrackets),
            "wordWrapEnabled": .bool(settings.wordWrapEnabled),
            "autoClosesPairs": .bool(settings.autoClosesPairs),
            "autoIndentsNewLines": .bool(settings.autoIndentsNewLines),
            "tabSize": .int(settings.tabSize),
            "fontFamily": .string(font.familyName ?? AppTypographySettings.defaultFontFamily),
            "fontSize": .double(Double(font.pointSize)),
            "lineHeight": .double(Double(ceil(font.pointSize * 1.45))),
        ]
    }
}
