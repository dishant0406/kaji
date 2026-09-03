import AppKit

@MainActor
enum KajiAgentScrollViewOperations {
    static func distanceFromBottom(_ scrollView: NSScrollView) -> CGFloat {
        let documentHeight = scrollView.documentView?.frame.height ?? 0
        return max(0, documentHeight - scrollView.documentVisibleRect.maxY)
    }

    static func bottomOriginY(_ scrollView: NSScrollView) -> CGFloat {
        let documentHeight = scrollView.documentView?.frame.height ?? 0
        let visibleHeight = scrollView.documentVisibleRect.height
        return max(0, documentHeight - visibleHeight)
    }

    static func setOriginY(_ y: CGFloat, in scrollView: NSScrollView, animated: Bool) {
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                scrollView.contentView.animator().setBoundsOrigin(NSPoint(x: 0, y: y))
            }
        } else {
            scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: y))
        }
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    static func findView(withIdentifier identifier: String, in view: NSView) -> NSView? {
        if view.identifier?.rawValue == identifier {
            return view
        }
        for subview in view.subviews {
            if let found = findView(withIdentifier: identifier, in: subview) {
                return found
            }
        }
        return nil
    }
}
