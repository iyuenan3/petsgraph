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

private final class SleepPackageFixture: @unchecked Sendable {
  let root: URL
  private var writtenPaths = Set<String>()

  init() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("petsgraph-sleep-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    root = directory.resolvingSymlinksInPath()
    try build()
  }

  func remove() {
    try? FileManager.default.removeItem(at: root)
  }

  private func build() throws {
    let clips: [[String: Any]] = [
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
    for clip in clips {
      try writeJSON(clip, to: "clips/\(clip["id"] as! String).json")
    }

    try writeJSON(
      [
        "schemaVersion": "0.1.0",
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
          "defaultNode": "rest.prone.left",
          "groundYPx": 266,
        ],
        "renderAssets": ["mode": "frames", "pixelFormat": "rgba8-straight"],
        "graph": "graph.json",
        "reviewIndex": "reviews/index.json",
        "integrity": "integrity.json",
      ],
      to: "package.json"
    )
    try writeJSON(
      [
        "schemaVersion": "0.1.0",
        "nodes": [
          [
            "id": "rest.prone.left",
            "posture": "prone",
            "orientation": "left",
            "grounded": true,
            "stability": "stable",
            "loopClip": "prone-left-loop-v1",
          ],
          [
            "id": "rest.side-curled.left",
            "posture": "side-curled",
            "orientation": "left",
            "grounded": true,
            "stability": "stable",
            "loopClip": "side-curled-left-loop-v1",
          ],
        ],
        "edges": [
          [
            "id": "prone-left-to-side-curled-left",
            "from": "rest.prone.left",
            "to": "rest.side-curled.left",
            "clip": "prone-left-to-side-curled-left-v1",
            "kind": "transition",
            "interruptPolicy": "direct-manipulation-only",
          ],
          [
            "id": "side-curled-left-to-prone-left",
            "from": "rest.side-curled.left",
            "to": "rest.prone.left",
            "clip": "side-curled-left-to-prone-left-v1",
            "kind": "transition",
            "interruptPolicy": "direct-manipulation-only",
          ],
        ],
      ],
      to: "graph.json"
    )
    try writeJSON(
      [
        "schemaVersion": "0.1.0",
        "id": "sleep-test-chain",
        "segments": [
          segment("prone-left-loop-v1", cycles: 3),
          segment("prone-left-to-side-curled-left-v1"),
          segment("side-curled-left-loop-v1", cycles: 3),
          segment("side-curled-left-to-prone-left-v1"),
          segment("prone-left-loop-v1", repeatForever: true),
        ],
      ],
      to: "demo-sequence.json"
    )
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
      ["schemaVersion": "0.1.0", "algorithm": "sha256", "files": entries],
      to: "integrity.json"
    )
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
}
