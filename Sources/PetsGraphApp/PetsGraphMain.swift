import AppKit
import Darwin
import Foundation
import PetsGraphCore

final class SingleInstanceLock {
  private let descriptor: Int32

  init?(path: String) {
    let descriptor = Darwin.open(path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else { return nil }
    guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
      Darwin.close(descriptor)
      return nil
    }
    self.descriptor = descriptor
  }

  deinit {
    flock(descriptor, LOCK_UN)
    Darwin.close(descriptor)
  }
}

struct AppConfiguration {
  let packageURL: URL
  let displayHeightPt: Double?
  let startDelaySeconds: Double
  let verifyIntegrity: Bool
  let validateOnly: Bool
  let validateMedia: Bool
  let engineeringBehaviorPreview: Bool
  let acceleratedBehavior: Bool
  let nativeLeftChainDemo: Bool
  let quietSceneRoundTripDemo: Bool
}

@main
struct PetsGraphMain {
  @MainActor private static var instanceLock: SingleInstanceLock?

  @MainActor
  static func main() {
    do {
      let configuration = try parseArguments(Array(CommandLine.arguments.dropFirst()))
      if !configuration.validateOnly, !configuration.validateMedia {
        let lockPath = URL(fileURLWithPath: NSTemporaryDirectory())
          .appendingPathComponent("petsgraph-runtime-\(getuid()).lock")
          .path
        guard let lock = SingleInstanceLock(path: lockPath) else {
          print("petsgraph another runtime instance is already active; exiting")
          return
        }
        instanceLock = lock
      }
      let started = ProcessInfo.processInfo.systemUptime
      let package = try PetPackageLoader().load(
        at: configuration.packageURL,
        verifyIntegrity: configuration.verifyIntegrity
      )
      let loadDuration = ProcessInfo.processInfo.systemUptime - started
      print(
        "petsgraph package=\(package.manifest.package.id) "
          + "clips=\(package.clips.count) verified=\(configuration.verifyIntegrity) "
          + String(format: "load=%.3fs", loadDuration)
      )
      if configuration.validateOnly {
        if package.behavior?.profile == "quiet-sleep-companion" {
          try validateQuietCompanionBehavior(package)
        } else if configuration.engineeringBehaviorPreview {
          try validateEngineeringBehavior(package)
        }
        print("petsgraph validation passed")
        return
      }
      if configuration.validateMedia {
        try validateRuntimeMedia(package)
        return
      }
      if configuration.engineeringBehaviorPreview {
        let nativeLeft = package.graph.nodes.contains {
          $0.id == "gait.walk.left.strict-side-low-tail"
        }
        print(
          "petsgraph ENGINEERING PREVIEW: native-left-locomotion="
            + (nativeLeft ? "yes" : "no")
            + "; this package remains non-installable until human desktop review"
        )
      }
      if package.behavior?.profile == "quiet-sleep-companion" {
        print("petsgraph quiet-sleep-companion enabled; desktop clicks and locomotion are disabled")
      }

      let application = NSApplication.shared
      let delegate = AppDelegate(
        package: package,
        configuration: configuration
      )
      application.delegate = delegate
      application.setActivationPolicy(.accessory)
      application.run()
      withExtendedLifetime(delegate) {}
    } catch {
      fputs("petsgraph: \(error)\n", stderr)
      exit(2)
    }
  }

  private static func validateEngineeringBehavior(
    _ package: LoadedPetPackage
  ) throws {
    let planner = try EngineeringBehaviorPlanner(package: package)
    let restNodes = package.graph.nodes
      .map(\.id)
      .filter { $0.hasPrefix("rest.") }
    var sleepPaths = 0
    for nodeID in restNodes {
      _ = try planner.idlePlan(nodeID: nodeID)
      for targetID in planner.sleepNeighborNodeIDs(from: nodeID) {
        let plan = try planner.sleepChangePlan(
          fromNodeID: nodeID,
          toNodeID: targetID,
          currentFrame: 0
        )
        guard abs(plan.finiteRootMotionPt) < 0.000_001 else {
          throw PackageValidationError.invalid(
            "sleep behavior path \(nodeID) to \(targetID) has root motion"
          )
        }
        sleepPaths += 1
      }
    }
    var activityPlans = 0
    for gait in [PreviewMovementGait.walk, .run] {
      for direction in [PreviewMovementDirection.left, .right] {
        _ = try planner.wakePlan(
          fromSleepNodeID: "rest.prone.left",
          currentFrame: 0,
          gait: gait,
          direction: direction
        )
        activityPlans += 1
        _ = try planner.sitMovementPlan(
          currentFrame: 0,
          gait: gait,
          direction: direction,
          walkCycles: 1,
          runCycles: 1
        )
        activityPlans += 1
        _ = try planner.sitMovementPlan(
          currentFrame: 0,
          gait: gait,
          direction: direction,
          walkCycles: 2,
          runCycles: 2
        )
        activityPlans += 1
      }
    }
    let nativeLeft = try planner.sitMovementPlan(
      currentFrame: 0,
      gait: .run,
      direction: .left,
      walkCycles: 1,
      runCycles: 1
    )
    guard nativeLeft.mirroredClipIDs.isEmpty else {
      throw PackageValidationError.invalid(
        "native left locomotion plan must not mirror any clip"
      )
    }
    _ = try planner.wakeToSitPlan(
      fromSleepNodeID: "rest.prone.left",
      currentFrame: 0
    )
    _ = try planner.sitToSleepPlan(currentFrame: 0)
    print(
      "petsgraph engineering-behavior validation "
        + "rest-nodes=\(restNodes.count) sleep-paths=\(sleepPaths) "
        + "activity-plans=\(activityPlans)"
    )
  }

  private static func validateQuietCompanionBehavior(
    _ package: LoadedPetPackage
  ) throws {
    let planner = try QuietCompanionPlanner(package: package)
    let dwellNodes = planner.autonomousNodeIDs()
    guard !dwellNodes.isEmpty else {
      throw PackageValidationError.invalid("quiet companion needs autonomous dwell nodes")
    }
    let interactionNodeIDs = Set(
      package.graph.nodes.filter { $0.role == "interaction" }.map(\.id)
    )
    func validateAutonomousPlan(_ plan: EngineeringBehaviorPlan) throws {
      guard plan.mirroredClipIDs.isEmpty else {
        throw PackageValidationError.invalid("quiet companion cannot mirror formal clips")
      }
      for segment in plan.sequence.segments {
        guard let clip = package.clips[segment.clip] else {
          throw PackageValidationError.missing("quiet plan clip \(segment.clip)")
        }
        if interactionNodeIDs.contains(clip.entryPose)
          || interactionNodeIDs.contains(clip.exitPose)
        {
          throw PackageValidationError.invalid(
            "autonomous quiet plan uses interaction clip \(clip.id)"
          )
        }
      }
    }
    var sleepPaths = 0
    var wakePaths = 0
    var returnPaths = 0
    for source in dwellNodes {
      _ = try planner.idlePlan(nodeID: source)
      let wake = try planner.wakeToSceneSitPlan(fromSleepNodeID: source, currentFrame: 0)
      guard abs(wake.finiteRootMotionPt) < 0.000_001 else {
        throw PackageValidationError.invalid("quiet wake path must have zero root motion")
      }
      guard
        planner.role(for: wake.finalNodeID) == "interaction",
        planner.scene(for: wake.finalNodeID) == planner.scene(for: source),
        wake.mirroredClipIDs.isEmpty
      else {
        throw PackageValidationError.invalid("quiet wake path must end at its scene interaction")
      }
      wakePaths += 1
      let returnPlan = try planner.returnToSceneSleepPlan(
        fromInteractionNodeID: wake.finalNodeID,
        currentFrame: 0,
        preferredDwellNodeID: source
      )
      guard
        returnPlan.finalNodeID == source,
        abs(returnPlan.finiteRootMotionPt) < 0.000_001,
        returnPlan.mirroredClipIDs.isEmpty
      else {
        throw PackageValidationError.invalid("quiet return path must restore its preferred dwell")
      }
      returnPaths += 1
      for target in dwellNodes where target != source {
        let plan = try planner.sleepChangePlan(
          fromNodeID: source,
          toNodeID: target,
          currentFrame: 0
        )
        let sameScene = planner.scene(for: source) == planner.scene(for: target)
        if sameScene, abs(plan.finiteRootMotionPt) >= 0.000_001 {
          throw PackageValidationError.invalid(
            "same-scene quiet path \(source) to \(target) has root motion"
          )
        }
        try validateAutonomousPlan(plan)
        if sameScene, plan.movementDirection != nil {
          throw PackageValidationError.invalid(
            "same-scene quiet path \(source) to \(target) cannot move the window"
          )
        }
        if !sameScene, plan.movementDirection == nil {
          throw PackageValidationError.invalid(
            "cross-scene quiet path \(source) to \(target) needs approved window motion"
          )
        }
        sleepPaths += 1
      }
    }
    print(
      "petsgraph quiet-companion validation "
        + "dwell-nodes=\(dwellNodes.count) sleep-paths=\(sleepPaths) "
        + "wake-paths=\(wakePaths) return-paths=\(returnPaths) "
        + "autonomous-interaction-shortcuts=0"
    )
  }

  @MainActor
  private static func validateRuntimeMedia(_ package: LoadedPetPackage) throws {
    guard ["hevc-alpha-clips", "cropped-rgba-clips"].contains(
      package.manifest.renderAssets.mode
    ) else {
      throw PackageValidationError.invalid(
        "--validate-media requires a compiled runtime media package"
      )
    }
    let started = ProcessInfo.processInfo.systemUptime
    let cache = ClipImageCache(package: package, createMirroredImages: false)
    var frameCount = 0
    for clipID in package.clips.keys.sorted() {
      guard let clip = package.clips[clipID] else { continue }
      try cache.prepare(clipIDs: [clipID])
      for frameIndex in clip.frames.indices {
        let decoded = try autoreleasepool {
          try cache.frame(clipID: clipID, frameIndex: frameIndex) != nil
        }
        guard decoded else {
          throw PackageValidationError.missing(
            "decoded runtime media frame \(clipID)/\(frameIndex)"
          )
        }
        frameCount += 1
      }
    }
    let elapsed = ProcessInfo.processInfo.systemUptime - started
    print(
      String(
        format: "petsgraph runtime media validation passed mode=%@ clips=%d frames=%d seconds=%.3f fps=%.1f",
        package.manifest.renderAssets.mode,
        package.clips.count,
        frameCount,
        elapsed,
        Double(frameCount) / elapsed
      )
    )
  }

  private static func parseArguments(_ arguments: [String]) throws -> AppConfiguration {
    if arguments.contains("--help") || arguments.contains("-h") {
      print(
        "Usage: petsgraph <package.petsgraph-pet> "
          + "[--display-height <points, defaults to package baseHeightPt>] "
          + "[--start-delay <seconds>] "
          + "[--no-integrity] [--validate-only] [--validate-media] "
          + "[--engineering-behavior-preview] [--accelerated-behavior] "
          + "[--native-left-chain-demo] [--quiet-scene-round-trip-demo]"
      )
      exit(0)
    }
    let packagePath: String
    let firstOptionIndex: Int
    if let supplied = arguments.first, !supplied.hasPrefix("--") {
      packagePath = supplied
      firstOptionIndex = 1
    } else if let bundled = Bundle.main.url(
      forResource: "DefaultPet",
      withExtension: "petsgraph-pet"
    ) {
      packagePath = bundled.path
      firstOptionIndex = 0
    } else {
      throw PackageValidationError.invalid(
        "a .petsgraph-pet directory is required, or DefaultPet.petsgraph-pet must be bundled"
      )
    }

    var displayHeight: Double?
    var startDelay = 1.0
    var verifyIntegrity = true
    var validateOnly = false
    var validateMedia = false
    var engineeringBehaviorPreview = false
    var acceleratedBehavior = false
    var nativeLeftChainDemo = false
    var quietSceneRoundTripDemo = false
    var index = firstOptionIndex
    while index < arguments.count {
      switch arguments[index] {
      case "--display-height":
        index += 1
        guard
          index < arguments.count,
          let value = Double(arguments[index]),
          value >= 80,
          value <= 320
        else {
          throw PackageValidationError.invalid("display height must be between 80 and 320 points")
        }
        displayHeight = value
      case "--start-delay":
        index += 1
        guard
          index < arguments.count,
          let value = Double(arguments[index]),
          value >= 0,
          value <= 10
        else {
          throw PackageValidationError.invalid("start delay must be between 0 and 10 seconds")
        }
        startDelay = value
      case "--no-integrity":
        verifyIntegrity = false
      case "--validate-only":
        validateOnly = true
      case "--validate-media":
        validateMedia = true
      case "--engineering-behavior-preview":
        engineeringBehaviorPreview = true
      case "--accelerated-behavior":
        acceleratedBehavior = true
      case "--native-left-chain-demo":
        nativeLeftChainDemo = true
      case "--quiet-scene-round-trip-demo":
        quietSceneRoundTripDemo = true
      default:
        throw PackageValidationError.invalid("unknown argument \(arguments[index])")
      }
      index += 1
    }
    guard !acceleratedBehavior || engineeringBehaviorPreview else {
      throw PackageValidationError.invalid(
        "accelerated behavior requires --engineering-behavior-preview"
      )
    }
    guard !nativeLeftChainDemo || engineeringBehaviorPreview else {
      throw PackageValidationError.invalid(
        "native left chain demo requires --engineering-behavior-preview"
      )
    }
    guard !quietSceneRoundTripDemo || engineeringBehaviorPreview else {
      throw PackageValidationError.invalid(
        "quiet scene round-trip demo requires --engineering-behavior-preview"
      )
    }
    guard !(nativeLeftChainDemo && quietSceneRoundTripDemo) else {
      throw PackageValidationError.invalid(
        "native left and quiet scene demos cannot run together"
      )
    }
    guard !(validateOnly && validateMedia) else {
      throw PackageValidationError.invalid(
        "validate-only and validate-media cannot run together"
      )
    }

    return AppConfiguration(
      packageURL: URL(fileURLWithPath: packagePath, isDirectory: true),
      displayHeightPt: displayHeight,
      startDelaySeconds: startDelay,
      verifyIntegrity: verifyIntegrity,
      validateOnly: validateOnly,
      validateMedia: validateMedia,
      engineeringBehaviorPreview: engineeringBehaviorPreview,
      acceleratedBehavior: acceleratedBehavior,
      nativeLeftChainDemo: nativeLeftChainDemo,
      quietSceneRoundTripDemo: quietSceneRoundTripDemo
    )
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let package: LoadedPetPackage
  private let configuration: AppConfiguration
  private let menuCatalog: QuietCompanionMenuCatalog
  private var petController: PetWindowController?
  private var statusItem: NSStatusItem?
  private var clipMenuItem: NSMenuItem?
  private var sleepPoseMenuItems: [String: NSMenuItem] = [:]

  init(package: LoadedPetPackage, configuration: AppConfiguration) {
    self.package = package
    self.configuration = configuration
    menuCatalog = QuietCompanionMenuCatalog(graph: package.graph)
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    do {
      let controller = try PetWindowController(
        package: package,
        requestedDisplayHeightPt: configuration.displayHeightPt
          ?? package.manifest.art.baseHeightPt,
        startDelaySeconds: configuration.startDelaySeconds,
        engineeringBehaviorPreview: configuration.engineeringBehaviorPreview,
        acceleratedBehavior: configuration.acceleratedBehavior,
        nativeLeftChainDemo: configuration.nativeLeftChainDemo,
        quietSceneRoundTripDemo: configuration.quietSceneRoundTripDemo
      )
      controller.onClipChanged = { [weak self] clipID in
        self?.updateMenuPresentation(clipID: clipID)
      }
      petController = controller
      makeStatusItem()
      controller.start()
    } catch {
      fputs("petsgraph: \(error)\n", stderr)
      NSApplication.shared.terminate(nil)
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    petController?.stop()
  }

  @objc private func restart() {
    petController?.restart()
  }

  @objc private func forceWalk() {
    petController?.forceWalk()
  }

  @objc private func forceRun() {
    petController?.forceRun()
  }

  @objc private func forceSleepChange() {
    petController?.forceSleepChange()
  }

  @objc private func selectSleepPose(_ sender: NSMenuItem) {
    guard
      let nodeID = sender.representedObject as? String,
      let option = menuCatalog.sleepPoses.first(where: { $0.nodeID == nodeID })
    else {
      return
    }
    _ = petController?.selectSleepPose(
      nodeID: option.nodeID,
      displayName: option.displayName
    )
  }

  @objc private func quit() {
    NSApplication.shared.terminate(nil)
  }

  private func makeStatusItem() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    item.button?.image = NSImage(
      systemSymbolName: "pawprint.fill",
      accessibilityDescription: "PetsGraph"
    )
    let menu = NSMenu()
    let pet = NSMenuItem(
      title: QuietCompanionMenuCatalog.petMenuTitle(
        displayName: package.manifest.pet.displayName
      ),
      action: nil,
      keyEquivalent: ""
    )
    pet.isEnabled = false
    menu.addItem(pet)
    let current = NSMenuItem(title: "当前状态：准备中", action: nil, keyEquivalent: "")
    current.isEnabled = false
    clipMenuItem = current
    menu.addItem(current)
    menu.addItem(.separator())
    if package.behavior?.profile == "quiet-sleep-companion" {
      let choosePose = NSMenuItem(title: "选择睡姿", action: nil, keyEquivalent: "")
      let poseMenu = NSMenu(title: "选择睡姿")
      addSleepPoseSection(scene: "floor", title: "地面睡姿", to: poseMenu)
      poseMenu.addItem(.separator())
      addSleepPoseSection(scene: "pillow", title: "枕头睡姿", to: poseMenu)
      choosePose.submenu = poseMenu
      menu.addItem(choosePose)
      menu.addItem(.separator())
    }
    if configuration.engineeringBehaviorPreview {
      menu.addItem(
        NSMenuItem(
          title: "工程预览：强制走路",
          action: #selector(forceWalk),
          keyEquivalent: "w"
        )
      )
      menu.addItem(
        NSMenuItem(
          title: "工程预览：强制跑步",
          action: #selector(forceRun),
          keyEquivalent: "f"
        )
      )
      menu.addItem(
        NSMenuItem(
          title: "工程预览：切换睡姿",
          action: #selector(forceSleepChange),
          keyEquivalent: "s"
        )
      )
      menu.addItem(.separator())
    }
    menu.addItem(
      NSMenuItem(
        title: configuration.engineeringBehaviorPreview
          ? "重置为睡眠"
          : (package.behavior == nil ? "重新播放当前预览链" : "回到默认睡姿"),
        action: #selector(restart),
        keyEquivalent: "r"
      )
    )
    menu.addItem(
      NSMenuItem(
        title: "退出 PetsGraph",
        action: #selector(quit),
        keyEquivalent: "q"
      )
    )
    for menuItem in menu.items where menuItem.action != nil {
      menuItem.target = self
    }
    item.menu = menu
    statusItem = item
  }

  private func addSleepPoseSection(scene: String, title: String, to menu: NSMenu) {
    let heading = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    heading.isEnabled = false
    menu.addItem(heading)
    for option in menuCatalog.sleepPoses where option.scene == scene {
      let menuItem = NSMenuItem(
        title: option.displayName,
        action: #selector(selectSleepPose(_:)),
        keyEquivalent: ""
      )
      menuItem.target = self
      menuItem.representedObject = option.nodeID
      menu.addItem(menuItem)
      sleepPoseMenuItems[option.nodeID] = menuItem
    }
  }

  private func updateMenuPresentation(clipID: String) {
    clipMenuItem?.title = menuCatalog.statusTitle(forClipID: clipID)
    let activeNodeID = menuCatalog.activeSleepNodeID(forClipID: clipID)
    for (nodeID, item) in sleepPoseMenuItems {
      item.state = nodeID == activeNodeID ? .on : .off
    }
  }
}
