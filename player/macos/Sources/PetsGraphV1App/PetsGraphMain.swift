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

@main
enum PetsGraphMain {
  @MainActor private static var delegate: PlayerAppDelegate?
  @MainActor private static var instanceLock: SingleInstanceLock?

  @MainActor
  static func main() {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments.count == 2, arguments[0] == "--validate-only" {
      let source = URL(fileURLWithPath: arguments[1])
      let destination = FileManager.default.temporaryDirectory
        .appendingPathComponent("petsgraph-validate-\(UUID().uuidString)", isDirectory: true)
      do {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: destination) }
        let result = try PetPackValidator().validateAndExtract(sourceURL: source, to: destination)
        print(
          "valid package=\(result.report.packageID) version=\(result.report.contentVersion.stringValue) "
            + "clips=\(result.report.clipCount) sha256=\(result.report.archiveSHA256)"
        )
      } catch {
        fputs("PetsGraph: \(error)\n", stderr)
        exit(1)
      }
      return
    }
    guard arguments.isEmpty else {
      fputs("Usage: petsgraph [--validate-only package.petpack]\n", stderr)
      exit(2)
    }
    let lockPath = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("petsgraph-player-\(getuid()).lock")
      .path
    guard let lock = SingleInstanceLock(path: lockPath) else {
      fputs("PetsGraph is already running.\n", stderr)
      return
    }
    instanceLock = lock
    do {
      let application = NSApplication.shared
      let delegate = try PlayerAppDelegate.make()
      self.delegate = delegate
      application.delegate = delegate
      application.setActivationPolicy(.accessory)
      application.run()
    } catch {
      fputs("PetsGraph could not open its local pet library: \(error)\n", stderr)
      exit(1)
    }
  }
}
