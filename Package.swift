// swift-tools-version: 6.1

import PackageDescription

#if os(macOS)
    let macProducts: [Product] = [
        .library(
            name: "MarkdownPDFMac",
            targets: ["MarkdownPDFMac"],
        ),
    ]

    let macTargets: [Target] = [
        .target(
            name: "MarkdownPDFMac",
            dependencies: ["MarkdownPDF"],
        ),
    ]

    let macTestDependencies: [Target.Dependency] = ["MarkdownPDFMac"]
#else
    let macProducts: [Product] = []
    let macTargets: [Target] = []
    let macTestDependencies: [Target.Dependency] = []
#endif

let package = Package(
    name: "MarkdownPDF",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "MarkdownPDF",
            targets: ["MarkdownPDF"],
        ),
        .library(
            name: "MarkdownPDFLinux",
            targets: ["MarkdownPDFLinux"],
        ),
        .library(
            name: "MarkdownPDFResume",
            targets: ["MarkdownPDFResume"],
        ),
    ] + macProducts,
    dependencies: [
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.4.3"),
        .package(url: "https://codeberg.org/MarkdownPdfHQ/MathTypeset.git", from: "0.6.0"),
    ],
    targets: [
        .target(
            name: "MarkdownPDF",
            dependencies: [
                .product(name: "MathTypeset", package: "MathTypeset"),
            ],
            resources: [.copy("Fonts")],
        ),
        .target(
            name: "MarkdownPDFDocumentation",
        ),
        .target(
            name: "MarkdownPDFLinux",
            dependencies: ["MarkdownPDF"],
        ),
        .target(
            name: "MarkdownPDFResume",
        ),
        .testTarget(
            name: "MarkdownPDFTests",
            dependencies: [
                "MarkdownPDF",
                "MarkdownPDFLinux",
                .product(name: "MathTypeset", package: "MathTypeset"),
            ] + macTestDependencies,
            exclude: ["Fixtures"],
        ),
        .testTarget(
            name: "MarkdownPDFResumeTests",
            dependencies: ["MarkdownPDF", "MarkdownPDFResume"],
            exclude: ["Fixtures"],
        ),
    ] + macTargets,
)
