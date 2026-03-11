// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MusicReelsGenerator",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "MusicReelsGenerator",
            targets: ["MusicReelsGenerator"]
        )
    ],
    targets: [
        .executableTarget(
            name: "MusicReelsGenerator",
            path: "MusicReelsGenerator",
            exclude: ["Resources/Info.plist", "Resources/MusicReelsGenerator.entitlements"]
        )
    ]
)
