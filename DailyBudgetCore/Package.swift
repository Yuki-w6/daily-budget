// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DailyBudgetCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v14)
    ],
    products: [
        .library(name: "DailyBudgetCore", targets: ["DailyBudgetCore"])
    ],
    targets: [
        .target(name: "DailyBudgetCore"),
        .testTarget(name: "DailyBudgetCoreTests", dependencies: ["DailyBudgetCore"])
    ]
)
