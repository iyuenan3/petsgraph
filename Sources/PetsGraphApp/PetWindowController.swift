import AppKit
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

final class PetImageView: NSImageView {
  var onPetMouseDown: ((NSPoint) -> Void)?
  var onPetMouseDragged: ((NSPoint) -> Void)?
  var onPetMouseUp: ((NSPoint) -> Void)?

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

struct CachedPetFrame {
  let image: NSImage
  let mirroredImage: NSImage?
  let bitmap: NSBitmapImageRep
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
final class ClipImageCache {
  private let package: LoadedPetPackage
  private let createMirroredImages: Bool
  private var frames: [String: [CachedPetFrame]] = [:]

  init(package: LoadedPetPackage, createMirroredImages: Bool) {
    self.package = package
    self.createMirroredImages = createMirroredImages
  }

  func prepare(clipIDs: [String]) throws {
    let retained = Set(clipIDs)
    frames = frames.filter { retained.contains($0.key) }
    for clipID in clipIDs where frames[clipID] == nil {
      guard let clip = package.clips[clipID] else {
        throw PackageValidationError.invalid("unknown clip \(clipID)")
      }
      let loaded = try clip.frames.indices.map { frameIndex in
        guard
          let url = package.frameURL(clipID: clipID, frameIndex: frameIndex),
          let data = try? Data(contentsOf: url),
          let bitmap = NSBitmapImageRep(data: data)
        else {
          throw PackageValidationError.missing("\(clipID) frame \(frameIndex)")
        }
        let image = NSImage(size: bitmap.size)
        image.addRepresentation(bitmap)
        image.cacheMode = .always
        return CachedPetFrame(
          image: image,
          mirroredImage: createMirroredImages ? Self.makeMirroredImage(image) : nil,
          bitmap: bitmap
        )
      }
      frames[clipID] = loaded
      print("petsgraph preloaded clip=\(clipID) frames=\(loaded.count)")
    }
  }

  func frame(clipID: String, frameIndex: Int) -> CachedPetFrame? {
    guard let clipFrames = frames[clipID], clipFrames.indices.contains(frameIndex) else {
      return nil
    }
    return clipFrames[frameIndex]
  }

  private static func makeMirroredImage(_ source: NSImage) -> NSImage {
    let mirrored = NSImage(size: source.size)
    mirrored.lockFocus()
    let transform = NSAffineTransform()
    transform.translateX(by: source.size.width, yBy: 0)
    transform.scaleX(by: -1, yBy: 1)
    transform.concat()
    source.draw(
      in: NSRect(origin: .zero, size: source.size),
      from: .zero,
      operation: .copy,
      fraction: 1
    )
    mirrored.unlockFocus()
    mirrored.cacheMode = .always
    return mirrored
  }
}

@MainActor
final class PetWindowController {
  var onClipChanged: ((String) -> Void)?

  private let package: LoadedPetPackage
  private let petDisplayName: String
  private let staticTimeline: PlaybackTimeline
  private let panel: PetPanel
  private let rootView: NSView
  private let imageView: PetImageView
  private let imageCache: ClipImageCache
  private let startDelaySeconds: Double
  private let displayHeightPt: Double
  private let motionScale: Double
  private let startX: Double
  private let windowY: Double
  private let groundFromWindowBottomPt: Double
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
  private var currentFrameIsMirrored = false
  private var currentClipID: String?
  private var currentSourceFrameIndex: Int?
  private var calculatedPanelX = 0.0
  private var manualOffsetX = 0.0
  private var manualOffsetY = 0.0
  private var dragStartMouse = NSPoint.zero
  private var dragStartPanelOrigin = NSPoint.zero
  private var isDraggingPet = false
  private var didDragPet = false
  private var lastPointerHit = false
  private var wasClampedAtHorizontalBoundary = false

  init(
    package: LoadedPetPackage,
    requestedDisplayHeightPt: Double,
    startDelaySeconds: Double,
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
    let canvasAspect = canvasWidth / canvasHeight
    let footprintFactor = canvasAspect + (
      engineeringBehaviorPreview ? 0 : staticTimeline.finiteRootMotionXPt / baseHeight
    )
    let maximumHeight = (visible.width - 2 * screenMargin) / max(1, footprintFactor)
    displayHeightPt = max(80, min(requestedDisplayHeightPt, maximumHeight))
    motionScale = displayHeightPt / baseHeight
    self.startDelaySeconds = startDelaySeconds

    let travel = engineeringBehaviorPreview
      ? 0
      : staticTimeline.finiteRootMotionXPt * motionScale
    let displayWidthPt = displayHeightPt * canvasAspect
    let footprint = displayWidthPt + travel
    groundFromWindowBottomPt = (
      canvasHeight - package.manifest.art.groundYPx
    ) / canvasHeight * displayHeightPt
    if quietCompanion {
      let placement = PetStartupPlacement.bottomLeft(
        screenFrame: screen.frame,
        groundFromWindowBottomPt: groundFromWindowBottomPt,
        margin: screenMargin
      )
      startX = placement.x
      windowY = placement.y
    } else {
      startX = max(visible.minX + screenMargin, visible.midX - footprint / 2)
      windowY = visible.minY + 5 - groundFromWindowBottomPt
    }

    panel = PetPanel(
      contentRect: NSRect(
        x: startX,
        y: windowY,
        width: displayWidthPt,
        height: displayHeightPt
      ),
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
    imageView.imageScaling = .scaleAxesIndependently
    imageView.wantsLayer = true
    imageView.layer?.backgroundColor = NSColor.clear.cgColor
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
        contentRect: NSRect(
          x: startX,
          y: windowY,
          width: displayWidthPt,
          height: displayHeightPt
        ),
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

  func start() {
    do {
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
        renderStatic(staticTimeline.sample(at: 0))
      }
      orderPanelsFront()
      if nativeLeftChainDemo {
        try startNativeLeftChainDemo(at: startUptime)
      } else if quietSceneRoundTripDemo {
        try behaviorSession?.startQuietSceneRoundTripDemo(at: startUptime)
      } else if engineeringBehaviorPreview, !quietCompanion {
        installDestinationClickMonitor()
      }
      let timer = Timer(
        timeInterval: 1.0 / 120.0,
        target: self,
        selector: #selector(tick(_:)),
        userInfo: nil,
        repeats: true
      )
      RunLoop.main.add(timer, forMode: .common)
      self.timer = timer
    } catch {
      fputs("petsgraph: \(error)\n", stderr)
      NSApplication.shared.terminate(nil)
    }
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
            currentPetCenterX: panel.frame.midX
          )
        )
      } catch {
        failAndTerminate(error)
        return
      }
    } else {
      playbackStartUptime = now + startDelaySeconds
      renderStatic(staticTimeline.sample(at: 0))
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
    let now = ProcessInfo.processInfo.systemUptime
    if let behaviorSession {
      do {
        try renderBehavior(
          behaviorSession.update(
            at: now,
            motionScale: motionScale,
            currentPetCenterX: panel.frame.midX
          )
        )
        updateMousePassthrough()
      } catch {
        recoverBehavior(after: error)
      }
    } else {
      let elapsed = max(0, now - playbackStartUptime)
      renderStatic(staticTimeline.sample(at: elapsed))
    }
  }

  private func renderStatic(_ sample: TimelineSample) {
    if sample.segmentIndex != currentSegmentIndex {
      currentSegmentIndex = sample.segmentIndex
      do {
        try imageCache.prepare(
          clipIDs: staticTimeline.clipIDsNear(segmentIndex: sample.segmentIndex)
        )
      } catch {
        failAndTerminate(error)
        return
      }
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

    renderFrame(
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

    renderFrame(
      sample,
      x: startX + presentation.totalRootMotionXPt * motionScale,
      mirrored: presentation.mirrored
    )
  }

  private func renderFrame(
    _ sample: TimelineSample,
    x: Double,
    mirrored: Bool
  ) {
    guard let frame = imageCache.frame(
      clipID: sample.clipID,
      frameIndex: sample.sourceFrameIndex
    ) else {
      return
    }
    let clipChanged = currentClipID != sample.clipID
    currentFrame = frame
    currentFrameIsMirrored = mirrored
    currentClipID = sample.clipID
    currentSourceFrameIndex = sample.sourceFrameIndex
    let displayedImage = mirrored ? (frame.mirroredImage ?? frame.image) : frame.image
    if imageView.image !== displayedImage {
      imageView.image = displayedImage
    }
    calculatedPanelX = x
    if !isDraggingPet {
      let placement = PreviewHorizontalPlacement.resolve(
        calculatedX: x,
        manualOffsetX: manualOffsetX,
        minimumX: screenFrame.minX + screenMargin,
        maximumX: screenFrame.maxX - screenMargin - panel.frame.width
      )
      manualOffsetX = placement.rebasedManualOffsetX
      panel.setFrameOrigin(
        NSPoint(
          x: placement.originX,
          y: windowY + manualOffsetY
        )
      )
      positionEnvironmentProps()
      if placement.hitBoundary, !wasClampedAtHorizontalBoundary {
        print(
          String(
            format: "petsgraph movement clamped-and-rebased boundary-x=%.1f",
            placement.originX
          )
        )
      }
      wasClampedAtHorizontalBoundary = placement.hitBoundary
    }
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
        currentPetCenterX: panel.frame.midX,
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
    dragStartPanelOrigin = panel.frame.origin
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
    let proposedX = dragStartPanelOrigin.x + deltaX
    let proposedY = dragStartPanelOrigin.y + deltaY
    let clampedX = min(
      screenFrame.maxX - screenMargin - panel.frame.width,
      max(screenFrame.minX + screenMargin, proposedX)
    )
    let clampedY = min(
      screenFrame.maxY - screenMargin - panel.frame.height,
      max(
        screenFrame.minY - groundFromWindowBottomPt + screenMargin,
        proposedY
      )
    )
    panel.setFrameOrigin(NSPoint(x: clampedX, y: clampedY))
    positionEnvironmentProps(
      floorOriginX: clampedX - (calculatedPanelX - startX),
      floorOriginY: clampedY
    )
  }

  private func finishPetDrag(at point: NSPoint) {
    guard isDraggingPet else { return }
    continuePetDrag(to: point)
    isDraggingPet = false
    manualOffsetX = panel.frame.minX - calculatedPanelX
    manualOffsetY = panel.frame.minY - windowY
    if didDragPet {
      print(
        String(
          format: "petsgraph pointer-dragged new-x=%.1f new-y=%.1f",
          panel.frame.minX,
          panel.frame.minY
        )
      )
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
    let badge = CATextLayer()
    badge.string = text
    badge.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
    badge.fontSize = 13
    badge.alignmentMode = .center
    badge.foregroundColor = NSColor.white.cgColor
    badge.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
    badge.cornerRadius = 10
    badge.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
    badge.frame = CGRect(
      x: 5,
      y: rootView.bounds.height - 31,
      width: rootView.bounds.width - 10,
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
    var pixelX = min(
      frame.bitmap.pixelsWide - 1,
      Int(normalizedX * Double(frame.bitmap.pixelsWide))
    )
    if currentFrameIsMirrored {
      pixelX = frame.bitmap.pixelsWide - 1 - pixelX
    }
    let unflippedPixelY = min(
      frame.bitmap.pixelsHigh - 1,
      Int(normalizedY * Double(frame.bitmap.pixelsHigh))
    )
    let pixelY = frame.bitmap.pixelsHigh - 1 - unflippedPixelY
    let opaque = (frame.bitmap.colorAt(x: pixelX, y: pixelY)?.alphaComponent ?? 0) > 0.05
    let hitRegion = currentPetHitEllipse()
    let insidePetRegion = hitRegion.map { ellipseContains($0, x: pixelX, y: pixelY) } ?? true
    setPointerHit(opaque && insidePetRegion)
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
          currentPetCenterX: panel.frame.midX
        )
      )
      orderPanelsFront()
      showCommandFeedback("动作已恢复")
    } catch {
      failAndTerminate(error)
    }
  }
}
