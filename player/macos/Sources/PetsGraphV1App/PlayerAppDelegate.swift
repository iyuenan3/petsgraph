import AppKit
import Foundation
import PetsGraphCore
import UniformTypeIdentifiers

@MainActor
final class PlayerAppDelegate: NSObject, NSApplicationDelegate {
  private let library: CanonicalPetLibrary
  private let stateStore: PlayerStateStore
  private var state: PlayerState
  private var packages: [String: LoadedPetPack]
  private var controllers: [String: PetWindowController] = [:]
  private var statusItem: NSStatusItem?

  static func make() throws -> PlayerAppDelegate {
    let library = try CanonicalPetLibrary()
    let loaded = try library.loadInstalledPetPacks()
    return PlayerAppDelegate(library: library, loaded: loaded)
  }

  private init(library: CanonicalPetLibrary, loaded: [LoadedPetPack]) {
    self.library = library
    packages = Dictionary(uniqueKeysWithValues: loaded.map { ($0.manifest.package.id, $0) })
    stateStore = PlayerStateStore(rootURL: library.rootURL)
    state = stateStore.load(for: loaded)
    super.init()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    makeStatusItem()
    for package in orderedPackages() { installController(for: package) }
    persistState()
    rebuildMenu()
  }

  func applicationWillTerminate(_ notification: Notification) {
    persistState()
    for controller in controllers.values { controller.dispose() }
    controllers.removeAll()
    statusItem = nil
  }

  @objc private func loadPetPacks() {
    let panel = NSOpenPanel()
    panel.title = "装载宠物包"
    panel.prompt = "装载"
    panel.allowsMultipleSelection = true
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    if let type = UTType(filenameExtension: "petpack") { panel.allowedContentTypes = [type] }
    guard panel.runModal() == .OK else { return }

    var messages: [String] = []
    for url in panel.urls {
      do {
        let outcome = try library.importPetPack(from: url) { current, proposed in
          let alert = NSAlert()
          alert.messageText = "更新 \(current.displayName)？"
          alert.informativeText =
            "将 \(current.contentVersion.stringValue) 更新为 \(proposed.contentVersion.stringValue)。位置和显示状态会保留。"
          alert.addButton(withTitle: "更新")
          alert.addButton(withTitle: "取消")
          return alert.runModal() == .alertFirstButtonReturn
        }
        switch outcome {
        case .installed(let pet): messages.append("已装载 \(pet.displayName)")
        case .updated(_, let pet): messages.append("已更新 \(pet.displayName)")
        case .alreadyInstalled(let pet): messages.append("\(pet.displayName) 已经装载")
        case .updateCancelled(_, let proposed): messages.append("已取消更新 \(proposed.displayName)")
        }
      } catch {
        messages.append("\(url.lastPathComponent)：\(friendly(error))")
      }
    }
    do {
      try reloadPackagesAndWindows()
    } catch {
      messages.append("重新读取内部宠物库失败：\(friendly(error))")
    }
    persistState()
    rebuildMenu()
    if !messages.isEmpty { showMessage("装载结果", messages.joined(separator: "\n")) }
  }

  @objc private func showPet(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String else { return }
    setVisible(true, packageID: id)
  }

  @objc private func hidePet(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String else { return }
    setVisible(false, packageID: id)
  }

  @objc private func showAllPets() {
    for id in controllers.keys { setVisible(true, packageID: id, persist: false) }
    persistState()
    rebuildMenu()
  }

  @objc private func hideAllPets() {
    for id in controllers.keys { setVisible(false, packageID: id, persist: false) }
    persistState()
    rebuildMenu()
  }

  @objc private func uninstallPet(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String,
      let package = packages[id],
      confirmUninstall(names: [package.manifest.pet.displayName])
    else { return }
    do {
      _ = try library.uninstall(packageID: id)
      controllers.removeValue(forKey: id)?.dispose()
      packages.removeValue(forKey: id)
      state.pets.removeValue(forKey: id)
      persistState()
      rebuildMenu()
    } catch { showMessage("卸载失败", friendly(error)) }
  }

  @objc private func uninstallAllPets() {
    let names = orderedPackages().map { $0.manifest.pet.displayName }
    guard !names.isEmpty, confirmUninstall(names: names) else { return }
    do {
      _ = try library.uninstallAll()
      for controller in controllers.values { controller.dispose() }
      controllers.removeAll()
      packages.removeAll()
      state.pets.removeAll()
      persistState()
      rebuildMenu()
    } catch { showMessage("卸载失败", friendly(error)) }
  }

  @objc private func selectScale(_ sender: NSMenuItem) {
    guard let number = sender.representedObject as? NSNumber else { return }
    let value = PlayerState.normalizedScale(number.doubleValue)
    state.globalScale = value
    for controller in controllers.values { controller.setScale(value) }
    persistState()
    rebuildMenu()
  }

  @objc private func quit() { NSApplication.shared.terminate(nil) }

  private func makeStatusItem() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    if let button = item.button {
      let image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "PetsGraph")
      image?.isTemplate = true
      button.image = image
      if image == nil { button.title = "PG" }
    }
    statusItem = item
    rebuildMenu()
  }

  private func rebuildMenu() {
    let menu = NSMenu(title: "PetsGraph")
    let load = NSMenuItem(title: "装载宠物包…", action: #selector(loadPetPacks), keyEquivalent: "o")
    load.target = self
    menu.addItem(load)
    menu.addItem(.separator())
    menu.addItem(visibilityMenu(title: "显示宠物", visible: true))
    menu.addItem(visibilityMenu(title: "隐藏宠物", visible: false))
    menu.addItem(uninstallMenu())
    menu.addItem(.separator())

    let sizeRoot = NSMenuItem(title: "大小", action: nil, keyEquivalent: "")
    let sizes = NSMenu(title: "大小")
    for value in PlayerState.allowedScales {
      let item = NSMenuItem(
        title: String(format: "%.2g×", value), action: #selector(selectScale(_:)), keyEquivalent: ""
      )
      item.target = self
      item.representedObject = NSNumber(value: value)
      item.state = abs(state.globalScale - value) < 0.000_001 ? .on : .off
      sizes.addItem(item)
    }
    sizeRoot.submenu = sizes
    menu.addItem(sizeRoot)
    menu.addItem(.separator())
    let quit = NSMenuItem(title: "退出 PetsGraph", action: #selector(quit), keyEquivalent: "q")
    quit.target = self
    menu.addItem(quit)
    statusItem?.menu = menu
  }

  private func visibilityMenu(title: String, visible: Bool) -> NSMenuItem {
    let root = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    let submenu = NSMenu(title: title)
    let all = NSMenuItem(
      title: "全部",
      action: visible ? #selector(showAllPets) : #selector(hideAllPets),
      keyEquivalent: ""
    )
    all.target = self
    all.isEnabled = controllers.values.contains { $0.petIsVisible != visible }
    submenu.addItem(all)
    if !packages.isEmpty { submenu.addItem(.separator()) }
    for package in orderedPackages() {
      let id = package.manifest.package.id
      let isVisible = controllers[id]?.petIsVisible == true
      let item = NSMenuItem(
        title: package.manifest.pet.displayName,
        action: visible ? #selector(showPet(_:)) : #selector(hidePet(_:)),
        keyEquivalent: ""
      )
      item.target = self
      item.representedObject = id
      item.isEnabled = isVisible != visible
      submenu.addItem(item)
    }
    root.submenu = submenu
    return root
  }

  private func uninstallMenu() -> NSMenuItem {
    let root = NSMenuItem(title: "卸载宠物", action: nil, keyEquivalent: "")
    let submenu = NSMenu(title: "卸载宠物")
    let all = NSMenuItem(title: "全部", action: #selector(uninstallAllPets), keyEquivalent: "")
    all.target = self
    all.isEnabled = !packages.isEmpty
    submenu.addItem(all)
    if !packages.isEmpty { submenu.addItem(.separator()) }
    for package in orderedPackages() {
      let item = NSMenuItem(
        title: package.manifest.pet.displayName,
        action: #selector(uninstallPet(_:)),
        keyEquivalent: ""
      )
      item.target = self
      item.representedObject = package.manifest.package.id
      submenu.addItem(item)
    }
    root.submenu = submenu
    return root
  }

  private func orderedPackages() -> [LoadedPetPack] {
    packages.values.sorted {
      let left = $0.manifest.pet.displayName.localizedStandardCompare($1.manifest.pet.displayName)
      if left == .orderedSame { return $0.manifest.package.id < $1.manifest.package.id }
      return left == .orderedAscending
    }
  }

  private func installController(for package: LoadedPetPack) {
    let id = package.manifest.package.id
    if controllers[id] != nil { return }
    var petState = state.pets[id] ?? PetPlayerState()
    let anchor =
      petState.savedAnchor.map { NSPoint(x: $0.x, y: $0.y) }
      ?? nextDefaultAnchor(for: package)
    do {
      let controller = try PetWindowController(
        package: package,
        scale: state.globalScale,
        anchor: anchor
      )
      controller.onAnchorChanged = { [weak self] anchor in
        guard let self else { return }
        var value = self.state.pets[id] ?? PetPlayerState()
        value.anchorX = anchor.x
        value.anchorY = anchor.y
        self.state.pets[id] = value
        self.persistState()
      }
      controller.onFault = { [weak self] error in
        guard let self else { return }
        self.setVisible(false, packageID: id)
        self.showMessage("宠物播放已暂停", "\(package.manifest.pet.displayName)：\(self.friendly(error))")
      }
      controllers[id] = controller
      petState.anchorX = anchor.x
      petState.anchorY = anchor.y
      state.pets[id] = petState
      if petState.visible { controller.show() } else { controller.hide() }
    } catch {
      showMessage("无法装载宠物", "\(package.manifest.pet.displayName)：\(friendly(error))")
    }
  }

  private func nextDefaultAnchor(for package: LoadedPetPack) -> NSPoint {
    let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1_440, height: 900)
    let canvas = package.manifest.stage.referenceCanvasPx
    let height = package.manifest.stage.baseDisplayHeight * state.globalScale
    let width = height * Double(canvas[0]) / Double(canvas[1])
    let right = controllers.values.map { $0.frame.maxX }.max() ?? screen.minX
    let proposedX = right + 12 + width / 2
    let x = proposedX + width / 2 <= screen.maxX ? proposedX : screen.minX + 12 + width / 2
    return NSPoint(x: x, y: screen.minY + 12)
  }

  private func reloadPackagesAndWindows() throws {
    let loaded = try library.loadInstalledPetPacks()
    let next = Dictionary(uniqueKeysWithValues: loaded.map { ($0.manifest.package.id, $0) })
    for id in controllers.keys where next[id] == nil {
      controllers.removeValue(forKey: id)?.dispose()
    }
    for package in loaded {
      let id = package.manifest.package.id
      if packages[id]?.manifest.package.contentVersion != package.manifest.package.contentVersion {
        controllers.removeValue(forKey: id)?.dispose()
      }
      packages[id] = package
      installController(for: package)
    }
    packages = next
  }

  private func setVisible(_ visible: Bool, packageID: String, persist: Bool = true) {
    guard let controller = controllers[packageID] else { return }
    if visible { controller.show() } else { controller.hide() }
    var value = state.pets[packageID] ?? PetPlayerState()
    value.visible = visible
    state.pets[packageID] = value
    if persist {
      persistState()
      rebuildMenu()
    }
  }

  private func confirmUninstall(names: [String]) -> Bool {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = names.count == 1 ? "卸载 \(names[0])？" : "卸载全部宠物？"
    alert.informativeText = "卸载会删除 PetsGraph 内部保存的宠物包、缓存、位置和显示状态。以后恢复必须重新提供原始 .petpack 文件。"
    alert.addButton(withTitle: "卸载")
    alert.addButton(withTitle: "取消")
    return alert.runModal() == .alertFirstButtonReturn
  }

  private func persistState() {
    do { try stateStore.save(state) } catch { fputs("PetsGraph settings: \(error)\n", stderr) }
  }

  private func showMessage(_ title: String, _ detail: String) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = detail
    alert.addButton(withTitle: "好")
    alert.runModal()
  }

  private func friendly(_ error: Error) -> String {
    if let error = error as? PetPackError { return error.detail }
    return "发生了无法完成的本地错误。"
  }
}
