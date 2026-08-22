import CryptoKit
import Foundation
import zlib

struct ZipArchiveLimits: Sendable {
  let maxEntries = 100_000
  let maxArchiveBytes: UInt64 = 64 * 1024 * 1024 * 1024
  let maxUncompressedBytes: UInt64 = 64 * 1024 * 1024 * 1024
  let maxSingleEntryBytes: UInt64 = 32 * 1024 * 1024 * 1024
  let maxCompressionRatio = 200.0
}

struct ZipEntry: Sendable {
  let path: String
  let flags: UInt16
  let compressionMethod: UInt16
  let crc32: UInt32
  let compressedSize: UInt64
  let uncompressedSize: UInt64
  let localHeaderOffset: UInt64
  let externalAttributes: UInt32
  let isDirectory: Bool
  let dataOffset: UInt64
}

struct ExtractedZip: Sendable {
  let entries: [ZipEntry]
  let digests: [String: String]
  let archiveSHA256: String
  let archiveBytes: UInt64
  let uncompressedBytes: UInt64
}

final class SafeZipArchive {
  private static let localSignature: UInt32 = 0x0403_4b50
  private static let centralSignature: UInt32 = 0x0201_4b50
  private static let endSignature: UInt32 = 0x0605_4b50
  private static let zip64EndSignature: UInt32 = 0x0606_4b50
  private static let zip64LocatorSignature: UInt32 = 0x0706_4b50
  private static let descriptorSignature: UInt32 = 0x0807_4b50

  private let url: URL
  private let handle: FileHandle
  private let limits: ZipArchiveLimits
  private let centralOffset: UInt64
  private(set) var entries: [ZipEntry] = []
  let archiveBytes: UInt64
  let uncompressedBytes: UInt64

  init(url: URL, limits: ZipArchiveLimits = .init()) throws {
    self.url = url
    self.limits = limits
    let values = try url.resourceValues(forKeys: [
      .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
    ])
    guard
      url.pathExtension.lowercased() == "petpack",
      values.isRegularFile == true,
      values.isSymbolicLink != true,
      let byteCount = values.fileSize,
      byteCount > 0
    else {
      throw PetPackError("invalid_container", "input must be one regular .petpack file")
    }
    archiveBytes = UInt64(byteCount)
    guard archiveBytes <= limits.maxArchiveBytes else {
      throw PetPackError("archive_budget", "archive exceeds the byte budget")
    }
    handle = try FileHandle(forReadingFrom: url)

    let end = try Self.readEndRecord(handle: handle, archiveBytes: archiveBytes)
    centralOffset = end.centralOffset
    guard end.entryCount > 0, end.entryCount <= UInt64(limits.maxEntries) else {
      throw PetPackError("entry_budget", "ZIP entry count is outside the allowed budget")
    }
    guard end.centralOffset + end.centralSize == end.centralEnd else {
      throw PetPackError("invalid_container", "ZIP central directory is not contiguous")
    }
    let centralEntries = try Self.readCentralDirectory(
      handle: handle,
      entryCount: end.entryCount,
      centralOffset: end.centralOffset,
      centralSize: end.centralSize,
      limits: limits
    )
    let validated = try Self.validateEntries(
      centralEntries,
      handle: handle,
      centralOffset: end.centralOffset,
      limits: limits
    )
    entries = validated.entries
    uncompressedBytes = validated.total
  }

  deinit {
    try? handle.close()
  }

  func read(_ entry: ZipEntry, maximumBytes: UInt64) throws -> Data {
    guard entry.uncompressedSize <= maximumBytes, entry.uncompressedSize <= UInt64(Int.max) else {
      try fail("entry_budget", "entry exceeds in-memory budget: \(entry.path)")
    }
    var result = Data()
    result.reserveCapacity(Int(entry.uncompressedSize))
    _ = try stream(entry) { result.append($0) }
    return result
  }

  func extract(to destination: URL) throws -> ExtractedZip {
    let fileManager = FileManager.default
    var isDirectory: ObjCBool = false
    let destinationValues = try destination.resourceValues(forKeys: [.isSymbolicLinkKey])
    guard
      destinationValues.isSymbolicLink != true,
      fileManager.fileExists(atPath: destination.path, isDirectory: &isDirectory),
      isDirectory.boolValue,
      (try fileManager.contentsOfDirectory(atPath: destination.path)).isEmpty
    else {
      try fail("invalid_destination", "extraction destination must be an empty directory")
    }

    var digests: [String: String] = [:]
    for entry in entries {
      let target = destination.appendingPathComponent(entry.path, isDirectory: entry.isDirectory)
      if entry.isDirectory {
        try fileManager.createDirectory(
          at: target,
          withIntermediateDirectories: true,
          attributes: [.posixPermissions: 0o700]
        )
        continue
      }
      try fileManager.createDirectory(
        at: target.deletingLastPathComponent(),
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
      )
      guard
        fileManager.createFile(
          atPath: target.path,
          contents: nil,
          attributes: [.posixPermissions: 0o600]
        )
      else {
        try fail("io_error", "cannot create extracted runtime file")
      }
      let output = try FileHandle(forWritingTo: target)
      do {
        let digest = try stream(entry) { try output.write(contentsOf: $0) }
        try output.synchronize()
        try output.close()
        digests[entry.path] = digest
      } catch {
        try? output.close()
        throw error
      }
    }
    return ExtractedZip(
      entries: entries,
      digests: digests,
      archiveSHA256: try Self.sha256(of: url),
      archiveBytes: archiveBytes,
      uncompressedBytes: uncompressedBytes
    )
  }

  private func stream(
    _ entry: ZipEntry,
    sink: (Data) throws -> Void
  ) throws -> String {
    try handle.seek(toOffset: entry.dataOffset)
    var hasher = SHA256()
    var checksum = CRC32()
    var written: UInt64 = 0

    func consume(_ data: Data) throws {
      guard written + UInt64(data.count) <= entry.uncompressedSize else {
        try fail("corrupt_entry", "entry expands beyond its declared size: \(entry.path)")
      }
      hasher.update(data: data)
      checksum.update(data)
      written += UInt64(data.count)
      try sink(data)
    }

    switch entry.compressionMethod {
    case 0:
      var remaining = entry.compressedSize
      while remaining > 0 {
        let count = Int(min(remaining, 1024 * 1024))
        let data = try readExact(count)
        try consume(data)
        remaining -= UInt64(count)
      }
    case 8:
      try inflate(entry: entry, consume: consume)
    default:
      try fail("unsupported_compression", "unsupported compression for \(entry.path)")
    }

    guard written == entry.uncompressedSize else {
      try fail("corrupt_entry", "entry length mismatch: \(entry.path)")
    }
    guard checksum.value == entry.crc32 else {
      try fail("corrupt_entry", "entry CRC mismatch: \(entry.path)")
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }

  private func inflate(
    entry: ZipEntry,
    consume: (Data) throws -> Void
  ) throws {
    var stream = z_stream()
    let initialized = inflateInit2_(
      &stream,
      -MAX_WBITS,
      ZLIB_VERSION,
      Int32(MemoryLayout<z_stream>.size)
    )
    guard initialized == Z_OK else {
      try fail("corrupt_entry", "cannot initialize DEFLATE decoder")
    }
    defer { inflateEnd(&stream) }

    var remaining = entry.compressedSize
    var reachedEnd = false
    while remaining > 0, !reachedEnd {
      let count = Int(min(remaining, 1024 * 1024))
      let input = try readExact(count)
      remaining -= UInt64(count)
      try input.withUnsafeBytes { rawInput in
        guard let inputBase = rawInput.bindMemory(to: UInt8.self).baseAddress else { return }
        stream.next_in = UnsafeMutablePointer(mutating: inputBase)
        stream.avail_in = uInt(count)
        repeat {
          var output = Data(count: 1024 * 1024)
          var status = Z_OK
          let produced = output.withUnsafeMutableBytes { rawOutput -> Int in
            let outputBase = rawOutput.bindMemory(to: UInt8.self).baseAddress!
            stream.next_out = outputBase
            stream.avail_out = uInt(rawOutput.count)
            status = zlib.inflate(&stream, Z_NO_FLUSH)
            return rawOutput.count - Int(stream.avail_out)
          }
          guard status == Z_OK || status == Z_STREAM_END else {
            try fail("corrupt_entry", "invalid DEFLATE stream: \(entry.path)")
          }
          if produced > 0 {
            output.removeSubrange(produced..<output.count)
            try consume(output)
          }
          if status == Z_STREAM_END {
            reachedEnd = true
            guard stream.avail_in == 0, remaining == 0 else {
              try fail("corrupt_entry", "trailing compressed data: \(entry.path)")
            }
            break
          }
        } while stream.avail_in > 0
      }
    }
    guard reachedEnd else {
      try fail("corrupt_entry", "truncated DEFLATE stream: \(entry.path)")
    }
  }

  private func readExact(_ count: Int) throws -> Data {
    if count == 0 { return Data() }
    let offset = try handle.offset()
    var result = Data()
    result.reserveCapacity(count)
    while result.count < count {
      guard let data = try handle.read(upToCount: count - result.count), !data.isEmpty else {
        try fail(
          "invalid_container", "unexpected end of ZIP archive at byte \(offset), wanted \(count)")
      }
      result.append(data)
    }
    return result
  }

  private static func readEndRecord(
    handle: FileHandle,
    archiveBytes: UInt64
  ) throws -> ZipEndRecord {
    guard archiveBytes >= 22 else {
      try fail("invalid_container", "archive is too short")
    }
    try handle.seek(toOffset: 0)
    let signature = try readExact(handle, 4).u32(0)
    guard signature == localSignature else {
      try fail("invalid_container", "archive must start with a ZIP local header")
    }
    let tailSize = Int(min(archiveBytes, 65_557))
    let tailOffset = archiveBytes - UInt64(tailSize)
    try handle.seek(toOffset: tailOffset)
    let tail = try readExact(handle, tailSize)
    guard let endIndex = tail.lastIndex(ofSignature: endSignature) else {
      try fail("invalid_container", "archive has no ZIP end record")
    }
    guard endIndex + 22 <= tail.count else {
      try fail("invalid_container", "archive has an incomplete ZIP end record")
    }
    let commentLength = Int(tail.u16(endIndex + 20))
    guard commentLength == 0, endIndex + 22 == tail.count else {
      try fail("invalid_container", "ZIP comments or trailing data are not allowed")
    }
    let endOffset = tailOffset + UInt64(endIndex)
    let disk = tail.u16(endIndex + 4)
    let centralDisk = tail.u16(endIndex + 6)
    guard disk == 0, centralDisk == 0 else {
      try fail("invalid_container", "split ZIP archives are not supported")
    }
    let count16 = tail.u16(endIndex + 10)
    let size32 = tail.u32(endIndex + 12)
    let offset32 = tail.u32(endIndex + 16)
    if count16 != UInt16.max, size32 != UInt32.max, offset32 != UInt32.max {
      guard tail.u16(endIndex + 8) == count16 else {
        try fail("invalid_container", "ZIP entry counts are inconsistent")
      }
      return ZipEndRecord(
        entryCount: UInt64(count16),
        centralSize: UInt64(size32),
        centralOffset: UInt64(offset32),
        centralEnd: endOffset
      )
    }

    guard endOffset >= 20 else {
      try fail("invalid_container", "ZIP64 locator is missing")
    }
    try handle.seek(toOffset: endOffset - 20)
    let locator = try readExact(handle, 20)
    guard
      locator.u32(0) == zip64LocatorSignature,
      locator.u32(4) == 0,
      locator.u32(16) == 1
    else {
      try fail("invalid_container", "invalid ZIP64 locator")
    }
    let zip64Offset = locator.u64(8)
    try handle.seek(toOffset: zip64Offset)
    let record = try readExact(handle, 56)
    guard
      record.u32(0) == zip64EndSignature,
      record.u64(4) >= 44,
      record.u32(16) == 0,
      record.u32(20) == 0,
      record.u64(24) == record.u64(32),
      zip64Offset + 12 + record.u64(4) == endOffset - 20
    else {
      try fail("invalid_container", "invalid ZIP64 end record")
    }
    return ZipEndRecord(
      entryCount: record.u64(32),
      centralSize: record.u64(40),
      centralOffset: record.u64(48),
      centralEnd: zip64Offset
    )
  }

  private static func readCentralDirectory(
    handle: FileHandle,
    entryCount: UInt64,
    centralOffset: UInt64,
    centralSize: UInt64,
    limits: ZipArchiveLimits
  ) throws -> [ZipEntry] {
    try handle.seek(toOffset: centralOffset)
    var consumed: UInt64 = 0
    var result: [ZipEntry] = []
    result.reserveCapacity(Int(entryCount))
    for _ in 0..<entryCount {
      let fixed = try readExact(handle, 46)
      consumed += 46
      guard fixed.u32(0) == centralSignature else {
        try fail("invalid_container", "invalid central directory entry")
      }
      let flags = fixed.u16(8)
      let method = fixed.u16(10)
      let crc = fixed.u32(16)
      var compressed = UInt64(fixed.u32(20))
      var uncompressed = UInt64(fixed.u32(24))
      let nameLength = Int(fixed.u16(28))
      let extraLength = Int(fixed.u16(30))
      let commentLength = Int(fixed.u16(32))
      let diskStart = fixed.u16(34)
      let externalAttributes = fixed.u32(38)
      var localOffset = UInt64(fixed.u32(42))
      let variableLength = nameLength + extraLength + commentLength
      guard commentLength == 0 else {
        try fail("noncanonical_zip", "ZIP entry comments are not allowed")
      }
      guard consumed + UInt64(variableLength) <= centralSize else {
        try fail("invalid_container", "central directory entry exceeds its bounds")
      }
      let variable = try readExact(handle, variableLength)
      consumed += UInt64(variableLength)
      let nameData = variable.subdata(in: 0..<nameLength)
      guard let path = String(data: nameData, encoding: .utf8) else {
        try fail("invalid_utf8", "ZIP entry path is not UTF-8")
      }
      let extra = variable.subdata(in: nameLength..<(nameLength + extraLength))
      let needsUncompressed = uncompressed == UInt64(UInt32.max)
      let needsCompressed = compressed == UInt64(UInt32.max)
      let needsOffset = localOffset == UInt64(UInt32.max)
      let needsDisk = diskStart == UInt16.max
      if needsUncompressed || needsCompressed || needsOffset || needsDisk {
        let values = try zip64Values(
          extra,
          uncompressed: needsUncompressed,
          compressed: needsCompressed,
          offset: needsOffset,
          disk: needsDisk
        )
        if let value = values.uncompressed { uncompressed = value }
        if let value = values.compressed { compressed = value }
        if let value = values.offset { localOffset = value }
        if let value = values.disk, value != 0 {
          try fail("invalid_container", "split ZIP archives are not supported")
        }
      } else if diskStart != 0 {
        try fail("invalid_container", "split ZIP archives are not supported")
      }
      let directory = path.hasSuffix("/")
      result.append(
        ZipEntry(
          path: path,
          flags: flags,
          compressionMethod: method,
          crc32: crc,
          compressedSize: compressed,
          uncompressedSize: uncompressed,
          localHeaderOffset: localOffset,
          externalAttributes: externalAttributes,
          isDirectory: directory,
          dataOffset: 0
        ))
    }
    guard consumed == centralSize else {
      try fail("invalid_container", "central directory byte count is inconsistent")
    }
    return result
  }

  private static func validateEntries(
    _ rawEntries: [ZipEntry],
    handle: FileHandle,
    centralOffset: UInt64,
    limits: ZipArchiveLimits
  ) throws -> (entries: [ZipEntry], total: UInt64) {
    var exactPaths = Set<String>()
    var foldedPaths = Set<String>()
    var total: UInt64 = 0
    var entries: [ZipEntry] = []
    entries.reserveCapacity(rawEntries.count)
    for entry in rawEntries {
      try validatePath(entry.path, directory: entry.isDirectory)
      guard exactPaths.insert(entry.path).inserted else {
        try fail("duplicate_path", "duplicate ZIP entry")
      }
      let folded = entry.path.precomposedStringWithCanonicalMapping
        .folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
      guard foldedPaths.insert(folded).inserted else {
        try fail("casefold_collision", "ZIP entries collide across platforms")
      }
      guard entry.flags & 0x41 == 0 else {
        try fail("encrypted_entry", "encrypted ZIP entries are not supported")
      }
      guard entry.compressionMethod == 0 || entry.compressionMethod == 8 else {
        try fail("unsupported_compression", "unsupported compression for \(entry.path)")
      }
      let mode = (entry.externalAttributes >> 16) & 0xffff
      guard mode & 0o170000 != 0o120000 else {
        try fail("symlink_entry", "symbolic link entries are not supported")
      }
      if !entry.isDirectory {
        guard mode == 0 || mode & 0o111 == 0 else {
          try fail("executable_entry", "executable permission bits are not allowed")
        }
        let suffix = URL(fileURLWithPath: entry.path).pathExtension.lowercased()
        let prohibited = Set([
          "app", "bat", "class", "cmd", "com", "dll", "dylib", "exe", "jar", "js",
          "msi", "pkg", "ps1", "py", "sh", "so", "swift", "vbs",
        ])
        guard !prohibited.contains(suffix) else {
          try fail("executable_entry", "executable content is not allowed")
        }
        guard entry.uncompressedSize <= limits.maxSingleEntryBytes else {
          try fail("entry_budget", "entry exceeds the byte budget")
        }
        if entry.uncompressedSize > 0 {
          guard entry.compressedSize > 0 else {
            try fail("compression_ratio", "invalid compressed size")
          }
          guard
            Double(entry.uncompressedSize) / Double(entry.compressedSize)
              <= limits.maxCompressionRatio
          else {
            try fail("compression_ratio", "entry compression ratio is too high")
          }
        }
        let (next, overflow) = total.addingReportingOverflow(entry.uncompressedSize)
        guard !overflow, next <= limits.maxUncompressedBytes else {
          try fail("archive_budget", "uncompressed archive exceeds the byte budget")
        }
        total = next
      } else if entry.compressedSize != 0 || entry.uncompressedSize != 0 {
        try fail("invalid_container", "directory entry contains data")
      }

      try handle.seek(toOffset: entry.localHeaderOffset)
      let local = try readExact(handle, 30)
      guard local.u32(0) == localSignature else {
        try fail("invalid_container", "missing local header for \(entry.path)")
      }
      let localFlags = local.u16(6)
      let localMethod = local.u16(8)
      let nameLength = Int(local.u16(26))
      let extraLength = Int(local.u16(28))
      let nameData = try readExact(handle, nameLength)
      guard String(data: nameData, encoding: .utf8) == entry.path else {
        try fail("invalid_container", "local and central paths differ")
      }
      guard localFlags == entry.flags, localMethod == entry.compressionMethod else {
        try fail("invalid_container", "local and central ZIP flags differ")
      }
      _ = try readExact(handle, extraLength)
      let dataOffset = entry.localHeaderOffset + 30 + UInt64(nameLength + extraLength)
      guard dataOffset <= centralOffset, entry.compressedSize <= centralOffset - dataOffset else {
        try fail("invalid_container", "entry data exceeds the local data area")
      }
      entries.append(
        ZipEntry(
          path: entry.path,
          flags: entry.flags,
          compressionMethod: entry.compressionMethod,
          crc32: entry.crc32,
          compressedSize: entry.compressedSize,
          uncompressedSize: entry.uncompressedSize,
          localHeaderOffset: entry.localHeaderOffset,
          externalAttributes: entry.externalAttributes,
          isDirectory: entry.isDirectory,
          dataOffset: dataOffset
        ))
    }

    let ordered = entries.sorted { $0.localHeaderOffset < $1.localHeaderOffset }
    guard ordered.first?.localHeaderOffset == 0 else {
      try fail("invalid_container", "archive contains a leading payload")
    }
    for index in ordered.indices {
      let entry = ordered[index]
      let nextOffset =
        index + 1 < ordered.count
        ? ordered[index + 1].localHeaderOffset
        : centralOffset
      let dataEnd = entry.dataOffset + entry.compressedSize
      guard nextOffset >= dataEnd else {
        try fail("invalid_container", "ZIP local entries overlap")
      }
      let gap = nextOffset - dataEnd
      if entry.flags & 0x8 == 0 {
        guard gap == 0 else {
          try fail("invalid_container", "archive contains an undeclared local payload")
        }
      } else {
        try validateDescriptor(
          handle: handle,
          offset: dataEnd,
          length: gap,
          entry: entry
        )
      }
    }

    let entriesByPath = Dictionary(uniqueKeysWithValues: entries.map { ($0.path, $0) })
    let centralOrder = try rawEntries.map { entry in
      guard let validated = entriesByPath[entry.path] else {
        try fail("invalid_container", "missing local data offset")
      }
      return validated
    }
    return (centralOrder, total)
  }

  private static func validateDescriptor(
    handle: FileHandle,
    offset: UInt64,
    length: UInt64,
    entry: ZipEntry
  ) throws {
    guard [12, 16, 20, 24].contains(length), length <= UInt64(Int.max) else {
      try fail("invalid_container", "invalid ZIP data descriptor")
    }
    try handle.seek(toOffset: offset)
    let data = try readExact(handle, Int(length))
    let hasSignature = data.u32(0) == descriptorSignature
    let cursor = hasSignature ? 4 : 0
    let zip64 = length - UInt64(cursor) == 20
    guard data.u32(cursor) == entry.crc32 else {
      try fail("invalid_container", "ZIP data descriptor CRC differs")
    }
    if zip64 {
      guard
        data.u64(cursor + 4) == entry.compressedSize,
        data.u64(cursor + 12) == entry.uncompressedSize
      else { try fail("invalid_container", "ZIP64 data descriptor sizes differ") }
    } else {
      guard
        entry.compressedSize <= UInt64(UInt32.max),
        entry.uncompressedSize <= UInt64(UInt32.max),
        data.u32(cursor + 4) == UInt32(entry.compressedSize),
        data.u32(cursor + 8) == UInt32(entry.uncompressedSize)
      else { try fail("invalid_container", "ZIP data descriptor sizes differ") }
    }
  }

  private static func validatePath(_ path: String, directory: Bool) throws {
    guard
      !path.isEmpty,
      !path.hasPrefix("/"),
      !path.contains("\\"),
      !path.contains("\0"),
      path.precomposedStringWithCanonicalMapping == path
    else { try fail("unsafe_path", "ZIP entry has an unsafe path") }
    let candidate = directory && path.hasSuffix("/") ? String(path.dropLast()) : path
    let components = candidate.split(separator: "/", omittingEmptySubsequences: false).map(
      String.init)
    guard
      !candidate.isEmpty,
      !candidate.hasSuffix("/"),
      components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
    else { try fail("unsafe_path", "ZIP entry has an unsafe path") }
    let reserved = Set(
      ["con", "prn", "aux", "nul", "clock$"]
        + (1...9).map { "com\($0)" }
        + (1...9).map { "lpt\($0)" }
    )
    for component in components {
      guard
        component == component.trimmingCharacters(in: .whitespacesAndNewlines),
        !component.hasSuffix("."),
        !component.hasSuffix(" "),
        !component.contains(":"),
        component.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value != 127 }),
        !reserved.contains(component.split(separator: ".", maxSplits: 1).first!.lowercased())
      else { try fail("unsafe_path", "ZIP entry path is not portable") }
    }
  }

  private static func zip64Values(
    _ extra: Data,
    uncompressed: Bool,
    compressed: Bool,
    offset: Bool,
    disk: Bool
  ) throws -> (uncompressed: UInt64?, compressed: UInt64?, offset: UInt64?, disk: UInt32?) {
    var cursor = 0
    while cursor + 4 <= extra.count {
      let identifier = extra.u16(cursor)
      let length = Int(extra.u16(cursor + 2))
      cursor += 4
      guard cursor + length <= extra.count else {
        try fail("invalid_container", "malformed ZIP extra field")
      }
      if identifier == 0x0001 {
        let end = cursor + length
        var valueCursor = cursor
        func next64(_ needed: Bool) throws -> UInt64? {
          guard needed else { return nil }
          guard valueCursor + 8 <= end else {
            try fail("invalid_container", "incomplete ZIP64 extra field")
          }
          defer { valueCursor += 8 }
          return extra.u64(valueCursor)
        }
        let a = try next64(uncompressed)
        let b = try next64(compressed)
        let c = try next64(offset)
        var d: UInt32?
        if disk {
          guard valueCursor + 4 <= end else {
            try fail("invalid_container", "incomplete ZIP64 disk field")
          }
          d = extra.u32(valueCursor)
        }
        return (a, b, c, d)
      }
      cursor += length
    }
    try fail("invalid_container", "required ZIP64 extra field is missing")
  }

  private static func sha256(of url: URL) throws -> String {
    let input = try FileHandle(forReadingFrom: url)
    defer { try? input.close() }
    var hasher = SHA256()
    while let data = try input.read(upToCount: 1024 * 1024), !data.isEmpty {
      hasher.update(data: data)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }

  private static func readExact(_ handle: FileHandle, _ count: Int) throws -> Data {
    if count == 0 { return Data() }
    let offset = try handle.offset()
    var result = Data()
    result.reserveCapacity(count)
    while result.count < count {
      guard let data = try handle.read(upToCount: count - result.count), !data.isEmpty else {
        try fail(
          "invalid_container", "unexpected end of ZIP archive at byte \(offset), wanted \(count)")
      }
      result.append(data)
    }
    return result
  }
}

private struct ZipEndRecord {
  let entryCount: UInt64
  let centralSize: UInt64
  let centralOffset: UInt64
  let centralEnd: UInt64
}

private struct CRC32 {
  private static let table: [UInt32] = (0..<256).map { value in
    var result = UInt32(value)
    for _ in 0..<8 {
      result = result & 1 == 1 ? 0xedb8_8320 ^ (result >> 1) : result >> 1
    }
    return result
  }

  private var state: UInt32 = 0xffff_ffff

  mutating func update(_ data: Data) {
    for byte in data {
      state = Self.table[Int((state ^ UInt32(byte)) & 0xff)] ^ (state >> 8)
    }
  }

  var value: UInt32 { state ^ 0xffff_ffff }
}

extension Data {
  fileprivate func u16(_ offset: Int) -> UInt16 {
    UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
  }

  fileprivate func u32(_ offset: Int) -> UInt32 {
    UInt32(self[offset])
      | UInt32(self[offset + 1]) << 8
      | UInt32(self[offset + 2]) << 16
      | UInt32(self[offset + 3]) << 24
  }

  fileprivate func u64(_ offset: Int) -> UInt64 {
    UInt64(u32(offset)) | UInt64(u32(offset + 4)) << 32
  }

  fileprivate func lastIndex(ofSignature signature: UInt32) -> Int? {
    guard count >= 4 else { return nil }
    for index in stride(from: count - 4, through: 0, by: -1) where u32(index) == signature {
      return index
    }
    return nil
  }
}
