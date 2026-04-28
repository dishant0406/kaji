import AppKit
import SwiftUI

struct NotificationRouteModal: View {
    let existing: NotificationRoutingRule?
    let destinations: [NotificationDeliveryDestination]
    let onCancel: () -> Void
    let onSave: (NotificationRoutingRule) -> Void
    @State private var draft: NotificationRoutingRule
    @State private var selectedDestinationIDs: Set<UUID>
    @State private var selectedSound = defaultSoundOptionID

    private static let defaultSoundOptionID = "__default__"

    init(
        existing: NotificationRoutingRule?,
        destinations: [NotificationDeliveryDestination],
        onCancel: @escaping () -> Void,
        onSave: @escaping (NotificationRoutingRule) -> Void
    ) {
        self.existing = existing
        self.destinations = destinations
        self.onCancel = onCancel
        self.onSave = onSave
        let route = existing ?? NotificationRoutingRule(
            name: "Notify all Codex completions",
            source: .codex,
            eventKind: .completed,
            destinationIDs: destinations.prefix(1).map(\.id)
        )
        _draft = State(initialValue: route)
        _selectedDestinationIDs = State(initialValue: Set(route.destinationIDs))
        _selectedSound = State(initialValue: route.sound?.rawValue ?? Self.defaultSoundOptionID)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(DroidTheme.border)
            VStack(alignment: .leading, spacing: 14) {
                NotificationFormRow("Name") {
                    DroidInput(placeholder: "Notify all Codex completions", text: $draft.name, width: 420)
                }
                HStack(alignment: .top, spacing: 12) {
                    NotificationFormRow("Source") {
                        DroidSelect(
                            options: NotificationRoutingRule.SourceFilter.allCases.map {
                                DroidSelectOption(id: $0.rawValue, title: $0.rawValue, value: $0)
                            },
                            selection: $draft.source,
                            width: 190
                        )
                    }
                    NotificationFormRow("Event") {
                        DroidSelect(
                            options: NotificationRoutingRule.KindFilter.allCases.map {
                                DroidSelectOption(id: $0.rawValue, title: $0.rawValue, value: $0)
                            },
                            selection: $draft.eventKind,
                            width: 190
                        )
                    }
                }
                NotificationFormRow("Sound") {
                    DroidSelect(
                        options: soundOptions,
                        selection: $selectedSound,
                        width: 190
                    )
                    .onChange(of: selectedSound) { _, newValue in
                        previewSound(newValue)
                    }
                }
                NotificationFormBlock("Send To") {
                    if destinations.isEmpty {
                        Text("Create a destination first, then come back to route notifications to it.")
                            .droidFont(size: SettingsMetrics.footnoteFontSize)
                            .foregroundStyle(DroidTheme.fgDim)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(
                                DroidTheme.secondaryBackground,
                                in: RoundedRectangle(cornerRadius: DroidShape.controlRadius)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: DroidShape.controlRadius)
                                    .stroke(DroidTheme.border, lineWidth: 1)
                            )
                    } else {
                        VStack(spacing: 0) {
                            ForEach(destinations) { destination in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(destination.name)
                                            .droidFont(size: SettingsMetrics.labelFontSize)
                                            .foregroundStyle(DroidTheme.fg)
                                        Text(destination.type.rawValue)
                                            .droidFont(size: SettingsMetrics.footnoteFontSize)
                                            .foregroundStyle(DroidTheme.fgDim)
                                    }
                                    Spacer()
                                    DroidSwitch(isOn: binding(for: destination.id))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                if destination.id != destinations.last?.id {
                                    Divider().overlay(DroidTheme.border)
                                }
                            }
                        }
                        .background(DroidTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: DroidShape.controlRadius))
                        .overlay(RoundedRectangle(cornerRadius: DroidShape.controlRadius).stroke(DroidTheme.border, lineWidth: 1))
                    }
                }
            }
            .padding(18)
            Divider().overlay(DroidTheme.border)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DroidTheme.bg.opacity(0.34))
    }

    private var header: some View {
        HStack {
            Text(existing == nil ? "New Rule" : "Edit Rule")
                .droidFont(size: 13, weight: .semibold)
                .foregroundStyle(DroidTheme.fg)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(DroidTheme.chrome.opacity(0.42))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Spacer()
            Button("Cancel", action: onCancel)
                .buttonStyle(DroidButtonStyle(.secondary))
            Button(existing == nil ? "Create" : "Save") {
                draft.destinationIDs = Array(selectedDestinationIDs)
                draft.sound = selectedSound == Self.defaultSoundOptionID ? nil : NotificationSound(rawValue: selectedSound)
                onSave(draft)
            }
            .buttonStyle(DroidButtonStyle(.primary))
            .disabled(!canSave)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(DroidTheme.chrome.opacity(0.42))
    }

    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !selectedDestinationIDs.isEmpty
    }

    private func binding(for destinationID: UUID) -> Binding<Bool> {
        Binding(
            get: { selectedDestinationIDs.contains(destinationID) },
            set: { isOn in
                if isOn {
                    selectedDestinationIDs.insert(destinationID)
                } else {
                    selectedDestinationIDs.remove(destinationID)
                }
            }
        )
    }

    private var soundOptions: [DroidSelectOption<String>] {
        [DroidSelectOption(id: Self.defaultSoundOptionID, title: "Use app default", value: Self.defaultSoundOptionID)] +
            NotificationSound.allCases.map {
                DroidSelectOption(id: $0.rawValue, title: $0.rawValue, value: $0.rawValue)
            }
    }

    private func previewSound(_ value: String) {
        guard value != Self.defaultSoundOptionID,
              let sound = NotificationSound(rawValue: value),
              sound != .none
        else {
            return
        }
        NSSound(named: .init(sound.rawValue))?.play()
    }
}
