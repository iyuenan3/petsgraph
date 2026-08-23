import Foundation

public struct PlayerScaleOption: Equatable, Sendable {
  public let value: Double
  public let label: String

  public init(value: Double, label: String) {
    self.value = value
    self.label = label
  }
}

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
  public static let scaleOptions = [
    PlayerScaleOption(value: 0.5, label: "0.5"),
    PlayerScaleOption(value: 0.75, label: "0.75"),
    PlayerScaleOption(value: 1.0, label: "1.0"),
    PlayerScaleOption(value: 1.25, label: "1.25"),
    PlayerScaleOption(value: 1.5, label: "1.5"),
    PlayerScaleOption(value: 1.75, label: "1.75"),
    PlayerScaleOption(value: 2.0, label: "2.0"),
  ]
  public static let allowedScales = scaleOptions.map(\.value)

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

  public static func migratedLegacyPet(anchorX: Double?, anchorY: Double?) -> PetPlayerState {
    PetPlayerState(
      visible: true,
      anchorX: anchorX.flatMap { $0.isFinite ? $0 : nil },
      anchorY: anchorY.flatMap { $0.isFinite ? $0 : nil }
    )
  }

  public static func hiddenFailSafe(packageIDs: some Sequence<String>) -> PlayerState {
    PlayerState(
      pets: Dictionary(
        uniqueKeysWithValues: packageIDs.map { ($0, PetPlayerState(visible: false)) }
      )
    )
  }

  public mutating func captureRuntimePet(
    packageID: String,
    visible: Bool,
    anchorX: Double,
    anchorY: Double
  ) {
    var pet = pets[packageID] ?? PetPlayerState()
    pet.visible = visible
    pet.anchorX = anchorX.isFinite ? anchorX : nil
    pet.anchorY = anchorY.isFinite ? anchorY : nil
    pets[packageID] = pet
  }
}
