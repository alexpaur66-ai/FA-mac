// swift-tools-version: 6.0
// FA-mac Swift package: the pure-Swift core and the SQLite data layer.
// The macOS app in App/FA.xcodeproj depends on this package as a local package.
import PackageDescription

var products: [Product] = [
    .library(name: "InvoicingCore", targets: ["InvoicingCore"]),
]
var dependencies: [Package.Dependency] = []
var targets: [Target] = [
    .target(name: "InvoicingCore", path: "Sources/InvoicingCore"),
    .testTarget(name: "InvoicingCoreTests", dependencies: ["InvoicingCore"], path: "Tests/InvoicingCoreTests"),
]

// The data layer needs GRDB and SQLite; it is built on Apple platforms only.
// The core deliberately has no dependencies, so it also compiles and tests on Linux (used by CI).
#if !os(Linux)
dependencies.append(.package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"))
products.append(.library(name: "InvoicingData", targets: ["InvoicingData"]))
targets += [
    .target(
        name: "InvoicingData",
        dependencies: ["InvoicingCore", .product(name: "GRDB", package: "GRDB.swift")],
        path: "Sources/InvoicingData"
    ),
    .testTarget(name: "InvoicingDataTests", dependencies: ["InvoicingData"], path: "Tests/InvoicingDataTests"),
]
#endif

let package = Package(
    name: "FA",
    platforms: [.macOS(.v14)],
    products: products,
    dependencies: dependencies,
    targets: targets,
    swiftLanguageModes: [.v6]
)
