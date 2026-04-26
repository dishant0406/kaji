import SwiftUI

struct CreateBranchModal: View {
    let currentBranch: String?
    let onCreate: (String) -> Void
    let onCancel: () -> Void
    @State private var name = ""

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var createEnabled: Bool {
        !trimmedName.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(DroidTheme.border).frame(height: 1)
            CreateWorktreeFormSection("Branch", detail: "Create a new branch and switch the current worktree to it.", showsDivider: false) {
                CreateWorktreeLabeledField("Branch name") {
                    DroidInput(placeholder: "feature-x", text: $name, monospaced: true)
                        .onSubmit {
                            guard createEnabled else { return }
                            onCreate(trimmedName)
                        }
                }
                if let currentBranch {
                    Text("Created from \(currentBranch)")
                        .font(.system(size: 11))
                        .foregroundStyle(DroidTheme.fgDim)
                }
            }
            Rectangle().fill(DroidTheme.border).frame(height: 1)
            footer
        }
        .frame(width: 460)
        .background(
            TranslucentSurface(
                base: DroidTheme.tertiaryBackground,
                material: .hudWindow,
                tintOpacity: 0.66,
                gradientOpacity: 0.08
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: DroidShape.modalRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DroidShape.modalRadius)
                .stroke(DroidTheme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 8, y: 2)
    }

    private var header: some View {
        HStack {
            Text("New Branch")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DroidTheme.fg)
            Spacer()
            IconButton(symbol: "xmark", accessibilityLabel: "Close Branch Modal", action: onCancel)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(DroidTheme.chrome.opacity(0.42))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Spacer()
            Button("Cancel", action: onCancel)
                .buttonStyle(DroidButtonStyle(.secondary))
            Button("Create") {
                onCreate(trimmedName)
            }
            .buttonStyle(DroidButtonStyle(.primary))
            .opacity(createEnabled ? 1 : 0.42)
            .disabled(!createEnabled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(DroidTheme.chrome.opacity(0.42))
    }
}
