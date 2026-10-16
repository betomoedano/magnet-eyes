// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "MagnetEyesCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "MagnetEyesCore", targets: ["MagnetEyesCore"])],
    targets: [
        .target(name: "MagnetEyesCore"),
        .testTarget(name: "MagnetEyesCoreTests", dependencies: ["MagnetEyesCore"])
    ]
)
