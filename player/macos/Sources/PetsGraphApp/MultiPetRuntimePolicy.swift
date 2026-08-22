import Foundation

enum MultiPetRuntimePolicy {
  static let allowedScales = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
  static let startupGapPt = 12.0

  static func orderedPetIDs<S: Sequence>(_ petIDs: S) -> [String]
  where S.Element == String {
    petIDs.sorted {
      let left = petOrderKey($0)
      let right = petOrderKey($1)
      return left == right ? $0 < $1 : left < right
    }
  }

  static func initialLoadedPetIDs(
    available: Set<String>,
    saved: [String]?
  ) -> Set<String> {
    guard let saved else { return available }
    return Set(saved).intersection(available)
  }

  static func normalizedScale(_ saved: Double?) -> Double {
    guard let saved, allowedScales.contains(saved) else { return 1.0 }
    return saved
  }

  static func scaleTitle(_ value: Double) -> String {
    switch value {
    case 0.5: "0.5×"
    case 0.75: "0.75×"
    case 1.0: "1.0×"
    case 1.25: "1.25×"
    case 1.5: "1.5×"
    case 1.75: "1.75×"
    case 2.0: "2.0×"
    default: String(format: "%g×", value)
    }
  }

  static func nextStartupX(existingMaxX: Double?) -> Double? {
    existingMaxX.map { $0 + startupGapPt }
  }

  private static func petOrderKey(_ petID: String) -> Int {
    switch petID {
    case "wubai": 0
    case "feiliu": 1
    default: 2
    }
  }
}
