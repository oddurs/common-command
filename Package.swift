// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CommonCommand",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CommandKit"),
        .executableTarget(
            name: "CommonCommand",
            dependencies: ["CommandKit"],
            linkerSettings: [
                .linkedFramework("Carbon"), .linkedFramework("IOKit"), .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(name: "CommandKitTests", dependencies: ["CommandKit"]),
    ]
)
