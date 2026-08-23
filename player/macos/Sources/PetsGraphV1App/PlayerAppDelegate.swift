import AppKit
import Foundation
import PetsGraphCore
import UniformTypeIdentifiers

@MainActor
final class PlayerAppDelegate: NSObject, NSApplicationDelegate {
  private static let lastImportDirectoryKey = "PetsGraphLastImportDirectory"

  private let library: CanonicalPetLibrary
  private let stateStore: PlayerStateStore
  private var state: PlayerState
  private var packages: [String: LoadedPetPack]
  private var controllers: [String: PetWindowController] = [:]
  private var statusItem: NSStatusItem?
  private var settingsSaveAlertShown = false
  private var applicationFinishedLaunching = false
  private var pendingOpenURLs: [URL] = []

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
    for package in orderedPackages() {
      do {
        try installController(for: package)
      } catch {
        showMessage("无法装载宠物", "\(package.manifest.pet.displayName)：\(friendly(error))")
      }
    }
    persistState()
    rebuildMenu()
    if let warning = stateStore.loadWarning { showMessage("已安全隐藏全部宠物", warning) }
    applicationFinishedLaunching = true
    if !pendingOpenURLs.isEmpty {
      let urls = pendingOpenURLs
      pendingOpenURLs.removeAll()
      importPetPacks(from: urls)
    }
  }

  func application(_ application: NSApplication, open urls: [URL]) {
    guard applicationFinishedLaunching else {
      pendingOpenURLs.append(contentsOf: urls)
      return
    }
    application.activate(ignoringOtherApps: true)
    importPetPacks(from: urls)
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
    panel.message = "双击文件夹可继续进入；按 ⌘⇧G 可直接输入宠物包所在文件夹的路径。"
    panel.allowsMultipleSelection = true
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    if let type = UTType(filenameExtension: "petpack") { panel.allowedContentTypes = [type] }
    configureInitialImportDirectory(for: panel)
    guard panel.runModal() == .OK else { return }
    importPetPacks(from: panel.urls)
  }

  private func importPetPacks(from urls: [URL]) {
    rememberImportDirectory(for: urls)
    var messages: [String] = []
    for url in urls {
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
        let successMessage: String
        let obsolete: InstalledPet?
        switch outcome {
        case .installed(let pet):
          successMessage = "已装载 \(pet.displayName)"
          obsolete = nil
        case .updated(let previous, let pet):
          successMessage = "已更新 \(pet.displayName)"
          obsolete = previous
        case .alreadyInstalled(let pet):
          messages.append("\(pet.displayName) 已经装载")
          continue
        case .updateCancelled(_, let proposed):
          messages.append("已取消更新 \(proposed.displayName)")
          continue
        }
        do {
          try reloadPackagesAndWindows()
          try library.commitImport(outcome)
        } catch {
          let activationError = friendly(error)
          do {
            try library.rollbackImport(outcome)
            try reloadPackagesAndWindows()
            messages.append("\(url.lastPathComponent)：新版本无法播放，已恢复原有宠物。\(activationError)")
          } catch {
            messages.append(
              "\(url.lastPathComponent)：新版本无法播放，自动恢复也失败。\(activationError)；\(friendly(error))"
            )
          }
          continue
        }
        messages.append(successMessage)
        if let obsolete {
          do {
            try library.discardObsolete([obsolete])
          } catch {
            messages.append("\(url.lastPathComponent)：新版已启用，但旧版清理失败。\(friendly(error))")
          }
        }
      } catch {
        messages.append("\(url.lastPathComponent)：\(friendly(error))")
      }
    }
    persistState()
    rebuildMenu()
    if !messages.isEmpty { showMessage("装载结果", messages.joined(separator: "\n")) }
  }

  private func configureInitialImportDirectory(for panel: NSOpenPanel) {
    if let savedPath = UserDefaults.standard.string(forKey: Self.lastImportDirectoryKey) {
      let savedURL = URL(fileURLWithPath: savedPath, isDirectory: true).standardizedFileURL
      var isDirectory: ObjCBool = false
      if FileManager.default.fileExists(atPath: savedURL.path, isDirectory: &isDirectory),
        isDirectory.boolValue
      {
        panel.directoryURL = savedURL
        return
      }
    }
    panel.directoryURL =
      FileManager.default.urls(
        for: .downloadsDirectory,
        in: .userDomainMask
      ).first
  }

  private func rememberImportDirectory(for urls: [URL]) {
    guard let directory = urls.first?.deletingLastPathComponent().standardizedFileURL else {
      return
    }
    UserDefaults.standard.set(directory.path, forKey: Self.lastImportDirectoryKey)
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
    controllers.removeValue(forKey: id)?.dispose()
    do {
      _ = try library.uninstall(packageID: id)
      packages.removeValue(forKey: id)
      state.pets.removeValue(forKey: id)
      persistState()
      rebuildMenu()
    } catch {
      let uninstallError = friendly(error)
      do {
        try installController(for: package)
        showMessage("卸载失败", uninstallError)
      } catch {
        showMessage("卸载失败", "\(uninstallError)；恢复播放也失败：\(friendly(error))")
      }
    }
  }

  @objc private func uninstallAllPets() {
    let names = orderedPackages().map { $0.manifest.pet.displayName }
    guard !names.isEmpty, confirmUninstall(names: names) else { return }
    for controller in controllers.values { controller.dispose() }
    controllers.removeAll()
    do {
      _ = try library.uninstallAll()
      packages.removeAll()
      state.pets.removeAll()
      persistState()
      rebuildMenu()
    } catch {
      let uninstallError = friendly(error)
      var restoreErrors: [String] = []
      for package in orderedPackages() where controllers[package.manifest.package.id] == nil {
        do {
          try installController(for: package)
        } catch {
          restoreErrors.append("\(package.manifest.pet.displayName)：\(friendly(error))")
        }
      }
      let suffix = restoreErrors.isEmpty ? "" : "；恢复播放失败：\(restoreErrors.joined(separator: "；"))"
      showMessage("卸载失败", uninstallError + suffix)
    }
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
    menu.autoenablesItems = false
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
    sizes.autoenablesItems = false
    for option in PlayerState.scaleOptions {
      let value = option.value
      let item = NSMenuItem(
        title: "\(option.label)×", action: #selector(selectScale(_:)), keyEquivalent: ""
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
    submenu.autoenablesItems = false
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
      let controller = controllers[id]
      let isVisible = controller?.petIsVisible == true
      let item = NSMenuItem(
        title: controller == nil
          ? "\(package.manifest.pet.displayName)（播放不可用）"
          : package.manifest.pet.displayName,
        action: visible ? #selector(showPet(_:)) : #selector(hidePet(_:)),
        keyEquivalent: ""
      )
      item.target = self
      item.representedObject = id
      item.isEnabled = controller != nil && isVisible != visible
      submenu.addItem(item)
    }
    root.submenu = submenu
    return root
  }

  private func uninstallMenu() -> NSMenuItem {
    let root = NSMenuItem(title: "卸载宠物", action: nil, keyEquivalent: "")
    let submenu = NSMenu(title: "卸载宠物")
    submenu.autoenablesItems = false
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

  private func installController(for package: LoadedPetPack) throws {
    let id = package.manifest.package.id
    if controllers[id] != nil { return }
    var petState = state.pets[id] ?? PetPlayerState()
    let anchor =
      petState.savedAnchor.map { NSPoint(x: $0.x, y: $0.y) }
      ?? nextDefaultAnchor(for: package)
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
  }

  private func nextDefaultAnchor(for package: LoadedPetPack) -> NSPoint {
    let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1_440, height: 900)
    let canvas = package.manifest.stage.referenceCanvasPx
    let height = package.manifest.stage.baseDisplayHeight * state.globalScale
    let width = height * Double(canvas[0]) / Double(canvas[1])
    let occupied = controllers.values.map(\.frame)
    var y = screen.minY + 12
    while y + height <= screen.maxY {
      var x = screen.minX + 12
      while x + width <= screen.maxX {
        let candidate = NSRect(x: x, y: y, width: width, height: height)
        if occupied.allSatisfy({ !$0.intersects(candidate) }) {
          return NSPoint(x: candidate.midX, y: candidate.minY)
        }
        x += width + 12
      }
      y += height + 12
    }
    return NSPoint(x: screen.minX + 12 + width / 2, y: screen.minY + 12)
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
      try installController(for: package)
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
    for (id, controller) in controllers {
      state.captureRuntimePet(
        packageID: id,
        visible: controller.petIsVisible,
        anchorX: controller.anchor.x,
        anchorY: controller.anchor.y
      )
    }
    do {
      try stateStore.save(state)
      settingsSaveAlertShown = false
    } catch {
      fputs("PetsGraph settings: \(error)\n", stderr)
      if !settingsSaveAlertShown {
        settingsSaveAlertShown = true
        showMessage("无法保存设置", "本次显示、隐藏、大小或位置变化可能无法在下次启动时保留。")
      }
    }
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
