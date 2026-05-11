import Foundation

struct BrowserConsoleEntry: Identifiable, Equatable {
    let id = UUID()
    let command: String
    var result: String
    var isRunning: Bool
}
