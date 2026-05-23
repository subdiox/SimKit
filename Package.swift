// swift-tools-version: 6.0
import PackageDescription

// SimulatorKit + CoreSimulator are deliberately NOT linked here. Nothing in Sources/
// does `import SimulatorKit` / `import CoreSimulator`. They are loaded via dlopen at
// runtime (see CoreSimulatorRuntime.swift). Linking them at build time would bake
// LC_LOAD_DYLIB entries that dyld must resolve before main(), which fails for users
// whose Xcode lives outside `/Applications/Xcode.app`.
let package = Package(
    name: "SimulatorView",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SimulatorView", targets: ["SimulatorView"])
    ],
    targets: [
        .target(
            name: "SimulatorView",
            path: "Sources/SimulatorView"
        ),
        .testTarget(
            name: "SimulatorViewTests",
            dependencies: ["SimulatorView"],
            path: "Tests/SimulatorViewTests"
        )
    ]
)
