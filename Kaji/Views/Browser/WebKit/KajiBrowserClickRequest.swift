import Foundation

struct KajiBrowserClickRequest {
    let target: String?
    let selector: String?
    let button: String
    let doubleClick: Bool
    let x: Double?
    let y: Double?
}
