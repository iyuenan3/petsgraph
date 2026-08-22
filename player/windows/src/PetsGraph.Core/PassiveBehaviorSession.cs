using System.Security.Cryptography;

namespace PetsGraph.Core;

public sealed record PetPlaybackPresentation(
    string ClipId,
    int FrameIndex,
    string CurrentNodeId,
    bool IsTransition,
    IReadOnlyList<string> PreloadClipIds);

public sealed class PassiveBehaviorSession
{
    private readonly LoadedPetPack package;
    private readonly IReadOnlyDictionary<string, PetGraphNode> nodes;
    private readonly IReadOnlyDictionary<string, PetGraphEdge[]> outgoing;
    private readonly PetGraphNode[] eligibleNodes;
    private SplitMix64 random;
    private string currentNodeId;
    private string currentClipId;
    private double segmentStartedAt;
    private double dwellDeadline;
    private readonly List<PetGraphEdge> pendingEdges = [];
    private double? scheduledExitAt;
    private bool hiddenRequested;
    private bool paused;
    private int frozenFrameIndex;

    public PassiveBehaviorSession(LoadedPetPack package, double startedAt, ulong? seed = null)
    {
        this.package = package;
        nodes = package.Graph.Nodes.ToDictionary(static node => node.Id, StringComparer.Ordinal);
        outgoing = package.Graph.Edges.GroupBy(static edge => edge.From)
            .ToDictionary(static group => group.Key,
                static group => group.OrderBy(static edge => edge.Id, StringComparer.Ordinal).ToArray(),
                StringComparer.Ordinal);
        eligibleNodes = package.Graph.Nodes.Where(static node => node.AutonomousEligible)
            .OrderBy(static node => node.Id, StringComparer.Ordinal).ToArray();
        currentNodeId = package.Manifest.Stage.DefaultNode;
        currentClipId = nodes[currentNodeId].LoopClip
            ?? throw Invalid("invalid_graph", "default node has no loop clip");
        segmentStartedAt = startedAt;
        var randomSeed = seed ?? SeedFromDigest(package.ArchiveSha256) ^ RandomSeed();
        random = new(randomSeed);
        dwellDeadline = startedAt + RandomDwell(currentNodeId);
    }

    public bool IsPaused => paused;
    public bool IsTransitioning => package.Clips[currentClipId].Type == "transition";
    public bool ShouldTickWhenHidden => hiddenRequested && !paused;
    public string CurrentStableNodeId => currentNodeId;

    public void SetVisible(bool visible, double now)
    {
        if (visible)
        {
            hiddenRequested = false;
            if (paused)
            {
                paused = false;
                segmentStartedAt = now;
                scheduledExitAt = null;
                pendingEdges.Clear();
                frozenFrameIndex = 0;
                dwellDeadline = now + RandomDwell(currentNodeId);
            }
            return;
        }
        _ = Update(now);
        hiddenRequested = true;
        if (!IsTransitioning)
        {
            PauseAtStableNode(now);
        }
    }

    public PetPlaybackPresentation Update(double now)
    {
        if (!double.IsFinite(now))
        {
            throw Invalid("invalid_time", "runtime time is not finite");
        }
        if (paused)
        {
            return Presentation(frozenFrameIndex);
        }
        AdvanceCompletedSegments(now);
        if (!IsTransitioning && !hiddenRequested)
        {
            if (pendingEdges.Count == 0 && now >= dwellDeadline)
            {
                PlanNextTarget(now);
            }
            if (scheduledExitAt is { } exitAt && now >= exitAt && pendingEdges.Count != 0)
            {
                var edge = pendingEdges[0];
                pendingEdges.RemoveAt(0);
                scheduledExitAt = null;
                currentClipId = edge.Clip;
                segmentStartedAt = exitAt;
                AdvanceCompletedSegments(now);
            }
        }
        var clip = package.Clips[currentClipId];
        var elapsed = Math.Max(0, now - segmentStartedAt);
        var rawFrame = (int)Math.Floor(elapsed * clip.FrameRate.FramesPerSecond);
        var frameIndex = clip.Type == "loop" ? rawFrame % clip.FrameCount : Math.Min(rawFrame, clip.FrameCount - 1);
        return Presentation(frameIndex);
    }

    private void AdvanceCompletedSegments(double now)
    {
        var safety = 0;
        while (IsTransitioning)
        {
            if (++safety > package.Graph.Edges.Length + 1)
            {
                throw Invalid("behavior_cycle", "transition advancement exceeded the graph budget");
            }
            var clip = package.Clips[currentClipId];
            var completedAt = segmentStartedAt + clip.DurationSeconds;
            if (now < completedAt)
            {
                return;
            }
            var edge = package.Graph.Edges.Single(item => item.Clip == clip.Id);
            currentNodeId = edge.To;
            var node = nodes[currentNodeId];
            if (node.Role == "gateway")
            {
                if (pendingEdges.Count == 0 || pendingEdges[0].From != node.Id)
                {
                    throw Invalid("invalid_graph", "transition path stopped at a gateway");
                }
                currentClipId = pendingEdges[0].Clip;
                pendingEdges.RemoveAt(0);
                segmentStartedAt = completedAt;
                continue;
            }
            currentClipId = node.LoopClip ?? throw Invalid("invalid_graph", "dwell node has no loop");
            segmentStartedAt = completedAt;
            if (hiddenRequested)
            {
                pendingEdges.Clear();
                scheduledExitAt = null;
                PauseAtStableNode(completedAt);
                return;
            }
            if (pendingEdges.Count != 0)
            {
                if (pendingEdges[0].From != node.Id)
                {
                    throw Invalid("invalid_graph", "planned path is discontinuous");
                }
                scheduledExitAt = NextSafeExit(completedAt, completedAt);
            }
            else
            {
                dwellDeadline = completedAt + RandomDwell(currentNodeId);
            }
            return;
        }
    }

    private void PlanNextTarget(double now)
    {
        if (eligibleNodes.Length <= 1)
        {
            dwellDeadline = now + RandomDwell(currentNodeId);
            return;
        }
        var candidates = eligibleNodes.Where(node =>
            !package.Behavior.Timing.AvoidImmediateRepeat || node.Id != currentNodeId).ToArray();
        var target = WeightedTarget(candidates);
        var path = ShortestPath(currentNodeId, target.Id);
        if (path.Count == 0)
        {
            throw Invalid("invalid_graph", "autonomous target has no transition path");
        }
        pendingEdges.AddRange(path);
        scheduledExitAt = NextSafeExit(segmentStartedAt, now);
    }

    private PetGraphNode WeightedTarget(IReadOnlyList<PetGraphNode> candidates)
    {
        var weighted = candidates.Select(node => (Node: node,
            Weight: package.Behavior.NodeWeights.GetValueOrDefault(node.Id, 1) *
                    package.Behavior.SceneWeights.GetValueOrDefault(node.Scene, 1))).ToArray();
        var total = weighted.Sum(static item => item.Weight);
        if (!double.IsFinite(total) || total <= 0)
        {
            throw Invalid("invalid_behavior", "autonomous target weights are invalid");
        }
        var selection = random.NextUnit() * total;
        foreach (var item in weighted)
        {
            selection -= item.Weight;
            if (selection < 0)
            {
                return item.Node;
            }
        }
        return weighted[^1].Node;
    }

    private IReadOnlyList<PetGraphEdge> ShortestPath(string source, string target)
    {
        var queue = new Queue<string>();
        queue.Enqueue(source);
        var visited = new HashSet<string>(StringComparer.Ordinal) { source };
        var predecessor = new Dictionary<string, PetGraphEdge>(StringComparer.Ordinal);
        while (queue.TryDequeue(out var current))
        {
            foreach (var edge in outgoing.GetValueOrDefault(current, []))
            {
                if (!visited.Add(edge.To))
                {
                    continue;
                }
                predecessor[edge.To] = edge;
                if (edge.To == target)
                {
                    var result = new List<PetGraphEdge>();
                    var cursor = target;
                    while (cursor != source)
                    {
                        var prior = predecessor[cursor];
                        result.Add(prior);
                        cursor = prior.From;
                    }
                    result.Reverse();
                    return result;
                }
                queue.Enqueue(edge.To);
            }
        }
        return [];
    }

    private double NextSafeExit(double loopStartedAt, double now)
    {
        var clip = package.Clips[currentClipId];
        if (clip.Type != "loop" || clip.SafeExitFrames.Length == 0)
        {
            throw Invalid("invalid_safe_exit", "current dwell loop has no safe exit");
        }
        var frameDuration = clip.FrameRate.Denominator / (double)clip.FrameRate.Numerator;
        var cycleDuration = clip.FrameCount * frameDuration;
        var elapsed = Math.Max(0, now - loopStartedAt);
        var firstCycle = Math.Max(0, (int)Math.Floor(elapsed / cycleDuration));
        for (var cycle = firstCycle; cycle <= firstCycle + 1; cycle++)
        {
            foreach (var frame in clip.SafeExitFrames)
            {
                var boundary = loopStartedAt + cycle * cycleDuration + (frame + 1) * frameDuration;
                if (boundary >= now - 0.0000001)
                {
                    return boundary;
                }
            }
        }
        throw Invalid("invalid_safe_exit", "could not schedule a safe loop exit");
    }

    private void PauseAtStableNode(double now)
    {
        paused = true;
        pendingEdges.Clear();
        scheduledExitAt = null;
        var clip = package.Clips[currentClipId];
        var elapsed = Math.Max(0, now - segmentStartedAt);
        frozenFrameIndex = (int)Math.Floor(elapsed * clip.FrameRate.FramesPerSecond) % clip.FrameCount;
    }

    private PetPlaybackPresentation Presentation(int frameIndex)
    {
        var preload = new HashSet<string>(StringComparer.Ordinal);
        if (pendingEdges.Count != 0)
        {
            preload.Add(pendingEdges[0].Clip);
            var finalNode = nodes[pendingEdges[^1].To];
            if (finalNode.LoopClip is { } loop)
            {
                preload.Add(loop);
            }
        }
        return new(currentClipId, frameIndex, currentNodeId, IsTransitioning,
            preload.Order(StringComparer.Ordinal).ToArray());
    }

    private double RandomDwell(string nodeId)
    {
        if (!package.Behavior.Timing.DwellRangesSeconds.TryGetValue(nodeId, out var range) ||
            range is not [var minimum, var maximum])
        {
            throw Invalid("invalid_behavior", "current node has no dwell range");
        }
        return minimum + (maximum - minimum) * random.NextUnit();
    }

    private static ulong RandomSeed()
    {
        Span<byte> bytes = stackalloc byte[8];
        RandomNumberGenerator.Fill(bytes);
        return BitConverter.ToUInt64(bytes);
    }

    private static ulong SeedFromDigest(string digest) =>
        ulong.TryParse(digest.AsSpan(0, 16), System.Globalization.NumberStyles.HexNumber,
            System.Globalization.CultureInfo.InvariantCulture, out var seed)
            ? seed
            : 0x5045545347524150;

    private static PetPackException Invalid(string code, string detail) => new(code, detail);

    private struct SplitMix64(ulong seed)
    {
        private ulong state = seed;

        public ulong Next()
        {
            state += 0x9e3779b97f4a7c15;
            var value = state;
            value = (value ^ (value >> 30)) * 0xbf58476d1ce4e5b9;
            value = (value ^ (value >> 27)) * 0x94d049bb133111eb;
            return value ^ (value >> 31);
        }

        public double NextUnit() => (Next() >> 11) / (double)(1UL << 53);
    }
}
