import Foundation

public struct PetPackageManifest: Codable, Sendable {
  public let schemaVersion: String
  public let package: PackageIdentity
  public let pet: PetIdentity
  public let art: ArtConfiguration
  public let renderAssets: RenderAssets
  public let graph: String
  public let reviewIndex: String
  public let integrity: String

  public init(
    schemaVersion: String,
    package: PackageIdentity,
    pet: PetIdentity,
    art: ArtConfiguration,
    renderAssets: RenderAssets,
    graph: String,
    reviewIndex: String,
    integrity: String
  ) {
    self.schemaVersion = schemaVersion
    self.package = package
    self.pet = pet
    self.art = art
    self.renderAssets = renderAssets
    self.graph = graph
    self.reviewIndex = reviewIndex
    self.integrity = integrity
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
}

public struct GraphDefinition: Codable, Sendable {
  public let schemaVersion: String
  public let nodes: [GraphNode]
  public let edges: [GraphEdge]
}

public struct GraphNode: Codable, Sendable {
  public let id: String
  public let posture: String
  public let orientation: String
  public let grounded: Bool
  public let stability: String
  public let loopClip: String
}

public struct GraphEdge: Codable, Sendable {
  public let id: String
  public let from: String
  public let to: String
  public let clip: String
  public let kind: String
  public let interruptPolicy: String
  public let targetStartFrame: Int?

  public init(
    id: String,
    from: String,
    to: String,
    clip: String,
    kind: String,
    interruptPolicy: String,
    targetStartFrame: Int? = nil
  ) {
    self.id = id
    self.from = from
    self.to = to
    self.clip = clip
    self.kind = kind
    self.interruptPolicy = interruptPolicy
    self.targetStartFrame = targetStartFrame
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
  public let provenance: ClipProvenance?
}

public struct ClipFrame: Codable, Sendable {
  public let src: String
  public let durationMs: Double
  public let contentBoundsPx: [Double]
  public let anchorsPx: FrameAnchors
  public let collision: FrameCollision
  public let rootMotionPt: [Double]
}

public struct FrameAnchors: Codable, Sendable {
  public let root: [Double]
  public let ground: [Double]
  public let head: [Double]
}

public struct FrameCollision: Codable, Sendable {
  public let bodyCoreEllipsePx: [Double]
  public let screenBoundsPx: [Double]
}

public struct ClipProvenance: Codable, Sendable {
  public let approvalStatus: String
  public let approvedRecipe: String
  public let approvedRecipeSha256: String?
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
  public let clips: [String: ClipDefinition]
  public let demoSequence: DemoSequence

  public init(
    rootURL: URL,
    manifest: PetPackageManifest,
    graph: GraphDefinition,
    clips: [String: ClipDefinition],
    demoSequence: DemoSequence
  ) {
    self.rootURL = rootURL
    self.manifest = manifest
    self.graph = graph
    self.clips = clips
    self.demoSequence = demoSequence
  }

  public func frameURL(clipID: String, frameIndex: Int) -> URL? {
    guard
      let clip = clips[clipID],
      clip.frames.indices.contains(frameIndex)
    else {
      return nil
    }
    return rootURL.appendingPathComponent(clip.frames[frameIndex].src)
  }
}
