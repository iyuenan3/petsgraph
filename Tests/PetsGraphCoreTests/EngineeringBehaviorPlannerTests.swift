import Foundation
import XCTest
@testable import PetsGraphCore

final class EngineeringBehaviorPlannerTests: XCTestCase {
  func testForcedMovementQueuesInsteadOfDisappearingDuringActiveChains() {
    XCTAssertEqual(
      EngineeringBehaviorCommandPolicy.disposition(
        phase: .active,
        command: .forcedMovement
      ),
      .queue
    )
    XCTAssertEqual(
      EngineeringBehaviorCommandPolicy.disposition(
        phase: .changingSleep,
        command: .forcedMovement
      ),
      .queue
    )
    XCTAssertEqual(
      EngineeringBehaviorCommandPolicy.disposition(
        phase: .sleeping,
        command: .forcedMovement
      ),
      .start
    )
    XCTAssertEqual(
      EngineeringBehaviorCommandPolicy.disposition(
        phase: .active,
        command: .automaticWake
      ),
      .ignore
    )
  }

  func testMidRunDragCannotCarryTheWindowOffscreen() {
    let clamped = PreviewHorizontalPlacement.resolve(
      calculatedX: 189.88,
      manualOffsetX: -502.62,
      minimumX: 0,
      maximumX: 1_906
    )
    XCTAssertEqual(clamped.originX, 0, accuracy: 0.000_001)
    XCTAssertEqual(clamped.rebasedManualOffsetX, -189.88, accuracy: 0.000_001)
    XCTAssertTrue(clamped.hitBoundary)

    let nextRightwardFrame = PreviewHorizontalPlacement.resolve(
      calculatedX: 199.88,
      manualOffsetX: clamped.rebasedManualOffsetX,
      minimumX: 0,
      maximumX: 1_906
    )
    XCTAssertEqual(nextRightwardFrame.originX, 10, accuracy: 0.000_001)
    XCTAssertFalse(nextRightwardFrame.hitBoundary)
  }

  func testDistancePlannerChoosesClosestWholeMotionCycle() {
    XCTAssertEqual(
      PreviewMovementDistancePlanner.selectCycles(
        targetDistancePt: 410,
        firstCycleDistancePt: 110,
        additionalCycleDistancePt: 100
      ),
      PreviewMovementCycleSelection(cycles: 4, plannedDistancePt: 410)
    )
    XCTAssertEqual(
      PreviewMovementDistancePlanner.selectCycles(
        targetDistancePt: 20,
        firstCycleDistancePt: 110,
        additionalCycleDistancePt: 100
      ),
      PreviewMovementCycleSelection(cycles: 1, plannedDistancePt: 110)
    )
    XCTAssertEqual(
      PreviewMovementDistancePlanner.selectCycles(
        targetDistancePt: 10_000,
        firstCycleDistancePt: 110,
        additionalCycleDistancePt: 100,
        maximumCycles: 3
      ),
      PreviewMovementCycleSelection(cycles: 3, plannedDistancePt: 310)
    )
  }

  func testDestinationClicksAreAcceptedOnlyWhileSitting() {
    XCTAssertTrue(PreviewDestinationClickPolicy.acceptsClick(during: .sitting))
    XCTAssertFalse(PreviewDestinationClickPolicy.acceptsClick(during: .moving))
    XCTAssertFalse(PreviewDestinationClickPolicy.acceptsClick(during: .unavailable))

    XCTAssertEqual(
      PreviewDestinationPlanner.resolve(
        targetX: 300,
        currentPetCenterX: 1_100
      ),
      PreviewDestinationResolution(direction: .left, distancePt: 800)
    )
    XCTAssertEqual(
      PreviewDestinationPlanner.resolve(
        targetX: 300,
        currentPetCenterX: 340
      ),
      PreviewDestinationResolution(direction: .left, distancePt: 40)
    )
    XCTAssertNil(
      PreviewDestinationPlanner.resolve(
        targetX: 300,
        currentPetCenterX: 325
      )
    )
  }

  func testWakeStopsAtSitAndPetClickCanReturnToSleep() throws {
    let fixture = makeBehaviorFixture()
    let planner = try EngineeringBehaviorPlanner(
      graph: fixture.graph,
      clips: fixture.clips
    )

    let wake = try planner.wakeToSitPlan(
      fromSleepNodeID: "rest.side-curled.left",
      currentFrame: 2
    )
    XCTAssertEqual(wake.finalNodeID, "sit.front")
    XCTAssertEqual(wake.sequence.segments.map(\.clip), [
      "side-curled-loop",
      "side-curled-left-to-prone-left",
      "prone-loop",
      "prone-left-to-sit-front",
      "sit-loop",
    ])
    XCTAssertTrue(wake.sequence.segments.last?.repeatForever == true)
    XCTAssertEqual(wake.finiteRootMotionPt, 0, accuracy: 0.000_001)

    let sleep = try planner.sitToSleepPlan(currentFrame: 2)
    XCTAssertEqual(sleep.finalNodeID, "rest.prone.left")
    XCTAssertEqual(sleep.sequence.segments.map(\.clip), [
      "sit-loop",
      "sit-front-to-prone-left",
      "prone-loop",
    ])
    XCTAssertTrue(sleep.sequence.segments.last?.repeatForever == true)
    XCTAssertEqual(sleep.finiteRootMotionPt, 0, accuracy: 0.000_001)
  }

  func testSitMovementReturnsToSitAndRunCyclesIncreaseDistance() throws {
    let fixture = makeBehaviorFixture()
    let planner = try EngineeringBehaviorPlanner(
      graph: fixture.graph,
      clips: fixture.clips
    )

    let walk = try planner.sitMovementPlan(
      currentFrame: 2,
      gait: .walk,
      direction: .left,
      walkCycles: 3
    )
    XCTAssertEqual(walk.finalNodeID, "sit.front")
    XCTAssertEqual(walk.movementDirection, .left)
    XCTAssertEqual(walk.sequence.segments.map(\.clip), [
      "sit-loop",
      "sit-front-to-walk-left-strict-side-low-tail-v2",
      "walk-left-loop",
      "walk-left-loop",
      "walk-left-strict-side-to-sit-front-v2",
      "sit-loop",
    ])
    XCTAssertEqual(walk.sequence.segments[2].frameCount, 4)
    XCTAssertEqual(walk.sequence.segments[3].cycles, 2)
    XCTAssertTrue(walk.sequence.segments.last?.repeatForever == true)
    XCTAssertTrue(walk.mirroredClipIDs.isEmpty)

    let runOnce = try planner.sitMovementPlan(
      currentFrame: 2,
      gait: .run,
      direction: .right,
      runCycles: 1
    )
    let runTwice = try planner.sitMovementPlan(
      currentFrame: 2,
      gait: .run,
      direction: .right,
      runCycles: 2
    )
    XCTAssertGreaterThan(runTwice.finiteRootMotionPt, runOnce.finiteRootMotionPt)
    XCTAssertTrue(
      runTwice.sequence.segments.map(\.clip).contains("walk-right-to-run-right")
    )
    XCTAssertTrue(runTwice.sequence.segments.map(\.clip).contains("run-loop"))
    XCTAssertTrue(
      runTwice.sequence.segments.map(\.clip).contains("run-right-to-walk-right")
    )
    XCTAssertEqual(runTwice.finalNodeID, "sit.front")
    XCTAssertTrue(runTwice.sequence.segments.last?.repeatForever == true)
  }

  func testWakePlanUsesDirectedEdgesAndLeavesEveryLoopAtSafeExit() throws {
    let fixture = makeBehaviorFixture()
    let planner = try EngineeringBehaviorPlanner(
      graph: fixture.graph,
      clips: fixture.clips
    )

    let plan = try planner.wakePlan(
      fromSleepNodeID: "rest.side-curled.left",
      currentFrame: 2,
      gait: .walk,
      direction: .left,
      sitCycles: 2,
      walkCycles: 2
    )

    XCTAssertEqual(plan.finalNodeID, "rest.prone.left")
    XCTAssertEqual(plan.movementDirection, .left)
    XCTAssertEqual(plan.sequence.segments.map(\.clip), [
      "side-curled-loop",
      "side-curled-left-to-prone-left",
      "prone-loop",
      "prone-left-to-sit-front",
      "sit-loop",
      "sit-front-to-walk-left-strict-side-low-tail-v2",
      "walk-left-loop",
      "walk-left-loop",
      "walk-left-strict-side-to-sit-front-v2",
      "sit-loop",
      "sit-loop",
      "sit-front-to-prone-left",
      "prone-loop",
    ])
    XCTAssertTrue(plan.sequence.segments.last?.repeatForever == true)

    for (index, segment) in plan.sequence.segments.enumerated().dropLast() {
      let clip = try XCTUnwrap(fixture.clips[segment.clip])
      if clip.type == "transition" {
        XCTAssertEqual(segment.startFrame, 0)
        XCTAssertEqual(segment.cycles, 1)
        XCTAssertNil(segment.frameCount)
      }
      guard
        clip.type == "loop",
        plan.sequence.segments[index + 1].clip != clip.id
      else {
        continue
      }
      let count = segment.frameCount ?? clip.frames.count
      let finalFrame = (segment.startFrame + count - 1) % clip.frames.count
      XCTAssertTrue(
        clip.safeExitFrames.contains(finalFrame),
        "\(clip.id) left at unsafe frame \(finalFrame)"
      )
    }

    XCTAssertTrue(plan.mirroredClipIDs.isEmpty)
  }

  func testRunPlanPreservesApprovedTargetPhasesAndTravelsFarther() throws {
    let fixture = makeBehaviorFixture()
    let planner = try EngineeringBehaviorPlanner(
      graph: fixture.graph,
      clips: fixture.clips
    )
    let walk = try planner.wakePlan(
      fromSleepNodeID: "rest.prone.left",
      currentFrame: 1,
      gait: .walk,
      direction: .right,
      sitCycles: 1,
      walkCycles: 1
    )
    let run = try planner.wakePlan(
      fromSleepNodeID: "rest.prone.left",
      currentFrame: 1,
      gait: .run,
      direction: .right,
      sitCycles: 1,
      walkCycles: 1
    )

    XCTAssertGreaterThan(run.finiteRootMotionPt, walk.finiteRootMotionPt)
    XCTAssertTrue(run.sequence.segments.map(\.clip).contains("walk-right-to-run-right"))
    XCTAssertTrue(run.sequence.segments.map(\.clip).contains("run-loop"))
    XCTAssertTrue(run.sequence.segments.map(\.clip).contains("run-right-to-walk-right"))

    let segments = run.sequence.segments
    let walkAfterSit = try XCTUnwrap(
      segments.firstIndex(where: { $0.clip == "sit-front-to-walk-right" })
    ) + 1
    XCTAssertEqual(segments[walkAfterSit].clip, "walk-loop")
    XCTAssertEqual(segments[walkAfterSit].startFrame, 3)

    let runAfterEdge = try XCTUnwrap(
      segments.firstIndex(where: { $0.clip == "walk-right-to-run-right" })
    ) + 1
    XCTAssertEqual(segments[runAfterEdge].clip, "run-loop")
    XCTAssertEqual(segments[runAfterEdge].startFrame, 4)

    let walkAfterRun = try XCTUnwrap(
      segments.firstIndex(where: { $0.clip == "run-right-to-walk-right" })
    ) + 1
    XCTAssertEqual(segments[walkAfterRun].clip, "walk-loop")
    XCTAssertEqual(segments[walkAfterRun].startFrame, 2)
  }

  func testNativeLeftRunUsesOnlyNativeClipsAndReturnsDirectlyToSit() throws {
    let fixture = makeBehaviorFixture()
    let planner = try EngineeringBehaviorPlanner(
      graph: fixture.graph,
      clips: fixture.clips
    )

    let plan = try planner.sitMovementPlan(
      currentFrame: 2,
      gait: .run,
      direction: .left,
      runCycles: 2
    )

    XCTAssertEqual(plan.sequence.segments.map(\.clip), [
      "sit-loop",
      "sit-front-to-walk-left-strict-side-low-tail-v2",
      "walk-left-loop",
      "walk-left-strict-side-to-run-left-native-v1",
      "run-left-loop",
      "run-left-loop",
      "run-left-native-to-walk-left-strict-side-v1",
      "walk-left-loop",
      "walk-left-strict-side-to-sit-front-v2",
      "sit-loop",
    ])
    XCTAssertTrue(plan.mirroredClipIDs.isEmpty)
    XCTAssertEqual(plan.finalNodeID, "sit.front")
    XCTAssertGreaterThan(plan.finiteRootMotionPt, 0)
    XCTAssertTrue(plan.sequence.segments.last?.repeatForever == true)

    for (index, segment) in plan.sequence.segments.enumerated().dropLast() {
      let clip = try XCTUnwrap(fixture.clips[segment.clip])
      guard
        clip.type == "loop",
        plan.sequence.segments[index + 1].clip != clip.id
      else {
        continue
      }
      let count = segment.frameCount ?? clip.frames.count * segment.cycles
      let finalFrame = (segment.startFrame + count - 1) % clip.frames.count
      XCTAssertTrue(
        clip.safeExitFrames.contains(finalFrame),
        "\(clip.id) left at unsafe frame \(finalFrame)"
      )
    }
  }

  func testSleepChangeUsesTheGraphAndEndsInTargetLoop() throws {
    let fixture = makeBehaviorFixture()
    let planner = try EngineeringBehaviorPlanner(
      graph: fixture.graph,
      clips: fixture.clips
    )
    let plan = try planner.sleepChangePlan(
      fromNodeID: "rest.side-curled.left",
      toNodeID: "rest.prone.left",
      currentFrame: 1
    )

    XCTAssertEqual(plan.sequence.segments.map(\.clip), [
      "side-curled-loop",
      "side-curled-left-to-prone-left",
      "prone-loop",
    ])
    XCTAssertEqual(plan.finalNodeID, "rest.prone.left")
    XCTAssertTrue(plan.sequence.segments.last?.repeatForever == true)
    XCTAssertEqual(plan.finiteRootMotionPt, 0, accuracy: 0.000_001)
  }

  func testDirectionSelectionRequiresTheWholeBrakingPathToFit() {
    XCTAssertEqual(
      PreviewMovementDirection.preferredDirection(
        travelPt: 800,
        motionScale: 1,
        availableLeftPt: 900,
        availableRightPt: 600
      ),
      .left
    )
    XCTAssertEqual(
      PreviewMovementDirection.preferredDirection(
        travelPt: 400,
        motionScale: 1,
        availableLeftPt: 500,
        availableRightPt: 700
      ),
      .right
    )
    XCTAssertNil(
      PreviewMovementDirection.preferredDirection(
        travelPt: 800,
        motionScale: 1,
        availableLeftPt: 700,
        availableRightPt: 799
      )
    )
  }
}

private struct BehaviorFixture {
  let graph: GraphDefinition
  let clips: [String: ClipDefinition]
}

private func makeBehaviorFixture() -> BehaviorFixture {
  let nodes = [
    node("rest.side-curled.left", loop: "side-curled-loop", posture: "side-curled"),
    node("rest.prone.left", loop: "prone-loop", posture: "prone"),
    node("sit.front", loop: "sit-loop", posture: "sit"),
    node("gait.walk.right", loop: "walk-loop", posture: "walk"),
    node("gait.run.right", loop: "run-loop", posture: "run"),
    node(
      "gait.walk.left.strict-side-low-tail",
      loop: "walk-left-loop",
      posture: "walk"
    ),
    node(
      "gait.run.left.native-strict-side",
      loop: "run-left-loop",
      posture: "run"
    ),
    node("stand.right", loop: "stand-loop", posture: "stand"),
  ]
  let edges = [
    edge("side-curled-left-to-prone-left", from: "rest.side-curled.left", to: "rest.prone.left"),
    edge("prone-left-to-sit-front", from: "rest.prone.left", to: "sit.front", target: 1),
    edge("sit-front-to-walk-right", from: "sit.front", to: "gait.walk.right", target: 3),
    edge("walk-right-to-run-right", from: "gait.walk.right", to: "gait.run.right", target: 4),
    edge("run-right-to-walk-right", from: "gait.run.right", to: "gait.walk.right", target: 2),
    edge("walk-right-to-stand-right", from: "gait.walk.right", to: "stand.right", target: 1),
    edge("stand-right-to-sit-front", from: "stand.right", to: "sit.front", target: 0),
    edge(
      "sit-front-to-walk-left-strict-side-low-tail-v2",
      from: "sit.front",
      to: "gait.walk.left.strict-side-low-tail",
      target: 1
    ),
    edge(
      "walk-left-strict-side-to-run-left-native-v1",
      from: "gait.walk.left.strict-side-low-tail",
      to: "gait.run.left.native-strict-side",
      target: 1
    ),
    edge(
      "run-left-native-to-walk-left-strict-side-v1",
      from: "gait.run.left.native-strict-side",
      to: "gait.walk.left.strict-side-low-tail",
      target: 1
    ),
    edge(
      "walk-left-strict-side-to-sit-front-v2",
      from: "gait.walk.left.strict-side-low-tail",
      to: "sit.front",
      target: 1
    ),
    edge("sit-front-to-prone-left", from: "sit.front", to: "rest.prone.left", target: 1),
  ]

  let loops = [
    loop("side-curled-loop", pose: "rest.side-curled.left", frames: 5, safe: 4),
    loop("prone-loop", pose: "rest.prone.left", frames: 4, safe: 3),
    loop("sit-loop", pose: "sit.front", frames: 6, safe: 5, facing: "front"),
    loop("walk-loop", pose: "gait.walk.right", frames: 5, safe: 2, facing: "right", motion: 25),
    loop("run-loop", pose: "gait.run.right", frames: 6, safe: 2, facing: "right", motion: 90),
    loop(
      "walk-left-loop",
      pose: "gait.walk.left.strict-side-low-tail",
      frames: 5,
      safe: 4,
      facing: "left",
      motion: 25
    ),
    loop(
      "run-left-loop",
      pose: "gait.run.left.native-strict-side",
      frames: 4,
      safe: 3,
      facing: "left",
      motion: 90
    ),
    loop("stand-loop", pose: "stand.right", frames: 4, safe: 3, facing: "right"),
  ]
  let transitions = edges.map { definition in
    transition(
      definition.clip,
      from: definition.from,
      to: definition.to,
      facing: definition.from.hasSuffix("right") || definition.to.hasSuffix("right")
        ? "right" : "left",
      motion: [
        "sit-front-to-walk-right",
        "walk-right-to-run-right",
        "run-right-to-walk-right",
        "walk-right-to-stand-right",
        "sit-front-to-walk-left-strict-side-low-tail-v2",
        "walk-left-strict-side-to-run-left-native-v1",
        "run-left-native-to-walk-left-strict-side-v1",
        "walk-left-strict-side-to-sit-front-v2",
      ]
        .contains(definition.id) ? 20 : 0
    )
  }
  return BehaviorFixture(
    graph: GraphDefinition(schemaVersion: "0.1.0", nodes: nodes, edges: edges),
    clips: Dictionary(uniqueKeysWithValues: (loops + transitions).map { ($0.id, $0) })
  )
}

private func node(
  _ id: String,
  loop: String,
  posture: String
) -> GraphNode {
  GraphNode(
    id: id,
    posture: posture,
    orientation: id.contains(".right") ? "right" : (id.contains(".left") ? "left" : "front"),
    grounded: true,
    stability: posture == "walk" || posture == "run" ? "cyclic" : "stable",
    loopClip: loop
  )
}

private func edge(
  _ id: String,
  from: String,
  to: String,
  target: Int = 0
) -> GraphEdge {
  GraphEdge(
    id: id,
    from: from,
    to: to,
    clip: id,
    kind: id.contains("walk") || id.contains("run") ? "locomotion-transition" : "transition",
    interruptPolicy: "direct-manipulation-only",
    targetStartFrame: target
  )
}

private func loop(
  _ id: String,
  pose: String,
  frames: Int,
  safe: Int,
  facing: String = "left",
  motion: Double = 0
) -> ClipDefinition {
  let samples = (0..<frames).map { index in
    motion * Double(index) / Double(frames)
  }
  return clip(
    id,
    type: "loop",
    facing: facing,
    from: pose,
    to: pose,
    roots: samples,
    terminal: motion,
    safe: [safe]
  )
}

private func transition(
  _ id: String,
  from: String,
  to: String,
  facing: String,
  motion: Double
) -> ClipDefinition {
  clip(
    id,
    type: "transition",
    facing: facing,
    from: from,
    to: to,
    roots: [0, motion / 2],
    terminal: motion,
    safe: []
  )
}

private func clip(
  _ id: String,
  type: String,
  facing: String,
  from: String,
  to: String,
  roots: [Double],
  terminal: Double,
  safe: [Int]
) -> ClipDefinition {
  ClipDefinition(
    schemaVersion: "0.1.0",
    id: id,
    type: type,
    facing: facing,
    mirrorSafe: false,
    entryPose: from,
    exitPose: to,
    safeExitFrames: safe,
    preloadHints: [],
    rootMotionEndPt: [terminal, 0],
    frames: roots.map { root in
      ClipFrame(
        src: "frames/\(id)/0.png",
        durationMs: 100,
        contentBoundsPx: [0, 0, 1, 1],
        anchorsPx: FrameAnchors(root: [0, 0], ground: [0, 0], head: [0, 0]),
        collision: FrameCollision(
          bodyCoreEllipsePx: [0, 0, 1, 1],
          screenBoundsPx: [0, 0, 1, 1]
        ),
        rootMotionPt: [root, 0]
      )
    },
    provenance: nil
  )
}
