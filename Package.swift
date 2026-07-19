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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.4")
    ],
    targets: [
        .executableTarget(
            name: "NotchCapture",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/NotchCapture",
            linkerSettings: [
                // The bundled app carries Sparkle in Contents/Frameworks; unsafeFlags
                // is acceptable because this leaf executable is never a dependency.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        .testTarget(
            name: "NotchCaptureTests",
            dependencies: ["NotchCapture"],
            path: "Tests/NotchCaptureTests"
        )
    ]
)
