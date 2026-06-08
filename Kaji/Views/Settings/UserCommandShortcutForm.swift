import SwiftUI

struct UserCommandShortcutForm: View {
    @Binding var draft: UserCommandShortcutDraft
    let validation: UserCommandShortcutValidation
    let onNameChange: (String) -> Void
    let onSlugChange: (String) -> Void
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                labeledInput("Name", placeholder: "Run tests", text: nameBinding, width: 240)
                labeledInput("Slug", placeholder: "runtests", text: slugBinding, width: 180, monospaced: true)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Trigger")
                        .kajiFont(size: 11, weight: .medium)
                        .foregroundStyle(KajiTheme.fgDim)
                    ShortcutBadge(label: "::\(draft.slug.isEmpty ? "slug" : draft.slug)", compact: true)
                        .frame(height: 34)
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Terminal Command")
                    .kajiFont(size: 11, weight: .medium)
                    .foregroundStyle(KajiTheme.fgDim)
                TextEditor(text: $draft.command)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(KajiTheme.fg)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(height: 86)
                    .background(KajiTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: KajiShape.controlRadius))
                    .overlay(RoundedRectangle(cornerRadius: KajiShape.controlRadius).stroke(borderColor, lineWidth: 1))
            }

            variableHelp

            ForEach(validation.errors, id: \.self) { error in
                HStack(spacing: 6) {
                    KajiIcon(systemName: "xmark.circle", size: 10)
                    Text(error.message)
                        .kajiFont(size: 11)
                }
                .foregroundStyle(KajiTheme.diffRemoveFg)
            }

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(KajiButtonStyle(.ghost, size: .small))
                Button(draft.id == nil ? "Create" : "Save", action: onSave)
                    .buttonStyle(KajiButtonStyle(.primary, size: .small))
                    .disabled(!validation.canSave)
            }
        }
        .padding(SettingsMetrics.horizontalPadding)
        .background(KajiTheme.surface.opacity(0.55), in: RoundedRectangle(cornerRadius: KajiShape.panelRadius))
        .padding(.horizontal, SettingsMetrics.horizontalPadding)
    }

    private var nameBinding: Binding<String> {
        Binding(get: { draft.name }, set: { onNameChange($0) })
    }

    private var slugBinding: Binding<String> {
        Binding(get: { draft.slug }, set: { onSlugChange($0) })
    }

    private var borderColor: Color {
        validation.errors.contains(.commandRequired) ? KajiTheme.diffRemoveFg.opacity(0.8) : KajiTheme.borderStrong.opacity(0.9)
    }

    private var variableHelp: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Variables")
                .kajiFont(size: 11, weight: .medium)
                .foregroundStyle(KajiTheme.fgDim)
            Text(variableHelpText)
                .kajiFont(size: 10)
                .foregroundStyle(KajiTheme.fgDim)
                .fixedSize(horizontal: false, vertical: true)
            if !variableBadges.isEmpty {
                HStack(spacing: 6) {
                    ForEach(variableBadges, id: \.self) { badge in
                        ShortcutBadge(label: badge, compact: true)
                    }
                }
            }
        }
    }

    private var variableBadges: [String] {
        guard let template = UserCommandShortcutTemplateParser.parse(draft.command).template else { return [] }
        let inputs = template.inputVariables.map { "{\($0.displayName)}" }
        let computed = template.computedVariables.map { "{~\($0.command)~}" }
        return inputs + computed
    }

    private var variableHelpText: String {
        "Use {name} then run ::slug value. Use {1} {2} for positional values. " +
            "Use {~command~} for computed values. Values are shell-escaped automatically."
    }

    private func labeledInput(
        _ title: String,
        placeholder: String,
        text: Binding<String>,
        width: CGFloat,
        monospaced: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .kajiFont(size: 11, weight: .medium)
                .foregroundStyle(KajiTheme.fgDim)
            KajiInput(placeholder: placeholder, text: text, width: width, monospaced: monospaced)
        }
    }
}
