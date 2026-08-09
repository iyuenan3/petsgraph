import AppKit
import Foundation
import PetsGraphCore

struct AppConfiguration {
  let packageURL: URL
  let displayHeightPt: Double
  let startDelaySeconds: Double
  let verifyIntegrity: Bool
  let validateOnly: Bool
  let engineeringBehaviorPreview: Bool
  let acceleratedBehavior: Bool
  let nativeLeftChainDemo: Bool
}

@main
struct PetsGraphMain {
  @MainActor
  static func main() {
    do {
      let configuration = try parseArguments(Array(CommandLine.arguments.dropFirst()))
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
        if configuration.engineeringBehaviorPreview {
          try validateEngineeringBehavior(package)
        }
        print("petsgraph validation passed")
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

  private static func parseArguments(_ arguments: [String]) throws -> AppConfiguration {
    if arguments.contains("--help") || arguments.contains("-h") {
      print(
        "Usage: petsgraph <package.petsgraph-pet> "
          + "[--display-height <points>] [--start-delay <seconds>] "
          + "[--no-integrity] [--validate-only] "
          + "[--engineering-behavior-preview] [--accelerated-behavior] "
          + "[--native-left-chain-demo]"
      )
      exit(0)
    }
    guard let packagePath = arguments.first, !packagePath.hasPrefix("--") else {
      throw PackageValidationError.invalid("a .petsgraph-pet directory is required")
    }

    var displayHeight = 150.0
    var startDelay = 1.0
    var verifyIntegrity = true
    var validateOnly = false
    var engineeringBehaviorPreview = false
    var acceleratedBehavior = false
    var nativeLeftChainDemo = false
    var index = 1
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
      case "--engineering-behavior-preview":
        engineeringBehaviorPreview = true
      case "--accelerated-behavior":
        acceleratedBehavior = true
      case "--native-left-chain-demo":
        nativeLeftChainDemo = true
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

    return AppConfiguration(
      packageURL: URL(fileURLWithPath: packagePath, isDirectory: true),
      displayHeightPt: displayHeight,
      startDelaySeconds: startDelay,
      verifyIntegrity: verifyIntegrity,
      validateOnly: validateOnly,
      engineeringBehaviorPreview: engineeringBehaviorPreview,
      acceleratedBehavior: acceleratedBehavior,
      nativeLeftChainDemo: nativeLeftChainDemo
    )
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let package: LoadedPetPackage
  private let configuration: AppConfiguration
  private var petController: PetWindowController?
  private var statusItem: NSStatusItem?
  private var clipMenuItem: NSMenuItem?

  init(package: LoadedPetPackage, configuration: AppConfiguration) {
    self.package = package
    self.configuration = configuration
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    do {
      let controller = try PetWindowController(
        package: package,
        requestedDisplayHeightPt: configuration.displayHeightPt,
        startDelaySeconds: configuration.startDelaySeconds,
        engineeringBehaviorPreview: configuration.engineeringBehaviorPreview,
        acceleratedBehavior: configuration.acceleratedBehavior,
        nativeLeftChainDemo: configuration.nativeLeftChainDemo
      )
      controller.onClipChanged = { [weak self] clipID in
        self?.clipMenuItem?.title = "当前：\(clipID)"
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

  @objc private func quit() {
    NSApplication.shared.terminate(nil)
  }

  private func makeStatusItem() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    item.button?.image = NSImage(
      systemSymbolName: "pawprint.fill",
      accessibilityDescription: "petsgraph"
    )
    let menu = NSMenu()
    let current = NSMenuItem(title: "当前：准备中", action: nil, keyEquivalent: "")
    current.isEnabled = false
    clipMenuItem = current
    menu.addItem(current)
    menu.addItem(.separator())
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
          : "重新播放当前预览链",
        action: #selector(restart),
        keyEquivalent: "r"
      )
    )
    menu.addItem(
      NSMenuItem(
        title: "退出 petsgraph",
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
}
