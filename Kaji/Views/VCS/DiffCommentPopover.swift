import SwiftUI

@MainActor
private enum DiffCommentPopoverRegistry {
    private static var activePopover: NSPopover?
    private static var activeOwner: UUID?

    static func replace(with popover: NSPopover, owner: UUID) {
        if let activePopover, activeOwner != owner {
            activePopover.delegate = nil
            activePopover.performClose(nil)
        }
        activePopover = popover
        activeOwner = owner
    }

    static func clear(owner: UUID) {
        if activeOwner == owner {
            activePopover = nil
            activeOwner = nil
        }
    }
}

struct DiffCommentDraftPopoverContent: View {
    let anchor: DiffCommentAnchor
    var initialText: String = ""
    let onSave: (String) -> Void
    let onCancel: () -> Void
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Comment on \(anchor.summary)")
                .kajiFont(size: 12, weight: .semibold)
                .foregroundStyle(KajiTheme.fg)
            KajiTextArea(
                placeholder: "Leave a comment",
                text: $text,
                minHeight: 110,
                maxHeight: 110,
                onShiftEnter: { onSave(text) }
            )
            .frame(width: 360, height: 110)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .kajiFont(size: 12)
                    .foregroundStyle(KajiTheme.fgMuted)
                Button("Save") { onSave(text) }
                    .buttonStyle(.plain)
                    .kajiFont(size: 12, weight: .semibold)
                    .foregroundStyle(KajiTheme.accent)
            }
        }
        .padding(12)
        .frame(width: 384)
        .background(KajiTheme.tertiaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear { text = initialText }
        .onExitCommand(perform: onCancel)
    }
}

struct DiffCommentWindowPopover: NSViewRepresentable {
    @Binding var request: DiffCommentDraftRequest?
    let onSave: (DiffCommentAnchor, String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(request: $request, onSave: onSave)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.hostView = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.hostView = nsView
        context.coordinator.update(request)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.cleanup()
    }

    @MainActor
    final class Coordinator: NSObject, NSPopoverDelegate {
        @Binding private var request: DiffCommentDraftRequest?
        private let onSave: (DiffCommentAnchor, String) -> Void
        private let id = UUID()
        private var popover: NSPopover?
        private var presentedID: UUID?
        private var isClosing = false
        weak var hostView: NSView?

        init(request: Binding<DiffCommentDraftRequest?>, onSave: @escaping (DiffCommentAnchor, String) -> Void) {
            _request = request
            self.onSave = onSave
            super.init()
        }

        func update(_ request: DiffCommentDraftRequest?) {
            guard let request else {
                close()
                return
            }
            guard presentedID != request.id else { return }
            present(request)
        }

        private func present(_ request: DiffCommentDraftRequest) {
            guard let hostView, let window = hostView.window, let contentView = window.contentView else { return }
            close()
            let popover = NSPopover()
            popover.behavior = .transient
            popover.animates = true
            popover.delegate = self
            let controller = NSHostingController(rootView: AnyView(
                DiffCommentDraftPopoverContent(anchor: request.anchor, initialText: request.initialText) { [weak self] text in
                    self?.onSave(request.anchor, text)
                    self?.request = nil
                    self?.close()
                } onCancel: { [weak self] in
                    self?.request = nil
                    self?.close()
                }
            ))
            controller.view.appearance = NSAppearance(named: .darkAqua)
            controller.view.wantsLayer = true
            controller.view.layer?.cornerRadius = 12
            controller.view.layer?.masksToBounds = true
            popover.contentViewController = controller
            popover.contentSize = NSSize(width: 384, height: 180)
            DiffCommentPopoverRegistry.replace(with: popover, owner: id)
            self.popover = popover
            presentedID = request.id

            let windowPoint = window.convertPoint(fromScreen: request.windowPoint)
            let contentPoint = contentView.convert(windowPoint, from: nil)
            popover.show(
                relativeTo: NSRect(x: contentPoint.x, y: contentPoint.y, width: 1, height: 1),
                of: contentView,
                preferredEdge: .maxX
            )
        }

        private func close() {
            guard !isClosing else { return }
            isClosing = true
            let closingPopover = popover
            if closingPopover != nil {
                DiffCommentPopoverRegistry.clear(owner: id)
            }
            popover = nil
            presentedID = nil
            closingPopover?.delegate = nil
            closingPopover?.performClose(nil)
            isClosing = false
        }

        func cleanup() {
            close()
            hostView = nil
        }

        deinit {
            MainActor.assumeIsolated {
                cleanup()
            }
        }

        func popoverDidClose(_ notification: Notification) {
            guard let closedPopover = notification.object as? NSPopover,
                  closedPopover === popover
            else { return }
            request = nil
            close()
        }
    }
}
