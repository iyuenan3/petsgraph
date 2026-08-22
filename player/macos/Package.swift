// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "PetsGraph",
  platforms: [
    .macOS(.v14),
  ],
  products: [
    .library(name: "PetsGraphCore", targets: ["PetsGraphCore"]),
    .executable(name: "petsgraph", targets: ["PetsGraphApp"]),
  ],
  targets: [
    .target(
      name: "PetsGraphCore",
      path: "Sources/PetsGraphV1Core",
      linkerSettings: [.linkedLibrary("z")]
    ),
    .executableTarget(
      name: "PetsGraphApp",
      dependencies: ["PetsGraphCore"],
      path: "Sources/PetsGraphV1App"
    ),
    .testTarget(
      name: "PetsGraphCoreTests",
      dependencies: ["PetsGraphCore"],
      path: "Tests/PetsGraphV1CoreTests"
    ),
  ]
)
