namespace PetsGraph.Core;

public readonly record struct TimelineSample(
    int SegmentIndex,
    string ClipId,
    int SourceFrameIndex,
    double ElapsedSeconds,
    double RootMotionXPt);

public sealed class PlaybackTimeline
{
    private sealed record ResolvedFrame(
        int SourceFrameIndex,
        double StartSeconds,
        double DurationSeconds,
        double StartMotionX,
        double EndMotionX);

    private sealed record ResolvedSegment(
        string ClipId,
        double StartSeconds,
        double StartMotionX,
        double DurationSeconds,
        double TerminalMotionX,
        bool RepeatForever,
        ResolvedFrame[] Frames);

    private readonly ResolvedSegment[] segments;

    public double FiniteDurationSeconds { get; }
    public double FiniteRootMotionXPt { get; }

    public PlaybackTimeline(IReadOnlyDictionary<string, ClipDefinition> clips, DemoSequence sequence)
    {
        var resolved = new List<ResolvedSegment>();
        var sequenceTime = 0.0;
        var sequenceMotion = 0.0;
        foreach (var segment in sequence.Segments)
        {
            if (!clips.TryGetValue(segment.Clip, out var clip))
            {
                throw Invalid($"timeline references unknown clip {segment.Clip}");
            }
            var built = BuildSegment(clip, segment, sequenceTime, sequenceMotion);
            resolved.Add(built);
            if (!segment.RepeatForever)
            {
                sequenceTime += built.DurationSeconds;
                sequenceMotion += built.TerminalMotionX;
            }
        }
        if (resolved.Count == 0)
        {
            throw Invalid("timeline contains no segments");
        }
        segments = [.. resolved];
        FiniteDurationSeconds = sequenceTime;
        FiniteRootMotionXPt = sequenceMotion;
    }

    public TimelineSample Sample(double elapsedSeconds)
    {
        var elapsed = Math.Max(0, elapsedSeconds);
        var index = SegmentIndex(elapsed);
        if (index < 0)
        {
            index = segments.Length - 1;
            var final = segments[index];
            var finalFrame = final.Frames[^1];
            return new(index, final.ClipId, finalFrame.SourceFrameIndex, elapsed,
                final.StartMotionX + final.TerminalMotionX);
        }

        var segment = segments[index];
        var local = Math.Max(0, elapsed - segment.StartSeconds);
        var repeatedMotion = 0.0;
        if (segment.RepeatForever && segment.DurationSeconds > 0)
        {
            var completedCycles = Math.Floor(local / segment.DurationSeconds);
            repeatedMotion = completedCycles * segment.TerminalMotionX;
            local %= segment.DurationSeconds;
        }
        else
        {
            local = Math.Min(local, segment.DurationSeconds);
        }

        var frame = FindFrame(segment, local);
        var progress = Math.Min(1, Math.Max(0, local - frame.StartSeconds) / frame.DurationSeconds);
        var localMotion = frame.StartMotionX + (frame.EndMotionX - frame.StartMotionX) * progress;
        return new(index, segment.ClipId, frame.SourceFrameIndex, elapsed,
            segment.StartMotionX + repeatedMotion + localMotion);
    }

    public IReadOnlyList<string> ClipIdsNear(int segmentIndex, int lookahead = 2)
    {
        if (segmentIndex < 0 || segmentIndex >= segments.Length)
        {
            return [];
        }
        var result = new List<string>();
        var seen = new HashSet<string>(StringComparer.Ordinal);
        var end = Math.Min(segments.Length - 1, segmentIndex + Math.Max(0, lookahead));
        for (var index = segmentIndex; index <= end; index++)
        {
            if (seen.Add(segments[index].ClipId))
            {
                result.Add(segments[index].ClipId);
            }
        }
        return result;
    }

    private int SegmentIndex(double elapsed)
    {
        for (var index = 0; index < segments.Length; index++)
        {
            var segment = segments[index];
            if (segment.RepeatForever || elapsed < segment.StartSeconds + segment.DurationSeconds)
            {
                return index;
            }
        }
        return -1;
    }

    private static ResolvedFrame FindFrame(ResolvedSegment segment, double localTime)
    {
        if (localTime >= segment.DurationSeconds)
        {
            return segment.Frames[^1];
        }
        var lower = 0;
        var upper = segment.Frames.Length;
        while (lower < upper)
        {
            var middle = (lower + upper) / 2;
            var candidate = segment.Frames[middle];
            if (candidate.StartSeconds + candidate.DurationSeconds <= localTime)
            {
                lower = middle + 1;
            }
            else
            {
                upper = middle;
            }
        }
        return segment.Frames[Math.Min(lower, segment.Frames.Length - 1)];
    }

    private static ResolvedSegment BuildSegment(
        ClipDefinition clip,
        DemoSegment segment,
        double sequenceStart,
        double motionStart)
    {
        if (segment.StartFrame < 0 || segment.StartFrame >= clip.Frames.Length || segment.Cycles <= 0)
        {
            throw Invalid($"clip {clip.Id} has an invalid segment range");
        }
        var oneCycle = Enumerable.Range(segment.StartFrame, clip.Frames.Length - segment.StartFrame)
            .Concat(Enumerable.Range(0, segment.StartFrame)).ToArray();
        var order = segment.FrameCount is { } count
            ? oneCycle.Take(count).ToArray()
            : Enumerable.Range(0, segment.Cycles).SelectMany(_ => oneCycle).ToArray();

        var frames = new List<ResolvedFrame>();
        var localTime = 0.0;
        var localMotion = 0.0;
        foreach (var sourceIndex in order)
        {
            var definition = clip.Frames[sourceIndex];
            var duration = definition.DurationMs / 1000.0;
            var startX = definition.RootMotionPt[0];
            var endX = sourceIndex + 1 < clip.Frames.Length
                ? clip.Frames[sourceIndex + 1].RootMotionPt[0]
                : clip.RootMotionEndPt[0];
            var delta = endX - startX;
            if (delta < -0.000001)
            {
                throw Invalid($"clip {clip.Id} has negative frame root motion");
            }
            frames.Add(new(sourceIndex, localTime, duration, localMotion, localMotion + Math.Max(0, delta)));
            localTime += duration;
            localMotion += Math.Max(0, delta);
        }
        if (frames.Count == 0)
        {
            throw Invalid($"clip {clip.Id} resolved to no frames");
        }
        return new(clip.Id, sequenceStart, motionStart, localTime, localMotion, segment.RepeatForever, [.. frames]);
    }

    private static PetPackageValidationException Invalid(string detail) =>
        new($"Invalid pet package: {detail}");
}
