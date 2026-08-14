// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "CasperFlow",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "CasperFlow", targets: ["CasperFlow"]),
  ],
  targets: [
    .executableTarget(
      name: "CasperFlow",
      path: "Sources/CasperFlow",
      linkerSettings: [
        .linkedFramework("ScreenCaptureKit"),
      ]
    ),
  ]
)
