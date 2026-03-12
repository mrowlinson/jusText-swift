// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "jusText",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "jusText", targets: ["jusText"]),
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.0"),
    ],
    targets: [
        .target(
            name: "jusText",
            dependencies: ["SwiftSoup"],
            resources: [.copy("Resources/Stoplists")]
        ),
        .testTarget(
            name: "JusTextTests",
            dependencies: ["jusText"]
        ),
        .executableTarget(
            name: "demo",
            dependencies: ["jusText"]
        ),
    ]
)
