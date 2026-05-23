import AppKit
import SwiftUI

struct FilePreviewPane: View {
    @Bindable var state: FilePreviewTabState
    let onFocus: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(KajiTheme.border).frame(height: 1)
            content
            statusBar
        }
        .background(KajiTheme.bg)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { onFocus() })
    }

    @ViewBuilder
    private var content: some View {
        switch state.kind {
        case .image:
            ImageFilePreviewView(url: state.url)
        case .pdf:
            PDFFilePreviewView(url: state.url)
        case .audioVideo:
            MediaFilePreviewView(url: state.url)
        case .web:
            WebFilePreviewView(url: state.url)
        case .document,
             .archive,
             .model3D,
             .quickLook:
            QuickLookFilePreviewView(url: state.url)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            KajiIcon(systemName: state.kind.systemImage, size: 13)
                .foregroundStyle(KajiTheme.fgMuted)
            Text(state.fileName)
                .kajiFont(size: 12, weight: .medium)
                .foregroundStyle(KajiTheme.fg)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([state.url])
            } label: {
                KajiIcon(systemName: "folder", size: 12)
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder")
            Button {
                NSWorkspace.shared.open(state.url)
            } label: {
                KajiIcon(systemName: "arrow.up.forward.app", size: 12)
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(.plain)
            .help("Open Externally")
        }
        .foregroundStyle(KajiTheme.fgMuted)
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(KajiTheme.secondaryBackground)
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Text(state.kind.displayName)
                .kajiFont(size: 11, design: .monospaced)
                .foregroundStyle(KajiTheme.fgMuted)
            Spacer()
            Text(state.filePath)
                .kajiFont(size: 11, design: .monospaced)
                .foregroundStyle(KajiTheme.fgDim)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(KajiTheme.secondaryBackground)
        .overlay(alignment: .top) {
            Rectangle().fill(KajiTheme.border).frame(height: 1)
        }
    }
}
