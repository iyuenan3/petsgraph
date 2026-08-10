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
    try validateEnvironmentProps(manifest.renderAssets.environmentProps, root: root)

    let graph: GraphDefinition = try decode(
      GraphDefinition.self,
      relativePath: manifest.graph,
      root: root,
      decoder: decoder
    )
    try validateEnvironmentPropScenes(
      manifest.renderAssets.environmentProps,
      graph: graph
    )
    let behavior: BehaviorDefinition?
    if let behaviorPath = manifest.behavior {
      behavior = try decode(
        BehaviorDefinition.self,
        relativePath: behaviorPath,
        root: root,
        decoder: decoder
      )
    } else {
      behavior = nil
    }
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
      try validateClip(
        clip,
        root: root,
        renderAssets: manifest.renderAssets,
        canvasPx: manifest.art.canvasPx
      )
      clips[clip.id] = clip
    }
    try validateGraph(
      graph,
      clips: clips,
      defaultNode: manifest.art.defaultNode,
      requiresSceneContract: Self.schemaMinor(manifest.schemaVersion) >= 2,
      declaredEnvironmentPropIDs: Set(
        manifest.renderAssets.environmentProps?.map(\.id) ?? []
      )
    )
    try validateBehavior(behavior, manifest: manifest, graph: graph)
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
      behavior: behavior,
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
    let schemaMinor = Self.schemaMinor(manifest.schemaVersion)
    guard schemaMinor >= 1 else {
      throw PackageValidationError.invalid("unsupported schema or render mode")
    }
    switch manifest.renderAssets.mode {
    case "frames":
      guard manifest.renderAssets.pixelFormat == "rgba8-straight" else {
        throw PackageValidationError.invalid("unsupported frame pixel format")
      }
    case "hevc-alpha-clips":
      guard
        schemaMinor >= 3,
        manifest.renderAssets.pixelFormat == "bgra8-premultiplied"
      else {
        throw PackageValidationError.invalid("unsupported HEVC Alpha package contract")
      }
    case "cropped-rgba-clips":
      guard
        schemaMinor >= 4,
        manifest.renderAssets.pixelFormat == "rgba8-premultiplied"
      else {
        throw PackageValidationError.invalid("unsupported cropped RGBA package contract")
      }
    default:
      throw PackageValidationError.invalid("unsupported schema or render mode")
    }
    if Self.schemaMinor(manifest.schemaVersion) >= 2, manifest.behavior == nil {
      throw PackageValidationError.missing("behavior.json for schema 0.2 or newer")
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

  private func validateEnvironmentProps(
    _ props: [EnvironmentProp]?,
    root: URL
  ) throws {
    guard let props else { return }
    let ids = props.map(\.id)
    guard Set(ids).count == ids.count else {
      throw PackageValidationError.invalid("duplicate environment prop ids")
    }
    for prop in props {
      guard
        !prop.id.isEmpty,
        prop.id.unicodeScalars.allSatisfy({
          CharacterSet.alphanumerics.contains($0) || "._-".unicodeScalars.contains($0)
        }),
        prop.offsetFromFloorOriginPt.count == 2,
        prop.offsetFromFloorOriginPt.allSatisfy(\.isFinite),
        ["persistent", "node-scenes", "embedded"].contains(prop.visibility),
        prop.layer == "behind-pet",
        prop.hitTest == "passthrough"
      else {
        throw PackageValidationError.invalid("invalid environment prop contract for \(prop.id)")
      }
      let url = try validatedRegularFileURL(relativePath: prop.src, root: root)
      guard url.pathExtension.lowercased() == "png" else {
        throw PackageValidationError.invalid("environment prop \(prop.id) is not a regular PNG")
      }
    }
  }

  private func validateEnvironmentPropScenes(
    _ props: [EnvironmentProp]?,
    graph: GraphDefinition
  ) throws {
    guard let props else { return }
    let declaredScenes = Set(graph.nodes.compactMap(\.scene))
    for prop in props {
      if prop.visibility == "persistent" {
        guard prop.scenes == nil || prop.scenes?.isEmpty == true else {
          throw PackageValidationError.invalid(
            "persistent environment prop \(prop.id) cannot declare scenes"
          )
        }
        continue
      }
      guard
        let scenes = prop.scenes,
        !scenes.isEmpty,
        Set(scenes).count == scenes.count,
        scenes.allSatisfy({ !$0.isEmpty && declaredScenes.contains($0) })
      else {
        throw PackageValidationError.invalid(
          "scene-scoped environment prop \(prop.id) must reference graph scenes"
        )
      }
    }
  }

  private func validateClip(
    _ clip: ClipDefinition,
    root: URL,
    renderAssets: RenderAssets,
    canvasPx: [Int]
  ) throws {
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
      guard
        frame.durationMs > 0,
        frame.rootMotionPt.count == 2,
        frame.contentBoundsPx.count == 4,
        frame.anchorsPx.root.count == 2,
        frame.anchorsPx.ground.count == 2,
        frame.anchorsPx.head.count == 2,
        frame.collision.bodyCoreEllipsePx.count == 4,
        frame.collision.screenBoundsPx.count == 4,
        (frame.petBoundsPx?.count ?? 4) == 4,
        (frame.collision.petHitEllipsePx?.count ?? 4) == 4,
        (frame.propBoundsPx?.values.allSatisfy({ $0.count == 4 }) ?? true)
      else {
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

      if renderAssets.mode == "frames" {
        let url = try validatedRegularFileURL(relativePath: frame.src, root: root)
        guard url.pathExtension.lowercased() == "png" else {
          throw PackageValidationError.invalid(
            "clip \(clip.id) frame \(index) is not a regular PNG"
          )
        }
      } else if renderAssets.mode == "hevc-alpha-clips" {
        let sourceReference = try safeURL(relativePath: frame.src, root: root)
        guard sourceReference.pathExtension.lowercased() == "png" else {
          throw PackageValidationError.invalid(
            "clip \(clip.id) frame \(index) has an invalid PNG source reference"
          )
        }
      } else if let media = clip.media {
        guard frame.src == media.src else {
          throw PackageValidationError.invalid(
            "clip \(clip.id) frame \(index) does not reference its cropped RGBA media"
          )
        }
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
    try validateClipMedia(
      clip,
      root: root,
      renderAssets: renderAssets,
      canvasPx: canvasPx
    )
  }

  private func validateClipMedia(
    _ clip: ClipDefinition,
    root: URL,
    renderAssets: RenderAssets,
    canvasPx: [Int]
  ) throws {
    if renderAssets.mode == "frames" {
      guard clip.media == nil else {
        throw PackageValidationError.invalid(
          "frame clip \(clip.id) cannot declare clip media"
        )
      }
      return
    }
    guard let media = clip.media else {
      throw PackageValidationError.missing("runtime media for clip \(clip.id)")
    }
    if renderAssets.mode == "cropped-rgba-clips" {
      try validateCroppedRGBAMedia(
        clip,
        media: media,
        root: root,
        canvasPx: canvasPx
      )
      return
    }
    guard
      media.type == "video",
      media.codec == "hevc-alpha",
      media.container == "quicktime",
      media.frameCount == clip.frames.count,
      abs(media.frameRate - 24) < 0.000_001,
      media.alphaMode == "premultiplied",
      media.colorSpace == "sRGB",
      media.sourceSequenceDigest.count == 64,
      media.compiledFrameSequenceDigest.count == 64,
      media.sourceSequenceDigest == clip.provenance?.sourceSequenceDigest,
      clip.frames.allSatisfy({
        abs($0.durationMs - 1_000.0 / media.frameRate) < 0.001
      })
    else {
      throw PackageValidationError.invalid(
        "clip \(clip.id) has an invalid HEVC Alpha media contract"
      )
    }
    let url = try validatedRegularFileURL(relativePath: media.src, root: root)
    guard url.pathExtension.lowercased() == "mov" else {
      throw PackageValidationError.invalid(
        "clip \(clip.id) HEVC Alpha media is not a QuickTime movie"
      )
    }
  }

  private func validateCroppedRGBAMedia(
    _ clip: ClipDefinition,
    media: ClipMedia,
    root: URL,
    canvasPx: [Int]
  ) throws {
    guard
      let crop = media.cropRectPx,
      crop.count == 4,
      crop.allSatisfy({ $0 >= 0 }),
      crop[2] > 0,
      crop[3] > 0,
      let bytesPerRow = media.bytesPerRow,
      let frameByteCount = media.frameByteCount,
      media.type == "raw-frames",
      media.codec == "raw-rgba8",
      media.container == "contiguous-frame-stream",
      media.frameCount == clip.frames.count,
      abs(media.frameRate - 24) < 0.000_001,
      media.alphaMode == "premultiplied-last",
      media.colorSpace == "sRGB",
      bytesPerRow == crop[2] * 4,
      frameByteCount == bytesPerRow * crop[3],
      media.sourceSequenceDigest.count == 64,
      media.compiledFrameSequenceDigest.count == 64,
      media.sourceSequenceDigest == clip.provenance?.sourceSequenceDigest,
      clip.frames.allSatisfy({
        abs($0.durationMs - 1_000.0 / media.frameRate) < 0.001
      })
    else {
      throw PackageValidationError.invalid(
        "clip \(clip.id) has an invalid cropped RGBA media contract"
      )
    }
    guard
      canvasPx.count == 2,
      crop[0] + crop[2] <= canvasPx[0],
      crop[1] + crop[3] <= canvasPx[1]
    else {
      throw PackageValidationError.invalid(
        "clip \(clip.id) cropped RGBA rectangle exceeds the package canvas"
      )
    }
    let url = try validatedRegularFileURL(relativePath: media.src, root: root)
    guard url.pathExtension.lowercased() == "rgba" else {
      throw PackageValidationError.invalid(
        "clip \(clip.id) cropped RGBA media is not a raw stream"
      )
    }
    let expectedBytes = media.frameCount.multipliedReportingOverflow(by: frameByteCount)
    guard !expectedBytes.overflow else {
      throw PackageValidationError.invalid("clip \(clip.id) cropped RGBA byte count overflows")
    }
    let actualBytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
    guard actualBytes == expectedBytes.partialValue else {
      throw PackageValidationError.invalid(
        "clip \(clip.id) cropped RGBA media byte count does not match its contract"
      )
    }
  }


  private func validateGraph(
    _ graph: GraphDefinition,
    clips: [String: ClipDefinition],
    defaultNode: String,
    requiresSceneContract: Bool,
    declaredEnvironmentPropIDs: Set<String>
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
      if requiresSceneContract {
        guard
          let scene = node.scene,
          ["floor", "pillow"].contains(scene),
          let role = node.role,
          ["dwell", "gateway", "interaction", "cyclic"].contains(role),
          node.autonomousEligible != nil,
          node.props != nil
        else {
          throw PackageValidationError.invalid("node \(node.id) lacks schema 0.2 scene semantics")
        }
        guard Set(node.props ?? []).isSubset(of: declaredEnvironmentPropIDs) else {
          throw PackageValidationError.invalid(
            "node \(node.id) references an undeclared environment prop"
          )
        }
        if ["gateway", "interaction"].contains(role), node.autonomousEligible == true {
          throw PackageValidationError.invalid("node \(node.id) cannot be autonomous")
        }
        if role == "dwell", node.autonomousEligible != true {
          throw PackageValidationError.invalid("dwell node \(node.id) must be autonomous")
        }
        guard Self.hasZeroRootMotion(loop) else {
          throw PackageValidationError.invalid(
            "schema 0.2 node loop \(loop.id) must have zero root motion"
          )
        }
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
      guard [
        "direct-manipulation-only",
        "safe-exit-only",
        "finish-before-retarget",
      ].contains(edge.interruptPolicy) else {
        throw PackageValidationError.invalid("edge \(edge.id) has an unsupported interrupt policy")
      }
      if requiresSceneContract {
        guard
          let sourceNode = graph.nodes.first(where: { $0.id == edge.from }),
          let sourceScene = sourceNode.scene,
          let targetScene = targetNode.scene
        else {
          throw PackageValidationError.invalid("edge \(edge.id) has missing scene metadata")
        }
        if sourceScene == targetScene {
          guard edge.sceneChange == nil, sourceNode.props == targetNode.props else {
            throw PackageValidationError.invalid("edge \(edge.id) changes props inside one scene")
          }
          guard Self.hasZeroRootMotion(clip) else {
            throw PackageValidationError.invalid(
              "same-scene edge \(edge.id) must have zero root motion"
            )
          }
        } else {
          guard edge.sceneChange == "\(sourceScene)-to-\(targetScene)" else {
            throw PackageValidationError.invalid("edge \(edge.id) lacks explicit scene change")
          }
        }
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
    if requiresSceneContract {
      try validateSceneReachability(graph)
    }
  }

  private static func hasZeroRootMotion(_ clip: ClipDefinition) -> Bool {
    clip.rootMotionEndPt.allSatisfy({ abs($0) < 0.000_001 })
      && clip.frames.allSatisfy({ frame in
        frame.rootMotionPt.allSatisfy({ abs($0) < 0.000_001 })
      })
  }

  private func validateBehavior(
    _ behavior: BehaviorDefinition?,
    manifest: PetPackageManifest,
    graph: GraphDefinition
  ) throws {
    let requiresBehavior = Self.schemaMinor(manifest.schemaVersion) >= 2
    guard requiresBehavior else { return }
    guard let behavior else {
      throw PackageValidationError.missing("behavior definition")
    }
    guard
      Self.schemaMinor(behavior.schemaVersion) >= 2,
      behavior.profile == "quiet-sleep-companion",
      behavior.defaultIntent == "sleep",
      behavior.timing.strategy == "random-long-tail",
      behavior.interactions.desktopClick == "ignore",
      behavior.interactions.drag == "direct-manipulation",
      behavior.interactions.petClick.sleeping == "wake-to-scene-sit",
      behavior.interactions.petClick.sitting == "return-to-scene-sleep"
    else {
      throw PackageValidationError.invalid("unsupported quiet companion behavior")
    }
    if let minimum = behavior.timing.minimumDwellSeconds,
      let median = behavior.timing.medianDwellSeconds,
      let maximum = behavior.timing.maximumDwellSeconds
    {
      guard minimum > 0, minimum <= median, median <= maximum else {
        throw PackageValidationError.invalid("invalid long-tail dwell parameters")
      }
    }
    if let limit = behavior.timing.recentHistoryLimit, limit < 1 {
      throw PackageValidationError.invalid("recent history limit must be positive")
    }
    if let probability = behavior.timing.sameSceneProbability,
      !(0...1).contains(probability)
    {
      throw PackageValidationError.invalid("same-scene probability must be between zero and one")
    }
    if let debounce = behavior.interactions.petClick.debounceSeconds,
      !(0.1...2).contains(debounce)
    {
      throw PackageValidationError.invalid("pet click debounce must be between 0.1 and 2 seconds")
    }
    let nodes = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0) })
    for node in graph.nodes
      where node.role == "dwell" && node.autonomousEligible == true
    {
      guard
        let displayName = node.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
        !displayName.isEmpty
      else {
        throw PackageValidationError.invalid(
          "quiet sleep node \(node.id) needs a localized display name"
        )
      }
    }
    for (scene, policy) in behavior.scenePolicy {
      guard ["floor", "pillow"].contains(scene) else {
        throw PackageValidationError.invalid("unknown behavior scene \(scene)")
      }
      if let gateway = policy.gateway {
        guard
          let node = nodes[gateway],
          node.scene == scene,
          node.role == "gateway",
          node.autonomousEligible == false
        else {
          throw PackageValidationError.invalid("invalid gateway \(gateway) for scene \(scene)")
        }
      }
    }
  }

  private func validateSceneReachability(_ graph: GraphDefinition) throws {
    let nodes = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0) })
    let outgoing = Dictionary(grouping: graph.edges, by: \GraphEdge.from)
    for node in graph.nodes where node.role == "dwell" && node.autonomousEligible == true {
      guard let scene = node.scene else { continue }
      let sceneSits = Set(
        graph.nodes.filter { $0.scene == scene && $0.role == "interaction" }.map(\.id)
      )
      guard !sceneSits.isEmpty, Self.canReach(
        from: node.id,
        targetIDs: sceneSits,
        outgoing: outgoing,
        nodes: nodes,
        requiredScene: scene
      ) else {
        throw PackageValidationError.invalid("dwell node \(node.id) cannot reach its scene interaction")
      }
      let dwellTargets = Set(
        graph.nodes.filter {
          $0.scene == scene && $0.role == "dwell" && $0.autonomousEligible == true
        }.map(\.id)
      )
      for sit in sceneSits where !Self.canReach(
        from: sit,
        targetIDs: dwellTargets,
        outgoing: outgoing,
        nodes: nodes,
        requiredScene: scene
      ) {
        throw PackageValidationError.invalid("interaction node \(sit) cannot return to sleep")
      }
    }
  }

  private static func canReach(
    from start: String,
    targetIDs: Set<String>,
    outgoing: [String: [GraphEdge]],
    nodes: [String: GraphNode],
    requiredScene: String
  ) -> Bool {
    var queue = [start]
    var visited = Set(queue)
    var cursor = 0
    while cursor < queue.count {
      let current = queue[cursor]
      cursor += 1
      if current != start, targetIDs.contains(current) { return true }
      for edge in outgoing[current] ?? [] {
        guard
          !visited.contains(edge.to),
          nodes[edge.to]?.scene == requiredScene
        else { continue }
        visited.insert(edge.to)
        queue.append(edge.to)
      }
    }
    return targetIDs.contains(start)
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
    if let behavior = manifest.behavior {
      requiredPaths.insert(behavior)
    }
    for prop in manifest.renderAssets.environmentProps ?? [] {
      requiredPaths.insert(prop.src)
    }
    for clip in clips.values {
      requiredPaths.insert("clips/\(clip.id).json")
      if manifest.renderAssets.mode == "frames" {
        requiredPaths.formUnion(clip.frames.map(\.src))
      } else if let media = clip.media {
        requiredPaths.insert(media.src)
      }
    }
    for path in requiredPaths where entries[path] == nil {
      throw PackageValidationError.integrity("missing entry for \(path)")
    }
    if manifest.renderAssets.mode == "cropped-rgba-clips" {
      for clip in clips.values {
        guard let media = clip.media else { continue }
        guard
          let entry = entries[media.src],
          entry.sha256.lowercased() == media.compiledFrameSequenceDigest.lowercased()
        else {
          throw PackageValidationError.integrity(
            "compiled media digest mismatch for \(clip.id)"
          )
        }
      }
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

  private static func schemaMinor(_ version: String) -> Int {
    let components = version.split(separator: ".", omittingEmptySubsequences: false)
    guard
      components.count == 3,
      components[0] == "0",
      let minor = Int(components[1]),
      Int(components[2]) != nil
    else {
      return -1
    }
    return minor
  }
}
