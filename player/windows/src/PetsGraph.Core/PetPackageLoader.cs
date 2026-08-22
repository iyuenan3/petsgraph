using System.Security.Cryptography;
using System.Text.Json;

namespace PetsGraph.Core;

public sealed class PetPackageLoader
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        ReadCommentHandling = JsonCommentHandling.Disallow,
    };

    public LoadedPetPackage Load(string packagePath, bool verifyIntegrity = false)
    {
        var root = Path.GetFullPath(packagePath);
        if (!Directory.Exists(root))
        {
            throw Invalid("package root must be a directory");
        }
        RejectReparsePoint(root, "package root");

        var manifest = Decode<PetPackageManifest>(root, "package.json");
        ValidateManifest(manifest);
        _ = ResolveRegularFile(root, manifest.Integrity);

        var review = Decode<ReviewIndex>(root, manifest.ReviewIndex);
        var runtimeChain = $"{manifest.Package.Id}-{manifest.Package.Version}";
        if (!review.Installable || review.RuntimeChainStatus != "runtime-chain-approved" ||
            review.RemainingRuntimeGates.Length != 0 ||
            !review.ApprovedRuntimeChains.Contains(runtimeChain, StringComparer.Ordinal))
        {
            throw Invalid("review index does not approve this runtime chain");
        }

        var graph = Decode<GraphDefinition>(root, manifest.Graph);
        var behavior = manifest.Behavior is null
            ? throw Invalid("schema 0.4 requires behavior.json")
            : Decode<BehaviorDefinition>(root, manifest.Behavior);
        var demo = Decode<DemoSequence>(root, "demo-sequence.json");

        ValidateGraphShape(graph, manifest);
        ValidateBehavior(behavior, graph);

        var clipIds = graph.Nodes.Select(node => node.LoopClip)
            .Concat(graph.Edges.Select(edge => edge.Clip))
            .Distinct(StringComparer.Ordinal)
            .Order(StringComparer.Ordinal)
            .ToArray();
        if (clipIds.Length == 0)
        {
            throw Invalid("graph contains no clip references");
        }

        var clips = new Dictionary<string, ClipDefinition>(StringComparer.Ordinal);
        foreach (var clipId in clipIds)
        {
            ValidateIdentifier(clipId, "clip id");
            var clip = Decode<ClipDefinition>(root, $"clips/{clipId}.json");
            if (clip.Id != clipId)
            {
                throw Invalid($"clip file {clipId}.json declares id {clip.Id}");
            }
            ValidateClip(root, manifest, clip);
            clips.Add(clipId, clip);
        }

        ValidateGraphLinks(graph, clips, manifest);
        ValidateDemo(demo, clips);
        ValidateEnvironmentProps(root, manifest, graph);

        if (verifyIntegrity)
        {
            VerifyIntegrity(root, manifest);
        }

        return new LoadedPetPackage(root, manifest, graph, behavior, clips, demo);
    }

    public static IEnumerable<string> FindPackages(string petsDirectory)
    {
        if (!Directory.Exists(petsDirectory))
        {
            return [];
        }
        return Directory.EnumerateDirectories(petsDirectory, "*.petsgraph-pet", SearchOption.TopDirectoryOnly)
            .Order(StringComparer.OrdinalIgnoreCase);
    }

    private static void ValidateManifest(PetPackageManifest manifest)
    {
        if (!Version.TryParse(manifest.SchemaVersion, out var version) || version.Major != 0 || version.Minor != 4)
        {
            throw Invalid($"unsupported schema {manifest.SchemaVersion}");
        }
        if (manifest.RenderAssets.Mode != "cropped-rgba-clips" ||
            manifest.RenderAssets.PixelFormat != "rgba8-premultiplied")
        {
            throw Invalid("Windows v0.6 requires cropped premultiplied RGBA clips");
        }
        if (manifest.Art.CanvasPx is not [> 0, > 0] ||
            manifest.Art.BaseHeightPt <= 0 ||
            manifest.Art.CoordinateOrigin != "top-left")
        {
            throw Invalid("invalid art coordinate contract");
        }
        ValidateIdentifier(manifest.Package.Id, "package id");
        ValidateIdentifier(manifest.Pet.Id, "pet id");
        if (string.IsNullOrWhiteSpace(manifest.Pet.DisplayName))
        {
            throw Invalid("pet display name is empty");
        }
    }

    private static void ValidateGraphShape(GraphDefinition graph, PetPackageManifest manifest)
    {
        if (graph.Nodes.Length == 0 || graph.Nodes.Select(node => node.Id).Distinct(StringComparer.Ordinal).Count() != graph.Nodes.Length)
        {
            throw Invalid("graph nodes must be non-empty and unique");
        }
        if (graph.Edges.Select(edge => edge.Id).Distinct(StringComparer.Ordinal).Count() != graph.Edges.Length)
        {
            throw Invalid("graph edge ids must be unique");
        }
        if (!graph.Nodes.Any(node => node.Id == manifest.Art.DefaultNode && node.Role == "dwell"))
        {
            throw Invalid("default node must be a dwell node");
        }
    }

    private static void ValidateGraphLinks(
        GraphDefinition graph,
        IReadOnlyDictionary<string, ClipDefinition> clips,
        PetPackageManifest manifest)
    {
        var nodes = graph.Nodes.ToDictionary(node => node.Id, StringComparer.Ordinal);
        var declaredPropIds = (manifest.RenderAssets.EnvironmentProps ?? [])
            .Select(prop => prop.Id)
            .ToHashSet(StringComparer.Ordinal);
        foreach (var node in graph.Nodes)
        {
            ValidateIdentifier(node.Id, "node id");
            if (!clips.TryGetValue(node.LoopClip, out var loop) || loop.Type != "loop")
            {
                throw Invalid($"node {node.Id} does not reference a loop clip");
            }
            if (loop.EntryPose != node.Id || loop.ExitPose != node.Id)
            {
                throw Invalid($"loop {loop.Id} does not preserve node {node.Id}");
            }
            if ((node.Props ?? []).Any(prop => !declaredPropIds.Contains(prop)))
            {
                throw Invalid($"node {node.Id} references an undeclared environment prop");
            }
        }
        foreach (var edge in graph.Edges)
        {
            if (!nodes.ContainsKey(edge.From) || !nodes.ContainsKey(edge.To))
            {
                throw Invalid($"edge {edge.Id} references an unknown node");
            }
            if (!clips.TryGetValue(edge.Clip, out var transition) || transition.Type != "transition")
            {
                throw Invalid($"edge {edge.Id} does not reference a transition clip");
            }
            if (transition.EntryPose != edge.From || transition.ExitPose != edge.To)
            {
                throw Invalid($"transition {transition.Id} endpoints do not match edge {edge.Id}");
            }
            var targetFrame = edge.TargetStartFrame ?? 0;
            var targetLoop = clips[nodes[edge.To].LoopClip];
            if (targetFrame < 0 || targetFrame >= targetLoop.Frames.Length)
            {
                throw Invalid($"edge {edge.Id} has an invalid target frame");
            }
        }

        var scenes = manifest.Scenes?.Select(scene => scene.Id).ToHashSet(StringComparer.Ordinal);
        if (graph.Nodes.Any(node => node.Scene is null) ||
            (scenes is not null && graph.Nodes.Any(node => !scenes.Contains(node.Scene!))))
        {
            throw Invalid("graph nodes must reference declared scenes");
        }
    }

    private static void ValidateBehavior(BehaviorDefinition behavior, GraphDefinition graph)
    {
        if (behavior.Profile != "quiet-sleep-companion" || behavior.DefaultIntent != "sleep")
        {
            throw Invalid("unsupported behavior profile");
        }
        if (behavior.Interactions.DesktopClick != "ignore" || behavior.Interactions.Drag != "direct-manipulation")
        {
            throw Invalid("unsupported interaction contract");
        }
        foreach (var scene in graph.Nodes.Select(node => node.Scene).OfType<string>().Distinct(StringComparer.Ordinal))
        {
            var interactions = graph.Nodes.Count(node => node.Scene == scene && node.Role == "interaction");
            var dwellNodes = graph.Nodes.Count(node => node.Scene == scene && node.Role == "dwell" && node.AutonomousEligible == true);
            if (interactions != 1 || dwellNodes == 0 || !behavior.ScenePolicy.ContainsKey(scene))
            {
                throw Invalid($"scene {scene} must have one interaction node and autonomous dwell nodes");
            }
        }
    }

    private static void ValidateClip(string root, PetPackageManifest manifest, ClipDefinition clip)
    {
        if (clip.Frames.Length == 0 || clip.RootMotionEndPt.Length != 2 ||
            clip.RootMotionEndPt.Any(value => !double.IsFinite(value)) ||
            clip.RootMotionEndPt[0] < -0.000001 || Math.Abs(clip.RootMotionEndPt[1]) > 0.000001)
        {
            throw Invalid($"clip {clip.Id} has no frames or invalid root motion");
        }
        if (clip.Type == "loop" && (clip.SafeExitFrames.Length == 0 || clip.SafeExitFrames.Any(frame => frame < 0 || frame >= clip.Frames.Length)))
        {
            throw Invalid($"loop {clip.Id} has invalid safe exits");
        }
        var previousRootMotionX = double.NegativeInfinity;
        foreach (var frame in clip.Frames)
        {
            if (frame.DurationMs <= 0 || frame.ContentBoundsPx.Length != 4 || frame.RootMotionPt.Length != 2 ||
                frame.AnchorsPx.Root.Length != 2 || frame.AnchorsPx.Ground.Length != 2 || frame.AnchorsPx.Head.Length != 2 ||
                frame.Collision.BodyCoreEllipsePx.Length != 4 || frame.Collision.ScreenBoundsPx.Length != 4 ||
                frame.RootMotionPt.Any(value => !double.IsFinite(value)) || frame.RootMotionPt[0] + 0.000001 < previousRootMotionX ||
                frame.RootMotionPt[0] < -0.000001 || Math.Abs(frame.RootMotionPt[1]) > 0.000001 ||
                (frame.PresentationOffsetPx is not null &&
                    (frame.PresentationOffsetPx.Length != 2 || frame.PresentationOffsetPx.Any(value => !double.IsFinite(value)) ||
                     Math.Abs(frame.PresentationOffsetPx[1]) > 0.000001)))
            {
                throw Invalid($"clip {clip.Id} contains invalid frame metadata");
            }
            previousRootMotionX = frame.RootMotionPt[0];
        }
        if (clip.RootMotionEndPt[0] + 0.000001 < previousRootMotionX ||
            (clip.RootMotionEndPt[0] > 0.000001 && clip.Facing is not ("left" or "right")) ||
            (clip.EntryPose.StartsWith("rest.", StringComparison.Ordinal) && clip.ExitPose.StartsWith("rest.", StringComparison.Ordinal) &&
                (clip.RootMotionEndPt.Any(value => Math.Abs(value) > 0.000001) ||
                 clip.Frames.Any(frame => frame.RootMotionPt.Any(value => Math.Abs(value) > 0.000001)))))
        {
            throw Invalid($"clip {clip.Id} has an invalid terminal root motion contract");
        }

        var media = clip.Media ?? throw Invalid($"clip {clip.Id} is missing raw media metadata");
        if (media.Type != "raw-frames" || media.Codec != "raw-rgba8" ||
            media.Container != "contiguous-frame-stream" || media.AlphaMode != "premultiplied-last" ||
            media.FrameCount != clip.Frames.Length || media.CropRectPx is not [var x, var y, var width, var height] ||
            x < 0 || y < 0 || width <= 0 || height <= 0 ||
            x + width > manifest.Art.CanvasPx[0] || y + height > manifest.Art.CanvasPx[1] ||
            media.BytesPerRow != width * 4 || media.FrameByteCount != width * height * 4 ||
            clip.Frames.Any(frame => frame.Src != media.Src))
        {
            throw Invalid($"clip {clip.Id} has an invalid cropped RGBA media contract");
        }

        var mediaPath = ResolveRegularFile(root, media.Src);
        var expectedBytes = checked((long)media.FrameCount * media.FrameByteCount.Value);
        if (new FileInfo(mediaPath).Length != expectedBytes)
        {
            throw Invalid($"clip {clip.Id} media length does not match its frame contract");
        }
    }

    private static void ValidateDemo(DemoSequence demo, IReadOnlyDictionary<string, ClipDefinition> clips)
    {
        if (demo.Segments.Length == 0)
        {
            throw Invalid("demo sequence is empty");
        }
        foreach (var segment in demo.Segments)
        {
            if (!clips.TryGetValue(segment.Clip, out var clip) || segment.StartFrame < 0 || segment.StartFrame >= clip.Frames.Length || segment.Cycles <= 0)
            {
                throw Invalid("demo sequence contains an invalid segment");
            }
        }
    }

    private static void ValidateEnvironmentProps(string root, PetPackageManifest manifest, GraphDefinition graph)
    {
        var props = manifest.RenderAssets.EnvironmentProps ?? [];
        if (props.Select(prop => prop.Id).Distinct(StringComparer.Ordinal).Count() != props.Length)
        {
            throw Invalid("environment prop ids must be unique");
        }
        var scenes = graph.Nodes.Select(node => node.Scene).OfType<string>().ToHashSet(StringComparer.Ordinal);
        foreach (var prop in props)
        {
            ValidateIdentifier(prop.Id, "environment prop id");
            if (prop.OffsetFromFloorOriginPt.Length != 2 || prop.Layer != "behind-pet" || prop.HitTest != "passthrough" ||
                prop.Visibility is not ("persistent" or "node-scenes" or "embedded") ||
                (prop.Scenes?.Any(scene => !scenes.Contains(scene)) ?? false) ||
                (prop.Visibility == "persistent" && prop.Scenes is { Length: > 0 }) ||
                (prop.Visibility != "persistent" && prop.Scenes is not { Length: > 0 }))
            {
                throw Invalid($"environment prop {prop.Id} has an invalid contract");
            }
            if (!ResolveRegularFile(root, prop.Src).EndsWith(".png", StringComparison.OrdinalIgnoreCase))
            {
                throw Invalid($"environment prop {prop.Id} is not a PNG");
            }
        }
    }

    private static void VerifyIntegrity(string root, PetPackageManifest manifest)
    {
        var integrity = Decode<IntegrityManifest>(root, manifest.Integrity);
        if (integrity.Algorithm != "sha256" || integrity.Files.Length == 0)
        {
            throw Invalid("unsupported or empty integrity manifest");
        }
        var declaredPaths = integrity.Files.Select(entry => NormalizeRelativePath(entry.Path)).ToArray();
        if (declaredPaths.Distinct(StringComparer.Ordinal).Count() != declaredPaths.Length)
        {
            throw Invalid("integrity manifest contains duplicate paths");
        }
        var integrityPath = NormalizeRelativePath(manifest.Integrity);
        var actualPaths = EnumerateRegularFiles(root)
            .Select(path => NormalizeRelativePath(Path.GetRelativePath(root, path)))
            .Where(path => path != integrityPath)
            .ToHashSet(StringComparer.Ordinal);
        if (!actualPaths.SetEquals(declaredPaths))
        {
            throw Invalid("integrity manifest does not exactly cover package files");
        }
        foreach (var entry in integrity.Files)
        {
            var path = ResolveRegularFile(root, entry.Path);
            var info = new FileInfo(path);
            if (info.Length != entry.Bytes)
            {
                throw Invalid($"integrity byte count mismatch for {entry.Path}");
            }
            using var stream = File.OpenRead(path);
            var digest = Convert.ToHexStringLower(SHA256.HashData(stream));
            if (!digest.Equals(entry.Sha256, StringComparison.OrdinalIgnoreCase))
            {
                throw Invalid($"integrity digest mismatch for {entry.Path}");
            }
        }
    }

    private static T Decode<T>(string root, string relativePath)
    {
        var path = ResolveRegularFile(root, relativePath);
        try
        {
            return JsonSerializer.Deserialize<T>(File.ReadAllBytes(path), JsonOptions)
                ?? throw Invalid($"empty JSON object in {relativePath}");
        }
        catch (JsonException exception)
        {
            throw Invalid($"malformed JSON in {relativePath}: {exception.Message}");
        }
    }

    internal static string ResolveRegularFile(string root, string relativePath)
    {
        if (string.IsNullOrWhiteSpace(relativePath) || Path.IsPathRooted(relativePath))
        {
            throw Invalid($"unsafe relative path {relativePath}");
        }
        var fullPath = Path.GetFullPath(Path.Combine(root, relativePath));
        var relative = Path.GetRelativePath(root, fullPath);
        if (relative == ".." || relative.StartsWith($"..{Path.DirectorySeparatorChar}", StringComparison.Ordinal) ||
            Path.IsPathRooted(relative) || !File.Exists(fullPath))
        {
            throw Invalid($"missing or escaping file {relativePath}");
        }
        RejectReparsePoint(fullPath, relativePath);
        var current = root;
        foreach (var component in relative.Split(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar))
        {
            current = Path.Combine(current, component);
            RejectReparsePoint(current, relativePath);
        }
        return fullPath;
    }

    private static IEnumerable<string> EnumerateRegularFiles(string root)
    {
        var pending = new Stack<string>();
        pending.Push(root);
        while (pending.TryPop(out var directory))
        {
            RejectReparsePoint(directory, Path.GetRelativePath(root, directory));
            foreach (var entry in Directory.EnumerateFileSystemEntries(directory))
            {
                RejectReparsePoint(entry, Path.GetRelativePath(root, entry));
                if (Directory.Exists(entry))
                {
                    pending.Push(entry);
                }
                else if (File.Exists(entry))
                {
                    yield return entry;
                }
            }
        }
    }

    private static string NormalizeRelativePath(string path) => path.Replace('\\', '/');

    private static void RejectReparsePoint(string path, string label)
    {
        if ((File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0)
        {
            throw Invalid($"{label} must not be a symbolic link or reparse point");
        }
    }

    private static void ValidateIdentifier(string value, string label)
    {
        if (string.IsNullOrWhiteSpace(value) || value.Any(character => !char.IsAsciiLetterOrDigit(character) && character is not ('.' or '_' or '-')))
        {
            throw Invalid($"unsafe {label} {value}");
        }
    }

    private static PetPackageValidationException Invalid(string detail) =>
        new($"Invalid pet package: {detail}");
}
