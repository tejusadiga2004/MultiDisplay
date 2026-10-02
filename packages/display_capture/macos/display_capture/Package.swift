// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "display_capture",
    platforms: [.macOS("14.0")],
    products: [
        .library(name: "display-capture", type: .static, targets: ["display_capture"]),
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
    ],
    targets: [
        .target(
            name: "display_capture",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
            ],
            resources: [
                .process("DisplayCapture.metal"),
            ]
        ),
    ]
)
