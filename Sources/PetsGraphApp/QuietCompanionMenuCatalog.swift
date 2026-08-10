import Foundation
import PetsGraphCore

struct SleepPoseMenuOption: Equatable {
  let nodeID: String
  let displayName: String
  let scene: String
}

struct QuietCompanionMenuCatalog {
  let sleepPoses: [SleepPoseMenuOption]

  private let nodesByLoopClip: [String: GraphNode]
  private let targetNodesByEdgeClip: [String: GraphNode]

  init(graph: GraphDefinition) {
    let nodesByID = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0) })
    nodesByLoopClip = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.loopClip, $0) })
    targetNodesByEdgeClip = Dictionary(
      uniqueKeysWithValues: graph.edges.compactMap { edge in
        nodesByID[edge.to].map { (edge.clip, $0) }
      }
    )
    sleepPoses = graph.nodes.compactMap { node in
      guard
        node.role == "dwell",
        node.autonomousEligible == true,
        let scene = node.scene,
        let name = Self.usableName(node.displayName)
      else {
        return nil
      }
      return SleepPoseMenuOption(nodeID: node.id, displayName: name, scene: scene)
    }
  }

  func statusTitle(forClipID clipID: String) -> String {
    if let node = nodesByLoopClip[clipID] {
      let name = Self.usableName(node.displayName) ?? Self.fallbackName(for: node.role)
      return node.role == "dwell" ? "当前睡姿：\(name)" : "当前状态：\(name)"
    }
    if let target = targetNodesByEdgeClip[clipID] {
      let name = Self.usableName(target.displayName) ?? Self.fallbackName(for: target.role)
      return target.role == "interaction" ? "正在起身" : "正在切换到：\(name)"
    }
    return "动作进行中"
  }

  func activeSleepNodeID(forClipID clipID: String) -> String? {
    guard let node = nodesByLoopClip[clipID], node.role == "dwell" else {
      return nil
    }
    return node.id
  }

  private static func usableName(_ value: String?) -> String? {
    guard let name = value?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
      return nil
    }
    return name
  }

  private static func fallbackName(for role: String?) -> String {
    switch role {
    case "interaction": "坐好"
    case "gateway": "换姿准备"
    default: "睡眠姿态"
    }
  }
}
