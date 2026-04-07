import Combine
import Foundation
import os
import Sparkle

private let logger = Logger(subsystem: "app.muxy", category: "UpdateService")

@MainActor @Observable
final class UpdateService: NSObject {
    static let shared = UpdateService()

    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()

    private(set) var canCheckForUpdates = false
    private(set) var availableUpdateVersion: String?

    private var updater: SPUUpdater {
        controller.updater
    }

    override private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: \.canCheckForUpdates, on: self)
            .store(in: &cancellables)
        observeUpdateNotifications()
        applyFeatureFlags()
    }

    func start() {
        do {
            try updater.start()
        } catch {
            logger.warning("Sparkle updater failed to start: \(error.localizedDescription)")
        }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    private func applyFeatureFlags() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["FF_UPDATE_AVAILABLE"] != nil {
            availableUpdateVersion = "0.0.0-dev"
        }
        #endif
    }

    private func observeUpdateNotifications() {
        NotificationCenter.default.publisher(for: .SUUpdaterDidFindValidUpdate)
            .compactMap { $0.userInfo?[SUUpdaterAppcastItemNotificationKey] as? SUAppcastItem }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] item in
                self?.availableUpdateVersion = item.displayVersionString
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .SUUpdaterDidNotFindUpdate)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.availableUpdateVersion = nil
            }
            .store(in: &cancellables)
    }
}
