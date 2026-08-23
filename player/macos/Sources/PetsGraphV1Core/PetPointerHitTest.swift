import CoreGraphics
import Foundation

public enum PetPointerHitTest {
  public static let alphaThreshold = 0.05

  public static func canvasPixel(
    at screenPoint: CGPoint,
    panelFrame: CGRect,
    canvasWidth: Int,
    canvasHeight: Int
  ) -> (x: Int, y: Int)? {
    guard
      canvasWidth > 0,
      canvasHeight > 0,
      panelFrame.width > 0,
      panelFrame.height > 0,
      panelFrame.contains(screenPoint)
    else { return nil }

    let normalizedX = (screenPoint.x - panelFrame.minX) / panelFrame.width
    let normalizedY = (screenPoint.y - panelFrame.minY) / panelFrame.height
    let canvasX = min(canvasWidth - 1, max(0, Int(floor(normalizedX * Double(canvasWidth)))))
    let canvasY = min(
      canvasHeight - 1,
      max(0, Int(floor((1 - normalizedY) * Double(canvasHeight))))
    )
    return (canvasX, canvasY)
  }

  public static func ignoresMouseEvents(
    alpha: Double,
    threshold: Double = alphaThreshold
  ) -> Bool {
    !alpha.isFinite || alpha <= threshold
  }
}
