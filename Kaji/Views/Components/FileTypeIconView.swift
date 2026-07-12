import SwiftUI

struct FileTypeIconView: View {
    enum Kind: Equatable {
        case file(name: String, relativePath: String?)
        case folder(name: String, relativePath: String?, isExpanded: Bool, isRoot: Bool)
    }

    let kind: Kind
    var size: CGFloat = 14
    var fallbackColor: Color = KajiTheme.fgMuted

    init(entry: FileTreeEntry, isExpanded: Bool, isRoot: Bool = false, size: CGFloat = 14) {
        kind = entry.isDirectory
            ? .folder(name: entry.name, relativePath: entry.relativePath, isExpanded: isExpanded, isRoot: isRoot)
            : .file(name: entry.name, relativePath: entry.relativePath)
        self.size = size
    }

    init(kind: Kind, size: CGFloat = 14) {
        self.kind = kind
        self.size = size
    }

    var body: some View {
        if let icon = resolvedIcon, let image = FileIconImageCache.shared.image(for: icon) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            KajiIcon(systemName: fallbackSymbol, size: size * 0.82)
                .foregroundStyle(fallbackColor)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }

    private var resolvedIcon: FileIcon? {
        switch kind {
        case let .file(name, relativePath):
            FileIconResolver.materialIconTheme.fileIcon(name: name, relativePath: relativePath)
        case let .folder(name, relativePath, isExpanded, isRoot):
            FileIconResolver.materialIconTheme.folderIcon(
                name: name,
                relativePath: relativePath,
                isExpanded: isExpanded,
                isRoot: isRoot
            )
        }
    }

    private var fallbackSymbol: String {
        switch kind {
        case .file:
            "doc"
        case let .folder(_, _, isExpanded, _):
            isExpanded ? "folder.fill" : "folder"
        }
    }
}
