import AppKit
import SwiftUI
import TermySwiftEmbed

final class TermyTerminalNSView: NSView {
    let workingDirectory: String
    let command: String?
    var envVars: [(key: String, value: String)] = []
    var injectedCommandDelivery = TerminalInjectedCommandDelivery()
    var injectedCommandTask: Task<Void, Never>?
    var onTitleChange: ((String) -> Void)?
    var onFocus: (() -> Void)?
    var onProcessExit: (() -> Void)?
    var onSplitRequest: ((SplitDirection, SplitPosition) -> Void)?
    var onHostCommand: ((NSEvent) -> Bool)?
    var onSearchStart: ((String?) -> Void)?
    var onSearchEnd: (() -> Void)?
    var onSearchTotal: ((Int?) -> Void)?
    var onSearchSelected: ((Int?) -> Void)?
    var surfaceVisible = true
    var searchVisible = false
    var terminal: TermyEmbeddedTerminal?
    var hostingView: NSHostingView<AnyView>?
    var titlePollTimer: Timer?
    var themeObserver: NSObjectProtocol?
    var lastTitle = "Shell"
    var processExitHandled = false
    var isFocused = false {
        didSet {
            guard oldValue != isFocused else { return }
            syncHostedView()
        }
    }

    var overlayActive = false {
        didSet {
            guard oldValue != overlayActive else { return }
            syncHostedView()
        }
    }

    init(workingDirectory: String, command: String? = nil) {
        self.workingDirectory = workingDirectory
        self.command = command
        super.init(frame: .zero)
        wantsLayer = true
        registerForDraggedTypes([.fileURL, .string])
        setAccessibilityRole(.textArea)
        setAccessibilityLabel("Terminal")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    enum SearchDirection: String {
        case next
        case previous
    }

    override var acceptsFirstResponder: Bool { false }
    override var isFlipped: Bool { true }
    var hasLiveSurface: Bool { terminal != nil && !processExitHandled }
    var hasTerminalRuntime: Bool { terminal != nil }
    var isTerminalSurfaceVisible: Bool { surfaceVisible }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { createSurface() }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        hostingView?.frame = bounds
    }

    func createSurface() {
        guard terminal == nil else { return }
        let terminal = TermyEmbeddedTerminal(
            workingDirectory: workingDirectory,
            command: command,
            envVars: envVars,
            configurationSource: .path(KajiConfig.shared.termyConfigPath)
        )
        terminal.onExit = { [weak self] in
            self?.handleProcessExit()
        }
        self.terminal = terminal
        processExitHandled = false
        installHostingView()
        startStatePolling()
        startThemeObservation()
        terminal.start()
        if !surfaceVisible {
            terminal.suspend()
        }
        flushInjectedCommandIfNeeded()
    }

    func destroySurface() {
        stopThemeObservation()
        stopStatePolling()
        injectedCommandTask?.cancel()
        injectedCommandTask = nil
        injectedCommandDelivery.cancelPendingDelivery()
        terminal?.onExit = nil
        terminal?.stop()
        terminal = nil
        hostingView?.removeFromSuperview()
        hostingView = nil
    }

    func tearDown() {
        onTitleChange = nil
        onFocus = nil
        onProcessExit = nil
        onSplitRequest = nil
        onHostCommand = nil
        destroySurface()
        removeFromSuperview()
    }

    func setInjectedCommand(_ command: String?) {
        if injectedCommandDelivery.setCommand(command) {
            injectedCommandTask?.cancel()
            injectedCommandTask = nil
        }
        flushInjectedCommandIfNeeded()
    }

    func notifySurfaceFocused() {
        isFocused = true
        terminal?.setFocused(true)
        if surfaceVisible {
            terminal?.resume()
        }
        DispatchQueue.main.async { [weak self] in self?.focusKeyboardCapture() }
    }

    func notifySurfaceUnfocused() {
        isFocused = false
        terminal?.setFocused(false)
        clearFirstResponderIfOwned()
    }

    func setSurfaceVisible(_ visible: Bool) {
        guard surfaceVisible != visible else {
            if visible {
                startStatePolling()
                terminal?.resume()
            } else {
                clearFirstResponderIfOwned()
                terminal?.suspend()
            }
            return
        }
        surfaceVisible = visible
        if visible {
            startStatePolling()
            terminal?.resume()
        } else {
            clearFirstResponderIfOwned()
            terminal?.suspend()
        }
        syncHostedView()
    }

    func startThemeObservation() {
        stopThemeObservation()
        themeObserver = NotificationCenter.default.addObserver(
            forName: .themeDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.terminal?.reloadConfiguration()
            }
        }
    }

    func stopThemeObservation() {
        guard let themeObserver else { return }
        NotificationCenter.default.removeObserver(themeObserver)
        self.themeObserver = nil
    }
}
