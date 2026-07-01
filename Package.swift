// swift-tools-version: 6.0

import Foundation
import PackageDescription

let packageDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let termyLibraryPath = packageDirectory.appendingPathComponent("TermyKit/lib").path
let termyLinkerSettings: [LinkerSetting] = [
    .unsafeFlags([
        "-L", termyLibraryPath,
        "-ltermy_ffi",
        "-Xlinker", "-rpath",
        "-Xlinker", termyLibraryPath,
    ]),
]

let package = Package(
    name: "Kaji",
    platforms: [
        .macOS(.v15),
    ],
    dependencies: [
        .package(url: "https://github.com/EmergeTools/Pow", from: "1.0.5"),
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.1"),
        .package(url: "https://github.com/siteline/swiftui-introspect", from: "26.0.0"),
        .package(url: "https://github.com/dishant0406/reorderable", exact: "1.3.2-kaji.3"),
        .package(url: "https://github.com/FluidInference/FluidAudio", exact: "0.15.4"),
        .package(path: "Vendor/Bonsplit"),
    ],
    targets: [
        .target(
            name: "TermyKit",
            path: "TermyKit",
            publicHeadersPath: "."
        ),
        .target(
            name: "TermySwiftEmbed",
            dependencies: ["TermyKit"],
            path: "Vendor/TermySwiftEmbed/Sources/TermySwiftEmbed"
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
                "FFFKit",
                "TermyKit",
                "TermySwiftEmbed",
                "SwiftyDiff",
                .product(name: "Reorderable", package: "reorderable"),
                .product(name: "Bonsplit", package: "Bonsplit"),
                .product(name: "Pow", package: "Pow"),
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "SwiftUIIntrospect", package: "swiftui-introspect"),
                .product(name: "FluidAudio", package: "FluidAudio"),
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
            linkerSettings: termyLinkerSettings + [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreText"),
                .linkedFramework("Foundation"),
                .linkedFramework("IOKit"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("WebKit"),
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
                "TermySwiftEmbed",
            ],
            path: "Tests/KajiTests",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreText"),
                .linkedFramework("Foundation"),
                .linkedFramework("IOKit"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("WebKit"),
                .linkedLibrary("c++"),
            ]
        ),
    ]
)
