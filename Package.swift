// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "petsgraph",
  platforms: [
    .macOS(.v13),
  ],
  products: [
    .library(name: "PetsGraphCore", targets: ["PetsGraphCore"]),
    .executable(name: "petsgraph", targets: ["PetsGraphApp"]),
  ],
  targets: [
    .target(name: "PetsGraphCore"),
    .executableTarget(
      name: "PetsGraphApp",
      dependencies: ["PetsGraphCore"]
    ),
    .testTarget(
      name: "PetsGraphCoreTests",
      dependencies: ["PetsGraphCore"]
    ),
  ]
)
