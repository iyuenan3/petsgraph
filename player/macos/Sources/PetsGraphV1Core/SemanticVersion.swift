import Foundation

public struct SemanticVersion: Comparable, Codable, Hashable, Sendable {
  public let major: Int
  public let minor: Int
  public let patch: Int
  public let prerelease: [String]
  public let build: String?

  public init?(_ value: String) {
    let halves = value.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)
    guard halves.count <= 2, halves.allSatisfy({ !$0.isEmpty }) else { return nil }
    let coreAndPrerelease = halves[0].split(
      separator: "-",
      maxSplits: 1,
      omittingEmptySubsequences: false
    )
    guard coreAndPrerelease.count <= 2, coreAndPrerelease.allSatisfy({ !$0.isEmpty }) else {
      return nil
    }
    let core = coreAndPrerelease[0].split(separator: ".", omittingEmptySubsequences: false)
    guard core.count == 3 else { return nil }
    var numbers: [Int] = []
    for component in core {
      guard
        !component.isEmpty,
        component.allSatisfy(\.isNumber),
        component.count == 1 || component.first != "0",
        let number = Int(component)
      else { return nil }
      numbers.append(number)
    }
    let prerelease: [String]
    if coreAndPrerelease.count == 2 {
      prerelease = coreAndPrerelease[1].split(
        separator: ".",
        omittingEmptySubsequences: false
      ).map(String.init)
      guard prerelease.allSatisfy(Self.isIdentifier) else { return nil }
      for identifier in prerelease where identifier.allSatisfy(\.isNumber) {
        guard identifier.count == 1 || identifier.first != "0" else { return nil }
      }
    } else {
      prerelease = []
    }
    let build = halves.count == 2 ? String(halves[1]) : nil
    if let build {
      guard
        build.split(separator: ".", omittingEmptySubsequences: false)
          .map(String.init).allSatisfy(Self.isIdentifier)
      else { return nil }
    }
    major = numbers[0]
    minor = numbers[1]
    patch = numbers[2]
    self.prerelease = prerelease
    self.build = build
  }

  public var stringValue: String {
    var value = "\(major).\(minor).\(patch)"
    if !prerelease.isEmpty { value += "-" + prerelease.joined(separator: ".") }
    if let build { value += "+" + build }
    return value
  }

  public static func < (left: SemanticVersion, right: SemanticVersion) -> Bool {
    let leftCore = [left.major, left.minor, left.patch]
    let rightCore = [right.major, right.minor, right.patch]
    if leftCore != rightCore { return leftCore.lexicographicallyPrecedes(rightCore) }
    if left.prerelease.isEmpty { return false }
    if right.prerelease.isEmpty { return true }
    for (lhs, rhs) in zip(left.prerelease, right.prerelease) where lhs != rhs {
      let leftNumber = Int(lhs)
      let rightNumber = Int(rhs)
      switch (leftNumber, rightNumber) {
      case (.some(let a), .some(let b)): return a < b
      case (.some, .none): return true
      case (.none, .some): return false
      case (.none, .none): return lhs < rhs
      }
    }
    return left.prerelease.count < right.prerelease.count
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let value = try container.decode(String.self)
    guard let parsed = SemanticVersion(value) else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "invalid semantic version"
      )
    }
    self = parsed
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(stringValue)
  }

  private static func isIdentifier(_ value: String) -> Bool {
    !value.isEmpty
      && value.utf8.allSatisfy {
        ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 90)
          || ($0 >= 97 && $0 <= 122) || $0 == 45
      }
  }
}
