import Foundation

public struct PetPackageManifest: Codable, Sendable {
  public let schemaVersion: String
  public let package: PackageIdentity
  public let pet: PetIdentity
  public let art: ArtConfiguration
  public let renderAssets: RenderAssets
  public let graph: String
  public let behavior: String?
  public let scenes: [SceneDefinition]?
  public let reviewIndex: String
  public let integrity: String

  public init(
    schemaVersion: String,
    package: PackageIdentity,
    pet: PetIdentity,
    art: ArtConfiguration,
    renderAssets: RenderAssets,
    graph: String,
    behavior: String? = nil,
    scenes: [SceneDefinition]? = nil,
    reviewIndex: String,
    integrity: String
  ) {
    self.schemaVersion = schemaVersion
    self.package = package
    self.pet = pet
    self.art = art
    self.renderAssets = renderAssets
    self.graph = graph
    self.behavior = behavior
    self.scenes = scenes
    self.reviewIndex = reviewIndex
    self.integrity = integrity
  }
}

public struct SceneDefinition: Codable, Sendable {
  public let id: String
  public let displayName: String
  public let order: Int

  public init(id: String, displayName: String, order: Int) {
    self.id = id
    self.displayName = displayName
    self.order = order
  }
}

public struct PackageIdentity: Codable, Sendable {
  public let id: String
  public let version: String
  public let createdAt: String
}

public struct PetIdentity: Codable, Sendable {
  public let id: String
  public let displayName: String
  public let species: String
  public let identityStyle: String
}

public struct ArtConfiguration: Codable, Sendable {
  public let canvasPx: [Int]
  public let baseHeightPt: Double
  public let coordinateOrigin: String
  public let defaultNode: String
  public let groundYPx: Double
}

public struct RenderAssets: Codable, Sendable {
  public let mode: String
  public let pixelFormat: String
  public let environmentProps: [EnvironmentProp]?

  public init(
    mode: String,
    pixelFormat: String,
    environmentProps: [EnvironmentProp]? = nil
  ) {
    self.mode = mode
    self.pixelFormat = pixelFormat
    self.environmentProps = environmentProps
  }
}

public struct EnvironmentProp: Codable, Sendable {
  public let id: String
  public let src: String
  public let offsetFromFloorOriginPt: [Double]
  public let visibility: String
  public let scenes: [String]?
  public let layer: String
  public let hitTest: String

  public init(
    id: String,
    src: String,
    offsetFromFloorOriginPt: [Double],
    visibility: String,
    scenes: [String]? = nil,
    layer: String,
    hitTest: String
  ) {
    self.id = id
    self.src = src
    self.offsetFromFloorOriginPt = offsetFromFloorOriginPt
    self.visibility = visibility
    self.scenes = scenes
    self.layer = layer
    self.hitTest = hitTest
  }
}

public struct GraphDefinition: Codable, Sendable {
  public let schemaVersion: String
  public let nodes: [GraphNode]
  public let edges: [GraphEdge]
}

public struct GraphNode: Codable, Sendable {
  public let id: String
  public let displayName: String?
  public let posture: String
  public let orientation: String
  public let grounded: Bool
  public let stability: String
  public let scene: String?
  public let role: String?
  public let autonomousEligible: Bool?
  public let props: [String]?
  public let loopClip: String

  public init(
    id: String,
    displayName: String? = nil,
    posture: String,
    orientation: String,
    grounded: Bool,
    stability: String,
    scene: String? = nil,
    role: String? = nil,
    autonomousEligible: Bool? = nil,
    props: [String]? = nil,
    loopClip: String
  ) {
    self.id = id
    self.displayName = displayName
    self.posture = posture
    self.orientation = orientation
    self.grounded = grounded
    self.stability = stability
    self.scene = scene
    self.role = role
    self.autonomousEligible = autonomousEligible
    self.props = props
    self.loopClip = loopClip
  }
}

public struct GraphEdge: Codable, Sendable {
  public let id: String
  public let from: String
  public let to: String
  public let clip: String
  public let kind: String
  public let interruptPolicy: String
  public let targetStartFrame: Int?
  public let sceneChange: String?

  public init(
    id: String,
    from: String,
    to: String,
    clip: String,
    kind: String,
    interruptPolicy: String,
    targetStartFrame: Int? = nil,
    sceneChange: String? = nil
  ) {
    self.id = id
    self.from = from
    self.to = to
    self.clip = clip
    self.kind = kind
    self.interruptPolicy = interruptPolicy
    self.targetStartFrame = targetStartFrame
    self.sceneChange = sceneChange
  }
}

public enum InterruptionCause: Sendable {
  case autonomousBehavior
  case directManipulation
}

public extension GraphEdge {
  func allowsInterruption(for cause: InterruptionCause) -> Bool {
    switch (interruptPolicy, cause) {
    case ("direct-manipulation-only", .directManipulation):
      true
    case ("safe-exit-only", .autonomousBehavior):
      true
    default:
      false
    }
  }
}

public struct ClipDefinition: Codable, Sendable {
  public let schemaVersion: String
  public let id: String
  public let type: String
  public let facing: String
  public let mirrorSafe: Bool
  public let entryPose: String
  public let exitPose: String
  public let safeExitFrames: [Int]
  public let preloadHints: [String]
  public let rootMotionEndPt: [Double]
  public let frames: [ClipFrame]
  public let media: ClipMedia?
  public let provenance: ClipProvenance?

  public init(
    schemaVersion: String,
    id: String,
    type: String,
    facing: String,
    mirrorSafe: Bool,
    entryPose: String,
    exitPose: String,
    safeExitFrames: [Int],
    preloadHints: [String],
    rootMotionEndPt: [Double],
    frames: [ClipFrame],
    media: ClipMedia? = nil,
    provenance: ClipProvenance?
  ) {
    self.schemaVersion = schemaVersion
    self.id = id
    self.type = type
    self.facing = facing
    self.mirrorSafe = mirrorSafe
    self.entryPose = entryPose
    self.exitPose = exitPose
    self.safeExitFrames = safeExitFrames
    self.preloadHints = preloadHints
    self.rootMotionEndPt = rootMotionEndPt
    self.frames = frames
    self.media = media
    self.provenance = provenance
  }
}

public struct ClipMedia: Codable, Sendable {
  public let type: String
  public let src: String
  public let codec: String
  public let container: String
  public let frameCount: Int
  public let frameRate: Double
  public let alphaMode: String
  public let colorSpace: String
  public let sourceSequenceDigest: String
  public let compiledFrameSequenceDigest: String
  public let cropRectPx: [Int]?
  public let bytesPerRow: Int?
  public let frameByteCount: Int?

  public init(
    type: String,
    src: String,
    codec: String,
    container: String,
    frameCount: Int,
    frameRate: Double,
    alphaMode: String,
    colorSpace: String,
    sourceSequenceDigest: String,
    compiledFrameSequenceDigest: String,
    cropRectPx: [Int]? = nil,
    bytesPerRow: Int? = nil,
    frameByteCount: Int? = nil
  ) {
    self.type = type
    self.src = src
    self.codec = codec
    self.container = container
    self.frameCount = frameCount
    self.frameRate = frameRate
    self.alphaMode = alphaMode
    self.colorSpace = colorSpace
    self.sourceSequenceDigest = sourceSequenceDigest
    self.compiledFrameSequenceDigest = compiledFrameSequenceDigest
    self.cropRectPx = cropRectPx
    self.bytesPerRow = bytesPerRow
    self.frameByteCount = frameByteCount
  }
}

public struct ClipFrame: Codable, Sendable {
  public let src: String
  public let durationMs: Double
  public let contentBoundsPx: [Double]
  public let petBoundsPx: [Double]?
  public let propBoundsPx: [String: [Double]]?
  public let anchorsPx: FrameAnchors
  public let collision: FrameCollision
  public let rootMotionPt: [Double]
  public let presentationOffsetPx: [Double]?

  public init(
    src: String,
    durationMs: Double,
    contentBoundsPx: [Double],
    petBoundsPx: [Double]? = nil,
    propBoundsPx: [String: [Double]]? = nil,
    anchorsPx: FrameAnchors,
    collision: FrameCollision,
    rootMotionPt: [Double],
    presentationOffsetPx: [Double]? = nil
  ) {
    self.src = src
    self.durationMs = durationMs
    self.contentBoundsPx = contentBoundsPx
    self.petBoundsPx = petBoundsPx
    self.propBoundsPx = propBoundsPx
    self.anchorsPx = anchorsPx
    self.collision = collision
    self.rootMotionPt = rootMotionPt
    self.presentationOffsetPx = presentationOffsetPx
  }
}

public struct FrameAnchors: Codable, Sendable {
  public let root: [Double]
  public let ground: [Double]
  public let head: [Double]
}

public struct FrameCollision: Codable, Sendable {
  public let bodyCoreEllipsePx: [Double]
  public let screenBoundsPx: [Double]
  public let petHitEllipsePx: [Double]?

  public init(
    bodyCoreEllipsePx: [Double],
    screenBoundsPx: [Double],
    petHitEllipsePx: [Double]? = nil
  ) {
    self.bodyCoreEllipsePx = bodyCoreEllipsePx
    self.screenBoundsPx = screenBoundsPx
    self.petHitEllipsePx = petHitEllipsePx
  }
}

public struct BehaviorDefinition: Codable, Sendable {
  public let schemaVersion: String
  public let profile: String
  public let defaultIntent: String
  public let timing: BehaviorTiming
  public let scenePolicy: [String: SceneBehaviorPolicy]
  public let interactions: BehaviorInteractions
}

public struct BehaviorTiming: Codable, Sendable {
  public let strategy: String
  public let parametersStatus: String
  public let avoidImmediateRepeat: Bool
  public let minimumDwellSeconds: Double?
  public let medianDwellSeconds: Double?
  public let maximumDwellSeconds: Double?
  public let recentHistoryLimit: Int?
  public let sameSceneProbability: Double?
}

public struct SceneBehaviorPolicy: Codable, Sendable {
  public let sticky: Bool
  public let gateway: String?
  public let minimumDwellSeconds: Double?
  public let exitCooldownSeconds: Double?
}

public struct BehaviorInteractions: Codable, Sendable {
  public let petClick: PetClickBehavior
  public let desktopClick: String
  public let drag: String
}

public struct PetClickBehavior: Codable, Sendable {
  public let sleeping: String
  public let sitting: String
  public let debounceSeconds: Double?

  public init(
    sleeping: String,
    sitting: String,
    debounceSeconds: Double? = nil
  ) {
    self.sleeping = sleeping
    self.sitting = sitting
    self.debounceSeconds = debounceSeconds
  }
}

public struct ClipProvenance: Codable, Sendable {
  public let approvalStatus: String
  public let approvedRecipe: String?
  public let approvedRecipeSha256: String?
  public let candidateRecipe: String?
  public let candidateRecipeSha256: String?
  public let sourceSequenceDigest: String?
  public let rootMotionStatus: String
  public let normalization: String
}

public struct DemoSequence: Codable, Sendable {
  public let schemaVersion: String
  public let id: String
  public let segments: [DemoSegment]
}

public struct DemoSegment: Codable, Sendable {
  public let clip: String
  public let startFrame: Int
  public let cycles: Int
  public let frameCount: Int?
  public let repeatForever: Bool

  public init(
    clip: String,
    startFrame: Int,
    cycles: Int,
    frameCount: Int? = nil,
    repeatForever: Bool = false
  ) {
    self.clip = clip
    self.startFrame = startFrame
    self.cycles = cycles
    self.frameCount = frameCount
    self.repeatForever = repeatForever
  }
}

public struct IntegrityManifest: Codable, Sendable {
  public let schemaVersion: String
  public let algorithm: String
  public let files: [IntegrityEntry]
}

public struct IntegrityEntry: Codable, Sendable {
  public let path: String
  public let bytes: Int
  public let sha256: String
}

public struct LoadedPetPackage: Sendable {
  public let rootURL: URL
  public let manifest: PetPackageManifest
  public let graph: GraphDefinition
  public let behavior: BehaviorDefinition?
  public let clips: [String: ClipDefinition]
  public let demoSequence: DemoSequence

  public init(
    rootURL: URL,
    manifest: PetPackageManifest,
    graph: GraphDefinition,
    behavior: BehaviorDefinition? = nil,
    clips: [String: ClipDefinition],
    demoSequence: DemoSequence
  ) {
    self.rootURL = rootURL
    self.manifest = manifest
    self.graph = graph
    self.behavior = behavior
    self.clips = clips
    self.demoSequence = demoSequence
  }

  public func frameURL(clipID: String, frameIndex: Int) -> URL? {
    guard
      manifest.renderAssets.mode == "frames",
      let clip = clips[clipID],
      clip.frames.indices.contains(frameIndex)
    else {
      return nil
    }
    return rootURL.appendingPathComponent(clip.frames[frameIndex].src)
  }

  public func clipMediaURL(clipID: String) -> URL? {
    guard let src = clips[clipID]?.media?.src else { return nil }
    return rootURL.appendingPathComponent(src)
  }

  public func environmentPropURL(id: String) -> URL? {
    guard let prop = manifest.renderAssets.environmentProps?.first(where: { $0.id == id }) else {
      return nil
    }
    return rootURL.appendingPathComponent(prop.src)
  }
}
