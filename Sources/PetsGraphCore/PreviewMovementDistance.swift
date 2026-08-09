import Foundation

public struct PreviewMovementCycleSelection: Equatable, Sendable {
  public let cycles: Int
  public let plannedDistancePt: Double

  public init(cycles: Int, plannedDistancePt: Double) {
    self.cycles = cycles
    self.plannedDistancePt = plannedDistancePt
  }
}

public enum PreviewMovementDistancePlanner {
  public static func selectCycles(
    targetDistancePt: Double,
    firstCycleDistancePt: Double,
    additionalCycleDistancePt: Double,
    maximumCycles: Int = 128
  ) -> PreviewMovementCycleSelection {
    precondition(targetDistancePt >= 0)
    precondition(firstCycleDistancePt >= 0)
    precondition(additionalCycleDistancePt > 0)
    precondition(maximumCycles > 0)

    let estimate = Int(
      ((targetDistancePt - firstCycleDistancePt) / additionalCycleDistancePt)
        .rounded()
    ) + 1
    let candidates = Set([
      1,
      max(1, min(maximumCycles, estimate - 1)),
      max(1, min(maximumCycles, estimate)),
      max(1, min(maximumCycles, estimate + 1)),
      maximumCycles,
    ])

    var bestCycles = 1
    var bestDistance = firstCycleDistancePt
    var bestError = abs(firstCycleDistancePt - targetDistancePt)
    for cycles in candidates.sorted() {
      let distance = firstCycleDistancePt
        + Double(cycles - 1) * additionalCycleDistancePt
      let error = abs(distance - targetDistancePt)
      if error + 0.000_001 < bestError {
        bestCycles = cycles
        bestDistance = distance
        bestError = error
      }
    }
    return PreviewMovementCycleSelection(
      cycles: bestCycles,
      plannedDistancePt: bestDistance
    )
  }
}

public struct PreviewDestinationResolution: Equatable, Sendable {
  public let direction: PreviewMovementDirection
  public let distancePt: Double

  public init(direction: PreviewMovementDirection, distancePt: Double) {
    self.direction = direction
    self.distancePt = distancePt
  }
}

public enum PreviewDestinationPlanner {
  public static func resolve(
    targetX: Double,
    currentPetCenterX: Double,
    minimumDistancePt: Double = 30
  ) -> PreviewDestinationResolution? {
    let delta = targetX - currentPetCenterX
    guard abs(delta) + 0.000_001 >= minimumDistancePt else {
      return nil
    }
    return PreviewDestinationResolution(
      direction: delta < 0 ? .left : .right,
      distancePt: abs(delta)
    )
  }
}

public enum PreviewDestinationPhase: Equatable, Sendable {
  case sitting
  case moving
  case unavailable
}

public enum PreviewDestinationClickPolicy {
  public static func acceptsClick(
    during phase: PreviewDestinationPhase
  ) -> Bool {
    phase == .sitting
  }
}
