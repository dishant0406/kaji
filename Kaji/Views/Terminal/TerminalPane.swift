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
                            view?.focusTerminalInput()
                        }
                    }
                )
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
        var registeredSeedKey: String?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> TermyTerminalNSView {
        let registry = TerminalViewRegistry.shared
        let view = registry.view(
            for: state.id,
            workingDirectory: state.projectPath,
            command: state.startupCommand
        )
        if view.envVars.isEmpty, let key = worktreeKey {
            view.envVars = Self.buildEnvVars(paneID: state.id, worktreeKey: key, worktreePath: state.projectPath)
        }
        view.setInjectedCommand(state.injectedCommand)
        registerInitialAgentSessionIfNeeded(context: context)
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
                view.focusTerminalInput()
            }
        }
        return view
    }

    func updateNSView(_ nsView: TermyTerminalNSView, context: Context) {
        if nsView.envVars.isEmpty, !nsView.hasTerminalRuntime, let key = worktreeKey {
            nsView.envVars = Self.buildEnvVars(paneID: state.id, worktreeKey: key, worktreePath: state.projectPath)
        }
        nsView.setInjectedCommand(state.injectedCommand)
        registerInitialAgentSessionIfNeeded(context: context)
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
            if nsView.ownsFirstResponder(nsView.window?.firstResponder) {
                nsView.window?.makeFirstResponder(nil)
            }
            if !wasOverlayActive {
                nsView.notifySurfaceUnfocused()
            }
        } else if focused, !wasFocused || wasOverlayActive {
            nsView.notifySurfaceFocused()
            DispatchQueue.main.async {
                nsView.focusTerminalInput()
            }
        } else if !focused, wasFocused {
            nsView.notifySurfaceUnfocused()
        }
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
        if let resourceURL = Bundle.appResources.resourceURL?.appendingPathComponent("termy", isDirectory: true) {
            vars.append((key: "TERMY_RESOURCES_DIR", value: resourceURL.path))
        }
        vars.append(contentsOf: KajiTerminalShellEnvironment.variables())
        return vars
    }

    private func registerInitialAgentSessionIfNeeded(context: Context) {
        guard let seed = state.agentSessionSeed,
              !seed.sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        let seedKey = "\(seed.providerID):\(seed.sessionID):\(state.id.uuidString)"
        guard context.coordinator.registeredSeedKey != seedKey else { return }
        context.coordinator.registeredSeedKey = seedKey
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
    }

    private func configureSearchCallbacks(_ view: TermyTerminalNSView) {
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
