import AppKit
import CoreGraphics
import Foundation
import PetsGraphCore
import QuartzCore

final class PetPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }

  override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
    frameRect
  }
}

final class PetStageView: NSView {
  let frameLayer = CALayer()
  var onMouseDown: ((NSPoint) -> Void)?
  var onMouseDragged: ((NSPoint) -> Void)?
  var onMouseUp: ((NSPoint) -> Void)?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.masksToBounds = true
    frameLayer.contentsGravity = .resize
    frameLayer.minificationFilter = .linear
    frameLayer.magnificationFilter = .linear
    frameLayer.actions = [
      "bounds": NSNull(),
      "contents": NSNull(),
      "position": NSNull(),
    ]
    layer?.addSublayer(frameLayer)
  }

  required init?(coder: NSCoder) { nil }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func mouseDown(with event: NSEvent) { onMouseDown?(NSEvent.mouseLocation) }
  override func mouseDragged(with event: NSEvent) { onMouseDragged?(NSEvent.mouseLocation) }
  override func mouseUp(with event: NSEvent) { onMouseUp?(NSEvent.mouseLocation) }
}

private final class MappedFrameContext {
  let data: NSData
  init(data: NSData) { self.data = data }
}

private final class MappedRGBAClip {
  let clip: PetClip
  let representation: ClipRepresentation
  private let data: NSData
  private let colorSpace: CGColorSpace
  private var images: [Int: CGImage] = [:]

  init(package: LoadedPetPack, clip: PetClip) throws {
    guard let representation = clip.representations.first,
      let url = package.mediaURL(for: clip.id)
    else { throw PetPackError("missing_media", "clip has no baseline media") }
    self.clip = clip
    self.representation = representation
    data = try Data(contentsOf: url, options: [.mappedIfSafe]) as NSData
    guard data.length == representation.bytes else {
      throw PetPackError("invalid_media_length", "runtime media length changed")
    }
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
      throw PetPackError("render_unavailable", "sRGB color space is unavailable")
    }
    self.colorSpace = colorSpace
  }

  func image(frameIndex: Int) throws -> CGImage {
    guard (0..<clip.frameCount).contains(frameIndex) else {
      throw PetPackError("invalid_frame", "runtime requested an invalid frame")
    }
    if let image = images[frameIndex] { return image }
    let frameBytes = representation.bytesPerRow * representation.heightPx
    let offset = frameIndex * frameBytes
    guard offset >= 0, offset + frameBytes <= data.length else {
      throw PetPackError("invalid_media_length", "runtime frame exceeds its media")
    }
    let context = MappedFrameContext(data: data)
    let info = Unmanaged.passRetained(context).toOpaque()
    let bytes = data.bytes.advanced(by: offset)
    guard
      let provider = CGDataProvider(
        dataInfo: info,
        data: bytes,
        size: frameBytes,
        releaseData: { info, _, _ in
          guard let info else { return }
          Unmanaged<MappedFrameContext>.fromOpaque(info).release()
        }
      )
    else {
      Unmanaged<MappedFrameContext>.fromOpaque(info).release()
      throw PetPackError("render_unavailable", "could not create a frame data provider")
    }
    guard
      let image = CGImage(
        width: representation.widthPx,
        height: representation.heightPx,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: representation.bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGBitmapInfo(
          rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
        ),
        provider: provider,
        decode: nil,
        shouldInterpolate: true,
        intent: .defaultIntent
      )
    else {
      throw PetPackError("render_unavailable", "could not create an RGBA frame")
    }
    images[frameIndex] = image
    return image
  }

  func alpha(frameIndex: Int, canvasX: Int, canvasY: Int) -> Double {
    let crop = clip.geometry.cropPx
    guard
      crop.count == 4,
      (0..<clip.frameCount).contains(frameIndex),
      canvasX >= crop[0],
      canvasY >= crop[1],
      canvasX < crop[0] + crop[2],
      canvasY < crop[1] + crop[3]
    else { return 0 }
    let localX = canvasX - crop[0]
    let localY = canvasY - crop[1]
    let frameBytes = representation.bytesPerRow * representation.heightPx
    let offset = frameIndex * frameBytes + localY * representation.bytesPerRow + localX * 4 + 3
    guard offset >= 0, offset < data.length else { return 0 }
    return Double(data.bytes.load(fromByteOffset: offset, as: UInt8.self)) / 255
  }
}

@MainActor
final class PetWindowController {
  let package: LoadedPetPack
  let panel: PetPanel
  private let stageView: PetStageView
  private let session: PassiveBehaviorSession
  private let contentEnvelopePx: CGRect
  private var stores: [String: MappedRGBAClip] = [:]
  private var timer: Timer?
  private var globalMonitor: Any?
  private var localMonitor: Any?
  private var currentPresentation: PetPlaybackPresentation?
  private var scale: Double
  private(set) var anchor: NSPoint
  private(set) var petIsVisible = false
  private var dragging = false
  private var dragStartMouse = NSPoint.zero
  private var dragStartAnchor = NSPoint.zero
  private var didDrag = false
  private var lastPointerLocation = NSPoint.zero
  private var ignoresMouseEvents = true

  var onAnchorChanged: ((NSPoint) -> Void)?
  var onFault: ((Error) -> Void)?

  var packageID: String { package.manifest.package.id }
  var displayName: String { package.manifest.pet.displayName }
  var frame: NSRect { panel.frame }

  init(
    package: LoadedPetPack,
    scale: Double,
    anchor: NSPoint,
    startedAt: TimeInterval = ProcessInfo.processInfo.systemUptime
  ) throws {
    self.package = package
    self.scale = PlayerState.normalizedScale(scale)
    self.anchor = anchor
    contentEnvelopePx = Self.contentEnvelope(for: package)
    session = try PassiveBehaviorSession(package: package, startedAt: startedAt)
    panel = PetPanel(
      contentRect: .zero,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    stageView = PetStageView(frame: .zero)
    panel.contentView = stageView
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.level = .floating
    panel.hidesOnDeactivate = false
    panel.ignoresMouseEvents = true
    panel.collectionBehavior = [
      .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle,
    ]
    panel.title = "PetsGraph · \(package.manifest.pet.displayName)"
    applyGeometry()
    self.anchor = clampedAnchor(anchor)
    applyGeometry()

    stageView.onMouseDown = { [weak self] point in self?.beginDrag(at: point) }
    stageView.onMouseDragged = { [weak self] point in self?.continueDrag(to: point) }
    stageView.onMouseUp = { [weak self] point in self?.finishDrag(at: point) }
    installPointerMonitors()
    try render(at: startedAt)
  }

  func show(at now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
    do {
      try session.setVisible(true, at: now)
      petIsVisible = true
      panel.orderFrontRegardless()
      updatePointer(at: lastPointerLocation)
      startTimer()
    } catch { onFault?(error) }
  }

  func hide(at now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
    do {
      try session.setVisible(false, at: now)
      petIsVisible = false
      panel.orderOut(nil)
      setIgnoresMouseEvents(true)
      if session.shouldTickWhenHidden { startTimer() } else { stopTimer() }
    } catch { onFault?(error) }
  }

  func setScale(_ value: Double) {
    scale = PlayerState.normalizedScale(value)
    applyGeometry()
    anchor = clampedAnchor(anchor)
    applyGeometry()
    if let presentation = currentPresentation {
      updateLayerGeometry(for: package.clips[presentation.clipID]!)
    }
  }

  func dispose() {
    stopTimer()
    if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
    if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    self.globalMonitor = nil
    self.localMonitor = nil
    panel.orderOut(nil)
    panel.close()
    stores.removeAll()
  }

  private func startTimer() {
    guard timer == nil else { return }
    let interval = tickInterval(for: currentPresentation?.clipID)
    let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.tick() }
    }
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  private func stopTimer() {
    timer?.invalidate()
    timer = nil
  }

  private func tick() {
    do {
      try render(at: ProcessInfo.processInfo.systemUptime)
      if !petIsVisible, !session.shouldTickWhenHidden { stopTimer() }
    } catch {
      stopTimer()
      onFault?(error)
    }
  }

  private func render(at now: TimeInterval) throws {
    let presentation = try session.update(at: now)
    let retainedClipIDs = Set(presentation.preloadClipIDs + [presentation.clipID])
    do {
      for clipID in presentation.preloadClipIDs {
        _ = try store(for: clipID).image(frameIndex: 0)
      }
    } catch {
      if !presentation.isTransition {
        retainStores(for: [presentation.clipID])
        try session.cancelPlannedTransition(at: now)
        return
      }
      throw error
    }
    guard
      currentPresentation?.clipID != presentation.clipID
        || currentPresentation?.frameIndex != presentation.frameIndex
    else {
      retainStores(for: retainedClipIDs)
      return
    }
    let store = try store(for: presentation.clipID)
    let image = try store.image(frameIndex: presentation.frameIndex)
    let clipChanged = currentPresentation?.clipID != presentation.clipID
    stageView.frameLayer.contents = image
    if clipChanged { updateLayerGeometry(for: store.clip) }
    currentPresentation = presentation
    retainStores(for: retainedClipIDs)
    updateTimerInterval(for: presentation.clipID)
    updatePointer(at: lastPointerLocation)
  }

  private func store(for clipID: String) throws -> MappedRGBAClip {
    if let existing = stores[clipID] { return existing }
    guard let clip = package.clips[clipID] else {
      throw PetPackError("missing_clip", "runtime requested a missing clip")
    }
    let result = try MappedRGBAClip(package: package, clip: clip)
    stores[clipID] = result
    return result
  }

  private func retainStores(for clipIDs: Set<String>) {
    let obsolete = stores.keys.filter { !clipIDs.contains($0) }
    for clipID in obsolete { stores.removeValue(forKey: clipID) }
  }

  private func updateTimerInterval(for clipID: String) {
    guard let timer else { return }
    let interval = tickInterval(for: clipID)
    guard abs(timer.timeInterval - interval) > 0.000_001 else { return }
    stopTimer()
    startTimer()
  }

  private func tickInterval(for clipID: String?) -> TimeInterval {
    guard let clipID, let clip = package.clips[clipID] else { return 1.0 / 30.0 }
    let frameDuration =
      Double(clip.frameRate.denominator) / Double(clip.frameRate.numerator)
    return max(1.0 / 60.0, frameDuration)
  }

  private func applyGeometry() {
    let canvas = package.manifest.stage.referenceCanvasPx
    let displayHeight = package.manifest.stage.baseDisplayHeight * scale
    let displayWidth = displayHeight * Double(canvas[0]) / Double(canvas[1])
    panel.setFrame(
      NSRect(
        x: anchor.x - displayWidth / 2,
        y: anchor.y,
        width: displayWidth,
        height: displayHeight
      ),
      display: true
    )
    stageView.frame = NSRect(origin: .zero, size: panel.frame.size)
  }

  private func updateLayerGeometry(for clip: PetClip) {
    let canvas = package.manifest.stage.referenceCanvasPx
    let crop = clip.geometry.cropPx
    let pixelScale = panel.frame.height / Double(canvas[1])
    stageView.frameLayer.frame = CGRect(
      x: Double(crop[0]) * pixelScale,
      y: Double(canvas[1] - crop[1] - crop[3]) * pixelScale,
      width: Double(crop[2]) * pixelScale,
      height: Double(crop[3]) * pixelScale
    )
  }

  private func installPointerMonitors() {
    lastPointerLocation = NSEvent.mouseLocation
    let mask: NSEvent.EventTypeMask = [
      .mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp,
    ]
    globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
      Task { @MainActor [weak self] in self?.pointerMoved(to: NSEvent.mouseLocation) }
    }
    localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
      self?.pointerMoved(to: NSEvent.mouseLocation)
      return event
    }
  }

  private func pointerMoved(to point: NSPoint) {
    lastPointerLocation = point
    updatePointer(at: point)
  }

  private func updatePointer(at point: NSPoint) {
    guard petIsVisible, !dragging, panel.frame.contains(point),
      let presentation = currentPresentation,
      let store = stores[presentation.clipID]
    else {
      if !dragging { setIgnoresMouseEvents(true) }
      return
    }
    let canvas = package.manifest.stage.referenceCanvasPx
    let normalizedX = (point.x - panel.frame.minX) / panel.frame.width
    let normalizedY = (point.y - panel.frame.minY) / panel.frame.height
    let canvasX = min(canvas[0] - 1, max(0, Int(floor(normalizedX * Double(canvas[0])))))
    let canvasY = min(canvas[1] - 1, max(0, Int(floor((1 - normalizedY) * Double(canvas[1])))))
    setIgnoresMouseEvents(
      store.alpha(
        frameIndex: presentation.frameIndex,
        canvasX: canvasX,
        canvasY: canvasY
      ) <= 0.05)
  }

  private func setIgnoresMouseEvents(_ value: Bool) {
    guard ignoresMouseEvents != value else { return }
    ignoresMouseEvents = value
    panel.ignoresMouseEvents = value
  }

  private func beginDrag(at point: NSPoint) {
    dragging = true
    didDrag = false
    dragStartMouse = point
    dragStartAnchor = anchor
    setIgnoresMouseEvents(false)
  }

  private func continueDrag(to point: NSPoint) {
    guard dragging else { return }
    let dx = point.x - dragStartMouse.x
    let dy = point.y - dragStartMouse.y
    if hypot(dx, dy) >= 3 { didDrag = true }
    anchor = clampedAnchor(NSPoint(x: dragStartAnchor.x + dx, y: dragStartAnchor.y + dy))
    applyGeometry()
  }

  private func finishDrag(at point: NSPoint) {
    guard dragging else { return }
    continueDrag(to: point)
    dragging = false
    if didDrag { onAnchorChanged?(anchor) }
    updatePointer(at: point)
  }

  private func clampedAnchor(_ candidate: NSPoint) -> NSPoint {
    let contentBounds = activeContentBoundsPx()
    let proposed = contentFrame(at: candidate, contentBounds: contentBounds)
    let screen = NSScreen.screens.first(where: { $0.frame.intersects(proposed) }) ?? NSScreen.main
    guard let screenFrame = screen?.frame else { return candidate }
    let canvas = package.manifest.stage.referenceCanvasPx
    return PetWindowPlacement.clampedAnchor(
      candidate,
      panelSize: panel.frame.size,
      canvasHeight: CGFloat(canvas[1]),
      contentBounds: contentBounds,
      screenFrame: screenFrame
    )
  }

  private func contentFrame(at candidate: NSPoint, contentBounds: CGRect) -> NSRect {
    let canvas = package.manifest.stage.referenceCanvasPx
    let pixelScale = panel.frame.height / Double(canvas[1])
    return NSRect(
      x: candidate.x - panel.frame.width / 2 + contentBounds.minX * pixelScale,
      y: candidate.y + (Double(canvas[1]) - contentBounds.maxY) * pixelScale,
      width: contentBounds.width * pixelScale,
      height: contentBounds.height * pixelScale
    )
  }

  private func activeContentBoundsPx() -> CGRect {
    let clipID =
      currentPresentation?.clipID
      ?? package.graph.nodes.first {
        $0.id == package.manifest.stage.defaultNode
      }?.loopClip
    guard let clipID, let clip = package.clips[clipID] else { return contentEnvelopePx }
    let crop = clip.geometry.cropPx
    return CGRect(x: crop[0], y: crop[1], width: crop[2], height: crop[3])
  }

  private static func contentEnvelope(for package: LoadedPetPack) -> CGRect {
    package.clips.values.reduce(CGRect.null) { result, clip in
      let crop = clip.geometry.cropPx
      return result.union(
        CGRect(x: crop[0], y: crop[1], width: crop[2], height: crop[3]))
    }
  }
}
