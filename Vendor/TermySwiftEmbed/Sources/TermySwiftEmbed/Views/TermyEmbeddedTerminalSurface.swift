import SwiftUI

public struct TermyEmbeddedTerminalSurface: View {
    @ObservedObject private var terminal: TerminalViewModel
    private let isFocused: Bool
    private let isInputEnabled: Bool
    private let isSearchVisible: Bool
    private let onFocus: () -> Void
    private let onSplitRight: () -> Void
    private let onSplitDown: () -> Void
    private let onClosePane: () -> Void
    private let onClosePaneIfSplit: () -> Bool
    private let onShowSearch: () -> Void
    private let onDismissSearch: () -> Void

    public init(
        controller: TermyEmbeddedTerminal,
        isFocused: Bool,
        isInputEnabled: Bool,
        isSearchVisible: Bool,
        onFocus: @escaping () -> Void,
        onSplitRight: @escaping () -> Void,
        onSplitDown: @escaping () -> Void,
        onClosePane: @escaping () -> Void,
        onClosePaneIfSplit: @escaping () -> Bool,
        onShowSearch: @escaping () -> Void,
        onDismissSearch: @escaping () -> Void
    ) {
        terminal = controller.terminal
        self.isFocused = isFocused
        self.isInputEnabled = isInputEnabled
        self.isSearchVisible = isSearchVisible
        self.onFocus = onFocus
        self.onSplitRight = onSplitRight
        self.onSplitDown = onSplitDown
        self.onClosePane = onClosePane
        self.onClosePaneIfSplit = onClosePaneIfSplit
        self.onShowSearch = onShowSearch
        self.onDismissSearch = onDismissSearch
    }

    public var body: some View {
        TermyEmbeddedTerminalBody(
            terminal: terminal,
            isFocused: isFocused,
            isInputEnabled: isInputEnabled,
            isSearchVisible: isSearchVisible,
            onFocus: onFocus,
            onSplitRight: onSplitRight,
            onSplitDown: onSplitDown,
            onClosePane: onClosePane,
            onClosePaneIfSplit: onClosePaneIfSplit,
            onShowSearch: onShowSearch,
            onDismissSearch: onDismissSearch
        )
    }
}

private struct TermyEmbeddedTerminalBody: View {
    @ObservedObject var terminal: TerminalViewModel
    @State private var lastSize: CGSize = .zero
    @State private var bellFlashOpacity: Double = 0
    let isFocused: Bool
    let isInputEnabled: Bool
    let isSearchVisible: Bool
    let onFocus: () -> Void
    let onSplitRight: () -> Void
    let onSplitDown: () -> Void
    let onClosePane: () -> Void
    let onClosePaneIfSplit: () -> Bool
    let onShowSearch: () -> Void
    let onDismissSearch: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                TerminalGridView(
                    frame: terminal.frame,
                    renderPlan: terminal.renderPlan,
                    renderDamage: terminal.renderDamage,
                    selection: terminal.selection,
                    renderConfig: terminal.renderConfig,
                    searchMatches: terminal.searchMatches,
                    activeSearchMatch: terminal.searchMatches[safe: terminal.activeSearchMatchIndex],
                    hoveredLink: terminal.hoveredLink,
                    isFocused: isFocused,
                    isCursorVisible: terminal.cursorBlinkVisible
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .onChange(of: isFocused) { _, value in terminal.setPaneFocused(value) }
                .onAppear { terminal.setPaneFocused(isFocused) }

                TerminalKeyboardInputView(
                    cols: terminal.frameMetadata.cols,
                    rows: terminal.frameMetadata.rows,
                    renderConfig: terminal.renderConfig,
                    isInputEnabled: isInputEnabled,
                    isSearchVisible: isSearchVisible,
                    canCopy: terminal.canCopySelection,
                    onFocus: onFocus,
                    onBytes: { terminal.send(bytes: $0) },
                    onKeyInput: { terminal.sendKey($0) },
                    onMouseInput: { terminal.sendMouse($0) },
                    onScrollLines: { terminal.scrollDisplay(deltaLines: $0) },
                    onScrollToTop: { terminal.scrollToTop() },
                    onScrollToBottom: { terminal.scrollToBottom() },
                    onClearBuffer: { terminal.clearScrollback() },
                    onSplitRight: onSplitRight,
                    onSplitDown: onSplitDown,
                    onClosePane: onClosePane,
                    onClosePaneIfSplit: onClosePaneIfSplit,
                    onFocusNextPane: {},
                    onShowSearch: onShowSearch,
                    onDismissSearch: onDismissSearch,
                    onSelectionChanged: { terminal.updateSelection($0) },
                    onSelectWord: { terminal.selectWord(at: $0) },
                    onSelectLine: { terminal.selectLine(at: $0) },
                    onSelectAll: { terminal.selectAll() },
                    onHoverProbe: { terminal.updateHoveredLink(at: $0) },
                    onOpenLink: { terminal.openLink(at: $0) },
                    onCopy: { terminal.copySelection() },
                    onPaste: { terminal.paste($0) },
                    onMarkedTextChanged: { terminal.setMarkedText($0) }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                markedTextOverlay
                TerminalTopLoader(progress: terminal.progress)
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                if let errorMessage = terminal.errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.red)
                        .padding(8)
                        .background(.regularMaterial)
                        .padding(8)
                }

                if terminal.isExited, !terminal.hasVisibleContent {
                    Text("Process exited")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .background(terminal.renderConfig.background.swiftUIColor.opacity(terminal.renderConfig.backgroundOpacity))
            .overlay {
                if bellFlashOpacity > 0 {
                    Rectangle()
                        .fill(terminal.renderConfig.foreground.swiftUIColor)
                        .opacity(bellFlashOpacity)
                        .allowsHitTesting(false)
                }
            }
            .onChange(of: terminal.bellPulse) { _, _ in
                bellFlashOpacity = 0.2
                withAnimation(.easeOut(duration: 0.3)) { bellFlashOpacity = 0 }
            }
            .onAppear {
                onFocus()
                terminal.start()
                lastSize = proxy.size
                resizeTerminal(to: proxy.size)
            }
            .onChange(of: proxy.size) { _, size in
                lastSize = size
                resizeTerminal(to: size)
            }
            .onChange(of: terminal.renderConfig) { _, _ in resizeTerminal(to: lastSize) }
        }
    }

    private func resizeTerminal(to size: CGSize) {
        let availableWidth = size.width - terminal.renderConfig.paddingX * 2
        let availableHeight = size.height - terminal.renderConfig.paddingY * 2
        terminal.resize(
            cols: gridCount(availableWidth, cellSize: terminal.renderConfig.cellWidth),
            rows: gridCount(availableHeight, cellSize: terminal.renderConfig.cellHeight),
            cellWidth: terminal.renderConfig.cellWidth,
            cellHeight: terminal.renderConfig.cellHeight
        )
    }

    private func gridCount(_ availableSize: CGFloat, cellSize: CGFloat) -> Int {
        guard availableSize.isFinite, cellSize.isFinite, cellSize > 0 else { return 2 }
        return max(2, Int(floor(max(0, availableSize) / cellSize)))
    }

    @ViewBuilder
    private var markedTextOverlay: some View {
        if !terminal.markedText.isEmpty, let cursor = terminal.frameMetadata.cursor {
            let config = terminal.renderConfig
            Text(terminal.markedText)
                .font(.custom(config.fontFamily, size: config.fontSize))
                .foregroundStyle(config.foreground.swiftUIColor)
                .background(config.background.swiftUIColor)
                .underline()
                .fixedSize()
                .offset(
                    x: config.paddingX + CGFloat(cursor.col) * config.cellWidth,
                    y: config.paddingY + CGFloat(cursor.row) * config.cellHeight
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .allowsHitTesting(false)
        }
    }
}
