namespace PetsGraph.Core;

public sealed record BehaviorPlan(
    DemoSequence Sequence,
    string FinalNodeId,
    double FiniteRootMotionPt,
    double MotionSign);

public sealed class QuietCompanionPlanner
{
    private readonly LoadedPetPackage package;
    private readonly IReadOnlyDictionary<string, GraphNode> nodes;
    private readonly IReadOnlyDictionary<string, GraphEdge[]> outgoingEdges;

    public string DefaultNodeId => package.Manifest.Art.DefaultNode;

    public QuietCompanionPlanner(LoadedPetPackage package)
    {
        if (package.Behavior.Profile != "quiet-sleep-companion")
        {
            throw Invalid("quiet companion behavior is unavailable");
        }
        this.package = package;
        nodes = package.Graph.Nodes.ToDictionary(node => node.Id, StringComparer.Ordinal);
        outgoingEdges = package.Graph.Edges.GroupBy(edge => edge.From, StringComparer.Ordinal)
            .ToDictionary(group => group.Key, group => group.OrderBy(edge => edge.Id, StringComparer.Ordinal).ToArray(), StringComparer.Ordinal);
        if (!nodes.TryGetValue(DefaultNodeId, out var defaultNode) || defaultNode.Role != "dwell")
        {
            throw Invalid("quiet companion default node must be a dwell node");
        }
    }

    public string? Scene(string nodeId) => nodes.GetValueOrDefault(nodeId)?.Scene;
    public string? Role(string nodeId) => nodes.GetValueOrDefault(nodeId)?.Role;

    public IReadOnlyList<GraphNode> AutonomousNodes(string? scene = null) => package.Graph.Nodes
        .Where(node => node.Role == "dwell" && node.AutonomousEligible == true && (scene is null || node.Scene == scene))
        .OrderBy(node => node.Id, StringComparer.Ordinal)
        .ToArray();

    public BehaviorPlan IdlePlan(string nodeId, int startFrame = 0)
    {
        var loop = LoopClip(nodeId);
        if (startFrame < 0 || startFrame >= loop.Frames.Length)
        {
            throw Invalid($"invalid idle start frame for {nodeId}");
        }
        return MakePlan($"quiet-idle-{nodeId}",
            [new DemoSegment { Clip = loop.Id, StartFrame = startFrame, Cycles = 1, RepeatForever = true }], nodeId);
    }

    public BehaviorPlan SleepChangePlan(string fromNodeId, string toNodeId, int currentFrame)
    {
        if (nodes.GetValueOrDefault(fromNodeId)?.Role != "dwell" ||
            nodes.GetValueOrDefault(toNodeId) is not { Role: "dwell", AutonomousEligible: true })
        {
            throw Invalid("quiet sleep changes require autonomous dwell nodes");
        }
        if (fromNodeId == toNodeId)
        {
            return IdlePlan(fromNodeId, currentFrame);
        }
        var sameScene = Scene(fromNodeId) == Scene(toNodeId);
        return PlanPath($"quiet-sleep-{fromNodeId}-to-{toNodeId}", fromNodeId, currentFrame,
            ShortestPath(fromNodeId, toNodeId, sameScene), toNodeId);
    }

    public BehaviorPlan WakeToSceneSitPlan(string fromSleepNodeId, int currentFrame)
    {
        if (nodes.GetValueOrDefault(fromSleepNodeId) is not { Role: "dwell", Scene: { } scene })
        {
            throw Invalid("wake request must start at a dwell node");
        }
        var interaction = package.Graph.Nodes.Where(node => node.Scene == scene && node.Role == "interaction").ToArray();
        if (interaction.Length != 1)
        {
            throw Invalid($"scene {scene} must have one interaction node");
        }
        var target = interaction[0].Id;
        return PlanPath($"quiet-wake-{fromSleepNodeId}-to-{target}", fromSleepNodeId, currentFrame,
            ShortestPath(fromSleepNodeId, target, false), target);
    }

    public BehaviorPlan ReturnToSceneSleepPlan(string fromInteractionNodeId, int currentFrame, string? preferredDwellNodeId)
    {
        if (nodes.GetValueOrDefault(fromInteractionNodeId) is not { Role: "interaction", Scene: { } scene })
        {
            throw Invalid("return request must start at an interaction node");
        }
        var candidates = AutonomousNodes(scene).Select(node => node.Id).ToList();
        if (preferredDwellNodeId is not null && Scene(preferredDwellNodeId) == scene)
        {
            candidates.Remove(preferredDwellNodeId);
            candidates.Insert(0, preferredDwellNodeId);
        }
        foreach (var target in candidates)
        {
            try
            {
                return PlanPath($"quiet-return-{fromInteractionNodeId}-to-{target}", fromInteractionNodeId, currentFrame,
                    ShortestPath(fromInteractionNodeId, target, false), target);
            }
            catch (PetPackageValidationException)
            {
            }
        }
        throw Invalid($"interaction {fromInteractionNodeId} cannot return to sleep");
    }

    private BehaviorPlan PlanPath(string id, string fromNodeId, int currentFrame, GraphEdge[] path, string finalNodeId)
    {
        if (path.Length == 0)
        {
            return IdlePlan(fromNodeId, currentFrame);
        }
        var segments = new List<DemoSegment> { LoopExitSegment(fromNodeId, currentFrame) };
        for (var index = 0; index < path.Length; index++)
        {
            var edge = path[index];
            segments.Add(new() { Clip = edge.Clip, StartFrame = 0, Cycles = 1 });
            var targetStart = edge.TargetStartFrame ?? 0;
            if (index == path.Length - 1)
            {
                segments.Add(new() { Clip = LoopClip(edge.To).Id, StartFrame = targetStart, Cycles = 1, RepeatForever = true });
            }
            else
            {
                segments.Add(LoopExitSegment(edge.To, targetStart));
            }
        }
        var movementDirections = path
            .Where(edge => package.Clips[edge.Clip].RootMotionEndPt[0] > 0.000001)
            .Select(edge => package.Clips[edge.Clip].Facing)
            .Distinct(StringComparer.Ordinal)
            .ToArray();
        if (movementDirections.Length > 1 || movementDirections.Any(direction => direction is not ("left" or "right")))
        {
            throw Invalid("one quiet plan cannot mix movement directions");
        }
        var motionSign = movementDirections.FirstOrDefault() == "left" ? -1 : 1;
        return MakePlan(id, [.. segments], finalNodeId, motionSign);
    }

    private BehaviorPlan MakePlan(string id, DemoSegment[] segments, string finalNodeId, double motionSign = 1)
    {
        var sequence = new DemoSequence { SchemaVersion = "0.4.0", Id = id, Segments = segments };
        var timeline = new PlaybackTimeline(package.Clips, sequence);
        return new(sequence, finalNodeId, timeline.FiniteRootMotionXPt, motionSign);
    }

    private ClipDefinition LoopClip(string nodeId)
    {
        if (!nodes.TryGetValue(nodeId, out var node) || !package.Clips.TryGetValue(node.LoopClip, out var clip) || clip.Type != "loop")
        {
            throw Invalid($"missing quiet behavior loop for node {nodeId}");
        }
        return clip;
    }

    private DemoSegment LoopExitSegment(string nodeId, int startFrame)
    {
        var loop = LoopClip(nodeId);
        if (startFrame < 0 || startFrame >= loop.Frames.Length)
        {
            throw Invalid($"invalid loop phase for {nodeId}");
        }
        var nearestDistance = loop.SafeExitFrames
            .Select(frame => (Frame: frame, Distance: (frame - startFrame + loop.Frames.Length) % loop.Frames.Length))
            .OrderBy(candidate => candidate.Distance)
            .ThenBy(candidate => candidate.Frame)
            .FirstOrDefault();
        return new()
        {
            Clip = loop.Id,
            StartFrame = startFrame,
            Cycles = 1,
            FrameCount = nearestDistance.Distance + 1,
        };
    }

    private GraphEdge[] ShortestPath(string start, string target, bool avoidGatewayIntermediates)
    {
        if (start == target)
        {
            return [];
        }
        var queue = new Queue<(string Node, GraphEdge[] Path)>();
        var visited = new HashSet<string>(StringComparer.Ordinal) { start };
        queue.Enqueue((start, []));
        while (queue.TryDequeue(out var current))
        {
            foreach (var edge in outgoingEdges.GetValueOrDefault(current.Node) ?? [])
            {
                if (visited.Contains(edge.To) ||
                    (edge.To != target && nodes[edge.To].Role == "interaction") ||
                    (avoidGatewayIntermediates && edge.To != target && nodes[edge.To].Role == "gateway"))
                {
                    continue;
                }
                var candidate = current.Path.Append(edge).ToArray();
                if (edge.To == target)
                {
                    return candidate;
                }
                visited.Add(edge.To);
                queue.Enqueue((edge.To, candidate));
            }
        }
        if (avoidGatewayIntermediates)
        {
            return ShortestPath(start, target, false);
        }
        throw Invalid($"no quiet behavior path from {start} to {target}");
    }

    private static PetPackageValidationException Invalid(string detail) =>
        new($"Invalid pet package: {detail}");
}
