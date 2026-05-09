import AppKit
import CEFBridge
import Foundation

@MainActor
final class BrowserWebController {
    private weak var surface: NativeBrowserSurfaceView?
    private var page: BrowserPageState?
    private var projectPath = ""
    private var pageChanged: ((UUID, String) -> Void)?
    private var popupRequested: ((UUID, String) -> Void)?
    private var browserView: DroidCEFBrowserView?
    private var isStarting = false
    private var activeState: Bool?
    private var startURL = ""
    private var startTask: Task<Void, Never>?

    func attach(
        surface: NativeBrowserSurfaceView,
        page: BrowserPageState,
        projectPath: String,
        isActive: Bool,
        callbacks: BrowserSurfaceCallbacks
    ) {
        self.surface = surface
        self.page = page
        self.projectPath = projectPath
        pageChanged = callbacks.pageChanged
        popupRequested = callbacks.popupRequested
        surface.controller = self
        if startURL.isEmpty {
            startURL = page.url
        }
        if let browserView {
            if !surface.contains(browserView: browserView) {
                surface.install(browserView: browserView)
            }
            updateActiveState(isActive, browserView: browserView)
            return
        }
        guard isActive else {
            surface.show(status: "")
            return
        }
        ensureStarted(url: page.url)
    }

    func navigate(to rawURL: String) {
        guard let url = BrowserURLParser.url(from: rawURL)?.absoluteString else { return }
        startURL = url
        if let page {
            page.url = url
            pageChanged?(page.id, url)
        }
        guard let browserView else {
            ensureStarted(url: url)
            return
        }
        browserView.loadURL(url)
    }

    func goBack() {
        browserView?.goBack()
    }

    func goForward() {
        browserView?.goForward()
    }

    func reload() {
        browserView?.reloadPage()
    }

    func setActive(_ active: Bool) {
        guard let browserView else {
            activeState = active
            return
        }
        updateActiveState(active, browserView: browserView)
    }

    func ensureStarted(url: String) {
        startURL = BrowserURLParser.url(from: url)?.absoluteString ?? url
        scheduleStart()
    }

    func click(selector: String) async throws {
        browserView?.clickSelector(selector)
    }

    func typeText(_ text: String, selector: String) async throws {
        browserView?.typeText(text, selector: selector)
    }

    func readPage() async throws -> String {
        guard let browserView else { return "" }
        return await withCheckedContinuation { continuation in
            browserView.readPage { text in
                continuation.resume(returning: text)
            }
        }
    }

    func close() {
        startTask?.cancel()
        startTask = nil
        startURL = ""
        browserView?.closeBrowser()
        browserView = nil
        surface = nil
        page = nil
        pageChanged = nil
        popupRequested = nil
        isStarting = false
    }

    private func startIfNeeded(url: String) {
        guard browserView == nil, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        surface?.show(status: "Starting Chromium…")
        do {
            try startRuntime()
            let browserView = DroidCEFBrowserView(url: BrowserURLParser.url(from: url)?.absoluteString ?? "about:blank")
            browserView.pageChanged = { [weak self] url, title in
                Task { @MainActor in self?.updatePage(url: url, title: title) }
            }
            browserView.popupRequested = { [weak self] url in
                Task { @MainActor in self?.openPopup(url: url) }
            }
            self.browserView = browserView
            surface?.install(browserView: browserView)
            updateActiveState(true, browserView: browserView)
        } catch {
            surface?.show(status: error.localizedDescription)
        }
    }

    private func scheduleStart() {
        guard surface != nil, !projectPath.isEmpty, browserView == nil, !isStarting, startTask == nil else { return }
        surface?.show(status: "Starting Chromium…")
        startTask = Task { @MainActor in
            await Task.yield()
            startIfNeeded(url: startURL)
            startTask = nil
        }
    }

    private func startRuntime() throws {
        guard let rootPath = CEFRuntimeLocator.rootPath() else { throw BrowserRuntimeError.runtimeMissing }
        guard let helperPath = CEFRuntimeLocator.helperPath(rootPath: rootPath) else { throw BrowserRuntimeError.helperMissing }
        let profilePath = DroidFileStorage.appSupportDirectory()
            .appendingPathComponent("CEFProfiles", isDirectory: true)
            .appendingPathComponent(BrowserProfileIdentifier.value(for: projectPath), isDirectory: true)
            .path
        try FileManager.default.createDirectory(atPath: profilePath, withIntermediateDirectories: true)
        do {
            try DroidCEFRuntime.start(withRootPath: rootPath, profilePath: profilePath, helperPath: helperPath)
        } catch {
            throw error
        }
    }

    private func updatePage(url: String, title: String) {
        guard let page else { return }
        if !url.isEmpty, page.url != url {
            page.url = url
            pageChanged?(page.id, url)
        }
        let resolvedTitle = title.isEmpty ? "Browser" : title
        if page.title != resolvedTitle {
            page.title = resolvedTitle
        }
    }

    private func openPopup(url: String) {
        guard let page else { return }
        popupRequested?(page.id, url)
    }

    private func updateActiveState(_ active: Bool, browserView: DroidCEFBrowserView) {
        guard activeState != active else { return }
        activeState = active
        browserView.setActive(active)
    }
}

enum BrowserRuntimeError: LocalizedError {
    case runtimeMissing
    case helperMissing
    case initializationFailed

    var errorDescription: String? {
        switch self {
        case .runtimeMissing: "Bundled CEF runtime not found. Run scripts/install-cef-runtime.sh and rebuild Droid."
        case .helperMissing: "Bundled CEF helper app not found. Run scripts/install-cef-runtime.sh and rebuild Droid."
        case .initializationFailed: "CEF failed to initialize."
        }
    }
}
