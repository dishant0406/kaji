import AppKit
import SwiftUI
import WebKit

struct MonacoEditorView: NSViewRepresentable {
    @Bindable var state: EditorTabState
    let typography: AppTypographySettings
    let themeVersion: Int
    let showsVerticalScroller: Bool
    let focused: Bool
    let searchNeedle: String
    let searchNavigationVersion: Int
    let searchNavigationDirection: EditorSearchNavigationDirection
    let searchCaseSensitive: Bool
    let searchUseRegex: Bool
    let replaceText: String
    let replaceVersion: Int
    let replaceAllVersion: Int
    let editorFocusVersion: Int
    let symbolNavigationVersion: Int
    let lineNavigationVersion: Int
    let inlineEditRequestVersion: Int
    let inlineEditApplyVersion: Int
    let lspChangeVersion: Int
    let onFocus: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state, typography: typography, onFocus: onFocus)
    }

    func makeNSView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.allowsAirPlayForMediaPlayback = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = KajiTheme.nsBg
        webView.wantsLayer = true
        webView.layer?.backgroundColor = KajiTheme.nsBg.cgColor
        if #available(macOS 13.3, *) {
            webView.isInspectable = false
        }
        context.coordinator.bind(webView: webView, userContentController: controller)
        context.coordinator.loadEditor()
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.updateState(state)
        coordinator.update(
            themeVersion: themeVersion,
            focused: focused,
            searchNeedle: searchNeedle,
            searchNavigationVersion: searchNavigationVersion,
            searchNavigationDirection: searchNavigationDirection,
            searchCaseSensitive: searchCaseSensitive,
            searchUseRegex: searchUseRegex,
            replaceText: replaceText,
            replaceVersion: replaceVersion,
            replaceAllVersion: replaceAllVersion,
            editorFocusVersion: editorFocusVersion,
            symbolNavigationVersion: symbolNavigationVersion,
            lineNavigationVersion: lineNavigationVersion,
            inlineEditRequestVersion: inlineEditRequestVersion,
            inlineEditApplyVersion: inlineEditApplyVersion,
            lspChangeVersion: lspChangeVersion
        )
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.dispose()
        webView.stopLoading()
        webView.removeFromSuperview()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, MonacoMessageTarget {
        private var state: EditorTabState
        private let typography: AppTypographySettings
        private let onFocus: () -> Void
        private weak var webView: WKWebView?
        private var userContentController: WKUserContentController?
        private var proxy: MonacoMessageProxy?
        private var ready = false
        private var hasLoadedEditor = false
        private var allowedAssetHost: String?
        private var allowedAssetPort: Int?
        private var lastModelFilePath: String?
        private var lastSyncedBackingStoreVersion = -1
        private var lastThemeVersion = -1
        private var lastOptionsFingerprint = ""
        private var lastDiagnosticsFingerprint = ""
        private var lastSearchNeedle = ""
        private var lastSearchNavigationVersion = 0
        private var lastSearchCaseSensitive = false
        private var lastSearchUseRegex = false
        private var lastReplaceVersion = 0
        private var lastReplaceAllVersion = 0
        private var lastEditorFocusVersion = 0
        private var lastSymbolNavigationVersion = 0
        private var lastLineNavigationVersion = 0
        private var lastInlineEditRequestVersion = 0
        private var lastInlineEditApplyVersion = 0
        private var lastLSPChangeVersion = 0
        private var lastMarkdownEditorScrollRequestVersion = 0
        private var lspTask: Task<Void, Never>?

        init(state: EditorTabState, typography: AppTypographySettings, onFocus: @escaping () -> Void) {
            self.state = state
            self.typography = typography
            self.onFocus = onFocus
            super.init()
        }

        func bind(webView: WKWebView, userContentController: WKUserContentController) {
            self.webView = webView
            self.userContentController = userContentController
            let proxy = MonacoMessageProxy(target: self)
            self.proxy = proxy
            userContentController.add(proxy, name: "kajiMonaco")
            webView.navigationDelegate = self
        }

        func updateState(_ state: EditorTabState) {
            self.state = state
        }

        func loadEditor() {
            guard !hasLoadedEditor else { return }
            guard let url = MonacoAssetServer.shared.ensureStarted() else {
                state.errorMessage = "Monaco editor runtime is missing. Run scripts/build-monaco-runtime.sh."
                return
            }
            hasLoadedEditor = true
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.queryItems = [URLQueryItem(name: "editorID", value: state.id.uuidString)]
            guard let editorURL = components?.url else { return }
            allowedAssetHost = editorURL.host
            allowedAssetPort = editorURL.port
            webView?.load(URLRequest(url: editorURL))
        }

        func update(
            themeVersion: Int,
            focused: Bool,
            searchNeedle: String,
            searchNavigationVersion: Int,
            searchNavigationDirection: EditorSearchNavigationDirection,
            searchCaseSensitive: Bool,
            searchUseRegex: Bool,
            replaceText: String,
            replaceVersion: Int,
            replaceAllVersion: Int,
            editorFocusVersion: Int,
            symbolNavigationVersion: Int,
            lineNavigationVersion: Int,
            inlineEditRequestVersion: Int,
            inlineEditApplyVersion: Int,
            lspChangeVersion: Int
        ) {
            guard ready else { return }
            syncModelIfNeeded()
            syncOptionsIfNeeded()
            syncThemeIfNeeded(themeVersion: themeVersion)
            syncDiagnosticsIfNeeded()
            syncMarkdownScrollRequestIfNeeded()
            if focused, lastEditorFocusVersion != editorFocusVersion {
                lastEditorFocusVersion = editorFocusVersion
                send(command: "focus")
            }
            if lastSymbolNavigationVersion != symbolNavigationVersion {
                lastSymbolNavigationVersion = symbolNavigationVersion
                navigateToRequestedSymbol()
            }
            if lastLineNavigationVersion != lineNavigationVersion {
                lastLineNavigationVersion = lineNavigationVersion
                navigateToRequestedLine()
            }
            if lastInlineEditRequestVersion != inlineEditRequestVersion {
                lastInlineEditRequestVersion = inlineEditRequestVersion
                send(command: "prepareInlineEdit")
            }
            if lastInlineEditApplyVersion != inlineEditApplyVersion {
                lastInlineEditApplyVersion = inlineEditApplyVersion
                applyInlineEditProposal()
            }
            if searchNeedle != lastSearchNeedle || searchCaseSensitive != lastSearchCaseSensitive || searchUseRegex != lastSearchUseRegex || searchNavigationVersion != lastSearchNavigationVersion {
                lastSearchNeedle = searchNeedle
                lastSearchCaseSensitive = searchCaseSensitive
                lastSearchUseRegex = searchUseRegex
                lastSearchNavigationVersion = searchNavigationVersion
                sendSearchCommand(direction: searchNavigationDirection)
            }
            if lastReplaceVersion != replaceVersion {
                lastReplaceVersion = replaceVersion
                send(command: "replaceCurrent", payload: ["replacement": .string(replaceText)])
            }
            if lastReplaceAllVersion != replaceAllVersion {
                lastReplaceAllVersion = replaceAllVersion
                send(command: "replaceAll", payload: ["replacement": .string(replaceText)])
            }
            if lastLSPChangeVersion != lspChangeVersion {
                lastLSPChangeVersion = lspChangeVersion
                scheduleLanguageServerChange()
            }
        }

        func receiveMonacoMessage(_ message: WKScriptMessage) {
            guard let bridgeMessage = decode(message.body) else { return }
            guard bridgeMessage.editorID == state.id.uuidString else { return }
            switch bridgeMessage.type {
            case .ready:
                ready = true
                syncModelIfNeeded(force: true)
                syncOptionsIfNeeded(force: true)
                syncThemeIfNeeded(themeVersion: lastThemeVersion, force: true)
                syncDiagnosticsIfNeeded(force: true)
                if state.isMarkdownFile {
                    updateMarkdownMetrics(scrollTop: 0, scrollHeight: 0, viewportHeight: 0)
                }
            case .contentChanged:
                if let edits = bridgeMessage.payload?.edits {
                    state.applyMonacoTextEdits(edits)
                    lastSyncedBackingStoreVersion = state.backingStoreVersion
                    scheduleLanguageServerChange()
                    syncDiagnosticsIfNeeded(force: true)
                }
            case .cursorChanged:
                state.updateCursorPosition(
                    line: bridgeMessage.payload?.line ?? 1,
                    column: bridgeMessage.payload?.column ?? 1,
                    selectionLength: bridgeMessage.payload?.selectionLength ?? 0
                )
            case .selectionChanged:
                state.currentSelection = bridgeMessage.payload?.text ?? ""
            case .scrollChanged:
                updateMarkdownMetrics(
                    scrollTop: CGFloat(bridgeMessage.payload?.scrollTop ?? 0),
                    scrollHeight: CGFloat(bridgeMessage.payload?.scrollHeight ?? 0),
                    viewportHeight: CGFloat(bridgeMessage.payload?.viewportHeight ?? 0)
                )
            case .saveRequested:
                state.saveFile()
            case .focusChanged:
                if bridgeMessage.payload?.focused == true {
                    onFocus()
                }
            case .inlineSelection:
                state.proposeInlineEdit(instruction: state.inlineEditInstruction, original: bridgeMessage.payload?.text ?? "")
            case .searchState:
                state.searchMatchCount = bridgeMessage.payload?.count ?? 0
                state.searchCurrentIndex = bridgeMessage.payload?.index ?? 0
                state.searchInvalidRegex = bridgeMessage.payload?.invalidRegex ?? false
            case .error:
                DebugFileLog.log("MonacoEditor", "bridge error filePath=\(state.filePath) message=\(bridgeMessage.payload?.message ?? "unknown")")
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor action: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = action.request.url else {
                decisionHandler(.cancel)
                return
            }
            guard url.host == allowedAssetHost, url.port == allowedAssetPort else {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func dispose() {
            lspTask?.cancel()
            userContentController?.removeScriptMessageHandler(forName: "kajiMonaco")
            webView?.navigationDelegate = nil
            webView = nil
            proxy = nil
        }

        private func syncModelIfNeeded(force: Bool = false) {
            guard let store = state.backingStore else { return }
            guard force || lastModelFilePath != state.filePath || lastSyncedBackingStoreVersion != state.backingStoreVersion else { return }
            lastModelFilePath = state.filePath
            lastSyncedBackingStoreVersion = state.backingStoreVersion
            send(
                command: "setModel",
                payload: [
                    "uri": .string(URL(fileURLWithPath: state.filePath).absoluteString),
                    "language": .string(MonacoLanguageMapper.languageID(for: state.filePath)),
                    "text": .string(store.fullText()),
                    "readOnly": .bool(state.isReadOnly),
                ]
            )
        }

        private func syncOptionsIfNeeded(force: Bool = false) {
            let payload = MonacoEditorOptionsMapper.options(settings: EditorSettings.shared, typography: typography)
            let fingerprint = String(describing: payload)
            guard force || fingerprint != lastOptionsFingerprint else { return }
            lastOptionsFingerprint = fingerprint
            send(command: "updateOptions", payload: payload)
        }

        private func syncThemeIfNeeded(themeVersion: Int, force: Bool = false) {
            guard force || themeVersion != lastThemeVersion else { return }
            lastThemeVersion = themeVersion
            send(command: "setTheme", payload: MonacoThemeMapper.theme())
        }

        private func syncDiagnosticsIfNeeded(force: Bool = false) {
            let diagnostics = DiagnosticsStore.shared.diagnostics(for: state.filePath)
            let fingerprint = diagnostics.map { "\($0.id)|\($0.line)|\($0.column)|\($0.severity.rawValue)|\($0.message)" }.joined(separator: "\n")
            guard force || fingerprint != lastDiagnosticsFingerprint else { return }
            lastDiagnosticsFingerprint = fingerprint
            send(command: "setDiagnostics", payload: ["markers": .array(MonacoMarkerMapper.markers(for: diagnostics))])
        }

        private func syncMarkdownScrollRequestIfNeeded() {
            guard state.isMarkdownFile else { return }
            guard state.markdownEditorScrollRequestVersion != lastMarkdownEditorScrollRequestVersion else { return }
            lastMarkdownEditorScrollRequestVersion = state.markdownEditorScrollRequestVersion
            guard let scrollY = state.markdownEditorScrollRequestY else { return }
            send(command: "setScrollTop", payload: ["scrollTop": .double(Double(scrollY))])
        }

        private func navigateToRequestedSymbol() {
            guard let symbol = state.symbolNavigationRequest else { return }
            send(command: "revealLine", payload: ["line": .int(symbol.line), "column": .int(1)])
        }

        private func navigateToRequestedLine() {
            guard let request = state.lineNavigationRequest else { return }
            send(command: "revealLine", payload: ["line": .int(request.line), "column": .int(request.column)])
        }

        private func applyInlineEditProposal() {
            guard !state.inlineEditProposal.isEmpty else { return }
            send(command: "applyInlineEdit", payload: ["text": .string(state.inlineEditProposal)])
        }

        private func sendSearchCommand(direction: EditorSearchNavigationDirection) {
            send(command: "find", payload: [
                "needle": .string(state.searchNeedle),
                "caseSensitive": .bool(state.searchCaseSensitive),
                "regex": .bool(state.searchUseRegex),
                "direction": .string(direction == .previous ? "previous" : "next"),
            ])
        }

        private func updateMarkdownMetrics(scrollTop: CGFloat, scrollHeight: CGFloat, viewportHeight: CGFloat) {
            guard state.isMarkdownFile, state.markdownScrollSyncEnabled else { return }
            state.markdownEditorScrollY = scrollTop
            state.markdownEditorViewportHeight = viewportHeight
            state.markdownEditorMaxScrollY = max(0, scrollHeight - viewportHeight)
            state.markdownEditorLineHeight = max(1, ceil(typography.nsFont(size: AppTypographySettings.defaultFontSize).pointSize * 1.45))
            let output = state.markdownSyncCoordinator.editorDidScroll(scrollY: scrollTop, map: state.currentMarkdownSyncMap())
            state.applyMarkdownSyncOutput(output)
        }

        private func scheduleLanguageServerChange() {
            lspTask?.cancel()
            lspTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 180_000_000)
                await MainActor.run {
                    guard let self else { return }
                    self.state.syncLanguageServerAfterEditorChange()
                    self.syncDiagnosticsIfNeeded(force: true)
                }
            }
        }

        private func send(command: String, payload: [String: MonacoJSONValue] = [:]) {
            let message = MonacoCommand(command: command, editorID: state.id.uuidString, payload: payload)
            guard let data = try? JSONEncoder().encode(message), let json = String(data: data, encoding: .utf8) else { return }
            webView?.evaluateJavaScript("window.kajiMonacoReceive&&window.kajiMonacoReceive(\(json));")
        }

        private func decode(_ body: Any) -> MonacoBridgeMessage? {
            guard JSONSerialization.isValidJSONObject(body), let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
            return try? JSONDecoder().decode(MonacoBridgeMessage.self, from: data)
        }
    }
}
