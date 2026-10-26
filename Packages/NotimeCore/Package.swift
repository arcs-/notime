// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotimeCore",
    platforms: [
        .iOS(.v17),
        // macOS is listed only so `swift test` can run the pure domain tests on the host.
        .macOS(.v14),
    ],
    products: [
        .library(name: "NotimeCore", targets: ["NotimeCore"]),
    ],
    targets: [
        .target(name: "NotimeCore"),
        .testTarget(name: "NotimeCoreTests", dependencies: ["NotimeCore"]),
    ]
)
