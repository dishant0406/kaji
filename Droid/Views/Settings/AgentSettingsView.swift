import SwiftUI

struct AgentSettingsView: View {
    @Environment(ProjectStore.self) private var projectStore
    @Environment(AppState.self) private var appState
    @State private var selectedProjectID = ""

    var body: some View {
        SettingsContainer {
            SettingsSection(
                "Verification",
                footer: "Set a project-specific command for Verify Run. Leave blank to auto-detect Swift packages "
                    + "and run swift build && swift test."
            ) {
                SettingsRow("Project") {
                    DroidSelect(
                        options: projectOptions,
                        selection: $selectedProjectID,
                        width: 320
                    )
                }

                SettingsInputRow(
                    label: "Verify command",
                    placeholder: "swift build && swift test",
                    text: verificationCommand,
                    width: 320,
                    monospaced: true
                )
            }
        }
        .onAppear(perform: selectDefaultProject)
        .onChange(of: projectStore.projects.map(\.id)) { _, _ in selectDefaultProject() }
    }

    private var selectedProject: Project? {
        projectStore.projects.first { $0.id.uuidString == selectedProjectID }
    }

    private var projectOptions: [DroidSelectOption<String>] {
        projectStore.projects.map { project in
            DroidSelectOption(id: project.id.uuidString, title: project.name, value: project.id.uuidString)
        }
    }

    private var verificationCommand: Binding<String> {
        Binding(
            get: { selectedProject?.verificationCommand ?? "" },
            set: { value in
                guard let id = UUID(uuidString: selectedProjectID) else { return }
                projectStore.setVerificationCommand(id: id, to: value)
            }
        )
    }

    private func selectDefaultProject() {
        if projectStore.projects.contains(where: { $0.id.uuidString == selectedProjectID }) { return }
        selectedProjectID = appState.activeProjectID?.uuidString ?? projectStore.projects.first?.id.uuidString ?? ""
    }
}
