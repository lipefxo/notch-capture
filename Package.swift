// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotchCapture",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "NotchCapture", targets: ["NotchCapture"])
    ],
    targets: [
        .executableTarget(
            name: "NotchCapture",
            path: "Sources/NotchCapture"
        ),
        .testTarget(
            name: "NotchCaptureTests",
            dependencies: ["NotchCapture"],
            path: "Tests/NotchCaptureTests"
        )
    ]
)
