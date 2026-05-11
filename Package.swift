// swift-tools-version: 6.0

import Foundation
import PackageDescription

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let cefRoot = packageRoot + "/.dev-support/cef-runtime/cef_binary"
let cefBuild = packageRoot + "/.dev-support/cef-runtime/build"

let package = Package(
    name: "Kaji",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.1"),
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.1"),
        .package(url: "https://github.com/tree-sitter/swift-tree-sitter", from: "0.25.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-bash", from: "0.25.0"),
    ],
    targets: [
        .target(
            name: "CEFBridge",
            path: "CEFBridge",
            publicHeadersPath: "include",
            cxxSettings: [
                .unsafeFlags([
                    "-I", cefRoot,
                    "-I", cefRoot + "/include",
                    "-std=c++20",
                    "-fno-exceptions",
                    "-fno-rtti",
                    "-fobjc-call-cxx-cdtors",
                ]),
            ],
            linkerSettings: [
                .unsafeFlags([
                    cefBuild + "/libcef_dll_wrapper/libcef_dll_wrapper.a",
                    "-F", cefRoot + "/Release",
                    "-framework", "Chromium Embedded Framework",
                    "-Xlinker", "-rpath",
                    "-Xlinker", cefRoot + "/Release",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks",
                ]),
                .linkedFramework("AppKit"),
                .linkedFramework("Cocoa"),
                .linkedFramework("IOSurface"),
                .linkedLibrary("c++"),
            ]
        ),
        .target(
            name: "GhosttyKit",
            path: "GhosttyKit",
            publicHeadersPath: "."
        ),
        .executableTarget(
            name: "Kaji",
            dependencies: [
                "CEFBridge",
                "GhosttyKit",
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
                .product(name: "TreeSitterBash", package: "tree-sitter-bash"),
            ],
            path: "Kaji",
            exclude: ["Info.plist", "Kaji.entitlements"],
            resources: [
                .process("Resources"),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "GhosttyKit.xcframework/macos-arm64_x86_64/ghostty-internal.a",
                    "-F", cefRoot + "/Release",
                    "-Xlinker", "-rpath",
                    "-Xlinker", cefRoot + "/Release",
                ]),
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreText"),
                .linkedFramework("Foundation"),
                .linkedFramework("IOKit"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("QuartzCore"),
                .linkedLibrary("c++"),
            ]
        ),
        .executableTarget(
            name: "KajiHookClient",
            path: "KajiHookClient"
        ),
        .testTarget(
            name: "KajiTests",
            dependencies: [
                "Kaji",
            ],
            path: "Tests/KajiTests",
            linkerSettings: [
                .unsafeFlags([
                    "GhosttyKit.xcframework/macos-arm64_x86_64/ghostty-internal.a",
                    "-F", cefRoot + "/Release",
                    "-Xlinker", "-rpath",
                    "-Xlinker", cefRoot + "/Release",
                ]),
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreText"),
                .linkedFramework("Foundation"),
                .linkedFramework("IOKit"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("QuartzCore"),
                .linkedLibrary("c++"),
            ]
        ),
    ]
)
