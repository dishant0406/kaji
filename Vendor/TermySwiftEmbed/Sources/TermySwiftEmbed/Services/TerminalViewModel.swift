import AppKit
import Darwin
import Foundation

@MainActor
final class TerminalViewModel: ObservableObject {
    @Published private(set) var frame: TerminalFrame = .empty
    @Published private(set) var errorMessage: String?
    @Published private(set) var renderConfig = TerminalRenderConfig.default
    @Published private(set) var title = "Shell"
    @Published private(set) var progress = TerminalProgress.clear
    @Published private(set) var isExited = false
    @Published private(set) var hasVisibleContent = false
    @Published private(set) var frameMetadata = TerminalFrameMetadata.empty
    @Published private(set) var canCopySelection = false
    @Published private(set) var currentWorkingDirectory: String?
    @Published private(set) var searchMatches: [TerminalSearchMatch] = []
    @Published private(set) var activeSearchMatchIndex = 0
    @Published private(set) var hoveredLink: TerminalFrameLink?
    @Published private(set) var debugMetrics = TerminalDebugMetrics.empty
    /// Bumped whenever the cached render plan changes, so the grid view redraws.
    /// The plan itself lives in `renderPlanCache` (not `@Published`) to avoid
    /// diffing large arrays on every frame.
    @Published private(set) var renderRevision = 0
    @Published private(set) var renderDamage = TerminalDamage.full
    /// Bumped on each terminal bell so the surface view can flash a visual bell.
    @Published private(set) var bellPulse = 0
    /// In-progress IME composition text, rendered inline at the cursor.
    @Published private(set) var markedText = ""
    /// Absolute scrollback rows where shell prompts started (OSC 133;A), shown
    /// as command marks in the scrollbar.
    @Published private(set) var commandMarkRows: [Int] = []
    /// Marks are exact only while history stays below the scrollback cap; once
    /// the buffer fills, eviction would drift them, so tracking stops.
    private var commandMarkTrackingActive = true
    var onExit: (() -> Void)?

    func setMarkedText(_ text: String) {
        markedText = text
    }

    @discardableResult
    func applyTerminalTitle(_ rawTitle: String) -> Bool {
        let nextTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nextTitle.isEmpty, title != nextTitle else {
            return false
        }
        title = nextTitle
        NotificationCenter.default.post(name: .termyNativeTabsChanged, object: nil)
        return true
    }

    @discardableResult
    func resetTerminalTitle() -> Bool {
        guard title != "Shell" else {
            return false
        }
        title = "Shell"
        NotificationCenter.default.post(name: .termyNativeTabsChanged, object: nil)
        return true
    }

    /// Host-driven cursor blink visibility; the grid view skips the cursor
    /// while this is `false`. Ticked from the refresh driver in
    /// `pollAndPresent()` so blinking follows the active/idle cadence and
    /// pauses with suspended (occluded) tabs.
    @Published private(set) var cursorBlinkVisible = true
    @Published var selection: TerminalSelection?

    /// The flattened paint instructions for the current frame, rebuilt
    /// incrementally from damage in `pollAndPresent()`.
    var renderPlan: TerminalRenderPlan { renderPlanCache.plan }
    private let renderPlanCache = TerminalRenderPlanCache()
    private let frameStore = TerminalFrameStore()
    private let nativeRenderMetricsRecorder = NativeRenderMetricsRecorder()

    private var terminal: LibTermyTerminal?
    private var cursorBlinkPhase = TerminalCursorBlinkPhase()
    /// Whether the hosting pane is focused (pushed in by the surface view).
    /// Unfocused panes never draw a cursor, so they skip blink ticking and idle
    /// at the slower inert cadence instead of the blink interval.
    private var isPaneFocused = true
    private var baseRenderConfig = TerminalRenderConfig.default
    private var fontSizeDelta: CGFloat = 0
    private var refreshDriver: DisplaySyncedRefreshDriver?
    private var cadence: RefreshCadence = .active
    private var lastActivityAt = Date()
    private static let idleCadenceThreshold: TimeInterval = 0.4
    private static let liveSearchRefreshInterval: TimeInterval = 0.15
    private var lastResize: TerminalResize?
    private var pendingResizeRefresh: Task<Void, Never>?
    private var lastResizeRefreshAt: Date?
    private var isSuspended = false
    private static let resizeRefreshInterval: TimeInterval = 1.0 / 60.0
    /// Owns the settings/appearance notification observers. Removing them in
    /// `stop()` covers the normal teardown, but a window closing can deallocate
    /// the view model without routing through `stop()`; the bag's own `deinit`
    /// then removes the observers, so they don't accumulate for the process
    /// lifetime. (A nonisolated `deinit` on this `@MainActor` class can't touch
    /// these non-Sendable tokens directly, hence the separate bag.)
    private let observers = NotificationObserverBag()
    private var startupRefreshUntil: Date?
    private let initialWorkingDirectory: String?
    private let startupCommand: String?
    private let tmuxSessionHint: String
    private let envVars: [(key: String, value: String)]
    private let configurationSource: TermyConfigurationSource
    private var configuration = TermyRuntimeConfiguration.default
    private var activeSearchQuery = ""
    private var activeSearchOptions = TerminalSearchOptions()
    private var lastSearchRefreshAt: Date?
    private var lastAutoCopiedSelectionText: String?
    private var pendingWakeupPoll = false
    private var inputEchoRefreshPolicy = TerminalInputEchoRefreshPolicy()
    private var inputEchoFallbackTask: Task<Void, Never>?
    private var renderedFrameCount = 0
    private var skippedPresentCount = 0
    private var fullRebuildCount = 0
    private var partialRebuildCount = 0
    private var lastDebugSample = ProcessUsageSample.capture()
    private var cachedLinkRowsRevision: Int?
    private var cachedLinkRows: [Int: [TerminalFrameLink]] = [:]

    init(
        workingDirectory: String? = nil,
        startupCommand: String? = nil,
        tmuxSessionHint: String = UUID().uuidString,
        restoredBufferText: String? = nil,
        envVars: [(key: String, value: String)] = [],
        configurationSource: TermyConfigurationSource = .defaultConfig
    ) {
        initialWorkingDirectory = TerminalViewModel.normalizedWorkingDirectory(workingDirectory)
        self.startupCommand = TerminalViewModel.normalizedStartupCommand(startupCommand)
        self.tmuxSessionHint = tmuxSessionHint
        self.envVars = envVars
        self.configurationSource = configurationSource
        if let restoredBufferText = Self.normalizedRestoredBufferText(restoredBufferText) {
            let previewFrame = TerminalFrame.plainTextPreview(restoredBufferText)
            frameStore.reset(to: previewFrame)
            frame = previewFrame
            hasVisibleContent = frameStore.hasVisibleContent
            frameMetadata = TerminalFrameMetadata(frame: previewFrame)
            canCopySelection = canCopy(selection, in: previewFrame)
            renderPlanCache.update(
                frame: previewFrame,
                renderConfig: renderConfig,
                damage: .full
            )
        }
    }

    func start() {
        guard terminal == nil else {
            return
        }

        do {
            configuration = TermyRuntimeConfigurationLoader.loadOrDefault(source: configurationSource)
            let terminal = try LibTermyTerminal(
                configurationSource: configurationSource,
                workingDirectoryOverride: initialWorkingDirectory,
                startupCommand: startupCommand,
                envVars: envVars
            )
            self.terminal = terminal
            applyConfiguredScrollbackLimit()
            terminal.startWakeupMonitor { [weak self] in
                self?.handleTerminalWakeup()
            }
            applyBaseRenderConfig(terminal.renderConfig)
            currentWorkingDirectory = initialWorkingDirectory
            isExited = false
            startupRefreshUntil = Date().addingTimeInterval(2)
            pollAndPresent(force: true)
            startRefreshDriver(.active)
            observers.add(
                NotificationCenter.default.addObserver(
                    forName: .termySettingsChanged,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in
                        self?.reloadConfiguration()
                    }
                },
                center: .default
            )
            observers.add(
                DistributedNotificationCenter.default().addObserver(
                    forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in
                        self?.reloadAppearance()
                    }
                },
                center: DistributedNotificationCenter.default()
            )
        } catch {
            report(error)
        }
    }

    /// Drives presentation from display refresh boundaries while active, then
    /// backs off to a low-rate idle timer for cursor blink. PTY output uses the
    /// FFI wake channel to schedule an immediate poll while idle, so visible
    /// terminals do not need to keep polling for changes.
    private func startRefreshDriver(_ cadence: RefreshCadence) {
        self.cadence = cadence
        if let refreshDriver {
            guard refreshDriver.cadence != cadence else {
                return
            }
            refreshDriver.stop()
            refreshDriver.start(cadence: cadence)
            return
        }
        let driver = DisplaySyncedRefreshDriver { [weak self] in
            self?.pollAndPresent()
        }
        refreshDriver = driver
        driver.start(cadence: cadence)
    }

    private func handleTerminalWakeup() {
        guard terminal != nil,
              !pendingWakeupPoll,
              inputEchoRefreshPolicy.acceptsWakeup(cadence: cadence, isSuspended: isSuspended)
        else {
            return
        }
        let inputGeneration = inputEchoRefreshPolicy.activeInputGenerationForWakeup(cadence: cadence)
        pendingWakeupPoll = true
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            self.pendingWakeupPoll = false
            if self.isSuspended {
                self.drainEventsWhileSuspended()
            } else {
                let outcome = self.pollAndPresent()
                if let inputGeneration {
                    self.recordInputEchoPoll(upTo: inputGeneration, outcome: outcome)
                }
            }
        }
    }

    /// While a tab is suspended (its window is occluded), we deliberately keep the
    /// wakeup monitor running and drain PTY events without presenting a frame.
    /// This is intentional: a fully-stopped backgrounded shell would block once
    /// the PTY buffer fills (e.g. a build logging in a hidden tab), so we consume
    /// output to keep it flowing. Draining without rendering is far cheaper than a
    /// full `pollAndPresent`, so the occlusion CPU savings are largely preserved.
    private func drainEventsWhileSuspended() {
        do {
            try handle(terminal?.drainEvents() ?? [])
        } catch {
            report(error)
        }
    }

    private func noteActivity() {
        lastActivityAt = Date()
        if cadence != .active {
            startRefreshDriver(.active)
        }
    }

    private func adaptCadenceWhenIdle() {
        let idleCadence = Self.idleCadence(
            cursorBlink: renderConfig.cursorBlink,
            paneFocused: isPaneFocused
        )
        if cadence == .active {
            guard Date().timeIntervalSince(lastActivityAt) > Self.idleCadenceThreshold else {
                return
            }
            startRefreshDriver(idleCadence)
            return
        }
        // Already idle, but the blink relevance may have changed (focus moved,
        // config reloaded) — switch between the blink and inert idle cadences.
        if cadence != idleCadence {
            startRefreshDriver(idleCadence)
        }
    }

    /// The idle cadence for the current blink relevance: panes that animate a
    /// blinking cursor poll at the blink interval; panes with nothing to animate
    /// (blink disabled, or unfocused — no cursor is drawn) only need the slow
    /// safety poll, as output wakes them through the FFI wake channel.
    nonisolated static func idleCadence(cursorBlink: Bool, paneFocused: Bool) -> RefreshCadence {
        cursorBlink && paneFocused ? .idle : .idleInert
    }

    /// Pushed by the surface view when pane focus changes. Restores a solid
    /// cursor on focus gain and re-evaluates the idle cadence either way.
    func setPaneFocused(_ focused: Bool) {
        guard focused != isPaneFocused else {
            return
        }
        isPaneFocused = focused
        if focused {
            resetCursorBlinkPhase()
        }
        guard terminal != nil, !isSuspended, cadence != .active else {
            return
        }
        startRefreshDriver(Self.idleCadence(
            cursorBlink: renderConfig.cursorBlink,
            paneFocused: focused
        ))
    }

    /// Pauses refresh polling without tearing down the PTY, so the terminal core
    /// keeps running and buffers output while the hosting tab/window is occluded.
    /// This stops occluded background tabs from competing for the main run loop
    /// (e.g. while a divider is being dragged in the visible window).
    func suspendRefresh() {
        guard terminal != nil, !isSuspended else {
            return
        }
        isSuspended = true
        applyConfiguredScrollbackLimit()
        refreshDriver?.stop()
        refreshDriver = nil
        pendingResizeRefresh?.cancel()
        pendingResizeRefresh = nil
    }

    /// Resumes polling when the tab/window becomes visible again and forces one
    /// refresh to catch up on output that accumulated while suspended.
    func resumeRefresh() {
        guard terminal != nil, isSuspended else {
            return
        }
        isSuspended = false
        applyConfiguredScrollbackLimit()
        terminal?.startWakeupMonitor { [weak self] in
            self?.handleTerminalWakeup()
        }
        startRefreshDriver(.active)
        pollAndPresent(force: true)
    }

    func stop() {
        refreshDriver?.stop()
        refreshDriver = nil
        terminal?.stopWakeupMonitor()
        pendingResizeRefresh?.cancel()
        pendingResizeRefresh = nil
        inputEchoFallbackTask?.cancel()
        inputEchoFallbackTask = nil
        inputEchoRefreshPolicy.reset()
        pendingWakeupPoll = false
        isSuspended = false
        observers.removeAll()
        terminal = nil
        isExited = true
        progress = .clear
        startupRefreshUntil = nil
    }

    private func reloadAppearance() {
        do {
            let nextRenderConfig = try terminal?.reloadConfiguration(from: configurationSource)
                ?? LibTermyTerminal.loadRenderConfig(configurationSource: configurationSource)
            applyBaseRenderConfig(nextRenderConfig)
            pollAndPresent(force: true)
        } catch {
            report(error)
        }
    }

    func reloadConfiguration() {
        configuration = TermyRuntimeConfigurationLoader.loadOrDefault(source: configurationSource)
        applyConfiguredScrollbackLimit()
        if !configuration.native.progressIndicatorEnabled {
            progress = .clear
        }
        reloadAppearance()
    }

    private func applyConfiguredScrollbackLimit() {
        guard terminal != nil else {
            return
        }
        let limit = isSuspended
            ? configuration.inactiveTabScrollback ?? configuration.scrollbackHistory
            : configuration.scrollbackHistory
        do {
            try terminal?.setScrollbackHistory(TermyRuntimeConfiguration.clampedScrollbackHistory(limit))
        } catch {
            report(error)
        }
    }

    func sendControlC() {
        send(bytes: [3])
    }

    func sendKey(_ keyInput: TerminalKeyInput) {
        do {
            guard let bytes = try terminal?.encodeKey(keyInput), !bytes.isEmpty else {
                return
            }
            send(bytes: bytes)
        } catch {
            report(error)
        }
    }

    func sendMouse(_ mouseInput: TerminalMouseInput) -> Bool {
        do {
            guard let bytes = try terminal?.encodeMouse(mouseInput), !bytes.isEmpty else {
                return false
            }
            send(bytes: bytes)
            return true
        } catch {
            report(error)
            return false
        }
    }

    /// Pastes clipboard text into the terminal. When the foreground program has
    /// enabled bracketed-paste mode the payload is wrapped in `ESC[200~`/
    /// `ESC[201~` so the program treats it as inert data instead of typed input;
    /// any embedded end-marker is stripped first so the paste cannot break out
    /// of the brackets and inject commands. This is the standard mitigation for
    /// clipboard-injection (e.g. a copied blob ending in `; rm -rf …\n`): without
    /// it, embedded newlines execute line-by-line on paste.
    func paste(_ text: String) {
        guard !text.isEmpty else {
            return
        }

        let bracketed = (try? terminal?.bracketedPasteMode()) ?? false
        guard bracketed else {
            send(bytes: Array(text.utf8))
            return
        }

        // Strip embedded bracketed-paste markers so the payload can't close
        // the bracket early or smuggle a nested framed paste sequence.
        let sanitized = text
            .replacingOccurrences(of: "\u{1b}[200~", with: "")
            .replacingOccurrences(of: "\u{1b}[201~", with: "")
        var bytes = Array("\u{1b}[200~".utf8)
        bytes.append(contentsOf: sanitized.utf8)
        bytes.append(contentsOf: Array("\u{1b}[201~".utf8))
        send(bytes: bytes)
    }

    func send(bytes: [UInt8]) {
        guard !bytes.isEmpty else {
            return
        }

        updateSelection(nil)
        if frame.displayOffset > 0 {
            scrollToBottom()
        }
        do {
            try terminal?.write(bytes)
            let inputGeneration = inputEchoRefreshPolicy.noteInput()
            scheduleInputEchoFallback()
            noteActivity()
            resetCursorBlinkPhase()
            // Don't force a full-grid frame on input: `noteActivity()` keeps the
            // display link at the active 60 Hz cadence, and the echo arrives as
            // ordinary partial damage. Forcing here serialized the entire grid
            // across the FFI (three full copies) and repainted the whole window
            // on every keystroke and scroll-wheel tick.
            let outcome = pollAndPresent()
            recordInputEchoPoll(upTo: inputGeneration, outcome: outcome)
        } catch {
            report(error)
        }
    }

    private func scheduleInputEchoFallback() {
        guard inputEchoFallbackTask == nil else {
            return
        }
        inputEchoFallbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(8))
            guard !Task.isCancelled, let self else {
                return
            }
            self.inputEchoFallbackTask = nil
            guard self.inputEchoRefreshPolicy.hasPendingInput else {
                return
            }
            guard let generation = self.inputEchoRefreshPolicy.pendingInputGenerationForRefresh else {
                return
            }
            if self.isSuspended {
                self.drainEventsWhileSuspended()
                self.recordInputEchoPoll(upTo: generation, outcome: .empty)
            } else {
                let outcome = self.pollAndPresent()
                self.recordInputEchoPoll(upTo: generation, outcome: outcome)
            }
        }
    }

    private func recordInputEchoPoll(upTo generation: UInt64, outcome: TerminalPollOutcome) {
        inputEchoRefreshPolicy.recordPoll(
            upTo: generation,
            observedFrameActivity: outcome.hasInputEchoActivity
        )
        guard !inputEchoRefreshPolicy.hasPendingInput else {
            scheduleInputEchoFallback()
            return
        }
        inputEchoFallbackTask?.cancel()
        inputEchoFallbackTask = nil
    }

    /// Forces the cursor solid and restarts the blink interval, e.g. on input
    /// or when the pane gains focus.
    func resetCursorBlinkPhase() {
        cursorBlinkPhase.noteInput()
        if !cursorBlinkVisible {
            cursorBlinkVisible = true
        }
    }

    func scrollDisplay(deltaLines: Int) {
        guard deltaLines != 0 else {
            return
        }

        let clampedDelta = max(Int(Int32.min), min(Int(Int32.max), deltaLines))
        refreshIfChanged {
            try terminal?.scrollDisplay(deltaLines: Int32(clampedDelta)) == true
        }
    }

    func scrollToBottom() {
        refreshIfChanged {
            try terminal?.scrollToBottom() == true
        }
    }

    func scrollToDisplayOffset(_ offset: Int) {
        let targetOffset = max(0, min(offset, frame.historySize))
        scrollDisplay(deltaLines: targetOffset - frame.displayOffset)
    }

    func scrollToTop() {
        scrollToDisplayOffset(frame.historySize)
    }

    func clearScrollback() {
        commandMarkRows.removeAll()
        commandMarkTrackingActive = true
        refreshIfChanged {
            try terminal?.clearScrollback() == true
        }
    }

    func increaseFontSize() {
        adjustFontSize(by: 1)
    }

    func decreaseFontSize() {
        adjustFontSize(by: -1)
    }

    func resetFontSize() {
        guard fontSizeDelta != 0 else {
            return
        }
        fontSizeDelta = 0
        applyRenderConfig(baseRenderConfig, forceFullRebuild: true)
    }

    private func adjustFontSize(by delta: CGFloat) {
        let currentFontSize = baseRenderConfig.fontSize + fontSizeDelta
        let nextFontSize = Self.clampedFontSize(currentFontSize + delta)
        let nextDelta = nextFontSize - baseRenderConfig.fontSize
        guard nextDelta != fontSizeDelta else {
            return
        }
        fontSizeDelta = nextDelta
        applyRenderConfig(zoomedRenderConfig(from: baseRenderConfig), forceFullRebuild: true)
    }

    func updateSelection(_ selection: TerminalSelection?) {
        self.selection = selection
        canCopySelection = canCopy(selection, in: frame)
        guard renderConfig.copyOnSelect,
              let text = selectedText(for: selection),
              !text.isEmpty
        else {
            lastAutoCopiedSelectionText = nil
            return
        }
        guard text != lastAutoCopiedSelectionText else {
            return
        }
        copy(text)
        lastAutoCopiedSelectionText = text
    }

    /// Double-click: select the word under the cursor.
    func selectWord(at position: TerminalGridPosition) {
        guard let selection = frame.wordSelection(at: position) else {
            updateSelection(nil)
            return
        }
        updateSelection(selection)
    }

    /// Triple-click: select the whole line under the cursor.
    func selectLine(at position: TerminalGridPosition) {
        updateSelection(frame.lineSelection(at: position))
    }

    func selectAll() {
        guard frame.cols > 0, frame.rows > 0 else {
            updateSelection(nil)
            return
        }
        updateSelection(TerminalSelection(
            anchor: TerminalBufferPosition(col: 0, row: 0),
            active: TerminalBufferPosition(
                col: frame.cols - 1,
                row: max(0, frame.historySize + frame.rows - 1)
            )
        ))
    }

    /// The link under `position`: an OSC 8 hyperlink reported by the core when
    /// present, otherwise heuristic text detection on the frame.
    private func link(at position: TerminalGridPosition) -> TerminalFrameLink? {
        if let link = terminal?.hyperlink(atRow: position.row, col: position.col) {
            return link
        }
        return links(inRow: position.row).first {
            position.col >= $0.startCol && position.col <= $0.endCol
        }
    }

    private func links(inRow row: Int) -> [TerminalFrameLink] {
        guard row >= 0, row < frame.rows else {
            return []
        }
        if cachedLinkRowsRevision != renderRevision {
            cachedLinkRowsRevision = renderRevision
            cachedLinkRows.removeAll(keepingCapacity: true)
        }
        if let links = cachedLinkRows[row] {
            return links
        }
        let links = frame.links(inRow: row)
        cachedLinkRows[row] = links
        return links
    }

    /// Updates the link highlighted under the pointer. Returns true when a link
    /// is present so the view can show the pointing-hand cursor.
    @discardableResult
    func updateHoveredLink(at position: TerminalGridPosition?) -> Bool {
        let link = position.flatMap { self.link(at: $0) }
        if link != hoveredLink {
            hoveredLink = link
        }
        return link != nil
    }

    /// Opens the link under `position` (⌘-click). Returns true if one was opened.
    /// The target is validated against a scheme allowlist first: an OSC 8
    /// hyperlink's target comes straight from (attacker-influenced) terminal
    /// output, so a disguised `file://` or custom-scheme URL must not reach
    /// `NSWorkspace.open`.
    func openLink(at position: TerminalGridPosition) -> Bool {
        guard let link = link(at: position),
              let url = TerminalFrameLink.openableURL(for: link.target)
        else {
            return false
        }
        return NSWorkspace.shared.open(url)
    }

    func copySelection() -> Bool {
        guard let text = selectedText(for: selection), !text.isEmpty else {
            return false
        }

        copy(text)
        return true
    }

    private func selectedText(for selection: TerminalSelection?) -> String? {
        guard let selection else {
            return nil
        }
        if let text = try? terminal?.selectedText(for: selection), !text.isEmpty {
            return text
        }
        return frame.selectedText(for: selection)
    }

    private func canCopy(_ selection: TerminalSelection?, in frame: TerminalFrame) -> Bool {
        guard let selection, !selection.isEmpty else {
            return false
        }
        return frame.hasSelectedText(for: selection) || selection.normalized.start.row < selection.normalized.end.row
    }

    func search(
        _ query: String,
        options: TerminalSearchOptions = TerminalSearchOptions()
    ) -> [TerminalSearchMatch] {
        do {
            return try terminal?.search(query, options: options) ?? []
        } catch {
            report(error)
            return []
        }
    }

    func updateSearch(
        _ query: String,
        options: TerminalSearchOptions = TerminalSearchOptions()
    ) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            activeSearchQuery = ""
            activeSearchOptions = options
            searchMatches = []
            activeSearchMatchIndex = 0
            lastSearchRefreshAt = nil
            return
        }

        let shouldResetActiveMatch = trimmedQuery != activeSearchQuery || options != activeSearchOptions
        activeSearchQuery = trimmedQuery
        activeSearchOptions = options
        refreshSearchMatches(resetActive: shouldResetActiveMatch, revealActive: true, force: true)
    }

    func selectNextSearchMatch() {
        guard !searchMatches.isEmpty else {
            return
        }
        activeSearchMatchIndex = (activeSearchMatchIndex + 1) % searchMatches.count
        revealActiveSearchMatch()
    }

    func selectPreviousSearchMatch() {
        guard !searchMatches.isEmpty else {
            return
        }
        activeSearchMatchIndex = (activeSearchMatchIndex + searchMatches.count - 1) % searchMatches.count
        revealActiveSearchMatch()
    }

    func resize(cols: Int, rows: Int, cellWidth: CGFloat, cellHeight: CGFloat) {
        let cols = max(2, min(cols, Int(UInt16.max)))
        let rows = max(2, min(rows, Int(UInt16.max)))
        let resize = TerminalResize(
            cols: UInt16(cols),
            rows: UInt16(rows),
            cellWidth: Float(cellWidth),
            cellHeight: Float(cellHeight)
        )
        guard resize != lastResize else {
            return
        }
        lastResize = resize

        do {
            // The FFI resize is cheap and keeps the PTY winsize correct, so run
            // it every step. The expensive forced refresh (full frame update +
            // plan rebuild + row renderer repaint) is throttled below so a
            // continuous drag — e.g. dragging a split divider, which crosses a
            // cell boundary every few pixels — does not block the main run loop
            // on every step.
            try terminal?.resize(
                cols: resize.cols,
                rows: resize.rows,
                cellWidth: resize.cellWidth,
                cellHeight: resize.cellHeight
            )
            guard !isSuspended else {
                return
            }
            // Resizing is user activity: keep the refresh driver at the active
            // cadence so reflowed output arriving mid-drag presents at 60 Hz.
            noteActivity()
            scheduleResizeRefresh()
        } catch {
            report(error)
        }
    }

    /// Coalesces the forced refresh during a continuous resize. Runs immediately
    /// when idle, then at most once per `resizeRefreshInterval`, always with a
    /// trailing refresh so the final drag size is rendered. `lastResize` already
    /// captured the latest dimensions synchronously, so the trailing snapshot
    /// reflects the end state.
    private func scheduleResizeRefresh() {
        let now = Date()
        if let last = lastResizeRefreshAt,
           now.timeIntervalSince(last) < Self.resizeRefreshInterval
        {
            guard pendingResizeRefresh == nil else {
                return
            }
            let delay = Self.resizeRefreshInterval - now.timeIntervalSince(last)
            pendingResizeRefresh = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard let self, !Task.isCancelled else {
                    return
                }
                self.pendingResizeRefresh = nil
                self.lastResizeRefreshAt = Date()
                self.pollAndPresent(force: true)
            }
            return
        }
        lastResizeRefreshAt = now
        pollAndPresent(force: true)
    }

    @discardableResult
    private func pollAndPresent(force: Bool = false) -> TerminalPollOutcome {
        do {
            let events = try terminal?.drainEvents() ?? []
            handle(events)
            let forceFull = force || shouldForceStartupRefresh()
            let update = try terminal?.frameUpdate(forceFull: forceFull)
            let applyResult = update.map(frameStore.apply)
                ?? TerminalFrameStoreApplyResult(
                    changed: false,
                    effectiveDamage: .none,
                    patchedCellCount: 0
                )
            let baseOutcome = TerminalPollOutcome(
                receivedEvents: !events.isEmpty,
                patchedCellCount: applyResult.patchedCellCount,
                changedFrame: applyResult.changed,
                publishedFrame: false,
                forcedFullRefresh: forceFull
            )
            if let update {
                nativeRenderMetricsRecorder.recordFrameUpdate(update, applyResult: applyResult)
            }
            if Self.hasCadenceActivity(
                events: events,
                patchedCellCount: applyResult.patchedCellCount,
                forceFull: forceFull,
                changed: applyResult.changed
            ) {
                noteActivity()
            } else {
                adaptCadenceWhenIdle()
            }

            // Only the focused pane draws a cursor, so only it animates blink;
            // unfocused panes settle to a solid (visible) phase.
            let blinkToggled = cursorBlinkPhase.tick(
                blinkEnabled: renderConfig.cursorBlink && isPaneFocused
            )
            if blinkToggled {
                cursorBlinkVisible = cursorBlinkPhase.isVisible
            }

            guard forceFull || applyResult.changed else {
                presentCursorBlink(toggled: blinkToggled)
                updateDebugMetrics(renderedFrame: false)
                return baseOutcome
            }

            guard update != nil else {
                presentCursorBlink(toggled: blinkToggled)
                updateDebugMetrics(renderedFrame: false)
                return baseOutcome
            }

            publishFrameState()
            // Once the scrollback fills, eviction would drift recorded marks, so
            // stop tracking and drop them rather than show stale positions.
            if commandMarkTrackingActive,
               configuration.scrollbackHistory > 0,
               frame.historySize >= configuration.scrollbackHistory
            {
                commandMarkTrackingActive = false
                commandMarkRows.removeAll()
            }
            errorMessage = nil
            let effectiveDamage = forceFull ? .full : applyResult.effectiveDamage
            // Fold the cursor cell into the published damage on a blink toggle
            // so the grid view repaints the cursor row alongside the frame's
            // own dirty rows. The plan cache below keeps the narrower
            // `effectiveDamage`: a blink changes no cell content.
            if blinkToggled, let cursor = frame.cursor {
                renderDamage = effectiveDamage.union(
                    TerminalDirtySpan(row: cursor.row, leftCol: cursor.col, rightCol: cursor.col)
                )
            } else {
                renderDamage = effectiveDamage
            }
            renderPlanCache.update(
                frame: frame,
                renderConfig: renderConfig,
                damage: effectiveDamage
            )
            nativeRenderMetricsRecorder.recordPresentedFrame(planStats: renderPlanCache.stats)
            renderRevision &+= 1
            updateDebugMetrics(renderedFrame: true)
            refreshSearchMatches(resetActive: false, revealActive: false, force: false)
            return TerminalPollOutcome(
                receivedEvents: baseOutcome.receivedEvents,
                patchedCellCount: baseOutcome.patchedCellCount,
                changedFrame: baseOutcome.changedFrame,
                publishedFrame: true,
                forcedFullRefresh: baseOutcome.forcedFullRefresh
            )
        } catch {
            report(error)
            return .empty
        }
    }

    /// Publishes a cursor-cell-only damage span when a blink toggle happens on
    /// a tick that presented no new frame, so the grid view repaints just the
    /// cursor row instead of re-applying stale (possibly full) damage.
    private func presentCursorBlink(toggled: Bool) {
        guard toggled, let cursor = frame.cursor, frame.displayOffset == 0 else {
            return
        }
        renderDamage = .partial([
            TerminalDirtySpan(row: cursor.row, leftCol: cursor.col, rightCol: cursor.col),
        ])
    }

    private func publishFrameState() {
        frame = frameStore.frame
        hasVisibleContent = frameStore.hasVisibleContent
        frameMetadata = TerminalFrameMetadata(frame: frame)
        canCopySelection = canCopy(selection, in: frame)
    }

    private func shouldForceStartupRefresh() -> Bool {
        guard let startupRefreshUntil else {
            return false
        }
        if Date() < startupRefreshUntil {
            return true
        }
        self.startupRefreshUntil = nil
        return false
    }

    private func refreshIfChanged(_ operation: () throws -> Bool) {
        do {
            if try operation() {
                pollAndPresent(force: true)
            }
        } catch {
            report(error)
        }
    }

    private func report(_ error: Error) {
        errorMessage = String(describing: error)
    }

    private func applyBaseRenderConfig(_ config: TerminalRenderConfig) {
        baseRenderConfig = config
        fontSizeDelta = Self.clampedFontSize(config.fontSize + fontSizeDelta) - config.fontSize
        applyRenderConfig(zoomedRenderConfig(from: config), forceFullRebuild: true)
    }

    private func zoomedRenderConfig(from config: TerminalRenderConfig) -> TerminalRenderConfig {
        let nextFontSize = Self.clampedFontSize(config.fontSize + fontSizeDelta)
        guard nextFontSize != config.fontSize else {
            return config
        }

        var nextConfig = config
        let scale = nextFontSize / config.fontSize
        nextConfig.fontSize = nextFontSize
        nextConfig.measuredCellWidth = max(1, config.measuredCellWidth * scale)
        nextConfig.measuredCellHeight = max(1, nextFontSize * config.lineHeight)
        return nextConfig
    }

    private func applyRenderConfig(_ config: TerminalRenderConfig, forceFullRebuild: Bool) {
        guard config != renderConfig else {
            return
        }

        renderConfig = config
        guard forceFullRebuild else {
            return
        }

        renderDamage = .full
        renderPlanCache.update(
            frame: frame,
            renderConfig: config,
            damage: .full
        )
        renderRevision &+= 1
    }

    private static func clampedFontSize(_ fontSize: CGFloat) -> CGFloat {
        min(72, max(6, fontSize))
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func updateDebugMetrics(renderedFrame: Bool) {
        // `debugMetrics` only has a consumer while the debug overlay is shown.
        // Skipping this when it's off avoids a `getrusage` + `task_info` syscall
        // pair (and counter bookkeeping) on every refresh tick — 60 Hz active,
        // and otherwise pure idle cost.
        guard configuration.native.showDebugOverlay else {
            return
        }

        if renderedFrame {
            renderedFrameCount += 1
            if renderPlanCache.stats.wasFullRebuild {
                fullRebuildCount += 1
            } else {
                partialRebuildCount += 1
            }
        } else {
            skippedPresentCount += 1
            nativeRenderMetricsRecorder.recordSkippedPresent()
        }

        let nextSample = ProcessUsageSample.capture()
        let elapsed = nextSample.timestamp.timeIntervalSince(lastDebugSample.timestamp)
        guard elapsed >= 1 else {
            return
        }

        let fps = Double(renderedFrameCount) / elapsed
        let cpuDelta = max(0, nextSample.cpuTime - lastDebugSample.cpuTime)
        debugMetrics = TerminalDebugMetrics(
            framesPerSecond: fps,
            cpuPercent: min(999, (cpuDelta / elapsed) * 100),
            memoryMegabytes: nextSample.memoryMegabytes,
            skippedPresentsPerSecond: Double(skippedPresentCount) / elapsed,
            fullRebuildsPerSecond: Double(fullRebuildCount) / elapsed,
            partialRebuildsPerSecond: Double(partialRebuildCount) / elapsed
        )
        renderedFrameCount = 0
        skippedPresentCount = 0
        fullRebuildCount = 0
        partialRebuildCount = 0
        lastDebugSample = nextSample
    }

    private func refreshSearchMatches(resetActive: Bool, revealActive: Bool, force: Bool) {
        guard !activeSearchQuery.isEmpty else {
            searchMatches = []
            activeSearchMatchIndex = 0
            lastSearchRefreshAt = nil
            return
        }

        let now = Date()
        guard force || resetActive || revealActive || shouldRefreshLiveSearch(at: now) else {
            return
        }

        let matches = search(activeSearchQuery, options: activeSearchOptions)
        lastSearchRefreshAt = now
        searchMatches = matches
        if matches.isEmpty {
            activeSearchMatchIndex = 0
            return
        }

        activeSearchMatchIndex = resetActive ? 0 : min(activeSearchMatchIndex, matches.count - 1)
        if revealActive {
            revealActiveSearchMatch()
        }
    }

    private func shouldRefreshLiveSearch(at now: Date) -> Bool {
        guard let lastSearchRefreshAt else {
            return true
        }
        return now.timeIntervalSince(lastSearchRefreshAt) >= Self.liveSearchRefreshInterval
    }

    private func revealActiveSearchMatch() {
        guard searchMatches.indices.contains(activeSearchMatchIndex), frame.rows > 0 else {
            return
        }

        let match = searchMatches[activeSearchMatchIndex]
        let visibleTop = frame.historySize - frame.displayOffset
        let visibleBottom = visibleTop + frame.rows - 1
        let targetOffset: Int
        if match.row < visibleTop {
            targetOffset = frame.historySize - match.row
        } else if match.row > visibleBottom {
            targetOffset = frame.historySize - (match.row - frame.rows + 1)
        } else {
            return
        }

        let clampedOffset = max(0, min(frame.historySize, targetOffset))
        scrollDisplay(deltaLines: clampedOffset - frame.displayOffset)
    }

    /// Rings the system bell and pulses the visual-bell signal.
    private func handleBell() {
        NSSound.beep()
        bellPulse &+= 1
    }

    /// Records a command mark at the prompt's absolute row. Only while shell
    /// integration is on and history is below the scrollback cap (so the
    /// absolute row can't have been shifted by eviction).
    /// Absolute scrollback row of a prompt at the given history/cursor position.
    nonisolated static func commandMarkAbsoluteRow(historySize: Int, cursorRow: Int) -> Int {
        historySize + cursorRow
    }

    /// Marks are exact only below the scrollback cap (eviction starts at the cap
    /// and would otherwise shift their absolute rows).
    nonisolated static func canTrackCommandMark(historySize: Int, scrollbackCap: Int) -> Bool {
        scrollbackCap > 0 && historySize < scrollbackCap
    }

    nonisolated static func hasActivityEvents(_ events: [TerminalRuntimeEvent]) -> Bool {
        events.contains { !$0.isPlainWakeup }
    }

    nonisolated static func hasCadenceActivity(
        events: [TerminalRuntimeEvent],
        patchedCellCount: Int,
        forceFull: Bool,
        changed: Bool
    ) -> Bool {
        hasActivityEvents(events) || patchedCellCount > 0 || (forceFull && changed)
    }

    private func recordCommandMark() {
        guard configuration.native.shellIntegrationEnabled,
              commandMarkTrackingActive,
              Self.canTrackCommandMark(
                  historySize: frame.historySize,
                  scrollbackCap: configuration.scrollbackHistory
              )
        else {
            return
        }
        commandMarkRows.append(Self.commandMarkAbsoluteRow(
            historySize: frame.historySize,
            cursorRow: frame.cursor?.row ?? 0
        ))
        if commandMarkRows.count > 200 {
            commandMarkRows.removeFirst(commandMarkRows.count - 200)
        }
    }

    private func handle(_ events: [TerminalRuntimeEvent]) {
        guard !events.isEmpty else {
            return
        }

        for event in events {
            switch event {
            case let .title(title):
                applyTerminalTitle(title)
            case .resetTitle:
                resetTerminalTitle()
            case .exit:
                if !isExited {
                    isExited = true
                    onExit?()
                }
                progress = .clear
            case let .progress(progress):
                if configuration.native.progressIndicatorEnabled {
                    self.progress = progress
                }
            case let .workingDirectory(path):
                currentWorkingDirectory = TerminalViewModel.normalizedWorkingDirectory(path)
            case let .clipboardStore(text):
                // OSC 52: an app (tmux, vim, ssh) asked to set the system
                // clipboard. The Rust side already base64-decodes the payload.
                if !text.isEmpty {
                    copy(text)
                }
            case .bell:
                handleBell()
            case .shellPromptStart:
                recordCommandMark()
            case .wakeup,
                 .shellCommandStart,
                 .shellCommandExecuting,
                 .shellCommandFinished:
                guard configuration.native.shellIntegrationEnabled else {
                    break
                }
            }
        }
    }

    private static func normalizedWorkingDirectory(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) {
            return nil
        }

        return trimmed
    }

    private static func normalizedStartupCommand(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedRestoredBufferText(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func childProcessID() -> Int32? {
        terminal?.childProcessID()
    }

    func foregroundProcessGroupID() -> Int32? {
        terminal?.foregroundProcessGroupID()
    }

    func ttyName() -> String? {
        terminal?.ttyName()
    }

    func visibleTextSnapshot() -> String {
        frame.visibleTextSnapshot()
    }
}

struct TerminalDebugMetrics: Equatable {
    var framesPerSecond: Double
    var cpuPercent: Double
    var memoryMegabytes: Double
    /// Display-synced polls in the last sample window that had no frame to present.
    var skippedPresentsPerSecond: Double
    /// Frames in the last sample window that rebuilt the entire render plan.
    var fullRebuildsPerSecond: Double
    /// Frames in the last sample window that rebuilt only the damaged rows.
    var partialRebuildsPerSecond: Double

    static let empty = TerminalDebugMetrics(
        framesPerSecond: 0,
        cpuPercent: 0,
        memoryMegabytes: 0,
        skippedPresentsPerSecond: 0,
        fullRebuildsPerSecond: 0,
        partialRebuildsPerSecond: 0
    )
}

private struct ProcessUsageSample {
    var timestamp: Date
    var cpuTime: TimeInterval
    var memoryMegabytes: Double

    static func capture() -> ProcessUsageSample {
        var usage = rusage()
        _ = getrusage(RUSAGE_SELF, &usage)
        let userCPU = TimeInterval(usage.ru_utime.tv_sec)
            + TimeInterval(usage.ru_utime.tv_usec) / 1_000_000
        let systemCPU = TimeInterval(usage.ru_stime.tv_sec)
            + TimeInterval(usage.ru_stime.tv_usec) / 1_000_000

        return ProcessUsageSample(
            timestamp: Date(),
            cpuTime: userCPU + systemCPU,
            memoryMegabytes: Self.currentResidentMemoryMegabytes()
        )
    }

    private static func currentResidentMemoryMegabytes() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.stride / MemoryLayout<natural_t>.stride)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    rebound,
                    &count
                )
            }
        }
        guard status == KERN_SUCCESS else {
            return 0
        }
        return Double(info.resident_size) / 1_048_576
    }
}

/// Holds NotificationCenter observer tokens and removes them on `removeAll()`
/// or when the bag is deallocated. Being a plain (non–`@MainActor`) class, its
/// `deinit` can access the stored non-Sendable tokens, which a `@MainActor`
/// owner's nonisolated `deinit` cannot. `removeObserver` is thread-safe, and in
/// practice all access happens on the main actor, so `@unchecked Sendable` is
/// sound. `DistributedNotificationCenter` is a `NotificationCenter` subclass,
/// so a single token list covers both.
private final class NotificationObserverBag: @unchecked Sendable {
    private var entries: [(center: NotificationCenter, token: any NSObjectProtocol)] = []

    func add(_ token: any NSObjectProtocol, center: NotificationCenter) {
        entries.append((center, token))
    }

    func removeAll() {
        for entry in entries {
            entry.center.removeObserver(entry.token)
        }
        entries.removeAll()
    }

    deinit {
        removeAll()
    }
}

private struct TerminalResize: Equatable {
    var cols: UInt16
    var rows: UInt16
    var cellWidth: Float
    var cellHeight: Float
}

enum RefreshCadence {
    case active
    case idle
    /// Idle with no cursor blink to animate (blink disabled or pane unfocused):
    /// the only remaining job is a slow safety poll, since PTY output wakes the
    /// terminal immediately through the FFI wake channel.
    case idleInert

    var interval: TimeInterval {
        switch self {
        case .active:
            1.0 / 60.0
        case .idle:
            TerminalCursorBlinkPhase.interval
        case .idleInert:
            2.0
        }
    }
}
