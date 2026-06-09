import SwiftUI

struct KajiAgentTimelineView: View {
    let store: KajiAgentStore
    let floatingTaskState: KajiAgentFloatingTaskState
    @State private var scrollCoordinator = KajiAgentScrollCoordinator()
    @State private var viewportObserver = KajiAgentScrollViewportObserver()
    @State private var rowStore = KajiAgentTimelineRowStore()
    @State private var heightIndex = KajiAgentTimelineHeightIndex()
    @State private var lastViewportHeight: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            timeline(viewportHeight: geometry.size.height)
                .onAppear { refreshRows(viewportHeight: geometry.size.height) }
                .onChange(of: geometry.size.height) { _, height in
                    refreshRows(viewportHeight: height)
                }
        }
        .onAppear {
            guard !store.turns.isEmpty else { return }
            scrollCoordinator.requestInitialBottomScroll()
        }
        .onChange(of: store.tailVersion) { _, _ in
            refreshRows(viewportHeight: lastViewportHeight)
        }
        .onChange(of: store.widgetLines) { _, _ in
            refreshRows(viewportHeight: lastViewportHeight)
        }
        .onChange(of: store.queuedMessageCount) { _, _ in
            refreshRows(viewportHeight: lastViewportHeight)
        }
        .onChange(of: store.turns.last?.id) { _, id in
            guard let id else { return }
            refreshRows(viewportHeight: lastViewportHeight)
            scrollCoordinator.scrollToTurn(id)
        }
        .onChange(of: store.autoScrollVersion) { _, _ in
            scrollCoordinator.handleTailChanged()
        }
        .onChange(of: store.forceScrollVersion) { _, _ in
            scrollCoordinator.scrollToBottom(force: true)
        }
        .onChange(of: store.userSubmittedScrollVersion) { _, _ in
            scrollCoordinator.prepareForUserSubmittedTurn()
        }
    }

    private func timeline(viewportHeight: CGFloat) -> some View {
        ZStack(alignment: .bottomTrailing) {
            KajiAgentVirtualTimelineView(
                rowStore: rowStore,
                viewportHeight: viewportHeight,
                heightIndex: heightIndex,
                scrollCoordinator: scrollCoordinator,
                viewportObserver: viewportObserver,
                onStructureChanged: { syncRows(viewportHeight: viewportHeight) }
            )
            bottomTrailingControls
        }
    }

    private func refreshRows(viewportHeight: CGFloat) {
        lastViewportHeight = viewportHeight
        rowStore.rebuild(
            turns: store.turns,
            widgetLines: store.widgetLines,
            queuedMessageCount: store.queuedMessageCount
        )
        syncRows(viewportHeight: viewportHeight)
    }

    private func syncRows(viewportHeight: CGFloat) {
        heightIndex.sync(rows: rowStore.rows)
        rowStore.setLatestTurnSpacer(turnID: store.turns.last?.id, height: latestTurnSpacerHeight(viewportHeight: viewportHeight))
        heightIndex.sync(rows: rowStore.rows)
    }

    private func latestTurnSpacerHeight(viewportHeight: CGFloat) -> CGFloat {
        guard let latestTurnID = store.turns.last?.id else { return 0 }
        let height = rowStore.rows.filter { row in
            row.turnID == latestTurnID && !row.isSpacer
        }.reduce(CGFloat(0)) { partial, row in
            partial + heightIndex.height(for: row)
        }
        return max(0, viewportHeight - height - 8)
    }

    private var bottomTrailingControls: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if scrollCoordinator.hasUnseenTail {
                Button("Jump to latest") {
                    scrollCoordinator.scrollToBottom(force: true)
                }
                .buttonStyle(KajiButtonStyle(.secondary, size: .small))
            }
            KajiAgentFloatingTaskButton(state: floatingTaskState)
        }
        .padding(.trailing, 14)
        .padding(.bottom, 14)
    }
}
