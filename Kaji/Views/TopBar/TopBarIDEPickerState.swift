import Foundation
import Observation
import os

private let topBarIDELogger = Logger(subsystem: "app.kaji", category: "TopBarIDEPicker")

@MainActor
@Observable
final class TopBarIDEPickerState {
    var ides: [ExternalIDE] = []
    var iconPathsByIDEID: [String: String] = [:]
    var isLoading = false
    var isOpening = false

    @ObservationIgnored private let settings: ExternalIDESettings
    @ObservationIgnored private let catalog: ExternalIDECatalog
    @ObservationIgnored private let openService: ExternalIDEOpenService
    @ObservationIgnored private let refreshInterval: TimeInterval
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var lastRefresh: Date?

    init(
        settings: ExternalIDESettings = .shared,
        catalog: ExternalIDECatalog = ExternalIDECatalog(),
        openService: ExternalIDEOpenService? = nil,
        refreshInterval: TimeInterval = 60
    ) {
        self.settings = settings
        self.catalog = catalog
        self.openService = openService ?? ExternalIDEOpenService(catalog: catalog)
        self.refreshInterval = refreshInterval
    }

    deinit {
        refreshTask?.cancel()
    }

    var selectedIDE: ExternalIDE? {
        if let selectedID = settings.selectedIDEID,
           let ide = ides.first(where: { $0.id == selectedID })
        {
            return ide
        }
        return ides.first
    }

    var selectedIDEID: String? {
        settings.selectedIDEID
    }

    var selectedIDEIconPath: String? {
        guard let selectedIDE else { return nil }
        return iconPathsByIDEID[selectedIDE.id]
    }

    func refreshIfNeeded() {
        guard !isLoading else { return }
        guard ides.isEmpty || shouldRefresh else { return }
        reload()
    }

    func reload() {
        refreshTask?.cancel()
        isLoading = true
        let catalog = catalog
        let customApplications = settings.customApplications
        let startedAt = Date()
        refreshTask = Task { [weak self] in
            let snapshot = await GitProcessRunner.offMain {
                let ides = catalog.installedIDEs(customApplications: customApplications)
                let iconPaths = ExternalIDEIconResolver(catalog: catalog).iconPaths(for: ides)
                return (ides: ides, iconPaths: iconPaths)
            }
            guard !Task.isCancelled, let self else { return }
            apply(snapshot.ides, iconPaths: snapshot.iconPaths, startedAt: startedAt)
        }
    }

    func addCustomApplication(at url: URL) {
        settings.addCustomApplication(at: url)
        reload()
    }

    func open(_ ide: ExternalIDE, projectPath: String) {
        settings.select(ide.id)
        isOpening = true
        Task { [weak self] in
            guard let self else { return }
            defer { isOpening = false }
            do {
                try await openService.open(projectPath: projectPath, in: ide)
                ToastState.shared.show("Opened in \(ide.displayName)")
            } catch {
                ToastState.shared.show(errorText(error))
            }
        }
    }

    func openSelected(projectPath: String) {
        guard let selectedIDE else {
            ToastState.shared.show("Choose an IDE first.")
            return
        }
        open(selectedIDE, projectPath: projectPath)
    }

    private func errorText(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private var shouldRefresh: Bool {
        guard let lastRefresh else { return true }
        return Date().timeIntervalSince(lastRefresh) >= refreshInterval
    }

    private func apply(_ resolved: [ExternalIDE], iconPaths: [String: String], startedAt: Date) {
        ides = resolved
        iconPathsByIDEID = iconPaths
        isLoading = false
        lastRefresh = Date()
        updateSelection()
        let elapsed = Date().timeIntervalSince(startedAt)
        if elapsed > 0.25 {
            topBarIDELogger.warning("External IDE scan finished slowly count=\(resolved.count) duration=\(elapsed)")
        } else {
            topBarIDELogger.debug("External IDE scan finished count=\(resolved.count) duration=\(elapsed)")
        }
    }

    private func updateSelection() {
        guard !ides.isEmpty else {
            settings.select(nil)
            return
        }
        if let selected = settings.selectedIDEID,
           ides.contains(where: { $0.id == selected })
        {
            return
        }
        settings.select(ides[0].id)
    }
}
