import Foundation

public struct TimelineSample: Equatable, Sendable {
  public let segmentIndex: Int
  public let clipID: String
  public let sourceFrameIndex: Int
  public let elapsedSeconds: TimeInterval
  public let rootMotionXPt: Double

  public init(
    segmentIndex: Int,
    clipID: String,
    sourceFrameIndex: Int,
    elapsedSeconds: TimeInterval,
    rootMotionXPt: Double
  ) {
    self.segmentIndex = segmentIndex
    self.clipID = clipID
    self.sourceFrameIndex = sourceFrameIndex
    self.elapsedSeconds = elapsedSeconds
    self.rootMotionXPt = rootMotionXPt
  }
}

public struct PlaybackTimeline: Sendable {
  private struct ResolvedFrame: Sendable {
    let sourceFrameIndex: Int
    let startSeconds: TimeInterval
    let durationSeconds: TimeInterval
    let startMotionX: Double
    let endMotionX: Double
  }

  private struct ResolvedSegment: Sendable {
    let clipID: String
    let startSeconds: TimeInterval
    let startMotionX: Double
    let durationSeconds: TimeInterval
    let terminalMotionX: Double
    let repeatForever: Bool
    let frames: [ResolvedFrame]
  }

  private let segments: [ResolvedSegment]

  public let finiteDurationSeconds: TimeInterval
  public let finiteRootMotionXPt: Double

  public init(
    clips: [String: ClipDefinition],
    sequence: DemoSequence
  ) throws {
    var resolved: [ResolvedSegment] = []
    var sequenceTime: TimeInterval = 0
    var sequenceMotion = 0.0

    for segment in sequence.segments {
      guard let clip = clips[segment.clip] else {
        throw PackageValidationError.invalid("timeline references unknown clip \(segment.clip)")
      }
      let built = try Self.buildSegment(
        clip: clip,
        segment: segment,
        sequenceStart: sequenceTime,
        motionStart: sequenceMotion
      )
      resolved.append(built)
      if !segment.repeatForever {
        sequenceTime += built.durationSeconds
        sequenceMotion += built.terminalMotionX
      }
    }

    segments = resolved
    finiteDurationSeconds = sequenceTime
    finiteRootMotionXPt = sequenceMotion
  }

  public func sample(at elapsedSeconds: TimeInterval) -> TimelineSample {
    let elapsed = max(0, elapsedSeconds)
    guard let index = segmentIndex(at: elapsed) else {
      let finalIndex = segments.count - 1
      let final = segments[finalIndex]
      let frame = final.frames.last!
      return TimelineSample(
        segmentIndex: finalIndex,
        clipID: final.clipID,
        sourceFrameIndex: frame.sourceFrameIndex,
        elapsedSeconds: elapsed,
        rootMotionXPt: final.startMotionX + final.terminalMotionX
      )
    }

    let segment = segments[index]
    var local = max(0, elapsed - segment.startSeconds)
    var repeatedMotion = 0.0
    if segment.repeatForever, segment.durationSeconds > 0 {
      let completedCycles = floor(local / segment.durationSeconds)
      repeatedMotion = completedCycles * segment.terminalMotionX
      local.formTruncatingRemainder(dividingBy: segment.durationSeconds)
    } else {
      local = min(local, segment.durationSeconds)
    }

    let frame = frame(in: segment, at: local)
    let frameElapsed = max(0, local - frame.startSeconds)
    let progress = min(1, frameElapsed / frame.durationSeconds)
    let localMotion = frame.startMotionX
      + (frame.endMotionX - frame.startMotionX) * progress
    return TimelineSample(
      segmentIndex: index,
      clipID: segment.clipID,
      sourceFrameIndex: frame.sourceFrameIndex,
      elapsedSeconds: elapsed,
      rootMotionXPt: segment.startMotionX + repeatedMotion + localMotion
    )
  }

  public func clipIDsNear(segmentIndex: Int, lookahead: Int = 2) -> [String] {
    guard segments.indices.contains(segmentIndex) else {
      return []
    }
    let end = min(segments.count - 1, segmentIndex + max(0, lookahead))
    var seen = Set<String>()
    return segments[segmentIndex...end].compactMap { segment in
      seen.insert(segment.clipID).inserted ? segment.clipID : nil
    }
  }

  private func segmentIndex(at elapsed: TimeInterval) -> Int? {
    for index in segments.indices {
      let segment = segments[index]
      if segment.repeatForever || elapsed < segment.startSeconds + segment.durationSeconds {
        return index
      }
    }
    return nil
  }

  private func frame(
    in segment: ResolvedSegment,
    at localTime: TimeInterval
  ) -> ResolvedFrame {
    if localTime >= segment.durationSeconds {
      return segment.frames.last!
    }
    var lower = 0
    var upper = segment.frames.count
    while lower < upper {
      let middle = (lower + upper) / 2
      let candidate = segment.frames[middle]
      if candidate.startSeconds + candidate.durationSeconds <= localTime {
        lower = middle + 1
      } else {
        upper = middle
      }
    }
    return segment.frames[min(lower, segment.frames.count - 1)]
  }

  private static func buildSegment(
    clip: ClipDefinition,
    segment: DemoSegment,
    sequenceStart: TimeInterval,
    motionStart: Double
  ) throws -> ResolvedSegment {
    let frameCount = clip.frames.count
    let oneCycleOrder = Array(segment.startFrame..<frameCount)
      + Array(0..<segment.startFrame)
    let order: [Int]
    if let requestedFrameCount = segment.frameCount {
      order = Array(oneCycleOrder.prefix(requestedFrameCount))
    } else {
      order = (0..<segment.cycles).flatMap { _ in oneCycleOrder }
    }

    var frames: [ResolvedFrame] = []
    var localTime: TimeInterval = 0
    var localMotion = 0.0
    for sourceIndex in order {
      let definition = clip.frames[sourceIndex]
      let duration = definition.durationMs / 1_000
      let startX = definition.rootMotionPt[0]
      let endX = sourceIndex + 1 < frameCount
        ? clip.frames[sourceIndex + 1].rootMotionPt[0]
        : clip.rootMotionEndPt[0]
      let delta = endX - startX
      guard delta >= -0.000_001 else {
        throw PackageValidationError.invalid("clip \(clip.id) has negative frame root motion")
      }
      frames.append(
        ResolvedFrame(
          sourceFrameIndex: sourceIndex,
          startSeconds: localTime,
          durationSeconds: duration,
          startMotionX: localMotion,
          endMotionX: localMotion + max(0, delta)
        )
      )
      localTime += duration
      localMotion += max(0, delta)
    }
    guard !frames.isEmpty else {
      throw PackageValidationError.invalid("clip \(clip.id) resolved to no frames")
    }

    return ResolvedSegment(
      clipID: clip.id,
      startSeconds: sequenceStart,
      startMotionX: motionStart,
      durationSeconds: localTime,
      terminalMotionX: localMotion,
      repeatForever: segment.repeatForever,
      frames: frames
    )
  }
}
