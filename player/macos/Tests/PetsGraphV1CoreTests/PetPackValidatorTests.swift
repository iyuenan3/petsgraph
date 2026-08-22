import Foundation
import XCTest

@testable import PetsGraphCore

final class PetPackValidatorTests: XCTestCase {
  func testLoadsPublicSyntheticPetPack() throws {
    let fixture = repositoryRoot()
      .appendingPathComponent("petpack/fixtures/synthetic-cat-v1.petpack")
    let destination = FileManager.default.temporaryDirectory
      .appendingPathComponent("petsgraph-swift-fixture-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: destination) }

    let result = try PetPackValidator().validateAndExtract(sourceURL: fixture, to: destination)

    XCTAssertEqual(result.report.packageID, "synthetic-cat-v1")
    XCTAssertEqual(result.report.contentVersion.stringValue, "1.0.0")
    XCTAssertEqual(result.report.entryCount, 12)
    XCTAssertEqual(result.report.clipCount, 4)
    XCTAssertEqual(result.report.nodeCount, 2)
    XCTAssertEqual(result.report.edgeCount, 2)
    XCTAssertEqual(
      result.report.archiveSHA256,
      "812f0459fe444ff4cf657908d3c9b235be21f591d796ac7d0f02e50f564ac2c1")
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: result.package.mediaURL(for: "rest-primary-loop")!.path))
  }

  func testNativeLoaderRejectsTrailingArchivePayload() throws {
    let source = repositoryRoot().appendingPathComponent(
      "petpack/fixtures/synthetic-cat-v1.petpack")
    let mutated = FileManager.default.temporaryDirectory
      .appendingPathComponent("petsgraph-trailing-\(UUID().uuidString).petpack")
    let destination = FileManager.default.temporaryDirectory
      .appendingPathComponent("petsgraph-trailing-out-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.copyItem(at: source, to: mutated)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
    defer {
      try? FileManager.default.removeItem(at: mutated)
      try? FileManager.default.removeItem(at: destination)
    }
    let handle = try FileHandle(forWritingTo: mutated)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data([0]))
    try handle.close()

    XCTAssertThrowsError(
      try PetPackValidator().validateAndExtract(sourceURL: mutated, to: destination)
    ) { error in
      XCTAssertEqual((error as? PetPackError)?.code, "invalid_container")
    }
  }

  func testSemanticVersionOrdering() throws {
    XCTAssertLessThan(
      try XCTUnwrap(SemanticVersion("1.0.0-alpha.1")), try XCTUnwrap(SemanticVersion("1.0.0")))
    XCTAssertLessThan(
      try XCTUnwrap(SemanticVersion("1.0.0")), try XCTUnwrap(SemanticVersion("1.0.1")))
    XCTAssertNil(SemanticVersion("1.0.0+\(String(repeating: "a", count: 81))"))
  }

  func testPlayerStateUsesOneBoundedGlobalScale() {
    XCTAssertEqual(PlayerState(globalScale: 0.5).globalScale, 0.5)
    XCTAssertEqual(PlayerState(globalScale: 2).globalScale, 2)
    XCTAssertEqual(PlayerState(globalScale: 1.1).globalScale, 1)
  }

  func testCanonicalLibraryImportsIdempotentlyAndOwnsItsCopy() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("petsgraph-library-\(UUID().uuidString)", isDirectory: true)
    let external = FileManager.default.temporaryDirectory
      .appendingPathComponent("petsgraph-external-\(UUID().uuidString).petpack")
    try FileManager.default.copyItem(
      at: repositoryRoot().appendingPathComponent("petpack/fixtures/synthetic-cat-v1.petpack"),
      to: external
    )
    defer {
      try? FileManager.default.removeItem(at: root)
      try? FileManager.default.removeItem(at: external)
    }
    let library = try CanonicalPetLibrary(rootURL: root)

    let first = try library.importPetPack(from: external) { _, _ in
      XCTFail("a first install must not request update confirmation")
      return false
    }
    guard case .installed(let installed) = first else {
      return XCTFail("expected a new install")
    }
    XCTAssertEqual(installed.packageID, "synthetic-cat-v1")

    try FileManager.default.removeItem(at: external)
    XCTAssertEqual(
      try library.loadInstalledPetPacks().map { $0.manifest.package.id }, ["synthetic-cat-v1"])

    let fixture = repositoryRoot().appendingPathComponent(
      "petpack/fixtures/synthetic-cat-v1.petpack")
    let second = try library.importPetPack(from: fixture) { _, _ in
      XCTFail("an idempotent install must not request update confirmation")
      return false
    }
    XCTAssertEqual(second, .alreadyInstalled(installed))

    XCTAssertEqual(try library.uninstall(packageID: installed.packageID), installed)
    XCTAssertTrue(try library.installedPets().isEmpty)
    XCTAssertTrue(try library.loadInstalledPetPacks().isEmpty)
  }

  func testCanonicalLibraryRebuildsDeletedCacheFromCanonicalArchive() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("petsgraph-cache-rebuild-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = try CanonicalPetLibrary(rootURL: root)
    let fixture = repositoryRoot().appendingPathComponent(
      "petpack/fixtures/synthetic-cat-v1.petpack")
    _ = try library.importPetPack(from: fixture) { _, _ in false }
    try FileManager.default.removeItem(at: root.appendingPathComponent("Cache"))
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent("Cache"), withIntermediateDirectories: false)

    let packages = try library.loadInstalledPetPacks()

    XCTAssertEqual(packages.count, 1)
    XCTAssertNotNil(packages[0].mediaURL(for: "rest-secondary-loop"))
  }

  func testCanonicalLibraryRejectsUnsafeRegistryIdentity() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("petsgraph-unsafe-registry-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = try CanonicalPetLibrary(rootURL: root)
    let registry = """
      {
        "formatVersion": 1,
        "packages": [
          {
            "packageID": "../../outside",
            "petID": "../../outside",
            "displayName": "Unsafe",
            "species": "cat",
            "contentVersion": "1.0.0",
            "archiveSHA256": "0000000000000000000000000000000000000000000000000000000000000000",
            "archiveBytes": 1
          }
        ]
      }
      """
    try Data(registry.utf8).write(to: root.appendingPathComponent("registry.json"))

    XCTAssertThrowsError(try library.installedPets()) { error in
      XCTAssertEqual((error as? PetPackError)?.code, "registry_corrupt")
    }
  }

  func testPassiveBehaviorUsesACompleteDirectedTransition() throws {
    try withSyntheticPackage { package in
      let session = try PassiveBehaviorSession(package: package, startedAt: 0, seed: 7)
      let initial = try session.update(at: 0)
      XCTAssertEqual(initial.clipID, "rest-primary-loop")

      _ = try session.update(at: 1_000)
      let arrived = try session.update(at: 1_001)

      XCTAssertEqual(arrived.currentNodeID, "rest.secondary")
      XCTAssertEqual(arrived.clipID, "rest-secondary-loop")
      XCTAssertFalse(arrived.isTransition)
    }
  }

  func testHiddenTransitionFinishesAtStableNodeThenPauses() throws {
    try withSyntheticPackage { package in
      let session = try PassiveBehaviorSession(package: package, startedAt: 0, seed: 9)
      _ = try session.update(at: 1_000)
      var now = 1_000.0
      while !session.isTransitioning, now < 1_001 {
        now += 0.01
        _ = try session.update(at: now)
      }
      XCTAssertTrue(session.isTransitioning)

      try session.setVisible(false, at: now)
      XCTAssertTrue(session.shouldTickWhenHidden)
      let hidden = try session.update(at: now + 1)

      XCTAssertTrue(session.isPaused)
      XCTAssertFalse(session.shouldTickWhenHidden)
      XCTAssertFalse(hidden.isTransition)
      try session.setVisible(true, at: now + 2)
      XCTAssertFalse(session.isPaused)
    }
  }

  private func repositoryRoot() -> URL {
    var result = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    for _ in 0..<4 { result.deleteLastPathComponent() }
    return result
  }

  private func withSyntheticPackage(_ body: (LoadedPetPack) throws -> Void) throws {
    let destination = FileManager.default.temporaryDirectory
      .appendingPathComponent("petsgraph-session-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: destination) }
    let fixture = repositoryRoot().appendingPathComponent(
      "petpack/fixtures/synthetic-cat-v1.petpack")
    let package = try PetPackValidator().validateAndExtract(
      sourceURL: fixture,
      to: destination
    ).package
    try body(package)
  }
}
