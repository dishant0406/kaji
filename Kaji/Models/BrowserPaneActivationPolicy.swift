import Foundation

enum BrowserPaneActivationPolicy {
    static func pageIsActive(pageID: UUID, selectedPageID: UUID, paneIsVisible: Bool) -> Bool {
        paneIsVisible && pageID == selectedPageID
    }

    static func shouldStartSelectedPage(paneIsVisible: Bool) -> Bool {
        paneIsVisible
    }

    static func browserActiveStateAfterStartup(requestedActiveState: Bool?) -> Bool {
        requestedActiveState ?? true
    }
}
