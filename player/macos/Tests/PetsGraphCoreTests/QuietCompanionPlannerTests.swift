import Foundation
import XCTest
@testable import PetsGraphCore

final class QuietCompanionPlannerTests: XCTestCase {
  func testAutonomousPoolExcludesInteractionAndGatewayNodes() throws {
    let planner = try QuietCompanionPlanner(package: makeQuietPackage())

    XCTAssertEqual(
      planner.autonomousNodeIDs(scene: "floor"),
      ["rest.prone.left", "rest.side.left"]
    )
    XCTAssertEqual(planner.role(for: "sit.front.floor"), "interaction")
    XCTAssertEqual(planner.role(for: "pillow.gateway"), "gateway")
  }

  func testWakeLeavesAtSafeExitAndPreloadsEdgeAndTargetLoop() throws {
    let package = makeQuietPackage()
    let planner = try QuietCompanionPlanner(package: package)
    let plan = try planner.wakeToSceneSitPlan(
      fromSleepNodeID: "rest.side.left",
      currentFrame: 0
    )

    XCTAssertEqual(plan.finalNodeID, "sit.front.floor")
    XCTAssertEqual(plan.sequence.segments.map(\.clip), [
      "side-loop",
      "side-to-sit",
      "sit-loop",
    ])
    XCTAssertEqual(plan.sequence.segments[0].frameCount, 2)
    XCTAssertEqual(plan.sequence.segments[1].startFrame, 0)
    XCTAssertNil(plan.sequence.segments[1].frameCount)
    XCTAssertTrue(plan.sequence.segments[2].repeatForever)
    XCTAssertEqual(plan.finiteRootMotionPt, 0, accuracy: 0.000_001)

    let timeline = try PlaybackTimeline(clips: package.clips, sequence: plan.sequence)
    XCTAssertEqual(
      timeline.clipIDsNear(segmentIndex: 0, lookahead: 2),
      ["side-loop", "side-to-sit", "sit-loop"]
    )
  }

  func testClickReturnUsesPreferredPriorDwellWhenReachable() throws {
    let package = makeQuietPackage()
    let planner = try QuietCompanionPlanner(package: package)
    let plan = try planner.returnToSceneSleepPlan(
      fromInteractionNodeID: "sit.front.floor",
      currentFrame: 0,
      preferredDwellNodeID: "rest.side.left"
    )

    XCTAssertEqual(plan.finalNodeID, "rest.side.left")
    XCTAssertEqual(plan.sequence.segments.map(\.clip), [
      "sit-loop",
      "sit-to-prone",
      "prone-loop",
      "prone-to-side",
      "side-loop",
    ])
    XCTAssertTrue(plan.sequence.segments.last?.repeatForever == true)
    XCTAssertEqual(plan.finiteRootMotionPt, 0, accuracy: 0.000_001)
  }

  func testFinishBeforeRetargetEdgeCannotBeInterrupted() {
    let edge = GraphEdge(
      id: "quiet-edge",
      from: "rest.prone.left",
      to: "sit.front.floor",
      clip: "prone-to-sit",
      kind: "transition",
      interruptPolicy: "finish-before-retarget"
    )

    XCTAssertFalse(edge.allowsInterruption(for: .autonomousBehavior))
    XCTAssertFalse(edge.allowsInterruption(for: .directManipulation))
  }

  func testSceneChangeUsesNativeClipFacingForWindowDirection() throws {
    let planner = try QuietCompanionPlanner(package: makeQuietPackage())

    let enter = try planner.sleepChangePlan(
      fromNodeID: "rest.prone.left",
      toNodeID: "rest.pillow.head",
      currentFrame: 0
    )
    XCTAssertEqual(enter.movementDirection, .right)
    XCTAssertEqual(enter.finiteRootMotionPt, 180, accuracy: 0.000_001)

    let leave = try planner.sleepChangePlan(
      fromNodeID: "rest.pillow.head",
      toNodeID: "rest.prone.left",
      currentFrame: 0
    )
    XCTAssertEqual(leave.movementDirection, .left)
    XCTAssertEqual(leave.finiteRootMotionPt, 180, accuracy: 0.000_001)
  }

  func testAutonomousSleepPathNeverUsesInteractionNodeAsShortcut() throws {
    let planner = try QuietCompanionPlanner(package: makeInteractionShortcutPackage())

    let plan = try planner.sleepChangePlan(
      fromNodeID: "rest.side.left",
      toNodeID: "rest.third.left",
      currentFrame: 0
    )

    XCTAssertEqual(plan.sequence.segments.map(\.clip), [
      "side-loop",
      "side-to-prone",
      "prone-loop",
      "prone-to-third",
      "third-loop",
    ])
    XCTAssertFalse(plan.sequence.segments.map(\.clip).contains("sit-loop"))
    XCTAssertFalse(plan.sequence.segments.map(\.clip).contains("sit-to-third"))
  }
}

private func makeInteractionShortcutPackage() -> LoadedPetPackage {
  let base = makeQuietPackage()
  let thirdNode = GraphNode(
    id: "rest.third.left",
    posture: "third",
    orientation: "left",
    grounded: true,
    stability: "stable",
    scene: "floor",
    role: "dwell",
    autonomousEligible: true,
    props: [],
    loopClip: "third-loop"
  )
  let extraEdges = [
    GraphEdge(
      id: "00-side-to-sit-shortcut",
      from: "rest.side.left",
      to: "sit.front.floor",
      clip: "side-to-sit",
      kind: "transition",
      interruptPolicy: "finish-before-retarget"
    ),
    GraphEdge(
      id: "prone-to-third",
      from: "rest.prone.left",
      to: "rest.third.left",
      clip: "prone-to-third",
      kind: "transition",
      interruptPolicy: "finish-before-retarget"
    ),
    GraphEdge(
      id: "sit-to-third",
      from: "sit.front.floor",
      to: "rest.third.left",
      clip: "sit-to-third",
      kind: "transition",
      interruptPolicy: "finish-before-retarget"
    ),
  ]
  var clips = base.clips
  clips["third-loop"] = quietClip(
    "third-loop",
    type: "loop",
    from: "rest.third.left",
    to: "rest.third.left"
  )
  clips["prone-to-third"] = quietClip(
    "prone-to-third",
    type: "transition",
    from: "rest.prone.left",
    to: "rest.third.left"
  )
  clips["sit-to-third"] = quietClip(
    "sit-to-third",
    type: "transition",
    from: "sit.front.floor",
    to: "rest.third.left"
  )
  return LoadedPetPackage(
    rootURL: base.rootURL,
    manifest: base.manifest,
    graph: GraphDefinition(
      schemaVersion: base.graph.schemaVersion,
      nodes: base.graph.nodes + [thirdNode],
      edges: base.graph.edges + extraEdges
    ),
    behavior: base.behavior,
    clips: clips,
    demoSequence: base.demoSequence
  )
}

private func makeQuietPackage() -> LoadedPetPackage {
  let nodes = [
    GraphNode(
      id: "rest.prone.left",
      posture: "prone",
      orientation: "left",
      grounded: true,
      stability: "stable",
      scene: "floor",
      role: "dwell",
      autonomousEligible: true,
      props: [],
      loopClip: "prone-loop"
    ),
    GraphNode(
      id: "rest.side.left",
      posture: "side",
      orientation: "left",
      grounded: true,
      stability: "stable",
      scene: "floor",
      role: "dwell",
      autonomousEligible: true,
      props: [],
      loopClip: "side-loop"
    ),
    GraphNode(
      id: "sit.front.floor",
      posture: "sit",
      orientation: "front",
      grounded: true,
      stability: "stable",
      scene: "floor",
      role: "interaction",
      autonomousEligible: false,
      props: [],
      loopClip: "sit-loop"
    ),
    GraphNode(
      id: "pillow.gateway",
      posture: "leaning-rest",
      orientation: "right",
      grounded: true,
      stability: "stable",
      scene: "pillow",
      role: "gateway",
      autonomousEligible: false,
      props: ["pillow"],
      loopClip: "gateway-loop"
    ),
    GraphNode(
      id: "rest.pillow.head",
      posture: "head-on-pillow",
      orientation: "left",
      grounded: true,
      stability: "stable",
      scene: "pillow",
      role: "dwell",
      autonomousEligible: true,
      props: ["pillow"],
      loopClip: "pillow-head-loop"
    ),
    GraphNode(
      id: "sit.front.pillow",
      posture: "sit",
      orientation: "front",
      grounded: true,
      stability: "stable",
      scene: "pillow",
      role: "interaction",
      autonomousEligible: false,
      props: ["pillow"],
      loopClip: "pillow-sit-loop"
    ),
  ]
  let edges = [
    GraphEdge(
      id: "prone-to-side",
      from: "rest.prone.left",
      to: "rest.side.left",
      clip: "prone-to-side",
      kind: "transition",
      interruptPolicy: "finish-before-retarget"
    ),
    GraphEdge(
      id: "side-to-prone",
      from: "rest.side.left",
      to: "rest.prone.left",
      clip: "side-to-prone",
      kind: "transition",
      interruptPolicy: "finish-before-retarget"
    ),
    GraphEdge(
      id: "prone-to-sit",
      from: "rest.prone.left",
      to: "sit.front.floor",
      clip: "prone-to-sit",
      kind: "transition",
      interruptPolicy: "finish-before-retarget"
    ),
    GraphEdge(
      id: "side-to-sit",
      from: "rest.side.left",
      to: "sit.front.floor",
      clip: "side-to-sit",
      kind: "transition",
      interruptPolicy: "finish-before-retarget"
    ),
    GraphEdge(
      id: "sit-to-prone",
      from: "sit.front.floor",
      to: "rest.prone.left",
      clip: "sit-to-prone",
      kind: "transition",
      interruptPolicy: "finish-before-retarget"
    ),
    GraphEdge(
      id: "floor-to-pillow-gateway",
      from: "rest.prone.left",
      to: "pillow.gateway",
      clip: "floor-to-pillow-gateway",
      kind: "scene-transition",
      interruptPolicy: "finish-before-retarget",
      sceneChange: "floor-to-pillow"
    ),
    GraphEdge(
      id: "pillow-gateway-to-head",
      from: "pillow.gateway",
      to: "rest.pillow.head",
      clip: "pillow-gateway-to-head",
      kind: "transition",
      interruptPolicy: "finish-before-retarget"
    ),
    GraphEdge(
      id: "pillow-head-to-gateway",
      from: "rest.pillow.head",
      to: "pillow.gateway",
      clip: "pillow-head-to-gateway",
      kind: "transition",
      interruptPolicy: "finish-before-retarget"
    ),
    GraphEdge(
      id: "pillow-gateway-to-floor",
      from: "pillow.gateway",
      to: "rest.prone.left",
      clip: "pillow-gateway-to-floor",
      kind: "scene-transition",
      interruptPolicy: "finish-before-retarget",
      sceneChange: "pillow-to-floor"
    ),
  ]
  var clips: [String: ClipDefinition] = [
    "prone-loop": quietClip("prone-loop", type: "loop", from: "rest.prone.left", to: "rest.prone.left"),
    "side-loop": quietClip("side-loop", type: "loop", from: "rest.side.left", to: "rest.side.left"),
    "sit-loop": quietClip("sit-loop", type: "loop", from: "sit.front.floor", to: "sit.front.floor"),
    "gateway-loop": quietClip("gateway-loop", type: "loop", from: "pillow.gateway", to: "pillow.gateway"),
    "pillow-head-loop": quietClip("pillow-head-loop", type: "loop", from: "rest.pillow.head", to: "rest.pillow.head"),
    "pillow-sit-loop": quietClip("pillow-sit-loop", type: "loop", from: "sit.front.pillow", to: "sit.front.pillow"),
  ]
  for edge in edges {
    if edge.id == "floor-to-pillow-gateway" {
      clips[edge.clip] = movingQuietClip(
        edge.clip,
        from: edge.from,
        to: edge.to,
        facing: "right",
        distance: 180
      )
    } else if edge.id == "pillow-gateway-to-floor" {
      clips[edge.clip] = movingQuietClip(
        edge.clip,
        from: edge.from,
        to: edge.to,
        facing: "left",
        distance: 180
      )
    } else {
      clips[edge.clip] = quietClip(edge.clip, type: "transition", from: edge.from, to: edge.to)
    }
  }
  let behavior = BehaviorDefinition(
    schemaVersion: "0.2.0",
    profile: "quiet-sleep-companion",
    defaultIntent: "sleep",
    timing: BehaviorTiming(
      strategy: "random-long-tail",
      parametersStatus: "runtime-review-pending",
      avoidImmediateRepeat: true,
      minimumDwellSeconds: 150,
      medianDwellSeconds: 420,
      maximumDwellSeconds: 1_200,
      recentHistoryLimit: 2,
      sameSceneProbability: 0.9
    ),
    scenePolicy: [
      "pillow": SceneBehaviorPolicy(
        sticky: true,
        gateway: "pillow.gateway",
        minimumDwellSeconds: 600,
        exitCooldownSeconds: 900
      ),
    ],
    interactions: BehaviorInteractions(
      petClick: PetClickBehavior(
        sleeping: "wake-to-scene-sit",
        sitting: "return-to-scene-sleep"
      ),
      desktopClick: "ignore",
      drag: "direct-manipulation"
    )
  )
  return LoadedPetPackage(
    rootURL: URL(fileURLWithPath: "/tmp/quiet-fixture"),
    manifest: PetPackageManifest(
      schemaVersion: "0.2.0",
      package: PackageIdentity(id: "quiet", version: "0.2.0", createdAt: "2026-08-10T00:00:00+08:00"),
      pet: PetIdentity(id: "wubai", displayName: "五百", species: "cat", identityStyle: "faithful"),
      art: ArtConfiguration(
        canvasPx: [800, 640],
        baseHeightPt: 150,
        coordinateOrigin: "top-left",
        defaultNode: "rest.prone.left",
        groundYPx: 532
      ),
      renderAssets: RenderAssets(mode: "frames", pixelFormat: "rgba8-straight"),
      graph: "graph.json",
      behavior: "behavior.json",
      reviewIndex: "reviews/index.json",
      integrity: "integrity.json"
    ),
    graph: GraphDefinition(schemaVersion: "0.2.0", nodes: nodes, edges: edges),
    behavior: behavior,
    clips: clips,
    demoSequence: DemoSequence(
      schemaVersion: "0.2.0",
      id: "quiet-demo",
      segments: [DemoSegment(clip: "prone-loop", startFrame: 0, cycles: 1, repeatForever: true)]
    )
  )
}

private func movingQuietClip(
  _ id: String,
  from: String,
  to: String,
  facing: String,
  distance: Double
) -> ClipDefinition {
  let base = quietClip(id, type: "transition", from: from, to: to)
  let frames = base.frames.enumerated().map { index, frame in
    ClipFrame(
      src: frame.src,
      durationMs: frame.durationMs,
      contentBoundsPx: frame.contentBoundsPx,
      petBoundsPx: frame.petBoundsPx,
      propBoundsPx: frame.propBoundsPx,
      anchorsPx: frame.anchorsPx,
      collision: frame.collision,
      rootMotionPt: [index == 0 ? 0 : distance / 2, 0]
    )
  }
  return ClipDefinition(
    schemaVersion: "0.2.0",
    id: id,
    type: "transition",
    facing: facing,
    mirrorSafe: false,
    entryPose: from,
    exitPose: to,
    safeExitFrames: [],
    preloadHints: [],
    rootMotionEndPt: [distance, 0],
    frames: frames,
    provenance: nil
  )
}

private func quietClip(
  _ id: String,
  type: String,
  from: String,
  to: String
) -> ClipDefinition {
  let frame = ClipFrame(
    src: "frames/\(id)/0000.png",
    durationMs: 41.666667,
    contentBoundsPx: [100, 100, 300, 300],
    petBoundsPx: [100, 100, 300, 300],
    propBoundsPx: [:],
    anchorsPx: FrameAnchors(root: [400, 532], ground: [400, 532], head: [200, 170]),
    collision: FrameCollision(
      bodyCoreEllipsePx: [150, 180, 200, 140],
      screenBoundsPx: [100, 100, 300, 300],
      petHitEllipsePx: [145, 170, 220, 170]
    ),
    rootMotionPt: [0, 0]
  )
  return ClipDefinition(
    schemaVersion: "0.2.0",
    id: id,
    type: type,
    facing: "left",
    mirrorSafe: false,
    entryPose: from,
    exitPose: to,
    safeExitFrames: type == "loop" ? [1] : [],
    preloadHints: [],
    rootMotionEndPt: [0, 0],
    frames: [frame, frame],
    provenance: nil
  )
}
