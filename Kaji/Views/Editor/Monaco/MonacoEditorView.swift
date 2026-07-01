import AppKit
import SwiftUI
import WebKit

private struct MonacoEditorUpdateContext {
    let modelInput: MonacoEditorModelInput
    let contentVisible: Bool
    let contentRevealDuration: TimeInterval
    let themeVersion: Int
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
    let quickOutlineRequestVersion: Int
    let lineNavigationVersion: Int
    let inlineEditRequestVersion: Int
    let inlineEditApplyVersion: Int
    let speechInsertText: String
    let speechInsertVersion: Int
}

struct MonacoEditorView: NSViewRepresentable {
    @Bindable var state: EditorTabState
    let modelInput: MonacoEditorModelInput
    let contentVisible: Bool
    let contentRevealDuration: TimeInterval
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
    let quickOutlineRequestVersion: Int
    let lineNavigationVersion: Int
    let inlineEditRequestVersion: Int
    let inlineEditApplyVersion: Int
    let speechInsertText: String
    let speechInsertVersion: Int
    let onModelActivated: (MonacoEditorRenderToken) -> Void
    let onFocus: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state, typography: typography, onModelActivated: onModelActivated, onFocus: onFocus)
    }

    func makeNSView(context: Context) -> MonacoEditorHostView {
        let hostView = MonacoEditorHostView()
        if let monacoHost = MonacoPreloadService.shared.takeReadyHost() {
            hostView.attach(monacoHost.webView)
            context.coordinator.bind(webView: monacoHost.webView, userContentController: monacoHost.userContentController)
            context.coordinator.bindPreloadedEditor()
            DebugFileLog.log("MonacoEditor", "makeNSView reusedPreload editorID=\(state.id) filePath=\(state.filePath)")
            return hostView
        }

        let monacoHost = MonacoWebViewFactory.makeHost()
        hostView.attach(monacoHost.webView)
        context.coordinator.bind(webView: monacoHost.webView, userContentController: monacoHost.userContentController)
        context.coordinator.loadEditor()
        DebugFileLog.log("MonacoEditor", "makeNSView newHost editorID=\(state.id) filePath=\(state.filePath)")
        return hostView
    }

    func updateNSView(_ hostView: MonacoEditorHostView, context: Context) {
        let coordinator = context.coordinator
        coordinator.updateState(state)
        coordinator.update(
            MonacoEditorUpdateContext(
                modelInput: modelInput,
                contentVisible: contentVisible,
                contentRevealDuration: contentRevealDuration,
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
                quickOutlineRequestVersion: quickOutlineRequestVersion,
                lineNavigationVersion: lineNavigationVersion,
                inlineEditRequestVersion: inlineEditRequestVersion,
                inlineEditApplyVersion: inlineEditApplyVersion,
                speechInsertText: speechInsertText,
                speechInsertVersion: speechInsertVersion
            )
        )
    }

    static func dismantleNSView(_ hostView: MonacoEditorHostView, coordinator: Coordinator) {
        coordinator.dispose()
        hostView.webView?.stopLoading()
        hostView.detach()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, MonacoMessageTarget {
        private var state: EditorTabState
        private let typography: AppTypographySettings
        private let onModelActivated: (MonacoEditorRenderToken) -> Void
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
        private var lastDeferredModelSyncEditorID: UUID?
        private var lastDeferredModelSyncVersion = -1
        private var lastContentVisible: Bool?
        private var lastThemeVersion = -1
        private var lastOptionsFingerprint = ""
        private var lastSearchNeedle = ""
        private var lastSearchNavigationVersion = 0
        private var lastSearchCaseSensitive = false
        private var lastSearchUseRegex = false
        private var lastReplaceVersion = 0
        private var lastReplaceAllVersion = 0
        private var lastEditorFocusVersion = 0
        private var lastQuickOutlineRequestVersion = 0
        private var lastLineNavigationVersion = 0
        private var lastInlineEditRequestVersion = 0
        private var lastInlineEditApplyVersion = 0
        private var lastSpeechInsertVersion = 0
        private var lastMarkdownEditorScrollRequestVersion = 0

        init(
            state: EditorTabState,
            typography: AppTypographySettings,
            onModelActivated: @escaping (MonacoEditorRenderToken) -> Void,
            onFocus: @escaping () -> Void
        ) {
            self.state = state
            self.typography = typography
            self.onModelActivated = onModelActivated
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
            setContentVisible(false, duration: 0)
        }

        func updateState(_ nextState: EditorTabState) {
            guard state.id != nextState.id else {
                state = nextState
                return
            }
            let previousID = state.id
            state = nextState
            resetEditorScopedSyncState(for: nextState)
            DebugFileLog.log(
                "MonacoEditor",
                "switchEditor from=\(previousID) to=\(nextState.id) filePath=\(nextState.filePath)"
            )
            guard hasLoadedEditor, ready else { return }
            bindCurrentEditor()
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

        func bindPreloadedEditor() {
            guard !hasLoadedEditor else { return }
            guard let url = webView?.url else { return }
            hasLoadedEditor = true
            ready = false
            allowedAssetHost = url.host
            allowedAssetPort = url.port
            bindCurrentEditor()
        }

        fileprivate func update(_ context: MonacoEditorUpdateContext) {
            setContentVisible(context.contentVisible, duration: context.contentRevealDuration)
            guard ready else { return }
            syncModelIfNeeded(modelInput: context.modelInput)
            syncOptionsIfNeeded()
            syncThemeIfNeeded(themeVersion: context.themeVersion)
            syncMarkdownScrollRequestIfNeeded()
            if context.focused, lastEditorFocusVersion != context.editorFocusVersion {
                lastEditorFocusVersion = context.editorFocusVersion
                send(command: "focus")
            }
            if lastQuickOutlineRequestVersion != context.quickOutlineRequestVersion {
                lastQuickOutlineRequestVersion = context.quickOutlineRequestVersion
                send(command: "quickOutline")
            }
            if lastLineNavigationVersion != context.lineNavigationVersion {
                lastLineNavigationVersion = context.lineNavigationVersion
                navigateToRequestedLine()
            }
            if lastInlineEditRequestVersion != context.inlineEditRequestVersion {
                lastInlineEditRequestVersion = context.inlineEditRequestVersion
                send(command: "prepareInlineEdit")
            }
            if lastInlineEditApplyVersion != context.inlineEditApplyVersion {
                lastInlineEditApplyVersion = context.inlineEditApplyVersion
                applyInlineEditProposal()
            }
            if lastSpeechInsertVersion != context.speechInsertVersion {
                lastSpeechInsertVersion = context.speechInsertVersion
                insertSpeechText(context.speechInsertText)
            }
            if context.searchNeedle != lastSearchNeedle || context.searchCaseSensitive != lastSearchCaseSensitive || context
                .searchUseRegex != lastSearchUseRegex ||
                context.searchNavigationVersion != lastSearchNavigationVersion
            {
                lastSearchNeedle = context.searchNeedle
                lastSearchCaseSensitive = context.searchCaseSensitive
                lastSearchUseRegex = context.searchUseRegex
                lastSearchNavigationVersion = context.searchNavigationVersion
                sendSearchCommand(direction: context.searchNavigationDirection)
            }
            if lastReplaceVersion != context.replaceVersion {
                lastReplaceVersion = context.replaceVersion
                send(command: "replaceCurrent", payload: ["replacement": .string(context.replaceText)])
            }
            if lastReplaceAllVersion != context.replaceAllVersion {
                lastReplaceAllVersion = context.replaceAllVersion
                send(command: "replaceAll", payload: ["replacement": .string(context.replaceText)])
            }
        }

        func receiveMonacoMessage(_ message: WKScriptMessage) {
            guard let bridgeMessage = decode(message.body) else { return }
            let isCurrentEditor = bridgeMessage.editorID == state.id.uuidString
            if bridgeMessage.type == .ready, !isCurrentEditor {
                bindCurrentEditor()
                return
            }
            guard isCurrentEditor else { return }
            switch bridgeMessage.type {
            case .ready:
                ready = true
                syncModelIfNeeded(force: true)
                syncOptionsIfNeeded(force: true)
                syncThemeIfNeeded(themeVersion: lastThemeVersion, force: true)
                if state.isMarkdownFile {
                    updateMarkdownMetrics(scrollTop: 0, scrollHeight: 0, viewportHeight: 0)
                }
            case .contentChanged:
                if let edits = bridgeMessage.payload?.edits {
                    state.applyMonacoTextEdits(edits)
                    lastSyncedBackingStoreVersion = state.backingStoreVersion
                    publishCurrentRenderToken()
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
            case .diagnosticsChanged:
                let diagnostics = MonacoDiagnosticMapper.diagnostics(
                    for: bridgeMessage.payload?.diagnostics ?? [],
                    filePath: state.filePath,
                    projectPath: state.projectPath
                )
                DiagnosticsStore.shared.setDiagnostics(diagnostics, for: state.filePath)
            case .modelActivated:
                publishActivatedRenderToken(payload: bridgeMessage.payload)
                let version = bridgeMessage.payload?.backingStoreVersion ?? -1
                let uri = bridgeMessage.payload?.uri ?? ""
                DebugFileLog.log(
                    "MonacoEditor",
                    "modelActivated editorID=\(state.id) version=\(version) uri=\(uri)"
                )
            case .error:
                DebugFileLog.log(
                    "MonacoEditor",
                    "bridge error filePath=\(state.filePath) message=\(bridgeMessage.payload?.message ?? "unknown")"
                )
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
            userContentController?.removeScriptMessageHandler(forName: "kajiMonaco")
            webView?.navigationDelegate = nil
            webView = nil
            proxy = nil
        }

        private func syncModelIfNeeded(force: Bool = false, modelInput: MonacoEditorModelInput? = nil) {
            let input = modelInput ?? MonacoEditorModelInput(state: state)
            guard input.editorID == state.id else { return }
            guard input.hasBackingStore, let store = state.backingStore else {
                logDeferredModelSyncIfNeeded(input)
                return
            }
            guard force || lastModelFilePath != input.filePath || lastSyncedBackingStoreVersion != input.backingStoreVersion else { return }
            lastDeferredModelSyncEditorID = nil
            lastDeferredModelSyncVersion = -1
            lastModelFilePath = input.filePath
            lastSyncedBackingStoreVersion = input.backingStoreVersion
            let text = store.fullText()
            let syncDetails = "editorID=\(input.editorID) version=\(input.backingStoreVersion) " +
                "chars=\(text.count) filePath=\(input.filePath)"
            DebugFileLog.log(
                "MonacoEditor",
                "modelSync sending \(syncDetails)"
            )
            send(
                command: "setModel",
                payload: [
                    "uri": .string(URL(fileURLWithPath: input.filePath).absoluteString),
                    "language": .string(MonacoLanguageMapper.languageID(for: input.filePath)),
                    "text": .string(text),
                    "readOnly": .bool(input.isReadOnly),
                    "backingStoreVersion": .int(input.backingStoreVersion),
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

        private func syncMarkdownScrollRequestIfNeeded() {
            guard state.isMarkdownFile else { return }
            guard state.markdownEditorScrollRequestVersion != lastMarkdownEditorScrollRequestVersion else { return }
            lastMarkdownEditorScrollRequestVersion = state.markdownEditorScrollRequestVersion
            guard let scrollY = state.markdownEditorScrollRequestY else { return }
            send(command: "setScrollTop", payload: ["scrollTop": .double(Double(scrollY))])
        }

        private func navigateToRequestedLine() {
            guard let request = state.lineNavigationRequest else { return }
            send(command: "revealLine", payload: ["line": .int(request.line), "column": .int(request.column)])
        }

        private func applyInlineEditProposal() {
            guard !state.inlineEditProposal.isEmpty else { return }
            send(command: "applyInlineEdit", payload: ["text": .string(state.inlineEditProposal)])
        }

        private func insertSpeechText(_ text: String) {
            guard !text.isEmpty else { return }
            send(command: "applyInlineEdit", payload: ["text": .string(text)])
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

        private func send(command: String, payload: [String: MonacoJSONValue] = [:]) {
            let message = MonacoCommand(command: command, editorID: state.id.uuidString, payload: payload)
            guard let data = try? JSONEncoder().encode(message), let json = String(data: data, encoding: .utf8) else { return }
            webView?.evaluateJavaScript("window.kajiMonacoReceive&&window.kajiMonacoReceive(\(json));")
        }

        private func setContentVisible(_ visible: Bool, duration: TimeInterval) {
            guard let webView else { return }
            guard lastContentVisible != visible || (visible && webView.alphaValue < 1) || (!visible && webView.alphaValue > 0)
            else { return }
            lastContentVisible = visible
            webView.isHidden = false
            if !visible || duration <= 0 {
                webView.layer?.removeAllAnimations()
                webView.alphaValue = visible ? 1 : 0
                return
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                webView.animator().alphaValue = 1
            }
        }

        private func publishCurrentRenderToken() {
            onModelActivated(MonacoEditorRenderToken(
                editorID: state.id,
                filePath: state.filePath,
                backingStoreVersion: state.backingStoreVersion
            ))
        }

        private func publishActivatedRenderToken(payload: MonacoBridgePayload?) {
            guard let version = payload?.backingStoreVersion else { return }
            onModelActivated(MonacoEditorRenderToken(
                editorID: state.id,
                filePath: state.filePath,
                backingStoreVersion: version
            ))
        }

        private func bindCurrentEditor() {
            ready = false
            send(command: "bindEditor", payload: ["editorID": .string(state.id.uuidString)])
        }

        private func resetEditorScopedSyncState(for state: EditorTabState) {
            lastModelFilePath = nil
            lastSyncedBackingStoreVersion = -1
            lastDeferredModelSyncEditorID = nil
            lastDeferredModelSyncVersion = -1
            lastSearchNeedle = ""
            lastSearchNavigationVersion = state.searchNavigationVersion
            lastSearchCaseSensitive = state.searchCaseSensitive
            lastSearchUseRegex = state.searchUseRegex
            lastReplaceVersion = state.replaceVersion
            lastReplaceAllVersion = state.replaceAllVersion
            lastEditorFocusVersion = state.editorFocusVersion - 1
            lastQuickOutlineRequestVersion = state.quickOutlineRequestVersion
            lastLineNavigationVersion = state.lineNavigationVersion
            lastInlineEditRequestVersion = state.inlineEditRequestVersion
            lastInlineEditApplyVersion = state.inlineEditApplyVersion
            lastMarkdownEditorScrollRequestVersion = state.markdownEditorScrollRequestVersion
        }

        private func decode(_ body: Any) -> MonacoBridgeMessage? {
            guard JSONSerialization.isValidJSONObject(body),
                  let data = try? JSONSerialization.data(withJSONObject: body)
            else { return nil }
            return try? JSONDecoder().decode(MonacoBridgeMessage.self, from: data)
        }

        private func logDeferredModelSyncIfNeeded(_ input: MonacoEditorModelInput) {
            guard lastDeferredModelSyncEditorID != input.editorID || lastDeferredModelSyncVersion != input.backingStoreVersion
            else { return }
            lastDeferredModelSyncEditorID = input.editorID
            lastDeferredModelSyncVersion = input.backingStoreVersion
            let syncDetails = "editorID=\(input.editorID) version=\(input.backingStoreVersion) " +
                "filePath=\(input.filePath)"
            DebugFileLog.log(
                "MonacoEditor",
                "modelSync deferred noBackingStore \(syncDetails)"
            )
        }
    }
}
