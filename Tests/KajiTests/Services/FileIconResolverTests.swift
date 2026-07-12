import Testing

@testable import Kaji

@Suite("File icon resolver")
struct FileIconResolverTests {
    private let resolver = FileIconResolver.materialIconTheme

    @Test("exact file names use specific icons before extensions")
    func exactFileNamesUseSpecificIconsBeforeExtensions() {
        #expect(resolver.fileIcon(name: "package.json")?.id == "nodejs")
        #expect(resolver.fileIcon(name: "Dockerfile")?.id == "docker")
        #expect(resolver.fileIcon(name: ".gitignore")?.id == "git")
        #expect(resolver.fileIcon(name: "README.md")?.id == "readme")
        #expect(resolver.fileIcon(name: ".env.local")?.id == "tune")
    }

    @Test("compound extensions use the longest matching suffix")
    func compoundExtensionsUseLongestMatchingSuffix() {
        #expect(resolver.fileIcon(name: "index.d.ts")?.id == "typescript-def")
        #expect(resolver.fileIcon(name: "button.test.tsx")?.id == "test-jsx")
        #expect(resolver.fileIcon(name: "button.cy.tsx")?.id == "test-jsx")
        #expect(resolver.fileIcon(name: "settings.schema.json")?.id == "json_schema")
        #expect(resolver.fileIcon(name: "bundle.js.map")?.id == "javascript-map")
    }

    @Test("normal extensions resolve language and media icons")
    func normalExtensionsResolveLanguageAndMediaIcons() {
        #expect(resolver.fileIcon(name: "main.swift")?.id == "swift")
        #expect(resolver.fileIcon(name: "app.ts")?.id == "typescript")
        #expect(resolver.fileIcon(name: "view.tsx")?.id == "react_ts")
        #expect(resolver.fileIcon(name: "notes.md")?.id == "markdown")
        #expect(resolver.fileIcon(name: "data.json")?.id == "json")
        #expect(resolver.fileIcon(name: "photo.png")?.id == "image")
        #expect(resolver.fileIcon(name: "manual.pdf")?.id == "pdf")
    }

    @Test("relative file paths support path-specific generated names")
    func relativeFilePathsSupportPathSpecificGeneratedNames() {
        #expect(resolver.fileIcon(name: "eslintrc", relativePath: ".config/eslintrc")?.id == "eslint")
        #expect(resolver.fileIcon(name: "webpack.config.ts", relativePath: "packages/web/webpack.config.ts")?.id == "webpack")
    }

    @Test("folders resolve specific closed and expanded icons")
    func foldersResolveSpecificClosedAndExpandedIcons() {
        #expect(resolver.folderIcon(name: "src", isExpanded: false)?.id == "folder-src")
        #expect(resolver.folderIcon(name: "src", isExpanded: true)?.id == "folder-src-open")
        #expect(resolver.folderIcon(name: "Tests", isExpanded: false)?.id == "folder-test")
        #expect(resolver.folderIcon(name: "Resources", isExpanded: true)?.id == "folder-resource-open")
        #expect(resolver.folderIcon(name: "node_modules", isExpanded: false)?.id == "folder-node")
        #expect(resolver.folderIcon(name: "ios", isExpanded: true)?.id == "folder-ios-open")
        #expect(resolver.folderIcon(name: "macos", isExpanded: true)?.id == "folder-macos-open")
    }

    @Test("folders resolve path-specific names")
    func foldersResolvePathSpecificNames() {
        #expect(resolver.folderIcon(name: "workflows", relativePath: ".github/workflows", isExpanded: false)?.id == "folder-gh-workflows")
        #expect(resolver.folderIcon(name: "workflows", relativePath: ".github/workflows", isExpanded: true)?.id == "folder-gh-workflows-open")
        #expect(resolver.folderIcon(name: "ISSUE_TEMPLATE", relativePath: ".github/ISSUE_TEMPLATE", isExpanded: false)?.id == "folder-template")
    }

    @Test("unknown files and folders fall back to defaults")
    func unknownFilesAndFoldersFallBackToDefaults() {
        #expect(resolver.fileIcon(name: "unknown-file-type.zzz")?.id == "file")
        #expect(resolver.folderIcon(name: "unknown-folder-name", isExpanded: false)?.id == "folder")
        #expect(resolver.folderIcon(name: "unknown-folder-name", isExpanded: true)?.id == "folder-open")
    }

    @MainActor
    @Test("resolved icons point at bundled SVG assets")
    func resolvedIconsPointAtBundledSVGAssets() {
        let icons = [
            resolver.fileIcon(name: "main.swift"),
            resolver.fileIcon(name: "package.json"),
            resolver.folderIcon(name: "src", isExpanded: false),
            resolver.folderIcon(name: "src", isExpanded: true),
            resolver.fileIcon(name: "unknown-file-type.zzz"),
        ].compactMap { $0 }

        #expect(!icons.isEmpty)
        for icon in icons {
            #expect(FileIconImageCache.shared.hasImage(for: icon))
        }
    }
}
