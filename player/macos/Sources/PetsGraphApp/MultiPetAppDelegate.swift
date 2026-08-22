import AppKit
import Foundation
import PetsGraphCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private static let loadedPetIDsKey = "petsgraph.loaded-pet-ids.v1"
  private static let globalScaleKey = "petsgraph.global-scale.v1"
  private static let positionKeyPrefix = "petsgraph.pet-canvas-origin.v2."

  private let packages: [LoadedPetPackage]
  private let configuration: AppConfiguration
  private let defaults: UserDefaults
  private let catalogs: [String: QuietCompanionMenuCatalog]
  private var desiredLoadedPetIDs: Set<String>
  private var controllers: [String: PetWindowController] = [:]
  private var currentClipIDs: [String: String] = [:]
  private var globalScale: Double
  private var scheduler: Timer?
  private var statusItem: NSStatusItem?
  private var loadMenuItems: [String: NSMenuItem] = [:]
  private var statusMenuItems: [String: NSMenuItem] = [:]
  private var poseMenuItems: [String: [String: NSMenuItem]] = [:]
  private var scaleMenuItems: [Double: NSMenuItem] = [:]

  init(
    packages: [LoadedPetPackage],
    configuration: AppConfiguration,
    defaults: UserDefaults = .standard
  ) {
    let order = MultiPetRuntimePolicy.orderedPetIDs(packages.map { $0.manifest.pet.id })
    let orderByID = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
    let ordered = packages.sorted {
      orderByID[$0.manifest.pet.id, default: .max]
        < orderByID[$1.manifest.pet.id, default: .max]
    }
    self.packages = ordered
    self.configuration = configuration
    self.defaults = defaults
    catalogs = Dictionary(
      uniqueKeysWithValues: ordered.map {
        ($0.manifest.pet.id, QuietCompanionMenuCatalog(graph: $0.graph))
      }
    )
    let allIDs = Set(ordered.map { $0.manifest.pet.id })
    if configuration.engineeringBehaviorPreview {
      desiredLoadedPetIDs = allIDs
    } else {
      let saved = defaults.object(forKey: Self.loadedPetIDsKey) == nil
        ? nil
        : defaults.array(forKey: Self.loadedPetIDsKey) as? [String]
      desiredLoadedPetIDs = MultiPetRuntimePolicy.initialLoadedPetIDs(
        available: allIDs,
        saved: saved
      )
      if saved == nil {
        defaults.set(Array(allIDs).sorted(), forKey: Self.loadedPetIDsKey)
      }
    }
    let savedScale = defaults.double(forKey: Self.globalScaleKey)
    globalScale = MultiPetRuntimePolicy.normalizedScale(
      savedScale == 0 ? nil : savedScale
    )
    if savedScale == 0 {
      defaults.set(globalScale, forKey: Self.globalScaleKey)
    }
    super.init()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    makeStatusItem()
    for package in packages where desiredLoadedPetIDs.contains(package.manifest.pet.id) {
      load(package: package, useStartupRow: true)
    }
    rebuildMenu()
  }

  func applicationWillTerminate(_ notification: Notification) {
    for controller in controllers.values {
      controller.stop()
    }
    controllers.removeAll()
    scheduler?.invalidate()
    scheduler = nil
  }

  @objc private func togglePet(_ sender: NSMenuItem) {
    guard let petID = sender.representedObject as? String else { return }
    if controllers[petID] != nil {
      unload(petID: petID)
    } else if let package = package(petID: petID) {
      desiredLoadedPetIDs.insert(petID)
      persistLoadedPetIDs()
      load(package: package, useStartupRow: false)
    }
    rebuildMenu()
  }

  @objc private func loadAllPets() {
    desiredLoadedPetIDs = Set(packages.map { $0.manifest.pet.id })
    persistLoadedPetIDs()
    for package in packages where controllers[package.manifest.pet.id] == nil {
      load(package: package, useStartupRow: true)
    }
    rebuildMenu()
  }

  @objc private func hideAllPets() {
    for petID in Array(controllers.keys) {
      unload(petID: petID)
    }
    desiredLoadedPetIDs.removeAll()
    persistLoadedPetIDs()
    rebuildMenu()
  }

  @objc private func selectSleepPose(_ sender: NSMenuItem) {
    guard
      let values = sender.representedObject as? [String],
      values.count == 2,
      let controller = controllers[values[0]],
      let option = catalogs[values[0]]?.sleepPoses.first(where: { $0.nodeID == values[1] })
    else { return }
    _ = controller.selectSleepPose(nodeID: option.nodeID, displayName: option.displayName)
  }

  @objc private func selectGlobalScale(_ sender: NSMenuItem) {
    guard let number = sender.representedObject as? NSNumber else { return }
    let value = number.doubleValue
    guard MultiPetRuntimePolicy.allowedScales.contains(value) else { return }
    globalScale = value
    defaults.set(value, forKey: Self.globalScaleKey)
    for package in packages {
      controllers[package.manifest.pet.id]?.setDisplayHeight(
        package.manifest.art.baseHeightPt * value
      )
    }
    rebuildMenu()
  }

  @objc private func resetLoadedPetsToSleep() {
    for controller in controllers.values {
      controller.restart()
    }
  }

  @objc private func quit() {
    NSApplication.shared.terminate(nil)
  }

  private func load(package: LoadedPetPackage, useStartupRow: Bool) {
    let petID = package.manifest.pet.id
    guard controllers[petID] == nil else { return }
    do {
      let saved = savedOrigin(petID: petID)
      let rowX: Double? = saved == nil && useStartupRow
        ? MultiPetRuntimePolicy.nextStartupX(
          existingMaxX: controllers.values.map { $0.windowFrame.maxX }.max()
        )
        : nil
      let requestedHeight = configuration.displayHeightPt
        ?? package.manifest.art.baseHeightPt * globalScale
      let controller = try PetWindowController(
        package: package,
        requestedDisplayHeightPt: requestedHeight,
        startDelaySeconds: configuration.startDelaySeconds,
        initialOrigin: saved,
        initialX: rowX,
        engineeringBehaviorPreview: configuration.engineeringBehaviorPreview,
        acceleratedBehavior: configuration.acceleratedBehavior,
        nativeLeftChainDemo: configuration.nativeLeftChainDemo,
        quietSceneRoundTripDemo: configuration.quietSceneRoundTripDemo
      )
      controller.onClipChanged = { [weak self] clipID in
        self?.currentClipIDs[petID] = clipID
        self?.updatePetMenuPresentation(petID: petID)
      }
      controller.onPositionChanged = { [weak self] origin in
        self?.persist(origin: origin, petID: petID)
      }
      controllers[petID] = controller
      desiredLoadedPetIDs.insert(petID)
      persistLoadedPetIDs()
      try controller.start(scheduleTimer: false)
      ensureScheduler()
      print("petsgraph loaded pet=\(petID) independent-clock=yes")
    } catch {
      controllers.removeValue(forKey: petID)?.stop()
      desiredLoadedPetIDs.remove(petID)
      persistLoadedPetIDs()
      fputs("petsgraph could not load pet \(petID): \(error)\n", stderr)
    }
  }

  private func unload(petID: String) {
    if let controller = controllers.removeValue(forKey: petID) {
      persist(origin: controller.persistentOrigin, petID: petID)
      controller.stop()
    }
    currentClipIDs.removeValue(forKey: petID)
    desiredLoadedPetIDs.remove(petID)
    persistLoadedPetIDs()
    if controllers.isEmpty {
      scheduler?.invalidate()
      scheduler = nil
    }
    print("petsgraph unloaded pet=\(petID) resources=released")
  }

  private func makeStatusItem() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    item.button?.image = NSImage(
      systemSymbolName: "pawprint.fill",
      accessibilityDescription: "PetsGraph"
    )
    statusItem = item
  }

  private func ensureScheduler() {
    guard scheduler == nil else { return }
    let timer = Timer(
      timeInterval: 1.0 / 24.0,
      target: self,
      selector: #selector(tickScheduler(_:)),
      userInfo: nil,
      repeats: true
    )
    timer.tolerance = 1.0 / 240.0
    RunLoop.main.add(timer, forMode: .common)
    scheduler = timer
    print("petsgraph shared-render-scheduler=24hz independent-behavior-clocks=yes")
  }

  @objc private func tickScheduler(_ timer: Timer) {
    let now = ProcessInfo.processInfo.systemUptime
    for controller in controllers.values {
      controller.advance(at: now)
    }
  }

  private func rebuildMenu() {
    let menu = NSMenu()
    let heading = NSMenuItem(title: "PetsGraph 桌面宠物", action: nil, keyEquivalent: "")
    heading.isEnabled = false
    menu.addItem(heading)

    let loading = NSMenuItem(title: "装载宠物", action: nil, keyEquivalent: "")
    let loadingMenu = NSMenu(title: "装载宠物")
    loadMenuItems.removeAll()
    for package in packages {
      let petID = package.manifest.pet.id
      let item = NSMenuItem(
        title: package.manifest.pet.displayName,
        action: #selector(togglePet(_:)),
        keyEquivalent: ""
      )
      item.target = self
      item.representedObject = petID
      item.state = controllers[petID] == nil ? .off : .on
      loadingMenu.addItem(item)
      loadMenuItems[petID] = item
    }
    loadingMenu.addItem(.separator())
    let all = NSMenuItem(title: "全部装载", action: #selector(loadAllPets), keyEquivalent: "")
    all.target = self
    loadingMenu.addItem(all)
    let hide = NSMenuItem(title: "全部隐藏", action: #selector(hideAllPets), keyEquivalent: "")
    hide.target = self
    loadingMenu.addItem(hide)
    loading.submenu = loadingMenu
    menu.addItem(loading)

    menu.addItem(.separator())
    statusMenuItems.removeAll()
    poseMenuItems.removeAll()
    for package in packages {
      addPetMenu(package: package, to: menu)
    }

    menu.addItem(.separator())
    let size = NSMenuItem(title: "宠物大小", action: nil, keyEquivalent: "")
    let sizeMenu = NSMenu(title: "宠物大小")
    scaleMenuItems.removeAll()
    for value in MultiPetRuntimePolicy.allowedScales {
      let item = NSMenuItem(
        title: MultiPetRuntimePolicy.scaleTitle(value),
        action: #selector(selectGlobalScale(_:)),
        keyEquivalent: ""
      )
      item.target = self
      item.representedObject = NSNumber(value: value)
      item.state = value == globalScale ? .on : .off
      sizeMenu.addItem(item)
      scaleMenuItems[value] = item
    }
    size.submenu = sizeMenu
    menu.addItem(size)

    let reset = NSMenuItem(
      title: "全部回到默认睡姿",
      action: #selector(resetLoadedPetsToSleep),
      keyEquivalent: "r"
    )
    reset.target = self
    reset.isEnabled = !controllers.isEmpty
    menu.addItem(reset)
    menu.addItem(.separator())
    let quitItem = NSMenuItem(title: "退出 PetsGraph", action: #selector(quit), keyEquivalent: "q")
    quitItem.target = self
    menu.addItem(quitItem)
    statusItem?.menu = menu
  }

  private func addPetMenu(package: LoadedPetPackage, to menu: NSMenu) {
    let petID = package.manifest.pet.id
    let loaded = controllers[petID] != nil
    let root = NSMenuItem(title: package.manifest.pet.displayName, action: nil, keyEquivalent: "")
    let submenu = NSMenu(title: package.manifest.pet.displayName)
    let status = NSMenuItem(
      title: loaded ? "当前状态：准备中" : "未装载",
      action: nil,
      keyEquivalent: ""
    )
    status.isEnabled = false
    submenu.addItem(status)
    statusMenuItems[petID] = status
    submenu.addItem(.separator())

    var items: [String: NSMenuItem] = [:]
    let sceneDefinitions = scenes(for: package)
    for (sceneIndex, scene) in sceneDefinitions.enumerated() {
      if sceneIndex > 0 { submenu.addItem(.separator()) }
      let title = NSMenuItem(title: "\(scene.displayName)睡姿", action: nil, keyEquivalent: "")
      title.isEnabled = false
      submenu.addItem(title)
      for option in catalogs[petID]?.sleepPoses.filter({ $0.scene == scene.id }) ?? [] {
        let item = NSMenuItem(
          title: option.displayName,
          action: #selector(selectSleepPose(_:)),
          keyEquivalent: ""
        )
        item.target = self
        item.representedObject = [petID, option.nodeID]
        item.isEnabled = loaded
        submenu.addItem(item)
        items[option.nodeID] = item
      }
    }
    poseMenuItems[petID] = items
    root.submenu = submenu
    menu.addItem(root)
    updatePetMenuPresentation(petID: petID)
  }

  private func updatePetMenuPresentation(petID: String) {
    guard let status = statusMenuItems[petID] else { return }
    let loaded = controllers[petID] != nil
    let clipID = currentClipIDs[petID]
    status.title = loaded
      ? (clipID.map { catalogs[petID]?.statusTitle(forClipID: $0) ?? "当前状态：准备中" }
        ?? "当前状态：准备中")
      : "未装载"
    let activeNode = clipID.flatMap { catalogs[petID]?.activeSleepNodeID(forClipID: $0) }
    for (nodeID, item) in poseMenuItems[petID] ?? [:] {
      item.isEnabled = loaded
      item.state = nodeID == activeNode ? .on : .off
    }
    loadMenuItems[petID]?.state = loaded ? .on : .off
  }

  private func scenes(for package: LoadedPetPackage) -> [SceneDefinition] {
    if let scenes = package.manifest.scenes {
      return scenes.sorted { $0.order < $1.order }
    }
    let ids = Set(package.graph.nodes.compactMap(\.scene)).sorted()
    return ids.enumerated().map { index, id in
      let legacyName = ["floor": "地面", "pillow": "枕头"][id] ?? id
      return SceneDefinition(id: id, displayName: legacyName, order: index)
    }
  }

  private func package(petID: String) -> LoadedPetPackage? {
    packages.first { $0.manifest.pet.id == petID }
  }

  private func persistLoadedPetIDs() {
    defaults.set(Array(desiredLoadedPetIDs).sorted(), forKey: Self.loadedPetIDsKey)
  }

  private func persist(origin: NSPoint, petID: String) {
    defaults.set(
      ["x": origin.x, "y": origin.y],
      forKey: Self.positionKeyPrefix + petID
    )
  }

  private func savedOrigin(petID: String) -> NSPoint? {
    guard
      let value = defaults.dictionary(forKey: Self.positionKeyPrefix + petID),
      let x = value["x"] as? Double,
      let y = value["y"] as? Double,
      x.isFinite,
      y.isFinite
    else { return nil }
    return NSPoint(x: x, y: y)
  }

}
