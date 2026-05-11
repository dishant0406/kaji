import SwiftUI

struct DropZoneHighlight: View {
    let zone: DropZone
    let showsTabStripTarget: Bool

    var body: some View {
        GeometryReader { geo in
            let outerRect = containerRect(in: geo.size)
            let targetRect = highlightRect(in: geo.size)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: outerCornerRadius)
                    .fill(KajiTheme.selection.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: outerCornerRadius)
                            .strokeBorder(KajiTheme.border.opacity(0.78), lineWidth: 1)
                    )
                    .frame(width: outerRect.width, height: outerRect.height)
                    .offset(x: outerRect.minX, y: outerRect.minY)

                RoundedRectangle(cornerRadius: targetCornerRadius)
                    .fill(KajiTheme.selection.opacity(0.82))
                    .overlay(
                        RoundedRectangle(cornerRadius: targetCornerRadius)
                            .strokeBorder(KajiTheme.accent.opacity(0.58), lineWidth: 1)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: targetCornerRadius)
                            .strokeBorder(KajiTheme.borderStrong.opacity(0.62), lineWidth: 1)
                    )
                    .frame(width: targetRect.width, height: targetRect.height)
                    .offset(x: targetRect.minX, y: targetRect.minY)
            }
            .animation(KajiMotion.fast, value: zone)
            .animation(KajiMotion.fast, value: showsTabStripTarget)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var outerCornerRadius: CGFloat {
        KajiShape.modalRadius
    }

    private var targetCornerRadius: CGFloat {
        KajiShape.panelRadius
    }

    private func containerRect(in size: CGSize) -> CGRect {
        CGRect(origin: .zero, size: size).insetBy(dx: 8, dy: 8)
    }

    private func highlightRect(in size: CGSize) -> CGRect {
        let inset: CGFloat = 12
        switch zone {
        case .left:
            return CGRect(x: inset, y: inset, width: size.width * 0.38, height: size.height - inset * 2)
        case .right:
            let width = size.width * 0.38
            return CGRect(x: size.width - inset - width, y: inset, width: width, height: size.height - inset * 2)
        case .top:
            return CGRect(x: inset, y: inset, width: size.width - inset * 2, height: size.height * 0.38)
        case .bottom:
            let height = size.height * 0.38
            return CGRect(x: inset, y: size.height - inset - height, width: size.width - inset * 2, height: height)
        case .center:
            if showsTabStripTarget {
                return CGRect(x: inset, y: inset, width: size.width - inset * 2, height: 28)
            }
            return CGRect(x: inset, y: inset, width: size.width - inset * 2, height: size.height - inset * 2)
        }
    }
}

typealias AreaFramePreferenceKey = UUIDFramePreferenceKey<AreaFrameTag>
