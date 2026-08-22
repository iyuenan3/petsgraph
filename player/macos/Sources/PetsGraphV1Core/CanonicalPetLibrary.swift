import Foundation

public struct InstalledPet: Codable, Equatable, Sendable {
  public let packageID: String
  public let petID: String
  public let displayName: String
  public let species: String
  public let contentVersion: SemanticVersion
  public let archiveSHA256: String
  public let archiveBytes: Int64
}

public enum PetImportOutcome: Equatable, Sendable {
  case installed(InstalledPet)
  case updated(previous: InstalledPet, current: InstalledPet)
  case alreadyInstalled(InstalledPet)
  case updateCancelled(current: InstalledPet, proposed: InstalledPet)
}

public final class CanonicalPetLibrary: @unchecked Sendable {
  private struct Registry: Codable {
    let formatVersion: Int
    var packages: [InstalledPet]
  }

  public let rootURL: URL
  private let packagesURL: URL
  private let cacheURL: URL
  private let stagingURL: URL
  private let registryURL: URL
  private let validator = PetPackValidator()
  private let fileManager: FileManager
  private let lock = NSLock()

  public init(rootURL: URL? = nil, fileManager: FileManager = .default) throws {
    self.fileManager = fileManager
    if let rootURL {
      self.rootURL = rootURL.standardizedFileURL
    } else {
      guard
        let applicationSupport = fileManager.urls(
          for: .applicationSupportDirectory,
          in: .userDomainMask
        ).first
      else {
        throw PetPackError("library_unavailable", "application support directory is unavailable")
      }
      self.rootURL = applicationSupport.appendingPathComponent("PetsGraph", isDirectory: true)
    }
    packagesURL = self.rootURL.appendingPathComponent("Library", isDirectory: true)
    cacheURL = self.rootURL.appendingPathComponent("Cache", isDirectory: true)
    stagingURL = self.rootURL.appendingPathComponent("Staging", isDirectory: true)
    registryURL = self.rootURL.appendingPathComponent("registry.json", isDirectory: false)
    try ensureDirectories()
  }

  public func installedPets() throws -> [InstalledPet] {
    try synchronized {
      try readRegistry().packages.sorted { $0.packageID < $1.packageID }
    }
  }

  public func importPetPack(
    from sourceURL: URL,
    confirmUpdate: (_ current: InstalledPet, _ proposed: InstalledPet) -> Bool
  ) throws -> PetImportOutcome {
    try synchronized {
      let staging = stagingURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
      let stagedArchive = staging.appendingPathComponent("source.petpack", isDirectory: false)
      let stagedRuntime = staging.appendingPathComponent("runtime", isDirectory: true)
      try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
      defer { try? fileManager.removeItem(at: staging) }
      do {
        try fileManager.copyItem(at: sourceURL, to: stagedArchive)
      } catch {
        throw PetPackError("import_copy_failed", "could not copy the selected PetPack")
      }
      try fileManager.createDirectory(at: stagedRuntime, withIntermediateDirectories: false)
      let validated = try validator.validateAndExtract(sourceURL: stagedArchive, to: stagedRuntime)
      let proposed = InstalledPet(
        packageID: validated.report.packageID,
        petID: validated.report.petID,
        displayName: validated.package.manifest.pet.displayName,
        species: validated.report.species,
        contentVersion: validated.report.contentVersion,
        archiveSHA256: validated.report.archiveSHA256,
        archiveBytes: validated.report.archiveBytes
      )

      var registry = try readRegistry()
      let current = registry.packages.first { $0.packageID == proposed.packageID }
      if let current {
        if current.contentVersion == proposed.contentVersion {
          guard current.archiveSHA256 == proposed.archiveSHA256 else {
            throw PetPackError(
              "version_conflict",
              "the same package id and content version have different bytes"
            )
          }
          return .alreadyInstalled(current)
        }
        guard current.contentVersion < proposed.contentVersion else {
          throw PetPackError(
            "downgrade_rejected", "installing an older content version is not allowed")
        }
        guard confirmUpdate(current, proposed) else {
          return .updateCancelled(current: current, proposed: proposed)
        }
      }

      let finalArchive = archiveURL(for: proposed)
      let finalRuntime = runtimeURL(for: proposed)
      try prepareParent(of: finalArchive)
      try prepareParent(of: finalRuntime)
      if fileManager.fileExists(atPath: finalArchive.path) {
        try fileManager.removeItem(at: finalArchive)
      }
      if fileManager.fileExists(atPath: finalRuntime.path) {
        try fileManager.removeItem(at: finalRuntime)
      }
      try fileManager.moveItem(at: stagedArchive, to: finalArchive)
      do {
        try fileManager.moveItem(at: stagedRuntime, to: finalRuntime)
      } catch {
        try? fileManager.removeItem(at: finalArchive)
        throw error
      }

      registry.packages.removeAll { $0.packageID == proposed.packageID }
      registry.packages.append(proposed)
      do {
        try writeRegistry(registry)
      } catch {
        try? fileManager.removeItem(at: finalArchive)
        try? fileManager.removeItem(at: finalRuntime)
        throw error
      }
      if let current {
        removeManagedFiles(for: current)
        return .updated(previous: current, current: proposed)
      }
      return .installed(proposed)
    }
  }

  public func loadInstalledPetPacks() throws -> [LoadedPetPack] {
    try synchronized {
      let records = try readRegistry().packages.sorted { $0.packageID < $1.packageID }
      return try records.map { try load(record: $0) }
    }
  }

  @discardableResult
  public func uninstall(packageID: String) throws -> InstalledPet? {
    try synchronized {
      var registry = try readRegistry()
      guard let record = registry.packages.first(where: { $0.packageID == packageID }) else {
        return nil
      }
      registry.packages.removeAll { $0.packageID == packageID }
      try writeRegistry(registry)
      removeManagedFiles(for: record)
      return record
    }
  }

  public func uninstallAll() throws -> [InstalledPet] {
    try synchronized {
      let current = try readRegistry().packages
      try writeRegistry(Registry(formatVersion: 1, packages: []))
      for record in current { removeManagedFiles(for: record) }
      return current
    }
  }

  private func load(record: InstalledPet) throws -> LoadedPetPack {
    let runtime = runtimeURL(for: record)
    do {
      return try validator.loadTrustedRuntime(
        root: runtime,
        archiveSHA256: record.archiveSHA256,
        archiveBytes: UInt64(record.archiveBytes)
      ).package
    } catch {
      let archive = archiveURL(for: record)
      guard fileManager.fileExists(atPath: archive.path) else {
        throw PetPackError("canonical_missing", "the internal canonical PetPack is missing")
      }
      let staging = stagingURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
      let stagedRuntime = staging.appendingPathComponent("runtime", isDirectory: true)
      try fileManager.createDirectory(at: stagedRuntime, withIntermediateDirectories: true)
      defer { try? fileManager.removeItem(at: staging) }
      let rebuilt = try validator.validateAndExtract(sourceURL: archive, to: stagedRuntime)
      guard
        rebuilt.report.packageID == record.packageID,
        rebuilt.report.contentVersion == record.contentVersion,
        rebuilt.report.archiveSHA256 == record.archiveSHA256
      else { throw PetPackError("canonical_mismatch", "the internal canonical PetPack changed") }
      try prepareParent(of: runtime)
      if fileManager.fileExists(atPath: runtime.path) { try fileManager.removeItem(at: runtime) }
      try fileManager.moveItem(at: stagedRuntime, to: runtime)
      return LoadedPetPack(
        runtimeRootURL: runtime,
        manifest: rebuilt.package.manifest,
        graph: rebuilt.package.graph,
        behavior: rebuilt.package.behavior,
        clips: rebuilt.package.clips,
        archiveSHA256: rebuilt.package.archiveSHA256
      )
    }
  }

  private func ensureDirectories() throws {
    for directory in [rootURL, packagesURL, cacheURL, stagingURL] {
      try fileManager.createDirectory(
        at: directory,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
      )
    }
  }

  private func readRegistry() throws -> Registry {
    guard fileManager.fileExists(atPath: registryURL.path) else {
      return Registry(formatVersion: 1, packages: [])
    }
    let data = try Data(contentsOf: registryURL)
    let registry = try StrictJSON.decode(Registry.self, from: data, path: "registry.json")
    guard registry.formatVersion == 1,
      Set(registry.packages.map(\.packageID)).count == registry.packages.count,
      registry.packages.allSatisfy({
        Self.isValidPackageID($0.packageID) && $0.packageID == $0.petID
          && Self.isValidDisplayName($0.displayName)
          && ($0.species == "cat" || $0.species == "dog")
          && $0.archiveBytes > 0
          && UInt64($0.archiveBytes) <= ZipArchiveLimits().maxArchiveBytes
          && Self.isValidSHA256($0.archiveSHA256)
      })
    else { throw PetPackError("registry_corrupt", "the installed-pet registry is invalid") }
    return registry
  }

  private func writeRegistry(_ registry: Registry) throws {
    let sorted = Registry(
      formatVersion: 1,
      packages: registry.packages.sorted { $0.packageID < $1.packageID }
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(sorted)
    let temporary = rootURL.appendingPathComponent("registry-\(UUID().uuidString).tmp")
    try data.write(to: temporary, options: [.atomic])
    do {
      if fileManager.fileExists(atPath: registryURL.path) {
        _ = try fileManager.replaceItemAt(registryURL, withItemAt: temporary)
      } else {
        try fileManager.moveItem(at: temporary, to: registryURL)
      }
    } catch {
      try? fileManager.removeItem(at: temporary)
      throw PetPackError("registry_write_failed", "could not update the installed-pet registry")
    }
  }

  private func archiveURL(for record: InstalledPet) -> URL {
    packagesURL
      .appendingPathComponent(record.packageID, isDirectory: true)
      .appendingPathComponent(record.contentVersion.stringValue, isDirectory: true)
      .appendingPathComponent("\(record.archiveSHA256).petpack", isDirectory: false)
  }

  private func runtimeURL(for record: InstalledPet) -> URL {
    cacheURL
      .appendingPathComponent(record.packageID, isDirectory: true)
      .appendingPathComponent(record.contentVersion.stringValue, isDirectory: true)
      .appendingPathComponent(record.archiveSHA256, isDirectory: true)
  }

  private func prepareParent(of url: URL) throws {
    try fileManager.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
  }

  private func removeManagedFiles(for record: InstalledPet) {
    let packageVersion = archiveURL(for: record).deletingLastPathComponent()
    let cacheVersion = runtimeURL(for: record).deletingLastPathComponent()
    try? fileManager.removeItem(at: packageVersion)
    try? fileManager.removeItem(at: cacheVersion)
    removeIfEmpty(packageVersion.deletingLastPathComponent())
    removeIfEmpty(cacheVersion.deletingLastPathComponent())
  }

  private func removeIfEmpty(_ directory: URL) {
    guard
      let contents = try? fileManager.contentsOfDirectory(atPath: directory.path),
      contents.isEmpty
    else { return }
    try? fileManager.removeItem(at: directory)
  }

  private func synchronized<T>(_ body: () throws -> T) throws -> T {
    lock.lock()
    defer { lock.unlock() }
    return try body()
  }

  private static func isValidPackageID(_ value: String) -> Bool {
    guard !value.isEmpty, value.count <= 80 else { return false }
    var priorWasHyphen = true
    for byte in value.utf8 {
      if byte == 45 {
        if priorWasHyphen { return false }
        priorWasHyphen = true
      } else {
        guard (byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 122) else {
          return false
        }
        priorWasHyphen = false
      }
    }
    return !priorWasHyphen
  }

  private static func isValidDisplayName(_ value: String) -> Bool {
    !value.isEmpty && value.count <= 80
      && value.precomposedStringWithCanonicalMapping == value
      && value.unicodeScalars.allSatisfy { $0.value >= 32 && $0.value != 127 }
  }

  private static func isValidSHA256(_ value: String) -> Bool {
    value.count == 64
      && value.utf8.allSatisfy {
        ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102)
      }
  }
}
