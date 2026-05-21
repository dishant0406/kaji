import AppKit
import Foundation
import GhosttyKit
import os

private let logger = Logger(subsystem: "app.kaji", category: "GhosttyService")

@MainActor @Observable
final class GhosttyService {
    static let shared = GhosttyService()

    @ObservationIgnored private(set) var app: ghostty_app_t?
    private(set) var config: ghostty_config_t?
    private(set) var configVersion = 0
    @ObservationIgnored private let runtimeEvents: any GhosttyRuntimeEventHandling = GhosttyRuntimeEventAdapter()
    @ObservationIgnored private let kajiConfig: KajiConfig

    private init(kajiConfig: KajiConfig = .shared) {
        self.kajiConfig = kajiConfig
        TerminalEnvironmentPolicy.applyToProcessEnvironment()
        initializeGhostty()
    }

    private func initializeGhostty() {
        resolveGhosttyResources()

        let result = ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv)
        guard result == GHOSTTY_SUCCESS else {
            logger.error("ghostty_init failed: \(String(describing: result))")
            return
        }

        guard let cfg = loadKajiGhosttyConfig() else {
            logger.error("ghostty_config failed")
            return
        }

        var rt = ghostty_runtime_config_s()
        rt.userdata = Unmanaged.passUnretained(self).toOpaque()
        rt.supports_selection_clipboard = true
        rt.wakeup_cb = { _ in
            GhosttyService.shared.runtimeEvents.wakeup()
        }
        rt.action_cb = { app, target, action in
            GhosttyService.shared.runtimeEvents.action(app: app, target: target, action: action)
        }
        rt.read_clipboard_cb = { userdata, location, state in
            GhosttyService.shared.runtimeEvents.readClipboard(userdata: userdata, location: location, state: state)
        }
        rt.confirm_read_clipboard_cb = { userdata, content, state, _ in
            GhosttyService.shared.runtimeEvents.confirmReadClipboard(userdata: userdata, content: content, state: state)
        }
        rt.write_clipboard_cb = { _, location, content, len, _ in
            GhosttyService.shared.runtimeEvents.writeClipboard(location: location, content: content, len: UInt(len))
        }
        rt.close_surface_cb = { userdata, needsConfirm in
            GhosttyService.shared.runtimeEvents.closeSurface(userdata: userdata, needsConfirm: needsConfirm)
        }

        guard let createdApp = ghostty_app_new(&rt, cfg) else {
            logger.error("ghostty_app_new failed")
            ghostty_config_free(cfg)
            return
        }

        self.app = createdApp
        self.config = cfg
    }

    func shutdown() {
        if let app { ghostty_app_free(app) }
        if let config { ghostty_config_free(config) }
        app = nil
        config = nil
    }

    var backgroundColor: NSColor {
        configColor("background")
            ?? themeFileColor(\.background)
            ?? NSColor(srgbRed: 0.059, green: 0.078, blue: 0.098, alpha: 1)
    }

    var foregroundColor: NSColor {
        configColor("foreground")
            ?? themeFileColor(\.foreground)
            ?? NSColor(srgbRed: 0.902, green: 0.882, blue: 0.812, alpha: 1)
    }

    var selectionBackgroundColor: NSColor {
        configColor("selection-background")
            ?? themeFileColor(\.selectionBackground)
            ?? NSColor(srgbRed: 0.153, green: 0.216, blue: 0.278, alpha: 1)
    }

    var accentColor: NSColor {
        configColor("cursor-color")
            ?? themeFileColor(\.cursorColor)
            ?? paletteColor(at: 3)
            ?? paletteColor(at: 4)
            ?? foregroundColor
    }

    func paletteColor(at index: Int) -> NSColor? {
        guard let config, index >= 0, index < 256 else { return nil }
        var palette = ghostty_config_palette_s()
        guard ghostty_config_get(config, &palette, "palette", 7) else { return nil }
        let c = withUnsafePointer(to: &palette.colors) {
            $0.withMemoryRebound(to: ghostty_config_color_s.self, capacity: 256) { $0[index] }
        }
        return NSColor(
            srgbRed: CGFloat(c.r) / 255,
            green: CGFloat(c.g) / 255,
            blue: CGFloat(c.b) / 255,
            alpha: 1
        )
    }

    private func configColor(_ key: String) -> NSColor? {
        guard let config else { return nil }
        var color = ghostty_config_color_s()
        guard ghostty_config_get(config, &color, key, UInt(key.lengthOfBytes(using: .utf8))) else {
            return nil
        }
        return NSColor(
            srgbRed: CGFloat(color.r) / 255,
            green: CGFloat(color.g) / 255,
            blue: CGFloat(color.b) / 255,
            alpha: 1
        )
    }

    private func themeFileColor(_ keyPath: KeyPath<ThemeColorSet, String>) -> NSColor? {
        guard let identifier = ThemeService.shared.currentThemeIdentifier(),
              let theme = ThemeService.discoverTheme(identifier: identifier)
        else { return nil }
        return Self.nsColor(hex: theme.draft.colors[keyPath: keyPath])
    }

    private static func nsColor(hex: String) -> NSColor? {
        let normalized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = normalized.hasPrefix("#") ? String(normalized.dropFirst()) : normalized
        guard value.count == 6, let rgb = UInt32(value, radix: 16) else { return nil }
        return NSColor(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }

    func reloadConfig() {
        guard let app else { return }
        guard let newConfig = loadKajiGhosttyConfig() else { return }
        ghostty_app_update_config(app, newConfig)
        let oldConfig = self.config
        self.config = newConfig
        if let oldConfig { ghostty_config_free(oldConfig) }
        configVersion += 1
    }

    private func loadKajiGhosttyConfig() -> ghostty_config_t? {
        guard let cfg = ghostty_config_new() else { return nil }
        let configPath = kajiConfig.ghosttyConfigPath
        configPath.withCString { ptr in
            ghostty_config_load_file(cfg, ptr)
        }
        ghostty_config_finalize(cfg)
        return cfg
    }

    func tick() {
        guard let app else { return }
        let signpostID = GhosttyPerf.begin("ghosttyAppTick")
        defer { GhosttyPerf.end("ghosttyAppTick", signpostID) }
        ghostty_app_tick(app)
    }

    private static let externalResourceParents = [
        "/Applications/Ghostty.app/Contents/Resources/ghostty",
        NSHomeDirectory() + "/Applications/Ghostty.app/Contents/Resources/ghostty",
    ]

    private func resolveGhosttyResources() {
        let existing = getenv("GHOSTTY_RESOURCES_DIR").map { String(cString: $0) }
        if let resolved = GhosttyRuntimeResourceLocator.preferredResourceDirectory(
            bundleResourceURL: Bundle.appResources.resourceURL,
            currentEnv: existing,
            externalCandidates: Self.externalResourceParents
        ) {
            setenv("GHOSTTY_RESOURCES_DIR", resolved, 1)
            return
        }

        if existing != nil {
            unsetenv("GHOSTTY_RESOURCES_DIR")
        }
    }
}
