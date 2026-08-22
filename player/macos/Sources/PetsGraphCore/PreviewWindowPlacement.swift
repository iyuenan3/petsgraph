import Foundation

public struct PreviewHorizontalPlacement: Equatable, Sendable {
  public let originX: Double
  public let rebasedManualOffsetX: Double
  public let hitBoundary: Bool

  public init(
    originX: Double,
    rebasedManualOffsetX: Double,
    hitBoundary: Bool
  ) {
    self.originX = originX
    self.rebasedManualOffsetX = rebasedManualOffsetX
    self.hitBoundary = hitBoundary
  }

  public static func resolve(
    calculatedX: Double,
    manualOffsetX: Double,
    minimumX: Double,
    maximumX: Double
  ) -> PreviewHorizontalPlacement {
    precondition(maximumX >= minimumX)
    let requestedX = calculatedX + manualOffsetX
    let originX = min(maximumX, max(minimumX, requestedX))
    let hitBoundary = abs(originX - requestedX) > 0.000_001
    return PreviewHorizontalPlacement(
      originX: originX,
      rebasedManualOffsetX: hitBoundary ? originX - calculatedX : manualOffsetX,
      hitBoundary: hitBoundary
    )
  }
}
