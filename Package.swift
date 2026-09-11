// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OpenBend",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "OpenBend",
            path: "Sources/OpenBend",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("IOKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
