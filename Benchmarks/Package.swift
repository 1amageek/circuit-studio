// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "CircuitStudioBenchmarks",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "circuit-studio-benchmarks", targets: ["CircuitStudioBenchmarks"])
    ],
    dependencies: [
        .package(path: "..")
    ],
    targets: [
        .target(
            name: "CircuitStudioBenchmarkSupport",
            dependencies: [
                .product(name: "CircuitStudioCore", package: "circuit-studio"),
                .product(name: "WaveformViewer", package: "circuit-studio"),
            ],
            path: "CircuitStudioBenchmarkSupport"
        ),
        .executableTarget(
            name: "CircuitStudioBenchmarks",
            dependencies: [
                "CircuitStudioBenchmarkSupport"
            ],
            path: "CircuitStudioBenchmarks"
        ),
    ]
)
