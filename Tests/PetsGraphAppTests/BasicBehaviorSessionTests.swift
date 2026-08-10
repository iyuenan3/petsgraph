import Foundation
import XCTest
@testable import PetsGraphApp
@testable import PetsGraphCore

final class BasicBehaviorSessionTests: XCTestCase {
  func testQuietCompanionStartsAtPhysicalBottomLeft() {
    let placement = PetStartupPlacement.bottomLeft(
      screenFrame: CGRect(x: -2_056, y: -1_329, width: 2_056, height: 1_329),
      groundFromWindowBottomPt: 25.3125
    )

    XCTAssertEqual(placement.x, -2_056, accuracy: 0.000_001)
    XCTAssertEqual(placement.y, -1_354.3125, accuracy: 0.000_001)
    XCTAssertEqual(placement.y + 25.3125, -1_329, accuracy: 0.000_001)
  }

  @MainActor
  func testQuietPetClickDebouncesAndDoesNotReverseDuringWakeTransition() throws {
    let session = try BasicBehaviorSession(
      package: makeQuietAppPackage(),
      accelerated: false
    )
    session.start(at: 0)

    XCTAssertEqual(try session.handlePetClick(at: 0.1), .wakeStarted)
    XCTAssertEqual(try session.handlePetClick(at: 0.2), .debounced)
    XCTAssertEqual(try session.handlePetClick(at: 1.0), .transitionInProgress)

    let sitting = try session.update(
      at: 10,
      motionScale: 1,
      currentPetCenterX: 400
    )
    XCTAssertEqual(sitting.interactionState, .sitting)

    let stillSitting = try session.update(
      at: 1_000,
      motionScale: 1,
      currentPetCenterX: 400
    )
    XCTAssertEqual(stillSitting.interactionState, .sitting)
  }

  @MainActor
  func testQuietSittingClickReturnsToSleepAndRejectsLocomotion() throws {
    let session = try BasicBehaviorSession(
      package: makeQuietAppPackage(),
      accelerated: false
    )
    session.start(at: 0)
    XCTAssertEqual(try session.handlePetClick(at: 0.1), .wakeStarted)
    _ = try session.update(at: 10, motionScale: 1, currentPetCenterX: 400)

    XCTAssertEqual(
      try session.requestDestination(
        targetX: 800,
        currentPetCenterX: 400,
        at: 10.1,
        motionScale: 1
      ),
      .unavailable
    )
    XCTAssertEqual(
      try session.forceMovement(
        .run,
        at: 10.1,
        motionScale: 1,
        availableLeftPt: 500,
        availableRightPt: 500
      ),
      .unavailable
    )
    XCTAssertEqual(try session.handlePetClick(at: 10.1), .sleepStarted)
    XCTAssertEqual(try session.handlePetClick(at: 10.2), .debounced)

    let sleeping = try session.update(
      at: 20,
      motionScale: 1,
      currentPetCenterX: 400
    )
    XCTAssertEqual(sleeping.interactionState, .sleeping)
    XCTAssertEqual(sleeping.totalRootMotionXPt, 0, accuracy: 0.000_001)
  }

  @MainActor
  func testSelectingNamedSleepPoseStartsAndQueuesWithoutInterruptingTransitions() throws {
    let session = try BasicBehaviorSession(
      package: makeQuietAppPackage(),
      accelerated: false
    )
    session.start(at: 0)

    XCTAssertEqual(
      try session.selectSleepPose(nodeID: "rest.side-curled.left", at: 0.1),
      .started
    )
    XCTAssertEqual(
      try session.selectSleepPose(nodeID: "rest.prone.left", at: 0.2),
      .queued
    )

    let returning = try session.update(at: 10, motionScale: 1, currentPetCenterX: 400)
    XCTAssertEqual(returning.interactionState, .sleeping)
    XCTAssertEqual(returning.sample.clipID, "side-loop")

    let returned = try session.update(at: 20, motionScale: 1, currentPetCenterX: 400)
    XCTAssertEqual(returned.interactionState, .sleeping)
    XCTAssertEqual(returned.sample.clipID, "prone-loop")
  }

  @MainActor
  func testSelectingNamedSleepPoseWhileSittingReturnsThenChangesPose() throws {
    let session = try BasicBehaviorSession(
      package: makeQuietAppPackage(),
      accelerated: false
    )
    session.start(at: 0)
    XCTAssertEqual(try session.handlePetClick(at: 0.1), .wakeStarted)
    _ = try session.update(at: 10, motionScale: 1, currentPetCenterX: 400)

    XCTAssertEqual(
      try session.selectSleepPose(nodeID: "rest.side-curled.left", at: 10.1),
      .started
    )
    let changing = try session.update(at: 20, motionScale: 1, currentPetCenterX: 400)
    XCTAssertEqual(changing.interactionState, .sleeping)
    XCTAssertEqual(changing.sample.clipID, "prone-loop")

    let transition = try session.update(at: 20.1, motionScale: 1, currentPetCenterX: 400)
    XCTAssertEqual(transition.interactionState, .sleeping)
    XCTAssertEqual(transition.sample.clipID, "prone-to-side")

    let selected = try session.update(at: 30, motionScale: 1, currentPetCenterX: 400)
    XCTAssertEqual(selected.interactionState, .sleeping)
    XCTAssertEqual(selected.sample.clipID, "side-loop")
  }

  func testMenuCatalogUsesChinesePoseNamesAndNeverExposesClipIDs() {
    let package = makeQuietAppPackage()
    let catalog = QuietCompanionMenuCatalog(graph: package.graph)

    XCTAssertEqual(catalog.sleepPoses.map(\.displayName), ["趴卧", "左侧蜷卧"])
    XCTAssertEqual(catalog.statusTitle(forClipID: "prone-loop"), "当前睡姿：趴卧")
    XCTAssertEqual(catalog.statusTitle(forClipID: "prone-to-side"), "正在切换到：左侧蜷卧")
    XCTAssertEqual(catalog.statusTitle(forClipID: "prone-to-sit"), "正在起身")
    XCTAssertFalse(catalog.statusTitle(forClipID: "prone-loop").contains("prone-loop"))
  }
}

private func makeQuietAppPackage() -> LoadedPetPackage {
  let proneNode = GraphNode(
    id: "rest.prone.left",
    displayName: "趴卧",
    posture: "prone",
    orientation: "left",
    grounded: true,
    stability: "stable",
    scene: "floor",
    role: "dwell",
    autonomousEligible: true,
    props: [],
    loopClip: "prone-loop"
  )
  let sideCurledNode = GraphNode(
    id: "rest.side-curled.left",
    displayName: "左侧蜷卧",
    posture: "side-curled",
    orientation: "left",
    grounded: true,
    stability: "stable",
    scene: "floor",
    role: "dwell",
    autonomousEligible: true,
    props: [],
    loopClip: "side-loop"
  )
  let sitNode = GraphNode(
    id: "sit.front.floor",
    displayName: "正面坐好",
    posture: "sit",
    orientation: "front",
    grounded: true,
    stability: "stable",
    scene: "floor",
    role: "interaction",
    autonomousEligible: false,
    props: [],
    loopClip: "sit-loop"
  )
  let edges = [
    GraphEdge(
      id: "prone-to-side",
      from: proneNode.id,
      to: sideCurledNode.id,
      clip: "prone-to-side",
      kind: "transition",
      interruptPolicy: "finish-before-retarget",
      targetStartFrame: 0
    ),
    GraphEdge(
      id: "side-to-prone",
      from: sideCurledNode.id,
      to: proneNode.id,
      clip: "side-to-prone",
      kind: "transition",
      interruptPolicy: "finish-before-retarget",
      targetStartFrame: 0
    ),
    GraphEdge(
      id: "prone-to-sit",
      from: proneNode.id,
      to: sitNode.id,
      clip: "prone-to-sit",
      kind: "transition",
      interruptPolicy: "finish-before-retarget",
      targetStartFrame: 0
    ),
    GraphEdge(
      id: "sit-to-prone",
      from: sitNode.id,
      to: proneNode.id,
      clip: "sit-to-prone",
      kind: "transition",
      interruptPolicy: "finish-before-retarget",
      targetStartFrame: 0
    ),
  ]
  let clips = [
    "prone-loop": quietAppClip(
      "prone-loop",
      type: "loop",
      from: proneNode.id,
      to: proneNode.id
    ),
    "sit-loop": quietAppClip(
      "sit-loop",
      type: "loop",
      from: sitNode.id,
      to: sitNode.id
    ),
    "side-loop": quietAppClip(
      "side-loop",
      type: "loop",
      from: sideCurledNode.id,
      to: sideCurledNode.id
    ),
    "prone-to-side": quietAppClip(
      "prone-to-side",
      type: "transition",
      from: proneNode.id,
      to: sideCurledNode.id
    ),
    "side-to-prone": quietAppClip(
      "side-to-prone",
      type: "transition",
      from: sideCurledNode.id,
      to: proneNode.id
    ),
    "prone-to-sit": quietAppClip(
      "prone-to-sit",
      type: "transition",
      from: proneNode.id,
      to: sitNode.id
    ),
    "sit-to-prone": quietAppClip(
      "sit-to-prone",
      type: "transition",
      from: sitNode.id,
      to: proneNode.id
    ),
  ]
  let behavior = BehaviorDefinition(
    schemaVersion: "0.2.0",
    profile: "quiet-sleep-companion",
    defaultIntent: "sleep",
    timing: BehaviorTiming(
      strategy: "random-long-tail",
      parametersStatus: "test",
      avoidImmediateRepeat: true,
      minimumDwellSeconds: 180,
      medianDwellSeconds: 480,
      maximumDwellSeconds: 1_800,
      recentHistoryLimit: 2,
      sameSceneProbability: 0.9
    ),
    scenePolicy: [
      "floor": SceneBehaviorPolicy(
        sticky: true,
        gateway: nil,
        minimumDwellSeconds: 900,
        exitCooldownSeconds: 1_800
      ),
    ],
    interactions: BehaviorInteractions(
      petClick: PetClickBehavior(
        sleeping: "wake-to-scene-sit",
        sitting: "return-to-scene-sleep",
        debounceSeconds: 0.35
      ),
      desktopClick: "ignore",
      drag: "direct-manipulation"
    )
  )
  return LoadedPetPackage(
    rootURL: URL(fileURLWithPath: "/tmp/petsgraph-app-test"),
    manifest: PetPackageManifest(
      schemaVersion: "0.2.0",
      package: PackageIdentity(
        id: "quiet-app-test",
        version: "0.2.0-test",
        createdAt: "2026-08-10T00:00:00+08:00"
      ),
      pet: PetIdentity(
        id: "wubai",
        displayName: "五百",
        species: "cat",
        identityStyle: "faithful"
      ),
      art: ArtConfiguration(
        canvasPx: [800, 640],
        baseHeightPt: 150,
        coordinateOrigin: "top-left",
        defaultNode: proneNode.id,
        groundYPx: 532
      ),
      renderAssets: RenderAssets(mode: "frames", pixelFormat: "rgba8-straight"),
      graph: "graph.json",
      behavior: "behavior.json",
      reviewIndex: "reviews/index.json",
      integrity: "integrity.json"
    ),
    graph: GraphDefinition(
      schemaVersion: "0.2.0",
      nodes: [proneNode, sideCurledNode, sitNode],
      edges: edges
    ),
    behavior: behavior,
    clips: clips,
    demoSequence: DemoSequence(
      schemaVersion: "0.2.0",
      id: "quiet-app-test",
      segments: [
        DemoSegment(
          clip: "prone-loop",
          startFrame: 0,
          cycles: 1,
          repeatForever: true
        ),
      ]
    )
  )
}

private func quietAppClip(
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
    anchorsPx: FrameAnchors(
      root: [400, 532],
      ground: [400, 532],
      head: [200, 170]
    ),
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
    facing: type == "loop" && from.hasPrefix("sit.") ? "front" : "left",
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
