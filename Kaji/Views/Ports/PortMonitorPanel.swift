import SwiftUI

struct PortMonitorPanel: View {
    let onDismiss: () -> Void

    @State private var service = PortMonitorService.shared
    @State private var query = ""
    @State private var pendingKill: PortProcessSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            KajiInput(placeholder: "Filter ports or processes", text: $query, leadingIcon: "magnifyingglass", monospaced: true)
            content
            status
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 380)
        .background(KajiTheme.tertiaryBackground, in: RoundedRectangle(cornerRadius: KajiShape.panelRadius))
        .confirmationDialog(
            "Kill process on :\(pendingKill?.port ?? 0)?",
            isPresented: pendingKillPresented,
            titleVisibility: .visible,
            presenting: pendingKill
        ) { snapshot in
            Button("Kill pid \(snapshot.pid)", role: .destructive) {
                service.terminate(snapshot)
                pendingKill = nil
            }
            Button("Cancel", role: .cancel) {
                pendingKill = nil
            }
        } message: { snapshot in
            Text("This sends SIGTERM to \(snapshot.processName) listening on port \(snapshot.port).")
        }
        .task {
            service.refresh()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            KajiIcon(systemName: "network", size: 12)
                .foregroundStyle(KajiTheme.fgMuted)
            Text("Running Ports")
                .kajiFont(size: 12, weight: .semibold)
                .foregroundStyle(KajiTheme.fg)

            Spacer(minLength: 8)

            Text("\(service.ports.count)")
                .kajiFont(size: 10, weight: .semibold, design: .monospaced)
                .foregroundStyle(KajiTheme.fgDim)

            Button(action: service.refresh) {
                Group {
                    if service.isRefreshing {
                        KajiSpinner(size: 12, lineWidth: 1.5)
                    } else {
                        KajiIcon(systemName: "arrow.clockwise", size: 11)
                    }
                }
                .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .kajiPointer()
            .foregroundStyle(KajiTheme.fgMuted)
            .disabled(service.isRefreshing)
            .help("Refresh")

            Button(action: onDismiss) {
                KajiIcon(systemName: "xmark", size: 11)
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .kajiPointer()
            .foregroundStyle(KajiTheme.fgMuted)
            .help("Close")
        }
    }

    @ViewBuilder
    private var content: some View {
        if filteredPorts.isEmpty {
            Text(emptyText)
                .kajiFont(size: 12)
                .foregroundStyle(KajiTheme.fgDim)
                .frame(maxWidth: .infinity, minHeight: 120)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(filteredPorts) { snapshot in
                        PortMonitorRow(
                            snapshot: snapshot,
                            isKilling: service.killingPID == snapshot.pid,
                            onKill: { pendingKill = snapshot }
                        )
                    }
                }
            }
            .frame(maxHeight: 360)
        }
    }

    @ViewBuilder
    private var status: some View {
        if let message = service.statusMessage {
            Text(message)
                .kajiFont(size: 11)
                .foregroundStyle(service.statusIsError ? KajiTheme.diffRemoveFg : KajiTheme.fgDim)
                .lineLimit(2)
        }
    }

    private var filteredPorts: [PortProcessSnapshot] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return service.ports }
        return service.ports.filter { snapshot in
            snapshot.processName.localizedCaseInsensitiveContains(trimmed) ||
                "\(snapshot.port)".contains(trimmed) ||
                "\(snapshot.pid)".contains(trimmed)
        }
    }

    private var emptyText: String {
        service.isRefreshing ? "Scanning ports..." : "No listening ports found."
    }

    private var pendingKillPresented: Binding<Bool> {
        Binding(
            get: { pendingKill != nil },
            set: { if !$0 { pendingKill = nil } }
        )
    }
}
