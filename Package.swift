// swift-tools-version: 6.3
import PackageDescription

// SimulatorKit + CoreSimulator are deliberately NOT linked here. Nothing in Sources/
// does `import SimulatorKit` / `import CoreSimulator`. They are loaded via dlopen at
// runtime (see CoreSimulatorRuntime.swift). Linking them at build time would bake
// LC_LOAD_DYLIB entries that dyld must resolve before main(), which fails for users
// whose Xcode lives outside `/Applications/Xcode.app`.
let package = Package(
  name: "SimKit",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "SimKit", targets: ["SimKit"])
  ],
  targets: [
    .target(
      name: "SimKit",
      path: "Sources/SimKit",
      swiftSettings: [
        .swiftLanguageMode(.v6),
        // Approachable Concurrency — enables `@concurrent` and nonisolated-nonsending
        // semantics so I/O methods can opt into the cooperative pool explicitly.
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
        .enableUpcomingFeature("InferIsolatedConformances"),
      ]
    )
  ]
)
