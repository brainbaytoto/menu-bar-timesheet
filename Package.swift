// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TimesheetTracker",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "TimesheetTrackerCore",
            path: "Sources/TimesheetTrackerCore"
        ),
        .executableTarget(
            name: "TimesheetTracker",
            dependencies: ["TimesheetTrackerCore"],
            path: "Sources/TimesheetTracker"
        ),
        .testTarget(
            name: "TimesheetTrackerCoreTests",
            dependencies: ["TimesheetTrackerCore"],
            path: "Tests/TimesheetTrackerCoreTests"
        ),
    ]
)
