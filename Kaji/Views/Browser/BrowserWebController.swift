import AppKit
import Foundation
import WebKit

@MainActor
final class BrowserWebController {
    weak var surface: NativeBrowserSurfaceView?
    var page: BrowserPageState?
    private var pageChanged: ((UUID, String) -> Void)?
    var popupRequested: ((UUID, String) -> Void)?
    private var navigationDelegate: KajiBrowserNavigationDelegate?
    private var uiDelegate: KajiBrowserUIDelegate?
    private var downloadDelegate: KajiBrowserDownloadDelegate?
    var pendingDialogs: [KajiBrowserPendingDialog] = []
    var popups: [KajiBrowserPopupWindow] = []
    var activeState: Bool?
    var startURL = ""
    private var startTask: Task<Void, Never>?
    var deviceProfile = BrowserDeviceProfiles.profile(for: BrowserDeviceProfiles.desktopID)
    private var isClosed = false
    var appliedDeviceProfile: BrowserDeviceProfile?
    var browserView: KajiBrowserWebView?

    var isReady: Bool { browserView != nil }
    var isDownloading: Bool { downloadDelegate?.isActive == true }

    func attach(_ attachment: BrowserWebControllerAttachment) {
        let previousSurface = surface
        if BrowserSurfaceAttachmentPolicy.shouldReleasePreviousSurface(
            hasPreviousSurface: previousSurface != nil,
            sameSurface: previousSurface === attachment.surface
        ) {
            previousSurface?.release(controller: self, browserView: browserView)
        }
        surface = attachment.surface
        page = attachment.page
        deviceProfile = attachment.deviceProfile
        pageChanged = attachment.callbacks.pageChanged
        popupRequested = attachment.callbacks.popupRequested
        attachment.surface.controller = self
        attachment.surface.applyDeviceProfile(deviceProfile)
        startURL = startURL.isEmpty ? attachment.page.url : startURL
        if let browserView {
            installIfNeeded(browserView, active: attachment.isActive)
            return
        }
        activeState = attachment.isActive
        guard attachment.isActive else {
            attachment.surface.show(status: "")
            return
        }
        ensureStarted(url: attachment.page.url)
    }

    func detach(surface: NativeBrowserSurfaceView) {
        guard self.surface === surface else { return }
        surface.release(controller: self, browserView: browserView)
        if let browserView {
            activeState = false
            browserView.allowsFocus = false
        }
        self.surface = nil
    }

    func ensureStarted(url: String) {
        guard !isClosed else { return }
        startURL = BrowserURLParser.url(from: url)?.absoluteString ?? url
        scheduleStart()
    }

    func navigate(to rawURL: String) {
        guard let url = BrowserURLParser.url(from: rawURL)?.absoluteString else { return }
        startURL = url
        updatePageURL(url)
        guard let browserView else {
            ensureStarted(url: url)
            return
        }
        if let url = URL(string: url) {
            browserView.load(URLRequest(url: url))
        }
    }

    func setActive(_ active: Bool) {
        activeState = active
        browserView?.allowsFocus = active
        if active {
            surface?.focus(browserView: browserView)
        }
    }

    func close() {
        isClosed = true
        startTask?.cancel()
        startTask = nil
        if let surface {
            surface.release(controller: self, browserView: browserView)
        }
        popups.forEach { $0.close() }
        popups.removeAll()
        teardown(webView: browserView)
        browserView = nil
        appliedDeviceProfile = nil
        surface = nil
        page = nil
        pageChanged = nil
        popupRequested = nil
        pendingDialogs.removeAll()
    }

    private func scheduleStart() {
        guard !isClosed, surface != nil, browserView == nil, startTask == nil else { return }
        surface?.show(status: "Starting WebKit…")
        startTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled, let self else { return }
            self.start(url: self.startURL)
            self.startTask = nil
        }
    }

    private func start(url: String) {
        guard !isClosed, surface != nil, browserView == nil else { return }
        let webView = KajiBrowserWebViewFactory.make()
        browserView = webView
        bind(webView)
        installIfNeeded(webView, active: activeState ?? true)
        applyDeviceProfile(deviceProfile)
        let resolved = BrowserURLParser.url(from: url)?.absoluteString ?? "about:blank"
        if let url = URL(string: resolved) {
            webView.load(URLRequest(url: url))
        }
    }

    func installIfNeeded(_ webView: KajiBrowserWebView, active: Bool) {
        if surface?.contains(browserView: webView) != true {
            surface?.install(browserView: webView)
        }
        setActive(active)
    }

    func bind(_ webView: KajiBrowserWebView) {
        let navigationDelegate = KajiBrowserNavigationDelegate()
        let uiDelegate = KajiBrowserUIDelegate()
        let downloadDelegate = KajiBrowserDownloadDelegate()
        navigationDelegate.popupRequested = { [weak self] url in self?.openPopup(url: url.absoluteString) }
        navigationDelegate.started = { [weak self] webView in self?.updateLoading(webView, loading: true) }
        navigationDelegate.finished = { [weak self] webView in self?.updateLoading(webView, loading: false) }
        navigationDelegate.failed = { [weak self] webView, _ in self?.updateLoading(webView, loading: false) }
        navigationDelegate.terminated = { [weak self] webView in self?.recoverTerminated(webView) }
        navigationDelegate.downloadDelegate = downloadDelegate
        uiDelegate.openPopup = { [weak self] configuration, features in self?.openPopup(configuration: configuration, features: features) }
        uiDelegate.closeRequested = { [weak self] webView in self?.closePopup(webView: webView) }
        uiDelegate.dialogRequested = { [weak self] dialog, _ in self?.pendingDialogs.append(dialog) }
        webView.onBackMouse = { [weak self] in self?.goBack() }
        webView.onForwardMouse = { [weak self] in self?.goForward() }
        webView.navigationDelegate = navigationDelegate
        webView.uiDelegate = uiDelegate
        self.navigationDelegate = navigationDelegate
        self.uiDelegate = uiDelegate
        self.downloadDelegate = downloadDelegate
    }

    func teardown(webView: KajiBrowserWebView?) {
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        webView?.removeFromSuperview()
        navigationDelegate = nil
        uiDelegate = nil
        downloadDelegate = nil
    }

    private func updateLoading(_ webView: WKWebView, loading _: Bool) {
        guard webView === browserView else { return }
        updatePage(url: webView.url?.absoluteString ?? startURL, title: webView.title ?? "Browser")
    }

    private func updatePage(url: String, title: String) {
        guard let page else { return }
        updatePageURL(url)
        let resolvedTitle = title.isEmpty ? "Browser" : title
        if page.title != resolvedTitle {
            page.title = resolvedTitle
        }
    }

    private func updatePageURL(_ url: String) {
        guard let page, !url.isEmpty, page.url != url else { return }
        page.url = url
        pageChanged?(page.id, url)
    }
}
