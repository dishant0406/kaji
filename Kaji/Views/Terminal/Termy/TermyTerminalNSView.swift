import AppKit
import SwiftUI
import TermySwiftEmbed

final class TermyTerminalNSView: NSView {
    let workingDirectory: String
    let command: String?
    var envVars: [(key: String, value: String)] = []
    var injectedCommand: String?
    var injectedCommandSent = false
    var onTitleChange: ((String) -> Void)?
    var onFocus: (() -> Void)?
    var onProcessExit: (() -> Void)?
    var onSplitRequest: ((SplitDirection, SplitPosition) -> Void)?
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
    var closesOnCommandExit: Bool { command != nil }

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
        self.terminal = terminal
        processExitHandled = false
        installHostingView()
        if surfaceVisible {
            startStatePolling()
        }
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
        destroySurface()
        removeFromSuperview()
    }

    func setInjectedCommand(_ command: String?) {
        let normalized = command?.trimmingCharacters(in: .whitespacesAndNewlines)
        injectedCommand = normalized?.isEmpty == false ? normalized : nil
        injectedCommandSent = false
        flushInjectedCommandIfNeeded()
    }

    func foregroundProcessGroupID() -> Int32? {
        terminal?.foregroundProcessGroupID()
    }

    func ttyName() -> String? {
        nil
    }

    func visibleText() -> String? {
        terminal?.visibleText()
    }

    func needsConfirmQuit() -> Bool {
        terminal?.needsConfirmQuit() ?? false
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
    }

    func setSurfaceVisible(_ visible: Bool) {
        guard surfaceVisible != visible else {
            return
        }
        surfaceVisible = visible
        if visible {
            startStatePolling()
            terminal?.resume()
        } else {
            terminal?.suspend()
            stopStatePolling()
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
