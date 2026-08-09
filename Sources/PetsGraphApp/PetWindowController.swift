import AppKit
import Foundation
import PetsGraphCore

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

@MainActor
final class ClipImageCache {
  private let package: LoadedPetPackage
  private var images: [String: [NSImage]] = [:]

  init(package: LoadedPetPackage) {
    self.package = package
  }

  func prepare(clipIDs: [String]) throws {
    let retained = Set(clipIDs)
    images = images.filter { retained.contains($0.key) }
    for clipID in clipIDs where images[clipID] == nil {
      guard let clip = package.clips[clipID] else {
        throw PackageValidationError.invalid("unknown clip \(clipID)")
      }
      let loaded = try clip.frames.indices.map { frameIndex in
        guard
          let url = package.frameURL(clipID: clipID, frameIndex: frameIndex),
          let image = NSImage(contentsOf: url)
        else {
          throw PackageValidationError.missing("\(clipID) frame \(frameIndex)")
        }
        image.cacheMode = .always
        return image
      }
      images[clipID] = loaded
      print("petsgraph preloaded clip=\(clipID) frames=\(loaded.count)")
    }
  }

  func image(clipID: String, frameIndex: Int) -> NSImage? {
    guard let clipImages = images[clipID], clipImages.indices.contains(frameIndex) else {
      return nil
    }
    return clipImages[frameIndex]
  }
}

@MainActor
final class PetWindowController {
  var onClipChanged: ((String) -> Void)?

  private let package: LoadedPetPackage
  private let timeline: PlaybackTimeline
  private let panel: PetPanel
  private let imageView: NSImageView
  private let imageCache: ClipImageCache
  private let startDelaySeconds: Double
  private let displayHeightPt: Double
  private let motionScale: Double
  private let startX: Double
  private let windowY: Double

  private var timer: Timer?
  private var playbackStartUptime: TimeInterval = 0
  private var currentSegmentIndex = -1

  init(
    package: LoadedPetPackage,
    requestedDisplayHeightPt: Double,
    startDelaySeconds: Double
  ) throws {
    self.package = package
    timeline = try PlaybackTimeline(
      clips: package.clips,
      sequence: package.demoSequence
    )
    guard let screen = NSScreen.main ?? NSScreen.screens.first else {
      throw PackageValidationError.invalid("no active macOS screen")
    }

    let visible = screen.visibleFrame
    let margin = 20.0
    let baseHeight = package.manifest.art.baseHeightPt
    let footprintFactor = 1 + timeline.finiteRootMotionXPt / baseHeight
    let maximumHeight = (visible.width - 2 * margin) / max(1, footprintFactor)
    displayHeightPt = max(80, min(requestedDisplayHeightPt, maximumHeight))
    motionScale = displayHeightPt / baseHeight
    self.startDelaySeconds = startDelaySeconds

    let travel = timeline.finiteRootMotionXPt * motionScale
    let footprint = displayHeightPt + travel
    startX = max(visible.minX + margin, visible.midX - footprint / 2)

    let canvasHeight = Double(package.manifest.art.canvasPx[1])
    let groundFromWindowBottom = (
      canvasHeight - package.manifest.art.groundYPx
    ) / canvasHeight * displayHeightPt
    windowY = visible.minY + 5 - groundFromWindowBottom

    panel = PetPanel(
      contentRect: NSRect(
        x: startX,
        y: windowY,
        width: displayHeightPt,
        height: displayHeightPt
      ),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false,
      screen: screen
    )
    panel.level = .floating
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.hidesOnDeactivate = false
    panel.ignoresMouseEvents = true
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

    imageView = NSImageView(frame: panel.contentView?.bounds ?? .zero)
    imageView.autoresizingMask = [.width, .height]
    imageView.imageScaling = .scaleAxesIndependently
    imageView.wantsLayer = true
    imageView.layer?.backgroundColor = NSColor.clear.cgColor
    panel.contentView = imageView
    imageCache = ClipImageCache(package: package)

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
  }

  func start() {
    do {
      try imageCache.prepare(clipIDs: timeline.clipIDsNear(segmentIndex: 0))
      render(timeline.sample(at: 0))
      panel.orderFrontRegardless()
      playbackStartUptime = ProcessInfo.processInfo.systemUptime + startDelaySeconds
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
    playbackStartUptime = ProcessInfo.processInfo.systemUptime + startDelaySeconds
    render(timeline.sample(at: 0))
    panel.orderFrontRegardless()
    print("petsgraph restarted")
  }

  func stop() {
    timer?.invalidate()
    timer = nil
    panel.orderOut(nil)
    panel.close()
  }

  @objc private func tick(_ timer: Timer) {
    let elapsed = max(
      0,
      ProcessInfo.processInfo.systemUptime - playbackStartUptime
    )
    render(timeline.sample(at: elapsed))
  }

  private func render(_ sample: TimelineSample) {
    if sample.segmentIndex != currentSegmentIndex {
      currentSegmentIndex = sample.segmentIndex
      do {
        try imageCache.prepare(
          clipIDs: timeline.clipIDsNear(segmentIndex: sample.segmentIndex)
        )
      } catch {
        fputs("petsgraph: \(error)\n", stderr)
        NSApplication.shared.terminate(nil)
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

    guard let image = imageCache.image(
      clipID: sample.clipID,
      frameIndex: sample.sourceFrameIndex
    ) else {
      return
    }
    if imageView.image !== image {
      imageView.image = image
    }
    panel.setFrameOrigin(
      NSPoint(
        x: startX + sample.rootMotionXPt * motionScale,
        y: windowY
      )
    )
  }
}
