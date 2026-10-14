// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "InfiniteCalendar",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "InfiniteCalendar", targets: ["InfiniteCalendar"])],
    targets: [
        .target(name: "CalendarCore"),
        .executableTarget(name: "InfiniteCalendar", dependencies: ["CalendarCore"]),
        .testTarget(name: "CalendarCoreTests", dependencies: ["CalendarCore"])
    ]
)
