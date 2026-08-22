using System.Globalization;
using System.Security.Cryptography;
using System.Text.RegularExpressions;

namespace PetsGraph.Core;

public sealed partial class PetPackValidator
{
    public const string FormatVersion = "1.0.0";
    public const string BaselineCapability = "cropped-rgba-clips";

    private readonly SafeZipArchive zipArchive = new();

    public ValidatedPetPack ValidateAndExtract(string sourcePath, string destinationRoot)
    {
        var index = zipArchive.Inspect(sourcePath);
        ValidateArchivePaths(index.Entries.Select(static entry => entry.Path));
        zipArchive.Extract(index, destinationRoot);
        var archiveSha256 = HashFile(index.ArchivePath);
        return LoadRuntime(destinationRoot, archiveSha256, index.ArchiveBytes,
            index.UncompressedBytes, index.Entries.Count);
    }

    public ValidatedPetPack LoadTrustedRuntime(string runtimeRoot, string archiveSha256, long archiveBytes)
    {
        ValidateSha256(archiveSha256, "archive digest");
        if (archiveBytes <= 0)
        {
            throw Invalid("archive_budget", "canonical archive size is invalid");
        }
        var files = EnumerateRuntimeFiles(runtimeRoot);
        return LoadRuntime(runtimeRoot, archiveSha256, archiveBytes,
            files.Sum(static file => new FileInfo(file.FullPath).Length), files.Count);
    }

    private static ValidatedPetPack LoadRuntime(string runtimeRoot, string archiveSha256,
        long archiveBytes, long uncompressedBytes, int entryCount)
    {
        var root = Path.GetFullPath(runtimeRoot);
        var runtimeFiles = EnumerateRuntimeFiles(root);
        var runtimePaths = runtimeFiles.Select(static file => file.RelativePath).ToHashSet(StringComparer.Ordinal);
        ValidateArchivePaths(runtimePaths);

        var manifest = Decode<PetPackManifest>(root, "manifest.json");
        var graph = Decode<PetGraph>(root, "graph.json");
        var behavior = Decode<PetBehavior>(root, "behavior.json");
        var integrity = Decode<PetPackIntegrity>(root, "integrity.json");
        ValidateManifest(manifest);
        ValidateIntegrity(root, integrity, runtimeFiles);

        var clipPaths = runtimePaths.Where(static path => path.StartsWith("clips/", StringComparison.Ordinal))
            .Order(StringComparer.Ordinal).ToArray();
        var clips = new Dictionary<string, PetClip>(StringComparer.Ordinal);
        foreach (var path in clipPaths)
        {
            var clip = Decode<PetClip>(root, path);
            ValidateClip(clip, path, manifest, runtimePaths, integrity);
            if (!clips.TryAdd(clip.Id, clip))
            {
                throw Invalid("duplicate_clip", "clip ids must be unique");
            }
        }
        ValidateGraph(graph, behavior, manifest, clips);

        var loaded = new LoadedPetPack(root, manifest, graph, behavior, clips, archiveSha256, archiveBytes);
        var report = new PetPackValidationReport(
            manifest.Package.Id,
            manifest.Pet.Id,
            manifest.Pet.DisplayName,
            manifest.Pet.Species,
            manifest.Package.ContentVersion,
            archiveSha256,
            archiveBytes,
            uncompressedBytes,
            entryCount,
            clips.Count,
            graph.Nodes.Length,
            graph.Edges.Length);
        return new(loaded, report);
    }

    private static void ValidateArchivePaths(IEnumerable<string> paths)
    {
        var values = paths.ToArray();
        var set = values.ToHashSet(StringComparer.Ordinal);
        if (set.Count != values.Length || !set.Contains("manifest.json") || !set.Contains("graph.json") ||
            !set.Contains("behavior.json") || !set.Contains("integrity.json") || set.Contains("signature.json"))
        {
            throw Invalid("archive_layout", "archive root files do not match PetPack 1.0");
        }
        foreach (var path in values)
        {
            SafeZipArchive.ValidatePath(path);
            var valid = path is "manifest.json" or "graph.json" or "behavior.json" or "integrity.json" ||
                (path.StartsWith("clips/", StringComparison.Ordinal) && path.EndsWith(".json", StringComparison.Ordinal) &&
                 path.Count(static character => character == '/') == 1) ||
                (path.StartsWith("media/", StringComparison.Ordinal) &&
                 path.EndsWith($"/{BaselineCapability}.rgba", StringComparison.Ordinal) &&
                 path.Count(static character => character == '/') == 2);
            if (!valid)
            {
                throw Invalid("archive_layout", "archive contains a path outside PetPack 1.0 layout");
            }
        }
    }

    private static void ValidateManifest(PetPackManifest manifest)
    {
        if (manifest.FormatVersion != FormatVersion || manifest.Graph != "graph.json" ||
            manifest.Behavior != "behavior.json" || manifest.Integrity != "integrity.json")
        {
            throw Invalid("unsupported_format", "manifest format or root references are unsupported");
        }
        ValidateIdentifier(manifest.Package.Id, PackageIdPattern(), 80, "package id");
        ValidateIdentifier(manifest.Pet.Id, PackageIdPattern(), 80, "pet id");
        if (manifest.Package.Id != manifest.Pet.Id || manifest.Pet.DisplayName.Length is < 1 or > 80 ||
            manifest.Pet.Species is not ("cat" or "dog") ||
            !TimestampPattern().IsMatch(manifest.Package.CreatedAt) ||
            !DateTimeOffset.TryParse(manifest.Package.CreatedAt, CultureInfo.InvariantCulture,
                DateTimeStyles.RoundtripKind, out _))
        {
            throw Invalid("invalid_identity", "manifest identity fields are invalid");
        }
        if (manifest.Stage.ReferenceCanvasPx is not [>= 1 and <= 16384, >= 1 and <= 16384] ||
            manifest.Stage.Anchor != "bottom-center" || !double.IsFinite(manifest.Stage.BaseDisplayHeight) ||
            manifest.Stage.BaseDisplayHeight is <= 0 or > 4096)
        {
            throw Invalid("invalid_stage", "manifest fixed stage is invalid");
        }
        ValidateIdentifier(manifest.Stage.DefaultNode, NodeIdPattern(), 120, "default node");
        if (!manifest.Capabilities.Required.SequenceEqual([BaselineCapability], StringComparer.Ordinal) ||
            manifest.Capabilities.Optional.Length != 0)
        {
            throw Invalid("unsupported_capability", "PetPack 1.0 requires exactly the RGBA baseline capability");
        }
    }

    private static void ValidateIntegrity(string root, PetPackIntegrity integrity,
        IReadOnlyList<RuntimeFile> runtimeFiles)
    {
        if (integrity.FormatVersion != FormatVersion || integrity.Algorithm != "sha256" ||
            integrity.Files.Length == 0)
        {
            throw Invalid("invalid_integrity", "integrity manifest header is invalid");
        }
        var declared = new Dictionary<string, IntegrityEntry>(StringComparer.Ordinal);
        foreach (var entry in integrity.Files)
        {
            SafeZipArchive.ValidatePath(entry.Path);
            ValidateSha256(entry.Sha256, "integrity digest");
            if (entry.Path == "integrity.json" || entry.Bytes < 0 || entry.MediaType.Length is < 1 or > 120 ||
                !declared.TryAdd(entry.Path, entry))
            {
                throw Invalid("invalid_integrity", "integrity entries are invalid or duplicated");
            }
        }
        var actual = runtimeFiles.Where(static file => file.RelativePath != "integrity.json")
            .ToDictionary(static file => file.RelativePath, StringComparer.Ordinal);
        if (!declared.Keys.ToHashSet(StringComparer.Ordinal).SetEquals(actual.Keys))
        {
            throw Invalid("integrity_coverage", "integrity does not exactly cover runtime files");
        }
        foreach (var pair in declared)
        {
            var file = actual[pair.Key];
            var info = new FileInfo(file.FullPath);
            if (info.Length != pair.Value.Bytes || !CryptographicOperations.FixedTimeEquals(
                    Convert.FromHexString(HashFile(file.FullPath)), Convert.FromHexString(pair.Value.Sha256)))
            {
                throw Invalid("integrity_mismatch", "runtime file integrity differs");
            }
        }
    }

    private static void ValidateClip(PetClip clip, string path, PetPackManifest manifest,
        IReadOnlySet<string> runtimePaths, PetPackIntegrity integrity)
    {
        if (clip.FormatVersion != FormatVersion)
        {
            throw Invalid("unsupported_format", "clip formatVersion is unsupported");
        }
        ValidateIdentifier(clip.Id, ClipIdPattern(), 160, "clip id");
        ValidateIdentifier(clip.EntryNode, NodeIdPattern(), 120, "clip entry node");
        ValidateIdentifier(clip.ExitNode, NodeIdPattern(), 120, "clip exit node");
        if (path != $"clips/{clip.Id}.json" ||
            (clip.Type == "loop" ? clip.EntryNode != clip.ExitNode :
                clip.Type == "transition" ? clip.EntryNode == clip.ExitNode : true))
        {
            throw Invalid("invalid_clip", "clip identity, type, or endpoints are inconsistent");
        }
        if (clip.FrameRate.Numerator is < 1 or > 1000 || clip.FrameRate.Denominator is < 1 or > 1000 ||
            clip.FrameCount < 1 || !double.IsFinite(clip.DurationSeconds) ||
            Math.Abs(clip.DurationSeconds - clip.FrameCount * clip.FrameRate.Denominator /
                (double)clip.FrameRate.Numerator) > 0.000001)
        {
            throw Invalid("invalid_duration", "clip duration does not match its frame contract");
        }
        if (!clip.SafeExitFrames.SequenceEqual(clip.SafeExitFrames.Distinct().Order()) ||
            clip.SafeExitFrames.Any(frame => frame < 0 || frame >= clip.FrameCount) ||
            (clip.Type == "loop" ? clip.SafeExitFrames.Length == 0 : clip.SafeExitFrames.Length != 0))
        {
            throw Invalid("invalid_safe_exit", "clip safe exits are invalid");
        }
        if (!clip.Stage.ReferenceCanvasPx.SequenceEqual(manifest.Stage.ReferenceCanvasPx) ||
            clip.Stage.Anchor != "bottom-center" || clip.Geometry.CropPx is not [var x, var y, var width, var height] ||
            clip.Geometry.PresentationOffsetPx is not [var offsetX, var offsetY] ||
            x < 0 || y < 0 || width < 1 || height < 1 ||
            x + width > manifest.Stage.ReferenceCanvasPx[0] || y + height > manifest.Stage.ReferenceCanvasPx[1] ||
            offsetX != x || offsetY != y)
        {
            throw Invalid("invalid_geometry", "clip fixed geometry is invalid");
        }
        if (!clip.Playback.NativeContinuousFrames || clip.Playback.Rate != 1 ||
            clip.Playback.SpeedProcessing != "none")
        {
            throw Invalid("invalid_playback", "clip must use native continuous frames at 1.0x");
        }
        ValidateSha256(clip.Production.RecipeDigest, "clip recipe digest");
        ValidateSha256(clip.Production.ApprovalDigest, "clip approval digest");
        if (clip.Representations is not [var representation])
        {
            throw Invalid("invalid_representation", "clip must have one baseline representation");
        }
        var expectedPath = $"media/{clip.Id}/{BaselineCapability}.rgba";
        long expectedBytes;
        try
        {
            expectedBytes = checked((long)width * 4 * height * clip.FrameCount);
        }
        catch (OverflowException exception)
        {
            throw new PetPackException("invalid_media_length", "clip media length overflows", exception);
        }
        if (representation.Id != BaselineCapability || representation.Kind != BaselineCapability ||
            representation.Path != expectedPath || representation.Encoding != "raw-premultiplied-rgba8" ||
            representation.WidthPx != width || representation.HeightPx != height ||
            representation.BytesPerRow != width * 4 || representation.FrameCount != clip.FrameCount ||
            representation.FrameRate.Numerator != clip.FrameRate.Numerator ||
            representation.FrameRate.Denominator != clip.FrameRate.Denominator ||
            representation.Alpha != "premultiplied" || representation.ColorSpace != "srgb" ||
            representation.Bytes != expectedBytes || !runtimePaths.Contains(expectedPath))
        {
            throw Invalid("invalid_representation", "clip baseline representation is invalid");
        }
        ValidateSha256(representation.Sha256, "clip representation digest");
        var integrityEntry = integrity.Files.SingleOrDefault(entry => entry.Path == expectedPath);
        if (integrityEntry is null || integrityEntry.Bytes != expectedBytes ||
            integrityEntry.Sha256 != representation.Sha256)
        {
            throw Invalid("invalid_media_length", "clip media and integrity declarations disagree");
        }
    }

    private static void ValidateGraph(PetGraph graph, PetBehavior behavior, PetPackManifest manifest,
        IReadOnlyDictionary<string, PetClip> clips)
    {
        if (graph.FormatVersion != FormatVersion || behavior.FormatVersion != FormatVersion ||
            behavior.Profile != "passive-memorial-companion" ||
            behavior.Timing.Strategy != "independent-random-dwell" || graph.Nodes.Length == 0)
        {
            throw Invalid("invalid_graph", "graph or behavior header is invalid");
        }
        var nodes = new Dictionary<string, PetGraphNode>(StringComparer.Ordinal);
        var referencedClips = new HashSet<string>(StringComparer.Ordinal);
        foreach (var node in graph.Nodes)
        {
            ValidateIdentifier(node.Id, NodeIdPattern(), 120, "node id");
            ValidateIdentifier(node.Scene, NodeIdPattern(), 120, "scene id");
            if (!nodes.TryAdd(node.Id, node) ||
                (node.Role == "dwell" ? node.LoopClip is null :
                    node.Role == "gateway" ? node.LoopClip is not null || node.AutonomousEligible : true))
            {
                throw Invalid("invalid_graph", "graph nodes are invalid or duplicated");
            }
            if (node.LoopClip is { } loop && !referencedClips.Add(loop))
            {
                throw Invalid("invalid_graph", "a loop clip is referenced more than once");
            }
        }
        var edges = new HashSet<string>(StringComparer.Ordinal);
        foreach (var edge in graph.Edges)
        {
            ValidateIdentifier(edge.Id, ClipIdPattern(), 160, "edge id");
            if (!edges.Add(edge.Id) || !nodes.ContainsKey(edge.From) || !nodes.ContainsKey(edge.To) ||
                edge.From == edge.To || edge.InterruptPolicy != "finish-before-retarget" ||
                !referencedClips.Add(edge.Clip))
            {
                throw Invalid("invalid_graph", "graph edges are invalid or duplicated");
            }
        }
        if (!referencedClips.SetEquals(clips.Keys))
        {
            throw Invalid("clip_coverage", "graph does not reference every clip exactly once");
        }
        foreach (var node in nodes.Values.Where(static node => node.LoopClip is not null))
        {
            var clip = clips[node.LoopClip!];
            if (clip.Type != "loop" || clip.EntryNode != node.Id || clip.ExitNode != node.Id)
            {
                throw Invalid("invalid_graph", "node loop clip endpoints are invalid");
            }
        }
        foreach (var edge in graph.Edges)
        {
            var clip = clips[edge.Clip];
            if (clip.Type != "transition" || clip.EntryNode != edge.From || clip.ExitNode != edge.To)
            {
                throw Invalid("invalid_graph", "edge clip endpoints are invalid");
            }
        }
        var eligible = nodes.Values.Where(static node => node.AutonomousEligible).Select(static node => node.Id)
            .ToHashSet(StringComparer.Ordinal);
        if (eligible.Count == 0 || manifest.Stage.DefaultNode != behavior.DefaultNode ||
            !eligible.Contains(manifest.Stage.DefaultNode) ||
            !eligible.SetEquals(behavior.Timing.DwellRangesSeconds.Keys) ||
            !eligible.SetEquals(behavior.NodeWeights.Keys))
        {
            throw Invalid("invalid_behavior", "autonomous behavior keys do not match eligible nodes");
        }
        var eligibleScenes = nodes.Values.Where(static node => node.AutonomousEligible)
            .Select(static node => node.Scene).ToHashSet(StringComparer.Ordinal);
        if (!eligibleScenes.SetEquals(behavior.SceneWeights.Keys))
        {
            throw Invalid("invalid_behavior", "scene weights do not match autonomous scenes");
        }
        foreach (var range in behavior.Timing.DwellRangesSeconds.Values)
        {
            if (range is not [var minimum, var maximum] || !double.IsFinite(minimum) ||
                !double.IsFinite(maximum) || minimum <= 0 || maximum < minimum)
            {
                throw Invalid("invalid_behavior", "dwell ranges are invalid");
            }
        }
        if (behavior.NodeWeights.Values.Concat(behavior.SceneWeights.Values)
            .Any(static value => !double.IsFinite(value) || value <= 0))
        {
            throw Invalid("invalid_behavior", "behavior weights are invalid");
        }
        foreach (var source in eligible)
        {
            var reachable = Reachable(source, graph.Edges);
            if (!eligible.IsSubsetOf(reachable))
            {
                throw Invalid("unreachable_graph", "autonomous nodes are not fully directed-reachable");
            }
        }
    }

    private static HashSet<string> Reachable(string source, IReadOnlyList<PetGraphEdge> edges)
    {
        var outgoing = edges.GroupBy(static edge => edge.From)
            .ToDictionary(static group => group.Key, static group => group.ToArray(), StringComparer.Ordinal);
        var visited = new HashSet<string>(StringComparer.Ordinal) { source };
        var queue = new Queue<string>();
        queue.Enqueue(source);
        while (queue.TryDequeue(out var node))
        {
            if (!outgoing.TryGetValue(node, out var next))
            {
                continue;
            }
            foreach (var edge in next)
            {
                if (visited.Add(edge.To))
                {
                    queue.Enqueue(edge.To);
                }
            }
        }
        return visited;
    }

    private static T Decode<T>(string root, string path)
    {
        var fullPath = SafeZipArchive.ResolveDestination(root, path);
        return StrictJson.DecodeFile<T>(fullPath, path);
    }

    private static IReadOnlyList<RuntimeFile> EnumerateRuntimeFiles(string runtimeRoot)
    {
        var root = Path.GetFullPath(runtimeRoot);
        if (!Directory.Exists(root) || (File.GetAttributes(root) & FileAttributes.ReparsePoint) != 0)
        {
            throw Invalid("runtime_missing", "runtime cache is missing or unsafe");
        }
        var files = new List<RuntimeFile>();
        var pending = new Stack<string>();
        pending.Push(root);
        while (pending.TryPop(out var directory))
        {
            foreach (var path in Directory.EnumerateFileSystemEntries(directory))
            {
                var attributes = File.GetAttributes(path);
                if ((attributes & FileAttributes.ReparsePoint) != 0)
                {
                    throw Invalid("unsafe_runtime", "runtime cache contains a reparse point");
                }
                if ((attributes & FileAttributes.Directory) != 0)
                {
                    pending.Push(path);
                    continue;
                }
                var relative = Path.GetRelativePath(root, path).Replace(Path.DirectorySeparatorChar, '/');
                SafeZipArchive.ValidatePath(relative);
                files.Add(new(relative, path));
            }
        }
        return files.OrderBy(static file => file.RelativePath, StringComparer.Ordinal).ToArray();
    }

    public static string HashFile(string path)
    {
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read,
            bufferSize: 1 << 20, FileOptions.SequentialScan);
        return Convert.ToHexStringLower(SHA256.HashData(stream));
    }

    private static void ValidateIdentifier(string value, Regex pattern, int maximumLength, string field)
    {
        if (value.Length is < 1 || value.Length > maximumLength || !pattern.IsMatch(value))
        {
            throw Invalid("invalid_identifier", $"{field} is invalid");
        }
    }

    private static void ValidateSha256(string value, string field)
    {
        if (!Sha256Pattern().IsMatch(value))
        {
            throw Invalid("invalid_digest", $"{field} is not lowercase SHA-256");
        }
    }

    private sealed record RuntimeFile(string RelativePath, string FullPath);

    private static PetPackException Invalid(string code, string detail) => new(code, detail);

    [GeneratedRegex("^[a-z0-9]+(?:-[a-z0-9]+)*$", RegexOptions.CultureInvariant)]
    private static partial Regex PackageIdPattern();

    [GeneratedRegex("^[a-z0-9]+(?:[.-][a-z0-9]+)*$", RegexOptions.CultureInvariant)]
    private static partial Regex NodeIdPattern();

    [GeneratedRegex("^[a-z0-9]+(?:-[a-z0-9]+)*$", RegexOptions.CultureInvariant)]
    private static partial Regex ClipIdPattern();

    [GeneratedRegex("^[0-9a-f]{64}$", RegexOptions.CultureInvariant)]
    private static partial Regex Sha256Pattern();

    [GeneratedRegex("T.*(?:Z|[+-][0-9]{2}:[0-9]{2})$", RegexOptions.CultureInvariant)]
    private static partial Regex TimestampPattern();
}
