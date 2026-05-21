import SwiftUI

struct ReorderableFramePreferenceKey<ID: Hashable>: PreferenceKey {
    static var defaultValue: [ID: CGRect] { [:] }

    static func reduce(value: inout [ID: CGRect], nextValue: () -> [ID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}
