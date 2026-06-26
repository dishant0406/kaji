import SwiftUI

struct CreatePRModalHeader: View {
    let onCancel: () -> Void

    var body: some View {
        HStack {
            Text("Create Pull Request")
                .kajiFont(size: 13, weight: .semibold)
                .foregroundStyle(KajiTheme.fg)
            Spacer()
            IconButton(symbol: "xmark", accessibilityLabel: "Close Pull Request Modal", action: onCancel)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(KajiTheme.chrome.opacity(0.42))
    }
}

struct CreatePRModalFooter: View {
    let inProgress: Bool
    let createEnabled: Bool
    let onCancel: () -> Void
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Spacer()
            Button("Cancel", action: onCancel)
                .buttonStyle(KajiButtonStyle(.secondary))
                .disabled(inProgress)
            Button(action: onSubmit) {
                HStack(spacing: 6) {
                    if inProgress {
                        KajiSpinner(size: 11, lineWidth: 1.4, color: KajiTheme.bg)
                    }
                    Text(inProgress ? "Creating..." : "Create PR")
                }
            }
            .buttonStyle(KajiButtonStyle(.primary))
            .opacity(createEnabled ? 1 : 0.42)
            .disabled(!createEnabled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(KajiTheme.chrome.opacity(0.42))
    }
}
