import SwiftUI

struct KajiAgentTimelineRowHeightValue: Equatable {
    let id: KajiAgentTimelineRowID
    let height: CGFloat
}

struct KajiAgentTimelineRowHeightPreferenceKey: PreferenceKey {
    static let defaultValue: [KajiAgentTimelineRowHeightValue] = []

    static func reduce(value: inout [KajiAgentTimelineRowHeightValue], nextValue: () -> [KajiAgentTimelineRowHeightValue]) {
        value.append(contentsOf: nextValue())
    }
}

struct KajiAgentTimelineRowHeightReader: ViewModifier {
    let id: KajiAgentTimelineRowID

    func body(content: Content) -> some View {
        content.background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: KajiAgentTimelineRowHeightPreferenceKey.self,
                    value: [KajiAgentTimelineRowHeightValue(id: id, height: proxy.size.height)]
                )
            }
        }
    }
}

extension View {
    func kajiAgentTimelineRowHeight(id: KajiAgentTimelineRowID) -> some View {
        modifier(KajiAgentTimelineRowHeightReader(id: id))
    }
}
