import Foundation

public struct PetPlaybackPresentation: Equatable, Sendable {
  public let clipID: String
  public let frameIndex: Int
  public let currentNodeID: String
  public let isTransition: Bool
  public let preloadClipIDs: [String]
}

public final class PassiveBehaviorSession: @unchecked Sendable {
  private let package: LoadedPetPack
  private let nodes: [String: PetGraphNode]
  private let outgoing: [String: [PetGraphEdge]]
  private let eligibleNodes: [PetGraphNode]
  private var random: SplitMix64

  private var currentNodeID: String
  private var currentClipID: String
  private var segmentStartedAt: TimeInterval
  private var dwellDeadline: TimeInterval
  private var pendingEdges: [PetGraphEdge] = []
  private var scheduledExitAt: TimeInterval?
  private var hiddenRequested = false
  private var paused = false
  private var frozenFrameIndex = 0

  public init(package: LoadedPetPack, startedAt: TimeInterval, seed: UInt64? = nil) throws {
    self.package = package
    nodes = Dictionary(uniqueKeysWithValues: package.graph.nodes.map { ($0.id, $0) })
    outgoing = Dictionary(grouping: package.graph.edges, by: \.from).mapValues {
      $0.sorted { $0.id < $1.id }
    }
    eligibleNodes = package.graph.nodes.filter(\.autonomousEligible).sorted { $0.id < $1.id }
    currentNodeID = package.manifest.stage.defaultNode
    guard let initialLoop = nodes[currentNodeID]?.loopClip else {
      throw PetPackError("invalid_graph", "default node has no loop clip")
    }
    currentClipID = initialLoop
    segmentStartedAt = startedAt
    random = SplitMix64(
      seed: seed
        ?? (Self.seed(from: package.archiveSHA256) ^ UInt64.random(in: UInt64.min...UInt64.max))
    )
    dwellDeadline = startedAt
    dwellDeadline =
      try startedAt
      + Self.randomDwell(
        behavior: package.behavior,
        nodeID: currentNodeID,
        random: &random
      )
  }

  public var isPaused: Bool { paused }
  public var isTransitioning: Bool { package.clips[currentClipID]?.type == "transition" }
  public var shouldTickWhenHidden: Bool { hiddenRequested && !paused }
  public var currentStableNodeID: String { currentNodeID }

  public func cancelPlannedTransition(at now: TimeInterval) throws {
    guard now.isFinite, !isTransitioning else {
      throw PetPackError(
        "invalid_transition_state", "only a planned dwell transition can be cancelled")
    }
    pendingEdges.removeAll()
    scheduledExitAt = nil
    dwellDeadline =
      try now
      + Self.randomDwell(
        behavior: package.behavior,
        nodeID: currentNodeID,
        random: &random
      )
  }

  public func setVisible(_ visible: Bool, at now: TimeInterval) throws {
    if visible {
      hiddenRequested = false
      if paused {
        paused = false
        segmentStartedAt = now
        scheduledExitAt = nil
        pendingEdges.removeAll()
        frozenFrameIndex = 0
        dwellDeadline =
          try now
          + Self.randomDwell(
            behavior: package.behavior,
            nodeID: currentNodeID,
            random: &random
          )
      }
      return
    }

    _ = try update(at: now)
    hiddenRequested = true
    if !isTransitioning {
      pauseAtStableNode(now: now)
    }
  }

  public func update(at now: TimeInterval) throws -> PetPlaybackPresentation {
    guard now.isFinite else { throw PetPackError("invalid_time", "runtime time is not finite") }
    if paused {
      return presentation(frameIndex: frozenFrameIndex)
    }

    try advanceCompletedSegments(now: now)
    if !isTransitioning, !hiddenRequested {
      if pendingEdges.isEmpty, now >= dwellDeadline {
        try planNextTarget(now: now)
      }
      if let exitAt = scheduledExitAt, now >= exitAt, let edge = pendingEdges.first {
        pendingEdges.removeFirst()
        scheduledExitAt = nil
        currentClipID = edge.clip
        segmentStartedAt = exitAt
        try advanceCompletedSegments(now: now)
      }
    }

    let clip = try currentClip()
    let elapsed = max(0, now - segmentStartedAt)
    return presentation(frameIndex: Self.frameIndex(for: clip, elapsed: elapsed))
  }

  private func advanceCompletedSegments(now: TimeInterval) throws {
    var safety = 0
    while isTransitioning {
      safety += 1
      guard safety <= package.graph.edges.count + 1 else {
        throw PetPackError("behavior_cycle", "transition advancement exceeded the graph budget")
      }
      let clip = try currentClip()
      let completedAt = segmentStartedAt + clip.durationSeconds
      guard now >= completedAt else { return }
      guard let edge = package.graph.edges.first(where: { $0.clip == clip.id }) else {
        throw PetPackError("invalid_graph", "transition clip has no graph edge")
      }
      currentNodeID = edge.to
      guard let node = nodes[currentNodeID] else {
        throw PetPackError("invalid_graph", "transition reached an unknown node")
      }
      if node.role == "gateway" {
        guard let next = pendingEdges.first, next.from == node.id else {
          throw PetPackError("invalid_graph", "transition path stopped at a gateway")
        }
        pendingEdges.removeFirst()
        currentClipID = next.clip
        segmentStartedAt = completedAt
        continue
      }
      guard let loop = node.loopClip else {
        throw PetPackError("invalid_graph", "dwell node has no loop")
      }
      currentClipID = loop
      segmentStartedAt = completedAt
      if hiddenRequested {
        pendingEdges.removeAll()
        scheduledExitAt = nil
        pauseAtStableNode(now: completedAt)
        return
      }
      if let next = pendingEdges.first {
        guard next.from == node.id else {
          throw PetPackError("invalid_graph", "planned path is discontinuous")
        }
        scheduledExitAt = try nextSafeExit(after: completedAt, now: completedAt)
      } else {
        dwellDeadline =
          try completedAt
          + Self.randomDwell(
            behavior: package.behavior,
            nodeID: currentNodeID,
            random: &random
          )
      }
      return
    }
  }

  private func planNextTarget(now: TimeInterval) throws {
    guard eligibleNodes.count > 1 else {
      dwellDeadline =
        try now
        + Self.randomDwell(
          behavior: package.behavior,
          nodeID: currentNodeID,
          random: &random
        )
      return
    }
    let candidates = eligibleNodes.filter {
      !package.behavior.timing.avoidImmediateRepeat || $0.id != currentNodeID
    }
    let target = try weightedTarget(from: candidates)
    let path = try shortestPath(from: currentNodeID, to: target.id)
    if path.isEmpty {
      dwellDeadline =
        try now
        + Self.randomDwell(
          behavior: package.behavior,
          nodeID: currentNodeID,
          random: &random
        )
      return
    }
    pendingEdges = path
    scheduledExitAt = try nextSafeExit(after: segmentStartedAt, now: now)
  }

  private func weightedTarget(from candidates: [PetGraphNode]) throws -> PetGraphNode {
    let logarithmic = candidates.map { node -> (PetGraphNode, Double) in
      let nodeWeight = package.behavior.nodeWeights[node.id] ?? 1
      let sceneWeight = package.behavior.sceneWeights[node.scene] ?? 1
      return (node, log(nodeWeight) + log(sceneWeight))
    }
    guard let maximum = logarithmic.map(\.1).max(), maximum.isFinite else {
      throw PetPackError("invalid_behavior", "autonomous target weights are invalid")
    }
    let weighted = logarithmic.map { ($0.0, exp($0.1 - maximum)) }
    let total = weighted.reduce(0) { $0 + $1.1 }
    guard total.isFinite, total > 0 else {
      throw PetPackError("invalid_behavior", "autonomous target weights are invalid")
    }
    var selection = random.nextUnit() * total
    for item in weighted {
      selection -= item.1
      if selection < 0 { return item.0 }
    }
    return weighted.last!.0
  }

  private func shortestPath(from source: String, to target: String) throws -> [PetGraphEdge] {
    var frontier = [source]
    var visited: Set<String> = [source]
    var predecessor: [String: PetGraphEdge] = [:]
    while !frontier.isEmpty {
      let current = frontier.removeFirst()
      for edge in outgoing[current, default: []] where visited.insert(edge.to).inserted {
        predecessor[edge.to] = edge
        if edge.to == target {
          var result: [PetGraphEdge] = []
          var cursor = target
          while cursor != source {
            guard let prior = predecessor[cursor] else {
              throw PetPackError("invalid_graph", "cannot reconstruct autonomous path")
            }
            result.append(prior)
            cursor = prior.from
          }
          return result.reversed()
        }
        frontier.append(edge.to)
      }
    }
    return []
  }

  private func nextSafeExit(after loopStartedAt: TimeInterval, now: TimeInterval) throws
    -> TimeInterval
  {
    let clip = try currentClip()
    guard clip.type == "loop", !clip.safeExitFrames.isEmpty else {
      throw PetPackError("invalid_safe_exit", "current dwell loop has no safe exit")
    }
    let frameDuration = Double(clip.frameRate.denominator) / Double(clip.frameRate.numerator)
    let cycleDuration = Double(clip.frameCount) * frameDuration
    let elapsed = max(0, now - loopStartedAt)
    let firstCycle = max(0, Int(floor(elapsed / cycleDuration)))
    for cycle in firstCycle...(firstCycle + 1) {
      for frame in clip.safeExitFrames {
        let boundary =
          loopStartedAt + Double(cycle) * cycleDuration
          + Double(frame + 1) * frameDuration
        if boundary > now + 0.000_000_1 { return boundary }
      }
    }
    throw PetPackError("invalid_safe_exit", "could not schedule a safe loop exit")
  }

  private func pauseAtStableNode(now: TimeInterval) {
    paused = true
    pendingEdges.removeAll()
    scheduledExitAt = nil
    let clip = package.clips[currentClipID]
    let elapsed = max(0, now - segmentStartedAt)
    frozenFrameIndex = clip.map { Self.frameIndex(for: $0, elapsed: elapsed) } ?? 0
  }

  private func currentClip() throws -> PetClip {
    guard let clip = package.clips[currentClipID] else {
      throw PetPackError("missing_clip", "behavior references a missing clip")
    }
    return clip
  }

  private func presentation(frameIndex: Int) -> PetPlaybackPresentation {
    var preload: [String] = []
    preload.append(contentsOf: pendingEdges.map(\.clip))
    if let last = pendingEdges.last, let loop = nodes[last.to]?.loopClip { preload.append(loop) }
    return PetPlaybackPresentation(
      clipID: currentClipID,
      frameIndex: frameIndex,
      currentNodeID: currentNodeID,
      isTransition: isTransitioning,
      preloadClipIDs: Array(Set(preload)).sorted()
    )
  }

  private static func randomDwell(
    behavior: PetBehavior,
    nodeID: String,
    random: inout SplitMix64
  ) throws -> TimeInterval {
    guard let range = behavior.timing.dwellRangesSeconds[nodeID], range.count == 2 else {
      throw PetPackError("invalid_behavior", "current node has no dwell range")
    }
    return range[0] + (range[1] - range[0]) * random.nextUnit()
  }

  private static func frameIndex(for clip: PetClip, elapsed: TimeInterval) -> Int {
    let boundedElapsed =
      clip.type == "loop" ? elapsed.truncatingRemainder(dividingBy: clip.durationSeconds) : elapsed
    let raw = Int(floor(boundedElapsed * clip.frameRate.framesPerSecond))
    return min(max(0, raw), clip.frameCount - 1)
  }

  private static func seed(from digest: String) -> UInt64 {
    UInt64(digest.prefix(16), radix: 16) ?? 0x5045_5453_4752_4150
  }
}

private struct SplitMix64 {
  private var state: UInt64

  init(seed: UInt64) { state = seed }

  mutating func next() -> UInt64 {
    state &+= 0x9e37_79b9_7f4a_7c15
    var value = state
    value = (value ^ (value >> 30)) &* 0xbf58_476d_1ce4_e5b9
    value = (value ^ (value >> 27)) &* 0x94d0_49bb_1331_11eb
    return value ^ (value >> 31)
  }

  mutating func nextUnit() -> Double {
    Double(next() >> 11) / Double(UInt64(1) << 53)
  }
}
