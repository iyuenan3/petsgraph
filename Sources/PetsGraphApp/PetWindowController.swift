import AppKit
import AVFoundation
import CoreImage
import Foundation
import PetsGraphCore
import QuartzCore

final class PetPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }

  override func constrainFrameRect(
    _ frameRect: NSRect,
    to screen: NSScreen?
  ) -> NSRect {
    frameRect
  }
}

struct PetSquareViewport: Equatable {
  let x: Double
  let y: Double
  let side: Double

  static func make(for clip: ClipDefinition, canvasPx: [Int]) -> PetSquareViewport {
    let bounds: CGRect
    if
      let crop = clip.media?.cropRectPx,
      crop.count == 4,
      crop[2] > 0,
      crop[3] > 0
    {
      bounds = CGRect(
        x: crop[0],
        y: crop[1],
        width: crop[2],
        height: crop[3]
      )
    } else {
      let frameBounds = clip.frames.compactMap { frame -> CGRect? in
        guard
          frame.contentBoundsPx.count == 4,
          frame.contentBoundsPx[2] > 0,
          frame.contentBoundsPx[3] > 0
        else { return nil }
        return CGRect(
          x: frame.contentBoundsPx[0],
          y: frame.contentBoundsPx[1],
          width: frame.contentBoundsPx[2],
          height: frame.contentBoundsPx[3]
        )
      }
      bounds = frameBounds.dropFirst().reduce(frameBounds.first ?? CGRect(
        x: 0,
        y: 0,
        width: canvasPx.first ?? 1,
        height: canvasPx.count > 1 ? canvasPx[1] : 1
      )) { $0.union($1) }.insetBy(dx: -4, dy: -4)
    }
    return enclosing(bounds)
  }

  static func enclosing(_ bounds: CGRect) -> PetSquareViewport {
    let side = max(1, max(bounds.width, bounds.height))
    return PetSquareViewport(
      x: bounds.midX - side / 2,
      y: bounds.midY - side / 2,
      side: side
    )
  }

  func panelFrame(
    canvasOrigin: NSPoint,
    canvasHeightPx: Double,
    pixelScale: Double
  ) -> NSRect {
    NSRect(
      x: canvasOrigin.x + x * pixelScale,
      y: canvasOrigin.y + (canvasHeightPx - y - side) * pixelScale,
      width: side * pixelScale,
      height: side * pixelScale
    )
  }
}

struct PetVisibleContentBoundary {
  static func horizontalAdjustment(
    contentBoundsPx: [Double],
    canvasOriginX: Double,
    canvasWidthPx: Double,
    pixelScale: Double,
    screenFrame: NSRect,
    margin: Double,
    mirrored: Bool
  ) -> Double {
    guard
      contentBoundsPx.count == 4,
      contentBoundsPx[2] > 0,
      pixelScale > 0
    else { return 0 }
    let sourceX = contentBoundsPx[0]
    let sourceWidth = contentBoundsPx[2]
    let displayX = mirrored
      ? canvasWidthPx - sourceX - sourceWidth
      : sourceX
    let visibleMinX = canvasOriginX + displayX * pixelScale
    let visibleMaxX = visibleMinX + sourceWidth * pixelScale
    if visibleMinX < screenFrame.minX + margin {
      return screenFrame.minX + margin - visibleMinX
    }
    if visibleMaxX > screenFrame.maxX - margin {
      return screenFrame.maxX - margin - visibleMaxX
    }
    return 0
  }
}

final class PetImageView: NSView {
  var onPetMouseDown: ((NSPoint) -> Void)?
  var onPetMouseDragged: ((NSPoint) -> Void)?
  var onPetMouseUp: ((NSPoint) -> Void)?

  private let frameLayer = CALayer()
  private var cropRectPx = [0, 0, 1, 1]
  private var canvasPx = [1, 1]
  private var viewportPx = PetSquareViewport(x: 0, y: 0, side: 1)
  private var mirrored = false

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    frameLayer.backgroundColor = NSColor.clear.cgColor
    frameLayer.contentsGravity = .resize
    frameLayer.minificationFilter = .linear
    frameLayer.magnificationFilter = .linear
    layer?.addSublayer(frameLayer)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layout() {
    super.layout()
    updateFrameLayerGeometry()
  }

  func setFrameImage(
    _ image: CGImage,
    cropRectPx: [Int],
    canvasPx: [Int],
    viewportPx: PetSquareViewport,
    mirrored: Bool
  ) {
    self.cropRectPx = cropRectPx
    self.canvasPx = canvasPx
    self.viewportPx = viewportPx
    self.mirrored = mirrored
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    frameLayer.contents = image
    updateFrameLayerGeometry(disableTransaction: false)
    CATransaction.commit()
  }

  private func updateFrameLayerGeometry(disableTransaction: Bool = true) {
    guard
      cropRectPx.count == 4,
      canvasPx.count == 2,
      canvasPx[0] > 0,
      canvasPx[1] > 0
    else { return }
    if disableTransaction {
      CATransaction.begin()
      CATransaction.setDisableActions(true)
    }
    let canvasWidth = CGFloat(canvasPx[0])
    let sourceX = CGFloat(cropRectPx[0])
    let sourceY = CGFloat(cropRectPx[1])
    let sourceWidth = CGFloat(cropRectPx[2])
    let sourceHeight = CGFloat(cropRectPx[3])
    let displayX = mirrored ? canvasWidth - sourceX - sourceWidth : sourceX
    let viewportX = mirrored
      ? canvasWidth - CGFloat(viewportPx.x + viewportPx.side)
      : CGFloat(viewportPx.x)
    let viewportY = CGFloat(viewportPx.y)
    let viewportSide = CGFloat(viewportPx.side)
    frameLayer.frame = CGRect(
      x: (displayX - viewportX) / viewportSide * bounds.width,
      y: (viewportY + viewportSide - sourceY - sourceHeight) / viewportSide * bounds.height,
      width: sourceWidth / viewportSide * bounds.width,
      height: sourceHeight / viewportSide * bounds.height
    )
    frameLayer.setAffineTransform(
      mirrored ? CGAffineTransform(scaleX: -1, y: 1) : .identity
    )
    if disableTransaction {
      CATransaction.commit()
    }
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    true
  }

  override func mouseDown(with event: NSEvent) {
    onPetMouseDown?(NSEvent.mouseLocation)
  }

  override func mouseDragged(with event: NSEvent) {
    onPetMouseDragged?(NSEvent.mouseLocation)
  }

  override func mouseUp(with event: NSEvent) {
    onPetMouseUp?(NSEvent.mouseLocation)
  }
}

private enum FrameAlphaSource {
  case bitmap(NSBitmapImageRep)
  case raw(
    data: NSData,
    frameOffset: Int,
    cropRectPx: [Int],
    bytesPerRow: Int
  )

  func alpha(canvasX: Int, canvasY: Int) -> Double {
    switch self {
    case .bitmap(let bitmap):
      guard
        canvasX >= 0,
        canvasY >= 0,
        canvasX < bitmap.pixelsWide,
        canvasY < bitmap.pixelsHigh
      else { return 0 }
      return Double(bitmap.colorAt(x: canvasX, y: canvasY)?.alphaComponent ?? 0)
    case .raw(let data, let frameOffset, let crop, let bytesPerRow):
      guard
        crop.count == 4,
        canvasX >= crop[0],
        canvasY >= crop[1],
        canvasX < crop[0] + crop[2],
        canvasY < crop[1] + crop[3]
      else { return 0 }
      let localX = canvasX - crop[0]
      let localY = canvasY - crop[1]
      let alphaOffset = frameOffset + localY * bytesPerRow + localX * 4 + 3
      guard alphaOffset >= 0, alphaOffset < data.length else { return 0 }
      return Double(data.bytes.load(fromByteOffset: alphaOffset, as: UInt8.self)) / 255.0
    }
  }
}

struct CachedPetFrame {
  let cgImage: CGImage
  let cropRectPx: [Int]
  private let alphaSource: FrameAlphaSource

  fileprivate init(
    cgImage: CGImage,
    cropRectPx: [Int],
    alphaSource: FrameAlphaSource
  ) {
    self.cgImage = cgImage
    self.cropRectPx = cropRectPx
    self.alphaSource = alphaSource
  }

  func alpha(canvasX: Int, canvasY: Int) -> Double {
    alphaSource.alpha(canvasX: canvasX, canvasY: canvasY)
  }
}

private final class RawFrameProviderContext {
  let data: NSData

  init(data: NSData) {
    self.data = data
  }
}

private struct EnvironmentPropPresentation {
  let definition: EnvironmentProp
  let panel: PetPanel
}

struct PetStartupPlacement {
  static func bottomLeft(
    screenFrame: NSRect,
    groundFromWindowBottomPt: Double,
    margin: Double = 0
  ) -> NSPoint {
    NSPoint(
      x: screenFrame.minX + margin,
      y: screenFrame.minY - groundFromWindowBottomPt + margin
    )
  }
}

@MainActor
final class CroppedRGBAClipFrameStore {
  private static let fullLoopBudgetBytes = 36 * 1024 * 1024
  private static let chunkBudgetBytes = 16 * 1024 * 1024
  private static let preloadFrameCount = 8

  private let clip: ClipDefinition
  private let media: ClipMedia
  private let data: NSData
  private let cropRectPx: [Int]
  private let bytesPerRow: Int
  private let frameByteCount: Int
  private let colorSpace: CGColorSpace
  private var cachedFrames: [Int: CachedPetFrame] = [:]
  private var cachedRange: Range<Int>?

  init(package: LoadedPetPackage, clip: ClipDefinition) throws {
    guard
      let media = clip.media,
      let mediaURL = package.clipMediaURL(clipID: clip.id),
      let cropRectPx = media.cropRectPx,
      cropRectPx.count == 4,
      let bytesPerRow = media.bytesPerRow,
      let frameByteCount = media.frameByteCount
    else {
      throw PackageValidationError.missing("cropped RGBA media for \(clip.id)")
    }
    self.clip = clip
    self.media = media
    self.cropRectPx = cropRectPx
    self.bytesPerRow = bytesPerRow
    self.frameByteCount = frameByteCount
    data = try NSData(contentsOf: mediaURL, options: [.mappedIfSafe])
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
      throw PackageValidationError.invalid("sRGB color space is unavailable")
    }
    self.colorSpace = colorSpace
  }

  func preload() throws {
    try cache(range: 0..<min(Self.preloadFrameCount, clip.frames.count))
  }

  func purge() {
    cachedFrames.removeAll(keepingCapacity: false)
    cachedRange = nil
  }

  func frame(at frameIndex: Int) throws -> CachedPetFrame {
    guard clip.frames.indices.contains(frameIndex) else {
      throw PackageValidationError.invalid(
        "cropped RGBA clip \(clip.id) requested invalid frame \(frameIndex)"
      )
    }
    if cachedFrames[frameIndex] == nil {
      if clip.type == "loop", data.length <= Self.fullLoopBudgetBytes {
        try cache(range: clip.frames.indices)
      } else {
        let framesPerChunk = max(1, Self.chunkBudgetBytes / frameByteCount)
        let chunkStart = frameIndex / framesPerChunk * framesPerChunk
        let chunkEnd = min(clip.frames.count, chunkStart + framesPerChunk * 2)
        try cache(range: chunkStart..<chunkEnd)
      }
    }
    guard let frame = cachedFrames[frameIndex] else {
      throw PackageValidationError.missing(
        "cropped RGBA clip \(clip.id) frame \(frameIndex)"
      )
    }
    return frame
  }

  private func cache(range: Range<Int>) throws {
    guard !range.isEmpty else { return }
    if cachedRange == range { return }
    var replacement: [Int: CachedPetFrame] = [:]
    replacement.reserveCapacity(range.count)
    for frameIndex in range {
      replacement[frameIndex] = try makeFrame(at: frameIndex)
    }
    cachedFrames = replacement
    cachedRange = range
  }

  private func makeFrame(at frameIndex: Int) throws -> CachedPetFrame {
    let frameOffset = frameIndex * frameByteCount
    guard frameOffset >= 0, frameOffset + frameByteCount <= data.length else {
      throw PackageValidationError.invalid(
        "cropped RGBA clip \(clip.id) frame \(frameIndex) exceeds its media"
      )
    }
    let context = RawFrameProviderContext(data: data)
    let info = Unmanaged.passRetained(context).toOpaque()
    let pointer = data.bytes.advanced(by: frameOffset)
    guard let provider = CGDataProvider(
      dataInfo: info,
      data: pointer,
      size: frameByteCount,
      releaseData: { info, _, _ in
        guard let info else { return }
        Unmanaged<RawFrameProviderContext>.fromOpaque(info).release()
      }
    ) else {
      Unmanaged<RawFrameProviderContext>.fromOpaque(info).release()
      throw PackageValidationError.invalid(
        "cropped RGBA clip \(clip.id) frame \(frameIndex) has no data provider"
      )
    }
    guard let image = CGImage(
      width: cropRectPx[2],
      height: cropRectPx[3],
      bitsPerComponent: 8,
      bitsPerPixel: 32,
      bytesPerRow: bytesPerRow,
      space: colorSpace,
      bitmapInfo: CGBitmapInfo(
        rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
          | CGBitmapInfo.byteOrder32Big.rawValue
      ),
      provider: provider,
      decode: nil,
      shouldInterpolate: true,
      intent: .defaultIntent
    ) else {
      throw PackageValidationError.invalid(
        "cropped RGBA clip \(clip.id) frame \(frameIndex) could not create CGImage"
      )
    }
    return CachedPetFrame(
      cgImage: image,
      cropRectPx: cropRectPx,
      alphaSource: .raw(
        data: data,
        frameOffset: frameOffset,
        cropRectPx: cropRectPx,
        bytesPerRow: bytesPerRow
      )
    )
  }
}

@MainActor
final class HEVCAlphaClipFrameStore {
  private let clip: ClipDefinition
  private let media: ClipMedia
  private let mediaURL: URL
  private let expectedSize: NSSize
  private let capacity: Int
  private let lookAhead: Int
  private let ciContext: CIContext
  private var cachedFrames: [Int: CachedPetFrame] = [:]
  private var insertionOrder: [Int] = []
  private var reader: AVAssetReader?
  private var output: AVAssetReaderTrackOutput?
  private var nextFrameIndex = 0

  init(
    package: LoadedPetPackage,
    clip: ClipDefinition,
    capacity: Int = 24,
    lookAhead: Int = 8
  ) throws {
    guard
      let media = clip.media,
      let mediaURL = package.clipMediaURL(clipID: clip.id)
    else {
      throw PackageValidationError.missing("HEVC Alpha media for \(clip.id)")
    }
    guard capacity > lookAhead * 2, lookAhead > 0 else {
      throw PackageValidationError.invalid("invalid HEVC Alpha frame queue capacity")
    }
    self.clip = clip
    self.media = media
    self.mediaURL = mediaURL
    expectedSize = NSSize(
      width: package.manifest.art.canvasPx[0],
      height: package.manifest.art.canvasPx[1]
    )
    self.capacity = capacity
    self.lookAhead = lookAhead
    ciContext = CIContext(options: [.cacheIntermediates: false])
  }

  func preload() throws {
    try decodeRange(startFrame: 0, endFrame: min(lookAhead, clip.frames.count - 1))
  }

  func purge() {
    reader?.cancelReading()
    reader = nil
    output = nil
    cachedFrames.removeAll(keepingCapacity: false)
    insertionOrder.removeAll(keepingCapacity: false)
    ciContext.clearCaches()
  }

  func frame(at frameIndex: Int) throws -> CachedPetFrame {
    guard clip.frames.indices.contains(frameIndex) else {
      throw PackageValidationError.invalid(
        "HEVC Alpha clip \(clip.id) requested invalid frame \(frameIndex)"
      )
    }
    if cachedFrames[frameIndex] == nil {
      try decodeRange(
        startFrame: frameIndex,
        endFrame: min(frameIndex + lookAhead, clip.frames.count - 1)
      )
    } else if nextFrameIndex >= frameIndex {
      try decodeForwardIfPossible(
        through: min(frameIndex + lookAhead, clip.frames.count - 1)
      )
    }
    guard let result = cachedFrames[frameIndex] else {
      throw PackageValidationError.missing(
        "HEVC Alpha clip \(clip.id) frame \(frameIndex)"
      )
    }
    if
      clip.type == "loop",
      frameIndex >= clip.frames.count - lookAhead,
      (0...min(lookAhead, clip.frames.count - 1)).contains(where: {
        cachedFrames[$0] == nil
      })
    {
      try decodeRange(startFrame: 0, endFrame: min(lookAhead, clip.frames.count - 1))
    }
    return result
  }

  private func decodeRange(startFrame: Int, endFrame: Int) throws {
    guard startFrame <= endFrame else { return }
    if reader == nil || nextFrameIndex > startFrame || nextFrameIndex < startFrame - lookAhead {
      try startReader(at: startFrame)
    }
    try decodeForwardIfPossible(through: endFrame)
    if cachedFrames[startFrame] == nil {
      try startReader(at: startFrame)
      try decodeForwardIfPossible(through: endFrame)
    }
  }

  private func decodeForwardIfPossible(through targetFrame: Int) throws {
    guard nextFrameIndex <= targetFrame else { return }
    while nextFrameIndex <= targetFrame {
      guard let sample = output?.copyNextSampleBuffer() else {
        let detail = reader?.error?.localizedDescription
          ?? "reader ended at frame \(nextFrameIndex)"
        throw PackageValidationError.invalid(
          "HEVC Alpha clip \(clip.id) decode failed: \(detail)"
        )
      }
      let actualTime = CMTimeGetSeconds(
        CMSampleBufferGetPresentationTimeStamp(sample)
      )
      let expectedTime = Double(nextFrameIndex) / media.frameRate
      guard abs(actualTime - expectedTime) < 0.000_001 else {
        throw PackageValidationError.invalid(
          "HEVC Alpha clip \(clip.id) frame \(nextFrameIndex) is off the declared time grid"
        )
      }
      guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else {
        throw PackageValidationError.invalid(
          "HEVC Alpha clip \(clip.id) frame \(nextFrameIndex) has no pixel buffer"
        )
      }
      let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
      guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
        throw PackageValidationError.invalid(
          "HEVC Alpha clip \(clip.id) frame \(nextFrameIndex) could not render"
        )
      }
      guard
        cgImage.width == Int(expectedSize.width),
        cgImage.height == Int(expectedSize.height)
      else {
        throw PackageValidationError.invalid(
          "HEVC Alpha clip \(clip.id) frame \(nextFrameIndex) has invalid dimensions"
        )
      }
      let bitmap = NSBitmapImageRep(cgImage: cgImage)
      store(
        CachedPetFrame(
          cgImage: cgImage,
          cropRectPx: [0, 0, cgImage.width, cgImage.height],
          alphaSource: .bitmap(bitmap)
        ),
        at: nextFrameIndex
      )
      nextFrameIndex += 1
    }
  }

  private func startReader(at frameIndex: Int) throws {
    reader?.cancelReading()
    let asset = AVURLAsset(url: mediaURL)
    guard let track = asset.tracks(withMediaType: .video).first else {
      throw PackageValidationError.invalid(
        "HEVC Alpha clip \(clip.id) has no video track"
      )
    }
    guard track.hasMediaCharacteristic(.containsAlphaChannel) else {
      throw PackageValidationError.invalid(
        "HEVC Alpha clip \(clip.id) has no alpha channel"
      )
    }
    let naturalSize = track.naturalSize
    guard
      Int(abs(naturalSize.width).rounded()) == Int(expectedSize.width),
      Int(abs(naturalSize.height).rounded()) == Int(expectedSize.height)
    else {
      throw PackageValidationError.invalid(
        "HEVC Alpha clip \(clip.id) dimensions do not match the package canvas"
      )
    }
    let newReader = try AVAssetReader(asset: asset)
    let newOutput = AVAssetReaderTrackOutput(
      track: track,
      outputSettings: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
      ]
    )
    newOutput.alwaysCopiesSampleData = false
    guard newReader.canAdd(newOutput) else {
      throw PackageValidationError.invalid(
        "HEVC Alpha clip \(clip.id) cannot create a BGRA decoder"
      )
    }
    newReader.add(newOutput)
    newReader.timeRange = CMTimeRange(
      start: CMTime(value: CMTimeValue(frameIndex), timescale: CMTimeScale(media.frameRate)),
      duration: .positiveInfinity
    )
    guard newReader.startReading() else {
      throw PackageValidationError.invalid(
        "HEVC Alpha clip \(clip.id) failed to start decoding: "
          + (newReader.error?.localizedDescription ?? "unknown AVAssetReader error")
      )
    }
    reader = newReader
    output = newOutput
    nextFrameIndex = frameIndex
  }

  private func store(_ frame: CachedPetFrame, at frameIndex: Int) {
    if cachedFrames[frameIndex] == nil {
      insertionOrder.append(frameIndex)
    }
    cachedFrames[frameIndex] = frame
    while insertionOrder.count > capacity {
      cachedFrames.removeValue(forKey: insertionOrder.removeFirst())
    }
  }

}

@MainActor
final class ClipImageCache {
  private let package: LoadedPetPackage
  private var frames: [String: [CachedPetFrame]] = [:]
  private var hevcStores: [String: HEVCAlphaClipFrameStore] = [:]
  private var croppedRGBAStores: [String: CroppedRGBAClipFrameStore] = [:]

  init(package: LoadedPetPackage, createMirroredImages _: Bool) {
    self.package = package
  }

  func prepare(clipIDs: [String]) throws {
    let retained = Set(clipIDs)
    frames = frames.filter { retained.contains($0.key) }
    for (clipID, store) in hevcStores where !retained.contains(clipID) {
      store.purge()
    }
    hevcStores = hevcStores.filter { retained.contains($0.key) }
    for (clipID, store) in croppedRGBAStores where !retained.contains(clipID) {
      store.purge()
    }
    croppedRGBAStores = croppedRGBAStores.filter { retained.contains($0.key) }
    for clipID in clipIDs {
      guard let clip = package.clips[clipID] else {
        throw PackageValidationError.invalid("unknown clip \(clipID)")
      }
      if package.manifest.renderAssets.mode == "hevc-alpha-clips" {
        if hevcStores[clipID] == nil {
          let store = try HEVCAlphaClipFrameStore(
            package: package,
            clip: clip
          )
          try store.preload()
          hevcStores[clipID] = store
          print(
            "petsgraph preloaded clip=\(clipID) frames=bounded source=hevc-alpha-clips"
          )
        }
      } else if package.manifest.renderAssets.mode == "cropped-rgba-clips" {
        if croppedRGBAStores[clipID] == nil {
          let store = try CroppedRGBAClipFrameStore(package: package, clip: clip)
          try store.preload()
          croppedRGBAStores[clipID] = store
          print(
            "petsgraph preloaded clip=\(clipID) frames=bounded source=cropped-rgba-clips"
          )
        }
      } else if frames[clipID] == nil {
        let loaded = try loadPNGFrames(clipID: clipID, clip: clip)
        frames[clipID] = loaded
        print(
          "petsgraph preloaded clip=\(clipID) frames=\(loaded.count) source=frames"
        )
      }
    }
  }

  func frame(clipID: String, frameIndex: Int) throws -> CachedPetFrame? {
    if let store = croppedRGBAStores[clipID] {
      return try store.frame(at: frameIndex)
    }
    if let store = hevcStores[clipID] {
      return try store.frame(at: frameIndex)
    }
    guard let clipFrames = frames[clipID], clipFrames.indices.contains(frameIndex) else {
      return nil
    }
    return clipFrames[frameIndex]
  }

  private func loadPNGFrames(
    clipID: String,
    clip: ClipDefinition
  ) throws -> [CachedPetFrame] {
    try clip.frames.indices.map { frameIndex in
        guard
          let url = package.frameURL(clipID: clipID, frameIndex: frameIndex),
          let data = try? Data(contentsOf: url),
          let bitmap = NSBitmapImageRep(data: data),
          let cgImage = bitmap.cgImage
        else {
          throw PackageValidationError.missing("\(clipID) frame \(frameIndex)")
        }
        return CachedPetFrame(
          cgImage: cgImage,
          cropRectPx: [0, 0, cgImage.width, cgImage.height],
          alphaSource: .bitmap(bitmap)
        )
      }
  }
}

@MainActor
final class PetWindowController {
  private static let playbackFrameInterval = 1.0 / 24.0

  var onClipChanged: ((String) -> Void)?
  var onPositionChanged: ((NSPoint) -> Void)?

  private let package: LoadedPetPackage
  private let petDisplayName: String
  private let staticTimeline: PlaybackTimeline
  private let panel: PetPanel
  private let rootView: NSView
  private let imageView: PetImageView
  private let imageCache: ClipImageCache
  private let startDelaySeconds: Double
  private let canvasWidthPx: Double
  private let canvasHeightPx: Double
  private let viewportsByClipID: [String: PetSquareViewport]
  private let maximumViewportSidePx: Double
  private var displayHeightPt: Double
  private var motionScale: Double
  private var startX: Double
  private var windowY: Double
  private var groundFromWindowBottomPt: Double
  private let visibleFrame: NSRect
  private let screenFrame: NSRect
  private let screenMargin = 0.0
  private let engineeringBehaviorPreview: Bool
  private let quietCompanion: Bool
  private let nativeLeftChainDemo: Bool
  private let quietSceneRoundTripDemo: Bool
  private var environmentProps: [EnvironmentPropPresentation] = []
  private var behaviorSession: BasicBehaviorSession?
  private var globalMouseMonitor: Any?

  private var timer: Timer?
  private var playbackStartUptime: TimeInterval = 0
  private var currentSegmentIndex = -1
  private var currentGeneration = -1
  private var lastInteractionState: BehaviorInteractionState?
  private var currentFrame: CachedPetFrame?
  private var activeViewport: PetSquareViewport
  private var currentFrameIsMirrored = false
  private var currentClipID: String?
  private var currentSourceFrameIndex: Int?
  private var calculatedPanelX = 0.0
  private var manualOffsetX = 0.0
  private var manualOffsetY = 0.0
  private var dragStartMouse = NSPoint.zero
  private var dragStartCanvasOrigin = NSPoint.zero
  private var isDraggingPet = false
  private var didDragPet = false
  private var lastPointerHit = false
  private var wasClampedAtHorizontalBoundary = false

  init(
    package: LoadedPetPackage,
    requestedDisplayHeightPt: Double,
    startDelaySeconds: Double,
    initialOrigin: NSPoint? = nil,
    initialX: Double? = nil,
    engineeringBehaviorPreview: Bool = false,
    acceleratedBehavior: Bool = false,
    nativeLeftChainDemo: Bool = false,
    quietSceneRoundTripDemo: Bool = false
  ) throws {
    self.package = package
    petDisplayName = package.manifest.pet.displayName
    staticTimeline = try PlaybackTimeline(
      clips: package.clips,
      sequence: package.demoSequence
    )
    self.engineeringBehaviorPreview = engineeringBehaviorPreview
    quietCompanion = package.behavior?.profile == "quiet-sleep-companion"
    self.nativeLeftChainDemo = nativeLeftChainDemo
    self.quietSceneRoundTripDemo = quietSceneRoundTripDemo
    guard let screen = NSScreen.main ?? NSScreen.screens.first else {
      throw PackageValidationError.invalid("no active macOS screen")
    }

    let visible = screen.visibleFrame
    visibleFrame = visible
    screenFrame = screen.frame
    let baseHeight = package.manifest.art.baseHeightPt
    let canvasWidth = Double(package.manifest.art.canvasPx[0])
    let canvasHeight = Double(package.manifest.art.canvasPx[1])
    canvasWidthPx = canvasWidth
    canvasHeightPx = canvasHeight
    let viewports = Dictionary(
      uniqueKeysWithValues: package.clips.map { clipID, clip in
        (clipID, PetSquareViewport.make(for: clip, canvasPx: package.manifest.art.canvasPx))
      }
    )
    viewportsByClipID = viewports
    maximumViewportSidePx = viewports.values.map(\.side).max() ?? max(canvasWidth, canvasHeight)
    guard
      let defaultNode = package.graph.nodes.first(where: {
        $0.id == package.manifest.art.defaultNode
      }),
      let defaultViewport = viewports[defaultNode.loopClip]
    else {
      throw PackageValidationError.invalid("default node has no square viewport")
    }
    activeViewport = defaultViewport
    let maximumHeight = min(screen.frame.width, screen.frame.height)
      * canvasHeight / maximumViewportSidePx
    displayHeightPt = max(40, min(requestedDisplayHeightPt, maximumHeight))
    motionScale = displayHeightPt / baseHeight
    self.startDelaySeconds = startDelaySeconds

    let travel = engineeringBehaviorPreview
      ? 0
      : staticTimeline.finiteRootMotionXPt * motionScale
    let pixelScale = displayHeightPt / canvasHeight
    let footprint = defaultViewport.side * pixelScale + travel
    groundFromWindowBottomPt = (
      canvasHeight - package.manifest.art.groundYPx
    ) / canvasHeight * displayHeightPt
    if quietCompanion {
      let placement = PetStartupPlacement.bottomLeft(
        screenFrame: screen.frame,
        groundFromWindowBottomPt: groundFromWindowBottomPt,
        margin: screenMargin
      )
      startX = placement.x - defaultViewport.x * pixelScale
      windowY = placement.y
    } else {
      startX = max(visible.minX + screenMargin, visible.midX - footprint / 2)
      windowY = visible.minY + 5 - groundFromWindowBottomPt
    }

    if let initialOrigin {
      startX = initialOrigin.x
      windowY = initialOrigin.y
    } else if let initialX {
      startX = initialX - defaultViewport.x * pixelScale
    }

    var initialCanvasOrigin = NSPoint(x: startX, y: windowY)
    var initialPanelFrame = defaultViewport.panelFrame(
      canvasOrigin: initialCanvasOrigin,
      canvasHeightPx: canvasHeight,
      pixelScale: pixelScale
    )
    if initialPanelFrame.minX < screen.frame.minX {
      initialCanvasOrigin.x += screen.frame.minX - initialPanelFrame.minX
    } else if initialPanelFrame.maxX > screen.frame.maxX {
      initialCanvasOrigin.x -= initialPanelFrame.maxX - screen.frame.maxX
    }
    initialCanvasOrigin.y = max(
      screen.frame.minY - groundFromWindowBottomPt,
      initialCanvasOrigin.y
    )
    initialPanelFrame = defaultViewport.panelFrame(
      canvasOrigin: initialCanvasOrigin,
      canvasHeightPx: canvasHeight,
      pixelScale: pixelScale
    )
    if initialPanelFrame.maxY > screen.frame.maxY {
      initialCanvasOrigin.y -= initialPanelFrame.maxY - screen.frame.maxY
      initialPanelFrame = defaultViewport.panelFrame(
        canvasOrigin: initialCanvasOrigin,
        canvasHeightPx: canvasHeight,
        pixelScale: pixelScale
      )
    }
    startX = initialCanvasOrigin.x
    windowY = initialCanvasOrigin.y

    panel = PetPanel(
      contentRect: initialPanelFrame,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false,
      screen: screen
    )
    let dockLevel = CGWindowLevelForKey(.dockWindow)
    let screenSaverLevel = CGWindowLevelForKey(.screenSaverWindow)
    panel.isFloatingPanel = true
    panel.becomesKeyOnlyIfNeeded = true
    panel.worksWhenModal = true
    panel.level = NSWindow.Level(rawValue: Int(screenSaverLevel) + 1)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.hidesOnDeactivate = false
    panel.ignoresMouseEvents = true
    panel.collectionBehavior = [
      .canJoinAllSpaces,
      .fullScreenAuxiliary,
      .stationary,
      .ignoresCycle,
    ]

    rootView = NSView(frame: panel.contentView?.bounds ?? .zero)
    rootView.autoresizingMask = [.width, .height]
    rootView.wantsLayer = true
    rootView.layer?.backgroundColor = NSColor.clear.cgColor
    panel.contentView = rootView

    imageView = PetImageView(frame: rootView.bounds)
    imageView.autoresizingMask = [.width, .height]
    rootView.addSubview(imageView)
    imageCache = ClipImageCache(
      package: package,
      createMirroredImages: !quietCompanion
    )
    for definition in package.manifest.renderAssets.environmentProps ?? [] {
      guard
        let url = package.environmentPropURL(id: definition.id),
        let image = NSImage(contentsOf: url)
      else {
        throw PackageValidationError.missing("environment prop \(definition.id)")
      }
      if definition.visibility == "embedded" {
        continue
      }
      let propPanel = PetPanel(
        contentRect: initialPanelFrame,
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false,
        screen: screen
      )
      propPanel.isFloatingPanel = true
      propPanel.becomesKeyOnlyIfNeeded = true
      propPanel.worksWhenModal = true
      propPanel.level = panel.level
      propPanel.isOpaque = false
      propPanel.backgroundColor = .clear
      propPanel.hasShadow = false
      propPanel.hidesOnDeactivate = false
      propPanel.ignoresMouseEvents = true
      propPanel.collectionBehavior = panel.collectionBehavior
      let propView = NSImageView(frame: propPanel.contentView?.bounds ?? .zero)
      propView.autoresizingMask = [.width, .height]
      propView.imageScaling = .scaleAxesIndependently
      propView.image = image
      propPanel.contentView = propView
      environmentProps.append(
        EnvironmentPropPresentation(definition: definition, panel: propPanel)
      )
    }
    if engineeringBehaviorPreview || quietCompanion {
      behaviorSession = try BasicBehaviorSession(
        package: package,
        accelerated: acceleratedBehavior
      )
    }
    imageView.onPetMouseDown = { [weak self] point in
      self?.beginPetDrag(at: point)
    }
    imageView.onPetMouseDragged = { [weak self] point in
      self?.continuePetDrag(to: point)
    }
    imageView.onPetMouseUp = { [weak self] point in
      self?.finishPetDrag(at: point)
    }

    if displayHeightPt + 0.001 < requestedDisplayHeightPt {
      print(
        String(
          format: "petsgraph display-height adjusted requested=%.1f actual=%.1f to fit screen",
          requestedDisplayHeightPt,
          displayHeightPt
        )
      )
    }
    print(
      String(
        format: "petsgraph screen=%.0fx%.0f display-height=%.1f travel=%.1f start-x=%.1f",
        visible.width,
        visible.height,
        displayHeightPt,
        travel,
        startX
      )
    )
    print(
      "petsgraph panel-level=\(panel.level.rawValue) "
        + "dock-level=\(dockLevel) screen-saver-level=\(screenSaverLevel)"
    )
    print(
      String(
        format: "petsgraph drag-min-y=%.2f ground-at-screen-bottom=%.2f",
        screenFrame.minY - groundFromWindowBottomPt,
        screenFrame.minY
      )
    )
  }

  func start(scheduleTimer: Bool = true) throws {
    let startUptime = ProcessInfo.processInfo.systemUptime + startDelaySeconds
    playbackStartUptime = startUptime
    if let behaviorSession {
      behaviorSession.start(at: startUptime)
      let presentation = try behaviorSession.update(
        at: startUptime,
        motionScale: motionScale,
        currentPetCenterX: panel.frame.midX
      )
      try renderBehavior(presentation)
    } else {
      try imageCache.prepare(clipIDs: staticTimeline.clipIDsNear(segmentIndex: 0))
      try renderStatic(staticTimeline.sample(at: 0))
    }
    orderPanelsFront()
    if nativeLeftChainDemo {
      try startNativeLeftChainDemo(at: startUptime)
    } else if quietSceneRoundTripDemo {
      try behaviorSession?.startQuietSceneRoundTripDemo(at: startUptime)
    } else if engineeringBehaviorPreview, !quietCompanion {
      installDestinationClickMonitor()
    }
    if scheduleTimer {
      let timer = Timer(
        timeInterval: Self.playbackFrameInterval,
        target: self,
        selector: #selector(tick(_:)),
        userInfo: nil,
        repeats: true
      )
      timer.tolerance = Self.playbackFrameInterval / 20.0
      RunLoop.main.add(timer, forMode: .common)
      self.timer = timer
    }
  }

  var windowFrame: NSRect { panel.frame }

  var persistentOrigin: NSPoint {
    NSPoint(
      x: calculatedPanelX + manualOffsetX,
      y: windowY + manualOffsetY
    )
  }

  private var currentPetCenterScreenX: Double {
    guard
      let currentClipID,
      let currentSourceFrameIndex,
      let clip = package.clips[currentClipID],
      clip.frames.indices.contains(currentSourceFrameIndex)
    else { return panel.frame.midX }
    let anchorX = clip.frames[currentSourceFrameIndex].anchorsPx.ground.first
      ?? canvasWidthPx / 2
    let displayX = currentFrameIsMirrored ? canvasWidthPx - anchorX : anchorX
    return persistentOrigin.x + displayX * displayHeightPt / canvasHeightPx
  }

  func setDisplayHeight(_ requestedHeightPt: Double) {
    let maximumHeight = min(screenFrame.width, screenFrame.height)
      * canvasHeightPx / maximumViewportSidePx
    let newHeight = max(40, min(requestedHeightPt, maximumHeight))
    guard abs(newHeight - displayHeightPt) >= 0.001 else { return }

    let frameDefinition: ClipFrame? = {
      guard
        let currentClipID,
        let currentSourceFrameIndex,
        let clip = package.clips[currentClipID],
        clip.frames.indices.contains(currentSourceFrameIndex)
      else { return nil }
      return clip.frames[currentSourceFrameIndex]
    }()
    let oldPixelScale = displayHeightPt / canvasHeightPx
    let oldCanvasOrigin = persistentOrigin
    let anchorX = frameDefinition?.anchorsPx.ground.first ?? canvasWidthPx / 2
    let anchorY = frameDefinition?.anchorsPx.ground.dropFirst().first
      ?? package.manifest.art.groundYPx
    let anchorScreenX = oldCanvasOrigin.x + anchorX * oldPixelScale
    let anchorScreenY = oldCanvasOrigin.y + (canvasHeightPx - anchorY) * oldPixelScale

    displayHeightPt = newHeight
    motionScale = displayHeightPt / package.manifest.art.baseHeightPt
    groundFromWindowBottomPt = (
      canvasHeightPx - package.manifest.art.groundYPx
    ) / canvasHeightPx * displayHeightPt
    let newPixelScale = displayHeightPt / canvasHeightPx
    var newCanvasOrigin = NSPoint(
      x: anchorScreenX - anchorX * newPixelScale,
      y: anchorScreenY - (canvasHeightPx - anchorY) * newPixelScale
    )
    var newPanelFrame = activeViewport.panelFrame(
      canvasOrigin: newCanvasOrigin,
      canvasHeightPx: canvasHeightPx,
      pixelScale: newPixelScale
    )
    if newPanelFrame.minX < screenFrame.minX {
      newCanvasOrigin.x += screenFrame.minX - newPanelFrame.minX
    } else if newPanelFrame.maxX > screenFrame.maxX {
      newCanvasOrigin.x -= newPanelFrame.maxX - screenFrame.maxX
    }
    newCanvasOrigin.y = max(
      screenFrame.minY - groundFromWindowBottomPt,
      newCanvasOrigin.y
    )
    newPanelFrame = activeViewport.panelFrame(
      canvasOrigin: newCanvasOrigin,
      canvasHeightPx: canvasHeightPx,
      pixelScale: newPixelScale
    )
    if newPanelFrame.maxY > screenFrame.maxY {
      newCanvasOrigin.y -= newPanelFrame.maxY - screenFrame.maxY
      newPanelFrame = activeViewport.panelFrame(
        canvasOrigin: newCanvasOrigin,
        canvasHeightPx: canvasHeightPx,
        pixelScale: newPixelScale
      )
    }
    panel.setFrame(
      newPanelFrame,
      display: true
    )
    startX = newCanvasOrigin.x
    windowY = newCanvasOrigin.y
    calculatedPanelX = newCanvasOrigin.x
    manualOffsetX = 0
    manualOffsetY = 0
    currentFrame = nil
    positionEnvironmentProps()
    orderPanelsFront()
    onPositionChanged?(newCanvasOrigin)
  }

  func restart() {
    currentSegmentIndex = -1
    currentGeneration = -1
    let now = ProcessInfo.processInfo.systemUptime
    if let behaviorSession {
      do {
        try behaviorSession.resetToSleep(at: now)
        try renderBehavior(
          behaviorSession.update(
            at: now,
            motionScale: motionScale,
            currentPetCenterX: currentPetCenterScreenX
          )
        )
      } catch {
        failAndTerminate(error)
        return
      }
    } else {
      playbackStartUptime = now + startDelaySeconds
      do {
        try renderStatic(staticTimeline.sample(at: 0))
      } catch {
        failAndTerminate(error)
        return
      }
    }
    orderPanelsFront()
    print("petsgraph restarted")
  }

  func forceWalk() {
    forceMovement(.walk)
  }

  func forceRun() {
    forceMovement(.run)
  }

  func forceSleepChange() {
    guard let behaviorSession else { return }
    do {
      try behaviorSession.forceSleepChange(at: ProcessInfo.processInfo.systemUptime)
    } catch {
      failAndTerminate(error)
    }
  }

  @discardableResult
  func selectSleepPose(nodeID: String, displayName: String) -> BehaviorCommandResult {
    guard let behaviorSession else { return .unavailable }
    do {
      let result = try behaviorSession.selectSleepPose(
        nodeID: nodeID,
        at: ProcessInfo.processInfo.systemUptime
      )
      switch result {
      case .started:
        showCommandFeedback("准备切换到\(displayName)")
      case .queued:
        showCommandFeedback("将在当前动作结束后切换到\(displayName)")
      case .ignored:
        showCommandFeedback("\(petDisplayName)已经是\(displayName)")
      case .unavailable:
        showCommandFeedback("当前无法切换睡姿")
      }
      return result
    } catch {
      reportBehaviorCommandError(error)
      return .unavailable
    }
  }

  func stop() {
    timer?.invalidate()
    timer = nil
    if let globalMouseMonitor {
      NSEvent.removeMonitor(globalMouseMonitor)
      self.globalMouseMonitor = nil
    }
    panel.orderOut(nil)
    panel.close()
    for prop in environmentProps {
      prop.panel.orderOut(nil)
      prop.panel.close()
    }
  }

  @objc private func tick(_ timer: Timer) {
    advance(at: ProcessInfo.processInfo.systemUptime)
  }

  func advance(at now: TimeInterval) {
    if let behaviorSession {
      do {
        try renderBehavior(
          behaviorSession.update(
            at: now,
            motionScale: motionScale,
            currentPetCenterX: currentPetCenterScreenX
          )
        )
        updateMousePassthrough()
      } catch {
        recoverBehavior(after: error)
      }
    } else {
      let elapsed = max(0, now - playbackStartUptime)
      do {
        try renderStatic(staticTimeline.sample(at: elapsed))
      } catch {
        failAndTerminate(error)
      }
    }
  }

  private func renderStatic(_ sample: TimelineSample) throws {
    if sample.segmentIndex != currentSegmentIndex {
      currentSegmentIndex = sample.segmentIndex
      try imageCache.prepare(
        clipIDs: staticTimeline.clipIDsNear(segmentIndex: sample.segmentIndex)
      )
      onClipChanged?(sample.clipID)
      print(
        String(
          format: "petsgraph segment=%d clip=%@ x=%.2f",
          sample.segmentIndex,
          sample.clipID,
          startX + sample.rootMotionXPt * motionScale
        )
      )
    }

    try renderFrame(
      sample,
      x: startX + sample.rootMotionXPt * motionScale,
      mirrored: false
    )
  }

  private func renderBehavior(_ presentation: BehaviorPresentation) throws {
    let sample = presentation.sample
    if presentation.interactionState != lastInteractionState {
      let priorState = lastInteractionState
      lastInteractionState = presentation.interactionState
      print("petsgraph interaction-state=\(presentation.interactionState)")
      if presentation.interactionState == .sitting, priorState != nil {
        showCommandFeedback(
          quietCompanion ? "再点一下，回去睡觉" : "点击桌面，让\(petDisplayName)过去"
        )
      }
    }
    if presentation.generation != currentGeneration
      || sample.segmentIndex != currentSegmentIndex
    {
      currentGeneration = presentation.generation
      currentSegmentIndex = sample.segmentIndex
      try imageCache.prepare(clipIDs: presentation.clipIDsToPreload)
      onClipChanged?(sample.clipID)
      print(
        String(
          format: "petsgraph behavior generation=%d segment=%d clip=%@ x=%.2f mirrored=%@",
          presentation.generation,
          sample.segmentIndex,
          sample.clipID,
          startX + presentation.totalRootMotionXPt * motionScale,
          presentation.mirrored ? "yes" : "no"
        )
      )
    }

    try renderFrame(
      sample,
      x: startX + presentation.totalRootMotionXPt * motionScale,
      mirrored: presentation.mirrored
    )
  }

  private func renderFrame(
    _ sample: TimelineSample,
    x: Double,
    mirrored: Bool
  ) throws {
    if
      currentFrame != nil,
      currentClipID == sample.clipID,
      currentSourceFrameIndex == sample.sourceFrameIndex,
      currentFrameIsMirrored == mirrored,
      abs(calculatedPanelX - x) < 0.001
    {
      return
    }
    guard let frame = try imageCache.frame(
      clipID: sample.clipID,
      frameIndex: sample.sourceFrameIndex
    ) else {
      return
    }
    guard
      let clipDefinition = package.clips[sample.clipID],
      clipDefinition.frames.indices.contains(sample.sourceFrameIndex)
    else {
      throw PackageValidationError.invalid(
        "clip \(sample.clipID) has no frame contract for \(sample.sourceFrameIndex)"
      )
    }
    let frameDefinition = clipDefinition.frames[sample.sourceFrameIndex]
    let clipChanged = currentClipID != sample.clipID
    let viewport = viewportsByClipID[sample.clipID] ?? activeViewport
    currentFrame = frame
    currentFrameIsMirrored = mirrored
    currentClipID = sample.clipID
    currentSourceFrameIndex = sample.sourceFrameIndex
    activeViewport = viewport
    calculatedPanelX = x
    if !isDraggingPet {
      let pixelScale = displayHeightPt / canvasHeightPx
      let authoredPresentationOffsetPx = frameDefinition.presentationOffsetPx?.first ?? 0
      let presentationOffsetPt = authoredPresentationOffsetPx * pixelScale
      var canvasOrigin = NSPoint(
        x: x + manualOffsetX + (mirrored ? -presentationOffsetPt : presentationOffsetPt),
        y: windowY + manualOffsetY
      )
      var desiredFrame = viewport.panelFrame(
        canvasOrigin: canvasOrigin,
        canvasHeightPx: canvasHeightPx,
        pixelScale: pixelScale
      )
      let boundaryAdjustment = PetVisibleContentBoundary.horizontalAdjustment(
        contentBoundsPx: frameDefinition.contentBoundsPx,
        canvasOriginX: canvasOrigin.x,
        canvasWidthPx: canvasWidthPx,
        pixelScale: pixelScale,
        screenFrame: screenFrame,
        margin: screenMargin,
        mirrored: mirrored
      )
      if boundaryAdjustment != 0 {
        if abs(presentationOffsetPt) < 0.000_001 {
          manualOffsetX += boundaryAdjustment
        }
        canvasOrigin.x += boundaryAdjustment
        desiredFrame = viewport.panelFrame(
          canvasOrigin: canvasOrigin,
          canvasHeightPx: canvasHeightPx,
          pixelScale: pixelScale
        )
      }
      if
        abs(panel.frame.minX - desiredFrame.minX) >= 0.001
          || abs(panel.frame.minY - desiredFrame.minY) >= 0.001
          || abs(panel.frame.width - desiredFrame.width) >= 0.001
      {
        panel.setFrame(desiredFrame, display: true)
        positionEnvironmentProps()
      }
      let hitBoundary = boundaryAdjustment != 0
      if hitBoundary, !wasClampedAtHorizontalBoundary {
        print(
          String(
            format: "petsgraph movement clamped-and-rebased boundary-x=%.1f",
            desiredFrame.minX
          )
        )
      }
      wasClampedAtHorizontalBoundary = hitBoundary
    }
    imageView.setFrameImage(
      frame.cgImage,
      cropRectPx: frame.cropRectPx,
      canvasPx: package.manifest.art.canvasPx,
      viewportPx: viewport,
      mirrored: mirrored
    )
    if clipChanged {
      updateEnvironmentPropVisibility(for: sample.clipID)
    }
  }

  private func handlePetClick() {
    guard let behaviorSession else { return }
    do {
      let result = try behaviorSession.handlePetClick(
        at: ProcessInfo.processInfo.systemUptime
      )
      switch result {
      case .wakeStarted:
        showCommandFeedback("正在起身")
      case .wakeQueued:
        showCommandFeedback("动作结束后起身")
      case .sleepStarted:
        showCommandFeedback("准备睡觉")
      case .sleepQueued:
        showCommandFeedback("动作结束后睡觉")
      case .debounced:
        showCommandFeedback("正在响应刚才的点击")
      case .transitionInProgress:
        showCommandFeedback("先让\(petDisplayName)完成当前动作")
      case .alreadyReturningToSleep:
        showCommandFeedback("正在准备睡觉")
      }
    } catch {
      reportBehaviorCommandError(error)
    }
  }

  private func installDestinationClickMonitor() {
    guard engineeringBehaviorPreview, globalMouseMonitor == nil else { return }
    globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: [.leftMouseDown]
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.handleDestinationClick(at: NSEvent.mouseLocation)
      }
    }
    print("petsgraph full-screen destination click monitor installed")
  }

  private func handleDestinationClick(at point: NSPoint) {
    guard let behaviorSession else { return }
    do {
      let result = try behaviorSession.requestDestination(
        targetX: point.x,
        currentPetCenterX: currentPetCenterScreenX,
        at: ProcessInfo.processInfo.systemUptime,
        motionScale: motionScale
      )
      switch result {
      case let .started(gait, direction, plannedDistancePt):
        let gaitName = gait == .run ? "跑步" : "走路"
        let directionName = direction == .left ? "左边" : "右边"
        showCommandFeedback(
          String(format: "向%@%@ %.0f 点", directionName, gaitName, plannedDistancePt)
        )
      case .queued:
        showCommandFeedback("已记住新的目的地")
      case .tooClose:
        showCommandFeedback("已经在附近了")
      case .ignored, .unavailable:
        break
      }
    } catch {
      reportBehaviorCommandError(error)
    }
  }

  private func beginPetDrag(at point: NSPoint) {
    behaviorSession?.handleDragStarted()
    dragStartMouse = point
    dragStartCanvasOrigin = persistentOrigin
    isDraggingPet = true
    didDragPet = false
    panel.ignoresMouseEvents = false
    print(
      String(
        format: "petsgraph pointer-down x=%.1f y=%.1f",
        point.x,
        point.y
      )
    )
  }

  private func continuePetDrag(to point: NSPoint) {
    guard isDraggingPet else { return }
    let deltaX = point.x - dragStartMouse.x
    let deltaY = point.y - dragStartMouse.y
    if hypot(deltaX, deltaY) >= 4 {
      didDragPet = true
    }
    var canvasOrigin = NSPoint(
      x: dragStartCanvasOrigin.x + deltaX,
      y: dragStartCanvasOrigin.y + deltaY
    )
    let pixelScale = displayHeightPt / canvasHeightPx
    var proposedFrame = activeViewport.panelFrame(
      canvasOrigin: canvasOrigin,
      canvasHeightPx: canvasHeightPx,
      pixelScale: pixelScale
    )
    if proposedFrame.minX < screenFrame.minX + screenMargin {
      canvasOrigin.x += screenFrame.minX + screenMargin - proposedFrame.minX
    } else if proposedFrame.maxX > screenFrame.maxX - screenMargin {
      canvasOrigin.x += screenFrame.maxX - screenMargin - proposedFrame.maxX
    }
    canvasOrigin.y = max(
      screenFrame.minY - groundFromWindowBottomPt + screenMargin,
      canvasOrigin.y
    )
    proposedFrame = activeViewport.panelFrame(
      canvasOrigin: canvasOrigin,
      canvasHeightPx: canvasHeightPx,
      pixelScale: pixelScale
    )
    if proposedFrame.maxY > screenFrame.maxY - screenMargin {
      canvasOrigin.y -= proposedFrame.maxY - (screenFrame.maxY - screenMargin)
      proposedFrame = activeViewport.panelFrame(
        canvasOrigin: canvasOrigin,
        canvasHeightPx: canvasHeightPx,
        pixelScale: pixelScale
      )
    }
    manualOffsetX = canvasOrigin.x - calculatedPanelX
    manualOffsetY = canvasOrigin.y - windowY
    panel.setFrame(proposedFrame, display: true)
    positionEnvironmentProps(
      floorOriginX: canvasOrigin.x,
      floorOriginY: canvasOrigin.y
    )
  }

  private func finishPetDrag(at point: NSPoint) {
    guard isDraggingPet else { return }
    continuePetDrag(to: point)
    isDraggingPet = false
    if didDragPet {
      print(
        String(
          format: "petsgraph pointer-dragged new-x=%.1f new-y=%.1f",
          panel.frame.minX,
          panel.frame.minY
        )
      )
      onPositionChanged?(persistentOrigin)
    } else {
      print("petsgraph pointer-click")
      showClickFeedback(at: point)
      handlePetClick()
    }
    updateMousePassthrough()
  }

  private func forceMovement(_ gait: PreviewMovementGait) {
    guard let behaviorSession else { return }
    do {
      let distances = availableTravelDistances()
      let result = try behaviorSession.forceMovement(
        gait,
        at: ProcessInfo.processInfo.systemUptime,
        motionScale: motionScale,
        availableLeftPt: distances.left,
        availableRightPt: distances.right
      )
      let gaitName = gait == .run ? "跑步" : "走路"
      switch result {
      case .started:
        showCommandFeedback("\(gaitName)链已开始")
      case .queued:
        showCommandFeedback("\(gaitName)已排队")
      case .unavailable:
        showCommandFeedback("空间不足，无法\(gaitName)")
      case .ignored:
        showCommandFeedback("当前动作暂不可响应")
      }
    } catch {
      reportBehaviorCommandError(error)
    }
  }

  private func startNativeLeftChainDemo(at uptime: TimeInterval) throws {
    guard let behaviorSession else {
      throw PackageValidationError.invalid(
        "native left chain demo requires engineering behavior preview"
      )
    }
    let distances = availableTravelDistances()
    let result = try behaviorSession.forceMovement(
      .run,
      direction: .left,
      at: uptime,
      motionScale: motionScale,
      availableLeftPt: distances.left,
      availableRightPt: distances.right
    )
    guard case .queued = result else {
      throw PackageValidationError.invalid(
        "native left chain demo could not queue its movement plan"
      )
    }
    print(
      "petsgraph native-left-chain-demo queued; external destination clicks disabled"
    )
  }

  private func availableTravelDistances() -> (left: Double, right: Double) {
    (
      left: max(0, panel.frame.minX - (screenFrame.minX + screenMargin)),
      right: max(0, screenFrame.maxX - screenMargin - panel.frame.maxX)
    )
  }

  private func showClickFeedback(at screenPoint: NSPoint) {
    guard let layer = rootView.layer else { return }
    let localPoint = NSPoint(
      x: screenPoint.x - panel.frame.minX,
      y: screenPoint.y - panel.frame.minY
    )

    let ring = CAShapeLayer()
    ring.path = CGPath(
      ellipseIn: CGRect(x: -10, y: -10, width: 20, height: 20),
      transform: nil
    )
    ring.position = localPoint
    ring.fillColor = NSColor.clear.cgColor
    ring.strokeColor = NSColor.systemPink.cgColor
    ring.lineWidth = 3
    ring.shadowColor = NSColor.white.cgColor
    ring.shadowOpacity = 0.9
    ring.shadowRadius = 3
    layer.addSublayer(ring)

    let ringScale = CABasicAnimation(keyPath: "transform.scale")
    ringScale.fromValue = 0.7
    ringScale.toValue = 2.8
    let ringFade = CABasicAnimation(keyPath: "opacity")
    ringFade.fromValue = 1.0
    ringFade.toValue = 0.0
    let ringGroup = CAAnimationGroup()
    ringGroup.animations = [ringScale, ringFade]
    ringGroup.duration = 0.7
    ringGroup.timingFunction = CAMediaTimingFunction(name: .easeOut)
    ringGroup.fillMode = .forwards
    ringGroup.isRemovedOnCompletion = false
    ring.add(ringGroup, forKey: "click-ring")

    let heart = CATextLayer()
    heart.string = "♥"
    heart.fontSize = 24
    heart.alignmentMode = .center
    heart.foregroundColor = NSColor.systemPink.cgColor
    heart.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
    heart.frame = CGRect(
      x: localPoint.x - 18,
      y: localPoint.y + 8,
      width: 36,
      height: 32
    )
    heart.shadowColor = NSColor.white.cgColor
    heart.shadowOpacity = 1
    heart.shadowRadius = 2
    layer.addSublayer(heart)

    let heartRise = CABasicAnimation(keyPath: "transform.translation.y")
    heartRise.fromValue = 0
    heartRise.toValue = 28
    let heartFade = CABasicAnimation(keyPath: "opacity")
    heartFade.fromValue = 1.0
    heartFade.toValue = 0.0
    let heartGroup = CAAnimationGroup()
    heartGroup.animations = [heartRise, heartFade]
    heartGroup.duration = 0.9
    heartGroup.timingFunction = CAMediaTimingFunction(name: .easeOut)
    heartGroup.fillMode = .forwards
    heartGroup.isRemovedOnCompletion = false
    heart.add(heartGroup, forKey: "click-heart")

    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
      ring.removeFromSuperlayer()
      heart.removeFromSuperlayer()
    }
  }

  private func showCommandFeedback(_ text: String) {
    guard let layer = rootView.layer else { return }
    let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
    let measuredWidth = ceil(
      (text as NSString).size(withAttributes: [.font: font]).width
    )
    let badgeWidth = min(
      max(0, rootView.bounds.width - 10),
      max(120, min(240, measuredWidth + 24))
    )
    let contentFrame = currentContentFrameInPanel()
    let preferredCenterX = contentFrame?.midX ?? rootView.bounds.midX
    let badgeX = min(
      max(5, preferredCenterX - badgeWidth / 2),
      max(5, rootView.bounds.width - badgeWidth - 5)
    )
    let preferredY = (contentFrame?.maxY ?? rootView.bounds.maxY) + 6
    let badgeY = min(
      max(5, preferredY),
      max(5, rootView.bounds.height - 29)
    )
    let badge = CATextLayer()
    badge.string = text
    badge.font = font
    badge.fontSize = 13
    badge.alignmentMode = .center
    badge.foregroundColor = NSColor.white.cgColor
    badge.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
    badge.cornerRadius = 10
    badge.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
    badge.frame = CGRect(
      x: badgeX,
      y: badgeY,
      width: badgeWidth,
      height: 24
    )
    layer.addSublayer(badge)

    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = 1.0
    fade.toValue = 0.0
    fade.beginTime = CACurrentMediaTime() + 1.2
    fade.duration = 0.5
    fade.fillMode = .forwards
    fade.isRemovedOnCompletion = false
    badge.add(fade, forKey: "command-feedback")
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
      badge.removeFromSuperlayer()
    }
  }

  private func updateMousePassthrough() {
    if isDraggingPet {
      panel.ignoresMouseEvents = false
      return
    }
    guard
      behaviorSession != nil,
      let frame = currentFrame,
      panel.frame.contains(NSEvent.mouseLocation)
    else {
      setPointerHit(false)
      return
    }
    let mouse = NSEvent.mouseLocation
    let normalizedX = (mouse.x - panel.frame.minX) / panel.frame.width
    let normalizedY = (mouse.y - panel.frame.minY) / panel.frame.height
    guard normalizedX >= 0, normalizedX < 1, normalizedY >= 0, normalizedY < 1 else {
      setPointerHit(false)
      return
    }
    let canvasWidth = package.manifest.art.canvasPx[0]
    let canvasHeight = package.manifest.art.canvasPx[1]
    var sourceX = activeViewport.x + normalizedX * activeViewport.side
    if currentFrameIsMirrored {
      sourceX = Double(canvasWidth) - sourceX
    }
    let sourceY = activeViewport.y + (1 - normalizedY) * activeViewport.side
    let pixelX = Int(floor(sourceX))
    let pixelY = Int(floor(sourceY))
    guard
      pixelX >= 0,
      pixelY >= 0,
      pixelX < canvasWidth,
      pixelY < canvasHeight
    else {
      setPointerHit(false)
      return
    }
    let opaque = frame.alpha(canvasX: pixelX, canvasY: pixelY) > 0.05
    let hitRegion = currentPetHitEllipse()
    let insidePetRegion = hitRegion.map { ellipseContains($0, x: pixelX, y: pixelY) } ?? true
    setPointerHit(opaque && insidePetRegion)
  }

  private func currentContentFrameInPanel() -> CGRect? {
    guard
      let currentClipID,
      let currentSourceFrameIndex,
      let clip = package.clips[currentClipID],
      clip.frames.indices.contains(currentSourceFrameIndex)
    else { return nil }
    let bounds = clip.frames[currentSourceFrameIndex].contentBoundsPx
    guard bounds.count == 4, activeViewport.side > 0 else { return nil }
    let scale = rootView.bounds.width / activeViewport.side
    return CGRect(
      x: (bounds[0] - activeViewport.x) * scale,
      y: (activeViewport.y + activeViewport.side - bounds[1] - bounds[3]) * scale,
      width: bounds[2] * scale,
      height: bounds[3] * scale
    )
  }

  private func currentPetHitEllipse() -> [Double]? {
    guard
      let currentClipID,
      let currentSourceFrameIndex,
      let clip = package.clips[currentClipID],
      clip.frames.indices.contains(currentSourceFrameIndex)
    else {
      return nil
    }
    let frame = clip.frames[currentSourceFrameIndex]
    // Floor scenes have no prop to distinguish, so every opaque pet pixel is
    // intentionally clickable. Pillow scenes use the narrower authored pet
    // ellipse to keep the exposed pillow from becoming a click target.
    guard frame.propBoundsPx?.isEmpty == false else { return nil }
    return frame.collision.petHitEllipsePx
  }

  private func ellipseContains(_ ellipse: [Double], x: Int, y: Int) -> Bool {
    guard ellipse.count == 4, ellipse[2] > 0, ellipse[3] > 0 else { return false }
    let pointX = Double(x)
    let centerX = ellipse[0] + ellipse[2] / 2
    let centerY = ellipse[1] + ellipse[3] / 2
    let dx = (pointX - centerX) / (ellipse[2] / 2)
    let dy = (Double(y) - centerY) / (ellipse[3] / 2)
    return dx * dx + dy * dy <= 1
  }

  private func setPointerHit(_ hit: Bool) {
    panel.ignoresMouseEvents = !hit
    if hit != lastPointerHit {
      lastPointerHit = hit
      print("petsgraph pointer-hit=\(hit ? "yes" : "no")")
    }
  }

  private func positionEnvironmentProps(
    floorOriginX: Double? = nil,
    floorOriginY: Double? = nil
  ) {
    let originX = floorOriginX ?? (startX + manualOffsetX)
    let originY = floorOriginY ?? (windowY + manualOffsetY)
    for prop in environmentProps {
      prop.panel.setFrameOrigin(
        NSPoint(
          x: originX + prop.definition.offsetFromFloorOriginPt[0] * motionScale,
          y: originY + prop.definition.offsetFromFloorOriginPt[1] * motionScale
        )
      )
    }
  }

  private func environmentPropIsVisible(
    _ definition: EnvironmentProp,
    for clipID: String?
  ) -> Bool {
    if definition.visibility == "persistent" {
      return true
    }
    guard
      definition.visibility == "node-scenes",
      let clipID,
      package.clips[clipID]?.type == "loop",
      let node = package.graph.nodes.first(where: { $0.loopClip == clipID }),
      let scene = node.scene
    else {
      return false
    }
    return definition.scenes?.contains(scene) == true
  }

  private func updateEnvironmentPropVisibility(for clipID: String?) {
    for prop in environmentProps {
      let visible = environmentPropIsVisible(prop.definition, for: clipID)
      if visible {
        prop.panel.orderFrontRegardless()
        panel.orderFrontRegardless()
      } else {
        prop.panel.orderOut(nil)
      }
      let visibility = visible ? "yes" : "no"
      let activeClip = clipID ?? "none"
      print(
        "petsgraph environment-prop=\(prop.definition.id) "
          + "visible=\(visibility) clip=\(activeClip)"
      )
    }
  }

  private func orderPanelsFront() {
    positionEnvironmentProps()
    for prop in environmentProps {
      if environmentPropIsVisible(prop.definition, for: currentClipID) {
        prop.panel.orderFrontRegardless()
      } else {
        prop.panel.orderOut(nil)
      }
    }
    panel.orderFrontRegardless()
  }

  private func failAndTerminate(_ error: Error) {
    fputs("petsgraph: \(error)\n", stderr)
    NSApplication.shared.terminate(nil)
  }

  private func reportBehaviorCommandError(_ error: Error) {
    fputs("petsgraph behavior command rejected: \(error)\n", stderr)
    showCommandFeedback("动作暂不可用，宠物仍在运行")
  }

  private func recoverBehavior(after error: Error) {
    fputs("petsgraph behavior recovered after: \(error)\n", stderr)
    guard let behaviorSession else {
      failAndTerminate(error)
      return
    }
    do {
      let now = ProcessInfo.processInfo.systemUptime
      try behaviorSession.resetToSleep(at: now)
      currentSegmentIndex = -1
      currentGeneration = -1
      try renderBehavior(
        behaviorSession.update(
          at: now,
          motionScale: motionScale,
          currentPetCenterX: currentPetCenterScreenX
        )
      )
      orderPanelsFront()
      showCommandFeedback("动作已恢复")
    } catch {
      failAndTerminate(error)
    }
  }
}
