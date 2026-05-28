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
    var browserView: KajiCEFBrowserView?
    private var isStarting = false
    private var activeState: Bool?
    private var startURL = ""
    private var startTask: Task<Void, Never>?
    private var deviceProfile = BrowserDeviceProfiles.profile(for: BrowserDeviceProfiles.desktopID)
    private var isClosed = false

    var isReady: Bool { browserView != nil }

    func attach(_ attachment: BrowserWebControllerAttachment) {
        let surface = attachment.surface
        let page = attachment.page
        let previousSurface = self.surface
        if BrowserSurfaceAttachmentPolicy.shouldReleasePreviousSurface(
            hasPreviousSurface: previousSurface != nil,
            sameSurface: previousSurface === surface
        ) {
            previousSurface?.release(controller: self, browserView: browserView)
        }
        self.surface = surface
        self.page = page
        projectPath = attachment.projectPath
        deviceProfile = attachment.deviceProfile
        surface.applyDeviceProfile(deviceProfile)
        pageChanged = attachment.callbacks.pageChanged
        popupRequested = attachment.callbacks.popupRequested
        surface.controller = self
        if startURL.isEmpty {
            startURL = page.url
        }
        if let browserView {
            if !surface.contains(browserView: browserView) {
                surface.install(browserView: browserView)
            }
            if attachment.isActive {
                applyDeviceProfile(deviceProfile)
            }
            updateActiveState(attachment.isActive, browserView: browserView)
            return
        }
        activeState = attachment.isActive
        guard attachment.isActive else {
            surface.show(status: "")
            return
        }
        ensureStarted(url: page.url)
    }

    func detach(surface: NativeBrowserSurfaceView) {
        guard self.surface === surface else { return }
        surface.release(controller: self, browserView: browserView)
        if BrowserSurfaceAttachmentPolicy.shouldDeactivateBrowserOnDetach(
            isCurrentSurface: true,
            hasBrowserView: browserView != nil
        ), let browserView {
            activeState = false
            browserView.setActive(false)
        }
        self.surface = nil
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

    func setActive(_ active: Bool) {
        guard let browserView else {
            activeState = active
            return
        }
        updateActiveState(active, browserView: browserView)
    }

    func ensureStarted(url: String) {
        guard !isClosed else { return }
        startURL = BrowserURLParser.url(from: url)?.absoluteString ?? url
        scheduleStart()
    }

    func close() {
        if BrowserStartupCompletionPolicy.shouldMarkStartedWhenControllerCloses(
            runtimeInfo: KajiBrowserRuntimeCoordinator.shared.currentRuntime()
        ) {
            KajiBrowserRuntimeCoordinator.shared.markBrowserStartupComplete()
        }
        isClosed = true
        startTask?.cancel()
        startTask = nil
        startURL = ""
        if let surface {
            surface.release(controller: self, browserView: browserView)
        }
        browserView?.pageChanged = nil
        browserView?.popupRequested = nil
        browserView?.closeBrowser()
        browserView = nil
        surface = nil
        page = nil
        pageChanged = nil
        popupRequested = nil
        isStarting = false
    }

    private func startIfNeeded(url: String) {
        guard !isClosed, surface != nil, browserView == nil, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        surface?.show(status: "Starting Chromium…")
        do {
            try startRuntime()
            guard !isClosed, surface != nil else { return }
            let browserView = KajiCEFBrowserView(url: BrowserURLParser.url(from: url)?.absoluteString ?? "about:blank")
            browserView.pageChanged = { [weak self] url, title in
                Task { @MainActor in self?.updatePage(url: url, title: title) }
            }
            browserView.popupRequested = { [weak self] url in
                Task { @MainActor in self?.openPopup(url: url) }
            }
            self.browserView = browserView
            surface?.install(browserView: browserView)
            applyDeviceProfile(deviceProfile)
            updateActiveState(
                BrowserPaneActivationPolicy.browserActiveStateAfterStartup(requestedActiveState: activeState),
                browserView: browserView
            )
            markStartupCompleteAfterStabilityDelay()
        } catch {
            surface?.show(status: error.localizedDescription)
        }
    }

    private func scheduleStart() {
        guard !isClosed, surface != nil, !projectPath.isEmpty, browserView == nil, !isStarting, startTask == nil else { return }
        surface?.show(status: "Starting Chromium…")
        startTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled, let self else { return }
            self.startIfNeeded(url: self.startURL)
            self.startTask = nil
        }
    }

    private func startRuntime() throws {
        _ = try KajiBrowserRuntimeCoordinator.shared.ensureStarted(projectPath: projectPath)
    }

    private func markStartupCompleteAfterStabilityDelay() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, !self.isClosed, self.browserView != nil else { return }
            KajiBrowserRuntimeCoordinator.shared.markBrowserStartupComplete()
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

    private func updateActiveState(_ active: Bool, browserView: KajiCEFBrowserView) {
        guard activeState != active else { return }
        activeState = active
        browserView.setActive(active)
    }
}
