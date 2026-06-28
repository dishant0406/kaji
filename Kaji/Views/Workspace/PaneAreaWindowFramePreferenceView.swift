import AppKit
import SwiftUI

struct PaneAreaWindowFramePreferenceView: View {
    let areaID: UUID
    @State private var frame: CGRect = .null

    var body: some View {
        WindowFrameReporter { frame = $0 }
            .preference(
                key: PaneAreaFramePreferenceKey.self,
                value: frame.isNull ? [:] : [areaID: frame]
            )
    }
}

private struct WindowFrameReporter: NSViewRepresentable {
    let onChange: (CGRect) -> Void

    func makeNSView(context _: Context) -> ReportingView {
        let view = ReportingView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: ReportingView, context _: Context) {
        view.onChange = onChange
        view.scheduleReport()
    }
}

private final class ReportingView: NSView {
    var onChange: ((CGRect) -> Void)?
    private var lastFrame: CGRect = .null

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        postsFrameChangedNotifications = true
        postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scheduleReportFromNotification),
            name: NSView.frameDidChangeNotification,
            object: self
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scheduleReportFromNotification),
            name: NSView.boundsDidChangeNotification,
            object: self
        )
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleReport()
    }

    override func layout() {
        super.layout()
        scheduleReport()
    }

    func scheduleReport() {
        DispatchQueue.main.async { [weak self] in
            self?.report()
        }
    }

    @objc
    private func scheduleReportFromNotification() {
        scheduleReport()
    }

    private func report() {
        guard let contentView = window?.contentView else { return }
        let rect = convert(bounds, to: contentView)
        let frame = if contentView.isFlipped {
            rect
        } else {
            CGRect(
                x: rect.minX,
                y: contentView.bounds.height - rect.maxY,
                width: rect.width,
                height: rect.height
            )
        }
        guard frame != lastFrame else { return }
        lastFrame = frame
        onChange?(frame)
    }
}
