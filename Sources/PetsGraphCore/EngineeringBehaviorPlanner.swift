import Foundation

public enum PreviewBehaviorPhase: Equatable, Sendable {
  case sleeping
  case changingSleep
  case active
}

public enum PreviewBehaviorCommandKind: Equatable, Sendable {
  case automaticWake
  case forcedMovement
}

public enum PreviewBehaviorCommandDisposition: Equatable, Sendable {
  case start
  case queue
  case ignore
}

public enum EngineeringBehaviorCommandPolicy {
  public static func disposition(
    phase: PreviewBehaviorPhase,
    command: PreviewBehaviorCommandKind
  ) -> PreviewBehaviorCommandDisposition {
    switch (phase, command) {
    case (.sleeping, _):
      return .start
    case (.changingSleep, _), (.active, .forcedMovement):
      return .queue
    case (.active, .automaticWake):
      return .ignore
    }
  }
}

public enum PreviewMovementGait: String, Sendable {
  case walk
  case run
}

public enum PreviewMovementDirection: String, Sendable {
  case left
  case right

  public var motionSign: Double {
    self == .left ? -1 : 1
  }

  public static func preferredDirection(
    travelPt: Double,
    motionScale: Double,
    availableLeftPt: Double,
    availableRightPt: Double
  ) -> PreviewMovementDirection? {
    let required = abs(travelPt) * motionScale
    let leftFits = availableLeftPt + 0.000_001 >= required
    let rightFits = availableRightPt + 0.000_001 >= required
    switch (leftFits, rightFits) {
    case (true, true):
      return availableLeftPt > availableRightPt ? .left : .right
    case (true, false):
      return .left
    case (false, true):
      return .right
    case (false, false):
      return nil
    }
  }
}

public struct EngineeringBehaviorPlan: Sendable {
  public let sequence: DemoSequence
  public let finalNodeID: String
  public let movementDirection: PreviewMovementDirection?
  public let mirroredClipIDs: Set<String>
  public let finiteRootMotionPt: Double

  public init(
    sequence: DemoSequence,
    finalNodeID: String,
    movementDirection: PreviewMovementDirection?,
    mirroredClipIDs: Set<String>,
    finiteRootMotionPt: Double
  ) {
    self.sequence = sequence
    self.finalNodeID = finalNodeID
    self.movementDirection = movementDirection
    self.mirroredClipIDs = mirroredClipIDs
    self.finiteRootMotionPt = finiteRootMotionPt
  }
}

public struct EngineeringBehaviorPlanner: Sendable {
  private let graph: GraphDefinition
  private let clips: [String: ClipDefinition]
  private let nodesByID: [String: GraphNode]
  private let edgesByID: [String: GraphEdge]
  private let outgoingEdges: [String: [GraphEdge]]

  public init(package: LoadedPetPackage) throws {
    try self.init(graph: package.graph, clips: package.clips)
  }

  public init(
    graph: GraphDefinition,
    clips: [String: ClipDefinition]
  ) throws {
    self.graph = graph
    self.clips = clips
    nodesByID = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0) })
    edgesByID = Dictionary(uniqueKeysWithValues: graph.edges.map { ($0.id, $0) })
    outgoingEdges = Dictionary(grouping: graph.edges, by: \GraphEdge.from)
      .mapValues { $0.sorted { $0.id < $1.id } }

    guard nodesByID.count == graph.nodes.count, edgesByID.count == graph.edges.count else {
      throw PackageValidationError.invalid("behavior planner requires unique graph ids")
    }
    for node in graph.nodes {
      guard clips[node.loopClip]?.type == "loop" else {
        throw PackageValidationError.invalid(
          "behavior planner node \(node.id) has no loop"
        )
      }
    }
  }

  public func idlePlan(
    nodeID: String,
    startFrame: Int = 0
  ) throws -> EngineeringBehaviorPlan {
    let loop = try loopClip(nodeID: nodeID)
    guard loop.frames.indices.contains(startFrame) else {
      throw PackageValidationError.invalid("invalid idle start frame for \(nodeID)")
    }
    return try makePlan(
      id: "engineering-idle-\(nodeID)",
      segments: [
        DemoSegment(
          clip: loop.id,
          startFrame: startFrame,
          cycles: 1,
          repeatForever: true
        ),
      ],
      finalNodeID: nodeID,
      direction: nil
    )
  }

  public func wakeToSitPlan(
    fromSleepNodeID: String,
    currentFrame: Int
  ) throws -> EngineeringBehaviorPlan {
    guard fromSleepNodeID.hasPrefix("rest.") else {
      throw PackageValidationError.invalid("wake-to-sit must start from a rest node")
    }
    var segments = [
      try loopExitSegment(nodeID: fromSleepNodeID, startFrame: currentFrame),
    ]
    let sleepPath = try shortestPath(from: fromSleepNodeID, to: "rest.prone.left")
    for edge in sleepPath {
      segments.append(edgeSegment(edge))
      segments.append(
        try loopExitSegment(
          nodeID: edge.to,
          startFrame: try targetStartFrame(for: edge)
        )
      )
    }

    let proneToSit = try edge(id: "prone-left-to-sit-front")
    segments.append(edgeSegment(proneToSit))
    let sitLoop = try loopClip(nodeID: proneToSit.to)
    segments.append(
      DemoSegment(
        clip: sitLoop.id,
        startFrame: try targetStartFrame(for: proneToSit),
        cycles: 1,
        repeatForever: true
      )
    )
    return try makePlan(
      id: "engineering-wake-to-sit",
      segments: segments,
      finalNodeID: "sit.front",
      direction: nil
    )
  }

  public func sitToSleepPlan(currentFrame: Int) throws -> EngineeringBehaviorPlan {
    var segments = [
      try loopExitSegment(nodeID: "sit.front", startFrame: currentFrame),
    ]
    let sitToProne = try edge(id: "sit-front-to-prone-left")
    segments.append(edgeSegment(sitToProne))
    let proneLoop = try loopClip(nodeID: sitToProne.to)
    segments.append(
      DemoSegment(
        clip: proneLoop.id,
        startFrame: try targetStartFrame(for: sitToProne),
        cycles: 1,
        repeatForever: true
      )
    )
    return try makePlan(
      id: "engineering-sit-to-sleep",
      segments: segments,
      finalNodeID: "rest.prone.left",
      direction: nil
    )
  }

  public func sitMovementPlan(
    currentFrame: Int,
    gait: PreviewMovementGait,
    direction: PreviewMovementDirection,
    walkCycles: Int = 1,
    runCycles: Int = 1
  ) throws -> EngineeringBehaviorPlan {
    guard walkCycles > 0, runCycles > 0 else {
      throw PackageValidationError.invalid("movement cycles must be positive")
    }
    var segments = [
      try loopExitSegment(nodeID: "sit.front", startFrame: currentFrame),
    ]
    let usesNativeLeft = direction == .left
    let sitToWalk = try edge(
      id: usesNativeLeft
        ? "sit-front-to-walk-left-strict-side-low-tail-v2"
        : "sit-front-to-walk-right"
    )
    segments.append(edgeSegment(sitToWalk))
    let walkStart = try targetStartFrame(for: sitToWalk)
    let walkNodeID = sitToWalk.to

    if gait == .run {
      segments.append(
        try loopExitSegment(nodeID: walkNodeID, startFrame: walkStart)
      )
      let walkToRun = try edge(
        id: usesNativeLeft
          ? "walk-left-strict-side-to-run-left-native-v1"
          : "walk-right-to-run-right"
      )
      segments.append(edgeSegment(walkToRun))
      segments.append(
        contentsOf: try loopCycleSegmentsEndingAtSafeExit(
          nodeID: walkToRun.to,
          startFrame: try targetStartFrame(for: walkToRun),
          cycles: runCycles
        )
      )

      let runToWalk = try edge(
        id: usesNativeLeft
          ? "run-left-native-to-walk-left-strict-side-v1"
          : "run-right-to-walk-right"
      )
      segments.append(edgeSegment(runToWalk))
      segments.append(
        try loopExitSegment(
          nodeID: runToWalk.to,
          startFrame: try targetStartFrame(for: runToWalk)
        )
      )
    } else {
      segments.append(
        contentsOf: try loopCycleSegmentsEndingAtSafeExit(
          nodeID: walkNodeID,
          startFrame: walkStart,
          cycles: walkCycles
        )
      )
    }

    let sitStartFrame: Int
    if usesNativeLeft {
      let walkToSit = try edge(id: "walk-left-strict-side-to-sit-front-v2")
      segments.append(edgeSegment(walkToSit))
      sitStartFrame = try targetStartFrame(for: walkToSit)
    } else {
      let walkToStand = try edge(id: "walk-right-to-stand-right")
      segments.append(edgeSegment(walkToStand))
      segments.append(
        try loopExitSegment(
          nodeID: walkToStand.to,
          startFrame: try targetStartFrame(for: walkToStand)
        )
      )
      let standToSit = try edge(id: "stand-right-to-sit-front")
      segments.append(edgeSegment(standToSit))
      sitStartFrame = try targetStartFrame(for: standToSit)
    }
    let sitLoop = try loopClip(nodeID: "sit.front")
    segments.append(
      DemoSegment(
        clip: sitLoop.id,
        startFrame: sitStartFrame,
        cycles: 1,
        repeatForever: true
      )
    )

    return try makePlan(
      id: "engineering-sit-move-\(gait.rawValue)-\(direction.rawValue)",
      segments: segments,
      finalNodeID: "sit.front",
      direction: direction
    )
  }

  public func wakePlan(
    fromSleepNodeID: String,
    currentFrame: Int,
    gait: PreviewMovementGait,
    direction: PreviewMovementDirection,
    sitCycles: Int = 3,
    walkCycles: Int = 3
  ) throws -> EngineeringBehaviorPlan {
    guard fromSleepNodeID.hasPrefix("rest."), sitCycles > 0, walkCycles > 0 else {
      throw PackageValidationError.invalid("invalid engineering wake request")
    }

    var segments = [try loopExitSegment(nodeID: fromSleepNodeID, startFrame: currentFrame)]
    let sleepPath = try shortestPath(from: fromSleepNodeID, to: "rest.prone.left")
    for edge in sleepPath {
      segments.append(edgeSegment(edge))
      segments.append(
        try loopExitSegment(
          nodeID: edge.to,
          startFrame: try targetStartFrame(for: edge)
        )
      )
    }

    let proneToSit = try edge(id: "prone-left-to-sit-front")
    segments.append(edgeSegment(proneToSit))
    segments.append(
      try loopExitSegment(
        nodeID: proneToSit.to,
        startFrame: try targetStartFrame(for: proneToSit)
      )
    )

    let usesNativeLeft = direction == .left
    let sitToWalk = try edge(
      id: usesNativeLeft
        ? "sit-front-to-walk-left-strict-side-low-tail-v2"
        : "sit-front-to-walk-right"
    )
    segments.append(edgeSegment(sitToWalk))
    let walkStart = try targetStartFrame(for: sitToWalk)
    let walkNodeID = sitToWalk.to

    if gait == .run {
      segments.append(
        try loopExitSegment(nodeID: walkNodeID, startFrame: walkStart)
      )
      let walkToRun = try edge(
        id: usesNativeLeft
          ? "walk-left-strict-side-to-run-left-native-v1"
          : "walk-right-to-run-right"
      )
      segments.append(edgeSegment(walkToRun))
      segments.append(
        try loopExitSegment(
          nodeID: walkToRun.to,
          startFrame: try targetStartFrame(for: walkToRun)
        )
      )
      let runToWalk = try edge(
        id: usesNativeLeft
          ? "run-left-native-to-walk-left-strict-side-v1"
          : "run-right-to-walk-right"
      )
      segments.append(edgeSegment(runToWalk))
      segments.append(
        try loopExitSegment(
          nodeID: runToWalk.to,
          startFrame: try targetStartFrame(for: runToWalk)
        )
      )
    } else {
      segments.append(
        contentsOf: try loopCycleSegmentsEndingAtSafeExit(
          nodeID: walkNodeID,
          startFrame: walkStart,
          cycles: walkCycles
        )
      )
    }

    let sitStartFrame: Int
    if usesNativeLeft {
      let walkToSit = try edge(id: "walk-left-strict-side-to-sit-front-v2")
      segments.append(edgeSegment(walkToSit))
      sitStartFrame = try targetStartFrame(for: walkToSit)
    } else {
      let walkToStand = try edge(id: "walk-right-to-stand-right")
      segments.append(edgeSegment(walkToStand))
      segments.append(
        try loopExitSegment(
          nodeID: walkToStand.to,
          startFrame: try targetStartFrame(for: walkToStand)
        )
      )
      let standToSit = try edge(id: "stand-right-to-sit-front")
      segments.append(edgeSegment(standToSit))
      sitStartFrame = try targetStartFrame(for: standToSit)
    }
    segments.append(
      contentsOf: try loopCycleSegmentsEndingAtSafeExit(
        nodeID: "sit.front",
        startFrame: sitStartFrame,
        cycles: sitCycles
      )
    )

    let sitToProne = try edge(id: "sit-front-to-prone-left")
    segments.append(edgeSegment(sitToProne))
    let proneLoop = try loopClip(nodeID: sitToProne.to)
    segments.append(
      DemoSegment(
        clip: proneLoop.id,
        startFrame: try targetStartFrame(for: sitToProne),
        cycles: 1,
        repeatForever: true
      )
    )

    return try makePlan(
      id: "engineering-wake-\(gait.rawValue)-\(direction.rawValue)",
      segments: segments,
      finalNodeID: "rest.prone.left",
      direction: direction
    )
  }

  public func sleepChangePlan(
    fromNodeID: String,
    toNodeID: String,
    currentFrame: Int
  ) throws -> EngineeringBehaviorPlan {
    guard fromNodeID.hasPrefix("rest."), toNodeID.hasPrefix("rest.") else {
      throw PackageValidationError.invalid("sleep changes must stay inside rest nodes")
    }
    if fromNodeID == toNodeID {
      return try idlePlan(nodeID: fromNodeID, startFrame: currentFrame)
    }

    var segments = [try loopExitSegment(nodeID: fromNodeID, startFrame: currentFrame)]
    let path = try shortestPath(from: fromNodeID, to: toNodeID)
    for (index, edge) in path.enumerated() {
      segments.append(edgeSegment(edge))
      let targetStart = try targetStartFrame(for: edge)
      if index == path.count - 1 {
        let loop = try loopClip(nodeID: edge.to)
        segments.append(
          DemoSegment(
            clip: loop.id,
            startFrame: targetStart,
            cycles: 1,
            repeatForever: true
          )
        )
      } else {
        segments.append(
          try loopExitSegment(nodeID: edge.to, startFrame: targetStart)
        )
      }
    }
    return try makePlan(
      id: "engineering-sleep-\(fromNodeID)-to-\(toNodeID)",
      segments: segments,
      finalNodeID: toNodeID,
      direction: nil
    )
  }

  public func sleepNeighborNodeIDs(from nodeID: String) -> [String] {
    (outgoingEdges[nodeID] ?? [])
      .map(\.to)
      .filter { $0.hasPrefix("rest.") }
  }

  public func nodeID(forLoopClip clipID: String) -> String? {
    graph.nodes.first(where: { $0.loopClip == clipID })?.id
  }

  private func makePlan(
    id: String,
    segments: [DemoSegment],
    finalNodeID: String,
    direction: PreviewMovementDirection?
  ) throws -> EngineeringBehaviorPlan {
    let sequence = DemoSequence(schemaVersion: "0.1.0", id: id, segments: segments)
    let timeline = try PlaybackTimeline(clips: clips, sequence: sequence)
    let mirrored: Set<String>
    if direction == .left {
      mirrored = Set(
        segments.compactMap { segment in
          clips[segment.clip]?.facing == "right" ? segment.clip : nil
        }
      )
    } else {
      mirrored = []
    }
    return EngineeringBehaviorPlan(
      sequence: sequence,
      finalNodeID: finalNodeID,
      movementDirection: direction,
      mirroredClipIDs: mirrored,
      finiteRootMotionPt: timeline.finiteRootMotionXPt
    )
  }

  private func edge(id: String) throws -> GraphEdge {
    guard let edge = edgesByID[id] else {
      throw PackageValidationError.missing("behavior graph edge \(id)")
    }
    return edge
  }

  private func edgeSegment(_ edge: GraphEdge) -> DemoSegment {
    DemoSegment(clip: edge.clip, startFrame: 0, cycles: 1)
  }

  private func loopClip(nodeID: String) throws -> ClipDefinition {
    guard
      let node = nodesByID[nodeID],
      let clip = clips[node.loopClip],
      clip.type == "loop"
    else {
      throw PackageValidationError.missing("behavior loop for node \(nodeID)")
    }
    return clip
  }

  private func targetStartFrame(for edge: GraphEdge) throws -> Int {
    let start = edge.targetStartFrame ?? 0
    let loop = try loopClip(nodeID: edge.to)
    guard loop.frames.indices.contains(start) else {
      throw PackageValidationError.invalid(
        "edge \(edge.id) target frame \(start) is outside \(loop.id)"
      )
    }
    return start
  }

  private func loopExitSegment(
    nodeID: String,
    startFrame: Int
  ) throws -> DemoSegment {
    let loop = try loopClip(nodeID: nodeID)
    guard loop.frames.indices.contains(startFrame) else {
      throw PackageValidationError.invalid("invalid loop phase for \(nodeID)")
    }
    let frameCount = loop.frames.count
    var nearestDistance: Int?
    var nearestFrame: Int?
    for safeFrame in loop.safeExitFrames {
      let distance = (safeFrame - startFrame + frameCount) % frameCount
      if nearestDistance == nil
        || distance < nearestDistance!
        || (distance == nearestDistance! && safeFrame < nearestFrame!)
      {
        nearestDistance = distance
        nearestFrame = safeFrame
      }
    }
    guard let nearestDistance, nearestFrame != nil else {
      throw PackageValidationError.invalid("loop \(loop.id) has no safe exit")
    }
    return DemoSegment(
      clip: loop.id,
      startFrame: startFrame,
      cycles: 1,
      frameCount: nearestDistance + 1
    )
  }

  private func assertSafeExit(
    _ segment: DemoSegment,
    clip: ClipDefinition
  ) throws {
    let count = segment.frameCount ?? clip.frames.count
    let finalFrame = (segment.startFrame + count - 1) % clip.frames.count
    guard clip.safeExitFrames.contains(finalFrame) else {
      throw PackageValidationError.invalid(
        "behavior segment leaves \(clip.id) at unsafe frame \(finalFrame)"
      )
    }
  }

  private func loopCycleSegmentsEndingAtSafeExit(
    nodeID: String,
    startFrame: Int,
    cycles: Int
  ) throws -> [DemoSegment] {
    guard cycles > 0 else {
      throw PackageValidationError.invalid("loop cycles must be positive")
    }
    let loop = try loopClip(nodeID: nodeID)
    guard loop.frames.indices.contains(startFrame) else {
      throw PackageValidationError.invalid("invalid loop phase for \(nodeID)")
    }

    let naturalFinalFrame = (
      startFrame + loop.frames.count * cycles - 1
    ) % loop.frames.count
    if loop.safeExitFrames.contains(naturalFinalFrame) {
      let segment = DemoSegment(
        clip: loop.id,
        startFrame: startFrame,
        cycles: cycles
      )
      try assertSafeExit(segment, clip: loop)
      return [segment]
    }

    let firstExit = try loopExitSegment(
      nodeID: nodeID,
      startFrame: startFrame
    )
    guard cycles > 1 else {
      return [firstExit]
    }
    let firstCount = firstExit.frameCount ?? loop.frames.count
    let firstFinalFrame = (
      firstExit.startFrame + firstCount - 1
    ) % loop.frames.count
    let alignedStartFrame = (firstFinalFrame + 1) % loop.frames.count
    let aligned = DemoSegment(
      clip: loop.id,
      startFrame: alignedStartFrame,
      cycles: cycles - 1
    )
    try assertSafeExit(aligned, clip: loop)
    return [firstExit, aligned]
  }

  private func shortestPath(
    from start: String,
    to target: String
  ) throws -> [GraphEdge] {
    if start == target {
      return []
    }
    var queue: [(String, [GraphEdge])] = [(start, [])]
    var visited: Set<String> = [start]
    var cursor = 0
    while cursor < queue.count {
      let (node, path) = queue[cursor]
      cursor += 1
      for edge in outgoingEdges[node] ?? [] {
        guard edge.to.hasPrefix("rest."), !visited.contains(edge.to) else {
          continue
        }
        let candidate = path + [edge]
        if edge.to == target {
          return candidate
        }
        visited.insert(edge.to)
        queue.append((edge.to, candidate))
      }
    }
    throw PackageValidationError.invalid("no behavior path from \(start) to \(target)")
  }
}
