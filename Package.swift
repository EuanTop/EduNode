// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "EduNodeBackend",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "EduNodeContracts", targets: ["EduNodeContracts"]),
        .executable(name: "EduNodeServer", targets: ["EduNodeServer"])
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.0.0")
    ],
    targets: [
        .target(
            name: "EduNodeContracts",
            path: "EduNode/Shared/BackendContracts"
        ),
        .target(
            name: "EduNodeBackendCore",
            dependencies: ["EduNodeContracts"],
            path: "Server/Sources/EduNodeBackendCore"
        ),
        .executableTarget(
            name: "EduNodeServer",
            dependencies: [
                "EduNodeBackendCore",
                .product(name: "Vapor", package: "vapor")
            ],
            path: "Server/Sources/EduNodeServer"
        )
    ]
)
