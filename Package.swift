// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "BLEHTTPServer",
    platforms: [
        .macOS(.v12)
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.121.0"),
    ],
    targets: [
        .target(
            name: "BLEHTTPServer",
            dependencies: [
                .product(name: "Vapor", package: "vapor")
            ]
        ),
        .executableTarget(
            name: "Run",
            dependencies: ["BLEHTTPServer"]
        )
    ]
)
