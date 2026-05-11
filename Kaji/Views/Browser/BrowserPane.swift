import SwiftUI

struct BrowserPane: View {
    @Bindable var state: BrowserPaneState
    let sessionID: String?
    let onClosePane: () -> Void
    @State private var controllers = BrowserControllerRegistry()
    @State private var pendingURL = ""
    @State private var showsPageText = false
    @State private var showsConsole = false
    @State private var isReading = false
    @State private var consoleCommand = ""
    @State private var consoleEntries: [BrowserConsoleEntry] = []
    @State private var isConsoleRunning = false

    private var selectedPage: BrowserPageState? { state.selectedPage }
    private var selectedController: BrowserWebController? {
        selectedPage.map { controllers.controller(for: $0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            tabStrip
            toolbar
            Divider().overlay(KajiTheme.border)
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
                if showsConsole {
                    BrowserConsolePanel(
                        command: $consoleCommand,
                        entries: consoleEntries,
                        isRunning: isConsoleRunning,
                        onRun: { Task { await runConsoleCommand() } },
                        onClose: { showsConsole = false }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .background(KajiTheme.bg)
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
            showsConsole = false
            selectedController?.ensureStarted(url: state.url)
            selectedController?.applyDeviceProfile(selectedDeviceProfile)
            registerBrowserControl()
        }
        .onChange(of: state.selectedDeviceProfileID) { _, _ in
            selectedController?.applyDeviceProfile(selectedDeviceProfile)
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
        .background(KajiTheme.secondaryBackground)
    }

    private var toolbar: some View {
        BrowserToolbar(
            pendingURL: $pendingURL,
            deviceProfileID: $state.selectedDeviceProfileID,
            showsConsole: showsConsole,
            showsPageText: showsPageText,
            onBack: { selectedController?.goBack() },
            onForward: { selectedController?.goForward() },
            onReload: { selectedController?.reload() },
            onNavigate: navigate,
            onToggleConsole: { showsConsole.toggle() },
            onReadPage: { Task { await readPage() } }
        )
    }

    private var pageStack: some View {
        ZStack {
            ForEach(state.pages) { page in
                NativeBrowserSurface(
                    controller: controllers.controller(for: page.id),
                    page: page,
                    projectPath: state.projectPath,
                    isActive: page.id == state.selectedPageID,
                    deviceProfile: selectedDeviceProfile,
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

    private var selectedDeviceProfile: BrowserDeviceProfile {
        BrowserDeviceProfiles.profile(for: state.selectedDeviceProfileID)
    }

    private func registerBrowserControl() {
        guard let sessionID else { return }
        KajiBrowserControlRegistry.shared.register(
            sessionID: sessionID,
            state: state,
            controllers: controllers,
            close: onClosePane
        )
        KajiBrowserControlBroker.shared.updateSession(sessionID)
    }

    private func unregisterBrowserControl() {
        guard let sessionID else { return }
        KajiBrowserControlRegistry.shared.unregister(sessionID: sessionID)
    }

    private func closeBrowserPage(_ pageID: UUID) {
        guard state.pages.count > 1 else {
            controllers.closeAll()
            onClosePane()
            return
        }
        state.closePage(id: pageID)
        pendingURL = state.url
        controllers.removeController(for: pageID)
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

    private func runConsoleCommand() async {
        let command = consoleCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        isConsoleRunning = true
        consoleCommand = ""
        let entry = BrowserConsoleEntry(command: command, result: "", isRunning: true)
        consoleEntries.append(entry)
        let result = await selectedController?.evaluateJavaScript(command) ?? "Browser is not ready."
        if let index = consoleEntries.firstIndex(where: { $0.id == entry.id }) {
            consoleEntries[index].result = result
            consoleEntries[index].isRunning = false
        }
        isConsoleRunning = false
    }
}
