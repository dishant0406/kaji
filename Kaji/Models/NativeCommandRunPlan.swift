import Foundation

struct NativeCommandRunPlan: Hashable {
    let title: String
    let executable: String
    let arguments: [String]
    let workingDirectory: URL
    let refreshesRepository: Bool
}
