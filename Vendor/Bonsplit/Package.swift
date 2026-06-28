// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Bonsplit",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "Bonsplit", targets: ["Bonsplit"]),
    ],
    targets: [
        .target(name: "Bonsplit", path: "Sources/Bonsplit"),
    ]
)
