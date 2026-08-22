import CryptoKit
import Foundation

public struct ValidatedPetPack: Sendable {
  public let package: LoadedPetPack
  public let report: PetPackValidationReport
}

public struct PetPackValidator: Sendable {
  public static let formatVersion = "1.0.0"
  public static let baselineCapability = "cropped-rgba-clips"

  public init() {}

  public func validateAndExtract(
    sourceURL: URL,
    to emptyDestination: URL
  ) throws -> ValidatedPetPack {
    let archive = try SafeZipArchive(url: sourceURL)
    try validateRuntimePaths(archive.entries)
    let extracted = try archive.extract(to: emptyDestination)
    return try loadExtracted(root: emptyDestination, extracted: extracted)
  }

  func loadTrustedRuntime(
    root: URL,
    archiveSHA256: String,
    archiveBytes: UInt64
  ) throws -> ValidatedPetPack {
    let fileManager = FileManager.default
    guard
      let enumerator = fileManager.enumerator(
        at: root,
        includingPropertiesForKeys: [
          .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey,
        ],
        options: []
      )
    else { try fail("cache_missing", "runtime cache is unavailable") }
    var entries: [ZipEntry] = []
    var digests: [String: String] = [:]
    var total: UInt64 = 0
    for case let url as URL in enumerator {
      let values = try url.resourceValues(forKeys: [
        .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey,
      ])
      guard values.isSymbolicLink != true else {
        try fail("cache_corrupt", "runtime cache contains a symbolic link")
      }
      let relative = String(url.path.dropFirst(root.path.count + 1))
      if values.isDirectory == true { continue }
      guard values.isRegularFile == true, let size = values.fileSize, size >= 0 else {
        try fail("cache_corrupt", "runtime cache contains an unsupported file")
      }
      let count = UInt64(size)
      total += count
      entries.append(
        ZipEntry(
          path: relative,
          flags: 0,
          compressionMethod: 0,
          crc32: 0,
          compressedSize: count,
          uncompressedSize: count,
          localHeaderOffset: 0,
          externalAttributes: 0,
          isDirectory: false,
          dataOffset: 0
        ))
      if relative.hasSuffix(".json"), relative != "integrity.json" {
        let data = try Data(contentsOf: url)
        digests[relative] = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
      }
    }
    try validateRuntimePaths(entries)
    let integrityData = try Data(contentsOf: root.appendingPathComponent("integrity.json"))
    let integrity = try StrictJSON.decode(
      PetPackIntegrity.self,
      from: integrityData,
      path: "integrity.json"
    )
    for item in integrity.files where !item.path.hasSuffix(".json") {
      digests[item.path] = item.sha256
    }
    return try loadExtracted(
      root: root,
      extracted: ExtractedZip(
        entries: entries,
        digests: digests,
        archiveSHA256: archiveSHA256,
        archiveBytes: archiveBytes,
        uncompressedBytes: total
      )
    )
  }

  private func loadExtracted(root: URL, extracted: ExtractedZip) throws -> ValidatedPetPack {
    let regularEntries = extracted.entries.filter { !$0.isDirectory }
    let jsonEntries = regularEntries.filter { $0.path.hasSuffix(".json") }
    var jsonData: [String: Data] = [:]
    for entry in jsonEntries {
      guard entry.uncompressedSize <= 16 * 1024 * 1024 else {
        try fail("json_budget", "JSON file exceeds the byte budget")
      }
      let data = try Data(contentsOf: root.appendingPathComponent(entry.path))
      _ = try StrictJSON.object(from: data, path: entry.path)
      jsonData[entry.path] = data
    }

    guard
      let manifestData = jsonData["manifest.json"],
      let graphData = jsonData["graph.json"],
      let behaviorData = jsonData["behavior.json"],
      let integrityData = jsonData["integrity.json"]
    else { try fail("missing_required_file", "PetPack root metadata is incomplete") }

    let manifest = try StrictJSON.decode(
      PetPackManifest.self, from: manifestData, path: "manifest.json")
    let graph = try StrictJSON.decode(PetGraph.self, from: graphData, path: "graph.json")
    let behavior = try StrictJSON.decode(
      PetBehavior.self, from: behaviorData, path: "behavior.json")
    let integrity = try StrictJSON.decode(
      PetPackIntegrity.self, from: integrityData, path: "integrity.json")

    try validateManifest(
      manifest, object: try StrictJSON.object(from: manifestData, path: "manifest.json"))
    try validateIntegrity(
      integrity,
      object: try StrictJSON.object(from: integrityData, path: "integrity.json"),
      entries: regularEntries,
      digests: extracted.digests
    )

    var clips: [String: PetClip] = [:]
    var declaredMedia = Set<String>()
    let clipPaths = jsonData.keys.filter { $0.hasPrefix("clips/") }.sorted()
    guard !clipPaths.isEmpty else { try fail("missing_clip", "package has no clip metadata") }
    for path in clipPaths {
      let data = jsonData[path]!
      let clip = try StrictJSON.decode(PetClip.self, from: data, path: path)
      try validateClip(
        clip,
        path: path,
        object: try StrictJSON.object(from: data, path: path),
        manifest: manifest,
        entries: regularEntries,
        integrity: integrity
      )
      guard clips.updateValue(clip, forKey: clip.id) == nil else {
        try fail("duplicate_identifier", "duplicate clip id")
      }
      declaredMedia.insert(clip.representations[0].path)
    }
    let archiveMedia = Set(regularEntries.map(\.path).filter { $0.hasPrefix("media/") })
    guard declaredMedia == archiveMedia else {
      try fail("media_coverage", "clip representations do not exactly cover media entries")
    }

    try validateGraph(
      graph,
      object: try StrictJSON.object(from: graphData, path: "graph.json"),
      clips: clips,
      defaultNode: manifest.stage.defaultNode
    )
    try validateBehavior(
      behavior,
      object: try StrictJSON.object(from: behaviorData, path: "behavior.json"),
      graph: graph,
      defaultNode: manifest.stage.defaultNode
    )

    let package = LoadedPetPack(
      runtimeRootURL: root,
      manifest: manifest,
      graph: graph,
      behavior: behavior,
      clips: clips,
      archiveSHA256: extracted.archiveSHA256
    )
    let report = PetPackValidationReport(
      packageID: manifest.package.id,
      petID: manifest.pet.id,
      displayName: manifest.pet.displayName,
      species: manifest.pet.species,
      contentVersion: manifest.package.contentVersion,
      archiveSHA256: extracted.archiveSHA256,
      archiveBytes: Int64(extracted.archiveBytes),
      uncompressedBytes: Int64(extracted.uncompressedBytes),
      entryCount: regularEntries.count,
      clipCount: clips.count,
      nodeCount: graph.nodes.count,
      edgeCount: graph.edges.count
    )
    return ValidatedPetPack(package: package, report: report)
  }

  private func validateRuntimePaths(_ entries: [ZipEntry]) throws {
    let files = Set(entries.filter { !$0.isDirectory }.map(\.path))
    let required = Set(["manifest.json", "graph.json", "behavior.json", "integrity.json"])
    guard required.isSubset(of: files) else {
      try fail("missing_required_file", "required PetPack root metadata is missing")
    }
    for path in files {
      let components = path.split(separator: "/").map(String.init)
      if components.count == 1 {
        guard required.contains(path) else {
          try fail("unexpected_runtime_file", "unexpected root runtime file")
        }
      } else if components.first == "clips" {
        guard components.count == 2, path.hasSuffix(".json") else {
          try fail("unexpected_runtime_file", "invalid clip metadata path")
        }
      } else if components.first == "media" {
        guard components.count == 3, path.hasSuffix(".rgba") else {
          try fail("unexpected_runtime_file", "invalid media path")
        }
      } else {
        try fail("unexpected_runtime_file", "unexpected runtime path")
      }
    }
  }

  private func validateManifest(_ manifest: PetPackManifest, object: [String: Any]) throws {
    try requireKeys(
      object,
      required: [
        "formatVersion", "package", "pet", "stage", "capabilities", "graph", "behavior",
        "integrity",
      ],
      where: "manifest.json"
    )
    guard manifest.formatVersion == Self.formatVersion else {
      try fail("unsupported_format", "manifest formatVersion is unsupported")
    }
    try validateIdentifier(manifest.package.id, kind: .package, where: "manifest.package.id")
    try validateIdentifier(manifest.pet.id, kind: .package, where: "manifest.pet.id")
    guard manifest.package.id == manifest.pet.id else {
      try fail("identity_mismatch", "package and pet ids must match")
    }
    try validateText(manifest.pet.displayName, maximum: 80, where: "manifest.pet.displayName")
    guard manifest.pet.species == "cat" || manifest.pet.species == "dog" else {
      try fail("invalid_value", "manifest.pet.species is unsupported")
    }
    let formatter = ISO8601DateFormatter()
    let timezoneMarker = manifest.package.createdAt.dropLast(5).last
    guard manifest.package.createdAt.contains("T"),
      timezoneMarker == "+" || timezoneMarker == "-" || manifest.package.createdAt.hasSuffix("Z"),
      formatter.date(from: manifest.package.createdAt) != nil
    else { try fail("invalid_value", "manifest.package.createdAt must include a timezone") }
    guard
      manifest.stage.referenceCanvasPx.count == 2,
      manifest.stage.referenceCanvasPx.allSatisfy({ (1...16_384).contains($0) }),
      manifest.stage.anchor == "bottom-center",
      manifest.stage.baseDisplayHeight > 0,
      manifest.stage.baseDisplayHeight <= 4_096,
      manifest.stage.baseDisplayHeight.isFinite
    else { try fail("invalid_stage", "manifest stage is invalid") }
    try validateIdentifier(
      manifest.stage.defaultNode, kind: .node, where: "manifest.stage.defaultNode")
    let required = Set(manifest.capabilities.required)
    let optional = Set(manifest.capabilities.optional)
    guard
      required.count == manifest.capabilities.required.count,
      optional.count == manifest.capabilities.optional.count,
      required.contains(Self.baselineCapability),
      required.isSubset(of: [Self.baselineCapability]),
      required.isDisjoint(with: optional)
    else { try fail("unsupported_capability", "manifest capabilities are unsupported") }
    guard
      manifest.graph == "graph.json",
      manifest.behavior == "behavior.json",
      manifest.integrity == "integrity.json"
    else { try fail("noncanonical_path", "manifest runtime paths are not canonical") }

    try validateNestedKeys(
      object,
      path: "package",
      required: ["id", "contentVersion", "createdAt"],
      where: "manifest.package"
    )
    try validateNestedKeys(
      object,
      path: "pet",
      required: ["id", "displayName", "species"],
      where: "manifest.pet"
    )
    try validateNestedKeys(
      object,
      path: "stage",
      required: ["referenceCanvasPx", "anchor", "baseDisplayHeight", "defaultNode"],
      where: "manifest.stage"
    )
    try validateNestedKeys(
      object,
      path: "capabilities",
      required: ["required", "optional"],
      where: "manifest.capabilities"
    )
  }

  private func validateIntegrity(
    _ integrity: PetPackIntegrity,
    object: [String: Any],
    entries: [ZipEntry],
    digests: [String: String]
  ) throws {
    try requireKeys(
      object, required: ["formatVersion", "algorithm", "files"], where: "integrity.json")
    guard integrity.formatVersion == Self.formatVersion, integrity.algorithm == "sha256" else {
      try fail("unsupported_format", "integrity format or algorithm is unsupported")
    }
    let actual = Set(entries.map(\.path).filter { $0 != "integrity.json" })
    var declared = Set<String>()
    for item in integrity.files {
      guard item.path != "integrity.json", declared.insert(item.path).inserted else {
        try fail("integrity_coverage", "integrity paths must be unique and exclude itself")
      }
      try validateSHA256(item.sha256, where: "integrity sha256")
      let expectedType =
        item.path.hasSuffix(".json")
        ? "application/json"
        : "application/vnd.petsgraph.rgba8"
      guard
        item.mediaType == expectedType,
        item.bytes >= 0,
        entries.first(where: { $0.path == item.path })?.uncompressedSize == UInt64(item.bytes),
        digests[item.path] == item.sha256
      else { try fail("integrity_sha256", "runtime file integrity differs") }
    }
    guard declared == actual else {
      try fail("integrity_coverage", "integrity does not exactly cover runtime files")
    }
    guard let files = object["files"] as? [[String: Any]] else {
      try fail("invalid_json_shape", "integrity.files must be an array")
    }
    for (index, item) in files.enumerated() {
      try requireKeys(
        item,
        required: ["path", "bytes", "mediaType", "sha256"],
        where: "integrity.files[\(index)]"
      )
    }
  }

  private func validateClip(
    _ clip: PetClip,
    path: String,
    object: [String: Any],
    manifest: PetPackManifest,
    entries: [ZipEntry],
    integrity: PetPackIntegrity
  ) throws {
    try requireKeys(
      object,
      required: [
        "formatVersion", "id", "type", "entryNode", "exitNode", "frameRate", "frameCount",
        "durationSeconds", "safeExitFrames", "stage", "geometry", "playback", "production",
        "representations",
      ],
      where: path
    )
    guard clip.formatVersion == Self.formatVersion else {
      try fail("unsupported_format", "clip formatVersion is unsupported")
    }
    try validateIdentifier(clip.id, kind: .clip, where: "clip.id")
    guard path == "clips/\(clip.id).json" else {
      try fail("identity_mismatch", "clip id does not match its path")
    }
    try validateIdentifier(clip.entryNode, kind: .node, where: "clip.entryNode")
    try validateIdentifier(clip.exitNode, kind: .node, where: "clip.exitNode")
    guard
      (clip.type == "loop" && clip.entryNode == clip.exitNode)
        || (clip.type == "transition" && clip.entryNode != clip.exitNode)
    else { try fail("invalid_clip", "clip type and endpoints are inconsistent") }
    guard
      (1...1000).contains(clip.frameRate.numerator),
      (1...1000).contains(clip.frameRate.denominator),
      clip.frameCount > 0,
      clip.durationSeconds.isFinite,
      abs(
        clip.durationSeconds - Double(clip.frameCount) * Double(clip.frameRate.denominator)
          / Double(clip.frameRate.numerator)) <= 0.000_001
    else { try fail("invalid_duration", "clip duration does not match its frame contract") }
    guard clip.safeExitFrames == Array(Set(clip.safeExitFrames)).sorted(),
      clip.safeExitFrames.allSatisfy({ (0..<clip.frameCount).contains($0) }),
      clip.type == "loop" ? !clip.safeExitFrames.isEmpty : clip.safeExitFrames.isEmpty
    else { try fail("invalid_safe_exit", "clip safe exits are invalid") }
    guard
      clip.stage.referenceCanvasPx == manifest.stage.referenceCanvasPx,
      clip.stage.anchor == "bottom-center",
      clip.geometry.cropPx.count == 4,
      clip.geometry.presentationOffsetPx.count == 2
    else { try fail("stage_mismatch", "clip stage differs from manifest") }
    let crop = clip.geometry.cropPx
    guard
      crop.allSatisfy({ $0 >= 0 }),
      crop[2] > 0,
      crop[3] > 0,
      crop[0] + crop[2] <= manifest.stage.referenceCanvasPx[0],
      crop[1] + crop[3] <= manifest.stage.referenceCanvasPx[1],
      clip.geometry.presentationOffsetPx == Array(crop.prefix(2))
    else { try fail("invalid_geometry", "clip crop is invalid") }
    guard
      clip.playback.nativeContinuousFrames,
      clip.playback.rate == 1,
      clip.playback.speedProcessing == "none"
    else { try fail("invalid_playback", "clip must use native continuous frames at 1.0x") }
    try validateSHA256(clip.production.recipeDigest, where: "clip production recipe")
    try validateSHA256(clip.production.approvalDigest, where: "clip production approval")
    guard clip.representations.count == 1 else {
      try fail("invalid_representation", "clip must have one baseline representation")
    }
    let representation = clip.representations[0]
    let expectedPath = "media/\(clip.id)/\(Self.baselineCapability).rgba"
    guard
      representation.id == Self.baselineCapability,
      representation.kind == Self.baselineCapability,
      representation.path == expectedPath,
      representation.encoding == "raw-premultiplied-rgba8",
      representation.widthPx == crop[2],
      representation.heightPx == crop[3],
      representation.bytesPerRow == crop[2] * 4,
      representation.frameCount == clip.frameCount,
      representation.frameRate == clip.frameRate,
      representation.alpha == "premultiplied",
      representation.colorSpace == "srgb"
    else { try fail("invalid_representation", "clip baseline representation is invalid") }
    let (frameBytes, overflow1) = representation.bytesPerRow.multipliedReportingOverflow(
      by: representation.heightPx)
    let (expectedBytes, overflow2) = frameBytes.multipliedReportingOverflow(by: clip.frameCount)
    guard
      !overflow1, !overflow2,
      representation.bytes == Int64(expectedBytes),
      entries.first(where: { $0.path == representation.path })?.uncompressedSize
        == UInt64(expectedBytes),
      integrity.files.first(where: { $0.path == representation.path })?.sha256
        == representation.sha256
    else { try fail("invalid_media_length", "clip media length is inconsistent") }
    try validateSHA256(representation.sha256, where: "clip representation sha256")

    try validateNestedKeys(
      object, path: "frameRate", required: ["numerator", "denominator"], where: "clip.frameRate")
    try validateNestedKeys(
      object, path: "stage", required: ["referenceCanvasPx", "anchor"], where: "clip.stage")
    try validateNestedKeys(
      object, path: "geometry", required: ["cropPx", "presentationOffsetPx"], where: "clip.geometry"
    )
    try validateNestedKeys(
      object, path: "playback", required: ["nativeContinuousFrames", "rate", "speedProcessing"],
      where: "clip.playback")
    try validateNestedKeys(
      object, path: "production", required: ["recipeDigest", "approvalDigest"],
      where: "clip.production")
    guard let representations = object["representations"] as? [[String: Any]],
      representations.count == 1
    else {
      try fail("invalid_json_shape", "clip representations are invalid")
    }
    try requireKeys(
      representations[0],
      required: [
        "id", "kind", "path", "encoding", "widthPx", "heightPx", "bytesPerRow", "frameCount",
        "frameRate", "alpha", "colorSpace", "bytes", "sha256",
      ],
      where: "clip.representations[0]"
    )
    try validateNestedKeys(
      representations[0],
      path: "frameRate",
      required: ["numerator", "denominator"],
      where: "clip.representations[0].frameRate"
    )
  }

  private func validateGraph(
    _ graph: PetGraph,
    object: [String: Any],
    clips: [String: PetClip],
    defaultNode: String
  ) throws {
    try requireKeys(object, required: ["formatVersion", "nodes", "edges"], where: "graph.json")
    guard graph.formatVersion == Self.formatVersion, !graph.nodes.isEmpty else {
      try fail("invalid_graph", "graph format or nodes are invalid")
    }
    var nodes: [String: PetGraphNode] = [:]
    var eligible = Set<String>()
    var referencedClips = Set<String>()
    for node in graph.nodes {
      try validateIdentifier(node.id, kind: .node, where: "graph node id")
      guard nodes.updateValue(node, forKey: node.id) == nil else {
        try fail("duplicate_identifier", "duplicate graph node")
      }
      try validateIdentifier(node.scene, kind: .node, where: "graph node scene")
      if node.role == "dwell" {
        guard
          let loopID = node.loopClip,
          let clip = clips[loopID],
          clip.type == "loop",
          clip.entryNode == node.id
        else { try fail("invalid_graph", "dwell node has an invalid loop") }
        referencedClips.insert(loopID)
      } else if node.role == "gateway" {
        guard node.loopClip == nil, !node.autonomousEligible else {
          try fail("invalid_graph", "gateway cannot loop or be autonomous")
        }
      } else {
        try fail("invalid_graph", "graph node role is unsupported")
      }
      if node.autonomousEligible { eligible.insert(node.id) }
    }
    guard nodes[defaultNode]?.role == "dwell", eligible.contains(defaultNode) else {
      try fail("invalid_graph", "default node must be an autonomous dwell")
    }
    var edgeIDs = Set<String>()
    var adjacency = Dictionary(uniqueKeysWithValues: nodes.keys.map { ($0, Set<String>()) })
    for edge in graph.edges {
      try validateIdentifier(edge.id, kind: .clip, where: "graph edge id")
      guard edgeIDs.insert(edge.id).inserted,
        edge.from != edge.to,
        nodes[edge.from] != nil,
        nodes[edge.to] != nil,
        edge.interruptPolicy == "finish-before-retarget",
        let clip = clips[edge.clip],
        clip.type == "transition",
        clip.entryNode == edge.from,
        clip.exitNode == edge.to
      else { try fail("invalid_graph", "graph edge is invalid") }
      referencedClips.insert(edge.clip)
      adjacency[edge.from, default: []].insert(edge.to)
    }
    guard referencedClips == Set(clips.keys) else {
      try fail("clip_coverage", "graph does not exactly reference runtime clips")
    }
    for source in eligible {
      var reached: Set<String> = [source]
      var frontier = [source]
      while let current = frontier.popLast() {
        for target in adjacency[current, default: []] where reached.insert(target).inserted {
          frontier.append(target)
        }
      }
      guard eligible.isSubset(of: reached) else {
        try fail("unreachable_node", "autonomous graph nodes are not mutually reachable")
      }
    }

    guard
      let rawNodes = object["nodes"] as? [[String: Any]],
      let rawEdges = object["edges"] as? [[String: Any]],
      rawNodes.count == graph.nodes.count,
      rawEdges.count == graph.edges.count
    else { try fail("invalid_json_shape", "graph node or edge arrays are invalid") }
    for node in rawNodes {
      let role = node["role"] as? String
      try requireKeys(
        node,
        required: role == "dwell"
          ? ["id", "role", "scene", "loopClip", "autonomousEligible"]
          : ["id", "role", "scene", "autonomousEligible"],
        where: "graph node"
      )
    }
    for edge in rawEdges {
      try requireKeys(
        edge, required: ["id", "from", "to", "clip", "interruptPolicy"], where: "graph edge")
    }
  }

  private func validateBehavior(
    _ behavior: PetBehavior,
    object: [String: Any],
    graph: PetGraph,
    defaultNode: String
  ) throws {
    try requireKeys(
      object,
      required: [
        "formatVersion", "profile", "defaultNode", "timing", "nodeWeights", "sceneWeights",
      ],
      where: "behavior.json"
    )
    guard
      behavior.formatVersion == Self.formatVersion,
      behavior.profile == "passive-memorial-companion",
      behavior.defaultNode == defaultNode,
      behavior.timing.strategy == "independent-random-dwell"
    else { try fail("invalid_behavior", "behavior profile or timing strategy is unsupported") }
    let eligible = Set(graph.nodes.filter(\.autonomousEligible).map(\.id))
    guard Set(behavior.timing.dwellRangesSeconds.keys) == eligible,
      Set(behavior.nodeWeights.keys).isSubset(of: eligible)
    else { try fail("invalid_behavior", "behavior node configuration is inconsistent") }
    for range in behavior.timing.dwellRangesSeconds.values {
      guard range.count == 2,
        range.allSatisfy({ $0.isFinite && $0 > 0 }),
        range[0] <= range[1]
      else { try fail("invalid_behavior", "behavior dwell range is invalid") }
    }
    guard behavior.nodeWeights.values.allSatisfy({ $0.isFinite && $0 > 0 }) else {
      try fail("invalid_behavior", "behavior node weight is invalid")
    }
    let scenes = Set(graph.nodes.map(\.scene))
    guard Set(behavior.sceneWeights.keys).isSubset(of: scenes),
      behavior.sceneWeights.values.allSatisfy({ $0.isFinite && $0 > 0 })
    else { try fail("invalid_behavior", "behavior scene weight is invalid") }
    try validateNestedKeys(
      object,
      path: "timing",
      required: ["strategy", "dwellRangesSeconds", "avoidImmediateRepeat"],
      where: "behavior.timing"
    )
  }
}

private enum IdentifierKind { case package, node, clip }

private func validateIdentifier(_ value: String, kind: IdentifierKind, where location: String)
  throws
{
  let maximum = kind == .package ? 80 : (kind == .node ? 120 : 160)
  try validateText(value, maximum: maximum, where: location)
  let separators: Set<Character> = kind == .node ? [".", "-"] : ["-"]
  var priorWasSeparator = true
  var valid = true
  for character in value {
    if separators.contains(character) {
      if priorWasSeparator { valid = false }
      priorWasSeparator = true
    } else {
      if !character.isASCII || (!character.isLowercase && !character.isNumber) {
        valid = false
      }
      priorWasSeparator = false
    }
  }
  guard
    valid,
    !priorWasSeparator
  else { try fail("invalid_identifier", "\(location) has an invalid identifier") }
}

private func validateText(_ value: String, maximum: Int, where location: String) throws {
  guard
    !value.isEmpty,
    value.count <= maximum,
    value.precomposedStringWithCanonicalMapping == value,
    value.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value != 127 })
  else { try fail("invalid_value", "\(location) is invalid") }
}

private func validateSHA256(_ value: String, where location: String) throws {
  guard value.count == 64,
    value.utf8.allSatisfy({
      ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102)
    })
  else { try fail("invalid_sha256", "\(location) is not a lowercase SHA-256") }
}

private func requireKeys(
  _ object: [String: Any],
  required: Set<String>,
  optional: Set<String> = [],
  where location: String
) throws {
  let keys = Set(object.keys)
  guard required.isSubset(of: keys) else {
    try fail("missing_field", "\(location) is missing a required field")
  }
  guard keys.isSubset(of: required.union(optional)) else {
    try fail("unknown_field", "\(location) contains an unknown field")
  }
}

private func validateNestedKeys(
  _ object: [String: Any],
  path: String,
  required: Set<String>,
  optional: Set<String> = [],
  where location: String
) throws {
  guard let nested = object[path] as? [String: Any] else {
    try fail("invalid_json_shape", "\(location) must be an object")
  }
  try requireKeys(nested, required: required, optional: optional, where: location)
}
