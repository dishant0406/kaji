import Foundation

enum DroidBrowserRuntimeError: LocalizedError, Equatable {
    case runtimeMissing
    case helperMissing
    case initializationFailed

    var errorDescription: String? {
        switch self {
        case .runtimeMissing:
            "Bundled CEF runtime not found. Run scripts/install-cef-runtime.sh and rebuild Droid."
        case .helperMissing:
            "Bundled CEF helper app not found. Run scripts/install-cef-runtime.sh and rebuild Droid."
        case .initializationFailed:
            "CEF failed to initialize."
        }
    }
}
