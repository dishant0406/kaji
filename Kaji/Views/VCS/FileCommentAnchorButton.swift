import SwiftUI

struct FileCommentAnchorButton: NSViewRepresentable {
    let filePath: String
    let symbol: String
    var accessibilityLabel: String = "Comment on file"
    var tintColor: NSColor = .secondaryLabelColor
    let comments: [DiffComment]
    var selected = false
    let action: (CGPoint) -> Void

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imageScaling = .scaleProportionallyDown
        button.wantsLayer = true
        button.target = context.coordinator
        button.action = #selector(Coordinator.clicked(_:))
        button.imagePosition = .imageOnly
        button.setButtonType(.momentaryChange)
        context.coordinator.button = button
        context.coordinator.installTrackingArea(on: button)
        configure(button)
        return button
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSButton, context: Context) -> CGSize? {
        CGSize(width: 22, height: 22)
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.filePath = filePath
        context.coordinator.action = action
        context.coordinator.selected = selected
        configure(nsView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(filePath: filePath, selected: selected, action: action)
    }

    private func configure(_ button: NSButton) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: accessibilityLabel)
        button.contentTintColor = tintColor
        button.toolTip = accessibilityLabel
        button.layer?.cornerRadius = 6
        button.layer?.backgroundColor = selected ? NSColor.controlAccentColor.withAlphaComponent(0.14).cgColor : NSColor.clear.cgColor
    }

    @MainActor
    final class Coordinator: NSObject {
        var filePath: String
        var selected: Bool
        var action: (CGPoint) -> Void
        weak var button: NSButton?
        private var trackingArea: NSTrackingArea?

        init(filePath: String, selected: Bool, action: @escaping (CGPoint) -> Void) {
            self.filePath = filePath
            self.selected = selected
            self.action = action
        }

        func installTrackingArea(on button: NSButton) {
            if let trackingArea {
                button.removeTrackingArea(trackingArea)
            }
            let area = NSTrackingArea(
                rect: button.bounds,
                options: [.mouseEnteredAndExited, .activeInActiveApp],
                owner: self,
                userInfo: nil
            )
            button.addTrackingArea(area)
            trackingArea = area
        }

        @MainActor
        @objc
        func clicked(_ sender: NSButton) {
            guard let window = sender.window else { return }
            let pointInWindow = sender.convert(NSPoint(x: sender.bounds.midX, y: sender.bounds.midY), to: nil)
            action(window.convertPoint(toScreen: pointInWindow))
        }

        func mouseEntered(with event: NSEvent) {
            NSCursor.pointingHand.set()
            button?.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
        }

        func mouseExited(with event: NSEvent) {
            NSCursor.arrow.set()
            button?.layer?.backgroundColor = selected ? NSColor.controlAccentColor.withAlphaComponent(0.14).cgColor : NSColor.clear.cgColor
        }
    }
}
