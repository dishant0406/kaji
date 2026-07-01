import Foundation

enum ThemeServiceError: LocalizedError {
    case invalidThemeFile
    case duplicateTheme
    case saveCancelled
    case importCancelled

    var errorDescription: String? {
        switch self {
        case .invalidThemeFile:
            "The selected file is not a valid Termy theme."
        case .duplicateTheme:
            "A theme with this slug already exists."
        case .saveCancelled:
            "Export was cancelled."
        case .importCancelled:
            "Import was cancelled."
        }
    }
}
