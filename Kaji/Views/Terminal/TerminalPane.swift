import AppKit
import SwiftUI

struct TerminalPane: View {
    let state: TerminalPaneState
    let focused: Bool
    let visible: Bool
    let onFocus: () -> Void
    let onProcessExit: () -> Void
    let onSplitRequest: (SplitDirection, SplitPosition) -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            TerminalBridge(
                state: state,
                focused: focused,
                visible: visible,
                onFocus: onFocus,
                onProcessExit: onProcessExit,
                onSplitRequest: onSplitRequest
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Terminal")
            .accessibilityAddTraits(.allowsDirectInteraction)
            if state.searchState.isVisible {
                TerminalSearchBar(
                    searchState: state.searchState,
                    onNavigateNext: {
                        let view = TerminalViewRegistry.shared.existingView(for: state.id)
                        view?.navigateSearch(direction: .next)
                    },
                    onNavigatePrevious: {
                        let view = TerminalViewRegistry.shared.existingView(for: state.id)
                        view?.navigateSearch(direction: .previous)
                    },
                    onClose: {
                        let view = TerminalViewRegistry.shared.existingView(for: state.id)
                        view?.endSearch()
                        DispatchQueue.main.async {
                            view?.window?.makeFirstResponder(view)
                        }
                    }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
}

struct TerminalBridge: NSViewRepresentable {
    let state: TerminalPaneState
    let focused: Bool
    let visible: Bool
    let onFocus: () -> Void
    let onProcessExit: () -> Void
    let onSplitRequest: (SplitDirection, SplitPosition) -> Void
    @Environment(\.overlayActive) private var overlayActive
    @Environment(\.activeWorktreeKey) private var worktreeKey

    final class Coordinator {
        var wasFocused = false
        var wasOverlayActive = false
        var wasVisible = true
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> GhosttyTerminalNSView {
        AskHangDebugLog.mark("TerminalBridge.makeNSView.start", [
            "focused": String(focused),
            "injected": state.injectedCommand == nil ? "nil" : "set",
            "paneID": state.id.uuidString,
            "startup": state.startupCommand == nil ? "nil" : "set",
            "visible": String(visible),
        ])
        let registry = TerminalViewRegistry.shared
        let view = registry.view(
            for: state.id,
            workingDirectory: state.projectPath,
            command: state.startupCommand
        )
        AskHangDebugLog.mark("TerminalBridge.makeNSView.afterRegistry", ["paneID": state.id.uuidString])
        if view.envVars.isEmpty, let key = worktreeKey {
            AskHangDebugLog.mark("TerminalBridge.makeNSView.beforeEnv", ["paneID": state.id.uuidString])
            view.envVars = Self.buildEnvVars(paneID: state.id, worktreeKey: key, worktreePath: state.projectPath)
            AskHangDebugLog.mark("TerminalBridge.makeNSView.afterEnv", ["paneID": state.id.uuidString])
        }
        AskHangDebugLog.mark("TerminalBridge.makeNSView.beforeInjected", ["paneID": state.id.uuidString])
        view.setInjectedCommand(state.injectedCommand)
        AskHangDebugLog.mark("TerminalBridge.makeNSView.afterInjected", ["paneID": state.id.uuidString])
        registerInitialAgentSessionIfNeeded()
        AskHangDebugLog.mark("TerminalBridge.makeNSView.afterRegisterSeed", ["paneID": state.id.uuidString])
        view.isFocused = focused
        view.overlayActive = overlayActive
        view.setSurfaceVisible(visible)
        view.onFocus = onFocus
        view.onProcessExit = onProcessExit
        view.onSplitRequest = onSplitRequest
        view.onTitleChange = { [weak state] title in
            DispatchQueue.main.async {
                state?.setTitle(title)
            }
        }
        configureSearchCallbacks(view)
        context.coordinator.wasFocused = focused
        context.coordinator.wasVisible = visible
        if focused, !overlayActive {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                view.window?.makeFirstResponder(view)
            }
        }
        AskHangDebugLog.mark("TerminalBridge.makeNSView.end", ["paneID": state.id.uuidString])
        return view
    }

    func updateNSView(_ nsView: GhosttyTerminalNSView, context: Context) {
        AskHangDebugLog.mark("TerminalBridge.updateNSView.start", [
            "injected": state.injectedCommand == nil ? "nil" : "set",
            "paneID": state.id.uuidString,
            "surface": String(nsView.hasLiveSurface),
            "visible": String(visible),
        ])
        if nsView.envVars.isEmpty, nsView.surface == nil, let key = worktreeKey {
            nsView.envVars = Self.buildEnvVars(paneID: state.id, worktreeKey: key, worktreePath: state.projectPath)
        }
        nsView.setInjectedCommand(state.injectedCommand)
        AskHangDebugLog.mark("TerminalBridge.updateNSView.afterInjected", ["paneID": state.id.uuidString])
        registerInitialAgentSessionIfNeeded()
        AskHangDebugLog.mark("TerminalBridge.updateNSView.afterRegisterSeed", ["paneID": state.id.uuidString])
        nsView.overlayActive = overlayActive
        nsView.onFocus = onFocus
        nsView.onProcessExit = onProcessExit
        nsView.onSplitRequest = onSplitRequest
        nsView.onTitleChange = { [weak state] title in
            DispatchQueue.main.async {
                state?.setTitle(title)
            }
        }
        configureSearchCallbacks(nsView)
        let wasFocused = context.coordinator.wasFocused
        let wasOverlayActive = context.coordinator.wasOverlayActive
        let wasVisible = context.coordinator.wasVisible
        context.coordinator.wasFocused = focused
        context.coordinator.wasOverlayActive = overlayActive
        context.coordinator.wasVisible = visible
        nsView.isFocused = focused
        if visible != wasVisible {
            nsView.setSurfaceVisible(visible)
        }

        if overlayActive {
            if nsView.window?.firstResponder === nsView || nsView.window?.firstResponder === nsView.inputContext {
                nsView.window?.makeFirstResponder(nil)
            }
            if !wasOverlayActive {
                nsView.notifySurfaceUnfocused()
            }
        } else if focused, !wasFocused || wasOverlayActive {
            nsView.notifySurfaceFocused()
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        } else if !focused, wasFocused {
            nsView.notifySurfaceUnfocused()
        }
        AskHangDebugLog.mark("TerminalBridge.updateNSView.end", ["paneID": state.id.uuidString])
    }

    private static func buildEnvVars(
        paneID: UUID,
        worktreeKey key: WorktreeKey,
        worktreePath: String
    ) -> [(key: String, value: String)] {
        var vars: [(key: String, value: String)] = [
            (key: "KAJI_PANE_ID", value: paneID.uuidString),
            (key: "KAJI_INSTANCE_ID", value: ProviderEvent.distributedObject),
            (key: "KAJI_PROJECT_ID", value: key.projectID.uuidString),
            (key: "KAJI_WORKTREE_ID", value: key.worktreeID.uuidString),
            (key: "KAJI_WORKTREE_PATH", value: worktreePath),
            (key: "KAJI_PI_PERMISSION_MODE", value: "prompt"),
        ]
        if let hookClientPath = KajiNotificationHooks.hookClientPath {
            vars.append((key: "KAJI_HOOK_CLIENT_PATH", value: hookClientPath))
        }
        vars.append(contentsOf: KajiCodeGraphInstructions.environment(projectID: key.projectID, worktreeID: key.worktreeID))
        vars.append(contentsOf: CodingAgentShimEnvironment.variables(
            projectID: key.projectID,
            worktreeID: key.worktreeID,
            worktreePath: worktreePath
        ))
        return vars
    }

    private func registerInitialAgentSessionIfNeeded() {
        AskHangDebugLog.mark("TerminalBridge.registerSeed.start", ["paneID": state.id.uuidString])
        guard let seed = state.agentSessionSeed,
               !seed.sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            AskHangDebugLog.mark("TerminalBridge.registerSeed.none", ["paneID": state.id.uuidString])
            return
        }
        AskHangDebugLog.mark("TerminalBridge.registerSeed.beforeStore", ["paneID": state.id.uuidString])
        CodingAgentSessionMetadataStore.shared.update(CodingAgentSessionMetadata(
            providerID: seed.providerID,
            paneID: state.id,
            sessionID: seed.sessionID,
            transcriptPath: seed.transcriptPath,
            title: seed.title,
            cwd: seed.cwd ?? state.projectPath,
            source: "kaji-launch",
            updatedAt: Date()
        ))
        AskHangDebugLog.mark("TerminalBridge.registerSeed.afterStore", ["paneID": state.id.uuidString])
    }

    private func configureSearchCallbacks(_ view: GhosttyTerminalNSView) {
        view.onSearchStart = { [weak state] needle in
            guard let state else { return }
            let searchState = state.searchState
            if let needle, !needle.isEmpty {
                searchState.needle = needle
            }
            searchState.isVisible = true
            searchState.focusVersion += 1
            searchState.startPublishing { [weak view] query in
                view?.sendSearchQuery(query)
            }
            if !searchState.needle.isEmpty {
                searchState.pushNeedle()
            }
        }
        view.onSearchEnd = { [weak state] in
            guard let state else { return }
            state.searchState.stopPublishing()
            state.searchState.isVisible = false
            state.searchState.needle = ""
            state.searchState.total = nil
            state.searchState.selected = nil
        }
        view.onSearchTotal = { [weak state] total in
            state?.searchState.total = total
        }
        view.onSearchSelected = { [weak state] selected in
            state?.searchState.selected = selected
        }
    }
}
