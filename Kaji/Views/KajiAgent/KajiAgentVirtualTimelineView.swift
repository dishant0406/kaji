import SwiftUI
import SwiftUIIntrospect

struct KajiAgentVirtualTimelineView: View {
    let rowStore: KajiAgentTimelineRowStore
    let viewportHeight: CGFloat
    let heightIndex: KajiAgentTimelineHeightIndex
    let scrollCoordinator: KajiAgentScrollCoordinator
    let viewportObserver: KajiAgentScrollViewportObserver
    let onStructureChanged: () -> Void
    let onInspectItem: (KajiAgentInspectorItem) -> Void

    var body: some View {
        let rows = rowStore.rows
        let layout = heightIndex.layout(
            scrollOffset: viewportObserver.scrollOffset,
            viewportHeight: effectiveViewportHeight
        )
        ScrollView(.vertical, showsIndicators: true) {
            HStack(alignment: .top, spacing: 0) {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: layout.topSpacerHeight)
                    ForEach(Array(layout.range), id: \.self) { index in
                        KajiAgentTimelineRowView(
                            row: rows[index],
                            isToolGroupExpanded: rowStore.isToolGroupExpanded,
                            toggleToolGroup: toggleToolGroup,
                            isToolExpanded: rowStore.isToolExpanded,
                            toggleTool: toggleTool,
                            toggleThinking: toggleThinking,
                            onInspectItem: onInspectItem
                        )
                        .kajiAgentTimelineRowHeight(id: rows[index].id)
                    }
                    Color.clear.frame(height: layout.bottomSpacerHeight)
                }
                .frame(
                    maxWidth: KajiAgentTranscriptMetrics.columnWidth,
                    minHeight: max(layout.totalHeight, effectiveViewportHeight),
                    alignment: .topLeading
                )
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: max(layout.totalHeight, effectiveViewportHeight), alignment: .top)
            .padding(.bottom, 8)
            .scrollTargetLayout()
        }
        .defaultScrollAnchor(.bottom)
        .introspect(.scrollView, on: .macOS(.v14, .v15, .v26)) { scrollView in
            scrollCoordinator.attach(scrollView)
            viewportObserver.attach(scrollView)
        }
        .onPreferenceChange(KajiAgentTimelineRowHeightPreferenceKey.self) { values in
            applyMeasuredHeights(values)
        }
    }

    private var effectiveViewportHeight: CGFloat {
        max(viewportHeight, viewportObserver.viewportHeight, 1)
    }

    private func toggleToolGroup(_ id: UUID) {
        let rowID = rowStore.rowID(forToolGroup: id)
        rowStore.toggleToolGroup(id)
        heightIndex.invalidate(rowID)
        onStructureChanged()
    }

    private func toggleTool(_ id: UUID) {
        let rowID = rowStore.rowID(forTool: id)
        rowStore.toggleTool(id)
        heightIndex.invalidate(rowID)
        onStructureChanged()
    }

    private func toggleThinking(_ id: UUID) {
        let rowID = rowStore.rowID(forThinking: id)
        rowStore.toggleThinking(id)
        heightIndex.invalidate(rowID)
        onStructureChanged()
    }

    private func applyMeasuredHeights(_ values: [KajiAgentTimelineRowHeightValue]) {
        let result = heightIndex.applyMeasurements(values, rowStore: rowStore, scrollOffset: viewportObserver.scrollOffset)
        viewportObserver.adjustOffset(by: result.correction)
    }
}
