import SwiftUI

struct DroidKitScriptForm: View {
    @Binding var draft: DroidKitScriptDraft
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(DroidTheme.border.opacity(0.75))
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    DroidScriptTextField(title: "Title", placeholder: "Commit and push", text: $draft.title, width: 360)
                    DroidScriptTextField(title: "Slug", placeholder: "commit-push", text: $draft.slug, width: 220, monospaced: true)
                    Spacer(minLength: 0)
                }
                HStack(alignment: .top, spacing: 12) {
                    DroidScriptSelect(title: "Scope", selection: $draft.scope, width: 124)
                    DroidScriptSelect(title: "Type", selection: $draft.kind, width: 132)
                    DroidScriptSelect(title: "Directory", selection: $draft.directoryMode, width: 150)
                    DroidScriptSelect(title: "Confirm", selection: $draft.confirmation, width: 116)
                    Spacer(minLength: 0)
                }
                Toggle("Auto-close on success", isOn: $draft.autoCloseOnSuccess)
                    .toggleStyle(.checkbox)
                    .droidFont(size: 12)
                    .foregroundStyle(DroidTheme.fgMuted)
                DroidScriptBodyEditor(text: $draft.command, diagnostics: diagnostics)
                Spacer(minLength: 0)
            }
            .padding(16)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(draft.id == nil ? "Create script" : "Edit script")
                .droidFont(size: 13, weight: .semibold)
                .foregroundStyle(DroidTheme.fg)
            Spacer()
            Button("Cancel", action: onCancel)
                .buttonStyle(.plain)
                .droidFont(size: 12, weight: .medium)
                .foregroundStyle(DroidTheme.fgMuted)
            Button("Save", action: onSave)
                .buttonStyle(.plain)
                .droidFont(size: 12, weight: .semibold)
                .foregroundStyle(canSave ? DroidTheme.fg : DroidTheme.fgDim)
                .disabled(!canSave)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var canSave: Bool {
        diagnostics.allSatisfy { $0.severity != .error }
    }

    private var diagnostics: [DroidCodeDiagnostic] {
        var items: [DroidCodeDiagnostic] = []
        if draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(.init(line: nil, severity: .error, message: "Title is required."))
        }
        if draft.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(.init(line: nil, severity: .error, message: "Script body is required."))
        }
        if draft.kind == .shellScript, !draft.command.hasPrefix("#!") {
            items.append(.init(line: 1, severity: .warning, message: "Full shell scripts should start with a shebang."))
        }
        if DroidKitScriptPlanner.isRisky(scriptPreview) {
            items.append(.init(
                line: nil,
                severity: .warning,
                message: "This script contains risky shell operations and will require confirmation."
            ))
        }
        return items
    }

    private var scriptPreview: DroidKitScript {
        DroidKitScript(title: draft.title, slug: draft.slug, scope: draft.scope, projectID: nil, kind: draft.kind, command: draft.command)
    }
}

private struct DroidScriptTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let width: CGFloat
    var monospaced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .droidFont(size: 11, weight: .medium)
                .foregroundStyle(DroidTheme.fgDim)
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(DroidTheme.fgDim))
                .textFieldStyle(.plain)
                .droidFont(size: 12, design: monospaced ? .monospaced : .default)
                .foregroundStyle(DroidTheme.fg)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(width: width, alignment: .leading)
                .background(DroidTheme.surface, in: RoundedRectangle(cornerRadius: DroidShape.tileRadius))
                .overlay(RoundedRectangle(cornerRadius: DroidShape.tileRadius).stroke(DroidTheme.border, lineWidth: 1))
        }
    }
}

private struct DroidScriptSelect<Value>: View where Value: RawRepresentable & CaseIterable & Hashable, Value.RawValue == String {
    let title: String
    @Binding var selection: Value
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .droidFont(size: 11, weight: .medium)
                .foregroundStyle(DroidTheme.fgDim)
            DroidSelect(
                options: Array(Value.allCases).map { .init(id: $0.rawValue, title: $0.rawValue, value: $0) },
                selection: $selection,
                width: width
            )
        }
    }
}

private struct DroidScriptBodyEditor: View {
    @Binding var text: String
    let diagnostics: [DroidCodeDiagnostic]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Script")
                .droidFont(size: 11, weight: .medium)
                .foregroundStyle(DroidTheme.fgDim)
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("#!/bin/zsh\nset -euo pipefail\n\n")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(DroidTheme.fgDim)
                        .padding(12)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(DroidTheme.fg)
                    .scrollContentBackground(.hidden)
                    .padding(6)
            }
            .frame(height: 260)
            .background(DroidTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: DroidShape.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: DroidShape.controlRadius).stroke(borderColor, lineWidth: 1))

            ForEach(diagnostics) { diagnostic in
                HStack(spacing: 6) {
                    DroidIcon(systemName: diagnostic.severity == .error ? "xmark.circle" : "exclamationmark.triangle", size: 10)
                    Text(message(for: diagnostic))
                        .droidFont(size: 11)
                }
                .foregroundStyle(diagnostic.severity == .error ? DroidTheme.diffRemoveFg : DroidTheme.diffHunkFg)
            }
        }
    }

    private var borderColor: Color {
        diagnostics.contains { $0.severity == .error } ? DroidTheme.diffRemoveFg.opacity(0.8) : DroidTheme.borderStrong.opacity(0.9)
    }

    private func message(for diagnostic: DroidCodeDiagnostic) -> String {
        guard let line = diagnostic.line else { return diagnostic.message }
        return "Line \(line): \(diagnostic.message)"
    }
}
