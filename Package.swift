// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Camera",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "CameraApp", path: "Sources/CameraApp")
    ]
)
