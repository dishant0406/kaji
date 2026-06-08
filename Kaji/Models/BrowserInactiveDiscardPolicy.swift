import Foundation

enum BrowserInactiveDiscardPolicy {
    static let defaultDelay: Duration = .seconds(30)

    static func shouldScheduleDiscard(closeOnDisappear: Bool, paneIsVisible: Bool) -> Bool {
        !closeOnDisappear && !paneIsVisible
    }
}
