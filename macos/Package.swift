// swift-tools-version: 5.9
import PackageDescription

// The product is a bare executable. scripts/make-app.sh wraps it in an
// LSUIElement .app bundle and embeds the x86_64 Node runtime.
let package = Package(
    name: "Switchboard",
    platforms: [.macOS(.v10_15)],
    products: [
        .executable(name: "Switchboard", targets: ["Switchboard"]),
    ],
    targets: [
        .executableTarget(
            name: "Switchboard",
            path: "Sources/Switchboard"
        ),
        .testTarget(
            name: "SwitchboardTests",
            dependencies: ["Switchboard"],
            path: "Tests/SwitchboardTests"
        ),
    ]
)
