// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CampusBar",
    platforms: [.macOS(.v14)],
    targets: [.executableTarget(name: "CampusBar", path: "Sources")]
)
