import CoreGraphics
import Foundation

public enum PetWindowPlacement {
  public static func clampedAnchor(
    _ candidate: CGPoint,
    panelSize: CGSize,
    canvasHeight: CGFloat,
    contentBounds: CGRect,
    screenFrame: CGRect
  ) -> CGPoint {
    let pixelScale = panelSize.height / canvasHeight
    let localMinX = contentBounds.minX * pixelScale
    let localMaxX = contentBounds.maxX * pixelScale
    let localMinY = (canvasHeight - contentBounds.maxY) * pixelScale
    let localMaxY = (canvasHeight - contentBounds.minY) * pixelScale
    let minimumX = screenFrame.minX + panelSize.width / 2 - localMinX
    let maximumX = screenFrame.maxX + panelSize.width / 2 - localMaxX
    let minimumY = screenFrame.minY - localMinY
    let maximumY = screenFrame.maxY - localMaxY
    let x =
      minimumX > maximumX
      ? screenFrame.midX + panelSize.width / 2 - (localMinX + localMaxX) / 2
      : min(maximumX, max(minimumX, candidate.x))
    let y =
      minimumY > maximumY
      ? screenFrame.midY - (localMinY + localMaxY) / 2
      : min(maximumY, max(minimumY, candidate.y))
    return CGPoint(x: x, y: y)
  }
}
