// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AIFare",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "AIFare", targets: ["AIFare"])],
    targets: [.executableTarget(name: "AIFare")]
)
