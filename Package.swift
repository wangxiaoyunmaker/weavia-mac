// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MouseCompanion",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MouseCompanion", targets: ["MouseCompanion"])
    ],
    targets: [
        .executableTarget(
            name: "MouseCompanion",
            path: "Sources/MouseCompanion",
            resources: [.copy("BrowserCapture.js"), .copy("DesignSkills"), .copy("CuppaCanvas")]
        )
    ]
)
