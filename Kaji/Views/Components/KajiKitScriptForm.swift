import SwiftUI

struct KajiKitScriptForm: View {
    @Binding var draft: KajiKitScriptDraft
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(KajiTheme.border.opacity(0.75))
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    KajiScriptTextField(title: "Title", placeholder: "Commit and push", text: $draft.title, width: 360)
                    KajiScriptTextField(title: "Slug", placeholder: "commit-push", text: $draft.slug, width: 220, monospaced: true)
                    Spacer(minLength: 0)
                }
                HStack(alignment: .top, spacing: 12) {
                    KajiScriptSelect(title: "Scope", selection: $draft.scope, width: 124)
                    KajiScriptSelect(title: "Type", selection: $draft.kind, width: 132)
                    KajiScriptSelect(title: "Directory", selection: $draft.directoryMode, width: 150)
                    KajiScriptSelect(title: "Confirm", selection: $draft.confirmation, width: 116)
                    Spacer(minLength: 0)
                }
                Toggle("Auto-close on success", isOn: $draft.autoCloseOnSuccess)
                    .toggleStyle(.checkbox)
                    .kajiFont(size: 12)
                    .foregroundStyle(KajiTheme.fgMuted)
                KajiScriptBodyEditor(text: $draft.command, diagnostics: diagnostics)
                Spacer(minLength: 0)
            }
            .padding(16)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(draft.id == nil ? "Create script" : "Edit script")
                .kajiFont(size: 13, weight: .semibold)
                .foregroundStyle(KajiTheme.fg)
            Spacer()
            Button("Cancel", action: onCancel)
                .buttonStyle(.plain)
                .kajiFont(size: 12, weight: .medium)
                .foregroundStyle(KajiTheme.fgMuted)
            Button("Save", action: onSave)
                .buttonStyle(.plain)
                .kajiFont(size: 12, weight: .semibold)
                .foregroundStyle(canSave ? KajiTheme.fg : KajiTheme.fgDim)
                .disabled(!canSave)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var canSave: Bool {
        diagnostics.allSatisfy { $0.severity != .error }
    }

    private var diagnostics: [KajiCodeDiagnostic] {
        var items: [KajiCodeDiagnostic] = []
        if draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(.init(line: nil, severity: .error, message: "Title is required."))
        }
        if draft.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(.init(line: nil, severity: .error, message: "Script body is required."))
        }
        if draft.kind == .shellScript, !draft.command.hasPrefix("#!") {
            items.append(.init(line: 1, severity: .warning, message: "Full shell scripts should start with a shebang."))
        }
        if KajiKitScriptPlanner.isRisky(scriptPreview) {
            items.append(.init(
                line: nil,
                severity: .warning,
                message: "This script contains risky shell operations and will require confirmation."
            ))
        }
        return items
    }

    private var scriptPreview: KajiKitScript {
        KajiKitScript(title: draft.title, slug: draft.slug, scope: draft.scope, projectID: nil, kind: draft.kind, command: draft.command)
    }
}

private struct KajiScriptTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let width: CGFloat
    var monospaced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .kajiFont(size: 11, weight: .medium)
                .foregroundStyle(KajiTheme.fgDim)
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(KajiTheme.fgDim))
                .textFieldStyle(.plain)
                .kajiFont(size: 12, design: monospaced ? .monospaced : .default)
                .foregroundStyle(KajiTheme.fg)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(width: width, alignment: .leading)
                .background(KajiTheme.surface, in: RoundedRectangle(cornerRadius: KajiShape.tileRadius))
                .overlay(RoundedRectangle(cornerRadius: KajiShape.tileRadius).stroke(KajiTheme.border, lineWidth: 1))
        }
    }
}

private struct KajiScriptSelect<Value>: View where Value: RawRepresentable & CaseIterable & Hashable, Value.RawValue == String {
    let title: String
    @Binding var selection: Value
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .kajiFont(size: 11, weight: .medium)
                .foregroundStyle(KajiTheme.fgDim)
            KajiSelect(
                options: Array(Value.allCases).map { .init(id: $0.rawValue, title: $0.rawValue, value: $0) },
                selection: $selection,
                width: width
            )
        }
    }
}

private struct KajiScriptBodyEditor: View {
    @Binding var text: String
    let diagnostics: [KajiCodeDiagnostic]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Script")
                .kajiFont(size: 11, weight: .medium)
                .foregroundStyle(KajiTheme.fgDim)
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("#!/bin/zsh\nset -euo pipefail\n\n")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(KajiTheme.fgDim)
                        .padding(12)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(KajiTheme.fg)
                    .scrollContentBackground(.hidden)
                    .padding(6)
            }
            .frame(height: 260)
            .background(KajiTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: KajiShape.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: KajiShape.controlRadius).stroke(borderColor, lineWidth: 1))

            ForEach(diagnostics) { diagnostic in
                HStack(spacing: 6) {
                    KajiIcon(systemName: diagnostic.severity == .error ? "xmark.circle" : "exclamationmark.triangle", size: 10)
                    Text(message(for: diagnostic))
                        .kajiFont(size: 11)
                }
                .foregroundStyle(diagnostic.severity == .error ? KajiTheme.diffRemoveFg : KajiTheme.diffHunkFg)
            }
        }
    }

    private var borderColor: Color {
        diagnostics.contains { $0.severity == .error } ? KajiTheme.diffRemoveFg.opacity(0.8) : KajiTheme.borderStrong.opacity(0.9)
    }

    private func message(for diagnostic: KajiCodeDiagnostic) -> String {
        guard let line = diagnostic.line else { return diagnostic.message }
        return "Line \(line): \(diagnostic.message)"
    }
}
