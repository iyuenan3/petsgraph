import XCTest
@testable import PetsGraphCore

final class GraphPhaseTests: XCTestCase {
  func testPartialRotatedLoopStopsOnTheApprovedExitPhase() throws {
    let clip = makePhaseClip(frameCount: 27)
    let timeline = try PlaybackTimeline(
      clips: [clip.id: clip],
      sequence: DemoSequence(
        schemaVersion: "0.1.0",
        id: "phase-exit",
        segments: [
          DemoSegment(
            clip: clip.id,
            startFrame: 24,
            cycles: 1,
            frameCount: 25
          ),
        ]
      )
    )

    XCTAssertEqual(timeline.sample(at: 0).sourceFrameIndex, 24)
    XCTAssertEqual(timeline.sample(at: 0.999).sourceFrameIndex, 21)
  }

  func testPackageClipResolutionComesFromGraphReferences() throws {
    let graph = GraphDefinition(
      schemaVersion: "0.1.0",
      nodes: [
        GraphNode(
          id: "stand.right",
          posture: "stand",
          orientation: "right",
          grounded: true,
          stability: "stable",
          loopClip: "stand-right-loop-v1"
        ),
        GraphNode(
          id: "gait.walk.right",
          posture: "walk",
          orientation: "right",
          grounded: true,
          stability: "cyclic",
          loopClip: "walk-right-loop-v1"
        ),
      ],
      edges: [
        GraphEdge(
          id: "stand-right-to-walk-right",
          from: "stand.right",
          to: "gait.walk.right",
          clip: "stand-right-to-walk-right-v4",
          kind: "locomotion-transition",
          interruptPolicy: "direct-manipulation-only"
        ),
      ]
    )

    XCTAssertEqual(try PetPackageLoader.requiredClipIDs(from: graph), [
      "stand-right-loop-v1",
      "stand-right-to-walk-right-v4",
      "walk-right-loop-v1",
    ])
  }
}

private func makePhaseClip(frameCount: Int) -> ClipDefinition {
  let frames = (0..<frameCount).map { index in
    ClipFrame(
      src: "frames/phase/\(index).png",
      durationMs: 40,
      contentBoundsPx: [0, 0, 1, 1],
      anchorsPx: FrameAnchors(root: [0, 0], ground: [0, 0], head: [0, 0]),
      collision: FrameCollision(
        bodyCoreEllipsePx: [0, 0, 1, 1],
        screenBoundsPx: [0, 0, 1, 1]
      ),
      rootMotionPt: [Double(index), 0]
    )
  }
  return ClipDefinition(
    schemaVersion: "0.1.0",
    id: "phase",
    type: "loop",
    facing: "right",
    mirrorSafe: false,
    entryPose: "gait.walk.right",
    exitPose: "gait.walk.right",
    safeExitFrames: [21, 22],
    preloadHints: [],
    rootMotionEndPt: [Double(frameCount), 0],
    frames: frames,
    provenance: nil
  )
}
