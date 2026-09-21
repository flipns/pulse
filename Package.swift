// swift-tools-version: 6.2
// Pulse — app de referencia del libro. Cada listado del libro vive aquí con el comentario
// `// Libro: cap. N, §X`. Las variantes con bug se compilan con `-DPULSE_BUG` (ver scripts/tag-cases.sh).
import PackageDescription

let concurrencia: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .defaultIsolation(MainActor.self),                              // Default Actor Isolation = MainActor
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),      // Approachable Concurrency (SE-0461)
    .enableUpcomingFeature("InferIsolatedConformances"),
    .unsafeFlags(["-Xfrontend", "-warn-long-expression-type-checking=100"], .when(configuration: .debug)), // cap. 8 §8.7
    // PULSE_BUG_FLAG  ← scripts/tag-cases.sh sustituye esta línea por .define("PULSE_BUG") en las etiquetas capN-bug
]

let package = Package(
    name: "Pulse",
    platforms: [.iOS(.v18), .macOS(.v26)],   // macOS 26: los tests usan Observations (cap. 10, §10.3)
    products: [
        .library(name: "PulseCore", targets: ["PulseCore"]),
        .library(name: "PulseFeed", targets: ["PulseFeed"]),
        .library(name: "PulseSearch", targets: ["PulseSearch"]),
        .library(name: "PulseProduct", targets: ["PulseProduct"]),
        .library(name: "PulseCart", targets: ["PulseCart"]),
        .library(name: "PulseCheckout", targets: ["PulseCheckout"]),
        .library(name: "PulseLegacy", targets: ["PulseLegacy"]),
        .library(name: "PulseDebug", targets: ["PulseDebug"]),
    ],
    dependencies: [
        // Versiones EXACTAS, no rangos (H12). Son las que resolvieron y compilaron en la
        // verificación con Xcode 27 (docs/evidencia/build5.log). Un repositorio que acompaña a
        // un libro tiene que compilar igual dentro de un año: con `from:`, cualquier versión
        // nueva de una dependencia —incluida una publicada rota— entra sin que toquemos nada.
        // Package.resolved también está en el repositorio, por la misma razón.
        .package(url: "https://github.com/apple/swift-async-algorithms", exact: "1.1.5"),
        .package(url: "https://github.com/nalexn/ViewInspector", exact: "0.10.3"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", exact: "1.19.5"),
    ],
    targets: [
        .target(name: "PulseCore", swiftSettings: concurrencia),
        .target(name: "PulseFeed", dependencies: ["PulseCore"], swiftSettings: concurrencia),
        .target(name: "PulseSearch",
                dependencies: ["PulseCore", .product(name: "AsyncAlgorithms", package: "swift-async-algorithms")],
                swiftSettings: concurrencia),
        .target(name: "PulseProduct", dependencies: ["PulseCore", "PulseCart"], swiftSettings: concurrencia),
        .target(name: "PulseCart", dependencies: ["PulseCore"], swiftSettings: concurrencia),
        .target(name: "PulseCheckout", dependencies: ["PulseCore", "PulseCart"], swiftSettings: concurrencia),
        .target(name: "PulseLegacy", dependencies: ["PulseCore"], swiftSettings: concurrencia),
        .target(name: "PulseDebug",
                dependencies: ["PulseCore", "PulseFeed", "PulseSearch", "PulseCheckout"],
                swiftSettings: concurrencia),

        .testTarget(name: "PulseCheckoutTests",
                    dependencies: ["PulseCheckout", "PulseCore",
                                   .product(name: "ViewInspector", package: "ViewInspector"),
                                   .product(name: "SnapshotTesting", package: "swift-snapshot-testing")],
                    swiftSettings: concurrencia),
        .testTarget(name: "PulseSearchTests",
                    dependencies: ["PulseSearch", "PulseCore",
                                   .product(name: "ViewInspector", package: "ViewInspector")],   // V9
                    swiftSettings: concurrencia),
        .testTarget(name: "PulseFeedTests",
                    dependencies: ["PulseFeed", "PulseCore",
                                   .product(name: "ViewInspector", package: "ViewInspector")],   // V2
                    swiftSettings: concurrencia),
    ]
)
