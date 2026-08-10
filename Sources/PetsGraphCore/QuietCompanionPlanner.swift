import Foundation

public struct QuietCompanionPlanner: Sendable {
  private let graph: GraphDefinition
  private let clips: [String: ClipDefinition]
  private let nodesByID: [String: GraphNode]
  private let outgoingEdges: [String: [GraphEdge]]

  public let defaultNodeID: String

  public init(package: LoadedPetPackage) throws {
    guard package.behavior?.profile == "quiet-sleep-companion" else {
      throw PackageValidationError.invalid("quiet companion behavior is unavailable")
    }
    graph = package.graph
    clips = package.clips
    nodesByID = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0) })
    outgoingEdges = Dictionary(grouping: graph.edges, by: \GraphEdge.from)
      .mapValues { $0.sorted { $0.id < $1.id } }
    defaultNodeID = package.manifest.art.defaultNode
    guard nodesByID[defaultNodeID]?.role == "dwell" else {
      throw PackageValidationError.invalid("quiet companion default node must be a dwell node")
    }
  }

  public func scene(for nodeID: String) -> String? {
    nodesByID[nodeID]?.scene
  }

  public func role(for nodeID: String) -> String? {
    nodesByID[nodeID]?.role
  }

  public func autonomousNodeIDs(scene: String? = nil) -> [String] {
    graph.nodes
      .filter {
        $0.role == "dwell"
          && $0.autonomousEligible == true
          && (scene == nil || $0.scene == scene)
      }
      .map(\.id)
      .sorted()
  }

  public func interactionNodeID(scene: String) throws -> String {
    let matches = graph.nodes.filter { $0.scene == scene && $0.role == "interaction" }
    guard matches.count == 1 else {
      throw PackageValidationError.invalid("scene \(scene) must have one interaction node")
    }
    return matches[0].id
  }

  public func idlePlan(nodeID: String, startFrame: Int = 0) throws -> EngineeringBehaviorPlan {
    let loop = try loopClip(nodeID: nodeID)
    guard loop.frames.indices.contains(startFrame) else {
      throw PackageValidationError.invalid("invalid idle start frame for \(nodeID)")
    }
    return try makePlan(
      id: "quiet-idle-\(nodeID)",
      segments: [
        DemoSegment(clip: loop.id, startFrame: startFrame, cycles: 1, repeatForever: true),
      ],
      finalNodeID: nodeID
    )
  }

  public func sleepChangePlan(
    fromNodeID: String,
    toNodeID: String,
    currentFrame: Int
  ) throws -> EngineeringBehaviorPlan {
    guard
      nodesByID[fromNodeID]?.role == "dwell",
      nodesByID[toNodeID]?.role == "dwell",
      nodesByID[toNodeID]?.autonomousEligible == true
    else {
      throw PackageValidationError.invalid("quiet sleep changes require autonomous dwell nodes")
    }
    if fromNodeID == toNodeID {
      return try idlePlan(nodeID: fromNodeID, startFrame: currentFrame)
    }
    let sameScene = nodesByID[fromNodeID]?.scene == nodesByID[toNodeID]?.scene
    let path = try shortestPath(
      from: fromNodeID,
      to: toNodeID,
      avoidGatewayIntermediates: sameScene
    )
    return try planFollowingPath(
      id: "quiet-sleep-\(fromNodeID)-to-\(toNodeID)",
      fromNodeID: fromNodeID,
      currentFrame: currentFrame,
      path: path,
      finalNodeID: toNodeID
    )
  }

  public func wakeToSceneSitPlan(
    fromSleepNodeID: String,
    currentFrame: Int
  ) throws -> EngineeringBehaviorPlan {
    guard
      nodesByID[fromSleepNodeID]?.role == "dwell",
      let scene = nodesByID[fromSleepNodeID]?.scene
    else {
      throw PackageValidationError.invalid("wake request must start at a dwell node")
    }
    let target = try interactionNodeID(scene: scene)
    let path = try shortestPath(
      from: fromSleepNodeID,
      to: target,
      avoidGatewayIntermediates: false
    )
    return try planFollowingPath(
      id: "quiet-wake-\(fromSleepNodeID)-to-\(target)",
      fromNodeID: fromSleepNodeID,
      currentFrame: currentFrame,
      path: path,
      finalNodeID: target
    )
  }

  public func returnToSceneSleepPlan(
    fromInteractionNodeID: String,
    currentFrame: Int,
    preferredDwellNodeID: String?
  ) throws -> EngineeringBehaviorPlan {
    guard
      nodesByID[fromInteractionNodeID]?.role == "interaction",
      let scene = nodesByID[fromInteractionNodeID]?.scene
    else {
      throw PackageValidationError.invalid("return request must start at an interaction node")
    }
    let candidates = autonomousNodeIDs(scene: scene)
    guard !candidates.isEmpty else {
      throw PackageValidationError.invalid("scene \(scene) has no autonomous sleep nodes")
    }
    let ordered = ([preferredDwellNodeID].compactMap { $0 } + candidates)
      .reduce(into: [String]()) { result, item in
        if !result.contains(item), nodesByID[item]?.scene == scene { result.append(item) }
      }
    for target in ordered {
      if let path = try? shortestPath(
        from: fromInteractionNodeID,
        to: target,
        avoidGatewayIntermediates: false
      ) {
        return try planFollowingPath(
          id: "quiet-return-\(fromInteractionNodeID)-to-\(target)",
          fromNodeID: fromInteractionNodeID,
          currentFrame: currentFrame,
          path: path,
          finalNodeID: target
        )
      }
    }
    throw PackageValidationError.invalid("interaction \(fromInteractionNodeID) cannot return to sleep")
  }

  private func planFollowingPath(
    id: String,
    fromNodeID: String,
    currentFrame: Int,
    path: [GraphEdge],
    finalNodeID: String
  ) throws -> EngineeringBehaviorPlan {
    guard !path.isEmpty else {
      return try idlePlan(nodeID: fromNodeID, startFrame: currentFrame)
    }
    var segments = [try loopExitSegment(nodeID: fromNodeID, startFrame: currentFrame)]
    for (index, edge) in path.enumerated() {
      segments.append(DemoSegment(clip: edge.clip, startFrame: 0, cycles: 1))
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
        segments.append(try loopExitSegment(nodeID: edge.to, startFrame: targetStart))
      }
    }
    let movementDirections = try Set(path.compactMap { edge -> PreviewMovementDirection? in
      guard let clip = clips[edge.clip], clip.rootMotionEndPt[0] > 0.000_001 else {
        return nil
      }
      switch clip.facing {
      case "left": return .left
      case "right": return .right
      default:
        throw PackageValidationError.invalid(
          "moving quiet edge \(edge.id) must face left or right"
        )
      }
    })
    guard movementDirections.count <= 1 else {
      throw PackageValidationError.invalid("one quiet plan cannot mix movement directions")
    }
    return try makePlan(
      id: id,
      segments: segments,
      finalNodeID: finalNodeID,
      movementDirection: movementDirections.first
    )
  }

  private func makePlan(
    id: String,
    segments: [DemoSegment],
    finalNodeID: String,
    movementDirection: PreviewMovementDirection? = nil
  ) throws -> EngineeringBehaviorPlan {
    let sequence = DemoSequence(schemaVersion: "0.2.0", id: id, segments: segments)
    let timeline = try PlaybackTimeline(clips: clips, sequence: sequence)
    return EngineeringBehaviorPlan(
      sequence: sequence,
      finalNodeID: finalNodeID,
      movementDirection: movementDirection,
      mirroredClipIDs: [],
      finiteRootMotionPt: timeline.finiteRootMotionXPt
    )
  }

  private func loopClip(nodeID: String) throws -> ClipDefinition {
    guard
      let node = nodesByID[nodeID],
      let clip = clips[node.loopClip],
      clip.type == "loop"
    else {
      throw PackageValidationError.missing("quiet behavior loop for node \(nodeID)")
    }
    return clip
  }

  private func targetStartFrame(for edge: GraphEdge) throws -> Int {
    let frame = edge.targetStartFrame ?? 0
    let loop = try loopClip(nodeID: edge.to)
    guard loop.frames.indices.contains(frame) else {
      throw PackageValidationError.invalid("edge \(edge.id) has invalid target frame")
    }
    return frame
  }

  private func loopExitSegment(nodeID: String, startFrame: Int) throws -> DemoSegment {
    let loop = try loopClip(nodeID: nodeID)
    guard loop.frames.indices.contains(startFrame) else {
      throw PackageValidationError.invalid("invalid loop phase for \(nodeID)")
    }
    let frameCount = loop.frames.count
    var nearestFrame: Int?
    var nearestDistance: Int?
    for frame in loop.safeExitFrames {
      let distance = (frame - startFrame + frameCount) % frameCount
      if nearestDistance == nil
        || distance < nearestDistance!
        || (distance == nearestDistance! && frame < nearestFrame!)
      {
        nearestFrame = frame
        nearestDistance = distance
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

  private func shortestPath(
    from start: String,
    to target: String,
    avoidGatewayIntermediates: Bool
  ) throws -> [GraphEdge] {
    if start == target { return [] }
    var queue: [(String, [GraphEdge])] = [(start, [])]
    var visited: Set<String> = [start]
    var cursor = 0
    while cursor < queue.count {
      let (node, path) = queue[cursor]
      cursor += 1
      for edge in outgoingEdges[node] ?? [] {
        guard !visited.contains(edge.to) else { continue }
        if edge.to != target, nodesByID[edge.to]?.role == "interaction" {
          continue
        }
        if avoidGatewayIntermediates, edge.to != target, nodesByID[edge.to]?.role == "gateway" {
          continue
        }
        let candidate = path + [edge]
        if edge.to == target { return candidate }
        visited.insert(edge.to)
        queue.append((edge.to, candidate))
      }
    }
    if avoidGatewayIntermediates {
      return try shortestPath(from: start, to: target, avoidGatewayIntermediates: false)
    }
    throw PackageValidationError.invalid("no quiet behavior path from \(start) to \(target)")
  }
}
