// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "swift-bigint-gmp",
    platforms: [
        // StaticBigInt (for arbitrary-size integer literals) needs these or later.
        .macOS(.v14), .iOS(.v17), .tvOS(.v17), .watchOS(.v10), .visionOS(.v1),
    ],
    products: [
        .library(name: "GMPBigInt", targets: ["GMPBigInt"]),
    ],
    targets: [
        // GNU MP itself.  Found via pkg-config: point PKG_CONFIG_PATH at your
        // gmp.pc if it lives off the beaten path (MacPorts:
        // /opt/local/lib/pkgconfig; Homebrew and apt work out of the box).
        .systemLibrary(
            name: "Cgmp",
            pkgConfig: "gmp",
            providers: [
                .brew(["gmp"]),
                .apt(["libgmp-dev"]),
            ]
        ),
        .target(name: "GMPBigInt", dependencies: ["Cgmp"]),
        .testTarget(name: "GMPBigIntTests", dependencies: ["GMPBigInt"]),
    ]
)
