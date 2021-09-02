// swift-tools-version:5.4

import PackageDescription

let package = Package(
    name: "ImageUI",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(name: "ImageUI", targets: ["ImageUI"])
    ],
    dependencies: [
        .package(url: "https://github.com/kean/Nuke.git", .upToNextMajor(from: "10.4.1"))
    ],
    targets: [
        .target(name: "ImageUI", dependencies: ["Nuke"])
    ]
)
