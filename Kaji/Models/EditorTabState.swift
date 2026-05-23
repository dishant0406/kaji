import AppKit
import CoreGraphics
import Foundation

enum EditorSearchNavigationDirection {
    case next
    case previous
}

enum EditorMarkdownViewMode: String, CaseIterable {
    case code
    case preview
    case split

    var title: String {
        switch self {
        case .code: "Code"
        case .preview: "Preview"
        case .split: "Split"
        }
    }

    var symbol: String {
        switch self {
        case .code: "curlybraces"
        case .preview: "doc.richtext"
        case .split: "rectangle.split.2x1"
        }
    }
}

enum EditorMarkdownScrollDriver {
    case editor
    case preview
}

@MainActor
@Observable
final class EditorTabState: Identifiable {
    private static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd"]

    let id = UUID()
    let projectPath: String
    private(set) var filePath: String
    var backingStoreVersion = 0
    var previewRefreshVersion = 0
    var lspChangeVersion = 0
    var isLoading = false
    var isIncrementalLoading = false
    var isModified = false
    var isSaving = false
    var errorMessage: String?
    var isReadOnly = false
    var cursorPosition: EditorCursorPosition = .initial
    var cursorLine: Int { cursorPosition.line }
    var cursorColumn: Int { cursorPosition.column }
    var searchVisible = false
    var searchFocusVersion = 0
    var replaceFocusVersion = 0
    var editorFocusVersion = 0
    var searchNeedle = ""
    var searchMatchCount = 0
    var searchCurrentIndex = 0
    var searchNavigationVersion = 0
    var searchNavigationDirection: EditorSearchNavigationDirection = .next
    var searchCaseSensitive = false
    var searchUseRegex = false
    var searchInvalidRegex = false
    var replaceVisible = false
    var replaceText = ""
    var replaceVersion = 0
    var replaceAllVersion = 0
    var currentSelection = ""
    var inlineEditVisible = false
    var inlineEditInstruction = ""
    var inlineEditOriginal = ""
    var inlineEditProposal = ""
    var inlineEditRequestVersion = 0
    var inlineEditApplyVersion = 0
    var awaitingLargeFileConfirmation = false
    var largeFileSize: Int64 = 0
    var backingStore: TextBackingStore?
    var markdownViewMode: EditorMarkdownViewMode = .code
    var markdownScrollPosition: CGFloat = 0
    var markdownScrollSyncEnabled = true
    var markdownScrollDriver: EditorMarkdownScrollDriver = .editor

    var markdownPreviewScrollRequestVersion: Int = 0
    var markdownPreviewScrollRequest: CGFloat?
    @ObservationIgnored var markdownEditorScrollRequestVersion: Int = 0
    @ObservationIgnored var markdownEditorScrollRequestY: CGFloat?

    @ObservationIgnored var markdownEditorScrollY: CGFloat = 0
    @ObservationIgnored var markdownEditorViewportHeight: CGFloat = 0
    @ObservationIgnored var markdownEditorMaxScrollY: CGFloat = 0
    @ObservationIgnored var markdownEditorLineHeight: CGFloat = 0
    @ObservationIgnored var markdownPreviewGeometries: [MarkdownPreviewAnchorGeometry] = []
    @ObservationIgnored var markdownPreviewMaxScrollTop: CGFloat = 0
    @ObservationIgnored var markdownPreviewViewportHeight: CGFloat = 0

    @ObservationIgnored let markdownSyncCoordinator = MarkdownSyncCoordinator()
    @ObservationIgnored private var markdownSyncAnchorsCache: [MarkdownSyncAnchor] = []
    @ObservationIgnored private var markdownSyncAnchorsCacheVersion: Int = -1
    @ObservationIgnored private(set) var syntaxHighlighter: (any SyntaxHighlighting)?
    @ObservationIgnored private let filePathForLogging: String
    @ObservationIgnored private var foldRegionsCache: [EditorFoldRegion] = []
    @ObservationIgnored private var foldRegionsCacheVersion: Int = -1
    @ObservationIgnored private var symbolsCache: [EditorSymbol] = []
    @ObservationIgnored private var symbolsCacheVersion: Int = -1
    @ObservationIgnored private var languageServerOpenFilePath: String?
    var collapsedFoldRegionIDs: Set<String> = []
    var symbolNavigationRequest: EditorSymbol?
    var symbolNavigationVersion = 0
    var lineNavigationRequest: EditorLineNavigationRequest?
    var lineNavigationVersion = 0

    static let largeFileWarningThreshold: Int64 = 5 * 1024 * 1024
    static let largeFileRefuseThreshold: Int64 = 50 * 1024 * 1024
    static let initialOpenChunkSize = 512 * 1024
    static let streamChunkSize = 4 * 1024 * 1024
    static let streamYieldChunkSize = 2 * 1024 * 1024

    var fileName: String {
        URL(fileURLWithPath: filePath).lastPathComponent
    }

    var fileExtension: String {
        let url = URL(fileURLWithPath: filePath)
        let ext = url.pathExtension.lowercased()
        guard ext.isEmpty else { return ext }
        return url.lastPathComponent
    }

    var displayTitle: String {
        let name = fileName
        return isModified ? "\(name) \u{2022}" : name
    }

    var languageDisplayName: String {
        LanguageRegistry.shared.definition(forFile: filePath)?.name ?? "Plain Text"
    }

    func updateCursorPosition(line: Int, column: Int, selectionLength: Int) {
        cursorPosition = EditorCursorPosition(
            line: max(1, line),
            column: max(1, column),
            selectionLength: max(0, selectionLength)
        )
    }

    var isMarkdownFile: Bool {
        Self.markdownExtensions.contains(fileExtension)
    }

    @ObservationIgnored private var loadTask: Task<Void, Never>?

    private enum FileLoadEvent {
        case initial(String, hasMore: Bool)
        case appended(String)
        case finished
    }

    private enum SaveError: LocalizedError {
        case fileIsReadOnly(String)

        var errorDescription: String? {
            switch self {
            case let .fileIsReadOnly(path):
                "File is read-only: \(URL(fileURLWithPath: path).lastPathComponent)"
            }
        }
    }

    init(projectPath: String, filePath: String) {
        self.projectPath = projectPath
        self.filePath = filePath
        filePathForLogging = filePath
        DebugFileLog.log("EditorState", "init projectPath=\(projectPath) filePath=\(filePath)")
        if isMarkdownFile {
            markdownViewMode = .preview
        }
        syntaxHighlighter = Self.makeSyntaxHighlighter(for: filePath)
        DebugFileLog.log("EditorState", "syntaxHighlighter=\(syntaxHighlighter == nil ? "nil" : "created") filePath=\(filePath)")
        loadFile()
    }

    func updateFilePath(_ newPath: String) {
        guard filePath != newPath else { return }
        closeLanguageServerDocument()
        filePath = newPath
        syntaxHighlighter = Self.makeSyntaxHighlighter(for: newPath)
        refreshReadOnlyStatus()
    }

    func markdownSyncAnchors() -> [MarkdownSyncAnchor] {
        guard isMarkdownFile else { return [] }
        guard let backingStore else { return [] }
        guard markdownSyncAnchorsCacheVersion != backingStoreVersion else {
            return markdownSyncAnchorsCache
        }
        markdownSyncAnchorsCache = MarkdownAnchorParser.parseAnchors(in: backingStore.fullText())
        markdownSyncAnchorsCacheVersion = backingStoreVersion
        return markdownSyncAnchorsCache
    }

    func foldRegions() -> [EditorFoldRegion] {
        guard let backingStore else { return [] }
        guard foldRegionsCacheVersion != backingStoreVersion else { return foldRegionsCache }
        foldRegionsCache = LanguageFoldingRegionParser.regions(
            in: backingStore,
            configuration: LanguageRegistry.shared.configuration(forFile: filePath)
        )
        foldRegionsCacheVersion = backingStoreVersion
        return foldRegionsCache
    }

    func foldRegionStarting(at line: Int) -> EditorFoldRegion? {
        foldRegions().first { $0.startLine == line }
    }

    func isFoldRegionCollapsed(_ region: EditorFoldRegion) -> Bool {
        collapsedFoldRegionIDs.contains(region.id)
    }

    func toggleFoldRegion(_ region: EditorFoldRegion) {
        if collapsedFoldRegionIDs.contains(region.id) {
            collapsedFoldRegionIDs.remove(region.id)
        } else {
            collapsedFoldRegionIDs.insert(region.id)
        }
    }

    func unfoldRegions(containing line: Int) -> Bool {
        let matching = foldRegions().filter { region in
            collapsedFoldRegionIDs.contains(region.id) && line > region.startLine && line <= region.endLine
        }
        guard !matching.isEmpty else { return false }
        for region in matching {
            collapsedFoldRegionIDs.remove(region.id)
        }
        return true
    }

    func symbols() -> [EditorSymbol] {
        guard let backingStore else { return [] }
        guard symbolsCacheVersion != backingStoreVersion else { return symbolsCache }
        let definition = LanguageRegistry.shared.definition(forFile: filePath)
        if let definition,
           let treeSitterSymbols = TreeSitterSymbolParser.symbols(in: backingStore, definition: definition)
        {
            symbolsCache = treeSitterSymbols
            symbolsCacheVersion = backingStoreVersion
            return symbolsCache
        }
        symbolsCache = EditorSymbolParser.symbols(
            in: backingStore,
            languageID: definition?.id
        )
        symbolsCacheVersion = backingStoreVersion
        return symbolsCache
    }

    func navigate(to symbol: EditorSymbol) {
        symbolNavigationRequest = symbol
        symbolNavigationVersion += 1
        editorFocusVersion += 1
    }

    func navigate(to request: EditorLineNavigationRequest) {
        lineNavigationRequest = request
        lineNavigationVersion += 1
        editorFocusVersion += 1
    }

    func showFind(prefillSelection: Bool = true) {
        if prefillSelection, !currentSelection.isEmpty {
            searchNeedle = currentSelection
        }
        searchVisible = true
        searchFocusVersion += 1
    }

    func showReplace() {
        showFind()
        replaceVisible = true
        replaceFocusVersion += 1
    }

    func requestInlineEdit() {
        inlineEditVisible = true
        inlineEditRequestVersion += 1
    }

    func proposeInlineEdit(instruction: String, original: String) {
        inlineEditInstruction = instruction
        inlineEditOriginal = original
        inlineEditProposal = original
    }

    func applyInlineEdit(proposal: String) {
        inlineEditProposal = proposal
        inlineEditApplyVersion += 1
        inlineEditVisible = false
    }

    func applyMarkdownSyncOutput(_ output: MarkdownSyncCoordinator.Output) {
        if let scrollTop = output.requestPreviewScrollTop {
            markdownScrollDriver = .editor
            markdownPreviewScrollRequest = scrollTop
            markdownPreviewScrollRequestVersion += 1
        }
        if let scrollY = output.requestEditorScrollY {
            if markdownScrollDriver != .preview {
                markdownScrollDriver = .preview
            }
            markdownEditorScrollRequestY = scrollY
            markdownEditorScrollRequestVersion += 1
            MarkdownEditorScrollBus.publish(tabID: id, scrollY: scrollY)
        }
    }

    func currentMarkdownSyncMap() -> MarkdownSyncMap {
        MarkdownSyncMapBuilder.build(
            MarkdownSyncMapInputs(
                anchors: markdownSyncAnchors(),
                previewGeometries: markdownPreviewGeometries,
                editorLineHeight: markdownEditorLineHeight,
                editorMaxScrollY: markdownEditorMaxScrollY,
                editorViewportHeight: markdownEditorViewportHeight,
                previewMaxScrollY: markdownPreviewMaxScrollTop,
                previewViewportHeight: markdownPreviewViewportHeight
            )
        )
    }

    private static func makeSyntaxHighlighter(for filePath: String) -> (any SyntaxHighlighting)? {
        SyntaxEngineRegistry.highlighter(forFile: filePath)
    }

    private func syncLanguageServerDocument(filePath: String, text: String) {
        if languageServerOpenFilePath == filePath {
            LanguageServerManager.shared.didChange(filePath: filePath, projectPath: projectPath, text: text)
            return
        }
        closeLanguageServerDocument()
        LanguageServerManager.shared.didOpen(filePath: filePath, projectPath: projectPath, text: text)
        languageServerOpenFilePath = filePath
    }

    private func closeLanguageServerDocument() {
        guard let filePath = languageServerOpenFilePath else { return }
        LanguageServerManager.shared.didClose(filePath: filePath, projectPath: projectPath)
        DiagnosticsStore.shared.clearDiagnostics(for: filePath)
        languageServerOpenFilePath = nil
    }

    deinit {
        DebugFileLog.log("EditorState", "deinit filePath=\(filePathForLogging)")
        loadTask?.cancel()
        MainActor.assumeIsolated {
            closeLanguageServerDocument()
        }
    }

    func loadFile() {
        DebugFileLog.log("EditorLoad", "loadFile requested filePath=\(filePath) isLoading=\(isLoading)")
        guard !isLoading else { return }
        errorMessage = nil
        isIncrementalLoading = false
        refreshReadOnlyStatus()

        let size = fileSize(at: filePath)
        DebugFileLog.log("EditorLoad", "file size=\(size) path=\(filePath)")
        if size >= Self.largeFileRefuseThreshold {
            DebugFileLog.log("EditorLoad", "refusing large file size=\(size) path=\(filePath)")
            errorMessage = "File is too large to open (\(Self.formatBytes(size))). " +
                "Use a dedicated editor for files over \(Self.formatBytes(Self.largeFileRefuseThreshold))."
            isLoading = false
            isIncrementalLoading = false
            return
        }
        if size >= Self.largeFileWarningThreshold {
            DebugFileLog.log("EditorLoad", "awaiting large file confirmation size=\(size) path=\(filePath)")
            largeFileSize = size
            awaitingLargeFileConfirmation = true
            isLoading = false
            isIncrementalLoading = false
            return
        }

        performLoad()
    }

    func confirmLargeFileOpen() {
        DebugFileLog.log("EditorLoad", "large file confirmed path=\(filePath) size=\(largeFileSize)")
        awaitingLargeFileConfirmation = false
        isIncrementalLoading = false
        performLoad()
    }

    func cancelLargeFileOpen() {
        DebugFileLog.log("EditorLoad", "large file cancelled path=\(filePath)")
        awaitingLargeFileConfirmation = false
        isIncrementalLoading = false
        errorMessage = "File load cancelled."
    }

    private func performLoad() {
        DebugFileLog.log("EditorLoad", "performLoad started path=\(filePath)")
        isLoading = true
        isIncrementalLoading = false
        isModified = false
        errorMessage = nil
        backingStore = nil
        syntaxHighlighter?.reset()
        loadTask?.cancel()
        let path = filePath
        loadTask = Task { [weak self] in
            do {
                var hasInitialChunk = false
                for try await event in Self.streamFile(at: path) {
                    guard !Task.isCancelled, let self else { return }
                    switch event {
                    case let .initial(text, hasMore):
                        DebugFileLog.log("EditorLoad", "initial chunk chars=\(text.count) hasMore=\(hasMore) path=\(path)")
                        hasInitialChunk = true
                        let store = TextBackingStore()
                        store.loadFromText(text)
                        backingStore = store
                        backingStoreVersion += 1
                        refreshReadOnlyStatus()
                        isModified = false
                        isLoading = false
                        isIncrementalLoading = hasMore
                        if !hasMore {
                            syncLanguageServerDocument(filePath: path, text: store.fullText())
                        }
                        DebugFileLog.log(
                            "EditorLoad",
                            "initial chunk applied lineCount=\(store.lineCount) version=\(backingStoreVersion) path=\(path)"
                        )
                    case let .appended(text):
                        DebugFileLog.log("EditorLoad", "append chunk chars=\(text.count) path=\(path)")
                        if let backingStore {
                            backingStore.appendText(text)
                            backingStoreVersion += 1
                            DebugFileLog.log(
                                "EditorLoad",
                                "append applied lineCount=\(backingStore.lineCount) version=\(backingStoreVersion) path=\(path)"
                            )
                        }
                        if isLoading {
                            isLoading = false
                        }
                        if !isIncrementalLoading {
                            isIncrementalLoading = true
                        }
                    case .finished:
                        DebugFileLog.log("EditorLoad", "stream finished path=\(path)")
                        if let backingStore {
                            backingStore.finishLoading()
                            backingStoreVersion += 1
                            DebugFileLog.log(
                                "EditorLoad",
                                "finish applied lineCount=\(backingStore.lineCount) version=\(backingStoreVersion) path=\(path)"
                            )
                        }
                        refreshReadOnlyStatus()
                        if isLoading {
                            isLoading = false
                        }
                        if isIncrementalLoading {
                            isIncrementalLoading = false
                        }
                        syncLanguageServerDocument(filePath: path, text: backingStore?.fullText() ?? "")
                    }
                }

                guard let self else { return }
                if !hasInitialChunk {
                    DebugFileLog.log("EditorLoad", "no initial chunk path=\(path)")
                    isLoading = false
                    isIncrementalLoading = false
                }
            } catch {
                guard !Task.isCancelled, let self else { return }
                DebugFileLog.logError("EditorLoad", error, context: "performLoad failed path=\(path)")
                errorMessage = error.localizedDescription
                isLoading = false
                isIncrementalLoading = false
            }
        }
    }

    private func fileSize(at path: String) -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? NSNumber
        else { return 0 }
        return size.int64Value
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private static func streamFile(at path: String) -> AsyncThrowingStream<FileLoadEvent, Error> {
        let initialChunkSize = initialOpenChunkSize
        let streamChunkSize = Self.streamChunkSize
        let yieldChunkSize = Self.streamYieldChunkSize
        return AsyncThrowingStream { continuation in
            let workerTask = Task.detached(priority: .userInitiated) {
                let url = URL(fileURLWithPath: path)
                do {
                    let attrs = try FileManager.default.attributesOfItem(atPath: path)
                    let fileSize = (attrs[.size] as? NSNumber)?.int64Value ?? 0
                    DebugFileLog.log("EditorStream", "stream opened path=\(path) bytes=\(fileSize)")
                    var pendingUTF8 = Data()

                    func decodeChunk(_ chunk: Data, isFinal: Bool) throws -> String {
                        var combined = Data()
                        combined.reserveCapacity(pendingUTF8.count + chunk.count)
                        combined.append(pendingUTF8)
                        combined.append(chunk)

                        let maxTrim = min(3, combined.count)
                        for trim in 0 ... maxTrim {
                            let end = combined.count - trim
                            let prefix = combined.prefix(end)
                            guard let text = String(bytes: prefix, encoding: .utf8) else { continue }
                            pendingUTF8 = Data(combined.suffix(trim))
                            if isFinal {
                                if pendingUTF8.isEmpty { return text }
                                guard let tail = String(bytes: pendingUTF8, encoding: .utf8) else {
                                    throw CocoaError(.fileReadUnknownStringEncoding)
                                }
                                pendingUTF8.removeAll(keepingCapacity: false)
                                return text + tail
                            }
                            return text
                        }

                        throw CocoaError(.fileReadUnknownStringEncoding)
                    }

                    let handle = try FileHandle(forReadingFrom: url)
                    defer {
                        try? handle.close()
                    }

                    let initialData = try handle.read(upToCount: initialChunkSize) ?? Data()
                    DebugFileLog.log("EditorStream", "initial read bytes=\(initialData.count) path=\(path)")
                    let initialText = try decodeChunk(initialData, isFinal: false)
                    let initialDataCount = Int64(initialData.count)
                    let hasMore = initialDataCount < fileSize
                    if !hasMore {
                        let tail = try decodeChunk(Data(), isFinal: true)
                        DebugFileLog.log("EditorStream", "single chunk completed tailChars=\(tail.count) path=\(path)")
                        continuation.yield(FileLoadEvent.initial(initialText + tail, hasMore: false))
                        continuation.finish()
                        return
                    }

                    continuation.yield(FileLoadEvent.initial(initialText, hasMore: true))

                    var batch = ""
                    batch.reserveCapacity(yieldChunkSize)
                    var batchBytes = 0

                    while true {
                        try Task.checkCancellation()
                        let data = try handle.read(upToCount: streamChunkSize) ?? Data()
                        if data.isEmpty { break }
                        let text = try decodeChunk(data, isFinal: false)
                        if text.isEmpty { continue }
                        batch += text
                        batchBytes += data.count
                        if batchBytes >= yieldChunkSize {
                            DebugFileLog.log("EditorStream", "yield append batchChars=\(batch.count) batchBytes=\(batchBytes) path=\(path)")
                            continuation.yield(FileLoadEvent.appended(batch))
                            batch = ""
                            batchBytes = 0
                        }
                    }

                    let tail = try decodeChunk(Data(), isFinal: true)
                    if !tail.isEmpty {
                        batch += tail
                    }
                    if !batch.isEmpty {
                        DebugFileLog.log("EditorStream", "yield final batchChars=\(batch.count) path=\(path)")
                        continuation.yield(FileLoadEvent.appended(batch))
                    }
                    DebugFileLog.log("EditorStream", "stream completed path=\(path)")
                    continuation.yield(FileLoadEvent.finished)
                    continuation.finish()
                } catch {
                    DebugFileLog.logError("EditorStream", error, context: "stream failed path=\(path)")
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                DebugFileLog.log("EditorStream", "stream termination path=\(path)")
                workerTask.cancel()
            }
        }
    }

    func saveFile() {
        Task { [weak self] in
            try? await self?.saveFileAsync()
        }
    }

    func saveFileAsync() async throws {
        guard !isSaving else { return }
        isSaving = true
        guard let store = backingStore else {
            isSaving = false
            return
        }
        let liveContent = store.fullText()
        let textToSave: String = if !liveContent.isEmpty, !liveContent.hasSuffix("\n") {
            liveContent + "\n"
        } else {
            liveContent
        }
        let path = filePath
        refreshReadOnlyStatus()
        guard Self.canWriteFile(at: path) else {
            isSaving = false
            throw SaveError.fileIsReadOnly(path)
        }
        do {
            try await Self.writeFile(text: textToSave, path: path)
            LanguageServerManager.shared.didSave(filePath: path, projectPath: projectPath, text: textToSave)
            isSaving = false
            isModified = false
        } catch {
            isSaving = false
            throw error
        }
    }

    private static func canWriteFile(at path: String) -> Bool {
        FileManager.default.isWritableFile(atPath: path)
    }

    private func refreshReadOnlyStatus() {
        isReadOnly = !Self.canWriteFile(at: filePath)
    }

    private static func writeFile(text: String, path: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .utility).async {
                do {
                    try text.write(toFile: path, atomically: true, encoding: .utf8)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func markModified() {
        guard !isModified else { return }
        isModified = true
    }

    func notifyLanguageServerChanged() {
        lspChangeVersion += 1
    }

    func reloadFromDiskAfterExternalChange() {
        guard !isModified else { return }
        loadTask?.cancel()
        performLoad()
    }

    func navigateSearch(_ direction: EditorSearchNavigationDirection) {
        searchNavigationDirection = direction
        searchNavigationVersion += 1
    }

    func requestReplaceCurrent() {
        replaceVersion += 1
    }

    func requestReplaceAll() {
        replaceAllVersion += 1
    }
}
