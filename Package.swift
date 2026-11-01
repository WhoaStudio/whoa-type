// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WhoaTypeCore",
    platforms: [.macOS("26.5")],
    products: [.library(name: "WhoaTypeCore", targets: ["WhoaTypeCore"])],
    targets: [
        .target(name: "WhoaTypeCore", path: "whoa-type",
            exclude: ["AppShell", "Assets.xcassets", "Permissions", "Resources", "Settings/LoginItemService.swift", "App/AppCoordinator.swift", "whoa_typeApp.swift"],
            sources: ["App/AppState.swift", "Settings/SettingsStore.swift", "Input/KeyboardGeometry.swift", "SoundPacks", "Audio", "Input/KeyMapper.swift", "Input/KeyCaptureService.swift", "Input/PointerMapper.swift"]),
        .testTarget(name: "WhoaTypeCoreTests", dependencies: ["WhoaTypeCore"], path: "Tests/WhoaTypeCoreTests")
    ]
)
