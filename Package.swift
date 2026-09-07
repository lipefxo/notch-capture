// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotchCapture",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .executable(name: "NotchCapture", targets: ["NotchCapture"]),
        .library(name: "NotchCaptureSync", targets: ["NotchCaptureSync"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.4")
    ],
    targets: [
        .target(
            name: "NotchCaptureSync",
            path: "Sources/NotchCaptureSync"
        ),
        .executableTarget(
            name: "NotchCapture",
            dependencies: [
                "NotchCaptureSync",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/NotchCapture",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                // The bundled app carries Sparkle in Contents/Frameworks; unsafeFlags
                // is acceptable because this leaf executable is never a dependency.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        .testTarget(
            name: "NotchCaptureTests",
            dependencies: ["NotchCapture"],
            path: "Tests/NotchCaptureTests",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "NotchCaptureSyncTests",
            dependencies: ["NotchCaptureSync"],
            path: "Tests/NotchCaptureSyncTests"
        )
    ]
)
