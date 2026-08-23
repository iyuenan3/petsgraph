import Foundation

package struct PlayerAboutInfo: Equatable {
  package let version: String?
  package let build: String?

  package init(infoDictionary: [String: Any]?) {
    version = Self.nonemptyString(
      infoDictionary?["CFBundleShortVersionString"]
    )
    build = Self.nonemptyString(
      infoDictionary?["CFBundleVersion"]
    )
  }

  package var versionLine: String {
    switch (version, build) {
    case (.some(let version), .some(let build)):
      return "版本 \(version)（构建 \(build)）"
    case (.some(let version), .none):
      return "版本 \(version)"
    case (.none, .some(let build)):
      return "构建 \(build)"
    case (.none, .none):
      return "开发版本"
    }
  }

  private static func nonemptyString(_ value: Any?) -> String? {
    guard let string = value as? String else { return nil }
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
