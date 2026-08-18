using System.Security.Cryptography;
using System.Text.Json;

namespace PetsGraph.Core.Tests;

internal sealed class TestPackageFixture : IDisposable
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true,
    };

    public string RootPath { get; } = Path.Combine(Path.GetTempPath(), $"petsgraph-tests-{Guid.NewGuid():N}.petsgraph-pet");

    public TestPackageFixture()
    {
        Directory.CreateDirectory(Path.Combine(RootPath, "clips", "media"));
        Directory.CreateDirectory(Path.Combine(RootPath, "reviews"));

        WriteJson("package.json", new PetPackageManifest
        {
            SchemaVersion = "0.4.0",
            Package = new() { Id = "test", Version = "0.0.1", CreatedAt = "2026-08-18T00:00:00+0800" },
            Pet = new() { Id = "testcat", DisplayName = "测试猫", Species = "cat", IdentityStyle = "fixture" },
            Art = new() { CanvasPx = [2, 1], BaseHeightPt = 1, CoordinateOrigin = "top-left", DefaultNode = "rest.floor", GroundYPx = 1 },
            RenderAssets = new() { Mode = "cropped-rgba-clips", PixelFormat = "rgba8-premultiplied", EnvironmentProps = [] },
            Graph = "graph.json",
            Behavior = "behavior.json",
            Scenes = [new() { Id = "floor", DisplayName = "地面", Order = 0 }],
            ReviewIndex = "reviews/index.json",
            Integrity = "integrity.json",
        });
        WriteJson("reviews/index.json", new ReviewIndex
        {
            SchemaVersion = "0.4.0",
            RuntimeChainStatus = "runtime-chain-approved",
            Installable = true,
            ApprovedRuntimeChains = ["test-0.0.1"],
            RemainingRuntimeGates = [],
        });
        WriteJson("graph.json", new GraphDefinition
        {
            SchemaVersion = "0.4.0",
            Nodes =
            [
                new() { Id = "rest.floor", DisplayName = "趴睡", Posture = "prone", Orientation = "right", Grounded = true, Stability = "stable", Scene = "floor", Role = "dwell", AutonomousEligible = true, Props = [], LoopClip = "rest-loop" },
                new() { Id = "sit.floor", DisplayName = "坐好", Posture = "sit", Orientation = "front", Grounded = true, Stability = "stable", Scene = "floor", Role = "interaction", AutonomousEligible = false, Props = [], LoopClip = "sit-loop" },
            ],
            Edges =
            [
                new() { Id = "wake", From = "rest.floor", To = "sit.floor", Clip = "wake", Kind = "transition", InterruptPolicy = "finish-before-retarget", TargetStartFrame = 0 },
                new() { Id = "sleep", From = "sit.floor", To = "rest.floor", Clip = "sleep", Kind = "transition", InterruptPolicy = "finish-before-retarget", TargetStartFrame = 0 },
            ],
        });
        WriteJson("behavior.json", new BehaviorDefinition
        {
            SchemaVersion = "0.4.0",
            Profile = "quiet-sleep-companion",
            DefaultIntent = "sleep",
            Timing = new() { Strategy = "random-long-tail", ParametersStatus = "fixture", AvoidImmediateRepeat = true, MinimumDwellSeconds = 180, MedianDwellSeconds = 480, MaximumDwellSeconds = 1800, RecentHistoryLimit = 2, SameSceneProbability = 0.9 },
            ScenePolicy = new() { ["floor"] = new() { Sticky = true, MinimumDwellSeconds = 180, ExitCooldownSeconds = 180 } },
            Interactions = new() { PetClick = new() { Sleeping = "wake-to-scene-sit", Sitting = "return-to-scene-sleep", DebounceSeconds = 0.35 }, DesktopClick = "ignore", Drag = "direct-manipulation" },
        });

        WriteClip("rest-loop", "loop", "rest.floor", "rest.floor", [10, 20, 30, 255, 40, 50, 60, 128]);
        WriteClip("sit-loop", "loop", "sit.floor", "sit.floor", [60, 50, 40, 255, 30, 20, 10, 128]);
        WriteClip("wake", "transition", "rest.floor", "sit.floor", [1, 2, 3, 255, 4, 5, 6, 255]);
        WriteClip("sleep", "transition", "sit.floor", "rest.floor", [6, 5, 4, 255, 3, 2, 1, 255]);

        WriteJson("demo-sequence.json", new DemoSequence
        {
            SchemaVersion = "0.4.0",
            Id = "fixture-demo",
            Segments = [new() { Clip = "rest-loop", StartFrame = 0, Cycles = 1, RepeatForever = true }],
        });

        var integrityEntries = Directory.EnumerateFiles(RootPath, "*", SearchOption.AllDirectories)
            .Select(path =>
            {
                var bytes = File.ReadAllBytes(path);
                return new IntegrityEntry
                {
                    Path = Path.GetRelativePath(RootPath, path).Replace('\\', '/'),
                    Bytes = bytes.Length,
                    Sha256 = Convert.ToHexStringLower(SHA256.HashData(bytes)),
                };
            })
            .OrderBy(entry => entry.Path, StringComparer.Ordinal)
            .ToArray();
        WriteJson("integrity.json", new IntegrityManifest
        {
            SchemaVersion = "0.4.0",
            Algorithm = "sha256",
            Files = integrityEntries,
        });
    }

    public void Dispose()
    {
        if (Directory.Exists(RootPath))
        {
            Directory.Delete(RootPath, recursive: true);
        }
    }

    private void WriteClip(string id, string type, string entry, string exit, byte[] mediaBytes)
    {
        var mediaRelativePath = $"clips/media/{id}.rgba";
        File.WriteAllBytes(Path.Combine(RootPath, mediaRelativePath), mediaBytes);
        WriteJson($"clips/{id}.json", new ClipDefinition
        {
            SchemaVersion = "0.4.0",
            Id = id,
            Type = type,
            Facing = "right",
            MirrorSafe = false,
            EntryPose = entry,
            ExitPose = exit,
            SafeExitFrames = type == "loop" ? [0] : [],
            PreloadHints = [],
            RootMotionEndPt = [0, 0],
            Frames =
            [
                new()
                {
                    Src = mediaRelativePath,
                    DurationMs = 100,
                    ContentBoundsPx = [0, 0, 2, 1],
                    PetBoundsPx = [0, 0, 2, 1],
                    AnchorsPx = new() { Root = [1, 1], Ground = [1, 1], Head = [1, 0] },
                    Collision = new() { BodyCoreEllipsePx = [0, 0, 2, 1], ScreenBoundsPx = [0, 0, 2, 1], PetHitEllipsePx = [0, 0, 2, 1] },
                    RootMotionPt = [0, 0],
                },
            ],
            Media = new()
            {
                Type = "raw-frames",
                Src = mediaRelativePath,
                Codec = "raw-rgba8",
                Container = "contiguous-frame-stream",
                FrameCount = 1,
                FrameRate = 10,
                AlphaMode = "premultiplied-last",
                ColorSpace = "sRGB",
                SourceSequenceDigest = "fixture",
                CompiledFrameSequenceDigest = "fixture",
                CropRectPx = [0, 0, 2, 1],
                BytesPerRow = 8,
                FrameByteCount = 8,
            },
        });
    }

    private void WriteJson<T>(string relativePath, T value)
    {
        var path = Path.Combine(RootPath, relativePath);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllBytes(path, JsonSerializer.SerializeToUtf8Bytes(value, JsonOptions));
    }
}
