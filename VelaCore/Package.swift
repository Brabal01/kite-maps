// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VelaCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "VelaCore", targets: ["VelaCore"]),
    ],
    targets: [
        .systemLibrary(name: "CZlib", pkgConfig: "zlib", providers: [.apt(["zlib1g-dev"])]),
        .target(name: "VelaCore", dependencies: [.target(name: "CZlib", condition: .when(platforms: [.linux]))]),
        // `swift run vela-probe pizza` asks Google live and prints what the parser saw.
        .executableTarget(name: "vela-probe", dependencies: ["VelaCore"]),
        .testTarget(name: "VelaCoreTests", dependencies: ["VelaCore"]),
    ]
)
