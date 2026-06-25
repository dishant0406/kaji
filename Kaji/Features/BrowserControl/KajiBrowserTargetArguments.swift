import Foundation

struct KajiBrowserTargetArguments {
    let target: String?
    let selector: String?

    init(_ arguments: KajiBrowserControlArguments) {
        target = arguments.string("target", "ref")
        selector = arguments.string("selector")
    }
}
