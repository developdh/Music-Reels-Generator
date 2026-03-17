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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "MusicReelsGenerator",
            dependencies: ["Sparkle"],
            path: "MusicReelsGenerator",
            exclude: ["Resources/Info.plist", "Resources/MusicReelsGenerator.entitlements"]
        )
    ]
)
