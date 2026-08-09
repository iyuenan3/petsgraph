import CryptoKit
import Foundation

public enum PackageValidationError: Error, CustomStringConvertible, Sendable {
  case invalid(String)
  case missing(String)
  case integrity(String)

  public var description: String {
    switch self {
    case .invalid(let detail):
      "Invalid pet package: \(detail)"
    case .missing(let detail):
      "Missing pet package file: \(detail)"
    case .integrity(let detail):
      "Pet package integrity failure: \(detail)"
    }
  }
}

public struct PetPackageLoader: Sendable {
  public init() {}

  public func load(
    at packageURL: URL,
    verifyIntegrity: Bool = true
  ) throws -> LoadedPetPackage {
    let root = packageURL.standardizedFileURL.resolvingSymlinksInPath()
    let values = try root.resourceValues(forKeys: [
      .isDirectoryKey,
      .isHiddenKey,
      .isSymbolicLinkKey,
    ])
    guard values.isDirectory == true, values.isSymbolicLink != true else {
      throw PackageValidationError.invalid("package root must be a real directory")
    }
    guard values.isHidden != true else {
      throw PackageValidationError.integrity("hidden package root")
    }

    let decoder = JSONDecoder()
    let manifest: PetPackageManifest = try decode(
      PetPackageManifest.self,
      relativePath: "package.json",
      root: root,
      decoder: decoder
    )
    try validateManifest(manifest)

    let graph: GraphDefinition = try decode(
      GraphDefinition.self,
      relativePath: manifest.graph,
      root: root,
      decoder: decoder
    )
    let demo: DemoSequence = try decode(
      DemoSequence.self,
      relativePath: "demo-sequence.json",
      root: root,
      decoder: decoder
    )

    var clips: [String: ClipDefinition] = [:]
    for expectedID in try Self.requiredClipIDs(from: graph) {
      let clip: ClipDefinition = try decode(
        ClipDefinition.self,
        relativePath: "clips/\(expectedID).json",
        root: root,
        decoder: decoder
      )
      guard clip.id == expectedID else {
        throw PackageValidationError.invalid(
          "clip file \(expectedID).json declares mismatched id \(clip.id)"
        )
      }
      try validateClip(clip, root: root)
      clips[clip.id] = clip
    }
    try validateGraph(graph, clips: clips, defaultNode: manifest.art.defaultNode)
    try validateDemo(demo, clips: clips)

    if verifyIntegrity {
      let integrity: IntegrityManifest = try decode(
        IntegrityManifest.self,
        relativePath: manifest.integrity,
        root: root,
        decoder: decoder
      )
      try verify(integrity, root: root, manifest: manifest, clips: clips)
    }

    return LoadedPetPackage(
      rootURL: root,
      manifest: manifest,
      graph: graph,
      clips: clips,
      demoSequence: demo
    )
  }

  static func requiredClipIDs(from graph: GraphDefinition) throws -> [String] {
    let ids = Set(graph.nodes.map(\.loopClip) + graph.edges.map(\.clip))
    guard !ids.isEmpty else {
      throw PackageValidationError.missing("graph clip references")
    }
    for id in ids {
      guard
        !id.isEmpty,
        id.unicodeScalars.allSatisfy({
          CharacterSet.alphanumerics.contains($0) || "._-".unicodeScalars.contains($0)
        })
      else {
        throw PackageValidationError.invalid("unsafe clip id \(id)")
      }
    }
    return ids.sorted()
  }

  private func decode<T: Decodable>(
    _ type: T.Type,
    relativePath: String,
    root: URL,
    decoder: JSONDecoder
  ) throws -> T {
    let url = try validatedRegularFileURL(relativePath: relativePath, root: root)
    return try decoder.decode(T.self, from: Data(contentsOf: url))
  }

  private func validateManifest(_ manifest: PetPackageManifest) throws {
    guard manifest.schemaVersion.hasPrefix("0."), manifest.renderAssets.mode == "frames" else {
      throw PackageValidationError.invalid("unsupported schema or render mode")
    }
    guard
      manifest.art.canvasPx.count == 2,
      manifest.art.canvasPx.allSatisfy({ $0 > 0 }),
      manifest.art.baseHeightPt > 0,
      manifest.art.coordinateOrigin == "top-left"
    else {
      throw PackageValidationError.invalid("invalid art coordinate contract")
    }
  }

  private func validateClip(_ clip: ClipDefinition, root: URL) throws {
    guard !clip.frames.isEmpty else {
      throw PackageValidationError.invalid("clip \(clip.id) has no frames")
    }
    guard clip.rootMotionEndPt.count == 2 else {
      throw PackageValidationError.invalid("clip \(clip.id) has invalid terminal root motion")
    }
    guard
      clip.safeExitFrames.allSatisfy({ clip.frames.indices.contains($0) }),
      clip.type != "loop" || !clip.safeExitFrames.isEmpty
    else {
      throw PackageValidationError.invalid("clip \(clip.id) has invalid safe exit frames")
    }

    var previousX = -Double.infinity
    for (index, frame) in clip.frames.enumerated() {
      guard frame.durationMs > 0, frame.rootMotionPt.count == 2 else {
        throw PackageValidationError.invalid("clip \(clip.id) frame \(index) has invalid timing or root motion")
      }
      guard abs(frame.rootMotionPt[1]) < 0.000_001 else {
        throw PackageValidationError.invalid("clip \(clip.id) moves vertically in phase 0")
      }
      if clip.facing == "right" {
        guard frame.rootMotionPt[0] + 0.000_001 >= previousX else {
          throw PackageValidationError.invalid("clip \(clip.id) has decreasing rightward root motion")
        }
      }
      previousX = frame.rootMotionPt[0]

      let url = try validatedRegularFileURL(relativePath: frame.src, root: root)
      guard url.pathExtension.lowercased() == "png" else {
        throw PackageValidationError.invalid("clip \(clip.id) frame \(index) is not a regular PNG")
      }
    }
    guard clip.rootMotionEndPt[0] + 0.000_001 >= previousX else {
      throw PackageValidationError.invalid("clip \(clip.id) terminal root motion precedes its last frame")
    }
    if clip.entryPose.hasPrefix("rest."), clip.exitPose.hasPrefix("rest.") {
      guard
        clip.frames.allSatisfy({
          abs($0.rootMotionPt[0]) < 0.000_001 && abs($0.rootMotionPt[1]) < 0.000_001
        }),
        clip.rootMotionEndPt.allSatisfy({ abs($0) < 0.000_001 })
      else {
        throw PackageValidationError.invalid("rest clip \(clip.id) must have zero root motion")
      }
    }
  }

  private func validateGraph(
    _ graph: GraphDefinition,
    clips: [String: ClipDefinition],
    defaultNode: String
  ) throws {
    let nodeIDs = Set(graph.nodes.map(\.id))
    guard nodeIDs.count == graph.nodes.count else {
      throw PackageValidationError.invalid("graph contains duplicate node ids")
    }
    guard Set(graph.edges.map(\.id)).count == graph.edges.count else {
      throw PackageValidationError.invalid("graph contains duplicate edge ids")
    }
    guard nodeIDs.contains(defaultNode) else {
      throw PackageValidationError.invalid("default node is absent from graph")
    }
    for node in graph.nodes {
      guard let loop = clips[node.loopClip] else {
        throw PackageValidationError.invalid(
          "node \(node.id) references unknown loop \(node.loopClip); "
            + "loaded clips: \(clips.keys.sorted().joined(separator: ", "))"
        )
      }
      guard
        loop.type == "loop",
        loop.entryPose == node.id,
        loop.exitPose == node.id
      else {
        throw PackageValidationError.invalid("node \(node.id) has an incompatible loop clip")
      }
    }
    for edge in graph.edges {
      guard
        nodeIDs.contains(edge.from),
        nodeIDs.contains(edge.to),
        let clip = clips[edge.clip],
        let targetNode = graph.nodes.first(where: { $0.id == edge.to }),
        let targetLoop = clips[targetNode.loopClip]
      else {
        throw PackageValidationError.invalid("edge \(edge.id) has an unresolved node or clip")
      }
      guard clip.entryPose == edge.from, clip.exitPose == edge.to else {
        throw PackageValidationError.invalid("edge \(edge.id) clip poses do not match its nodes")
      }
      guard ["direct-manipulation-only", "safe-exit-only"].contains(edge.interruptPolicy) else {
        throw PackageValidationError.invalid("edge \(edge.id) has an unsupported interrupt policy")
      }
      if let targetStartFrame = edge.targetStartFrame {
        guard targetLoop.frames.indices.contains(targetStartFrame) else {
          throw PackageValidationError.invalid(
            "edge \(edge.id) has invalid target loop frame \(targetStartFrame)"
          )
        }
      }
    }
    for clip in clips.values {
      for hint in clip.preloadHints where clips[hint] == nil {
        throw PackageValidationError.invalid("clip \(clip.id) has unknown preload hint \(hint)")
      }
    }
  }

  private func validateDemo(
    _ demo: DemoSequence,
    clips: [String: ClipDefinition]
  ) throws {
    guard !demo.segments.isEmpty else {
      throw PackageValidationError.invalid("demo sequence is empty")
    }
    for (index, segment) in demo.segments.enumerated() {
      guard let clip = clips[segment.clip] else {
        throw PackageValidationError.invalid("demo references unknown clip \(segment.clip)")
      }
      guard clip.frames.indices.contains(segment.startFrame), segment.cycles > 0 else {
        throw PackageValidationError.invalid("demo segment \(index) has invalid phase or cycles")
      }
      if let frameCount = segment.frameCount {
        guard frameCount > 0, frameCount <= clip.frames.count, segment.cycles == 1 else {
          throw PackageValidationError.invalid("demo segment \(index) has invalid partial frame count")
        }
      }
      if segment.repeatForever && index != demo.segments.count - 1 {
        throw PackageValidationError.invalid("only the final demo segment may repeat forever")
      }
      if segment.repeatForever && segment.frameCount != nil {
        throw PackageValidationError.invalid("a forever segment must retain the complete rotated cycle")
      }
      if clip.type == "transition" {
        guard
          segment.startFrame == 0,
          segment.cycles == 1,
          segment.frameCount == nil,
          !segment.repeatForever
        else {
          throw PackageValidationError.invalid(
            "transition clip \(clip.id) must play once from frame zero without truncation"
          )
        }
      }
    }

    for index in demo.segments.indices.dropLast() {
      let currentSegment = demo.segments[index]
      let nextSegment = demo.segments[index + 1]
      guard
        let currentClip = clips[currentSegment.clip],
        let nextClip = clips[nextSegment.clip]
      else {
        continue
      }
      guard currentClip.exitPose == nextClip.entryPose else {
        throw PackageValidationError.invalid(
          "demo segment \(index) exits \(currentClip.exitPose) but next enters \(nextClip.entryPose)"
        )
      }
      if currentClip.type == "loop", currentClip.id != nextClip.id {
        let exitFrame = Self.finalSourceFrameIndex(
          segment: currentSegment,
          frameCount: currentClip.frames.count
        )
        guard currentClip.safeExitFrames.contains(exitFrame) else {
          throw PackageValidationError.invalid(
            "demo leaves loop \(currentClip.id) at unsafe frame \(exitFrame)"
          )
        }
      }
    }
  }

  private static func finalSourceFrameIndex(
    segment: DemoSegment,
    frameCount: Int
  ) -> Int {
    if let requestedFrameCount = segment.frameCount {
      return (segment.startFrame + requestedFrameCount - 1) % frameCount
    }
    return (segment.startFrame + frameCount - 1) % frameCount
  }

  private func verify(
    _ integrity: IntegrityManifest,
    root: URL,
    manifest: PetPackageManifest,
    clips: [String: ClipDefinition]
  ) throws {
    guard integrity.algorithm.lowercased() == "sha256" else {
      throw PackageValidationError.integrity("unsupported algorithm")
    }
    var entries: [String: IntegrityEntry] = [:]
    for entry in integrity.files {
      guard entries[entry.path] == nil else {
        throw PackageValidationError.integrity("duplicate entry for \(entry.path)")
      }
      entries[entry.path] = entry
    }
    var requiredPaths: Set<String> = [
      "package.json",
      manifest.graph,
      "demo-sequence.json",
      manifest.reviewIndex,
    ]
    for clip in clips.values {
      requiredPaths.insert("clips/\(clip.id).json")
      requiredPaths.formUnion(clip.frames.map(\.src))
    }
    for path in requiredPaths where entries[path] == nil {
      throw PackageValidationError.integrity("missing entry for \(path)")
    }

    for entry in integrity.files {
      let url = try validatedRegularFileURL(relativePath: entry.path, root: root)
      let data = try Data(contentsOf: url, options: [.mappedIfSafe])
      guard data.count == entry.bytes else {
        throw PackageValidationError.integrity("byte count mismatch for \(entry.path)")
      }
      let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
      guard digest == entry.sha256.lowercased() else {
        throw PackageValidationError.integrity("SHA-256 mismatch for \(entry.path)")
      }
    }
  }

  private func validatedRegularFileURL(relativePath: String, root: URL) throws -> URL {
    let url = try safeURL(relativePath: relativePath, root: root)
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw PackageValidationError.missing(relativePath)
    }
    let values = try url.resourceValues(forKeys: [
      .isHiddenKey,
      .isRegularFileKey,
      .isSymbolicLinkKey,
    ])
    guard values.isHidden != true else {
      throw PackageValidationError.integrity("hidden required file \(relativePath)")
    }
    guard values.isRegularFile == true, values.isSymbolicLink != true else {
      throw PackageValidationError.invalid("required path is not a regular file \(relativePath)")
    }
    return url
  }

  private func safeURL(relativePath: String, root: URL) throws -> URL {
    guard !relativePath.isEmpty, !relativePath.hasPrefix("/") else {
      throw PackageValidationError.invalid("absolute or empty path")
    }
    let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
    guard !components.contains(".."), !components.contains("."), !components.contains("") else {
      throw PackageValidationError.invalid("unsafe relative path \(relativePath)")
    }
    let candidate = root.appendingPathComponent(relativePath).standardizedFileURL
    let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
    guard candidate.path.hasPrefix(prefix) else {
      throw PackageValidationError.invalid("path escapes package root")
    }
    return candidate
  }
}
