import CryptoKit
import Foundation
import XCTest
@testable import PetsGraphCore

final class PackageLoaderTests: XCTestCase {
  func testLoadsApprovedSleepGraphContract() throws {
    let fixture = try SleepPackageFixture()
    addTeardownBlock { fixture.remove() }

    let package = try PetPackageLoader().load(at: fixture.root)
    XCTAssertEqual(Set(package.clips.keys), Set([
      "prone-left-loop-v1",
      "prone-left-to-side-curled-left-v1",
      "side-curled-left-loop-v1",
      "side-curled-left-to-prone-left-v1",
    ]))
    XCTAssertEqual(Set(package.graph.nodes.map(\.id)), Set([
      "rest.prone.left",
      "rest.side-curled.left",
    ]))
    XCTAssertEqual(Set(package.graph.edges.map(\.id)), Set([
      "prone-left-to-side-curled-left",
      "side-curled-left-to-prone-left",
    ]))
    XCTAssertEqual(package.clips["prone-left-loop-v1"]?.safeExitFrames, [15])
    XCTAssertEqual(package.clips["side-curled-left-loop-v1"]?.safeExitFrames, [52])

    for edge in package.graph.edges {
      XCTAssertFalse(edge.allowsInterruption(for: .autonomousBehavior))
      XCTAssertTrue(edge.allowsInterruption(for: .directManipulation))
    }
    for clip in package.clips.values {
      XCTAssertEqual(clip.rootMotionEndPt, [0, 0])
      XCTAssertTrue(clip.frames.allSatisfy { $0.rootMotionPt == [0, 0] })
    }
  }

  func testSleepTimelinePreloadsNextEdgeAndTargetLoop() throws {
    let fixture = try SleepPackageFixture()
    addTeardownBlock { fixture.remove() }
    let package = try PetPackageLoader().load(at: fixture.root)
    let timeline = try PlaybackTimeline(
      clips: package.clips,
      sequence: package.demoSequence
    )

    XCTAssertEqual(timeline.clipIDsNear(segmentIndex: 0), [
      "prone-left-loop-v1",
      "prone-left-to-side-curled-left-v1",
      "side-curled-left-loop-v1",
    ])
    XCTAssertEqual(timeline.clipIDsNear(segmentIndex: 2), [
      "side-curled-left-loop-v1",
      "side-curled-left-to-prone-left-v1",
      "prone-left-loop-v1",
    ])
  }

  func testLoadsSideStretchedSupineGraphContract() throws {
    let fixture = try SleepPackageFixture(kind: .sideStretchedSupine)
    addTeardownBlock { fixture.remove() }

    let package = try PetPackageLoader().load(at: fixture.root)
    XCTAssertEqual(Set(package.clips.keys), Set([
      "side-stretched-left-loop-v1",
      "side-stretched-left-to-supine-left-v1",
      "supine-left-loop-v1",
      "supine-left-to-side-stretched-left-v1",
    ]))
    XCTAssertEqual(Set(package.graph.nodes.map(\.id)), Set([
      "rest.side-stretched.left",
      "rest.supine.left",
    ]))
    XCTAssertEqual(Set(package.graph.edges.map(\.id)), Set([
      "side-stretched-left-to-supine-left",
      "supine-left-to-side-stretched-left",
    ]))
    XCTAssertEqual(package.clips["side-stretched-left-loop-v1"]?.frames.count, 50)
    XCTAssertEqual(package.clips["side-stretched-left-loop-v1"]?.safeExitFrames, [49])
    XCTAssertEqual(
      package.clips["side-stretched-left-to-supine-left-v1"]?.frames.count,
      135
    )
    XCTAssertEqual(package.clips["supine-left-loop-v1"]?.frames.count, 50)
    XCTAssertEqual(package.clips["supine-left-loop-v1"]?.safeExitFrames, [49])
    XCTAssertEqual(
      package.clips["supine-left-to-side-stretched-left-v1"]?.frames.count,
      106
    )

    for edge in package.graph.edges {
      XCTAssertFalse(edge.allowsInterruption(for: .autonomousBehavior))
      XCTAssertTrue(edge.allowsInterruption(for: .directManipulation))
    }
    for clip in package.clips.values {
      XCTAssertEqual(clip.rootMotionEndPt, [0, 0])
      XCTAssertTrue(clip.frames.allSatisfy { $0.rootMotionPt == [0, 0] })
    }
  }

  func testSideStretchedSupineTimelinePreloadsAndPlaysFramesInOrder() throws {
    let fixture = try SleepPackageFixture(kind: .sideStretchedSupine)
    addTeardownBlock { fixture.remove() }
    let package = try PetPackageLoader().load(at: fixture.root)
    let timeline = try PlaybackTimeline(
      clips: package.clips,
      sequence: package.demoSequence
    )

    XCTAssertEqual(timeline.clipIDsNear(segmentIndex: 0), [
      "side-stretched-left-loop-v1",
      "side-stretched-left-to-supine-left-v1",
      "supine-left-loop-v1",
    ])
    XCTAssertEqual(timeline.clipIDsNear(segmentIndex: 2), [
      "supine-left-loop-v1",
      "supine-left-to-side-stretched-left-v1",
      "side-stretched-left-loop-v1",
    ])

    let frameDuration = 41.666667 / 1_000.0
    let outboundStart = 3.0 * 50.0 * frameDuration
    XCTAssertEqual(
      timeline.sample(at: outboundStart + 0.000_001).clipID,
      "side-stretched-left-to-supine-left-v1"
    )
    XCTAssertEqual(timeline.sample(at: outboundStart + 0.000_001).sourceFrameIndex, 0)
    XCTAssertEqual(
      timeline.sample(at: outboundStart + frameDuration + 0.000_001).sourceFrameIndex,
      1
    )
    let supineStart = outboundStart + 135.0 * frameDuration
    XCTAssertEqual(timeline.sample(at: supineStart + 0.000_001).clipID, "supine-left-loop-v1")
    XCTAssertEqual(timeline.sample(at: supineStart + 0.000_001).sourceFrameIndex, 0)
  }

  func testRejectsDemoThatLeavesLoopBeforeSafeExit() throws {
    let fixture = try SleepPackageFixture(kind: .sideStretchedSupine)
    addTeardownBlock { fixture.remove() }
    try fixture.makeFirstLoopExitUnsafe()

    XCTAssertThrowsError(
      try PetPackageLoader().load(at: fixture.root, verifyIntegrity: false)
    ) { error in
      XCTAssertTrue(String(describing: error).contains("unsafe frame 48"))
    }
  }

  func testRejectsTargetStartFrameOutsideTargetLoop() throws {
    let fixture = try SleepPackageFixture()
    addTeardownBlock { fixture.remove() }
    try fixture.makeFirstEdgeTargetStartFrameInvalid()

    XCTAssertThrowsError(
      try PetPackageLoader().load(at: fixture.root, verifyIntegrity: false)
    ) { error in
      XCTAssertTrue(String(describing: error).contains("invalid target loop frame 53"))
    }
  }

  func testMissingClipFileIsRejected() throws {
    let fixture = try SleepPackageFixture()
    addTeardownBlock { fixture.remove() }
    try FileManager.default.removeItem(
      at: fixture.root.appendingPathComponent("clips/prone-left-loop-v1.json")
    )

    XCTAssertThrowsError(try PetPackageLoader().load(at: fixture.root))
  }

  func testModifiedClipFileFailsIntegrity() throws {
    let fixture = try SleepPackageFixture()
    addTeardownBlock { fixture.remove() }
    let clip = fixture.root.appendingPathComponent("clips/prone-left-loop-v1.json")
    var data = try Data(contentsOf: clip)
    data.append(contentsOf: [0x20, 0x0A])
    try data.write(to: clip)

    assertIntegrityFailure(try PetPackageLoader().load(at: fixture.root))
  }

  func testHiddenClipFileFailsIntegrity() throws {
    let fixture = try SleepPackageFixture()
    addTeardownBlock { fixture.remove() }
    var clip = fixture.root.appendingPathComponent("clips/prone-left-loop-v1.json")
    var values = URLResourceValues()
    values.isHidden = true
    try clip.setResourceValues(values)
    XCTAssertEqual(try clip.resourceValues(forKeys: [.isHiddenKey]).isHidden, true)

    assertIntegrityFailure(try PetPackageLoader().load(at: fixture.root))
  }

  func testLoadsQuietCompanionSchemaContract() throws {
    let fixture = try SleepPackageFixture(kind: .quietCompanion)
    addTeardownBlock { fixture.remove() }

    let package = try PetPackageLoader().load(at: fixture.root)
    XCTAssertEqual(package.manifest.schemaVersion, "0.2.0")
    XCTAssertEqual(package.behavior?.profile, "quiet-sleep-companion")
    XCTAssertEqual(package.behavior?.interactions.desktopClick, "ignore")
    XCTAssertEqual(
      package.behavior?.interactions.petClick.debounceSeconds ?? -1,
      0.35,
      accuracy: 0.000_001
    )
    XCTAssertEqual(package.manifest.renderAssets.environmentProps?.map(\.id), ["pillow"])
    XCTAssertEqual(
      package.manifest.renderAssets.environmentProps?.first?.offsetFromFloorOriginPt,
      [35.625, 0]
    )
    XCTAssertEqual(package.manifest.renderAssets.environmentProps?.first?.hitTest, "passthrough")
    XCTAssertEqual(package.manifest.renderAssets.environmentProps?.first?.scenes, ["floor"])
    XCTAssertEqual(package.environmentPropURL(id: "pillow")?.lastPathComponent, "pillow.png")
    XCTAssertEqual(package.graph.nodes.first(where: { $0.id == "rest.prone.left" })?.role, "dwell")
    XCTAssertEqual(package.graph.nodes.first(where: { $0.id == "sit.front.floor" })?.role, "interaction")
    XCTAssertTrue(package.clips.values.allSatisfy { clip in
      clip.rootMotionEndPt == [0, 0]
        && clip.frames.allSatisfy { $0.rootMotionPt == [0, 0] }
    })
  }

  func testLoadsEmbeddedEnvironmentPropContract() throws {
    let fixture = try SleepPackageFixture(kind: .quietCompanion)
    addTeardownBlock { fixture.remove() }
    try fixture.setEnvironmentPropVisibility("embedded")

    let package = try PetPackageLoader().load(
      at: fixture.root,
      verifyIntegrity: false
    )
    XCTAssertEqual(
      package.manifest.renderAssets.environmentProps?.first?.visibility,
      "embedded"
    )
    XCTAssertEqual(
      package.manifest.renderAssets.environmentProps?.first?.scenes,
      ["floor"]
    )
  }

  func testLoadsHEVCAlphaPackageWithoutBundledPNGFrames() throws {
    let fixture = try SleepPackageFixture(kind: .quietCompanion)
    addTeardownBlock { fixture.remove() }
    try fixture.enableHEVCAlphaMedia()

    let package = try PetPackageLoader().load(at: fixture.root)
    XCTAssertEqual(package.manifest.schemaVersion, "0.3.0")
    XCTAssertEqual(package.manifest.renderAssets.mode, "hevc-alpha-clips")
    XCTAssertEqual(package.clips.count, 4)
    for clip in package.clips.values {
      XCTAssertEqual(clip.media?.frameCount, clip.frames.count)
      XCTAssertEqual(clip.media?.frameRate, 24)
      XCTAssertEqual(clip.media?.compiledFrameSequenceDigest.count, 64)
      XCTAssertNil(package.frameURL(clipID: clip.id, frameIndex: 0))
      XCTAssertEqual(package.clipMediaURL(clipID: clip.id)?.pathExtension, "mov")
    }
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: fixture.root.appendingPathComponent("frames").path
      )
    )
  }

  func testMissingHEVCAlphaMediaIsRejected() throws {
    let fixture = try SleepPackageFixture(kind: .quietCompanion)
    addTeardownBlock { fixture.remove() }
    try fixture.enableHEVCAlphaMedia()
    try FileManager.default.removeItem(at: fixture.firstMediaURL)

    XCTAssertThrowsError(try PetPackageLoader().load(at: fixture.root))
  }

  func testModifiedHEVCAlphaMediaFailsIntegrity() throws {
    let fixture = try SleepPackageFixture(kind: .quietCompanion)
    addTeardownBlock { fixture.remove() }
    try fixture.enableHEVCAlphaMedia()
    var data = try Data(contentsOf: fixture.firstMediaURL)
    data.append(0x00)
    try data.write(to: fixture.firstMediaURL)

    assertIntegrityFailure(try PetPackageLoader().load(at: fixture.root))
  }

  func testHiddenHEVCAlphaMediaFailsIntegrity() throws {
    let fixture = try SleepPackageFixture(kind: .quietCompanion)
    addTeardownBlock { fixture.remove() }
    try fixture.enableHEVCAlphaMedia()
    var media = fixture.firstMediaURL
    var values = URLResourceValues()
    values.isHidden = true
    try media.setResourceValues(values)

    assertIntegrityFailure(try PetPackageLoader().load(at: fixture.root))
  }

  func testHEVCAlphaMediaFrameCountMustMatchMetadataFrames() throws {
    let fixture = try SleepPackageFixture(kind: .quietCompanion)
    addTeardownBlock { fixture.remove() }
    try fixture.enableHEVCAlphaMedia()
    try fixture.setFirstMediaFrameCount(999)

    XCTAssertThrowsError(
      try PetPackageLoader().load(at: fixture.root, verifyIntegrity: false)
    ) { error in
      XCTAssertTrue(String(describing: error).contains("invalid HEVC Alpha media contract"))
    }
  }

  func testLoadsCroppedRGBAPackageWithoutBundledPNGFrames() throws {
    let fixture = try SleepPackageFixture(kind: .quietCompanion)
    addTeardownBlock { fixture.remove() }
    try fixture.enableCroppedRGBAMedia()

    let package = try PetPackageLoader().load(at: fixture.root)
    XCTAssertEqual(package.manifest.schemaVersion, "0.4.0")
    XCTAssertEqual(package.manifest.renderAssets.mode, "cropped-rgba-clips")
    XCTAssertEqual(package.clips.count, 4)
    for clip in package.clips.values {
      XCTAssertEqual(clip.media?.frameCount, clip.frames.count)
      XCTAssertEqual(clip.media?.cropRectPx, [0, 0, 1, 1])
      XCTAssertEqual(clip.media?.bytesPerRow, 4)
      XCTAssertEqual(clip.media?.frameByteCount, 4)
      XCTAssertNil(package.frameURL(clipID: clip.id, frameIndex: 0))
      XCTAssertEqual(package.clipMediaURL(clipID: clip.id)?.pathExtension, "rgba")
      XCTAssertTrue(clip.frames.allSatisfy { $0.src == clip.media?.src })
    }
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: fixture.root.appendingPathComponent("frames").path
      )
    )
  }

  func testMissingCroppedRGBAMediaIsRejected() throws {
    let fixture = try SleepPackageFixture(kind: .quietCompanion)
    addTeardownBlock { fixture.remove() }
    try fixture.enableCroppedRGBAMedia()
    try FileManager.default.removeItem(at: fixture.firstRawMediaURL)

    XCTAssertThrowsError(try PetPackageLoader().load(at: fixture.root))
  }

  func testModifiedCroppedRGBAMediaFailsIntegrity() throws {
    let fixture = try SleepPackageFixture(kind: .quietCompanion)
    addTeardownBlock { fixture.remove() }
    try fixture.enableCroppedRGBAMedia()
    var data = try Data(contentsOf: fixture.firstRawMediaURL)
    data[0] ^= 0xFF
    try data.write(to: fixture.firstRawMediaURL)

    assertIntegrityFailure(try PetPackageLoader().load(at: fixture.root))
  }

  func testHiddenCroppedRGBAMediaFailsIntegrity() throws {
    let fixture = try SleepPackageFixture(kind: .quietCompanion)
    addTeardownBlock { fixture.remove() }
    try fixture.enableCroppedRGBAMedia()
    var media = fixture.firstRawMediaURL
    var values = URLResourceValues()
    values.isHidden = true
    try media.setResourceValues(values)

    assertIntegrityFailure(try PetPackageLoader().load(at: fixture.root))
  }

  func testCroppedRGBAMediaByteCountMustMatchContract() throws {
    let fixture = try SleepPackageFixture(kind: .quietCompanion)
    addTeardownBlock { fixture.remove() }
    try fixture.enableCroppedRGBAMedia()
    try fixture.setFirstRawFrameByteCount(8)

    XCTAssertThrowsError(
      try PetPackageLoader().load(at: fixture.root, verifyIntegrity: false)
    ) { error in
      XCTAssertTrue(String(describing: error).contains("invalid cropped RGBA media contract"))
    }
  }

  func testCroppedRGBAMetadataDigestMustMatchIntegrityDigest() throws {
    let fixture = try SleepPackageFixture(kind: .quietCompanion)
    addTeardownBlock { fixture.remove() }
    try fixture.enableCroppedRGBAMedia()
    try fixture.setFirstRawCompiledDigest(String(repeating: "c", count: 64))

    assertIntegrityFailure(try PetPackageLoader().load(at: fixture.root))
  }

  func testRejectsQuietSleepNodeWithoutDisplayName() throws {
    let fixture = try SleepPackageFixture(kind: .quietCompanion)
    addTeardownBlock { fixture.remove() }
    try fixture.removeDwellDisplayName()

    XCTAssertThrowsError(
      try PetPackageLoader().load(at: fixture.root, verifyIntegrity: false)
    ) { error in
      XCTAssertTrue(String(describing: error).contains("localized display name"))
    }
  }

  func testMissingEnvironmentPropIsRejected() throws {
    let fixture = try SleepPackageFixture(kind: .quietCompanion)
    addTeardownBlock { fixture.remove() }
    try FileManager.default.removeItem(at: fixture.environmentPropURL)

    XCTAssertThrowsError(try PetPackageLoader().load(at: fixture.root))
  }

  func testModifiedEnvironmentPropFailsIntegrity() throws {
    let fixture = try SleepPackageFixture(kind: .quietCompanion)
    addTeardownBlock { fixture.remove() }
    var data = try Data(contentsOf: fixture.environmentPropURL)
    data.append(0x20)
    try data.write(to: fixture.environmentPropURL)

    assertIntegrityFailure(try PetPackageLoader().load(at: fixture.root))
  }

  func testHiddenEnvironmentPropFailsIntegrity() throws {
    let fixture = try SleepPackageFixture(kind: .quietCompanion)
    addTeardownBlock { fixture.remove() }
    var prop = fixture.environmentPropURL
    var values = URLResourceValues()
    values.isHidden = true
    try prop.setResourceValues(values)

    assertIntegrityFailure(try PetPackageLoader().load(at: fixture.root))
  }

  func testRejectsQuietSameSceneRootMotion() throws {
    let fixture = try SleepPackageFixture(kind: .quietCompanion)
    addTeardownBlock { fixture.remove() }
    try fixture.setTerminalRootMotion(clipID: "prone-left-to-sit-front-v1", x: 12)

    XCTAssertThrowsError(
      try PetPackageLoader().load(at: fixture.root, verifyIntegrity: false)
    ) { error in
      XCTAssertTrue(String(describing: error).contains("same-scene edge"))
    }
  }

  func testRejectsQuietNodeLoopRootMotion() throws {
    let fixture = try SleepPackageFixture(kind: .quietCompanion)
    addTeardownBlock { fixture.remove() }
    try fixture.setTerminalRootMotion(clipID: "prone-left-loop-v1", x: 12)

    XCTAssertThrowsError(
      try PetPackageLoader().load(at: fixture.root, verifyIntegrity: false)
    ) { error in
      XCTAssertTrue(String(describing: error).contains("zero root motion"))
    }
  }

  private func assertIntegrityFailure<T>(
    _ expression: @autoclosure () throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertThrowsError(try expression(), file: file, line: line) { error in
      guard case PackageValidationError.integrity = error else {
        XCTFail("expected integrity failure, got \(error)", file: file, line: line)
        return
      }
    }
  }
}

private enum SleepFixtureKind: Equatable {
  case proneSideCurled
  case sideStretchedSupine
  case quietCompanion
}

private final class SleepPackageFixture: @unchecked Sendable {
  let root: URL
  var environmentPropURL: URL {
    root.appendingPathComponent("props/pillow.png")
  }
  var firstMediaURL: URL {
    root.appendingPathComponent("media/prone-left-loop-v1.mov")
  }
  var firstRawMediaURL: URL {
    root.appendingPathComponent("media/prone-left-loop-v1.rgba")
  }
  private let kind: SleepFixtureKind
  private var writtenPaths = Set<String>()

  init(kind: SleepFixtureKind = .proneSideCurled) throws {
    self.kind = kind
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("petsgraph-sleep-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    root = directory.resolvingSymlinksInPath()
    try build()
  }

  func remove() {
    try? FileManager.default.removeItem(at: root)
  }

  func makeFirstLoopExitUnsafe() throws {
    let url = root.appendingPathComponent("demo-sequence.json")
    var value = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    var segments = value["segments"] as! [[String: Any]]
    segments[0]["frameCount"] = 49
    segments[0]["cycles"] = 1
    value["segments"] = segments
    let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url)
  }

  func makeFirstEdgeTargetStartFrameInvalid() throws {
    let url = root.appendingPathComponent("graph.json")
    var value = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    var edges = value["edges"] as! [[String: Any]]
    edges[0]["targetStartFrame"] = 53
    value["edges"] = edges
    let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url)
  }

  func setTerminalRootMotion(clipID: String, x: Double) throws {
    let url = root.appendingPathComponent("clips/\(clipID).json")
    var value = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    value["rootMotionEndPt"] = [x, 0]
    let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url)
  }

  func removeDwellDisplayName() throws {
    let url = root.appendingPathComponent("graph.json")
    var value = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    var nodes = value["nodes"] as! [[String: Any]]
    guard let index = nodes.firstIndex(where: { $0["role"] as? String == "dwell" }) else {
      throw PackageValidationError.missing("fixture dwell node")
    }
    nodes[index].removeValue(forKey: "displayName")
    value["nodes"] = nodes
    let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url)
  }

  func setEnvironmentPropVisibility(_ visibility: String) throws {
    let url = root.appendingPathComponent("package.json")
    var value = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    var renderAssets = value["renderAssets"] as! [String: Any]
    var props = renderAssets["environmentProps"] as! [[String: Any]]
    props[0]["visibility"] = visibility
    renderAssets["environmentProps"] = props
    value["renderAssets"] = renderAssets
    let data = try JSONSerialization.data(
      withJSONObject: value,
      options: [.prettyPrinted, .sortedKeys]
    )
    try data.write(to: url)
  }

  func enableHEVCAlphaMedia() throws {
    guard kind == .quietCompanion else {
      throw PackageValidationError.invalid("HEVC fixture requires quiet companion")
    }
    let packageURL = root.appendingPathComponent("package.json")
    var package = try JSONSerialization.jsonObject(
      with: Data(contentsOf: packageURL)
    ) as! [String: Any]
    package["schemaVersion"] = "0.3.0"
    var renderAssets = package["renderAssets"] as! [String: Any]
    renderAssets["mode"] = "hevc-alpha-clips"
    renderAssets["pixelFormat"] = "bgra8-premultiplied"
    package["renderAssets"] = renderAssets
    try writeJSON(package, to: "package.json")

    let clipPaths = writtenPaths.filter { $0.hasPrefix("clips/") }.sorted()
    for path in clipPaths {
      let url = root.appendingPathComponent(path)
      var clip = try JSONSerialization.jsonObject(
        with: Data(contentsOf: url)
      ) as! [String: Any]
      let clipID = clip["id"] as! String
      let frames = clip["frames"] as! [[String: Any]]
      for frame in frames {
        let framePath = frame["src"] as! String
        try FileManager.default.removeItem(
          at: root.appendingPathComponent(framePath)
        )
        writtenPaths.remove(framePath)
      }
      clip["schemaVersion"] = "0.3.0"
      clip["provenance"] = [
        "approvalStatus": "approved",
        "sourceSequenceDigest": String(repeating: "a", count: 64),
        "rootMotionStatus": "approved-zero-root-motion",
        "normalization": "approved-frame-canvas",
      ]
      let mediaPath = "media/\(clipID).mov"
      try writeData(Data([0x00, 0x00, 0x00, 0x00]), to: mediaPath)
      clip["media"] = [
        "type": "video",
        "src": mediaPath,
        "codec": "hevc-alpha",
        "container": "quicktime",
        "frameCount": frames.count,
        "frameRate": 24,
        "alphaMode": "premultiplied",
        "colorSpace": "sRGB",
        "sourceSequenceDigest": String(repeating: "a", count: 64),
        "compiledFrameSequenceDigest": String(repeating: "b", count: 64),
      ]
      try writeJSON(clip, to: path)
    }
    try? FileManager.default.removeItem(at: root.appendingPathComponent("frames"))
    try rewriteIntegrity(schemaVersion: "0.3.0")
  }

  func setFirstMediaFrameCount(_ count: Int) throws {
    let url = root.appendingPathComponent("clips/prone-left-loop-v1.json")
    var clip = try JSONSerialization.jsonObject(
      with: Data(contentsOf: url)
    ) as! [String: Any]
    var media = clip["media"] as! [String: Any]
    media["frameCount"] = count
    clip["media"] = media
    try writeJSON(clip, to: "clips/prone-left-loop-v1.json")
  }

  func enableCroppedRGBAMedia() throws {
    guard kind == .quietCompanion else {
      throw PackageValidationError.invalid("cropped RGBA fixture requires quiet companion")
    }
    let packageURL = root.appendingPathComponent("package.json")
    var package = try JSONSerialization.jsonObject(
      with: Data(contentsOf: packageURL)
    ) as! [String: Any]
    package["schemaVersion"] = "0.4.0"
    var renderAssets = package["renderAssets"] as! [String: Any]
    renderAssets["mode"] = "cropped-rgba-clips"
    renderAssets["pixelFormat"] = "rgba8-premultiplied"
    package["renderAssets"] = renderAssets
    try writeJSON(package, to: "package.json")

    let clipPaths = writtenPaths.filter { $0.hasPrefix("clips/") }.sorted()
    for path in clipPaths {
      let url = root.appendingPathComponent(path)
      var clip = try JSONSerialization.jsonObject(
        with: Data(contentsOf: url)
      ) as! [String: Any]
      let clipID = clip["id"] as! String
      var frames = clip["frames"] as! [[String: Any]]
      for frame in frames {
        let framePath = frame["src"] as! String
        try FileManager.default.removeItem(at: root.appendingPathComponent(framePath))
        writtenPaths.remove(framePath)
      }
      let mediaPath = "media/\(clipID).rgba"
      for index in frames.indices {
        frames[index]["src"] = mediaPath
      }
      clip["frames"] = frames
      clip["schemaVersion"] = "0.4.0"
      clip["provenance"] = [
        "approvalStatus": "approved",
        "sourceSequenceDigest": String(repeating: "a", count: 64),
        "rootMotionStatus": "approved-zero-root-motion",
        "normalization": "approved-frame-canvas",
      ]
      let rawData = Data(repeating: 0xFF, count: frames.count * 4)
      try writeData(rawData, to: mediaPath)
      clip["media"] = [
        "type": "raw-frames",
        "src": mediaPath,
        "codec": "raw-rgba8",
        "container": "contiguous-frame-stream",
        "frameCount": frames.count,
        "frameRate": 24,
        "alphaMode": "premultiplied-last",
        "colorSpace": "sRGB",
        "sourceSequenceDigest": String(repeating: "a", count: 64),
        "compiledFrameSequenceDigest": SHA256.hash(data: rawData)
          .map { String(format: "%02x", $0) }.joined(),
        "cropRectPx": [0, 0, 1, 1],
        "bytesPerRow": 4,
        "frameByteCount": 4,
      ]
      try writeJSON(clip, to: path)
    }
    try? FileManager.default.removeItem(at: root.appendingPathComponent("frames"))
    try rewriteIntegrity(schemaVersion: "0.4.0")
  }

  func setFirstRawFrameByteCount(_ count: Int) throws {
    let url = root.appendingPathComponent("clips/prone-left-loop-v1.json")
    var clip = try JSONSerialization.jsonObject(
      with: Data(contentsOf: url)
    ) as! [String: Any]
    var media = clip["media"] as! [String: Any]
    media["frameByteCount"] = count
    clip["media"] = media
    try writeJSON(clip, to: "clips/prone-left-loop-v1.json")
  }

  func setFirstRawCompiledDigest(_ digest: String) throws {
    let url = root.appendingPathComponent("clips/prone-left-loop-v1.json")
    var clip = try JSONSerialization.jsonObject(
      with: Data(contentsOf: url)
    ) as! [String: Any]
    var media = clip["media"] as! [String: Any]
    media["compiledFrameSequenceDigest"] = digest
    clip["media"] = media
    try writeJSON(clip, to: "clips/prone-left-loop-v1.json")
    try rewriteIntegrity(schemaVersion: "0.4.0")
  }

  private func build() throws {
    let clips: [[String: Any]]
    switch kind {
    case .proneSideCurled:
      clips = [
        clip(
          id: "prone-left-loop-v1",
          type: "loop",
          entry: "rest.prone.left",
          exit: "rest.prone.left",
          frameCount: 16,
          safeExits: [15],
          preloadHints: ["prone-left-to-side-curled-left-v1"]
        ),
        clip(
          id: "prone-left-to-side-curled-left-v1",
          type: "transition",
          entry: "rest.prone.left",
          exit: "rest.side-curled.left",
          frameCount: 2,
          safeExits: [],
          preloadHints: ["side-curled-left-loop-v1"]
        ),
        clip(
          id: "side-curled-left-loop-v1",
          type: "loop",
          entry: "rest.side-curled.left",
          exit: "rest.side-curled.left",
          frameCount: 53,
          safeExits: [52],
          preloadHints: ["side-curled-left-to-prone-left-v1"]
        ),
        clip(
          id: "side-curled-left-to-prone-left-v1",
          type: "transition",
          entry: "rest.side-curled.left",
          exit: "rest.prone.left",
          frameCount: 2,
          safeExits: [],
          preloadHints: ["prone-left-loop-v1"]
        ),
      ]
    case .sideStretchedSupine:
      clips = [
        clip(
          id: "side-stretched-left-loop-v1",
          type: "loop",
          entry: "rest.side-stretched.left",
          exit: "rest.side-stretched.left",
          frameCount: 50,
          safeExits: [49],
          preloadHints: ["side-stretched-left-to-supine-left-v1"]
        ),
        clip(
          id: "side-stretched-left-to-supine-left-v1",
          type: "transition",
          entry: "rest.side-stretched.left",
          exit: "rest.supine.left",
          frameCount: 135,
          safeExits: [],
          preloadHints: ["supine-left-loop-v1"]
        ),
        clip(
          id: "supine-left-loop-v1",
          type: "loop",
          entry: "rest.supine.left",
          exit: "rest.supine.left",
          frameCount: 50,
          safeExits: [49],
          preloadHints: ["supine-left-to-side-stretched-left-v1"]
        ),
        clip(
          id: "supine-left-to-side-stretched-left-v1",
          type: "transition",
          entry: "rest.supine.left",
          exit: "rest.side-stretched.left",
          frameCount: 106,
          safeExits: [],
          preloadHints: ["side-stretched-left-loop-v1"]
        ),
      ]
    case .quietCompanion:
      clips = [
        clip(
          id: "prone-left-loop-v1",
          type: "loop",
          entry: "rest.prone.left",
          exit: "rest.prone.left",
          frameCount: 16,
          safeExits: [15],
          preloadHints: ["prone-left-to-sit-front-v1"]
        ),
        clip(
          id: "sit-front-floor-loop-v1",
          type: "loop",
          entry: "sit.front.floor",
          exit: "sit.front.floor",
          frameCount: 4,
          safeExits: [3],
          preloadHints: ["sit-front-to-prone-left-v1"]
        ),
        clip(
          id: "prone-left-to-sit-front-v1",
          type: "transition",
          entry: "rest.prone.left",
          exit: "sit.front.floor",
          frameCount: 2,
          safeExits: [],
          preloadHints: ["sit-front-floor-loop-v1"]
        ),
        clip(
          id: "sit-front-to-prone-left-v1",
          type: "transition",
          entry: "sit.front.floor",
          exit: "rest.prone.left",
          frameCount: 2,
          safeExits: [],
          preloadHints: ["prone-left-loop-v1"]
        ),
      ]
    }
    for clip in clips {
      try writeJSON(clip, to: "clips/\(clip["id"] as! String).json")
    }

    let graphNodes: [[String: Any]]
    let graphEdges: [[String: Any]]
    let demoSegments: [[String: Any]]
    switch kind {
    case .proneSideCurled:
      graphNodes = [
        node(id: "rest.prone.left", posture: "prone", loop: "prone-left-loop-v1"),
        node(
          id: "rest.side-curled.left",
          posture: "side-curled",
          loop: "side-curled-left-loop-v1"
        ),
      ]
      graphEdges = [
        edge(
          id: "prone-left-to-side-curled-left",
          from: "rest.prone.left",
          to: "rest.side-curled.left",
          clip: "prone-left-to-side-curled-left-v1"
        ),
        edge(
          id: "side-curled-left-to-prone-left",
          from: "rest.side-curled.left",
          to: "rest.prone.left",
          clip: "side-curled-left-to-prone-left-v1"
        ),
      ]
      demoSegments = [
        segment("prone-left-loop-v1", cycles: 3),
        segment("prone-left-to-side-curled-left-v1"),
        segment("side-curled-left-loop-v1", cycles: 3),
        segment("side-curled-left-to-prone-left-v1"),
        segment("prone-left-loop-v1", repeatForever: true),
      ]
    case .sideStretchedSupine:
      graphNodes = [
        node(
          id: "rest.side-stretched.left",
          posture: "side-stretched",
          loop: "side-stretched-left-loop-v1"
        ),
        node(id: "rest.supine.left", posture: "supine", loop: "supine-left-loop-v1"),
      ]
      graphEdges = [
        edge(
          id: "side-stretched-left-to-supine-left",
          from: "rest.side-stretched.left",
          to: "rest.supine.left",
          clip: "side-stretched-left-to-supine-left-v1"
        ),
        edge(
          id: "supine-left-to-side-stretched-left",
          from: "rest.supine.left",
          to: "rest.side-stretched.left",
          clip: "supine-left-to-side-stretched-left-v1"
        ),
      ]
      demoSegments = [
        segment("side-stretched-left-loop-v1", cycles: 3),
        segment("side-stretched-left-to-supine-left-v1"),
        segment("supine-left-loop-v1", cycles: 3),
        segment("supine-left-to-side-stretched-left-v1"),
        segment("side-stretched-left-loop-v1", repeatForever: true),
      ]
    case .quietCompanion:
      graphNodes = [
        quietNode(
          id: "rest.prone.left",
          posture: "prone",
          loop: "prone-left-loop-v1",
          role: "dwell",
          autonomous: true
        ),
        quietNode(
          id: "sit.front.floor",
          posture: "sit",
          loop: "sit-front-floor-loop-v1",
          role: "interaction",
          autonomous: false
        ),
      ]
      graphEdges = [
        quietEdge(
          id: "prone-left-to-sit-front",
          from: "rest.prone.left",
          to: "sit.front.floor",
          clip: "prone-left-to-sit-front-v1"
        ),
        quietEdge(
          id: "sit-front-to-prone-left",
          from: "sit.front.floor",
          to: "rest.prone.left",
          clip: "sit-front-to-prone-left-v1"
        ),
      ]
      demoSegments = [
        segment("prone-left-loop-v1", cycles: 1),
        segment("prone-left-to-sit-front-v1"),
        segment("sit-front-floor-loop-v1", repeatForever: true),
      ]
    }

    let schemaVersion = kind == .quietCompanion ? "0.2.0" : "0.1.0"

    var renderAssets: [String: Any] = [
      "mode": "frames",
      "pixelFormat": "rgba8-straight",
    ]
    if kind == .quietCompanion {
      try writeData(Data([0x89, 0x50, 0x4E, 0x47]), to: "props/pillow.png")
      renderAssets["environmentProps"] = [[
        "id": "pillow",
        "src": "props/pillow.png",
        "offsetFromFloorOriginPt": [35.625, 0],
        "visibility": "node-scenes",
        "scenes": ["floor"],
        "layer": "behind-pet",
        "hitTest": "passthrough",
      ]]
    }
    var packageManifest: [String: Any] = [
        "schemaVersion": schemaVersion,
        "package": [
          "id": "sleep-test",
          "version": "0.0.0-test",
          "createdAt": "2026-08-09T00:00:00+08:00",
        ],
        "pet": [
          "id": "wubai",
          "displayName": "Wubai",
          "species": "cat",
          "identityStyle": "test",
        ],
        "art": [
          "canvasPx": [320, 320],
          "baseHeightPt": 150,
          "coordinateOrigin": "top-left",
          "defaultNode": kind == .proneSideCurled
            ? "rest.prone.left"
            : (kind == .sideStretchedSupine ? "rest.side-stretched.left" : "rest.prone.left"),
          "groundYPx": 266,
        ],
        "renderAssets": renderAssets,
        "graph": "graph.json",
        "reviewIndex": "reviews/index.json",
        "integrity": "integrity.json",
    ]
    if kind == .quietCompanion {
      packageManifest["behavior"] = "behavior.json"
    }
    try writeJSON(packageManifest, to: "package.json")
    try writeJSON(
      [
        "schemaVersion": schemaVersion,
        "nodes": graphNodes,
        "edges": graphEdges,
      ],
      to: "graph.json"
    )
    try writeJSON(
      [
        "schemaVersion": schemaVersion,
        "id": "sleep-test-chain",
        "segments": demoSegments,
      ],
      to: "demo-sequence.json"
    )
    if kind == .quietCompanion {
      try writeJSON(
        [
          "schemaVersion": "0.2.0",
          "profile": "quiet-sleep-companion",
          "defaultIntent": "sleep",
          "timing": [
            "strategy": "random-long-tail",
            "parametersStatus": "product-default-awaiting-runtime-review",
            "avoidImmediateRepeat": true,
            "minimumDwellSeconds": 120,
            "medianDwellSeconds": 420,
            "maximumDwellSeconds": 1_200,
          "recentHistoryLimit": 2,
          "sameSceneProbability": 0.9,
          ],
          "scenePolicy": [
            "floor": [
              "sticky": true,
              "minimumDwellSeconds": 300,
              "exitCooldownSeconds": 300,
            ],
          ],
          "interactions": [
            "petClick": [
              "sleeping": "wake-to-scene-sit",
              "sitting": "return-to-scene-sleep",
              "debounceSeconds": 0.35,
            ],
            "desktopClick": "ignore",
            "drag": "direct-manipulation",
          ],
        ],
        to: "behavior.json"
      )
    }
    try writeJSON(["runtimeChainStatus": "awaiting-human-runtime-review"], to: "reviews/index.json")

    let entries = try writtenPaths.sorted().map { path -> [String: Any] in
      let data = try Data(contentsOf: root.appendingPathComponent(path))
      return [
        "path": path,
        "bytes": data.count,
        "sha256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
      ]
    }
    try writeJSON(
      ["schemaVersion": schemaVersion, "algorithm": "sha256", "files": entries],
      to: "integrity.json"
    )
  }

  private func node(id: String, posture: String, loop: String) -> [String: Any] {
    [
      "id": id,
      "displayName": "测试姿态",
      "posture": posture,
      "orientation": "left",
      "grounded": true,
      "stability": "stable",
      "loopClip": loop,
    ]
  }

  private func edge(
    id: String,
    from: String,
    to: String,
    clip: String
  ) -> [String: Any] {
    [
      "id": id,
      "from": from,
      "to": to,
      "clip": clip,
      "kind": "transition",
      "interruptPolicy": "direct-manipulation-only",
    ]
  }

  private func quietNode(
    id: String,
    posture: String,
    loop: String,
    role: String,
    autonomous: Bool
  ) -> [String: Any] {
    [
      "id": id,
      "displayName": role == "dwell" ? "测试睡姿" : "测试坐姿",
      "posture": posture,
      "orientation": "front",
      "grounded": true,
      "stability": "stable",
      "loopClip": loop,
      "scene": "floor",
      "role": role,
      "autonomousEligible": autonomous,
      "props": [],
    ]
  }

  private func quietEdge(
    id: String,
    from: String,
    to: String,
    clip: String
  ) -> [String: Any] {
    [
      "id": id,
      "from": from,
      "to": to,
      "clip": clip,
      "kind": "transition",
      "interruptPolicy": "finish-before-retarget",
      "targetStartFrame": 0,
    ]
  }

  private func clip(
    id: String,
    type: String,
    entry: String,
    exit: String,
    frameCount: Int,
    safeExits: [Int],
    preloadHints: [String]
  ) -> [String: Any] {
    let frames = (0..<frameCount).map { index -> [String: Any] in
      let path = "frames/\(id)/\(String(format: "%04d", index)).png"
      try! writeData(Data([0x89, 0x50, 0x4E, 0x47]), to: path)
      return [
        "src": path,
        "durationMs": 41.666667,
        "contentBoundsPx": [80, 100, 160, 166],
        "anchorsPx": [
          "root": [160, 266],
          "ground": [160, 266],
          "head": [100, 140],
        ],
        "collision": [
          "bodyCoreEllipsePx": [100, 140, 120, 80],
          "screenBoundsPx": [80, 100, 160, 166],
        ],
        "rootMotionPt": [0, 0],
      ]
    }
    return [
      "schemaVersion": "0.1.0",
      "id": id,
      "type": type,
      "facing": "left",
      "mirrorSafe": false,
      "entryPose": entry,
      "exitPose": exit,
      "safeExitFrames": safeExits,
      "preloadHints": preloadHints,
      "rootMotionEndPt": [0, 0],
      "frames": frames,
    ]
  }

  private func segment(
    _ clip: String,
    cycles: Int = 1,
    repeatForever: Bool = false
  ) -> [String: Any] {
    [
      "clip": clip,
      "startFrame": 0,
      "cycles": cycles,
      "repeatForever": repeatForever,
    ]
  }

  private func writeJSON(_ value: Any, to relativePath: String) throws {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    try writeData(data, to: relativePath)
  }

  private func writeData(_ data: Data, to relativePath: String) throws {
    let destination = root.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(
      at: destination.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try data.write(to: destination)
    writtenPaths.insert(relativePath)
  }

  private func rewriteIntegrity(schemaVersion: String) throws {
    writtenPaths.remove("integrity.json")
    let entries = try writtenPaths.sorted().map { path -> [String: Any] in
      let data = try Data(contentsOf: root.appendingPathComponent(path))
      return [
        "path": path,
        "bytes": data.count,
        "sha256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
      ]
    }
    try writeJSON(
      ["schemaVersion": schemaVersion, "algorithm": "sha256", "files": entries],
      to: "integrity.json"
    )
  }
}
