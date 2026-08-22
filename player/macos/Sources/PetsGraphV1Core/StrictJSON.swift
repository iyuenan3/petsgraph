import Foundation

enum StrictJSON {
  static func decode<T: Decodable>(_ type: T.Type, from data: Data, path: String) throws -> T {
    var scanner = JSONScanner(data: data, path: path)
    try scanner.validate()
    do {
      return try JSONDecoder().decode(type, from: data)
    } catch {
      try fail("invalid_json", "\(path) does not match the PetPack 1.0 contract")
    }
  }

  static func object(from data: Data, path: String) throws -> [String: Any] {
    var scanner = JSONScanner(data: data, path: path)
    try scanner.validate()
    do {
      guard
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
      else { try fail("invalid_json_shape", "\(path) must be an object") }
      return object
    } catch let error as PetPackError {
      throw error
    } catch {
      try fail("invalid_json", "\(path) is not valid UTF-8 JSON")
    }
  }
}

private struct JSONScanner {
  private let bytes: [UInt8]
  private let path: String
  private var index = 0

  init(data: Data, path: String) {
    bytes = Array(data)
    self.path = path
  }

  mutating func validate() throws {
    guard String(data: Data(bytes), encoding: .utf8) != nil else {
      try fail("invalid_utf8", "\(path) is not UTF-8")
    }
    skipWhitespace()
    try parseValue()
    skipWhitespace()
    guard index == bytes.count else {
      try fail("invalid_json", "\(path) contains trailing JSON data")
    }
  }

  private mutating func parseValue() throws {
    guard index < bytes.count else { try invalid() }
    switch bytes[index] {
    case 0x7b: try parseObject()
    case 0x5b: try parseArray()
    case 0x22: _ = try parseString()
    case 0x74: try consume("true")
    case 0x66: try consume("false")
    case 0x6e: try consume("null")
    case 0x2d, 0x30...0x39: try parseNumber()
    default: try invalid()
    }
  }

  private mutating func parseObject() throws {
    index += 1
    skipWhitespace()
    if consumeIf(0x7d) { return }
    var keys = Set<String>()
    while true {
      guard index < bytes.count, bytes[index] == 0x22 else { try invalid() }
      let key = try parseString()
      guard keys.insert(key).inserted else {
        try fail("duplicate_json_key", "\(path) contains a duplicate object key")
      }
      skipWhitespace()
      guard consumeIf(0x3a) else { try invalid() }
      skipWhitespace()
      try parseValue()
      skipWhitespace()
      if consumeIf(0x7d) { return }
      guard consumeIf(0x2c) else { try invalid() }
      skipWhitespace()
    }
  }

  private mutating func parseArray() throws {
    index += 1
    skipWhitespace()
    if consumeIf(0x5d) { return }
    while true {
      try parseValue()
      skipWhitespace()
      if consumeIf(0x5d) { return }
      guard consumeIf(0x2c) else { try invalid() }
      skipWhitespace()
    }
  }

  private mutating func parseString() throws -> String {
    let start = index
    index += 1
    while index < bytes.count {
      let byte = bytes[index]
      if byte == 0x22 {
        index += 1
        let data = Data(bytes[start..<index])
        do {
          return try JSONDecoder().decode(String.self, from: data)
        } catch {
          try invalid()
        }
      }
      if byte < 0x20 { try invalid() }
      if byte == 0x5c {
        index += 1
        guard index < bytes.count else { try invalid() }
        if bytes[index] == 0x75 {
          guard index + 4 < bytes.count else { try invalid() }
          for digit in bytes[(index + 1)...(index + 4)] where !Self.isHex(digit) {
            _ = digit
            try invalid()
          }
          index += 5
          continue
        }
        guard [0x22, 0x5c, 0x2f, 0x62, 0x66, 0x6e, 0x72, 0x74].contains(bytes[index]) else {
          try invalid()
        }
      }
      index += 1
    }
    try invalid()
  }

  private mutating func parseNumber() throws {
    if consumeIf(0x2d), index == bytes.count { try invalid() }
    if consumeIf(0x30) {
      if index < bytes.count, Self.isDigit(bytes[index]) { try invalid() }
    } else {
      guard index < bytes.count, (0x31...0x39).contains(bytes[index]) else { try invalid() }
      while index < bytes.count, Self.isDigit(bytes[index]) { index += 1 }
    }
    if consumeIf(0x2e) {
      guard index < bytes.count, Self.isDigit(bytes[index]) else { try invalid() }
      while index < bytes.count, Self.isDigit(bytes[index]) { index += 1 }
    }
    if index < bytes.count, bytes[index] == 0x65 || bytes[index] == 0x45 {
      index += 1
      if index < bytes.count, bytes[index] == 0x2b || bytes[index] == 0x2d { index += 1 }
      guard index < bytes.count, Self.isDigit(bytes[index]) else { try invalid() }
      while index < bytes.count, Self.isDigit(bytes[index]) { index += 1 }
    }
  }

  private mutating func consume(_ literal: String) throws {
    let expected = Array(literal.utf8)
    guard index + expected.count <= bytes.count,
      Array(bytes[index..<(index + expected.count)]) == expected
    else { try invalid() }
    index += expected.count
  }

  private mutating func skipWhitespace() {
    while index < bytes.count, [0x20, 0x09, 0x0a, 0x0d].contains(bytes[index]) {
      index += 1
    }
  }

  private mutating func consumeIf(_ byte: UInt8) -> Bool {
    guard index < bytes.count, bytes[index] == byte else { return false }
    index += 1
    return true
  }

  private func invalid() throws -> Never {
    try fail("invalid_json", "\(path) is not valid JSON")
  }

  private static func isDigit(_ byte: UInt8) -> Bool { (0x30...0x39).contains(byte) }
  private static func isHex(_ byte: UInt8) -> Bool {
    isDigit(byte) || (0x41...0x46).contains(byte) || (0x61...0x66).contains(byte)
  }
}
