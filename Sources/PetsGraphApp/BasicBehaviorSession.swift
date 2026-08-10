import Foundation
import PetsGraphCore

enum BehaviorInteractionState: Equatable {
  case sleeping
  case waking
  case sitting
  case moving
  case returningToSleep
}

struct BehaviorPresentation {
  let generation: Int
  let sample: TimelineSample
  let totalRootMotionXPt: Double
  let mirrored: Bool
  let clipIDsToPreload: [String]
  let interactionState: BehaviorInteractionState
}

enum BehaviorCommandResult: Equatable {
  case started
  case queued
  case ignored
  case unavailable
}

enum PetClickResult: Equatable {
  case wakeStarted
  case wakeQueued
  case sleepStarted
  case sleepQueued
  case debounced
  case transitionInProgress
  case alreadyReturningToSleep
}

enum DestinationCommandResult: Equatable {
  case started(
    gait: PreviewMovementGait,
    direction: PreviewMovementDirection,
    plannedDistancePt: Double
  )
  case queued
  case ignored
  case tooClose
  case unavailable
}

@MainActor
final class BasicBehaviorSession {
  private enum Mode: Equatable {
    case sleeping
    case changingSleep
    case waking
    case sitting
    case moving
    case returningToSleep
  }

  private struct MovementRequest {
    let direction: PreviewMovementDirection
    let targetDistancePt: Double
    let forcedGait: PreviewMovementGait?
  }

  private struct ResolvedMovement {
    let plan: EngineeringBehaviorPlan
    let gait: PreviewMovementGait
    let plannedDistancePt: Double
  }

  private let package: LoadedPetPackage
  private let planner: EngineeringBehaviorPlanner
  private let quietPlanner: QuietCompanionPlanner?
  private let accelerated: Bool
  private let petClickDebounceSeconds: Double

  private var mode: Mode = .sleeping
  private var activePlan: EngineeringBehaviorPlan
  private var timeline: PlaybackTimeline
  private var planStartUptime: TimeInterval = 0
  private var accumulatedRootMotionPt = 0.0
  private var activeMotionSign = 1.0
  private var currentNodeID: String
  private var lastDwellNodeID: String
  private var previousSleepNodeID: String?
  private var recentSleepNodeIDs: [String] = []
  private var currentSceneEnteredUptime: TimeInterval = 0
  private var lastSceneExitUptime: [String: TimeInterval] = [:]
  private var nextSleepChangeUptime = TimeInterval.greatestFiniteMagnitude
  private var nextSittingSleepUptime = TimeInterval.greatestFiniteMagnitude
  private var wakeRequested = false
  private var sleepRequested = false
  private var queuedMovement: MovementRequest?
  private var engineeringSleepTargets: [String] = []
  private var engineeringDwellSeconds: Double?
  private var generation = 0
  private var lastPetClickUptime = -Double.infinity

  init(package: LoadedPetPackage, accelerated: Bool) throws {
    self.package = package
    planner = try EngineeringBehaviorPlanner(package: package)
    quietPlanner = package.behavior == nil ? nil : try QuietCompanionPlanner(package: package)
    self.accelerated = accelerated
    petClickDebounceSeconds = package.behavior?.interactions.petClick.debounceSeconds ?? 0.35
    currentNodeID = quietPlanner?.defaultNodeID ?? "rest.prone.left"
    lastDwellNodeID = currentNodeID
    activePlan = try quietPlanner?.idlePlan(nodeID: currentNodeID)
      ?? planner.idlePlan(nodeID: currentNodeID)
    timeline = try PlaybackTimeline(
      clips: package.clips,
      sequence: activePlan.sequence
    )
  }

  func start(at uptime: TimeInterval) {
    planStartUptime = uptime
    currentSceneEnteredUptime = uptime
    recentSleepNodeIDs = [currentNodeID]
    scheduleNextSleepChange(after: uptime)
  }

  func update(
    at uptime: TimeInterval,
    motionScale: Double,
    currentPetCenterX: Double
  ) throws -> BehaviorPresentation {
    try finishFinitePlanIfNeeded(
      at: uptime,
      motionScale: motionScale,
      currentPetCenterX: currentPetCenterX
    )

    if mode == .sleeping, uptime >= nextSleepChangeUptime {
      try beginSleepChange(at: uptime)
    } else if mode == .sitting, uptime >= nextSittingSleepUptime {
      try beginReturnToSleep(at: uptime)
    }

    let sample = timeline.sample(at: elapsed(at: uptime))
    return BehaviorPresentation(
      generation: generation,
      sample: sample,
      totalRootMotionXPt: accumulatedRootMotionPt
        + activeMotionSign * sample.rootMotionXPt,
      mirrored: activePlan.mirroredClipIDs.contains(sample.clipID),
      clipIDsToPreload: timeline.clipIDsNear(segmentIndex: sample.segmentIndex),
      interactionState: interactionState
    )
  }

  func handlePetClick(at uptime: TimeInterval) throws -> PetClickResult {
    guard uptime - lastPetClickUptime >= petClickDebounceSeconds else {
      return .debounced
    }
    lastPetClickUptime = uptime
    cancelEngineeringSleepSequence()
    switch mode {
    case .sleeping:
      try beginWakeToSit(at: uptime)
      return .wakeStarted
    case .changingSleep:
      wakeRequested = true
      return .wakeQueued
    case .waking:
      if quietPlanner != nil {
        return .transitionInProgress
      }
      sleepRequested = true
      queuedMovement = nil
      return .sleepQueued
    case .sitting:
      try beginReturnToSleep(at: uptime)
      return .sleepStarted
    case .moving:
      sleepRequested = true
      queuedMovement = nil
      return .sleepQueued
    case .returningToSleep:
      return .alreadyReturningToSleep
    }
  }

  func requestDestination(
    targetX: Double,
    currentPetCenterX: Double,
    at uptime: TimeInterval,
    motionScale: Double
  ) throws -> DestinationCommandResult {
    guard quietPlanner == nil else { return .unavailable }
    let phase: PreviewDestinationPhase = switch mode {
    case .sitting: .sitting
    case .moving: .moving
    case .sleeping, .changingSleep, .waking, .returningToSleep: .unavailable
    }
    guard PreviewDestinationClickPolicy.acceptsClick(during: phase) else {
      if phase == .moving {
        print("petsgraph destination ignored while moving")
      }
      return .ignored
    }
    return try startDestination(
      targetX: targetX,
      currentPetCenterX: currentPetCenterX,
      at: uptime,
      motionScale: motionScale
    )
  }

  func forceMovement(
    _ gait: PreviewMovementGait,
    direction requestedDirection: PreviewMovementDirection? = nil,
    at uptime: TimeInterval,
    motionScale: Double,
    availableLeftPt: Double,
    availableRightPt: Double
  ) throws -> BehaviorCommandResult {
    guard quietPlanner == nil else { return .unavailable }
    let direction: PreviewMovementDirection = requestedDirection
      ?? (availableLeftPt > availableRightPt ? .left : .right)
    let available = direction == .left ? availableLeftPt : availableRightPt
    guard available >= 30 else {
      return .unavailable
    }
    let preferredDistance = gait == .run ? 1_000.0 : 320.0
    let request = MovementRequest(
      direction: direction,
      targetDistancePt: min(available, preferredDistance),
      forcedGait: gait
    )

    switch mode {
    case .sitting:
      let result = try startMovement(request, at: uptime, motionScale: motionScale)
      if case .started = result {
        return .started
      }
      return .unavailable
    case .sleeping:
      queuedMovement = request
      try beginWakeToSit(at: uptime)
      return .queued
    case .changingSleep:
      queuedMovement = request
      wakeRequested = true
      return .queued
    case .waking, .moving:
      queuedMovement = request
      sleepRequested = false
      return .queued
    case .returningToSleep:
      queuedMovement = request
      wakeRequested = true
      return .queued
    }
  }

  func forceSleepChange(at uptime: TimeInterval) throws {
    guard mode == .sleeping else {
      print("petsgraph behavior ignored sleep-change outside sleep")
      return
    }
    try beginSleepChange(at: uptime)
  }

  func startQuietSceneRoundTripDemo(
    at uptime: TimeInterval,
    dwellSeconds: Double = 3
  ) throws {
    guard let quietPlanner else {
      throw PackageValidationError.invalid(
        "quiet scene round-trip demo requires quiet companion behavior"
      )
    }
    guard mode == .sleeping else {
      throw PackageValidationError.invalid(
        "quiet scene round-trip demo must start while sleeping"
      )
    }
    let pillowNodes = quietPlanner.autonomousNodeIDs(scene: "pillow")
    guard !pillowNodes.isEmpty else {
      throw PackageValidationError.missing("quiet scene round-trip demo needs a pillow dwell")
    }
    let pillowTarget = pillowNodes.contains("rest.pillow.head-on")
      ? "rest.pillow.head-on"
      : pillowNodes[0]
    engineeringSleepTargets = [pillowTarget, quietPlanner.defaultNodeID]
    engineeringDwellSeconds = max(1, dwellSeconds)
    try beginSleepChange(at: uptime)
    print(
      "petsgraph quiet-scene-round-trip-demo queued "
        + "targets=\(engineeringSleepTargets.joined(separator: ","))"
    )
  }

  func handleDragStarted() {
    cancelEngineeringSleepSequence()
    wakeRequested = false
    sleepRequested = false
    queuedMovement = nil
    engineeringSleepTargets = []
    engineeringDwellSeconds = nil
  }

  func resetToSleep(at uptime: TimeInterval) throws {
    let target = quietPlanner?.defaultNodeID ?? "rest.prone.left"
    let plan = try quietPlanner?.idlePlan(nodeID: target)
      ?? planner.idlePlan(nodeID: target)
    replacePlan(plan, at: uptime)
    currentNodeID = target
    lastDwellNodeID = target
    mode = .sleeping
    wakeRequested = false
    sleepRequested = false
    queuedMovement = nil
    recentSleepNodeIDs = [target]
    currentSceneEnteredUptime = uptime
    lastSceneExitUptime = [:]
    lastPetClickUptime = -Double.infinity
    scheduleNextSleepChange(after: uptime)
    nextSittingSleepUptime = .greatestFiniteMagnitude
    print("petsgraph behavior reset node=\(currentNodeID)")
  }

  private var interactionState: BehaviorInteractionState {
    switch mode {
    case .sleeping, .changingSleep:
      return .sleeping
    case .waking:
      return .waking
    case .sitting:
      return .sitting
    case .moving:
      return .moving
    case .returningToSleep:
      return .returningToSleep
    }
  }

  private func beginWakeToSit(at uptime: TimeInterval) throws {
    let currentFrame = timeline.sample(at: elapsed(at: uptime)).sourceFrameIndex
    lastDwellNodeID = currentNodeID
    let plan = if let quietPlanner {
      try quietPlanner.wakeToSceneSitPlan(
        fromSleepNodeID: currentNodeID,
        currentFrame: currentFrame
      )
    } else {
      try planner.wakeToSitPlan(
        fromSleepNodeID: currentNodeID,
        currentFrame: currentFrame
      )
    }
    replacePlan(plan, at: uptime)
    mode = .waking
    wakeRequested = false
    nextSleepChangeUptime = .greatestFiniteMagnitude
    nextSittingSleepUptime = .greatestFiniteMagnitude
    print("petsgraph behavior waking-to-sit from=\(currentNodeID)")
  }

  private func beginReturnToSleep(at uptime: TimeInterval) throws {
    let currentFrame = timeline.sample(at: elapsed(at: uptime)).sourceFrameIndex
    let plan = if let quietPlanner {
      try quietPlanner.returnToSceneSleepPlan(
        fromInteractionNodeID: currentNodeID,
        currentFrame: currentFrame,
        preferredDwellNodeID: lastDwellNodeID
      )
    } else {
      try planner.sitToSleepPlan(currentFrame: currentFrame)
    }
    replacePlan(plan, at: uptime)
    mode = .returningToSleep
    sleepRequested = false
    queuedMovement = nil
    nextSittingSleepUptime = .greatestFiniteMagnitude
    print("petsgraph behavior returning-to-sleep")
  }

  private func startMovement(
    _ request: MovementRequest,
    at uptime: TimeInterval,
    motionScale: Double
  ) throws -> DestinationCommandResult {
    let currentFrame = timeline.sample(at: elapsed(at: uptime)).sourceFrameIndex
    let resolved = try resolveMovement(
      request,
      currentFrame: currentFrame,
      motionScale: motionScale
    )
    replacePlan(resolved.plan, at: uptime)
    mode = .moving
    queuedMovement = nil
    sleepRequested = false
    nextSittingSleepUptime = .greatestFiniteMagnitude
    print(
      String(
        format: "petsgraph destination started gait=%@ direction=%@ target=%.1f planned=%.1f",
        resolved.gait.rawValue,
        request.direction.rawValue,
        request.targetDistancePt,
        resolved.plannedDistancePt
      )
    )
    return .started(
      gait: resolved.gait,
      direction: request.direction,
      plannedDistancePt: resolved.plannedDistancePt
    )
  }

  private func startDestination(
    targetX: Double,
    currentPetCenterX: Double,
    at uptime: TimeInterval,
    motionScale: Double
  ) throws -> DestinationCommandResult {
    guard let destination = PreviewDestinationPlanner.resolve(
      targetX: targetX,
      currentPetCenterX: currentPetCenterX
    ) else {
      print(
        String(
          format: "petsgraph destination already reached target-x=%.1f current-x=%.1f",
          targetX,
          currentPetCenterX
        )
      )
      return .tooClose
    }
    let request = MovementRequest(
      direction: destination.direction,
      targetDistancePt: destination.distancePt,
      forcedGait: nil
    )
    return try startMovement(request, at: uptime, motionScale: motionScale)
  }

  private func resolveMovement(
    _ request: MovementRequest,
    currentFrame: Int,
    motionScale: Double
  ) throws -> ResolvedMovement {
    let minimumRun = try planner.sitMovementPlan(
      currentFrame: currentFrame,
      gait: .run,
      direction: request.direction,
      runCycles: 1
    )
    let minimumRunDistance = minimumRun.finiteRootMotionPt * motionScale
    let gait = request.forcedGait
      ?? (request.targetDistancePt + 0.000_001 >= minimumRunDistance ? .run : .walk)

    let first = try planner.sitMovementPlan(
      currentFrame: currentFrame,
      gait: gait,
      direction: request.direction,
      walkCycles: 1,
      runCycles: 1
    )
    let second = try planner.sitMovementPlan(
      currentFrame: currentFrame,
      gait: gait,
      direction: request.direction,
      walkCycles: gait == .walk ? 2 : 1,
      runCycles: gait == .run ? 2 : 1
    )
    let firstDistance = first.finiteRootMotionPt * motionScale
    let increment = max(
      0.000_001,
      second.finiteRootMotionPt * motionScale - firstDistance
    )
    let selection = PreviewMovementDistancePlanner.selectCycles(
      targetDistancePt: request.targetDistancePt,
      firstCycleDistancePt: firstDistance,
      additionalCycleDistancePt: increment
    )
    let bestPlan = selection.cycles == 1
      ? first
      : try planner.sitMovementPlan(
        currentFrame: currentFrame,
        gait: gait,
        direction: request.direction,
        walkCycles: gait == .walk ? selection.cycles : 1,
        runCycles: gait == .run ? selection.cycles : 1
      )
    return ResolvedMovement(
      plan: bestPlan,
      gait: gait,
      plannedDistancePt: selection.plannedDistancePt
    )
  }

  private func beginSleepChange(at uptime: TimeInterval) throws {
    if !engineeringSleepTargets.isEmpty {
      let target = engineeringSleepTargets.removeFirst()
      try beginSleepChange(to: target, at: uptime)
      return
    }
    let neighbors: [String]
    if let quietPlanner {
      let currentScene = quietPlanner.scene(for: currentNodeID)
      let sameScene = quietPlanner.autonomousNodeIDs(scene: currentScene)
        .filter { $0 != currentNodeID }
      let allOther = quietPlanner.autonomousNodeIDs()
        .filter { candidate in
          guard candidate != currentNodeID, !sameScene.contains(candidate) else {
            return false
          }
          guard
            let candidateScene = quietPlanner.scene(for: candidate),
            let lastExit = lastSceneExitUptime[candidateScene],
            let cooldown = package.behavior?.scenePolicy[candidateScene]?.exitCooldownSeconds
          else {
            return true
          }
          return uptime - lastExit >= cooldown
        }
      let scenePolicy = currentScene.flatMap { package.behavior?.scenePolicy[$0] }
      let stickyMinimum = scenePolicy?.minimumDwellSeconds ?? 0
      let mustStay = scenePolicy?.sticky == true
        && uptime - currentSceneEnteredUptime < stickyMinimum
      let sameSceneProbability = package.behavior?.timing.sameSceneProbability ?? 0.86
      let chooseSameScene = mustStay
        || allOther.isEmpty
        || Double.random(in: 0..<1) < sameSceneProbability
      neighbors = chooseSameScene && !sameScene.isEmpty ? sameScene : allOther
    } else {
      neighbors = planner.sleepNeighborNodeIDs(from: currentNodeID)
    }
    guard !neighbors.isEmpty else {
      scheduleNextSleepChange(after: uptime)
      return
    }
    let recent = Set(recentSleepNodeIDs)
    let deDuplicated = neighbors.filter { !recent.contains($0) }
    let alternatives = deDuplicated.isEmpty
      ? neighbors.filter { $0 != previousSleepNodeID }
      : deDuplicated
    let candidates = alternatives.isEmpty ? neighbors : alternatives
    guard let target = candidates.randomElement() else {
      return
    }
    try beginSleepChange(to: target, at: uptime)
  }

  private func beginSleepChange(to target: String, at uptime: TimeInterval) throws {
    let currentFrame = timeline.sample(at: elapsed(at: uptime)).sourceFrameIndex
    let plan = if let quietPlanner {
      try quietPlanner.sleepChangePlan(
        fromNodeID: currentNodeID,
        toNodeID: target,
        currentFrame: currentFrame
      )
    } else {
      try planner.sleepChangePlan(
        fromNodeID: currentNodeID,
        toNodeID: target,
        currentFrame: currentFrame
      )
    }
    previousSleepNodeID = currentNodeID
    replacePlan(plan, at: uptime)
    mode = .changingSleep
    nextSleepChangeUptime = .greatestFiniteMagnitude
    print("petsgraph behavior sleep-change from=\(currentNodeID) to=\(target)")
  }

  private func finishFinitePlanIfNeeded(
    at uptime: TimeInterval,
    motionScale: Double,
    currentPetCenterX: Double
  ) throws {
    guard
      ![Mode.sleeping, .sitting].contains(mode),
      elapsed(at: uptime) >= timeline.finiteDurationSeconds
    else {
      return
    }

    switch mode {
    case .changingSleep:
      let previousScene = quietPlanner?.scene(for: currentNodeID)
      currentNodeID = activePlan.finalNodeID
      lastDwellNodeID = currentNodeID
      if let previousScene, quietPlanner?.scene(for: currentNodeID) != previousScene {
        lastSceneExitUptime[previousScene] = uptime
        currentSceneEnteredUptime = uptime
      }
      appendRecentSleepNode(currentNodeID)
      mode = .sleeping
      if !engineeringSleepTargets.isEmpty, let dwell = engineeringDwellSeconds {
        nextSleepChangeUptime = uptime + dwell
      } else {
        engineeringDwellSeconds = nil
        scheduleNextSleepChange(after: uptime)
      }
      if wakeRequested {
        try beginWakeToSit(at: uptime)
      }
    case .waking:
      currentNodeID = activePlan.finalNodeID
      mode = .sitting
      scheduleSittingSleep(after: uptime)
      if sleepRequested {
        try beginReturnToSleep(at: uptime)
      } else if let request = queuedMovement {
        _ = try startMovement(request, at: uptime, motionScale: motionScale)
      }
    case .moving:
      currentNodeID = "sit.front"
      mode = .sitting
      scheduleSittingSleep(after: uptime)
      if sleepRequested {
        try beginReturnToSleep(at: uptime)
      } else if let request = queuedMovement {
        _ = try startMovement(request, at: uptime, motionScale: motionScale)
      }
    case .returningToSleep:
      let previousScene = quietPlanner?.scene(for: currentNodeID)
      currentNodeID = activePlan.finalNodeID
      lastDwellNodeID = currentNodeID
      if let previousScene, quietPlanner?.scene(for: currentNodeID) != previousScene {
        lastSceneExitUptime[previousScene] = uptime
        currentSceneEnteredUptime = uptime
      }
      appendRecentSleepNode(currentNodeID)
      mode = .sleeping
      scheduleNextSleepChange(after: uptime)
      if wakeRequested || queuedMovement != nil {
        try beginWakeToSit(at: uptime)
      }
    case .sleeping, .sitting:
      break
    }
  }

  private func replacePlan(_ plan: EngineeringBehaviorPlan, at uptime: TimeInterval) {
    let prior = timeline.sample(at: elapsed(at: uptime))
    accumulatedRootMotionPt += activeMotionSign * prior.rootMotionXPt
    do {
      timeline = try PlaybackTimeline(clips: package.clips, sequence: plan.sequence)
    } catch {
      preconditionFailure("validated behavior plan failed to resolve: \(error)")
    }
    activePlan = plan
    activeMotionSign = plan.movementDirection?.motionSign ?? 1
    planStartUptime = uptime
    generation += 1
  }

  private func elapsed(at uptime: TimeInterval) -> TimeInterval {
    max(0, uptime - planStartUptime)
  }

  private func scheduleNextSleepChange(after uptime: TimeInterval) {
    let delay: Double
    if accelerated {
      delay = Double.random(in: 18...28)
    } else if let timing = package.behavior?.timing {
      let minimum = timing.minimumDwellSeconds ?? 150
      let median = timing.medianDwellSeconds ?? 420
      let maximum = timing.maximumDwellSeconds ?? 1_200
      let u1 = max(Double.leastNonzeroMagnitude, Double.random(in: 0..<1))
      let u2 = Double.random(in: 0..<1)
      let standardNormal = sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
      delay = min(maximum, max(minimum, exp(log(median) + 0.68 * standardNormal)))
    } else {
      delay = Double.random(in: 90...240)
    }
    nextSleepChangeUptime = uptime + delay
  }

  private func scheduleSittingSleep(after uptime: TimeInterval) {
    nextSittingSleepUptime = quietPlanner == nil
      ? uptime + (accelerated ? 15 : 30)
      : .greatestFiniteMagnitude
  }

  private func appendRecentSleepNode(_ nodeID: String) {
    recentSleepNodeIDs.append(nodeID)
    let limit = package.behavior?.timing.recentHistoryLimit ?? 2
    if recentSleepNodeIDs.count > limit {
      recentSleepNodeIDs.removeFirst(recentSleepNodeIDs.count - limit)
    }
  }

  private func cancelEngineeringSleepSequence() {
    engineeringSleepTargets = []
    engineeringDwellSeconds = nil
  }
}
