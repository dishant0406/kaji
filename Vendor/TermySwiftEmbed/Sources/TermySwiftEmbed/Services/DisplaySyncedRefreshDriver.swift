import CoreVideo
import Foundation
import QuartzCore

final class DisplaySyncedRefreshDriver: @unchecked Sendable {
    var cadence: RefreshCadence = .active

    private var displayLink: CVDisplayLink?
    private var fallbackTimer: Timer?
    private let onTick: @MainActor () -> Void
    private var lastDeliveredUptime: TimeInterval?
    private var isRunning = false
    private var thermalState = ProcessInfo.processInfo.thermalState
    private var thermalObserver: NSObjectProtocol?
    /// Guards the dispatch pre-filter state shared with the CoreVideo callback
    /// thread (`displayLinkTick`).
    private let dispatchGate = NSLock()
    private var dispatchGap: TimeInterval = 0
    private var lastDispatchUptime: TimeInterval = 0

    init(onTick: @escaping @MainActor () -> Void) {
        self.onTick = onTick
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else {
                return
            }
            self.thermalState = ProcessInfo.processInfo.thermalState
            self.updateDispatchGap()
        }
    }

    deinit {
        // Tear down the display link before the object is freed. `stop()` calls
        // `CVDisplayLinkStop`, which fences against an in-flight callback on the
        // CoreVideo thread, so the unretained `self` pointer handed to the
        // callback can never be dereferenced after deallocation. Without this a
        // window closing while the link runs leaves a live 60 Hz callback (and a
        // running fallback Timer) pointing at freed memory.
        stop()
        if let thermalObserver {
            NotificationCenter.default.removeObserver(thermalObserver)
        }
    }

    /// The minimum gap between ticks, raised under thermal pressure so a hot
    /// machine throttles the 60 Hz active cadence rather than fighting the fans.
    private var effectiveInterval: TimeInterval {
        max(cadence.interval, Self.thermalFloor(thermalState))
    }

    static func thermalFloor(_ state: ProcessInfo.ThermalState) -> TimeInterval {
        switch state {
        case .nominal,
             .fair:
            return 0
        case .serious:
            return 1.0 / 30.0
        case .critical:
            return 1.0 / 15.0
        @unknown default:
            return 0
        }
    }

    /// The CoreVideo-thread pre-filter threshold: half the delivery interval, so
    /// link-fire jitter can never starve `deliverTickIfDue`, while ticks that
    /// would certainly be dropped (a ProMotion link fires at 120 Hz against a
    /// 60 Hz cadence) are discarded before the main-queue hop.
    static func dispatchGap(deliveryInterval: TimeInterval) -> TimeInterval {
        deliveryInterval * 0.5
    }

    func start(cadence: RefreshCadence) {
        self.cadence = cadence
        updateDispatchGap()
        guard !isRunning else {
            return
        }
        isRunning = true
        lastDeliveredUptime = nil

        guard cadence == .active else {
            startFallbackTimer()
            return
        }

        var link: CVDisplayLink?
        let status = CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard status == kCVReturnSuccess, let link else {
            startFallbackTimer()
            return
        }

        displayLink = link
        let context = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(link, displayLinkCallback, context)
        if CVDisplayLinkStart(link) != kCVReturnSuccess {
            displayLink = nil
            startFallbackTimer()
        }
    }

    func stop() {
        isRunning = false
        fallbackTimer?.invalidate()
        fallbackTimer = nil
        if let displayLink {
            CVDisplayLinkStop(displayLink)
            CVDisplayLinkSetOutputCallback(displayLink, nil, nil)
            self.displayLink = nil
        }
        lastDeliveredUptime = nil
        dispatchGate.lock()
        lastDispatchUptime = 0
        dispatchGate.unlock()
    }

    private func updateDispatchGap() {
        let gap = Self.dispatchGap(deliveryInterval: effectiveInterval)
        dispatchGate.lock()
        dispatchGap = gap
        dispatchGate.unlock()
    }

    private func startFallbackTimer() {
        fallbackTimer?.invalidate()
        let timer = Timer(timeInterval: cadence.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.deliverTickIfDue()
            }
        }
        timer.tolerance = cadence.interval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        fallbackTimer = timer
    }

    fileprivate func displayLinkTick() {
        // Drop over-rate link fires here, on the CoreVideo thread, so they never
        // cost a main-queue hop: `deliverTickIfDue` still enforces the full
        // delivery interval for whatever gets through.
        let now = CACurrentMediaTime()
        dispatchGate.lock()
        let due = now - lastDispatchUptime >= dispatchGap
        if due {
            lastDispatchUptime = now
        }
        dispatchGate.unlock()
        guard due else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.deliverTickIfDue()
        }
    }

    @MainActor
    private func deliverTickIfDue() {
        guard isRunning else {
            return
        }

        let now = CACurrentMediaTime()
        if let lastDeliveredUptime,
           now - lastDeliveredUptime < effectiveInterval
        {
            return
        }

        lastDeliveredUptime = now
        onTick()
    }
}

private let displayLinkCallback: CVDisplayLinkOutputCallback = {
    _, _, _, _, _, userInfo in
    guard let userInfo else {
        return kCVReturnSuccess
    }

    let driver = Unmanaged<DisplaySyncedRefreshDriver>
        .fromOpaque(userInfo)
        .takeUnretainedValue()
    driver.displayLinkTick()
    return kCVReturnSuccess
}
