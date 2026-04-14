// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "MyWorkingHours",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "MyWorkingHours",
            targets: ["MyWorkingHoursApp"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "MyWorkingHoursApp",
            path: "Sources/MyWorkingHoursApp"
        ),
        .testTarget(
            name: "MyWorkingHoursAppTests",
            dependencies: ["MyWorkingHoursApp"],
            path: "Tests/MyWorkingHoursAppTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
