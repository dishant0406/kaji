import Foundation

struct BrowserSurfaceCallbacks {
    let pageChanged: (UUID, String) -> Void
    let popupRequested: (UUID, String) -> Void
}
