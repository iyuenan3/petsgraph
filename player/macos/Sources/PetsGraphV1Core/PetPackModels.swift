import Foundation

public struct PetPackManifest: Codable, Equatable, Sendable {
  public let formatVersion: String
  public let package: PackageIdentity
  public let pet: PetIdentity
  public let stage: StageDefinition
  public let capabilities: CapabilityDeclaration
  public let graph: String
  public let behavior: String
  public let integrity: String
}

public struct PackageIdentity: Codable, Equatable, Sendable {
  public let id: String
  public let contentVersion: SemanticVersion
  public let createdAt: String
}

public struct PetIdentity: Codable, Equatable, Sendable {
  public let id: String
  public let displayName: String
  public let species: String
}

public struct StageDefinition: Codable, Equatable, Sendable {
  public let referenceCanvasPx: [Int]
  public let anchor: String
  public let baseDisplayHeight: Double
  public let defaultNode: String
}

public struct CapabilityDeclaration: Codable, Equatable, Sendable {
  public let required: [String]
  public let optional: [String]
}

public struct PetGraph: Codable, Equatable, Sendable {
  public let formatVersion: String
  public let nodes: [PetGraphNode]
  public let edges: [PetGraphEdge]
}

public struct PetGraphNode: Codable, Equatable, Sendable {
  public let id: String
  public let role: String
  public let scene: String
  public let loopClip: String?
  public let autonomousEligible: Bool
}

public struct PetGraphEdge: Codable, Equatable, Sendable {
  public let id: String
  public let from: String
  public let to: String
  public let clip: String
  public let interruptPolicy: String
}

public struct PetBehavior: Codable, Equatable, Sendable {
  public let formatVersion: String
  public let profile: String
  public let defaultNode: String
  public let timing: BehaviorTiming
  public let nodeWeights: [String: Double]
  public let sceneWeights: [String: Double]
}

public struct BehaviorTiming: Codable, Equatable, Sendable {
  public let strategy: String
  public let dwellRangesSeconds: [String: [Double]]
  public let avoidImmediateRepeat: Bool
}

public struct PetClip: Codable, Equatable, Sendable {
  public let formatVersion: String
  public let id: String
  public let type: String
  public let entryNode: String
  public let exitNode: String
  public let frameRate: FrameRate
  public let frameCount: Int
  public let durationSeconds: Double
  public let safeExitFrames: [Int]
  public let stage: ClipStage
  public let geometry: ClipGeometry
  public let playback: ClipPlayback
  public let production: ClipProduction
  public let representations: [ClipRepresentation]
}

public struct FrameRate: Codable, Equatable, Sendable {
  public let numerator: Int
  public let denominator: Int

  public var framesPerSecond: Double {
    Double(numerator) / Double(denominator)
  }
}

public struct ClipStage: Codable, Equatable, Sendable {
  public let referenceCanvasPx: [Int]
  public let anchor: String
}

public struct ClipGeometry: Codable, Equatable, Sendable {
  public let cropPx: [Int]
  public let presentationOffsetPx: [Int]
}

public struct ClipPlayback: Codable, Equatable, Sendable {
  public let nativeContinuousFrames: Bool
  public let rate: Double
  public let speedProcessing: String
}

public struct ClipProduction: Codable, Equatable, Sendable {
  public let recipeDigest: String
  public let approvalDigest: String
}

public struct ClipRepresentation: Codable, Equatable, Sendable {
  public let id: String
  public let kind: String
  public let path: String
  public let encoding: String
  public let widthPx: Int
  public let heightPx: Int
  public let bytesPerRow: Int
  public let frameCount: Int
  public let frameRate: FrameRate
  public let alpha: String
  public let colorSpace: String
  public let bytes: Int64
  public let sha256: String
}

public struct PetPackIntegrity: Codable, Equatable, Sendable {
  public let formatVersion: String
  public let algorithm: String
  public let files: [IntegrityEntry]
}

public struct IntegrityEntry: Codable, Equatable, Sendable {
  public let path: String
  public let bytes: Int64
  public let mediaType: String
  public let sha256: String
}

public struct LoadedPetPack: Sendable {
  public let runtimeRootURL: URL
  public let manifest: PetPackManifest
  public let graph: PetGraph
  public let behavior: PetBehavior
  public let clips: [String: PetClip]
  public let archiveSHA256: String

  public func mediaURL(for clipID: String) -> URL? {
    guard let path = clips[clipID]?.representations.first?.path else { return nil }
    return runtimeRootURL.appendingPathComponent(path, isDirectory: false)
  }
}

public struct PetPackValidationReport: Equatable, Sendable {
  public let packageID: String
  public let petID: String
  public let displayName: String
  public let species: String
  public let contentVersion: SemanticVersion
  public let archiveSHA256: String
  public let archiveBytes: Int64
  public let uncompressedBytes: Int64
  public let entryCount: Int
  public let clipCount: Int
  public let nodeCount: Int
  public let edgeCount: Int
}
