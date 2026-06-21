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
        .package(url: "https://github.com/EmergeTools/Pow", from: "1.0.5"),
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.1"),
        .package(url: "https://github.com/siteline/swiftui-introspect", from: "26.0.0"),
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
        .target(
            name: "FFFKit",
            path: "FFFKit",
            publicHeadersPath: "include"
        ),
        .target(
            name: "SwiftyDiff",
            path: "Vendor/SwiftyDiff/Sources/SwiftyDiff"
        ),
        .executableTarget(
            name: "Kaji",
            dependencies: [
                "CEFBridge",
                "FFFKit",
                "GhosttyKit",
                "SwiftyDiff",
                .product(name: "Pow", package: "Pow"),
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "SwiftUIIntrospect", package: "swiftui-introspect"),
            ],
            path: "Kaji",
            exclude: [
                "Info.plist",
                "Kaji.entitlements",
                "Resources/MonacoEditor",
            ],
            resources: [
                .copy("Resources/MonacoEditor"),
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
                "FFFKit",
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
