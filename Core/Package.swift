// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WilderCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "WilderCore", targets: ["WilderCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/microsoft/onnxruntime-swift-package-manager", from: "1.19.2"),
    ],
    targets: [
        .target(
            name: "WilderCore",
            dependencies: [.product(name: "onnxruntime", package: "onnxruntime-swift-package-manager")]
        ),
        .executableTarget(name: "wilder-cli", dependencies: ["WilderCore"]),
    ]
)
