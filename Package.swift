// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacAlarm",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "MacAlarm", path: "Sources/MacAlarm")
    ]
)
