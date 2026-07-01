import AppKit
import TermyKit

struct TermyRenderConfig: Equatable {
    let fontFamily: String
    let fontSize: CGFloat
    let lineHeight: CGFloat
    let cellWidth: CGFloat
    let cellHeight: CGFloat
    let foreground: TermyRGBA
    let background: TermyRGBA
    let cursor: TermyRGBA
    let selectionBackground: TermyRGBA

    static let `default` = TermyRenderConfig(
        fontFamily: "SF Mono",
        fontSize: 13,
        lineHeight: 1.2,
        cellWidth: 8,
        cellHeight: 18,
        foreground: TermyRGBA(r: 230, g: 225, b: 207, a: 255),
        background: TermyRGBA(r: 15, g: 20, b: 25, a: 255),
        cursor: TermyRGBA(r: 230, g: 225, b: 207, a: 255),
        selectionBackground: TermyRGBA(r: 39, g: 55, b: 71, a: 255)
    )

    static func load(contents: String? = nil) -> TermyRenderConfig {
        var config: OpaquePointer?
        let status = if let contents, !contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Array(contents.utf8).withUnsafeBufferPointer { buffer in
                termy_config_from_contents(buffer.baseAddress, buffer.count, &config)
            }
        } else {
            termy_config_load_default(&config)
        }
        guard status == TERMY_FFI_OK else { return .default }
        defer { termy_config_free(config) }
        var ffi = TermyFfiRenderConfig()
        guard termy_config_render_config(config, &ffi) == TERMY_FFI_OK else { return .default }
        defer { termy_render_config_free(&ffi) }
        return TermyRenderConfig(
            fontFamily: TermyBytes.string(ffi.font_family) ?? Self.default.fontFamily,
            fontSize: CGFloat(ffi.font_size),
            lineHeight: CGFloat(ffi.line_height),
            cellWidth: CGFloat(ffi.cell_width),
            cellHeight: CGFloat(ffi.cell_height),
            foreground: TermyRGBA(ffi.foreground),
            background: TermyRGBA(ffi.background),
            cursor: TermyRGBA(ffi.cursor),
            selectionBackground: TermyRGBA(r: 39, g: 55, b: 71, a: 255)
        )
    }
}
