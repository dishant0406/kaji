import Darwin
import Foundation
import TermyKit

enum LibTermyError: Error, CustomStringConvertible {
    case missingTerminal
    case missingCells

    var description: String {
        switch self {
        case .missingTerminal:
            "libtermy did not return a terminal handle"
        case .missingCells:
            "libtermy returned a frame without cells"
        }
    }
}

private final class TerminalWakeupMonitor: @unchecked Sendable {
    private let handle: OpaquePointer
    private let onWakeup: @MainActor () -> Void
    private let queue = DispatchQueue(label: "dev.termy.terminal-wakeup", qos: .userInteractive)
    private let group = DispatchGroup()
    private let lock = NSLock()
    private var running = true

    init(handle: OpaquePointer, onWakeup: @escaping @MainActor () -> Void) {
        self.handle = handle
        self.onWakeup = onWakeup
        group.enter()
        queue.async { [weak self] in
            self?.run()
        }
    }

    func stop() {
        lock.lock()
        let wasRunning = running
        running = false
        lock.unlock()

        guard wasRunning else {
            return
        }

        _ = termy_terminal_notify_wakeup(handle)
        group.wait()
    }

    private func run() {
        defer {
            group.leave()
        }

        while isRunning {
            var woke = false
            // The timeout is a safety net only: PTY output and `stop()` (via
            // `termy_terminal_notify_wakeup`) both wake the blocking wait
            // immediately, so a long timeout keeps the monitor thread asleep
            // instead of waking 4×/s per pane just to re-check `running`.
            let status = termy_terminal_wait_for_wakeup(handle, 10000, &woke)
            guard status == TERMY_FFI_OK else {
                return
            }
            guard woke, isRunning else {
                continue
            }
            Task { @MainActor [weak self] in
                guard let self, self.isRunning else {
                    return
                }
                self.onWakeup()
            }
        }
    }

    private var isRunning: Bool {
        lock.lock()
        defer {
            lock.unlock()
        }
        return running
    }
}

final class LibTermyTerminal {
    private var handle: OpaquePointer?
    private var configHandle: OpaquePointer?
    private var wakeupMonitor: TerminalWakeupMonitor?

    private(set) var renderConfig: TerminalRenderConfig

    init(
        cols: UInt16 = 96,
        rows: UInt16 = 28,
        loadUserConfig: Bool = true,
        configurationSource: TermyConfigurationSource = .defaultConfig,
        workingDirectoryOverride: String? = nil,
        startupCommand: String? = nil,
        envVars: [(key: String, value: String)] = []
    ) throws {
        var size = termy_size_default()
        size.cols = cols
        size.rows = rows
        let config = try loadUserConfig ? Self.loadConfig(configurationSource) : nil
        do {
            renderConfig = try Self.renderConfig(for: config)
        } catch {
            if let config {
                _ = termy_config_free(config)
            }
            throw error
        }
        configHandle = config
        let workingDirectory: String? = if let override = Self.normalizedWorkingDirectory(workingDirectoryOverride) {
            override
        } else {
            try Self.workingDirectory(for: config)
        }

        var terminal: OpaquePointer?
        let workingDirectoryBytes = workingDirectory.map { Array($0.utf8) } ?? []
        let startupCommandBytes = startupCommand.map { Array($0.utf8) } ?? []
        let ffiEnv = envVars.map { (Array($0.key.utf8), Array($0.value.utf8)) }
        let status = try workingDirectoryBytes.withUnsafeBufferPointer { workingDirectoryBuffer in
            try startupCommandBytes.withUnsafeBufferPointer { startupCommandBuffer in
                try withTermyEnvVars(ffiEnv) { envPointer, envCount in
                    var options = TermyFfiTerminalOptions(
                        config: config,
                        working_directory_ptr: workingDirectoryBuffer.baseAddress,
                        working_directory_len: workingDirectoryBuffer.count,
                        startup_command_ptr: startupCommandBuffer.baseAddress,
                        startup_command_len: startupCommandBuffer.count,
                        env_vars_ptr: envPointer,
                        env_vars_len: envCount
                    )
                    return termy_terminal_new_with_options(size, &options, &terminal)
                }
            }
        }
        try TermyFfiBridge.requireOK("termy_terminal_new_with_options", status)

        guard let terminal else {
            throw LibTermyError.missingTerminal
        }
        // The Swift shell consumes the FFI wake channel, so plain wakeups are
        // useful: they move idle terminals from timer cadence to immediate poll.
        _ = termy_terminal_set_wakeup_enabled(terminal, true)
        handle = terminal
    }

    /// Creates a display-only terminal (no shell/PTY) for rendering tmux
    /// control-mode pane output. Drive it with `feedOutput`; `write` is a no-op.
    init(displayCols cols: UInt16, rows: UInt16, loadUserConfig: Bool = true) throws {
        var size = termy_size_default()
        size.cols = cols
        size.rows = rows
        let config = try loadUserConfig ? Self.loadDefaultConfig() : nil
        do {
            renderConfig = try Self.renderConfig(for: config)
        } catch {
            if let config {
                _ = termy_config_free(config)
            }
            throw error
        }
        configHandle = config

        var terminal: OpaquePointer?
        try TermyFfiBridge.requireOK(
            "termy_display_terminal_new",
            termy_display_terminal_new(size, &terminal)
        )
        guard let terminal else {
            throw LibTermyError.missingTerminal
        }
        handle = terminal
    }

    deinit {
        stopWakeupMonitor()
        if let handle {
            _ = termy_terminal_free(handle)
        }
        if let configHandle {
            _ = termy_config_free(configHandle)
        }
    }

    func childProcessID() -> Int32? {
        guard let handle else { return nil }
        var pid: UInt32 = 0
        guard termy_terminal_child_pid(handle, &pid) == TERMY_FFI_OK, pid > 0 else { return nil }
        return Int32(pid)
    }

    func ttyName() -> String? {
        childProcessID().flatMap(DarwinTerminalIdentityResolver.ttyName(pid:))
    }

    func foregroundProcessGroupID() -> Int32? {
        DarwinTerminalIdentityResolver.foregroundProcessGroupID(ttyName: ttyName())
    }

    func startWakeupMonitor(onWakeup: @escaping @MainActor () -> Void) {
        stopWakeupMonitor()
        guard let handle else {
            return
        }
        wakeupMonitor = TerminalWakeupMonitor(handle: handle, onWakeup: onWakeup)
    }

    func stopWakeupMonitor() {
        wakeupMonitor?.stop()
        wakeupMonitor = nil
    }

    /// Advance the grid with output bytes (e.g. tmux `%output`) on a display
    /// terminal, without sending input to a PTY.
    func feedOutput(_ bytes: [UInt8]) throws {
        let handle = try terminalHandle()
        let status = bytes.withUnsafeBufferPointer { buffer in
            termy_terminal_feed_output(handle, buffer.baseAddress, buffer.count)
        }
        try TermyFfiBridge.requireOK("termy_terminal_feed_output", status)
    }

    func write(_ bytes: [UInt8]) throws {
        let handle = try terminalHandle()
        let status = bytes.withUnsafeBufferPointer { buffer in
            termy_terminal_write(handle, buffer.baseAddress, buffer.count)
        }
        try TermyFfiBridge.requireOK("termy_terminal_write", status)
    }

    func encodeKey(_ keyInput: TerminalKeyInput) throws -> [UInt8]? {
        let handle = try terminalHandle()

        let keyBytes = Array(keyInput.key.utf8)
        let keyCharBytes = keyInput.keyChar.map { Array($0.utf8) } ?? []
        var outBytes = TermyFfiBytes()

        let status = keyBytes.withUnsafeBufferPointer { keyBuffer in
            keyCharBytes.withUnsafeBufferPointer { keyCharBuffer in
                var ffiKeystroke = TermyFfiKeystroke(
                    control: keyInput.control,
                    alt: keyInput.alt,
                    shift: keyInput.shift,
                    platform: keyInput.platform,
                    function: keyInput.function,
                    key_ptr: keyBuffer.baseAddress,
                    key_len: keyBuffer.count,
                    key_char_ptr: keyCharBuffer.baseAddress,
                    key_char_len: keyCharBuffer.count,
                    event_kind: keyInput.eventKind.rawValue
                )
                return termy_terminal_encode_key(handle, &ffiKeystroke, &outBytes)
            }
        }
        try TermyFfiBridge.requireOK("termy_terminal_encode_key", status)
        defer {
            if outBytes.ptr != nil {
                _ = termy_buffer_free(outBytes)
            }
        }

        guard let ptr = outBytes.ptr, outBytes.len > 0 else {
            return nil
        }
        return Array(UnsafeBufferPointer(start: ptr, count: Int(outBytes.len)))
    }

    func encodeMouse(_ mouseInput: TerminalMouseInput) throws -> [UInt8]? {
        let handle = try terminalHandle()
        var ffiInput = TermyFfiMouseInput(
            kind: mouseInput.kind.rawValue,
            button: mouseInput.button.rawValue,
            col: mouseInput.position.col,
            row: mouseInput.position.row,
            control: mouseInput.control,
            alt: mouseInput.alt,
            shift: mouseInput.shift
        )
        var outBytes = TermyFfiBytes()
        try TermyFfiBridge.requireOK(
            "termy_terminal_encode_mouse",
            termy_terminal_encode_mouse(handle, &ffiInput, &outBytes)
        )
        defer {
            if outBytes.ptr != nil {
                _ = termy_buffer_free(outBytes)
            }
        }

        guard let ptr = outBytes.ptr, outBytes.len > 0 else {
            return nil
        }
        return Array(UnsafeBufferPointer(start: ptr, count: Int(outBytes.len)))
    }

    func resize(cols: UInt16, rows: UInt16, cellWidth: Float, cellHeight: Float) throws {
        let handle = try terminalHandle()
        var size = termy_size_default()
        size.cols = cols
        size.rows = rows
        size.cell_width = cellWidth
        size.cell_height = cellHeight
        try TermyFfiBridge.requireOK("termy_terminal_resize", termy_terminal_resize(handle, size))
    }

    func scrollDisplay(deltaLines: Int32) throws -> Bool {
        try changedBy("termy_terminal_scroll_display") { handle, changed in
            termy_terminal_scroll_display(handle, deltaLines, changed)
        }
    }

    func scrollToBottom() throws -> Bool {
        try changedBy("termy_terminal_scroll_to_bottom") { handle, changed in
            termy_terminal_scroll_to_bottom(handle, changed)
        }
    }

    func reloadConfiguration(from source: TermyConfigurationSource) throws -> TerminalRenderConfig {
        let nextConfig = try Self.loadConfig(source)
        do {
            let nextRenderConfig = try Self.renderConfig(for: nextConfig)
            try reloadColors(using: nextConfig)
            if let configHandle {
                _ = termy_config_free(configHandle)
            }
            configHandle = nextConfig
            renderConfig = nextRenderConfig
            return nextRenderConfig
        } catch {
            if let nextConfig {
                _ = termy_config_free(nextConfig)
            }
            throw error
        }
    }

    static func loadRenderConfig(configurationSource: TermyConfigurationSource = .defaultConfig) throws -> TerminalRenderConfig {
        let config = try loadConfig(configurationSource)
        defer {
            if let config {
                _ = termy_config_free(config)
            }
        }
        return try renderConfig(for: config)
    }

    func clearScrollback() throws -> Bool {
        try changedBy("termy_terminal_clear_scrollback") { handle, changed in
            termy_terminal_clear_scrollback(handle, changed)
        }
    }

    /// Whether the foreground program has enabled bracketed-paste mode. When
    /// true, the host wraps pasted text in `ESC[200~`/`ESC[201~` so the program
    /// can treat it as inert data rather than typed input.
    func bracketedPasteMode() throws -> Bool {
        try changedBy("termy_terminal_bracketed_paste_mode") { handle, enabled in
            termy_terminal_bracketed_paste_mode(handle, enabled)
        }
    }

    func setScrollbackHistory(_ scrollbackHistory: Int) throws {
        let handle = try terminalHandle()
        try TermyFfiBridge.requireOK(
            "termy_terminal_set_scrollback_history",
            termy_terminal_set_scrollback_history(handle, max(0, scrollbackHistory))
        )
    }

    func drainEvents() throws -> [TerminalRuntimeEvent] {
        let handle = try terminalHandle()
        var batch = TermyFfiEventBatch()
        try TermyFfiBridge.requireOK(
            "termy_terminal_drain_events",
            termy_terminal_drain_events(handle, &batch)
        )
        defer {
            _ = termy_event_batch_free(&batch)
        }

        guard let eventsPtr = batch.events_ptr else {
            return []
        }
        return UnsafeBufferPointer(start: eventsPtr, count: Int(batch.events_len))
            .compactMap(Self.event(from:))
    }

    func snapshot() throws -> TerminalFrame {
        let handle = try terminalHandle()

        var frame = TermyFfiFrame()
        try TermyFfiBridge.requireOK("termy_terminal_snapshot", termy_terminal_snapshot(handle, &frame))
        defer {
            _ = termy_frame_free(&frame)
        }

        guard let cellsPtr = frame.cells_ptr else {
            throw LibTermyError.missingCells
        }

        let cells = UnsafeBufferPointer(start: cellsPtr, count: Int(frame.cells_len))
            .map(Self.cell(from:))
        let cursor = frame.cursor.visible
            ? TerminalCursor(
                col: Int(frame.cursor.col),
                row: Int(frame.cursor.row),
                style: TerminalCursorStyle(ffiRawValue: frame.cursor.style)
            )
            : nil

        return TerminalFrame(
            cols: Int(frame.cols),
            rows: Int(frame.rows),
            cells: cells,
            cursor: cursor,
            displayOffset: Int(frame.display_offset),
            historySize: Int(frame.history_size)
        )
    }

    func frameUpdate(forceFull: Bool) throws -> TerminalFrameUpdate {
        let handle = try terminalHandle()

        var update = TermyFfiFrameUpdate()
        try TermyFfiBridge.requireOK(
            "termy_terminal_take_frame_update",
            termy_terminal_take_frame_update(handle, forceFull, &update)
        )
        defer {
            _ = termy_frame_update_free(&update)
        }

        let cells: [TerminalCell]
        if update.cells_len > 0 {
            guard let cellsPtr = update.cells_ptr else {
                throw LibTermyError.missingCells
            }
            cells = UnsafeBufferPointer(start: cellsPtr, count: Int(update.cells_len))
                .map(Self.cell(from:))
        } else {
            cells = []
        }

        let damage: TerminalDamage
        switch update.damage_kind {
        case 1:
            damage = .full
        case 2:
            if update.spans_len > 0 {
                guard let spansPtr = update.spans_ptr else {
                    damage = .none
                    break
                }
                let spans = UnsafeBufferPointer(start: spansPtr, count: Int(update.spans_len))
                    .map {
                        TerminalDirtySpan(
                            row: Int($0.row),
                            leftCol: Int($0.left_col),
                            rightCol: Int($0.right_col)
                        )
                    }
                damage = .partial(spans)
            } else {
                damage = .none
            }
        default:
            damage = .none
        }

        return TerminalFrameUpdate(
            cols: Int(update.cols),
            rows: Int(update.rows),
            cells: cells,
            cursor: Self.cursor(from: update.cursor),
            displayOffset: Int(update.display_offset),
            historySize: Int(update.history_size),
            damage: damage
        )
    }

    /// The OSC 8 hyperlink under a viewport cell, if any, expanded to the
    /// contiguous link run on that row. Best-effort: returns nil on FFI errors
    /// since hover lookups should never surface failures.
    func hyperlink(atRow row: Int, col: Int) -> TerminalFrameLink? {
        guard row >= 0, col >= 0, let handle else {
            return nil
        }

        var found = false
        var link = TermyFfiHyperlink()
        guard termy_terminal_hyperlink_at(handle, row, col, &found, &link) == TERMY_FFI_OK,
              found
        else {
            return nil
        }
        defer { _ = termy_hyperlink_free(&link) }

        guard let target = TermyFfiBridge.string(from: link.uri), !target.isEmpty else {
            return nil
        }
        return TerminalFrameLink(
            row: row,
            startCol: Int(link.start_col),
            endCol: Int(link.end_col),
            target: target
        )
    }

    func search(
        _ query: String,
        options: TerminalSearchOptions = TerminalSearchOptions()
    ) throws -> [TerminalSearchMatch] {
        let handle = try terminalHandle()

        var batch = TermyFfiSearchBatch()
        let ffiOptions = TermyFfiSearchOptions(
            case_sensitive: options.caseSensitive,
            regex: options.usesRegex
        )
        let status = Array(query.utf8).withUnsafeBufferPointer { buffer in
            termy_terminal_search_with_options(
                handle,
                buffer.baseAddress,
                buffer.count,
                ffiOptions,
                &batch
            )
        }
        try TermyFfiBridge.requireOK("termy_terminal_search_with_options", status)
        defer {
            _ = termy_search_batch_free(&batch)
        }

        guard let matchesPtr = batch.matches_ptr else {
            return []
        }
        return UnsafeBufferPointer(start: matchesPtr, count: Int(batch.matches_len))
            .map { match in
                TerminalSearchMatch(
                    row: Int(match.row),
                    startCol: Int(match.start_col),
                    endCol: Int(match.end_col)
                )
            }
    }

    private func terminalHandle() throws -> OpaquePointer {
        guard let handle else {
            throw LibTermyError.missingTerminal
        }
        return handle
    }

    private func changedBy(
        _ operation: String,
        _ call: (OpaquePointer, UnsafeMutablePointer<Bool>) -> TermyFfiStatus
    ) throws -> Bool {
        let handle = try terminalHandle()
        var changed = false
        try TermyFfiBridge.requireOK(operation, call(handle, &changed))
        return changed
    }

    static func loadConfig(_ source: TermyConfigurationSource) throws -> OpaquePointer? {
        switch source {
        case .defaultConfig:
            try loadDefaultConfig()
        case let .path(path):
            try loadConfigPath(path)
        case let .contents(contents):
            try loadConfigContents(contents)
        }
    }

    private static func loadDefaultConfig() throws -> OpaquePointer? {
        var config: OpaquePointer?
        try TermyFfiBridge.requireOK("termy_config_load_default", termy_config_load_default(&config))
        return config
    }

    private static func loadConfigPath(_ path: String) throws -> OpaquePointer? {
        let normalized = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return try loadDefaultConfig()
        }
        var config: OpaquePointer?
        let bytes = Array(normalized.utf8)
        try bytes.withUnsafeBufferPointer { buffer in
            try TermyFfiBridge.requireOK(
                "termy_config_load_path",
                termy_config_load_path(buffer.baseAddress, buffer.count, &config)
            )
        }
        return config
    }

    private static func loadConfigContents(_ contents: String) throws -> OpaquePointer? {
        let normalized = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return try loadDefaultConfig()
        }
        var config: OpaquePointer?
        let bytes = Array(contents.utf8)
        try bytes.withUnsafeBufferPointer { buffer in
            try TermyFfiBridge.requireOK(
                "termy_config_from_contents",
                termy_config_from_contents(buffer.baseAddress, buffer.count, &config)
            )
        }
        return config
    }

    private static func renderConfig(for config: OpaquePointer?) throws -> TerminalRenderConfig {
        guard let config else {
            return .default
        }

        var renderConfig = TermyFfiRenderConfig()
        try TermyFfiBridge.requireOK(
            "termy_config_render_config_for_appearance",
            termy_config_render_config_for_appearance(
                config,
                Self.currentSystemAppearanceRawValue(),
                &renderConfig
            )
        )
        defer {
            _ = termy_render_config_free(&renderConfig)
        }
        return TerminalRenderConfig(renderConfig)
    }

    private static func currentSystemAppearanceRawValue() -> UInt32 {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark" ? 1 : 0
    }

    private func reloadColors(using config: OpaquePointer?) throws {
        let handle = try terminalHandle()
        if let config {
            try TermyFfiBridge.requireOK(
                "termy_terminal_reload_config_colors",
                termy_terminal_reload_config_colors(handle, config, Self.currentSystemAppearanceRawValue())
            )
            return
        }
        try TermyFfiBridge.requireOK(
            "termy_terminal_reload_default_config_colors",
            termy_terminal_reload_default_config_colors(handle)
        )
    }

    private static func workingDirectory(for config: OpaquePointer?) throws -> String? {
        guard let config else {
            return nil
        }

        var bytes = TermyFfiBytes()
        try TermyFfiBridge.requireOK(
            "termy_config_working_directory",
            termy_config_working_directory(config, &bytes)
        )
        defer {
            if bytes.ptr != nil {
                _ = termy_buffer_free(bytes)
            }
        }

        guard bytes.ptr != nil, bytes.len > 0 else {
            return nil
        }
        let value = TermyFfiBridge.string(from: bytes, trimmingWhitespaceAndNewlines: true) ?? ""
        return value.isEmpty ? nil : value
    }

    private static func normalizedWorkingDirectory(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func event(from event: TermyFfiEvent) -> TerminalRuntimeEvent? {
        guard let eventKind = TerminalRuntimeEventKind(rawValue: event.kind) else {
            return nil
        }

        switch eventKind {
        case .wakeup:
            return .wakeup
        case .title:
            return .title(TermyFfiBridge.string(from: event.payload) ?? "")
        case .resetTitle:
            return .resetTitle
        case .bell:
            return .bell
        case .exit:
            return .exit
        case .clipboardStore:
            return .clipboardStore(TermyFfiBridge.string(from: event.payload) ?? "")
        case .shellPromptStart:
            return .shellPromptStart
        case .shellCommandStart:
            return .shellCommandStart
        case .shellCommandExecuting:
            return .shellCommandExecuting
        case .shellCommandFinished:
            return .shellCommandFinished(event.exit_code >= 0 ? event.exit_code : nil)
        case .progress:
            return .progress(TerminalProgress(
                state: event.progress_state,
                value: event.progress_value
            ))
        case .workingDirectory:
            return .workingDirectory(TermyFfiBridge.string(from: event.payload) ?? "")
        }
    }

    private static func cell(from ffiCell: TermyFfiCell) -> TerminalCell {
        TerminalCell(
            col: Int(ffiCell.col),
            row: Int(ffiCell.row),
            codepoint: ffiCell.codepoint,
            foreground: TerminalRGBA(ffiCell.fg),
            background: TerminalRGBA(ffiCell.bg),
            usesTerminalDefaultBackground: ffiCell.uses_terminal_default_bg,
            renderText: ffiCell.render_text,
            bold: ffiCell.bold
        )
    }

    private static func cursor(from ffiCursor: TermyFfiCursor) -> TerminalCursor? {
        guard ffiCursor.visible else {
            return nil
        }
        return TerminalCursor(
            col: Int(ffiCursor.col),
            row: Int(ffiCursor.row),
            style: TerminalCursorStyle(ffiRawValue: ffiCursor.style)
        )
    }
}

private func withTermyEnvVars<T>(
    _ env: [([UInt8], [UInt8])],
    _ body: (UnsafePointer<TermyFfiEnvVar>?, Int) throws -> T
) throws -> T {
    var allocations: [UnsafeMutablePointer<CChar>] = []
    defer { allocations.forEach { free($0) } }
    var vars: [TermyFfiEnvVar] = []
    for pair in env {
        guard let key = String(bytes: pair.0, encoding: .utf8),
              let value = String(bytes: pair.1, encoding: .utf8),
              let keyPtr = strdup(key),
              let valuePtr = strdup(value)
        else { continue }
        allocations.append(keyPtr)
        allocations.append(valuePtr)
        vars.append(TermyFfiEnvVar(
            key_ptr: UnsafePointer(keyPtr).withMemoryRebound(to: UInt8.self, capacity: pair.0.count) { $0 },
            key_len: pair.0.count,
            value_ptr: UnsafePointer(valuePtr).withMemoryRebound(to: UInt8.self, capacity: pair.1.count) { $0 },
            value_len: pair.1.count
        ))
    }
    return try vars.withUnsafeBufferPointer { buffer in
        try body(buffer.baseAddress, buffer.count)
    }
}

private enum DarwinTerminalIdentityResolver {
    static func ttyName(pid: Int32) -> String? {
        guard pid > 0 else { return nil }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
              info.pbi_flags & UInt32(PROC_FLAG_CONTROLT) != 0,
              info.e_tdev != UInt32.max
        else { return nil }
        let device = dev_t(bitPattern: info.e_tdev)
        guard let name = devname(device, S_IFCHR) else { return nil }
        return validatedTTYPath(String(cString: name))
    }

    static func foregroundProcessGroupID(ttyName: String?) -> Int32? {
        guard let path = validatedTTYPath(ttyName) else { return nil }
        let descriptor = open(path, O_RDONLY | O_NOCTTY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        let processGroupID = tcgetpgrp(descriptor)
        return processGroupID > 0 ? processGroupID : nil
    }

    private static func validatedTTYPath(_ ttyName: String?) -> String? {
        guard let ttyName else { return nil }
        let component = ttyName.hasPrefix("/dev/") ? String(ttyName.dropFirst(5)) : ttyName
        guard component.hasPrefix("tty"),
              component.count <= 64,
              component.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) })
        else { return nil }
        return "/dev/\(component)"
    }
}
