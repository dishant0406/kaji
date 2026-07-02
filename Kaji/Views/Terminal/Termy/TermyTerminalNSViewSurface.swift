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
        guard terminal != nil, let command = injectedCommandDelivery.prepareDelivery() else { return }
        injectedCommandTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, let self else { return }
            guard let terminal else {
                injectedCommandDelivery.cancelPendingDelivery(command)
                return
            }
            guard injectedCommandDelivery.completePendingDelivery(command) else { return }
            injectedCommandTask = nil
            if surfaceVisible {
                terminal.resume()
            }
            terminal.sendText(command)
            terminal.sendReturnKey()
        }
    }
}
