import Foundation
import PetsGraphCore

final class PlayerStateStore {
  private let url: URL
  private let defaults: UserDefaults

  init(rootURL: URL, defaults: UserDefaults = .standard) {
    url = rootURL.appendingPathComponent("settings.json", isDirectory: false)
    self.defaults = defaults
  }

  func load(for packages: [LoadedPetPack]) -> PlayerState {
    if let data = try? Data(contentsOf: url),
      let decoded = try? JSONDecoder().decode(PlayerState.self, from: data),
      decoded.formatVersion == PlayerState.formatVersion
    {
      return normalized(decoded)
    }
    return migrateLegacy(for: packages)
  }

  func save(_ state: PlayerState) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(normalized(state)).write(to: url, options: [.atomic])
  }

  private func normalized(_ state: PlayerState) -> PlayerState {
    var result = state
    result.formatVersion = PlayerState.formatVersion
    result.globalScale = PlayerState.normalizedScale(state.globalScale)
    result.pets = state.pets.filter { key, value in
      !key.isEmpty && (value.anchorX == nil || value.anchorX!.isFinite)
        && (value.anchorY == nil || value.anchorY!.isFinite)
    }
    return result
  }

  private func migrateLegacy(for packages: [LoadedPetPack]) -> PlayerState {
    let legacyScale = defaults.double(forKey: "petsgraph.global-scale.v1")
    let scale = PlayerState.normalizedScale(legacyScale == 0 ? 1 : legacyScale)
    var pets: [String: PetPlayerState] = [:]
    for package in packages {
      let id = package.manifest.package.id
      var anchorX: Double?
      var anchorY: Double?
      if let value = defaults.dictionary(forKey: "petsgraph.pet-canvas-origin.v2.\(id)"),
        let originX = value["x"] as? Double,
        let originY = value["y"] as? Double,
        originX.isFinite,
        originY.isFinite
      {
        let canvas = package.manifest.stage.referenceCanvasPx
        let pixelScale = package.manifest.stage.baseDisplayHeight * scale / Double(canvas[1])
        anchorX = originX + Double(canvas[0]) * pixelScale / 2
        anchorY = originY
      }
      pets[id] = PlayerState.migratedLegacyPet(anchorX: anchorX, anchorY: anchorY)
    }
    return PlayerState(globalScale: scale, pets: pets)
  }
}
