import SwiftUI

struct PaneHeaderView: View {
    let title: String
    let isFocused: Bool
    let isDragging: Bool
    let onClose: () -> Void
    let onDragChanged: (DragGesture.Value) -> Void
    let onDragEnded: (DragGesture.Value) -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 0) {
            dragRegion
            closeButton
        }
        .frame(height: 28)
        .background(backgroundColor)
        .animation(.easeOut(duration: 0.12), value: hovered)
        .animation(.easeOut(duration: 0.12), value: isDragging)
        .animation(.easeOut(duration: 0.12), value: isFocused)
        .onHover { hovered = $0 }
    }

    private var dragRegion: some View {
        HStack(spacing: 10) {
            HStack(spacing: 3) {
                Capsule()
                    .fill(handleColor)
                    .frame(width: 14, height: 2)
                Capsule()
                    .fill(handleColor)
                    .frame(width: 14, height: 2)
            }
            .frame(width: 16)

            Text(title)
                .droidFont(size: 11, weight: .medium)
                .foregroundStyle(titleColor)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 3, coordinateSpace: .named(DragCoordinateSpace.mainWindow))
                .onChanged(onDragChanged)
                .onEnded(onDragEnded)
        )
    }

    private var closeButton: some View {
        Button(action: onClose) {
            ZStack {
                RoundedRectangle(cornerRadius: DroidShape.badgeRadius)
                    .fill(closeButtonBackground)
                RoundedRectangle(cornerRadius: DroidShape.badgeRadius)
                    .strokeBorder(closeButtonBorder, lineWidth: 1)
                DroidIcon(systemName: "xmark", size: 8)
                    .foregroundStyle(closeButtonForeground)
            }
            .frame(width: 18, height: 18)
            .contentShape(RoundedRectangle(cornerRadius: DroidShape.badgeRadius))
        }
        .buttonStyle(.plain)
        .padding(.trailing, 8)
        .opacity(hovered || isFocused ? 1 : 0.82)
    }

    private var backgroundColor: Color {
        DroidTheme.bg
    }

    private var closeButtonBackground: Color {
        if hovered || isFocused {
            return DroidTheme.border.opacity(0.16)
        }
        return .clear
    }

    private var closeButtonForeground: Color {
        if hovered || isFocused {
            return DroidTheme.fgMuted
        }
        return DroidTheme.fgDim
    }

    private var closeButtonBorder: Color {
        if hovered || isFocused {
            return DroidTheme.border.opacity(0.85)
        }
        return .clear
    }

    private var titleColor: Color {
        if isFocused || hovered || isDragging {
            return DroidTheme.fg
        }
        return DroidTheme.fgMuted
    }

    private var handleColor: Color {
        if isFocused || hovered || isDragging {
            return DroidTheme.fgDim
        }
        return DroidTheme.fgDim.opacity(0.78)
    }
}
