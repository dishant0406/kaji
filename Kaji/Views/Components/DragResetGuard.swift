import AppKit
import SwiftUI

struct DragResetGuard: ViewModifier {
    @Binding var isDragging: Bool
    @Binding var generation: Int

    @State private var globalMouseUpMonitor: Any?
    @State private var localMouseUpMonitor: Any?
    @State private var resignObserver: NSObjectProtocol?

    func body(content: Content) -> some View {
        content
            .onAppear(perform: attachMonitors)
            .onDisappear(perform: detachMonitors)
    }

    private func attachMonitors() {
        guard globalMouseUpMonitor == nil, localMouseUpMonitor == nil, resignObserver == nil else { return }

        globalMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { _ in
            scheduleReset()
        }
        localMouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { event in
            scheduleReset()
            return event
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: nil,
            queue: .main
        ) { _ in
            scheduleReset()
        }
    }

    private func detachMonitors() {
        if let globalMouseUpMonitor {
            NSEvent.removeMonitor(globalMouseUpMonitor)
        }
        if let localMouseUpMonitor {
            NSEvent.removeMonitor(localMouseUpMonitor)
        }
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
        }
        globalMouseUpMonitor = nil
        localMouseUpMonitor = nil
        resignObserver = nil
    }

    private func scheduleReset() {
        guard isDragging else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            if isDragging {
                generation += 1
                isDragging = false
            }
        }
    }
}

extension View {
    func dragResetGuard(isDragging: Binding<Bool>, generation: Binding<Int>) -> some View {
        modifier(DragResetGuard(isDragging: isDragging, generation: generation))
    }
}
