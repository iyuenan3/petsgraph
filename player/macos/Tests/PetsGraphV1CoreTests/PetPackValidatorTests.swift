import CoreGraphics
import Foundation
import XCTest

@testable import PetsGraphCore

final class PetPackValidatorTests: XCTestCase {
  func testPlayerAboutInfoFormatsBundleVersionAndSafeFallbacks() {
    XCTAssertEqual(
      PlayerAboutInfo(
        infoDictionary: [
          "CFBundleShortVersionString": "0.7.0-review",
          "CFBundleVersion": "18",
        ]
      ).versionLine,
      "版本 0.7.0-review（构建 18）"
    )
    XCTAssertEqual(
      PlayerAboutInfo(infoDictionary: ["CFBundleShortVersionString": " 1.0.0 "]).versionLine,
      "版本 1.0.0"
    )
    XCTAssertEqual(PlayerAboutInfo(infoDictionary: nil).versionLine, "开发版本")
  }

  func testRuntimeFrameCacheRetainsLoopsButOnlyLatestTransitionFrame() {
    var loop = RuntimeFrameCache<String>(retainsAllFrames: true)
    loop.insert("zero", for: 0)
    loop.insert("one", for: 1)
    loop.insert("two", for: 2)
    XCTAssertEqual(loop.retainedFrameIndices, [0, 1, 2])
    XCTAssertEqual(loop.value(for: 0), "zero")

    var transition = RuntimeFrameCache<String>(retainsAllFrames: false)
    transition.insert("zero", for: 0)
    transition.insert("one", for: 1)
    transition.insert("two", for: 2)
    XCTAssertEqual(transition.retainedFrameIndices, [2])
    XCTAssertNil(transition.value(for: 0))
    XCTAssertEqual(transition.value(for: 2), "two")
  }

  func testSharedRenderCadenceUsesFastestActivePetWithoutChangingFrameRate() {
    XCTAssertNil(SharedRenderCadence.interval(for: []))
    XCTAssertEqual(SharedRenderCadence.interval(for: [1.0 / 12.0]), 1.0 / 12.0)
    XCTAssertEqual(
      SharedRenderCadence.interval(for: [1.0 / 12.0, 1.0 / 24.0]),
      1.0 / 24.0
    )
  }

  func testPetPointerHitTestMapsScreenCoordinatesToTopOriginCanvasPixels() throws {
    let panel = CGRect(x: 100, y: 200, width: 400, height: 200)

    let bottomLeft = try XCTUnwrap(
      PetPointerHitTest.canvasPixel(
        at: CGPoint(x: 100, y: 200),
        panelFrame: panel,
        canvasWidth: 800,
        canvasHeight: 400
      ))
    XCTAssertEqual(bottomLeft.x, 0)
    XCTAssertEqual(bottomLeft.y, 399)

    let center = try XCTUnwrap(
      PetPointerHitTest.canvasPixel(
        at: CGPoint(x: 300, y: 300),
        panelFrame: panel,
        canvasWidth: 800,
        canvasHeight: 400
      ))
    XCTAssertEqual(center.x, 400)
    XCTAssertEqual(center.y, 200)

    let topRight = try XCTUnwrap(
      PetPointerHitTest.canvasPixel(
        at: CGPoint(x: 499.999, y: 399.999),
        panelFrame: panel,
        canvasWidth: 800,
        canvasHeight: 400
      ))
    XCTAssertEqual(topRight.x, 799)
    XCTAssertEqual(topRight.y, 0)

    XCTAssertNil(
      PetPointerHitTest.canvasPixel(
        at: CGPoint(x: 500, y: 300),
        panelFrame: panel,
        canvasWidth: 800,
        canvasHeight: 400
      ))
  }

  func testPetPointerHitTestPassesTransparentPixelsAndCapturesVisiblePixels() {
    XCTAssertTrue(PetPointerHitTest.ignoresMouseEvents(alpha: 0))
    XCTAssertTrue(PetPointerHitTest.ignoresMouseEvents(alpha: 0.05))
    XCTAssertFalse(PetPointerHitTest.ignoresMouseEvents(alpha: 0.050_001))
    XCTAssertFalse(PetPointerHitTest.ignoresMouseEvents(alpha: 1))
    XCTAssertTrue(PetPointerHitTest.ignoresMouseEvents(alpha: .nan))
  }

  func testPetWindowPlacementAlignsVisibleContentToEveryScreenEdge() {
    let cases: [(screen: CGRect, panel: CGSize, canvasHeight: CGFloat, content: CGRect)] = [
      (
        CGRect(x: 0, y: 0, width: 1_728, height: 1_117),
        CGSize(width: 530.5, height: 181.125),
        224,
        CGRect(x: 226, y: 103, width: 206, height: 75)
      ),
      (
        CGRect(x: -1_440, y: 80, width: 1_440, height: 900),
        CGSize(width: 225, height: 172.5),
        368,
        CGRect(x: 106, y: 192, width: 265, height: 121)
      ),
    ]

    for item in cases {
      let center = CGPoint(x: item.screen.midX, y: item.screen.midY)
      let left = PetWindowPlacement.clampedAnchor(
        CGPoint(x: -10_000, y: center.y),
        panelSize: item.panel,
        canvasHeight: item.canvasHeight,
        contentBounds: item.content,
        screenFrame: item.screen
      )
      let right = PetWindowPlacement.clampedAnchor(
        CGPoint(x: 10_000, y: center.y),
        panelSize: item.panel,
        canvasHeight: item.canvasHeight,
        contentBounds: item.content,
        screenFrame: item.screen
      )
      let bottom = PetWindowPlacement.clampedAnchor(
        CGPoint(x: center.x, y: -10_000),
        panelSize: item.panel,
        canvasHeight: item.canvasHeight,
        contentBounds: item.content,
        screenFrame: item.screen
      )
      let top = PetWindowPlacement.clampedAnchor(
        CGPoint(x: center.x, y: 10_000),
        panelSize: item.panel,
        canvasHeight: item.canvasHeight,
        contentBounds: item.content,
        screenFrame: item.screen
      )

      XCTAssertEqual(
        visibleContentFrame(
          anchor: left,
          panel: item.panel,
          canvasHeight: item.canvasHeight,
          content: item.content
        ).minX,
        item.screen.minX,
        accuracy: 0.000_001
      )
      XCTAssertEqual(
        visibleContentFrame(
          anchor: right,
          panel: item.panel,
          canvasHeight: item.canvasHeight,
          content: item.content
        ).maxX,
        item.screen.maxX,
        accuracy: 0.000_001
      )
      XCTAssertEqual(
        visibleContentFrame(
          anchor: bottom,
          panel: item.panel,
          canvasHeight: item.canvasHeight,
          content: item.content
        ).minY,
        item.screen.minY,
        accuracy: 0.000_001
      )
      XCTAssertEqual(
        visibleContentFrame(
          anchor: top,
          panel: item.panel,
          canvasHeight: item.canvasHeight,
          content: item.content
        ).maxY,
        item.screen.maxY,
        accuracy: 0.000_001
      )
    }
  }

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

  func testLoadsForwardCompatibleSyntheticPetPack() throws {
    let fixture = repositoryRoot()
      .appendingPathComponent("petpack/fixtures/synthetic-cat-forward-v1.petpack")
    let destination = FileManager.default.temporaryDirectory
      .appendingPathComponent("petsgraph-swift-forward-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: destination) }

    let result = try PetPackValidator().validateAndExtract(sourceURL: fixture, to: destination)

    XCTAssertEqual(result.report.packageID, "synthetic-cat-forward-v1")
    XCTAssertEqual(result.package.manifest.capabilities.optional, ["future-audio"])
    XCTAssertTrue(result.package.behavior.nodeWeights.isEmpty)
    XCTAssertTrue(result.package.behavior.sceneWeights.isEmpty)
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
    XCTAssertEqual(
      try XCTUnwrap(SemanticVersion("1.0.0+one")),
      try XCTUnwrap(SemanticVersion("1.0.0+two")))
    XCTAssertNil(SemanticVersion("1.0.0-01"))
    XCTAssertNil(SemanticVersion("1.0.0-alpha..1"))
    XCTAssertNil(SemanticVersion("2147483648.0.0"))
    XCTAssertLessThan(
      try XCTUnwrap(SemanticVersion("1.0.0-999999999999999999999")),
      try XCTUnwrap(SemanticVersion("1.0.0-1000000000000000000000")))
  }

  func testPlayerStateUsesOneBoundedGlobalScale() {
    XCTAssertEqual(PlayerState(globalScale: 0.5).globalScale, 0.5)
    XCTAssertEqual(PlayerState(globalScale: 2).globalScale, 2)
    XCTAssertEqual(PlayerState(globalScale: 1.1).globalScale, 1)
  }

  func testPlayerScaleOptionsUseExactStableLabels() {
    XCTAssertEqual(
      PlayerState.scaleOptions,
      [
        PlayerScaleOption(value: 0.5, label: "0.5"),
        PlayerScaleOption(value: 0.75, label: "0.75"),
        PlayerScaleOption(value: 1.0, label: "1.0"),
        PlayerScaleOption(value: 1.25, label: "1.25"),
        PlayerScaleOption(value: 1.5, label: "1.5"),
        PlayerScaleOption(value: 1.75, label: "1.75"),
        PlayerScaleOption(value: 2.0, label: "2.0"),
      ])
    XCTAssertEqual(PlayerState.allowedScales, PlayerState.scaleOptions.map(\.value))
  }

  func testPlayerStateCapturesClampedRuntimePositionBeforeSaving() {
    var state = PlayerState(
      pets: [
        "wubai": PetPlayerState(visible: false, anchorX: -10_000, anchorY: 10_000)
      ]
    )

    state.captureRuntimePet(
      packageID: "wubai",
      visible: true,
      anchorX: 86.75,
      anchorY: -31.6875
    )

    XCTAssertEqual(
      state.pets["wubai"],
      PetPlayerState(visible: true, anchorX: 86.75, anchorY: -31.6875)
    )
  }

  func testLegacyMigrationKeepsOnlyPositionAndResetsVisibility() {
    let migrated = PlayerState.migratedLegacyPet(anchorX: 123, anchorY: 456)

    XCTAssertTrue(migrated.visible)
    XCTAssertEqual(migrated.anchorX, 123)
    XCTAssertEqual(migrated.anchorY, 456)
    XCTAssertNil(PlayerState.migratedLegacyPet(anchorX: .infinity, anchorY: .nan).anchorX)
    XCTAssertNil(PlayerState.migratedLegacyPet(anchorX: .infinity, anchorY: .nan).anchorY)
  }

  func testCorruptSettingsFailSafeHidesEveryInstalledPet() {
    let state = PlayerState.hiddenFailSafe(packageIDs: ["wubai", "feiliu"])

    XCTAssertEqual(state.pets.keys.sorted(), ["feiliu", "wubai"])
    XCTAssertTrue(state.pets.values.allSatisfy { !$0.visible })
  }

  func testStateStoreFailsClosedWhenSettingsAreCorrupt() throws {
    try withSyntheticPackage { package in
      let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("petsgraph-settings-\(UUID().uuidString)", isDirectory: true)
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
      defer { try? FileManager.default.removeItem(at: root) }
      try Data("not json".utf8).write(to: root.appendingPathComponent("settings.json"))
      let defaults = UserDefaults(suiteName: "petsgraph-tests-\(UUID().uuidString)")!
      let store = PlayerStateStore(rootURL: root, defaults: defaults)

      let state = store.load(for: [package])

      XCTAssertNotNil(store.loadWarning)
      XCTAssertEqual(state.pets[package.manifest.package.id]?.visible, false)
    }
  }

  func testStateStoreRoundTripsTwoPetsAndPrunesUninstalledState() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("petsgraph-settings-\(UUID().uuidString)", isDirectory: true)
    let primaryRuntime = root.appendingPathComponent("primary", isDirectory: true)
    let secondaryRuntime = root.appendingPathComponent("secondary", isDirectory: true)
    try FileManager.default.createDirectory(at: primaryRuntime, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: secondaryRuntime, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = repositoryRoot()
    let validator = PetPackValidator()
    let primary = try validator.validateAndExtract(
      sourceURL: repository.appendingPathComponent("petpack/fixtures/synthetic-cat-v1.petpack"),
      to: primaryRuntime
    ).package
    let secondary = try validator.validateAndExtract(
      sourceURL: repository.appendingPathComponent(
        "petpack/fixtures/synthetic-cat-forward-v1.petpack"),
      to: secondaryRuntime
    ).package
    let suite = "petsgraph-tests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = PlayerStateStore(rootURL: root, defaults: defaults)
    let state = PlayerState(
      globalScale: 1.75,
      pets: [
        primary.manifest.package.id: PetPlayerState(
          visible: false, anchorX: 123.5, anchorY: 456.25),
        secondary.manifest.package.id: PetPlayerState(
          visible: true, anchorX: -80, anchorY: 900),
        "uninstalled-pet": PetPlayerState(visible: false, anchorX: 1, anchorY: 2),
      ]
    )

    try store.save(state)
    let restored = store.load(for: [primary, secondary])

    XCTAssertNil(store.loadWarning)
    XCTAssertEqual(restored.globalScale, 1.75)
    XCTAssertEqual(
      restored.pets,
      [
        primary.manifest.package.id: PetPlayerState(
          visible: false, anchorX: 123.5, anchorY: 456.25),
        secondary.manifest.package.id: PetPlayerState(
          visible: true, anchorX: -80, anchorY: 900),
      ]
    )
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
    try library.commitImport(first)
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

  func testCanonicalLibraryRollsBackFailedFirstInstall() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("petsgraph-import-rollback-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = try CanonicalPetLibrary(rootURL: root)
    let fixture = repositoryRoot().appendingPathComponent(
      "petpack/fixtures/synthetic-cat-v1.petpack")
    let outcome = try library.importPetPack(from: fixture) { _, _ in false }

    try library.rollbackImport(outcome)

    XCTAssertTrue(try library.installedPets().isEmpty)
    XCTAssertTrue(try library.loadInstalledPetPacks().isEmpty)
    XCTAssertTrue(
      (try FileManager.default.contentsOfDirectory(
        at: root.appendingPathComponent("Library"),
        includingPropertiesForKeys: nil
      )).isEmpty)
  }

  func testCanonicalLibraryRecoversInterruptedImportOnRestart() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("petsgraph-import-recovery-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = repositoryRoot().appendingPathComponent(
      "petpack/fixtures/synthetic-cat-v1.petpack")
    let interrupted = try CanonicalPetLibrary(rootURL: root)
    _ = try interrupted.importPetPack(from: fixture) { _, _ in false }

    let recovered = try CanonicalPetLibrary(rootURL: root)

    XCTAssertTrue(try recovered.installedPets().isEmpty)
    XCTAssertTrue(try recovered.loadInstalledPetPacks().isEmpty)
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: root.appendingPathComponent("pending-import.json").path))
  }

  func testCanonicalLibraryRollsBackFailedUpdateToPreviousVersion() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("petsgraph-update-rollback-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = try CanonicalPetLibrary(rootURL: root)
    let fixture = repositoryRoot().appendingPathComponent(
      "petpack/fixtures/synthetic-cat-v1.petpack")
    let initial = try library.importPetPack(from: fixture) { _, _ in false }
    guard case .installed(let previous) = initial else {
      return XCTFail("expected initial install")
    }
    try library.commitImport(initial)
    let current = InstalledPet(
      packageID: previous.packageID,
      petID: previous.petID,
      displayName: previous.displayName,
      species: previous.species,
      contentVersion: try XCTUnwrap(SemanticVersion("1.0.1")),
      archiveSHA256: previous.archiveSHA256,
      archiveBytes: previous.archiveBytes
    )
    let currentArchiveDirectory = root.appendingPathComponent(
      "Library/\(current.packageID)/\(current.contentVersion.stringValue)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: currentArchiveDirectory, withIntermediateDirectories: true)
    try FileManager.default.copyItem(
      at: fixture,
      to: currentArchiveDirectory.appendingPathComponent("\(current.archiveSHA256).petpack")
    )
    let previousRuntime = root.appendingPathComponent(
      "Cache/\(previous.packageID)/\(previous.contentVersion.stringValue)/\(previous.archiveSHA256)",
      isDirectory: true)
    let currentRuntime = root.appendingPathComponent(
      "Cache/\(current.packageID)/\(current.contentVersion.stringValue)/\(current.archiveSHA256)",
      isDirectory: true)
    try FileManager.default.createDirectory(
      at: currentRuntime.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: previousRuntime, to: currentRuntime)
    let registry = try JSONSerialization.data(
      withJSONObject: [
        "formatVersion": 1,
        "packages": [
          [
            "packageID": current.packageID,
            "petID": current.petID,
            "displayName": current.displayName,
            "species": current.species,
            "contentVersion": current.contentVersion.stringValue,
            "archiveSHA256": current.archiveSHA256,
            "archiveBytes": current.archiveBytes,
          ]
        ],
      ],
      options: [.prettyPrinted, .sortedKeys]
    )
    try registry.write(to: root.appendingPathComponent("registry.json"), options: [.atomic])

    try library.rollbackImport(.updated(previous: previous, current: current))

    XCTAssertEqual(try library.installedPets(), [previous])
    XCTAssertEqual(
      try XCTUnwrap(library.loadInstalledPetPacks().first).manifest.package.contentVersion,
      previous.contentVersion)
    XCTAssertFalse(FileManager.default.fileExists(atPath: currentArchiveDirectory.path))
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: currentRuntime.deletingLastPathComponent().path))
  }

  func testCanonicalLibraryRebuildsDeletedCacheFromCanonicalArchive() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("petsgraph-cache-rebuild-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = try CanonicalPetLibrary(rootURL: root)
    let fixture = repositoryRoot().appendingPathComponent(
      "petpack/fixtures/synthetic-cat-v1.petpack")
    let imported = try library.importPetPack(from: fixture) { _, _ in false }
    try library.commitImport(imported)
    try FileManager.default.removeItem(at: root.appendingPathComponent("Cache"))
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent("Cache"), withIntermediateDirectories: false)

    let packages = try library.loadInstalledPetPacks()

    XCTAssertEqual(packages.count, 1)
    XCTAssertNotNil(packages[0].mediaURL(for: "rest-secondary-loop"))
  }

  func testCanonicalLibraryRemovesUnjournaledUninstallTransaction() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "petsgraph-orphan-transaction-\(UUID().uuidString)", isDirectory: true)
    let orphan = root.appendingPathComponent("Staging/uninstall-orphan", isDirectory: true)
    try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    _ = try CanonicalPetLibrary(rootURL: root)

    XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
  }

  func testCanonicalLibraryRollsBackInterruptedUninstallBeforeRegistryCommit() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "petsgraph-uninstall-rollback-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = try CanonicalPetLibrary(rootURL: root)
    let fixture = repositoryRoot().appendingPathComponent(
      "petpack/fixtures/synthetic-cat-v1.petpack")
    let outcome = try library.importPetPack(from: fixture) { _, _ in false }
    try library.commitImport(outcome)
    let installed = try XCTUnwrap(try library.installedPets().first)
    let transaction = try stageInterruptedUninstall(
      root: root, installed: installed, registryKeepsPet: true)

    let recovered = try CanonicalPetLibrary(rootURL: root)

    XCTAssertEqual(try recovered.installedPets(), [installed])
    XCTAssertEqual(try recovered.loadInstalledPetPacks().count, 1)
    XCTAssertFalse(FileManager.default.fileExists(atPath: transaction.path))
  }

  func testCanonicalLibraryFinishesInterruptedUninstallAfterRegistryCommit() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "petsgraph-uninstall-commit-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = try CanonicalPetLibrary(rootURL: root)
    let fixture = repositoryRoot().appendingPathComponent(
      "petpack/fixtures/synthetic-cat-v1.petpack")
    let outcome = try library.importPetPack(from: fixture) { _, _ in false }
    try library.commitImport(outcome)
    let installed = try XCTUnwrap(try library.installedPets().first)
    let transaction = try stageInterruptedUninstall(
      root: root, installed: installed, registryKeepsPet: false)

    let recovered = try CanonicalPetLibrary(rootURL: root)

    XCTAssertTrue(try recovered.installedPets().isEmpty)
    XCTAssertTrue(try recovered.loadInstalledPetPacks().isEmpty)
    XCTAssertFalse(FileManager.default.fileExists(atPath: transaction.path))
  }

  func testCanonicalLibraryRebuildsSameLengthCorruptMediaCache() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("petsgraph-cache-corrupt-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = try CanonicalPetLibrary(rootURL: root)
    let fixture = repositoryRoot().appendingPathComponent(
      "petpack/fixtures/synthetic-cat-v1.petpack")
    let imported = try library.importPetPack(from: fixture) { _, _ in false }
    try library.commitImport(imported)
    let installed = try XCTUnwrap(try library.loadInstalledPetPacks().first)
    let media = try XCTUnwrap(installed.mediaURL(for: "rest-primary-loop"))
    let expected = try Data(contentsOf: media)
    var corrupt = expected
    corrupt[corrupt.startIndex] ^= 0xff
    try corrupt.write(to: media)

    let rebuilt = try XCTUnwrap(try library.loadInstalledPetPacks().first)

    XCTAssertEqual(
      try Data(contentsOf: XCTUnwrap(rebuilt.mediaURL(for: "rest-primary-loop"))), expected)
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

  func testImportRecoveryUsesExactVersionPathIdentity() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("petsgraph-import-identity-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    _ = try CanonicalPetLibrary(rootURL: root)
    func record(_ version: String) -> [String: Any] {
      [
        "packageID": "synthetic-cat-v1",
        "petID": "synthetic-cat-v1",
        "displayName": "Synthetic Cat",
        "species": "cat",
        "contentVersion": version,
        "archiveSHA256": String(repeating: "0", count: 64),
        "archiveBytes": 1,
      ]
    }
    try JSONSerialization.data(
      withJSONObject: ["formatVersion": 1, "packages": [record("1.0.0+two")]],
      options: [.sortedKeys]
    ).write(to: root.appendingPathComponent("registry.json"), options: [.atomic])
    try JSONSerialization.data(
      withJSONObject: [
        "formatVersion": 1,
        "current": record("1.0.0+one"),
        "previous": NSNull(),
      ],
      options: [.sortedKeys]
    ).write(to: root.appendingPathComponent("pending-import.json"), options: [.atomic])

    XCTAssertThrowsError(try CanonicalPetLibrary(rootURL: root)) { error in
      XCTAssertEqual((error as? PetPackError)?.code, "import_recovery_failed")
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

  func testPassiveBehaviorSessionsAdvanceOnIndependentClocks() throws {
    try withSyntheticPackage { package in
      let earlier = try PassiveBehaviorSession(package: package, startedAt: 0, seed: 3)
      let later = try PassiveBehaviorSession(package: package, startedAt: 0, seed: 6)

      let earlierAtForty = try earlier.update(at: 40)
      let laterAtForty = try later.update(at: 40)

      XCTAssertFalse(earlierAtForty.preloadClipIDs.isEmpty)
      XCTAssertTrue(laterAtForty.preloadClipIDs.isEmpty)
      XCTAssertEqual(earlierAtForty.currentNodeID, "rest.primary")
      XCTAssertEqual(laterAtForty.currentNodeID, "rest.primary")
    }
  }

  func testPassiveBehaviorPreloadsWholeGatewayPathAndTargetLoop() throws {
    try withSyntheticPackage { package in
      let primary = package.graph.nodes.first { $0.id == "rest.primary" }!
      let secondary = package.graph.nodes.first { $0.id == "rest.secondary" }!
      let gateway = PetGraphNode(
        id: "rest.gateway", role: "gateway", scene: "rest", loopClip: nil,
        autonomousEligible: false)
      let edges = [
        PetGraphEdge(
          id: "primary-to-gateway", from: primary.id, to: gateway.id,
          clip: "rest-primary-to-rest-secondary", interruptPolicy: "finish-before-retarget"),
        PetGraphEdge(
          id: "gateway-to-secondary", from: gateway.id, to: secondary.id,
          clip: "rest-secondary-to-rest-primary", interruptPolicy: "finish-before-retarget"),
      ]
      let modified = LoadedPetPack(
        runtimeRootURL: package.runtimeRootURL,
        manifest: package.manifest,
        graph: PetGraph(
          formatVersion: "1.0.0", nodes: [primary, gateway, secondary], edges: edges),
        behavior: package.behavior,
        clips: package.clips,
        archiveSHA256: package.archiveSHA256
      )
      let session = try PassiveBehaviorSession(package: modified, startedAt: 0, seed: 7)

      let planned = try session.update(at: 1_000)

      XCTAssertEqual(
        Set(planned.preloadClipIDs),
        Set([
          "rest-primary-to-rest-secondary", "rest-secondary-to-rest-primary",
          "rest-secondary-loop",
        ]))
      XCTAssertFalse(planned.isTransition)
      try session.cancelPlannedTransition(at: 1_000)
      XCTAssertTrue(try session.update(at: 1_000).preloadClipIDs.isEmpty)
    }
  }

  func testPassiveBehaviorAllowsWeightedImmediateRepeatWithoutTransition() throws {
    try withSyntheticPackage { package in
      let behavior = PetBehavior(
        formatVersion: package.behavior.formatVersion,
        profile: package.behavior.profile,
        defaultNode: package.behavior.defaultNode,
        timing: BehaviorTiming(
          strategy: package.behavior.timing.strategy,
          dwellRangesSeconds: package.behavior.timing.dwellRangesSeconds,
          avoidImmediateRepeat: false),
        nodeWeights: [
          "rest.primary": Double.greatestFiniteMagnitude,
          "rest.secondary": Double.leastNonzeroMagnitude,
        ],
        sceneWeights: package.behavior.sceneWeights
      )
      let modified = LoadedPetPack(
        runtimeRootURL: package.runtimeRootURL,
        manifest: package.manifest,
        graph: package.graph,
        behavior: behavior,
        clips: package.clips,
        archiveSHA256: package.archiveSHA256
      )
      let session = try PassiveBehaviorSession(package: modified, startedAt: 0, seed: 1)

      let presentation = try session.update(at: 1_000)

      XCTAssertEqual(presentation.currentNodeID, "rest.primary")
      XCTAssertFalse(presentation.isTransition)
      XCTAssertTrue(presentation.preloadClipIDs.isEmpty)
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

  private func visibleContentFrame(
    anchor: CGPoint,
    panel: CGSize,
    canvasHeight: CGFloat,
    content: CGRect
  ) -> CGRect {
    let pixelScale = panel.height / canvasHeight
    return CGRect(
      x: anchor.x - panel.width / 2 + content.minX * pixelScale,
      y: anchor.y + (canvasHeight - content.maxY) * pixelScale,
      width: content.width * pixelScale,
      height: content.height * pixelScale
    )
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

  private func stageInterruptedUninstall(
    root: URL,
    installed: InstalledPet,
    registryKeepsPet: Bool
  ) throws -> URL {
    let transaction = root.appendingPathComponent(
      "Staging/uninstall-interrupted-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: transaction, withIntermediateDirectories: true)
    let record: [String: Any] = [
      "packageID": installed.packageID,
      "petID": installed.petID,
      "displayName": installed.displayName,
      "species": installed.species,
      "contentVersion": installed.contentVersion.stringValue,
      "archiveSHA256": installed.archiveSHA256,
      "archiveBytes": installed.archiveBytes,
    ]
    let journal = try JSONSerialization.data(
      withJSONObject: ["formatVersion": 1, "records": [record]],
      options: [.prettyPrinted, .sortedKeys]
    )
    try journal.write(
      to: transaction.appendingPathComponent("transaction.json"), options: [.atomic])
    for component in ["Library", "Cache"] {
      let source = root.appendingPathComponent(
        "\(component)/\(installed.packageID)/\(installed.contentVersion.stringValue)",
        isDirectory: true)
      let destination = transaction.appendingPathComponent(
        "\(component)/\(installed.packageID)/\(installed.contentVersion.stringValue)",
        isDirectory: true)
      try FileManager.default.createDirectory(
        at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
      try FileManager.default.moveItem(at: source, to: destination)
    }
    if !registryKeepsPet {
      let registry = try JSONSerialization.data(
        withJSONObject: ["formatVersion": 1, "packages": []],
        options: [.prettyPrinted, .sortedKeys]
      )
      try registry.write(to: root.appendingPathComponent("registry.json"), options: [.atomic])
    }
    return transaction
  }
}
