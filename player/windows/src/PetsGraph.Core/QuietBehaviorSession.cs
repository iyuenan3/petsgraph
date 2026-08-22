namespace PetsGraph.Core;

public enum QuietInteractionState
{
    Sleeping,
    ChangingSleep,
    Waking,
    Sitting,
    ReturningToSleep,
}

public readonly record struct BehaviorPresentation(
    TimelineSample Sample,
    double TotalRootMotionXPt,
    QuietInteractionState State,
    IReadOnlyList<string> ClipIdsToPreload);

public enum PetClickResult
{
    WakeStarted,
    SleepStarted,
    Debounced,
    TransitionInProgress,
}

public sealed class QuietBehaviorSession
{
    private readonly LoadedPetPackage package;
    private readonly QuietCompanionPlanner planner;
    private readonly Random random;
    private readonly double clickDebounceSeconds;
    private readonly List<string> recentSleepNodeIds = [];
    private readonly Dictionary<string, double> lastSceneExitSeconds = new(StringComparer.Ordinal);

    private BehaviorPlan activePlan;
    private PlaybackTimeline timeline;
    private double planStartSeconds;
    private double nextSleepChangeSeconds = double.PositiveInfinity;
    private double lastClickSeconds = double.NegativeInfinity;
    private double currentSceneEnteredSeconds;
    private double accumulatedRootMotionXPt;
    private string currentNodeId;
    private string lastDwellNodeId;
    private string? requestedSleepNodeId;

    public QuietInteractionState State { get; private set; } = QuietInteractionState.Sleeping;
    public string CurrentNodeId => currentNodeId;

    public QuietBehaviorSession(LoadedPetPackage package, int? randomSeed = null)
    {
        this.package = package;
        planner = new(package);
        random = randomSeed is { } seed ? new Random(seed) : Random.Shared;
        clickDebounceSeconds = package.Behavior.Interactions.PetClick.DebounceSeconds ?? 0.35;
        currentNodeId = planner.DefaultNodeId;
        lastDwellNodeId = currentNodeId;
        activePlan = planner.IdlePlan(currentNodeId);
        timeline = new(package.Clips, activePlan.Sequence);
    }

    public void Start(double uptimeSeconds)
    {
        planStartSeconds = uptimeSeconds;
        currentSceneEnteredSeconds = uptimeSeconds;
        recentSleepNodeIds.Clear();
        recentSleepNodeIds.Add(currentNodeId);
        ScheduleNextSleepChange(uptimeSeconds);
    }

    public BehaviorPresentation Update(double uptimeSeconds)
    {
        FinishFinitePlanIfNeeded(uptimeSeconds);
        if (State == QuietInteractionState.Sleeping && uptimeSeconds >= nextSleepChangeSeconds)
        {
            BeginAutomaticSleepChange(uptimeSeconds);
        }
        var sample = timeline.Sample(uptimeSeconds - planStartSeconds);
        return new(
            sample,
            accumulatedRootMotionXPt + activePlan.MotionSign * sample.RootMotionXPt,
            State,
            timeline.ClipIdsNear(sample.SegmentIndex));
    }

    public PetClickResult HandlePetClick(double uptimeSeconds)
    {
        if (uptimeSeconds - lastClickSeconds < clickDebounceSeconds)
        {
            return PetClickResult.Debounced;
        }
        lastClickSeconds = uptimeSeconds;
        switch (State)
        {
            case QuietInteractionState.Sleeping:
                StartPlan(planner.WakeToSceneSitPlan(currentNodeId, CurrentFrame(uptimeSeconds)), QuietInteractionState.Waking, uptimeSeconds);
                return PetClickResult.WakeStarted;
            case QuietInteractionState.Sitting:
                StartPlan(planner.ReturnToSceneSleepPlan(currentNodeId, CurrentFrame(uptimeSeconds), requestedSleepNodeId ?? lastDwellNodeId),
                    QuietInteractionState.ReturningToSleep, uptimeSeconds);
                return PetClickResult.SleepStarted;
            default:
                return PetClickResult.TransitionInProgress;
        }
    }

    public bool SelectSleepPose(string nodeId, double uptimeSeconds)
    {
        if (!planner.AutonomousNodes().Any(node => node.Id == nodeId))
        {
            return false;
        }
        switch (State)
        {
            case QuietInteractionState.Sleeping:
                if (nodeId == currentNodeId)
                {
                    ScheduleNextSleepChange(uptimeSeconds);
                    return true;
                }
                StartPlan(planner.SleepChangePlan(currentNodeId, nodeId, CurrentFrame(uptimeSeconds)), QuietInteractionState.ChangingSleep, uptimeSeconds);
                return true;
            case QuietInteractionState.Sitting:
                requestedSleepNodeId = nodeId;
                StartPlan(planner.ReturnToSceneSleepPlan(currentNodeId, CurrentFrame(uptimeSeconds), nodeId),
                    QuietInteractionState.ReturningToSleep, uptimeSeconds);
                return true;
            case QuietInteractionState.ChangingSleep:
            case QuietInteractionState.Waking:
            case QuietInteractionState.ReturningToSleep:
                requestedSleepNodeId = nodeId;
                return true;
            default:
                return false;
        }
    }

    private void FinishFinitePlanIfNeeded(double uptimeSeconds)
    {
        if (State is QuietInteractionState.Sleeping or QuietInteractionState.Sitting ||
            uptimeSeconds - planStartSeconds < timeline.FiniteDurationSeconds)
        {
            return;
        }
        var previousNodeId = currentNodeId;
        accumulatedRootMotionXPt += activePlan.MotionSign * activePlan.FiniteRootMotionPt;
        currentNodeId = activePlan.FinalNodeId;
        if (planner.Role(currentNodeId) == "interaction")
        {
            State = QuietInteractionState.Sitting;
            StartIdleAt(uptimeSeconds);
            if (requestedSleepNodeId is { } queuedSleepNodeId)
            {
                requestedSleepNodeId = null;
                StartPlan(planner.ReturnToSceneSleepPlan(currentNodeId, 0, queuedSleepNodeId),
                    QuietInteractionState.ReturningToSleep, uptimeSeconds);
            }
            return;
        }

        State = QuietInteractionState.Sleeping;
        var previousScene = planner.Scene(previousNodeId);
        var currentScene = planner.Scene(currentNodeId);
        if (previousScene is not null && currentScene is not null && previousScene != currentScene)
        {
            lastSceneExitSeconds[previousScene] = uptimeSeconds;
            currentSceneEnteredSeconds = uptimeSeconds;
        }
        lastDwellNodeId = currentNodeId;
        RecordRecentSleepNode(currentNodeId);
        var queued = requestedSleepNodeId;
        requestedSleepNodeId = null;
        if (queued is not null && queued != currentNodeId)
        {
            StartPlan(planner.SleepChangePlan(currentNodeId, queued, 0), QuietInteractionState.ChangingSleep, uptimeSeconds);
            return;
        }
        StartIdleAt(uptimeSeconds);
        ScheduleNextSleepChange(uptimeSeconds);
    }

    private void BeginAutomaticSleepChange(double uptimeSeconds)
    {
        var currentScene = planner.Scene(currentNodeId);
        var all = planner.AutonomousNodes()
            .Where(node => IsAutonomousSceneEligible(currentScene, node.Scene, uptimeSeconds))
            .ToArray();
        var sameScene = all.Where(node => node.Scene == currentScene).ToArray();
        var useSameScene = random.NextDouble() < (package.Behavior.Timing.SameSceneProbability ?? 0.9);
        var pool = (useSameScene && sameScene.Length > 1 ? sameScene : all)
            .Where(node => node.Id != currentNodeId && !recentSleepNodeIds.Contains(node.Id, StringComparer.Ordinal))
            .ToArray();
        if (pool.Length == 0)
        {
            pool = all.Where(node => node.Id != currentNodeId).ToArray();
        }
        if (pool.Length == 0)
        {
            ScheduleNextSleepChange(uptimeSeconds);
            return;
        }
        var target = pool[random.Next(pool.Length)].Id;
        StartPlan(planner.SleepChangePlan(currentNodeId, target, CurrentFrame(uptimeSeconds)), QuietInteractionState.ChangingSleep, uptimeSeconds);
    }

    private void StartPlan(BehaviorPlan plan, QuietInteractionState state, double uptimeSeconds)
    {
        activePlan = plan;
        timeline = new(package.Clips, plan.Sequence);
        planStartSeconds = uptimeSeconds;
        State = state;
        nextSleepChangeSeconds = double.PositiveInfinity;
    }

    private void StartIdleAt(double uptimeSeconds)
    {
        activePlan = planner.IdlePlan(currentNodeId);
        timeline = new(package.Clips, activePlan.Sequence);
        planStartSeconds = uptimeSeconds;
    }

    private int CurrentFrame(double uptimeSeconds) => timeline.Sample(uptimeSeconds - planStartSeconds).SourceFrameIndex;

    private void ScheduleNextSleepChange(double uptimeSeconds)
    {
        var timing = package.Behavior.Timing;
        var minimum = timing.MinimumDwellSeconds ?? 180;
        var median = timing.MedianDwellSeconds ?? 480;
        var maximum = timing.MaximumDwellSeconds ?? 1800;
        var exponential = -Math.Log(Math.Max(double.Epsilon, 1 - random.NextDouble())) * median / Math.Log(2);
        nextSleepChangeSeconds = uptimeSeconds + Math.Clamp(exponential, minimum, maximum);
    }

    private void RecordRecentSleepNode(string nodeId)
    {
        recentSleepNodeIds.Remove(nodeId);
        recentSleepNodeIds.Add(nodeId);
        var limit = Math.Max(1, package.Behavior.Timing.RecentHistoryLimit ?? 2);
        while (recentSleepNodeIds.Count > limit)
        {
            recentSleepNodeIds.RemoveAt(0);
        }
    }

    private bool IsAutonomousSceneEligible(string? currentScene, string? targetScene, double uptimeSeconds)
    {
        if (currentScene is null || targetScene is null || currentScene == targetScene)
        {
            return true;
        }
        if (package.Behavior.ScenePolicy.TryGetValue(currentScene, out var currentPolicy) &&
            uptimeSeconds - currentSceneEnteredSeconds < (currentPolicy.MinimumDwellSeconds ?? 0))
        {
            return false;
        }
        if (package.Behavior.ScenePolicy.TryGetValue(targetScene, out var targetPolicy) &&
            lastSceneExitSeconds.TryGetValue(targetScene, out var exitedAt) &&
            uptimeSeconds - exitedAt < (targetPolicy.ExitCooldownSeconds ?? 0))
        {
            return false;
        }
        return true;
    }
}
