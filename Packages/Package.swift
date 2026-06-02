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

let coreProducts: [Product] = [
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
    .executable(
        name: "markdownpdf",
        targets: ["MarkdownPDFCLI"],
    ),
    .executable(
        name: "resumepdf",
        targets: ["ResumePDFCLI"],
    ),
]

let coreTargets: [Target] = [
    .target(
        name: "MarkdownPDF",
    ),
    .target(
        name: "MarkdownPDFDocumentation",
    ),
    .target(
        name: "MarkdownPDFLinux",
        dependencies: ["MarkdownPDF"],
    ),
    .executableTarget(
        name: "MarkdownPDFCLI",
        dependencies: ["MarkdownPDF"],
    ),
    .target(
        name: "MarkdownPDFResume",
    ),
    .executableTarget(
        name: "ResumePDFCLI",
        dependencies: ["MarkdownPDF", "MarkdownPDFResume"],
    ),
    .testTarget(
        name: "MarkdownPDFTests",
        dependencies: ["MarkdownPDF", "MarkdownPDFLinux"] + macTestDependencies,
        exclude: ["Fixtures"],
    ),
    .testTarget(
        name: "MarkdownPDFResumeTests",
        dependencies: ["MarkdownPDF", "MarkdownPDFResume"],
        exclude: ["Fixtures"],
    ),
]

let package = Package(
    name: "MarkdownPDF",
    platforms: [
        .macOS(.v13),
    ],
    products: coreProducts + macProducts,
    dependencies: [
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.4.3"),
    ],
    targets: coreTargets + macTargets,
)
