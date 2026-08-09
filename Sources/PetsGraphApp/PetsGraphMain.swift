import AppKit
import Foundation
import PetsGraphCore

struct AppConfiguration {
  let packageURL: URL
  let displayHeightPt: Double
  let startDelaySeconds: Double
  let verifyIntegrity: Bool
  let validateOnly: Bool
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
        print("petsgraph validation passed")
        return
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

  private static func parseArguments(_ arguments: [String]) throws -> AppConfiguration {
    if arguments.contains("--help") || arguments.contains("-h") {
      print(
        "Usage: petsgraph <package.petsgraph-pet> "
          + "[--display-height <points>] [--start-delay <seconds>] "
          + "[--no-integrity] [--validate-only]"
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
      default:
        throw PackageValidationError.invalid("unknown argument \(arguments[index])")
      }
      index += 1
    }

    return AppConfiguration(
      packageURL: URL(fileURLWithPath: packagePath, isDirectory: true),
      displayHeightPt: displayHeight,
      startDelaySeconds: startDelay,
      verifyIntegrity: verifyIntegrity,
      validateOnly: validateOnly
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
        startDelaySeconds: configuration.startDelaySeconds
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
    menu.addItem(
      NSMenuItem(
        title: "重新播放当前预览链",
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
