import Foundation
import os

private let logger = Logger(subsystem: "app.droid", category: "NotificationSocketServer")

final class NotificationSocketServer: @unchecked Sendable {
    static let shared = NotificationSocketServer()

    private var serverFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var healthTimer: DispatchSourceTimer?
    private var retryWorkItem: DispatchWorkItem?
    private var wantsListening = false
    private let queue = DispatchQueue(label: "app.droid.notificationSocket")

    static var socketPath: String {
        DroidFileStorage.appSupportDirectory()
            .appendingPathComponent("droid-\(ProcessInfo.processInfo.processIdentifier).sock")
            .path
    }

    private init() {}

    func start() {
        queue.async { [weak self] in
            self?.wantsListening = true
            self?.startHealthChecksIfNeeded()
            self?.startListening()
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.wantsListening = false
            self?.cleanup()
        }
    }

    func restart() {
        queue.async { [weak self] in
            self?.wantsListening = true
            self?.startHealthChecksIfNeeded()
            self?.cleanup()
            self?.startListening()
        }
    }

    private func startListening() {
        guard acceptSource == nil else { return }
        retryWorkItem?.cancel()
        retryWorkItem = nil
        let path = Self.socketPath
        unlink(path)

        serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFD >= 0 else {
            logger.error("Failed to create socket: \(String(cString: strerror(errno)))")
            scheduleRetry()
            return
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let bound = ptr.withMemoryRebound(to: CChar.self, capacity: 104) { $0 }
            _ = path.withCString { strncpy(bound, $0, 103) }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(serverFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            logger.error("Failed to bind socket: \(String(cString: strerror(errno)))")
            close(serverFD)
            serverFD = -1
            scheduleRetry()
            return
        }

        chmod(path, 0o600)

        guard listen(serverFD, 5) == 0 else {
            logger.error("Failed to listen on socket: \(String(cString: strerror(errno)))")
            close(serverFD)
            serverFD = -1
            scheduleRetry()
            return
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: serverFD, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptConnection()
        }
        source.setCancelHandler { [weak self] in
            guard let self, self.serverFD >= 0 else { return }
            close(self.serverFD)
            self.serverFD = -1
            unlink(path)
        }
        acceptSource = source
        source.resume()

        logger.info("Notification socket listening at \(path)")
    }

    private func acceptConnection() {
        let clientFD = accept(serverFD, nil, nil)
        guard clientFD >= 0 else {
            let code = errno
            guard NotificationSocketRecoveryPolicy.shouldRetryAfterAcceptFailure(errno: code) else { return }
            logger.error("Accept failed on notification socket: \(String(cString: strerror(code)))")
            cleanupListener()
            scheduleRetry()
            return
        }

        queue.async { [weak self] in
            self?.handleClient(clientFD)
        }
    }

    private static let maxMessageSize = 65536

    private func handleClient(_ fd: Int32) {
        defer { close(fd) }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let bytesRead = read(fd, &buffer, buffer.count)
            if bytesRead <= 0 { break }
            data.append(contentsOf: buffer[0 ..< bytesRead])
            if data.count > Self.maxMessageSize {
                logger.warning("Client exceeded max message size (\(Self.maxMessageSize) bytes), dropping")
                return
            }
        }

        guard !data.isEmpty else { return }

        for line in data.split(separator: UInt8(ascii: "\n")) {
            processMessage(Data(line))
        }
    }

    private func processMessage(_ data: Data) {
        guard let message = String(data: data, encoding: .utf8) else { return }
        let parts = message.split(
            separator: "|",
            maxSplits: 3,
            omittingEmptySubsequences: false
        ).map(String.init)
        guard parts.count >= 3 else {
            logger.warning("Invalid message on notification socket: expected type|paneID|title|body")
            return
        }

        let type = parts[0]
        let paneIDString = parts[1]
        let rawTitle = parts[2]
        let title = rawTitle.isEmpty ? "Task completed!" : rawTitle
        let body = parts.count > 3 ? parts[3] : ""

        DispatchQueue.main.async { [weak self] in
            self?.dispatchNotification(type: type, title: title, body: body, paneIDString: paneIDString)
        }
    }

    @MainActor
    private func dispatchNotification(type: String, title: String, body: String, paneIDString: String?) {
        if AIActivitySocketRouter.handle(
            .init(type: type, title: title, body: body, paneIDString: paneIDString),
            appState: NotificationStore.shared.appState,
            worktreeStore: NotificationStore.shared.worktreeStore
        ) {
            return
        }

        let source = AIProviderRegistry.shared.notificationSource(for: type)

        guard let appState = NotificationStore.shared.appState else {
            NotificationStore.shared.addDetached(source: source, title: title, body: body)
            logger.warning("Persisted detached notification: appState not ready")
            return
        }

        if let paneIDString, let paneID = UUID(uuidString: paneIDString) {
            completeProviderRunIfNeeded(source: source, paneID: paneID, title: title, body: body)
            NotificationStore.shared.add(
                paneID: paneID,
                source: source,
                title: title,
                body: body,
                appState: appState
            )
            return
        }

        guard let projectID = appState.activeProjectID,
              let key = appState.activeWorktreeKey(for: projectID),
              let context = NotificationFallbackContextResolver.resolve(
                  key: key,
                  appState: appState,
                  worktreeStore: NotificationStore.shared.worktreeStore
              )
        else {
            NotificationStore.shared.addDetached(source: source, title: title, body: body)
            logger.warning("Persisted detached notification: no active pane context for socket fallback")
            return
        }

        NotificationStore.shared.addWithContext(
            context: context,
            source: source,
            title: title,
            body: body,
            appState: appState
        )
    }

    @MainActor
    private func completeProviderRunIfNeeded(source: DroidNotification.Source, paneID: UUID, title: String, body: String) {
        guard case let .aiProvider(providerID) = source else { return }
        let text = "\(title) \(body)".lowercased()
        guard !text.contains("needs permission"),
              !text.contains("needs attention"),
              !text.contains("question"),
              !text.contains("error")
        else { return }
        AIActivityStore.shared.stop(paneID: paneID)
        AgentRunStore.shared.complete(
            providerID: providerID,
            paneID: paneID,
            message: body.isEmpty ? "Session completed" : body
        )
    }

    private func cleanup() {
        retryWorkItem?.cancel()
        retryWorkItem = nil
        healthTimer?.cancel()
        healthTimer = nil
        cleanupListener()
    }

    private func cleanupListener() {
        acceptSource?.cancel()
        acceptSource = nil
    }

    private func scheduleRetry() {
        guard wantsListening, retryWorkItem == nil else { return }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.retryWorkItem = nil
            guard self.wantsListening else { return }
            self.cleanupListener()
            self.startListening()
        }
        retryWorkItem = workItem
        queue.asyncAfter(
            deadline: .now() + NotificationSocketRecoveryPolicy.retryDelaySeconds,
            execute: workItem
        )
    }

    private func startHealthChecksIfNeeded() {
        guard healthTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now() + NotificationSocketRecoveryPolicy.healthCheckIntervalSeconds,
            repeating: NotificationSocketRecoveryPolicy.healthCheckIntervalSeconds
        )
        timer.setEventHandler { [weak self] in
            self?.performHealthCheck()
        }
        healthTimer = timer
        timer.resume()
    }

    private func performHealthCheck() {
        let socketExists = FileManager.default.fileExists(atPath: Self.socketPath)
        let shouldRecover = NotificationSocketRecoveryPolicy.shouldRecover(
            wantsListening: wantsListening,
            socketExists: socketExists,
            hasAcceptSource: acceptSource != nil,
            serverFD: serverFD
        )
        guard shouldRecover else { return }
        logger.notice("Notification socket health check requested listener recovery")
        cleanupListener()
        startListening()
    }
}
