import Foundation

package struct RuntimeFrameCache<Value> {
  private let retainsAllFrames: Bool
  private var loopValues: [Int: Value] = [:]
  private var latestValue: (frameIndex: Int, value: Value)?

  package init(retainsAllFrames: Bool) {
    self.retainsAllFrames = retainsAllFrames
  }

  package func value(for frameIndex: Int) -> Value? {
    if retainsAllFrames { return loopValues[frameIndex] }
    guard latestValue?.frameIndex == frameIndex else { return nil }
    return latestValue?.value
  }

  package mutating func insert(_ value: Value, for frameIndex: Int) {
    if retainsAllFrames {
      loopValues[frameIndex] = value
    } else {
      latestValue = (frameIndex, value)
    }
  }

  package var retainedFrameIndices: Set<Int> {
    if retainsAllFrames { return Set(loopValues.keys) }
    return Set(latestValue.map { [$0.frameIndex] } ?? [])
  }
}

package enum SharedRenderCadence {
  package static func interval(for activeIntervals: some Sequence<TimeInterval>) -> TimeInterval? {
    activeIntervals.filter { $0.isFinite && $0 > 0 }.min()
  }
}
