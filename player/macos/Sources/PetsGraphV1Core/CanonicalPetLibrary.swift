import Foundation

public struct InstalledPet: Codable, Equatable, Hashable, Sendable {
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

  private struct UninstallTransaction: Codable {
    let formatVersion: Int
    let records: [InstalledPet]
  }

  private struct ImportTransaction: Codable {
    let formatVersion: Int
    let current: InstalledPet
    let previous: InstalledPet?
  }

  public let rootURL: URL
  private let packagesURL: URL
  private let cacheURL: URL
  private let stagingURL: URL
  private let registryURL: URL
  private let pendingImportURL: URL
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
    pendingImportURL = self.rootURL.appendingPathComponent(
      "pending-import.json", isDirectory: false)
    try ensureDirectories()
    try recoverUninstallTransactions()
    try recoverImportTransaction()
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
      guard !fileManager.fileExists(atPath: pendingImportURL.path) else {
        throw PetPackError("import_pending", "a previous PetPack import is awaiting commit")
      }
      let sourceValues = try sourceURL.resourceValues(forKeys: [
        .isRegularFileKey, .isSymbolicLinkKey,
      ])
      guard sourceValues.isRegularFile == true, sourceValues.isSymbolicLink != true else {
        throw PetPackError("import_source", "selected PetPack must be a regular file")
      }
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
        try writeImportTransaction(
          ImportTransaction(formatVersion: 1, current: proposed, previous: current))
        try writeRegistry(registry)
      } catch {
        try? fileManager.removeItem(at: pendingImportURL)
        try? fileManager.removeItem(at: finalArchive)
        try? fileManager.removeItem(at: finalRuntime)
        throw error
      }
      if let current { return .updated(previous: current, current: proposed) }
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
      let transaction = try stageManagedFiles(for: [record])
      registry.packages.removeAll { $0.packageID == packageID }
      do {
        try writeRegistry(registry)
      } catch {
        try rollback(transaction: transaction)
        throw error
      }
      finish(transaction: transaction)
      return record
    }
  }

  public func uninstallAll() throws -> [InstalledPet] {
    try synchronized {
      let current = try readRegistry().packages
      guard !current.isEmpty else { return [] }
      let transaction = try stageManagedFiles(for: current)
      do {
        try writeRegistry(Registry(formatVersion: 1, packages: []))
      } catch {
        try rollback(transaction: transaction)
        throw error
      }
      finish(transaction: transaction)
      return current
    }
  }

  public func discardObsolete(_ records: [InstalledPet]) throws {
    try synchronized {
      let installed = try readRegistry().packages
      let obsolete = records.filter { record in
        !installed.contains { Self.sameInstalledPet($0, record) }
      }
      guard !obsolete.isEmpty else { return }
      finish(transaction: try stageManagedFiles(for: obsolete))
    }
  }

  public func commitImport(_ outcome: PetImportOutcome) throws {
    let current: InstalledPet?
    switch outcome {
    case .installed(let installed): current = installed
    case .updated(_, let installed): current = installed
    case .alreadyInstalled, .updateCancelled: current = nil
    }
    guard let current else { return }

    try synchronized {
      let transaction = try readImportTransaction()
      let registry = try readRegistry()
      guard Self.sameInstalledPet(transaction.current, current),
        registry.packages.contains(where: { Self.sameInstalledPet($0, current) })
      else {
        throw PetPackError(
          "import_commit_conflict", "the installed-pet registry changed before import commit")
      }
      try fileManager.removeItem(at: pendingImportURL)
    }
  }

  public func rollbackImport(_ outcome: PetImportOutcome) throws {
    let replacement: (current: InstalledPet, previous: InstalledPet?)?
    switch outcome {
    case .installed(let current): replacement = (current, nil)
    case .updated(let previous, let current): replacement = (current, previous)
    case .alreadyInstalled, .updateCancelled: replacement = nil
    }
    guard let replacement else { return }

    try synchronized {
      try rollbackImported(current: replacement.current, previous: replacement.previous)
      try clearImportTransaction(expectedCurrent: replacement.current)
    }
  }

  private func rollbackImported(current: InstalledPet, previous: InstalledPet?) throws {
    var registry = try readRegistry()
    guard registry.packages.contains(where: { Self.sameInstalledPet($0, current) }) else {
      throw PetPackError(
        "import_rollback_conflict", "the installed-pet registry changed before import rollback")
    }
    if let previous {
      guard previous.packageID == current.packageID,
        previous.contentVersion < current.contentVersion
      else {
        throw PetPackError("import_rollback_conflict", "the import rollback identity is invalid")
      }
      _ = try load(record: previous)
    }

    let transaction = try stageManagedFiles(for: [current])
    registry.packages.removeAll { $0.packageID == current.packageID }
    if let previous { registry.packages.append(previous) }
    do {
      try writeRegistry(registry)
    } catch {
      try rollback(transaction: transaction)
      throw error
    }
    finish(transaction: transaction)
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
      registry.packages.allSatisfy(Self.isValidInstalledPet)
    else { throw PetPackError("registry_corrupt", "the installed-pet registry is invalid") }
    return registry
  }

  private func writeImportTransaction(_ transaction: ImportTransaction) throws {
    guard !fileManager.fileExists(atPath: pendingImportURL.path) else {
      throw PetPackError("import_pending", "a previous PetPack import is awaiting commit")
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    do {
      try encoder.encode(transaction).write(to: pendingImportURL, options: [.atomic])
    } catch {
      throw PetPackError("import_journal_failed", "could not create the PetPack import journal")
    }
  }

  private func readImportTransaction() throws -> ImportTransaction {
    guard fileManager.fileExists(atPath: pendingImportURL.path) else {
      throw PetPackError("import_journal_missing", "the PetPack import journal is missing")
    }
    let transaction = try StrictJSON.decode(
      ImportTransaction.self,
      from: Data(contentsOf: pendingImportURL),
      path: "pending-import.json"
    )
    guard transaction.formatVersion == 1,
      Self.isValidInstalledPet(transaction.current),
      transaction.previous.map(Self.isValidInstalledPet) ?? true,
      transaction.previous.map({
        $0.packageID == transaction.current.packageID
          && $0.contentVersion < transaction.current.contentVersion
      }) ?? true
    else {
      throw PetPackError("import_recovery_failed", "the PetPack import journal is invalid")
    }
    return transaction
  }

  private func clearImportTransaction(expectedCurrent: InstalledPet) throws {
    guard fileManager.fileExists(atPath: pendingImportURL.path) else { return }
    guard Self.sameInstalledPet(try readImportTransaction().current, expectedCurrent) else {
      throw PetPackError("import_recovery_failed", "the PetPack import journal changed")
    }
    try fileManager.removeItem(at: pendingImportURL)
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

  private func stageManagedFiles(for records: [InstalledPet]) throws -> URL {
    let transaction = stagingURL.appendingPathComponent(
      "uninstall-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: transaction, withIntermediateDirectories: false)
    let journal = UninstallTransaction(formatVersion: 1, records: records)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    do {
      try encoder.encode(journal).write(
        to: transaction.appendingPathComponent("transaction.json"), options: [.atomic])
    } catch {
      finish(transaction: transaction)
      throw PetPackError(
        "uninstall_stage_failed", "could not create the managed pet removal journal")
    }
    do {
      for record in records {
        try moveManagedVersion(
          from: archiveURL(for: record).deletingLastPathComponent(),
          to: transaction.appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent(record.packageID, isDirectory: true)
            .appendingPathComponent(record.contentVersion.stringValue, isDirectory: true)
        )
        try moveManagedVersion(
          from: runtimeURL(for: record).deletingLastPathComponent(),
          to: transaction.appendingPathComponent("Cache", isDirectory: true)
            .appendingPathComponent(record.packageID, isDirectory: true)
            .appendingPathComponent(record.contentVersion.stringValue, isDirectory: true)
        )
      }
      return transaction
    } catch {
      try? rollback(transaction: transaction)
      throw PetPackError(
        "uninstall_stage_failed", "could not prepare managed pet files for removal")
    }
  }

  private func moveManagedVersion(from source: URL, to destination: URL) throws {
    guard fileManager.fileExists(atPath: source.path) else { return }
    try fileManager.createDirectory(
      at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    try fileManager.moveItem(at: source, to: destination)
    removeIfEmpty(source.deletingLastPathComponent())
  }

  private func rollback(transaction: URL) throws {
    let journalURL = transaction.appendingPathComponent("transaction.json")
    let journal = try JSONDecoder().decode(
      UninstallTransaction.self, from: Data(contentsOf: journalURL))
    for record in journal.records.reversed() {
      try restoreManagedVersion(
        from: transaction.appendingPathComponent("Library", isDirectory: true)
          .appendingPathComponent(record.packageID, isDirectory: true)
          .appendingPathComponent(record.contentVersion.stringValue, isDirectory: true),
        to: archiveURL(for: record).deletingLastPathComponent()
      )
      try restoreManagedVersion(
        from: transaction.appendingPathComponent("Cache", isDirectory: true)
          .appendingPathComponent(record.packageID, isDirectory: true)
          .appendingPathComponent(record.contentVersion.stringValue, isDirectory: true),
        to: runtimeURL(for: record).deletingLastPathComponent()
      )
    }
    try fileManager.removeItem(at: transaction)
  }

  private func restoreManagedVersion(from source: URL, to destination: URL) throws {
    guard fileManager.fileExists(atPath: source.path) else { return }
    guard !fileManager.fileExists(atPath: destination.path) else {
      throw PetPackError("uninstall_recovery_failed", "managed pet recovery target already exists")
    }
    try fileManager.createDirectory(
      at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    try fileManager.moveItem(at: source, to: destination)
  }

  private func finish(transaction: URL) {
    try? fileManager.removeItem(at: transaction)
  }

  private func recoverUninstallTransactions() throws {
    let entries = try fileManager.contentsOfDirectory(
      at: stagingURL, includingPropertiesForKeys: [.isDirectoryKey])
    let registry = try readRegistry()
    for transaction in entries where transaction.lastPathComponent.hasPrefix("uninstall-") {
      let journalURL = transaction.appendingPathComponent("transaction.json")
      guard fileManager.fileExists(atPath: journalURL.path) else {
        finish(transaction: transaction)
        continue
      }
      let journal = try JSONDecoder().decode(
        UninstallTransaction.self, from: Data(contentsOf: journalURL))
      guard journal.formatVersion == 1 else {
        throw PetPackError("uninstall_recovery_failed", "unsupported uninstall recovery record")
      }
      let stillInstalled = journal.records.filter { record in
        registry.packages.contains { Self.sameInstalledPet($0, record) }
      }
      if stillInstalled.count == journal.records.count {
        try rollback(transaction: transaction)
      } else if stillInstalled.isEmpty {
        finish(transaction: transaction)
      } else {
        throw PetPackError("uninstall_recovery_failed", "partial uninstall registry state")
      }
    }
  }

  private func recoverImportTransaction() throws {
    guard fileManager.fileExists(atPath: pendingImportURL.path) else { return }
    let transaction = try readImportTransaction()
    let registry = try readRegistry()
    let registered = registry.packages.first { $0.packageID == transaction.current.packageID }
    if Self.sameInstalledPet(registered, transaction.current) {
      try rollbackImported(current: transaction.current, previous: transaction.previous)
    } else {
      guard Self.sameInstalledPet(registered, transaction.previous) else {
        throw PetPackError(
          "import_recovery_failed", "the installed-pet registry conflicts with import recovery")
      }
      finish(transaction: try stageManagedFiles(for: [transaction.current]))
    }
    try clearImportTransaction(expectedCurrent: transaction.current)
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

  private static func isValidInstalledPet(_ pet: InstalledPet) -> Bool {
    isValidPackageID(pet.packageID) && pet.packageID == pet.petID
      && isValidDisplayName(pet.displayName)
      && (pet.species == "cat" || pet.species == "dog")
      && pet.archiveBytes > 0
      && UInt64(pet.archiveBytes) <= ZipArchiveLimits().maxArchiveBytes
      && isValidSHA256(pet.archiveSHA256)
  }

  private static func sameInstalledPet(_ left: InstalledPet?, _ right: InstalledPet?) -> Bool {
    switch (left, right) {
    case (nil, nil): return true
    case (.some(let left), .some(let right)):
      return left.packageID == right.packageID && left.petID == right.petID
        && left.displayName == right.displayName && left.species == right.species
        && left.contentVersion.stringValue == right.contentVersion.stringValue
        && left.archiveSHA256 == right.archiveSHA256 && left.archiveBytes == right.archiveBytes
    default: return false
    }
  }

  private static func isValidSHA256(_ value: String) -> Bool {
    value.count == 64
      && value.utf8.allSatisfy {
        ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102)
      }
  }
}
