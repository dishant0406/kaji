import SwiftUI

struct BrowserPane: View {
    @Bindable var state: BrowserPaneState
    let sessionID: String?
    let onClosePane: () -> Void
    @State private var controllers = BrowserControllerRegistry()
    @State private var pendingURL = ""
    @State private var showsPageText = false
    @State private var isReading = false

    private var selectedPage: BrowserPageState? { state.selectedPage }
    private var selectedController: BrowserWebController? {
        selectedPage.map { controllers.controller(for: $0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            tabStrip
            toolbar
            Divider().overlay(DroidTheme.border)
            ZStack(alignment: .bottom) {
                pageStack
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                if showsPageText {
                    BrowserPageTextPanel(
                        title: isReading ? "Reading page…" : "Page text",
                        text: state.pageSummary,
                        onClose: { showsPageText = false }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .background(DroidTheme.bg)
        .clipped()
        .task {
            pendingURL = state.url
            registerBrowserControl()
        }
        .onDisappear {
            unregisterBrowserControl()
            controllers.closeAll()
        }
        .onChange(of: state.url) { _, newValue in
            pendingURL = newValue
        }
        .onChange(of: state.selectedPageID) { _, _ in
            pendingURL = state.url
            showsPageText = false
            selectedController?.ensureStarted(url: state.url)
            registerBrowserControl()
        }
    }

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(state.pages) { page in
                    BrowserTabButton(
                        page: page,
                        selected: page.id == state.selectedPageID,
                        onSelect: {
                            state.selectPage(id: page.id)
                            pendingURL = page.url
                        },
                        onClose: { closeBrowserPage(page.id) }
                    )
                }
                IconButton(symbol: "plus", accessibilityLabel: "New browser tab") {
                    let page = state.openPage()
                    pendingURL = page.url
                    controllers.controller(for: page.id).ensureStarted(url: page.url)
                }
                .help("New tab")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
        .background(DroidTheme.secondaryBackground)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            IconButton(symbol: "arrow.left", accessibilityLabel: "Back") {
                selectedController?.goBack()
            }
            IconButton(symbol: "arrow.right", accessibilityLabel: "Forward") {
                selectedController?.goForward()
            }
            IconButton(symbol: "arrow.clockwise", accessibilityLabel: "Reload") {
                selectedController?.reload()
            }
            TextField("Search or enter URL", text: $pendingURL)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(DroidTheme.surface, in: RoundedRectangle(cornerRadius: DroidShape.tileRadius))
                .onSubmit { navigate() }
            IconButton(symbol: "paperplane", accessibilityLabel: "Open URL") {
                navigate()
            }
            IconButton(symbol: "text.page", selected: showsPageText, accessibilityLabel: "Read Page") {
                Task { await readPage() }
            }
            .help("Read page text")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(DroidTheme.secondaryBackground)
    }

    private var pageStack: some View {
        ZStack {
            ForEach(state.pages) { page in
                NativeBrowserSurface(
                    controller: controllers.controller(for: page.id),
                    page: page,
                    projectPath: state.projectPath,
                    isActive: page.id == state.selectedPageID,
                    callbacks: BrowserSurfaceCallbacks(pageChanged: pageChanged, popupRequested: popupRequested)
                )
                .opacity(page.id == state.selectedPageID ? 1 : 0)
                .allowsHitTesting(page.id == state.selectedPageID)
            }
        }
    }

    private func navigate() {
        selectedController?.navigate(to: pendingURL)
    }

    private func registerBrowserControl() {
        guard let sessionID else { return }
        DroidBrowserControlRegistry.shared.register(
            sessionID: sessionID,
            state: state,
            controllers: controllers,
            close: onClosePane
        )
    }

    private func unregisterBrowserControl() {
        guard let sessionID else { return }
        DroidBrowserControlRegistry.shared.unregister(sessionID: sessionID)
    }

    private func closeBrowserPage(_ pageID: UUID) {
        guard state.pages.count > 1 else {
            controllers.closeAll()
            onClosePane()
            return
        }
        controllers.removeController(for: pageID)
        state.closePage(id: pageID)
        pendingURL = state.url
    }

    private func pageChanged(pageID: UUID, url: String) {
        if pageID == state.selectedPageID, pendingURL != url {
            pendingURL = url
        }
    }

    private func popupRequested(pageID _: UUID, url: String) {
        let page = state.openPage(url: url.isEmpty ? "about:blank" : url)
        pendingURL = page.url
        controllers.controller(for: page.id).ensureStarted(url: page.url)
    }

    private func readPage() async {
        isReading = true
        showsPageText = true
        defer { isReading = false }
        do {
            state.pageSummary = try await selectedController?.readPage() ?? ""
        } catch {
            state.pageSummary = error.localizedDescription
        }
    }
}
