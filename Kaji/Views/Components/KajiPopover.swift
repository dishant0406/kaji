import AppKit
import SwiftUI

enum KajiPopoverEdge {
    case top
    case bottom
    case leading
    case trailing

    var nsRectEdge: NSRectEdge {
        switch self {
        case .top:
            .maxY
        case .bottom:
            .minY
        case .leading:
            .minX
        case .trailing:
            .maxX
        }
    }
}

struct KajiPopoverModifier<PopoverContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let preferredEdge: KajiPopoverEdge
    let content: () -> PopoverContent

    func body(content base: Content) -> some View {
        base.background(
            KajiPopoverPresenter(
                isPresented: $isPresented,
                preferredEdge: preferredEdge,
                content: self.content
            )
        )
    }
}

extension View {
    func kajiPopover(
        isPresented: Binding<Bool>,
        preferredEdge: KajiPopoverEdge,
        @ViewBuilder content: @escaping () -> some View
    ) -> some View {
        modifier(
            KajiPopoverModifier(
                isPresented: isPresented,
                preferredEdge: preferredEdge,
                content: content
            )
        )
    }
}

@MainActor
private struct KajiPopoverPresenter<PopoverContent: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    let preferredEdge: KajiPopoverEdge
    let content: () -> PopoverContent

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.present(
            from: nsView,
            isPresented: isPresented,
            preferredEdge: preferredEdge,
            makeRootView: {
                AnyView(KajiPopoverSurface(content: content))
            }
        )
    }

    @MainActor
    final class Coordinator: NSObject, NSPopoverDelegate {
        @Binding private var isPresented: Bool
        private let popover = NSPopover()
        private var hostingController: NSHostingController<AnyView>?

        init(isPresented: Binding<Bool>) {
            _isPresented = isPresented
            super.init()
            popover.behavior = .transient
            popover.animates = true
            popover.delegate = self
        }

        func attach(to view: NSView) {
            view.postsFrameChangedNotifications = true
        }

        func present(
            from view: NSView,
            isPresented: Bool,
            preferredEdge: KajiPopoverEdge,
            makeRootView: () -> AnyView
        ) {
            if !KajiPopoverPresentationPolicy.shouldPreparePopover(
                isPresented: isPresented,
                isShown: popover.isShown
            ) {
                return
            }

            let rootView = makeRootView()

            if hostingController == nil {
                hostingController = NSHostingController(rootView: rootView)
                hostingController?.view.appearance = NSAppearance(named: .darkAqua)
            } else {
                hostingController?.rootView = rootView
            }

            guard let hostingController else { return }

            popover.contentViewController = hostingController
            hostingController.view.layoutSubtreeIfNeeded()
            popover.contentSize = hostingController.view.fittingSize

            if isPresented {
                if popover.isShown {
                    return
                }
                popover.show(relativeTo: view.bounds, of: view, preferredEdge: preferredEdge.nsRectEdge)
                return
            }

            if popover.isShown {
                popover.performClose(nil)
            }
        }

        func popoverDidClose(_ notification: Notification) {
            DispatchQueue.main.async {
                self.isPresented = false
            }
        }
    }
}

struct KajiPopoverSurface<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .background(
                TranslucentSurface(
                    base: KajiTheme.tertiaryBackground,
                    material: .menu,
                    blendingMode: .behindWindow,
                    tintOpacity: 0.74
                )
            )
            .preferredColorScheme(KajiTheme.colorScheme)
    }
}
