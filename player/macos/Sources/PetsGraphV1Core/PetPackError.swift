import Foundation

public struct PetPackError: Error, CustomStringConvertible, Equatable, Sendable {
  public let code: String
  public let detail: String

  public init(_ code: String, _ detail: String) {
    self.code = code
    self.detail = detail
  }

  public var description: String {
    "\(code): \(detail)"
  }
}

@inline(__always)
func fail(_ code: String, _ detail: String) throws -> Never {
  throw PetPackError(code, detail)
}
