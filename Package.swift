// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SchematicModeler",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SchematicModeler",
            path: "Sources/SchematicModeler",
            resources: [
                .copy("Resources/AppIcon.png")
            ]
        )
    ]
)
