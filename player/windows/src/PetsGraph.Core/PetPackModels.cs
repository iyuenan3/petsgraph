using System.Text.Json.Serialization;

namespace PetsGraph.Core;

public sealed record PetPackManifest
{
    public required string FormatVersion { get; init; }
    public required PackageIdentity Package { get; init; }
    public required PetIdentity Pet { get; init; }
    public required StageDefinition Stage { get; init; }
    public required CapabilityDeclaration Capabilities { get; init; }
    public required string Graph { get; init; }
    public required string Behavior { get; init; }
    public required string Integrity { get; init; }
}

public sealed record PackageIdentity
{
    public required string Id { get; init; }
    public required SemanticVersion ContentVersion { get; init; }
    public required string CreatedAt { get; init; }
}

public sealed record PetIdentity
{
    public required string Id { get; init; }
    public required string DisplayName { get; init; }
    public required string Species { get; init; }
}

public sealed record StageDefinition
{
    public required int[] ReferenceCanvasPx { get; init; }
    public required string Anchor { get; init; }
    public required double BaseDisplayHeight { get; init; }
    public required string DefaultNode { get; init; }
}

public sealed record CapabilityDeclaration
{
    public required string[] Required { get; init; }
    public required string[] Optional { get; init; }
}

public sealed record PetGraph
{
    public required string FormatVersion { get; init; }
    public required PetGraphNode[] Nodes { get; init; }
    public required PetGraphEdge[] Edges { get; init; }
}

public sealed record PetGraphNode
{
    public required string Id { get; init; }
    public required string Role { get; init; }
    public required string Scene { get; init; }
    public string? LoopClip { get; init; }
    public required bool AutonomousEligible { get; init; }
}

public sealed record PetGraphEdge
{
    public required string Id { get; init; }
    public required string From { get; init; }
    public required string To { get; init; }
    public required string Clip { get; init; }
    public required string InterruptPolicy { get; init; }
}

public sealed record PetBehavior
{
    public required string FormatVersion { get; init; }
    public required string Profile { get; init; }
    public required string DefaultNode { get; init; }
    public required BehaviorTiming Timing { get; init; }
    public required Dictionary<string, double> NodeWeights { get; init; }
    public required Dictionary<string, double> SceneWeights { get; init; }
}

public sealed record BehaviorTiming
{
    public required string Strategy { get; init; }
    public required Dictionary<string, double[]> DwellRangesSeconds { get; init; }
    public required bool AvoidImmediateRepeat { get; init; }
}

public sealed record PetClip
{
    public required string FormatVersion { get; init; }
    public required string Id { get; init; }
    public required string Type { get; init; }
    public required string EntryNode { get; init; }
    public required string ExitNode { get; init; }
    public required FrameRate FrameRate { get; init; }
    public required int FrameCount { get; init; }
    public required double DurationSeconds { get; init; }
    public required int[] SafeExitFrames { get; init; }
    public required ClipStage Stage { get; init; }
    public required ClipGeometry Geometry { get; init; }
    public required ClipPlayback Playback { get; init; }
    public required ClipProduction Production { get; init; }
    public required ClipRepresentation[] Representations { get; init; }
}

public sealed record FrameRate
{
    public required int Numerator { get; init; }
    public required int Denominator { get; init; }
    [JsonIgnore]
    public double FramesPerSecond => Numerator / (double)Denominator;
}

public sealed record ClipStage
{
    public required int[] ReferenceCanvasPx { get; init; }
    public required string Anchor { get; init; }
}

public sealed record ClipGeometry
{
    public required int[] CropPx { get; init; }
    public required int[] PresentationOffsetPx { get; init; }
}

public sealed record ClipPlayback
{
    public required bool NativeContinuousFrames { get; init; }
    public required double Rate { get; init; }
    public required string SpeedProcessing { get; init; }
}

public sealed record ClipProduction
{
    public required string RecipeDigest { get; init; }
    public required string ApprovalDigest { get; init; }
}

public sealed record ClipRepresentation
{
    public required string Id { get; init; }
    public required string Kind { get; init; }
    public required string Path { get; init; }
    public required string Encoding { get; init; }
    public required int WidthPx { get; init; }
    public required int HeightPx { get; init; }
    public required int BytesPerRow { get; init; }
    public required int FrameCount { get; init; }
    public required FrameRate FrameRate { get; init; }
    public required string Alpha { get; init; }
    public required string ColorSpace { get; init; }
    public required long Bytes { get; init; }
    public required string Sha256 { get; init; }
}

public sealed record PetPackIntegrity
{
    public required string FormatVersion { get; init; }
    public required string Algorithm { get; init; }
    public required IntegrityEntry[] Files { get; init; }
}

public sealed record IntegrityEntry
{
    public required string Path { get; init; }
    public required long Bytes { get; init; }
    public required string MediaType { get; init; }
    public required string Sha256 { get; init; }
}

public sealed record LoadedPetPack(
    string RuntimeRoot,
    PetPackManifest Manifest,
    PetGraph Graph,
    PetBehavior Behavior,
    IReadOnlyDictionary<string, PetClip> Clips,
    string ArchiveSha256,
    long ArchiveBytes)
{
    public string MediaPath(string clipId)
    {
        if (!Clips.TryGetValue(clipId, out var clip) || clip.Representations.Length != 1)
        {
            throw new PetPackException("missing_media", "clip has no baseline media");
        }
        return Path.Combine(RuntimeRoot, clip.Representations[0].Path.Replace('/', Path.DirectorySeparatorChar));
    }
}

public sealed record PetPackValidationReport(
    string PackageId,
    string PetId,
    string DisplayName,
    string Species,
    SemanticVersion ContentVersion,
    string ArchiveSha256,
    long ArchiveBytes,
    long UncompressedBytes,
    int EntryCount,
    int ClipCount,
    int NodeCount,
    int EdgeCount);

public sealed record ValidatedPetPack(LoadedPetPack Package, PetPackValidationReport Report);
