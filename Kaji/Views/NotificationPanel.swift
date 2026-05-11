import SwiftUI

struct NotificationPanelItem: Identifiable {
    let id: UUID
    let sourceIcon: String
    let title: String
    let body: String
    let timestamp: Date
    let isRead: Bool

    var relativeTimestamp: String {
        let interval = Date().timeIntervalSince(timestamp)
        guard interval >= 60 else { return "now" }
        let minutes = Int(interval / 60)
        guard minutes >= 60 else { return "\(minutes)m" }
        let hours = minutes / 60
        guard hours >= 24 else { return "\(hours)h" }
        return "\(hours / 24)d"
    }
}

struct NotificationPanel: View {
    @Environment(AppState.self) private var appState
    let onDismiss: () -> Void

    private var items: [NotificationPanelItem] {
        let store = NotificationStore.shared
        _ = store.readStateVersion
        let registry = AIProviderRegistry.shared
        return store.notifications.map { n in
            NotificationPanelItem(
                id: n.id,
                sourceIcon: registry.iconName(for: n.source),
                title: NotificationDisplayTextResolver.title(
                    for: n,
                    appState: store.appState,
                    worktreeStore: store.worktreeStore
                ),
                body: n.body,
                timestamp: n.timestamp,
                isRead: n.isRead
            )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            let currentItems = items
            if currentItems.isEmpty {
                emptyState
            } else {
                header
                Divider().overlay(KajiTheme.border)
                notificationList(currentItems)
            }
        }
        .frame(width: 320, height: 400)
        .background(
            TranslucentSurface(
                base: KajiTheme.tertiaryBackground,
                material: .menu,
                tintOpacity: 0.64,
                gradientOpacity: 0.06
            )
        )
    }

    private var header: some View {
        HStack {
            Text("Notifications")
                .kajiFont(size: 12, weight: .semibold)
                .foregroundStyle(KajiTheme.fg)
            Spacer()
            Button {
                NotificationStore.shared.clear()
            } label: {
                Text("Clear All")
                    .kajiFont(size: 11)
                    .foregroundStyle(KajiTheme.fgMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func notificationList(_ currentItems: [NotificationPanelItem]) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(currentItems) { item in
                    NotificationRow(item: item, isHighlighted: false, onRemove: {
                        NotificationStore.shared.remove(item.id)
                    })
                    .contentShape(Rectangle())
                    .onTapGesture { selectItem(item) }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(notificationAccessibilityLabel(for: item))
                    .accessibilityAddTraits(.isButton)
                }
            }
            .padding(.vertical, 4)
        }
        .background(KajiTheme.bg.opacity(0.32))
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Notifications")
                    .kajiFont(size: 12, weight: .semibold)
                    .foregroundStyle(KajiTheme.fg)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider().overlay(KajiTheme.border)

            VStack(spacing: 8) {
                Spacer()
                KajiIcon(systemName: "bell.slash", size: 24)
                    .foregroundStyle(KajiTheme.fgMuted)
                Text("No notifications")
                    .kajiFont(size: 12, weight: .medium)
                    .foregroundStyle(KajiTheme.fgMuted)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
        .background(KajiTheme.bg.opacity(0.32))
    }

    private func notificationAccessibilityLabel(for item: NotificationPanelItem) -> String {
        var label = item.title
        if !item.body.isEmpty { label += ": \(item.body)" }
        label += ", \(item.relativeTimestamp)"
        if !item.isRead { label += ", unread" }
        return label
    }

    private func selectItem(_ item: NotificationPanelItem) {
        let store = NotificationStore.shared
        guard let notification = store.notifications.first(where: { $0.id == item.id }) else { return }
        NotificationNavigator.navigate(
            to: notification,
            appState: appState,
            notificationStore: store
        )
        onDismiss()
    }
}

private struct NotificationRow: View {
    let item: NotificationPanelItem
    let isHighlighted: Bool
    let onRemove: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(item.isRead ? Color.clear : KajiTheme.accent)
                .frame(width: 6, height: 6)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    if ProviderIconView.hasIcon(named: item.sourceIcon) {
                        ProviderIconView(iconName: item.sourceIcon, size: 10, style: .monochrome(KajiTheme.fgMuted))
                    } else {
                        KajiIcon(systemName: item.sourceIcon, size: 10)
                            .foregroundStyle(KajiTheme.fgMuted)
                    }
                    Text(item.title)
                        .kajiFont(size: 12, weight: .semibold)
                        .foregroundStyle(KajiTheme.fg)
                        .lineLimit(1)
                    Spacer()
                    Text(item.relativeTimestamp)
                        .kajiFont(size: 10)
                        .foregroundStyle(KajiTheme.fgMuted)
                    if hovered {
                        dismissButton
                    }
                }

                if !item.body.isEmpty {
                    Text(item.body)
                        .kajiFont(size: 11)
                        .foregroundStyle(KajiTheme.fgMuted)
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isHighlighted ? KajiTheme.surface : (hovered ? KajiTheme.hover : .clear))
        .onHover { hovered = $0 }
    }

    private var dismissButton: some View {
        Button {
            onRemove()
        } label: {
            KajiIcon(systemName: "xmark", size: 8)
                .foregroundStyle(KajiTheme.fgMuted)
                .frame(width: 14, height: 14)
                .background(KajiTheme.elevatedBackground, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dismiss Notification")
    }
}
