import Foundation

public struct PetPlayerState: Codable, Equatable, Sendable {
  public var visible: Bool
  public var anchorX: Double?
  public var anchorY: Double?

  public init(visible: Bool = true, anchorX: Double? = nil, anchorY: Double? = nil) {
    self.visible = visible
    self.anchorX = anchorX
    self.anchorY = anchorY
  }

  public var savedAnchor: (x: Double, y: Double)? {
    guard let anchorX, let anchorY, anchorX.isFinite, anchorY.isFinite else { return nil }
    return (anchorX, anchorY)
  }
}

public struct PlayerState: Codable, Equatable, Sendable {
  public static let formatVersion = 1
  public static let allowedScales = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

  public var formatVersion: Int
  public var globalScale: Double
  public var pets: [String: PetPlayerState]

  public init(
    formatVersion: Int = Self.formatVersion,
    globalScale: Double = 1,
    pets: [String: PetPlayerState] = [:]
  ) {
    self.formatVersion = formatVersion
    self.globalScale = Self.normalizedScale(globalScale)
    self.pets = pets
  }

  public static func normalizedScale(_ value: Double) -> Double {
    allowedScales.contains(value) ? value : 1
  }
}
