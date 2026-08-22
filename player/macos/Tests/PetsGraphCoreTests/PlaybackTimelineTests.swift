import Foundation
import XCTest
@testable import PetsGraphCore

final class PlaybackTimelineTests: XCTestCase {
  func testRotatedCyclePreservesEveryFrameDelta() throws {
    let clip = makeClip(
      id: "walk",
      roots: [0, 2, 5],
      terminal: 9,
      durationMs: 100
    )
    let timeline = try PlaybackTimeline(
      clips: [clip.id: clip],
      sequence: DemoSequence(
        schemaVersion: "0.1.0",
        id: "rotated",
        segments: [
          DemoSegment(clip: clip.id, startFrame: 2, cycles: 1),
        ]
      )
    )

    XCTAssertEqual(timeline.sample(at: 0).sourceFrameIndex, 2)
    XCTAssertEqual(timeline.sample(at: 0.05).rootMotionXPt, 2, accuracy: 0.000_001)
    XCTAssertEqual(timeline.sample(at: 0.1).sourceFrameIndex, 0)
    XCTAssertEqual(timeline.sample(at: 0.3).rootMotionXPt, 9, accuracy: 0.000_001)
  }

  func testDirectSamplingDoesNotAccumulateDroppedFrameError() throws {
    let clip = makeClip(
      id: "run",
      roots: [0, 10, 20, 30],
      terminal: 40,
      durationMs: 100
    )
    let timeline = try PlaybackTimeline(
      clips: [clip.id: clip],
      sequence: DemoSequence(
        schemaVersion: "0.1.0",
        id: "drop",
        segments: [
          DemoSegment(clip: clip.id, startFrame: 0, cycles: 1),
        ]
      )
    )

    _ = timeline.sample(at: 0.04)
    let afterLongGap = timeline.sample(at: 0.34)
    let direct = timeline.sample(at: 0.34)
    XCTAssertEqual(afterLongGap, direct)
    XCTAssertEqual(direct.rootMotionXPt, 34, accuracy: 0.000_001)
    XCTAssertEqual(direct.sourceFrameIndex, 3)
  }

  func testRunningAverageSpeedIsMoreThanDoubleWalking() throws {
    let walk = makeClip(
      id: "walk",
      roots: [0, 7.5, 15, 22.5],
      terminal: 30,
      durationMs: 250
    )
    let run = makeClip(
      id: "run",
      roots: [0, 28.75, 57.5, 86.25],
      terminal: 115,
      durationMs: 250
    )
    let walkSpeed = walk.rootMotionEndPt[0] / clipDuration(walk)
    let runSpeed = run.rootMotionEndPt[0] / clipDuration(run)
    XCTAssertGreaterThan(runSpeed / walkSpeed, 2)
  }
}

private func clipDuration(_ clip: ClipDefinition) -> Double {
  clip.frames.reduce(0) { $0 + $1.durationMs / 1_000 }
}

private func makeClip(
  id: String,
  roots: [Double],
  terminal: Double,
  durationMs: Double
) -> ClipDefinition {
  let frames = roots.enumerated().map { index, root in
    ClipFrame(
      src: "frames/\(id)/\(index).png",
      durationMs: durationMs,
      contentBoundsPx: [0, 0, 1, 1],
      anchorsPx: FrameAnchors(
        root: [0, 0],
        ground: [0, 0],
        head: [0, 0]
      ),
      collision: FrameCollision(
        bodyCoreEllipsePx: [0, 0, 1, 1],
        screenBoundsPx: [0, 0, 1, 1]
      ),
      rootMotionPt: [root, 0]
    )
  }
  return ClipDefinition(
    schemaVersion: "0.1.0",
    id: id,
    type: "loop",
    facing: "right",
    mirrorSafe: false,
    entryPose: id,
    exitPose: id,
    safeExitFrames: [0],
    preloadHints: [],
    rootMotionEndPt: [terminal, 0],
    frames: frames,
    provenance: nil
  )
}
