import AppKit
import SwiftUI

struct VirtualizedList<Item: Identifiable, Row: View>: View {
    let items: [Item]
    let rowHeight: CGFloat
    let highlightedIndex: Int?
    let overscan: Int
    let row: (Int, Item) -> Row
    let coordinateSpace = UUID().uuidString

    @State private var scrollOffset: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0

    init(
        items: [Item],
        rowHeight: CGFloat,
        highlightedIndex: Int? = nil,
        overscan: Int = 8,
        @ViewBuilder row: @escaping (Int, Item) -> Row
    ) {
        self.items = items
        self.rowHeight = rowHeight
        self.highlightedIndex = highlightedIndex
        self.overscan = overscan
        self.row = row
    }

    var body: some View {
        GeometryReader { geometry in
            content(viewportHeight: geometry.size.height)
                .onAppear { viewportHeight = geometry.size.height }
                .onChange(of: geometry.size.height) { _, height in viewportHeight = height }
        }
    }

    @ViewBuilder
    private func content(viewportHeight: CGFloat) -> some View {
        if contentHeight <= viewportHeight {
            VStack(spacing: 0) {
                ForEach(items.indices, id: \.self) { index in
                    row(index, items[index])
                        .frame(height: rowHeight)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onAppear { scrollOffset = 0 }
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    offsetReader
                        .frame(height: 0)
                        .background(scrollController)
                    Color.clear.frame(height: topSpacerHeight)
                    ForEach(visibleRange, id: \.self) { index in
                        row(index, items[index])
                            .frame(height: rowHeight)
                    }
                    Color.clear.frame(height: bottomSpacerHeight)
                }
                .frame(maxWidth: .infinity, minHeight: contentHeight, alignment: .topLeading)
            }
            .coordinateSpace(name: coordinateSpace)
            .onPreferenceChange(VirtualizedListOffsetKey.self) { scrollOffset = min(max(0, $0), maxScrollOffset) }
        }
    }

    private var contentHeight: CGFloat {
        max(0, CGFloat(items.count) * rowHeight)
    }

    private var visibleRange: [Int] {
        guard !items.isEmpty, rowHeight > 0, viewportHeight > 0 else { return Array(items.indices.prefix(overscan * 2)) }
        let first = visibleStartIndex
        let visibleCount = Int(ceil(viewportHeight / rowHeight)) + overscan * 2
        let last = min(items.count - 1, first + visibleCount)
        guard first <= last else { return [] }
        return Array(first ... last)
    }

    private var visibleStartIndex: Int {
        guard rowHeight > 0 else { return 0 }
        return max(0, Int(floor(min(scrollOffset, maxScrollOffset) / rowHeight)) - overscan)
    }

    private var topSpacerHeight: CGFloat {
        CGFloat(visibleStartIndex) * rowHeight
    }

    private var bottomSpacerHeight: CGFloat {
        guard let last = visibleRange.last else { return 0 }
        return max(0, contentHeight - CGFloat(last + 1) * rowHeight)
    }

    private var maxScrollOffset: CGFloat {
        max(0, contentHeight - viewportHeight)
    }

    private var offsetReader: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: VirtualizedListOffsetKey.self,
                value: -proxy.frame(in: .named(coordinateSpace)).minY
            )
        }
    }

    private var scrollController: some View {
        VirtualizedListScrollController(
            highlightedIndex: highlightedIndex,
            rowHeight: rowHeight,
            scrollOffset: scrollOffset,
            viewportHeight: viewportHeight,
            itemCount: items.count
        )
    }
}

private struct VirtualizedListOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct VirtualizedListScrollController: NSViewRepresentable {
    let highlightedIndex: Int?
    let rowHeight: CGFloat
    let scrollOffset: CGFloat
    let viewportHeight: CGFloat
    let itemCount: Int

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let scrollView = view.enclosingScrollView else { return }
            scrollView.verticalScrollElasticity = .none
            scrollView.hasVerticalScroller = CGFloat(itemCount) * rowHeight > scrollView.documentVisibleRect.height
            clamp(scrollView)
        }
        guard context.coordinator.lastIndex != highlightedIndex || context.coordinator.lastItemCount != itemCount else { return }
        context.coordinator.lastIndex = highlightedIndex
        context.coordinator.lastItemCount = itemCount
        guard let highlightedIndex, highlightedIndex >= 0, highlightedIndex < itemCount else { return }
        DispatchQueue.main.async {
            guard let scrollView = view.enclosingScrollView else { return }
            let visibleHeight = viewportHeight > 0 ? viewportHeight : scrollView.documentVisibleRect.height
            guard CGFloat(itemCount) * rowHeight > visibleHeight else {
                scrollView.contentView.scroll(to: .zero)
                scrollView.reflectScrolledClipView(scrollView.contentView)
                return
            }
            let visibleMinY = scrollView.documentVisibleRect.minY
            let visibleMaxY = scrollView.documentVisibleRect.maxY
            let rowMinY = CGFloat(highlightedIndex) * rowHeight
            let rowMaxY = rowMinY + rowHeight
            guard rowMinY < visibleMinY || rowMaxY > visibleMaxY else { return }
            let target = rowMinY - max(0, visibleHeight - rowHeight) / 2
            let maxY = max(0, CGFloat(itemCount) * rowHeight - visibleHeight)
            let y = min(max(0, target), maxY)
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    private func clamp(_ scrollView: NSScrollView) {
        let visibleHeight = viewportHeight > 0 ? viewportHeight : scrollView.documentVisibleRect.height
        let maxY = max(0, CGFloat(itemCount) * rowHeight - visibleHeight)
        guard scrollOffset > maxY || scrollOffset < 0 else { return }
        let y = min(max(0, scrollOffset), maxY)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    final class Coordinator {
        var lastIndex: Int?
        var lastItemCount = 0
    }
}
