namespace PetsGraph.Core;

public sealed record PetPackageManifest
{
    public string SchemaVersion { get; init; } = "";
    public PackageIdentity Package { get; init; } = new();
    public PetIdentity Pet { get; init; } = new();
    public ArtConfiguration Art { get; init; } = new();
    public RenderAssets RenderAssets { get; init; } = new();
    public string Graph { get; init; } = "";
    public string? Behavior { get; init; }
    public SceneDefinition[]? Scenes { get; init; }
    public string ReviewIndex { get; init; } = "";
    public string Integrity { get; init; } = "";
}

public sealed record PackageIdentity
{
    public string Id { get; init; } = "";
    public string Version { get; init; } = "";
    public string CreatedAt { get; init; } = "";
}

public sealed record PetIdentity
{
    public string Id { get; init; } = "";
    public string DisplayName { get; init; } = "";
    public string Species { get; init; } = "";
    public string IdentityStyle { get; init; } = "";
}

public sealed record ArtConfiguration
{
    public int[] CanvasPx { get; init; } = [];
    public double BaseHeightPt { get; init; }
    public string CoordinateOrigin { get; init; } = "";
    public string DefaultNode { get; init; } = "";
    public double GroundYPx { get; init; }
}

public sealed record RenderAssets
{
    public string Mode { get; init; } = "";
    public string PixelFormat { get; init; } = "";
    public EnvironmentProp[]? EnvironmentProps { get; init; }
}

public sealed record EnvironmentProp
{
    public string Id { get; init; } = "";
    public string Src { get; init; } = "";
    public double[] OffsetFromFloorOriginPt { get; init; } = [];
    public string Visibility { get; init; } = "";
    public string[]? Scenes { get; init; }
    public string Layer { get; init; } = "";
    public string HitTest { get; init; } = "";
}

public sealed record SceneDefinition
{
    public string Id { get; init; } = "";
    public string DisplayName { get; init; } = "";
    public int Order { get; init; }
}

public sealed record GraphDefinition
{
    public string SchemaVersion { get; init; } = "";
    public GraphNode[] Nodes { get; init; } = [];
    public GraphEdge[] Edges { get; init; } = [];
}

public sealed record GraphNode
{
    public string Id { get; init; } = "";
    public string? DisplayName { get; init; }
    public string Posture { get; init; } = "";
    public string Orientation { get; init; } = "";
    public bool Grounded { get; init; }
    public string Stability { get; init; } = "";
    public string? Scene { get; init; }
    public string? Role { get; init; }
    public bool? AutonomousEligible { get; init; }
    public string[]? Props { get; init; }
    public string LoopClip { get; init; } = "";
}

public sealed record GraphEdge
{
    public string Id { get; init; } = "";
    public string From { get; init; } = "";
    public string To { get; init; } = "";
    public string Clip { get; init; } = "";
    public string Kind { get; init; } = "";
    public string InterruptPolicy { get; init; } = "";
    public int? TargetStartFrame { get; init; }
    public string? SceneChange { get; init; }
}

public sealed record ClipDefinition
{
    public string SchemaVersion { get; init; } = "";
    public string Id { get; init; } = "";
    public string Type { get; init; } = "";
    public string Facing { get; init; } = "";
    public bool MirrorSafe { get; init; }
    public string EntryPose { get; init; } = "";
    public string ExitPose { get; init; } = "";
    public int[] SafeExitFrames { get; init; } = [];
    public string[] PreloadHints { get; init; } = [];
    public double[] RootMotionEndPt { get; init; } = [];
    public ClipFrame[] Frames { get; init; } = [];
    public ClipMedia? Media { get; init; }
}

public sealed record ClipMedia
{
    public string Type { get; init; } = "";
    public string Src { get; init; } = "";
    public string Codec { get; init; } = "";
    public string Container { get; init; } = "";
    public int FrameCount { get; init; }
    public double FrameRate { get; init; }
    public string AlphaMode { get; init; } = "";
    public string ColorSpace { get; init; } = "";
    public string SourceSequenceDigest { get; init; } = "";
    public string CompiledFrameSequenceDigest { get; init; } = "";
    public int[]? CropRectPx { get; init; }
    public int? BytesPerRow { get; init; }
    public int? FrameByteCount { get; init; }
}

public sealed record ClipFrame
{
    public string Src { get; init; } = "";
    public double DurationMs { get; init; }
    public double[] ContentBoundsPx { get; init; } = [];
    public double[]? PetBoundsPx { get; init; }
    public Dictionary<string, double[]>? PropBoundsPx { get; init; }
    public FrameAnchors AnchorsPx { get; init; } = new();
    public FrameCollision Collision { get; init; } = new();
    public double[] RootMotionPt { get; init; } = [];
    public double[]? PresentationOffsetPx { get; init; }
}

public sealed record FrameAnchors
{
    public double[] Root { get; init; } = [];
    public double[] Ground { get; init; } = [];
    public double[] Head { get; init; } = [];
}

public sealed record FrameCollision
{
    public double[] BodyCoreEllipsePx { get; init; } = [];
    public double[] ScreenBoundsPx { get; init; } = [];
    public double[]? PetHitEllipsePx { get; init; }
}

public sealed record BehaviorDefinition
{
    public string SchemaVersion { get; init; } = "";
    public string Profile { get; init; } = "";
    public string DefaultIntent { get; init; } = "";
    public BehaviorTiming Timing { get; init; } = new();
    public Dictionary<string, SceneBehaviorPolicy> ScenePolicy { get; init; } = [];
    public BehaviorInteractions Interactions { get; init; } = new();
}

public sealed record BehaviorTiming
{
    public string Strategy { get; init; } = "";
    public string ParametersStatus { get; init; } = "";
    public bool AvoidImmediateRepeat { get; init; }
    public double? MinimumDwellSeconds { get; init; }
    public double? MedianDwellSeconds { get; init; }
    public double? MaximumDwellSeconds { get; init; }
    public int? RecentHistoryLimit { get; init; }
    public double? SameSceneProbability { get; init; }
}

public sealed record SceneBehaviorPolicy
{
    public bool Sticky { get; init; }
    public string? Gateway { get; init; }
    public double? MinimumDwellSeconds { get; init; }
    public double? ExitCooldownSeconds { get; init; }
}

public sealed record BehaviorInteractions
{
    public PetClickBehavior PetClick { get; init; } = new();
    public string DesktopClick { get; init; } = "";
    public string Drag { get; init; } = "";
}

public sealed record PetClickBehavior
{
    public string Sleeping { get; init; } = "";
    public string Sitting { get; init; } = "";
    public double? DebounceSeconds { get; init; }
}

public sealed record DemoSequence
{
    public string SchemaVersion { get; init; } = "";
    public string Id { get; init; } = "";
    public DemoSegment[] Segments { get; init; } = [];
}

public sealed record DemoSegment
{
    public string Clip { get; init; } = "";
    public int StartFrame { get; init; }
    public int Cycles { get; init; } = 1;
    public int? FrameCount { get; init; }
    public bool RepeatForever { get; init; }
}

public sealed record IntegrityManifest
{
    public string SchemaVersion { get; init; } = "";
    public string Algorithm { get; init; } = "";
    public IntegrityEntry[] Files { get; init; } = [];
}

public sealed record IntegrityEntry
{
    public string Path { get; init; } = "";
    public long Bytes { get; init; }
    public string Sha256 { get; init; } = "";
}

public sealed record ReviewIndex
{
    public string SchemaVersion { get; init; } = "";
    public string RuntimeChainStatus { get; init; } = "";
    public bool Installable { get; init; }
    public string[] ApprovedRuntimeChains { get; init; } = [];
    public string[] RemainingRuntimeGates { get; init; } = [];
}

public sealed record LoadedPetPackage(
    string RootPath,
    PetPackageManifest Manifest,
    GraphDefinition Graph,
    BehaviorDefinition Behavior,
    IReadOnlyDictionary<string, ClipDefinition> Clips,
    DemoSequence DemoSequence);

public sealed class PetPackageValidationException(string message) : Exception(message);
