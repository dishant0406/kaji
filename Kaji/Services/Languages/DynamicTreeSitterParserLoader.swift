import Darwin
import Foundation
import SwiftTreeSitter

enum DynamicTreeSitterParserLoader {
    static func language(from url: URL, parserID: String) -> Language? {
        guard let handle = dlopen(url.path, RTLD_NOW | RTLD_LOCAL) else { return nil }
        let symbol = parserSymbolName(for: parserID)
        guard let pointer = dlsym(handle, symbol) else {
            dlclose(handle)
            return nil
        }
        typealias LanguageFunction = @convention(c) () -> OpaquePointer?
        let function = unsafeBitCast(pointer, to: LanguageFunction.self)
        guard let language = function() else {
            dlclose(handle)
            return nil
        }
        return Language(language)
    }

    private static func parserSymbolName(for parserID: String) -> String {
        let name = parserID
            .replacingOccurrences(of: "tree-sitter-", with: "")
            .replacingOccurrences(of: "tree_sitter_", with: "")
            .replacingOccurrences(of: "-", with: "_")
        return "tree_sitter_\(name)"
    }
}
