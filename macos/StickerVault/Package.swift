// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StickerVault",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "StickerVault", targets: ["StickerVault"]),
    ],
    targets: [
        .executableTarget(
            name: "StickerVault",
            path: "Sources"
        ),
    ]
)
