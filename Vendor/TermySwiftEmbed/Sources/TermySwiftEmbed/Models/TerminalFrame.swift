import AppKit
import SwiftUI
import TermyKit

struct TerminalRGBA: Equatable {
    private var packedRGBA: UInt32

    init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.init(
            redByte: Self.byte(red),
            greenByte: Self.byte(green),
            blueByte: Self.byte(blue),
            alphaByte: Self.byte(alpha)
        )
    }

    init(redByte: UInt8, greenByte: UInt8, blueByte: UInt8, alphaByte: UInt8) {
        packedRGBA = UInt32(redByte) << 24
            | UInt32(greenByte) << 16
            | UInt32(blueByte) << 8
            | UInt32(alphaByte)
    }

    init(_ color: TermyFfiColor) {
        self.init(redByte: color.r, greenByte: color.g, blueByte: color.b, alphaByte: color.a)
    }

    /// The packed `0xRRGGBBAA` value. Stable and cheap, so it doubles as a
    /// cache key for derived `NSColor`s and typeset lines in the renderer.
    var packedValue: UInt32 {
        packedRGBA
    }

    var red: Double {
        Double((packedRGBA >> 24) & 0xFF) / 255.0
    }

    var green: Double {
        Double((packedRGBA >> 16) & 0xFF) / 255.0
    }

    var blue: Double {
        Double((packedRGBA >> 8) & 0xFF) / 255.0
    }

    var alpha: Double {
        Double(packedRGBA & 0xFF) / 255.0
    }

    var swiftUIColor: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }

    /// Terminal escape-sequence colors are sRGB by convention; the calibrated
    /// generic color space renders them visibly duller.
    var nsColor: NSColor {
        NSColor(
            srgbRed: red,
            green: green,
            blue: blue,
            alpha: alpha
        )
    }

    private static func byte(_ value: Double) -> UInt8 {
        UInt8((min(1.0, max(0.0, value)) * 255.0).rounded())
    }

    static let termyForeground = TerminalRGBA(redByte: 232, greenByte: 235, blueByte: 245, alphaByte: 255)
    static let termyBackground = TerminalRGBA(redByte: 10, greenByte: 15, blueByte: 33, alphaByte: 255)
    static let termyCursor = TerminalRGBA(redByte: 166, greenByte: 232, blueByte: 163, alphaByte: 255)
}

struct TerminalRenderConfig: Equatable {
    var fontFamily: String
    var activeTheme: String
    var foreground: TerminalRGBA
    var background: TerminalRGBA
    var cursor: TerminalRGBA
    var fontSize: CGFloat
    var lineHeight: CGFloat
    var paddingX: CGFloat
    var paddingY: CGFloat
    var backgroundOpacity: Double
    var backgroundOpacityCells: Bool
    var cursorBlink: Bool
    var cursorStyle: TerminalCursorStyle
    var measuredCellWidth: CGFloat
    var measuredCellHeight: CGFloat
    var backgroundBlur: Bool
    var mouseScrollMultiplier: CGFloat
    var scrollbarVisibility: TerminalScrollbarVisibility
    var scrollbarStyle: TerminalScrollbarStyle
    var copyOnSelect: Bool
    var copyOnSelectToast: Bool
    var paneFocusEffect: TerminalPaneFocusEffect
    var paneFocusStrength: CGFloat
    var chromeContrast: Bool

    static let `default` = TerminalRenderConfig(
        fontFamily: "JetBrains Mono",
        activeTheme: "termy",
        foreground: .termyForeground,
        background: .termyBackground,
        cursor: .termyCursor,
        fontSize: 14.0,
        lineHeight: 1.4,
        paddingX: 12.0,
        paddingY: 8.0,
        backgroundOpacity: 1.0,
        backgroundOpacityCells: false,
        cursorBlink: true,
        cursorStyle: .block,
        measuredCellWidth: 9.0,
        measuredCellHeight: 19.6,
        backgroundBlur: false,
        mouseScrollMultiplier: 3.0,
        scrollbarVisibility: .onScroll,
        scrollbarStyle: .neutral,
        copyOnSelect: false,
        copyOnSelectToast: true,
        paneFocusEffect: .softSpotlight,
        paneFocusStrength: 0.6,
        chromeContrast: false
    )

    init(
        fontFamily: String,
        activeTheme: String,
        foreground: TerminalRGBA,
        background: TerminalRGBA,
        cursor: TerminalRGBA,
        fontSize: CGFloat,
        lineHeight: CGFloat,
        paddingX: CGFloat,
        paddingY: CGFloat,
        backgroundOpacity: Double,
        backgroundOpacityCells: Bool,
        cursorBlink: Bool,
        cursorStyle: TerminalCursorStyle,
        measuredCellWidth: CGFloat,
        measuredCellHeight: CGFloat,
        backgroundBlur: Bool,
        mouseScrollMultiplier: CGFloat,
        scrollbarVisibility: TerminalScrollbarVisibility,
        scrollbarStyle: TerminalScrollbarStyle,
        copyOnSelect: Bool,
        copyOnSelectToast: Bool,
        paneFocusEffect: TerminalPaneFocusEffect,
        paneFocusStrength: CGFloat,
        chromeContrast: Bool
    ) {
        self.fontFamily = fontFamily
        self.activeTheme = activeTheme
        self.foreground = foreground
        self.background = background
        self.cursor = cursor
        self.fontSize = max(1.0, fontSize)
        self.lineHeight = max(0.8, lineHeight)
        self.paddingX = max(0.0, paddingX)
        self.paddingY = max(0.0, paddingY)
        self.backgroundOpacity = min(1.0, max(0.0, backgroundOpacity))
        self.backgroundOpacityCells = backgroundOpacityCells
        self.cursorBlink = cursorBlink
        self.cursorStyle = cursorStyle
        self.measuredCellWidth = max(1.0, measuredCellWidth)
        self.measuredCellHeight = max(1.0, measuredCellHeight)
        self.backgroundBlur = backgroundBlur
        self.mouseScrollMultiplier = max(0.0, mouseScrollMultiplier)
        self.scrollbarVisibility = scrollbarVisibility
        self.scrollbarStyle = scrollbarStyle
        self.copyOnSelect = copyOnSelect
        self.copyOnSelectToast = copyOnSelectToast
        self.paneFocusEffect = paneFocusEffect
        self.paneFocusStrength = max(0.0, min(2.0, paneFocusStrength))
        self.chromeContrast = chromeContrast
    }

    init(_ ffiConfig: TermyFfiRenderConfig) {
        self.init(
            fontFamily: TermyFfiBridge.string(from: ffiConfig.font_family) ?? Self.default.fontFamily,
            activeTheme: TermyFfiBridge.string(from: ffiConfig.active_theme) ?? Self.default.activeTheme,
            foreground: TerminalRGBA(ffiConfig.foreground),
            background: TerminalRGBA(ffiConfig.background),
            cursor: TerminalRGBA(ffiConfig.cursor),
            fontSize: CGFloat(ffiConfig.font_size),
            lineHeight: CGFloat(ffiConfig.line_height),
            paddingX: CGFloat(ffiConfig.padding_x),
            paddingY: CGFloat(ffiConfig.padding_y),
            backgroundOpacity: Double(ffiConfig.background_opacity),
            backgroundOpacityCells: ffiConfig.background_opacity_cells,
            cursorBlink: ffiConfig.cursor_blink,
            cursorStyle: TerminalCursorStyle(ffiRawValue: ffiConfig.cursor_style),
            measuredCellWidth: CGFloat(ffiConfig.cell_width),
            measuredCellHeight: CGFloat(ffiConfig.cell_height),
            backgroundBlur: ffiConfig.background_blur,
            mouseScrollMultiplier: CGFloat(ffiConfig.mouse_scroll_multiplier),
            scrollbarVisibility: TerminalScrollbarVisibility(ffiRawValue: ffiConfig.scrollbar_visibility),
            scrollbarStyle: TerminalScrollbarStyle(ffiRawValue: ffiConfig.scrollbar_style),
            copyOnSelect: ffiConfig.copy_on_select,
            copyOnSelectToast: ffiConfig.copy_on_select_toast,
            paneFocusEffect: TerminalPaneFocusEffect(ffiRawValue: ffiConfig.pane_focus_effect),
            paneFocusStrength: CGFloat(ffiConfig.pane_focus_strength),
            chromeContrast: ffiConfig.chrome_contrast
        )
    }

    var cellWidth: CGFloat {
        measuredCellWidth
    }

    var cellHeight: CGFloat {
        measuredCellHeight
    }
}

enum TerminalCursorStyle: UInt32 {
    case line = 1
    case block = 2

    init(ffiRawValue: UInt32) {
        self = TerminalCursorStyle(rawValue: ffiRawValue) ?? .block
    }
}

enum TerminalScrollbarVisibility: UInt32 {
    case off = 0
    case always = 1
    case onScroll = 2

    init(ffiRawValue: UInt32) {
        self = TerminalScrollbarVisibility(rawValue: ffiRawValue) ?? .onScroll
    }
}

enum TerminalScrollbarStyle: UInt32 {
    case neutral = 0
    case mutedTheme = 1
    case theme = 2

    init(ffiRawValue: UInt32) {
        self = TerminalScrollbarStyle(rawValue: ffiRawValue) ?? .neutral
    }
}

enum TerminalPaneFocusEffect: UInt32 {
    case off = 0
    case softSpotlight = 1
    case cinematic = 2
    case minimal = 3

    init(ffiRawValue: UInt32) {
        self = TerminalPaneFocusEffect(rawValue: ffiRawValue) ?? .softSpotlight
    }
}

struct TerminalGridPosition: Equatable {
    var col: Int
    var row: Int
}

struct TerminalSelection: Equatable {
    var anchor: TerminalGridPosition
    var active: TerminalGridPosition

    var normalized: (start: TerminalGridPosition, end: TerminalGridPosition) {
        if (anchor.row, anchor.col) <= (active.row, active.col) {
            return (anchor, active)
        }
        return (active, anchor)
    }

    func rowRanges(cols: Int, rows: Int) -> [TerminalSelectionRowRange] {
        guard cols > 0, rows > 0 else {
            return []
        }

        let range = normalized
        let startRow = max(0, min(range.start.row, rows - 1))
        let endRow = max(0, min(range.end.row, rows - 1))
        guard startRow <= endRow else {
            return []
        }

        return (startRow ... endRow).map { row in
            let startCol = row == startRow ? range.start.col : 0
            let endCol = row == endRow ? range.end.col : cols - 1
            return TerminalSelectionRowRange(
                row: row,
                startCol: max(0, min(startCol, cols - 1)),
                endCol: max(0, min(endCol, cols - 1))
            )
        }
    }
}

struct TerminalSelectionRowRange: Identifiable, Equatable {
    var id: Int {
        row
    }

    var row: Int
    var startCol: Int
    var endCol: Int
}

struct TerminalCell: Identifiable, Equatable {
    var id: Int {
        (row * 10000) + col
    }

    var col: Int
    var row: Int
    var codepoint: UInt32
    var foreground: TerminalRGBA
    var background: TerminalRGBA
    var usesTerminalDefaultBackground: Bool
    var renderText: Bool
    var bold: Bool

    init(
        col: Int,
        row: Int,
        character: Character,
        foreground: TerminalRGBA,
        background: TerminalRGBA,
        usesTerminalDefaultBackground: Bool,
        renderText: Bool,
        bold: Bool
    ) {
        self.col = col
        self.row = row
        codepoint = Self.codepoint(from: character)
        self.foreground = foreground
        self.background = background
        self.usesTerminalDefaultBackground = usesTerminalDefaultBackground
        self.renderText = renderText
        self.bold = bold
    }

    init(
        col: Int,
        row: Int,
        codepoint: UInt32,
        foreground: TerminalRGBA,
        background: TerminalRGBA,
        usesTerminalDefaultBackground: Bool,
        renderText: Bool,
        bold: Bool
    ) {
        self.col = col
        self.row = row
        self.codepoint = UnicodeScalar(codepoint) == nil ? 32 : codepoint
        self.foreground = foreground
        self.background = background
        self.usesTerminalDefaultBackground = usesTerminalDefaultBackground
        self.renderText = renderText
        self.bold = bold
    }

    var character: Character {
        get {
            UnicodeScalar(codepoint).map(Character.init) ?? " "
        }
        set {
            codepoint = Self.codepoint(from: newValue)
        }
    }

    private static func codepoint(from character: Character) -> UInt32 {
        character.unicodeScalars.first.map { UInt32($0.value) } ?? 32
    }
}

struct TerminalCursor: Equatable {
    var col: Int
    var row: Int
    var style: TerminalCursorStyle
}

struct TerminalFrameMetadata: Equatable {
    var cols: Int
    var rows: Int
    var cursor: TerminalCursor?
    var displayOffset: Int
    var historySize: Int

    static let empty = TerminalFrameMetadata(
        cols: 0,
        rows: 0,
        cursor: nil,
        displayOffset: 0,
        historySize: 0
    )

    init(
        cols: Int,
        rows: Int,
        cursor: TerminalCursor?,
        displayOffset: Int,
        historySize: Int
    ) {
        self.cols = cols
        self.rows = rows
        self.cursor = cursor
        self.displayOffset = displayOffset
        self.historySize = historySize
    }

    init(frame: TerminalFrame) {
        self.init(
            cols: frame.cols,
            rows: frame.rows,
            cursor: frame.cursor,
            displayOffset: frame.displayOffset,
            historySize: frame.historySize
        )
    }
}

private final class TerminalCellStorage: Equatable {
    var cells: [TerminalCell]

    init(_ cells: [TerminalCell]) {
        self.cells = cells
    }

    static func == (lhs: TerminalCellStorage, rhs: TerminalCellStorage) -> Bool {
        lhs.cells == rhs.cells
    }
}

struct TerminalFrame: Equatable {
    var cols: Int
    var rows: Int
    private var cellStorage: TerminalCellStorage
    var cursor: TerminalCursor?
    var displayOffset: Int
    var historySize: Int

    init(
        cols: Int,
        rows: Int,
        cells: [TerminalCell],
        cursor: TerminalCursor?,
        displayOffset: Int,
        historySize: Int
    ) {
        self.cols = cols
        self.rows = rows
        cellStorage = TerminalCellStorage(cells)
        self.cursor = cursor
        self.displayOffset = displayOffset
        self.historySize = historySize
    }

    var cells: [TerminalCell] {
        get {
            cellStorage.cells
        }
        set {
            cellStorage = TerminalCellStorage(newValue)
        }
    }

    static var empty: TerminalFrame {
        TerminalFrame(
            cols: 0,
            rows: 0,
            cells: [],
            cursor: nil,
            displayOffset: 0,
            historySize: 0
        )
    }

    static func plainTextPreview(_ text: String, cols: Int = 96, rows: Int = 28) -> TerminalFrame {
        let cols = max(2, cols)
        let rows = max(2, rows)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            .suffix(rows)
            .map(String.init)
        let topPadding = max(0, rows - lines.count)
        var cells: [TerminalCell] = []
        cells.reserveCapacity(cols * rows)

        for row in 0 ..< rows {
            let lineIndex = row - topPadding
            let characters = lineIndex >= 0 ? Array(lines[lineIndex].prefix(cols)) : []
            for col in 0 ..< cols {
                let character = characters.indices.contains(col) ? characters[col] : " "
                cells.append(TerminalCell(
                    col: col,
                    row: row,
                    character: character,
                    foreground: .termyForeground,
                    background: .termyBackground,
                    usesTerminalDefaultBackground: true,
                    renderText: character != " ",
                    bold: false
                ))
            }
        }

        return TerminalFrame(
            cols: cols,
            rows: rows,
            cells: cells,
            cursor: nil,
            displayOffset: 0,
            historySize: 0
        )
    }

    func cells(inRow row: Int) -> ArraySlice<TerminalCell> {
        let start = row * cols
        let end = start + cols
        guard row >= 0, cols > 0, start >= 0, end <= cellStorage.cells.count else {
            return []
        }
        return cellStorage.cells[start ..< end]
    }

    func cell(row: Int, col: Int) -> TerminalCell? {
        guard row >= 0, row < rows, col >= 0, col < cols else {
            return nil
        }
        let index = (row * cols) + col
        guard index >= 0, index < cellStorage.cells.count else {
            return nil
        }
        return cellStorage.cells[index]
    }

    @discardableResult
    mutating func setCell(_ cell: TerminalCell, at index: Int) -> Bool {
        guard index >= 0, index < cellStorage.cells.count else {
            return false
        }
        guard cellStorage.cells[index] != cell else {
            return false
        }
        cellStorage.cells[index] = cell
        return true
    }

    func selectedText(for selection: TerminalSelection?) -> String? {
        guard let selection else {
            return nil
        }

        let lines = selection.rowRanges(cols: cols, rows: rows).map { range in
            let characters = (range.startCol ... range.endCol).map { col -> Character in
                guard let cell = cell(row: range.row, col: col), cell.renderText else {
                    return " "
                }
                return cell.character
            }
            return String(characters).trimmingTrailingSpaces()
        }
        guard !lines.isEmpty else {
            return nil
        }
        return lines.joined(separator: "\n")
    }

    /// Whether `selectedText(for:)` would return non-empty text, without
    /// building the string (this runs per render pass). A multi-row selection
    /// is always non-empty (the row join contributes a newline); a single-row
    /// selection is non-empty exactly when some cell renders a non-space — the
    /// trailing-space trim removes everything else.
    func hasSelectedText(for selection: TerminalSelection?) -> Bool {
        guard let selection else {
            return false
        }
        let ranges = selection.rowRanges(cols: cols, rows: rows)
        guard let range = ranges.first else {
            return false
        }
        if ranges.count > 1 {
            return true
        }
        guard range.startCol <= range.endCol else {
            return false
        }
        return (range.startCol ... range.endCol).contains { col in
            guard let cell = cell(row: range.row, col: col), cell.renderText else {
                return false
            }
            return cell.character != " "
        }
    }

    var hasVisibleContent: Bool {
        cells.contains { cell in
            cell.renderText && cell.character != " "
        }
    }

    func visibleTextSnapshot() -> String {
        guard cols > 0, rows > 0 else {
            return ""
        }
        return (0 ..< rows)
            .map { row in
                String(cells(inRow: row).map { $0.renderText ? $0.character : " " })
                    .trimmingTrailingSpaces()
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Word selection for double-click: expands from `position` over a contiguous
    /// run of same-class characters (word vs. non-word punctuation), stopping at
    /// whitespace. Word characters include path/URL-friendly punctuation so file
    /// paths and URLs select as a single token. Returns nil over whitespace.
    func wordSelection(at position: TerminalGridPosition) -> TerminalSelection? {
        guard cols > 0, rows > 0,
              position.row >= 0, position.row < rows,
              position.col >= 0, position.col < cols
        else {
            return nil
        }

        func character(at col: Int) -> Character {
            guard let cell = cell(row: position.row, col: col), cell.renderText else {
                return " "
            }
            return cell.character
        }

        let target = character(at: position.col)
        guard !target.isWhitespace else {
            return nil
        }
        let targetIsWord = TerminalFrame.isWordCharacter(target)

        func matches(_ col: Int) -> Bool {
            let c = character(at: col)
            return !c.isWhitespace && TerminalFrame.isWordCharacter(c) == targetIsWord
        }

        var startCol = position.col
        while startCol > 0, matches(startCol - 1) {
            startCol -= 1
        }
        var endCol = position.col
        while endCol < cols - 1, matches(endCol + 1) {
            endCol += 1
        }

        return TerminalSelection(
            anchor: TerminalGridPosition(col: startCol, row: position.row),
            active: TerminalGridPosition(col: endCol, row: position.row)
        )
    }

    /// Line selection for triple-click: selects the full visible row. Trailing
    /// blanks are trimmed when the text is copied.
    func lineSelection(at position: TerminalGridPosition) -> TerminalSelection? {
        guard cols > 0, rows > 0, position.row >= 0, position.row < rows else {
            return nil
        }
        return TerminalSelection(
            anchor: TerminalGridPosition(col: 0, row: position.row),
            active: TerminalGridPosition(col: cols - 1, row: position.row)
        )
    }

    static func isWordCharacter(_ character: Character) -> Bool {
        if character.isLetter || character.isNumber {
            return true
        }
        return "_./-~:@%+=?&#".contains(character)
    }
}

private extension String {
    func trimmingTrailingSpaces() -> String {
        var result = self
        while result.last == " " {
            result.removeLast()
        }
        return result
    }
}
