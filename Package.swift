// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "IotaMonitor",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "IotaMonitorCore",
            path: "Sources/IotaMonitorCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "IotaMonitor",
            dependencies: ["IotaMonitorCore"],
            path: "Sources/IotaMonitor"
        ),
        // 本机只有 CLT（无 XCTest），用独立执行器跑断言：swift run SelfTest
        .executableTarget(
            name: "SelfTest",
            dependencies: ["IotaMonitorCore"],
            path: "Sources/SelfTest"
        )
    ]
)
