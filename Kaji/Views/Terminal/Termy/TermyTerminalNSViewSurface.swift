import AppKit
import SwiftUI
import TermySwiftEmbed

extension TermyTerminalNSView {
    func installHostingView() {
        let view = NSHostingView(rootView: terminalView())
        view.frame = bounds
        view.autoresizingMask = [.width, .height]
        addSubview(view)
        hostingView = view
    }

    func syncHostedView() {
        hostingView?.rootView = terminalView()
    }

    func terminalView() -> AnyView {
        guard let terminal else { return AnyView(Color.clear) }
        return AnyView(TermyEmbeddedTerminalSurface(
            controller: terminal,
            isFocused: isFocused && surfaceVisible && !overlayActive,
            isInputEnabled: surfaceVisible && !overlayActive,
            isSearchVisible: searchVisible,
            onFocus: { [weak self] in self?.onFocus?() },
            onSplitRight: { [weak self] in self?.requestSplit(direction: .horizontal, position: .second) },
            onSplitDown: { [weak self] in self?.requestSplit(direction: .vertical, position: .second) },
            onClosePane: { [weak self] in self?.onProcessExit?() },
            onClosePaneIfSplit: { [weak self] in self?.requestCloseIfSplit() ?? false },
            onShowSearch: { [weak self] in self?.startSearch() },
            onDismissSearch: { [weak self] in self?.endSearch() }
        ))
    }

    func requestSplit(direction: SplitDirection, position: SplitPosition) {
        onSplitRequest?(direction, position)
    }

    func requestCloseIfSplit() -> Bool {
        onProcessExit?()
        return true
    }

    func flushInjectedCommandIfNeeded() {
        guard !injectedCommandSent, let injectedCommand, terminal != nil else { return }
        injectedCommandSent = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.terminal?.sendText(injectedCommand)
            self?.terminal?.sendReturnKey()
        }
    }
}
