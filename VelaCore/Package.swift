// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VelaCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "VelaCore", targets: ["VelaCore"]),
    ],
    targets: [
        .target(name: "VelaCore", resources: [.process("Resources")]),
        // `swift run vela-probe pizza` asks Google live and prints what the parser saw.
        .executableTarget(name: "vela-probe", dependencies: ["VelaCore"]),
        .executableTarget(name: "vela-bench", dependencies: ["VelaCore"]),
        .testTarget(name: "VelaCoreTests", dependencies: ["VelaCore"]),
    ]
)
