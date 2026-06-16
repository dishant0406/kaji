import Foundation

enum MonacoLanguageMapper {
    static func languageID(for filePath: String) -> String {
        let url = URL(fileURLWithPath: filePath)
        let ext = url.pathExtension.lowercased()
        let fileName = url.lastPathComponent.lowercased()
        if fileName == "dockerfile" { return "dockerfile" }
        if fileName == "makefile" || fileName.hasPrefix("makefile.") { return "makefile" }
        if fileName == ".gitignore" { return "ignore" }
        return switch ext {
        case "swift": "swift"
        case "m", "mm": "objective-c"
        case "c", "h": "c"
        case "cc", "cpp", "cxx", "hpp", "hh", "hxx": "cpp"
        case "cs": "csharp"
        case "java": "java"
        case "kt", "kts": "kotlin"
        case "scala": "scala"
        case "go": "go"
        case "rs": "rust"
        case "zig": "zig"
        case "dart": "dart"
        case "js", "mjs", "cjs": "javascript"
        case "jsx": "javascript"
        case "ts", "mts", "cts": "typescript"
        case "tsx": "typescript"
        case "php": "php"
        case "py", "pyw": "python"
        case "rb": "ruby"
        case "lua": "lua"
        case "sh", "bash", "zsh", "fish": "shell"
        case "pl", "pm": "perl"
        case "ex", "exs": "elixir"
        case "hs": "haskell"
        case "r": "r"
        case "jl": "julia"
        case "clj", "cljs", "cljc": "clojure"
        case "ml", "mli": "ocaml"
        case "ps1", "psm1": "powershell"
        case "html", "htm": "html"
        case "xml", "xsd", "svg": "xml"
        case "css": "css"
        case "scss": "scss"
        case "less": "less"
        case "md", "markdown", "mdown", "mkd": "markdown"
        case "vue": "html"
        case "svelte": "html"
        case "graphql", "gql": "graphql"
        case "tf", "tfvars", "hcl": "hcl"
        case "csv", "tsv": "plaintext"
        case "json", "jsonc", "map": "json"
        case "yaml", "yml": "yaml"
        case "toml": "toml"
        case "ini", "conf", "cfg": "ini"
        case "sql": "sql"
        default: "plaintext"
        }
    }
}
