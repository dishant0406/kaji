import AppKit
import Foundation
import os

private let logger = Logger(subsystem: "app.kaji", category: "NotificationStore")

@MainActor
@Observable
final class NotificationStore {
    static let shared = NotificationStore()

    var appState: AppState?
    var worktreeStore: WorktreeStore?

    private(set) var notifications: [KajiNotification] = []
    private(set) var readStateVersion: Int = 0

    private static let maxNotifications = 200
    private static let defaults = UserDefaults.standard
    private static let fileURL = KajiFileStorage.fileURL(filename: "notifications.json")
    private var saveTask: Task<Void, Never>?

    private init() {
        notifications = Self.loadFromDisk()
    }

    var unreadCount: Int {
        _ = readStateVersion
        return notifications.count { !$0.isRead }
    }

    func unreadCount(for projectID: UUID) -> Int {
        _ = readStateVersion
        return notifications.count { !$0.isRead && $0.projectID == projectID }
    }

    func unreadCount(for projectID: UUID, worktreeID: UUID) -> Int {
        _ = readStateVersion
        return notifications.count { !$0.isRead && $0.projectID == projectID && $0.worktreeID == worktreeID }
    }

    func hasUnread(tabID: UUID) -> Bool {
        _ = readStateVersion
        return notifications.contains { !$0.isRead && $0.tabID == tabID }
    }

    func markAsRead(tabID: UUID) {
        var changed = false
        for notification in notifications where !notification.isRead && notification.tabID == tabID {
            notification.isRead = true
            changed = true
        }
        if changed {
            readStateVersion += 1
            scheduleSave()
        }
    }

    func add(
        paneID: UUID,
        source: KajiNotification.Source,
        title: String,
        body: String,
        appState: AppState
    ) {
        if let worktreeStore,
           let context = NotificationNavigator.resolveContext(
               for: paneID,
               appState: appState,
               worktreeStore: worktreeStore
           )
        {
            let notification = KajiNotification(
                paneID: paneID,
                projectID: context.projectID,
                worktreeID: context.worktreeID,
                areaID: context.areaID,
                tabID: context.tabID,
                worktreePath: context.worktreePath,
                source: source,
                title: title,
                body: body
            )
            insertIfNotFocused(notification, appState: appState)
            return
        }

        if let projectID = appState.activeProjectID,
           let key = appState.activeWorktreeKey(for: projectID),
           let context = NotificationFallbackContextResolver.resolve(
               key: key,
               appState: appState,
               worktreeStore: worktreeStore
           )
        {
            logger.warning("Notification pane context missing for \(paneID.uuidString, privacy: .public); falling back to active context")
            addWithContext(
                context: context,
                paneID: paneID,
                source: source,
                title: title,
                body: body,
                appState: appState
            )
            return
        }

        logger.warning("Notification pane context missing for \(paneID.uuidString, privacy: .public); persisting detached notification")
        addDetached(source: source, title: title, body: body)
    }

    func addWithContext(
        context: NavigationContext,
        paneID: UUID = UUID(),
        source: KajiNotification.Source,
        title: String,
        body: String,
        appState: AppState
    ) {
        let notification = KajiNotification(
            paneID: paneID,
            projectID: context.projectID,
            worktreeID: context.worktreeID,
            areaID: context.areaID,
            tabID: context.tabID,
            worktreePath: context.worktreePath,
            source: source,
            title: title,
            body: body
        )
        insertIfNotFocused(notification, appState: appState)
    }

    func addDetached(
        source: KajiNotification.Source,
        title: String,
        body: String,
        markRead: Bool = false
    ) {
        let notification = KajiNotification(
            paneID: UUID(),
            projectID: UUID(),
            worktreeID: UUID(),
            areaID: UUID(),
            tabID: UUID(),
            worktreePath: "",
            source: source,
            title: title,
            body: body,
            isRead: markRead
        )
        clearActivityIfNeeded(for: notification)
        switch CodingAgentNotificationCoalescer.merge(notification, into: &notifications) {
        case .replaced:
            scheduleSave()
            deliverOutbound(notification, event: normalizedEvent(for: notification))
            return
        case .ignored:
            scheduleSave()
            return
        case .none:
            break
        }
        guard !NotificationDeduplicator.isDuplicate(notification, in: notifications) else { return }
        notifications.insert(notification, at: 0)
        trimIfNeeded()
        scheduleSave()
        deliverNotification(notification)
    }

    private func insertIfNotFocused(_ notification: KajiNotification, appState: AppState) {
        let decision = NotificationDeliveryDecision.resolve(
            isAppActive: NSApp?.isActive ?? false,
            isTargetTabActive: NotificationNavigator.isActiveTab(notification.tabID, appState: appState)
        )
        notification.isRead = decision == .persistReadAndDeliver
        clearActivityIfNeeded(for: notification)
        switch CodingAgentNotificationCoalescer.merge(notification, into: &notifications) {
        case .replaced:
            scheduleSave()
            deliverOutbound(notification, event: normalizedEvent(for: notification))
            return
        case .ignored:
            scheduleSave()
            return
        case .none:
            break
        }
        guard !NotificationDeduplicator.isDuplicate(notification, in: notifications) else { return }

        notifications.insert(notification, at: 0)
        trimIfNeeded()
        scheduleSave()
        deliverNotification(notification)
    }

    private func deliverNotification(_ notification: KajiNotification) {
        let event = normalizedEvent(for: notification)
        if suppressesUserDelivery(for: notification, event: event) {
            return
        }
        if Self.defaults.bool(forKey: "kaji.notifications.toastEnabled", fallback: true) {
            ToastState.shared.show(
                NotificationDisplayTextResolver.title(
                    for: notification,
                    appState: appState,
                    worktreeStore: worktreeStore
                )
            )
        }
        playSound(for: event)
        deliverOutbound(notification, event: event)
    }

    private func suppressesUserDelivery(for notification: KajiNotification, event: NotificationOutboundEvent) -> Bool {
        guard event.kind == .completed,
              case .aiProvider = notification.source
        else { return false }
        return AIProviderRegistry.shared.notificationPolicy(for: notification.source).suppressCompletionUserDelivery
    }

    private func normalizedEvent(for notification: KajiNotification) -> NotificationOutboundEvent {
        NotificationEventNormalizer.normalize(
            notification: notification,
            appState: appState,
            worktreeStore: worktreeStore
        )
    }

    private func deliverOutbound(_ notification: KajiNotification, event: NotificationOutboundEvent) {
        CodingAgentOutboundNotificationCoordinator.shared.deliver(notification: notification, event: event) { event in
            await NotificationIntegrationStore.shared.deliver(event)
        }
    }

    private func playSound(for event: NotificationOutboundEvent) {
        let defaultSoundName = Self.defaults.string(forKey: "kaji.notifications.sound") ?? NotificationSound.funk.rawValue
        let defaultSound = NotificationSound(rawValue: defaultSoundName) ?? .funk
        let resolvedSound = NotificationRouteSoundResolver.resolve(
            routes: NotificationIntegrationStore.shared.routes,
            event: event,
            defaultSound: defaultSound
        )
        guard resolvedSound != .none else { return }
        NSSound(named: .init(resolvedSound.rawValue))?.play()
    }

    func markAsRead(_ id: UUID) {
        guard let index = notifications.firstIndex(where: { $0.id == id }) else { return }
        notifications[index].isRead = true
        readStateVersion += 1
        scheduleSave()
    }

    func markAllAsRead() {
        var changed = false
        for notification in notifications where !notification.isRead {
            notification.isRead = true
            changed = true
        }
        if changed {
            readStateVersion += 1
            scheduleSave()
        }
    }

    func markAllAsRead(projectID: UUID) {
        var changed = false
        for notification in notifications where !notification.isRead && notification.projectID == projectID {
            notification.isRead = true
            changed = true
        }
        if changed {
            readStateVersion += 1
            scheduleSave()
        }
    }

    func remove(_ id: UUID) {
        notifications.removeAll { $0.id == id }
        scheduleSave()
    }

    func remove(projectID: UUID) {
        let originalCount = notifications.count
        notifications.removeAll { $0.projectID == projectID }
        guard notifications.count != originalCount else { return }
        readStateVersion += 1
        scheduleSave()
    }

    func clear() {
        notifications.removeAll()
        scheduleSave()
    }

    private func trimIfNeeded() {
        guard notifications.count > Self.maxNotifications else { return }
        notifications = Array(notifications.prefix(Self.maxNotifications))
    }

    private func clearActivityIfNeeded(for notification: KajiNotification) {
        guard let providerID = providerID(for: notification),
              normalizedEvent(for: notification).kind == .completed
        else {
            return
        }
        let message = notification.body.isEmpty ? "Session completed" : notification.body
        if AIActivityStore.shared.stop(paneID: notification.paneID) != nil {
            AgentRunStore.shared.complete(providerID: providerID, paneID: notification.paneID, message: message)
            return
        }
        AIActivityStore.shared.stop(
            providerID: providerID,
            projectID: notification.projectID,
            worktreeID: notification.worktreeID
        )
        AgentRunStore.shared.complete(
            providerID: providerID,
            projectID: notification.projectID,
            worktreeID: notification.worktreeID,
            message: message
        )
    }

    private func providerID(for notification: KajiNotification) -> String? {
        guard case let .aiProvider(providerID) = notification.source else { return nil }
        return providerID
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.saveToDisk()
        }
    }

    func saveToDisk() {
        do {
            let data = try JSONEncoder().encode(notifications)
            try data.write(to: Self.fileURL, options: .atomic)
        } catch {
            logger.error("Failed to save notifications: \(error.localizedDescription)")
        }
    }

    private static func loadFromDisk() -> [KajiNotification] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            let loaded = try JSONDecoder().decode([KajiNotification].self, from: data)
            return Array(loaded.prefix(maxNotifications))
        } catch {
            logger.error("Failed to load notifications: \(error.localizedDescription)")
            return []
        }
    }
}

extension UserDefaults {
    func bool(forKey key: String, fallback: Bool) -> Bool {
        object(forKey: key) != nil ? bool(forKey: key) : fallback
    }
}
