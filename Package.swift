// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VertCam",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "VertCam", path: "Sources/VertCam")
    ]
)
