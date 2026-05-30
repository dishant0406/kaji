import SwiftUI

private let languagePacksSettingsFooter = "Language packs install comments, brackets, syntax highlighting metadata, " +
    "and LSP metadata. Native parser artifacts are only used after integrity validation."

struct LanguagePacksSettingsView: View {
    @State private var installed: [LanguageDefinition] = []
    @State private var available: [LanguagePackCatalogEntry] = []
    @State private var statusMessage: String?
    @State private var lastInstalledID: String?
    @State private var failedInstallMessage: String?

    var body: some View {
        SettingsContainer {
            SettingsSection(
                "Language Packs",
                footer: languagePacksSettingsFooter
            ) {
                SettingsRow("Installed") {
                    Text("\(installed.count)")
                        .kajiFont(size: SettingsMetrics.labelFontSize)
                        .foregroundStyle(KajiTheme.fgMuted)
                }
                ForEach(installed) { definition in
                    LanguagePackInstalledRow(definition: definition)
                }
            }

            SettingsSection("Available", showsDivider: false) {
                ForEach(available) { entry in
                    LanguagePackAvailableRow(
                        entry: entry,
                        isInstalled: installed.contains { $0.id == entry.id },
                        recentlyInstalled: lastInstalledID == entry.id,
                        failedMessage: failedInstallMessage
                    ) {
                        install(entry)
                    }
                }
                if let statusMessage {
                    Text(statusMessage)
                        .kajiFont(size: SettingsMetrics.footnoteFontSize)
                        .foregroundStyle(KajiTheme.fgDim)
                        .padding(.horizontal, SettingsMetrics.horizontalPadding)
                        .padding(.vertical, SettingsMetrics.rowVerticalPadding)
                }
            }
        }
        .task { refresh() }
    }

    private func refresh() {
        installed = LanguageRegistry.shared.allDefinitions()
        available = LanguagePackCatalog.allEntries()
    }

    private func install(_ entry: LanguagePackCatalogEntry) {
        switch LanguagePackInstaller.install(entry) {
        case let .success(definition):
            statusMessage = "Installed \(definition.name)"
            lastInstalledID = definition.id
            failedInstallMessage = nil
            ToastState.shared.show("Installed \(definition.name) language pack")
        case let .failure(error):
            statusMessage = error.localizedDescription
            failedInstallMessage = error.localizedDescription
        }
        refresh()
    }
}

private struct LanguagePackInstalledRow: View {
    let definition: LanguageDefinition

    var body: some View {
        SettingsRow(definition.name) {
            Text("\(definition.source.rawValue), \(definition.syntax?.engine.rawValue ?? "no syntax")")
                .kajiFont(size: SettingsMetrics.footnoteFontSize)
                .foregroundStyle(KajiTheme.fgMuted)
        }
    }
}

private struct LanguagePackAvailableRow: View {
    let entry: LanguagePackCatalogEntry
    let isInstalled: Bool
    let recentlyInstalled: Bool
    let failedMessage: String?
    let install: () -> Void

    var body: some View {
        SettingsRow(entry.name) {
            HStack(spacing: 8) {
                Text(entry.version)
                    .kajiFont(size: SettingsMetrics.footnoteFontSize)
                    .foregroundStyle(KajiTheme.fgMuted)
                Button(isInstalled ? "Reinstall" : "Install") {
                    install()
                }
            }
        }
        .kajiChangeFeedback(KajiMotion.successFeedback, value: recentlyInstalled, isEnabled: recentlyInstalled)
        .kajiChangeFeedback(KajiMotion.invalidFeedback, value: failedMessage ?? "", isEnabled: failedMessage != nil)
    }
}
