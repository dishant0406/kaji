import Foundation

struct UserCommandShortcutPreview: Hashable {
    let detail: String
    let annotation: String
}

enum UserCommandShortcutResolveResult: Hashable {
    case plan(NativeCommandRunPlan)
    case failure(title: String, message: String)
}

enum UserCommandShortcutComputedValueResult: Hashable {
    case success(String)
    case failure(String)
}
