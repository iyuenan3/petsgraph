using System.Buffers.Binary;
using System.IO.Compression;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace PetsGraph.Core.Tests;

[TestClass]
public sealed class PetPackV1Tests
{
    private static string FixturePath => Path.Combine(AppContext.BaseDirectory, "synthetic-cat-v1.petpack");
    private static string ForwardFixturePath =>
        Path.Combine(AppContext.BaseDirectory, "synthetic-cat-forward-v1.petpack");

    [TestMethod]
    public void LoadsPublicSyntheticPetPack()
    {
        using var workspace = new TestWorkspace();
        var runtime = workspace.CreateDirectory("runtime");
        var validated = new PetPackValidator().ValidateAndExtract(FixturePath, runtime);

        Assert.AreEqual("synthetic-cat-v1", validated.Report.PackageId);
        Assert.AreEqual("812f0459fe444ff4cf657908d3c9b235be21f591d796ac7d0f02e50f564ac2c1",
            validated.Report.ArchiveSha256);
        Assert.AreEqual(4, validated.Report.ClipCount);
        Assert.AreEqual(2, validated.Report.NodeCount);
        Assert.AreEqual(2, validated.Report.EdgeCount);
    }

    [TestMethod]
    public void LoadsDeflatedPetPack()
    {
        using var workspace = new TestWorkspace();
        var source = workspace.PathFor("deflated.petpack");
        var extracted = workspace.CreateDirectory("source");
        ZipFile.ExtractToDirectory(FixturePath, extracted);
        ZipFile.CreateFromDirectory(extracted, source, CompressionLevel.Optimal, includeBaseDirectory: false);

        var validated = new PetPackValidator().ValidateAndExtract(source, workspace.CreateDirectory("runtime"));

        Assert.AreEqual(4, validated.Report.ClipCount);
    }

    [TestMethod]
    public void LoadsForwardCompatiblePetPack()
    {
        using var workspace = new TestWorkspace();
        var validated = new PetPackValidator().ValidateAndExtract(
            ForwardFixturePath, workspace.CreateDirectory("runtime"));

        Assert.AreEqual("synthetic-cat-forward-v1", validated.Report.PackageId);
        Assert.HasCount(0, validated.Package.Behavior.NodeWeights);
        Assert.HasCount(0, validated.Package.Behavior.SceneWeights);
        Assert.AreEqual("future-audio", validated.Package.Manifest.Capabilities.Optional.Single());
    }

    [TestMethod]
    public void RejectsTrailingArchivePayload()
    {
        using var workspace = new TestWorkspace();
        var source = workspace.PathFor("trailing.petpack");
        File.Copy(FixturePath, source);
        using (var stream = new FileStream(source, FileMode.Append, FileAccess.Write, FileShare.None))
        {
            stream.WriteByte(0);
        }

        var exception = Assert.Throws<PetPackException>(() =>
            new PetPackValidator().ValidateAndExtract(source, workspace.CreateDirectory("runtime")));

        Assert.AreEqual("archive_trailing", exception.Code);
    }

    [TestMethod]
    public void RejectsDuplicateJsonKeysBeforeTrustingIntegrity()
    {
        using var workspace = new TestWorkspace();
        var extracted = workspace.CreateDirectory("source");
        ZipFile.ExtractToDirectory(FixturePath, extracted);
        var manifest = Path.Combine(extracted, "manifest.json");
        var text = File.ReadAllText(manifest);
        File.WriteAllText(manifest, text.Replace("{\n  \"behavior\"", "{\n  \"behavior\": \"behavior.json\",\n  \"behavior\"",
            StringComparison.Ordinal));
        var source = workspace.PathFor("duplicate-json.petpack");
        ZipFile.CreateFromDirectory(extracted, source, CompressionLevel.NoCompression, includeBaseDirectory: false);

        var exception = Assert.Throws<PetPackException>(() =>
            new PetPackValidator().ValidateAndExtract(source, workspace.CreateDirectory("runtime")));

        Assert.AreEqual("invalid_json", exception.Code);
    }

    [TestMethod]
    public void RejectsPathTraversalEntry()
    {
        using var workspace = new TestWorkspace();
        var source = workspace.PathFor("traversal.petpack");
        WriteArchiveWithExtra(workspace, source, "../escape.json", "{}"u8.ToArray(), RegularFileAttributes);

        var exception = Assert.Throws<PetPackException>(() =>
            new PetPackValidator().ValidateAndExtract(source, workspace.CreateDirectory("runtime")));

        Assert.AreEqual("unsafe_path", exception.Code);
    }

    [TestMethod]
    public void RejectsCrossPlatformCaseCollision()
    {
        using var workspace = new TestWorkspace();
        var source = workspace.PathFor("casefold.petpack");
        WriteArchiveWithExtra(workspace, source, "Graph.json", "{}"u8.ToArray(), RegularFileAttributes);

        var exception = Assert.Throws<PetPackException>(() =>
            new PetPackValidator().ValidateAndExtract(source, workspace.CreateDirectory("runtime")));

        Assert.AreEqual("path_conflict", exception.Code);
    }

    [TestMethod]
    public void RejectsSymlinkEntry()
    {
        using var workspace = new TestWorkspace();
        var source = workspace.PathFor("symlink.petpack");
        WriteArchiveWithExtra(workspace, source, "media/link.rgba", "target"u8.ToArray(), SymlinkAttributes);

        var exception = Assert.Throws<PetPackException>(() =>
            new PetPackValidator().ValidateAndExtract(source, workspace.CreateDirectory("runtime")));

        Assert.AreEqual("unsafe_entry", exception.Code);
    }

    [TestMethod]
    public void RejectsExplicitDirectoryEntry()
    {
        using var workspace = new TestWorkspace();
        var source = workspace.PathFor("directory-entry.petpack");
        WriteArchiveWithExtra(workspace, source, "media/", [], RegularFileAttributes);

        var exception = Assert.Throws<PetPackException>(() =>
            new PetPackValidator().ValidateAndExtract(source, workspace.CreateDirectory("runtime")));

        Assert.AreEqual("unsafe_path", exception.Code);
    }

    [TestMethod]
    public void RejectsMediaDigestMismatch()
    {
        using var workspace = new TestWorkspace();
        var extracted = workspace.CreateDirectory("source");
        ZipFile.ExtractToDirectory(FixturePath, extracted);
        var media = Directory.EnumerateFiles(Path.Combine(extracted, "media"), "*.rgba", SearchOption.AllDirectories).First();
        var bytes = File.ReadAllBytes(media);
        bytes[^1] ^= byte.MaxValue;
        File.WriteAllBytes(media, bytes);
        var source = workspace.PathFor("digest.petpack");
        ZipFile.CreateFromDirectory(extracted, source, CompressionLevel.NoCompression, includeBaseDirectory: false);

        var exception = Assert.Throws<PetPackException>(() =>
            new PetPackValidator().ValidateAndExtract(source, workspace.CreateDirectory("runtime")));

        Assert.AreEqual("integrity_mismatch", exception.Code);
    }

    [TestMethod]
    public void RejectsIncorrectIntegrityMediaType()
    {
        using var workspace = new TestWorkspace();
        var extracted = workspace.CreateDirectory("source");
        ZipFile.ExtractToDirectory(FixturePath, extracted);
        var path = Path.Combine(extracted, "integrity.json");
        var integrity = JsonNode.Parse(File.ReadAllText(path))!.AsObject();
        integrity["files"]!.AsArray()[0]!["mediaType"] = "application/octet-stream";
        File.WriteAllText(path, integrity.ToJsonString(new() { WriteIndented = true }));
        var source = workspace.PathFor("media-type.petpack");
        ZipFile.CreateFromDirectory(extracted, source, CompressionLevel.NoCompression, includeBaseDirectory: false);

        var exception = Assert.Throws<PetPackException>(() =>
            new PetPackValidator().ValidateAndExtract(source, workspace.CreateDirectory("runtime")));

        Assert.AreEqual("invalid_integrity", exception.Code);
    }

    [TestMethod]
    public void RejectsNonNfcDisplayName()
    {
        using var workspace = new TestWorkspace();
        var extracted = workspace.CreateDirectory("source");
        ZipFile.ExtractToDirectory(FixturePath, extracted);
        var path = Path.Combine(extracted, "manifest.json");
        var manifest = JsonNode.Parse(File.ReadAllText(path))!.AsObject();
        manifest["pet"]!["displayName"] = "e\u0301";
        File.WriteAllText(path, manifest.ToJsonString(new() { WriteIndented = true }));
        RewriteIntegrity(extracted);
        var source = workspace.PathFor("display-name.petpack");
        ZipFile.CreateFromDirectory(extracted, source, CompressionLevel.NoCompression, includeBaseDirectory: false);

        var exception = Assert.Throws<PetPackException>(() =>
            new PetPackValidator().ValidateAndExtract(source, workspace.CreateDirectory("runtime")));

        Assert.AreEqual("invalid_text", exception.Code);
    }

    [TestMethod]
    public void RejectsGatewayWithExplicitNullLoopClip()
    {
        using var workspace = new TestWorkspace();
        var extracted = workspace.CreateDirectory("source");
        ZipFile.ExtractToDirectory(FixturePath, extracted);
        var path = Path.Combine(extracted, "graph.json");
        var graph = JsonNode.Parse(File.ReadAllText(path))!.AsObject();
        graph["nodes"]!.AsArray().Add(new JsonObject
        {
            ["autonomousEligible"] = false,
            ["id"] = "rest.gateway",
            ["loopClip"] = null,
            ["role"] = "gateway",
            ["scene"] = "rest",
        });
        File.WriteAllText(path, graph.ToJsonString(new() { WriteIndented = true }));
        RewriteIntegrity(extracted);
        var source = workspace.PathFor("gateway-null.petpack");
        ZipFile.CreateFromDirectory(extracted, source, CompressionLevel.NoCompression, includeBaseDirectory: false);

        var exception = Assert.Throws<PetPackException>(() =>
            new PetPackValidator().ValidateAndExtract(source, workspace.CreateDirectory("runtime")));

        Assert.AreEqual("invalid_graph", exception.Code);
    }

    [TestMethod]
    public void RejectsDurationThatOnlyMatchesOverflowedIntegerArithmetic()
    {
        using var workspace = new TestWorkspace();
        var extracted = workspace.CreateDirectory("source");
        ZipFile.ExtractToDirectory(FixturePath, extracted);
        var path = Path.Combine(extracted, "clips", "rest-primary-loop.json");
        var clip = JsonNode.Parse(File.ReadAllText(path))!.AsObject();
        clip["frameRate"] = new JsonObject { ["numerator"] = 1, ["denominator"] = 1_000 };
        clip["frameCount"] = int.MaxValue;
        clip["durationSeconds"] = -1_000;
        File.WriteAllText(path, clip.ToJsonString(new() { WriteIndented = true }));
        RewriteIntegrity(extracted);
        var source = workspace.PathFor("duration-overflow.petpack");
        ZipFile.CreateFromDirectory(extracted, source, CompressionLevel.NoCompression, includeBaseDirectory: false);

        var exception = Assert.Throws<PetPackException>(() =>
            new PetPackValidator().ValidateAndExtract(source, workspace.CreateDirectory("runtime")));

        Assert.AreEqual("invalid_duration", exception.Code);
    }

    [TestMethod]
    public void CanonicalLibraryOwnsCopyAndImportsIdempotently()
    {
        using var workspace = new TestWorkspace();
        var source = workspace.PathFor("owned.petpack");
        File.Copy(FixturePath, source);
        var library = new CanonicalPetLibrary(workspace.CreateDirectory("library-root"));

        var first = library.Import(source);
        library.CommitImport(first);
        File.Delete(source);
        var second = library.Import(FixturePath);
        var loaded = library.LoadInstalledPetPacks();

        Assert.AreEqual(PetImportResult.Installed, first.Result);
        Assert.AreEqual(PetImportResult.AlreadyInstalled, second.Result);
        Assert.HasCount(1, loaded);
        Assert.AreEqual("synthetic-cat-v1", loaded[0].Manifest.Package.Id);
    }

    [TestMethod]
    public void CanonicalLibraryRollsBackFailedFirstInstall()
    {
        using var workspace = new TestWorkspace();
        var root = workspace.CreateDirectory("library-root");
        var library = new CanonicalPetLibrary(root);
        var outcome = library.Import(FixturePath);

        library.RollbackImport(outcome);

        Assert.IsEmpty(library.InstalledPets());
        Assert.IsEmpty(library.LoadInstalledPetPacks());
        Assert.IsFalse(Directory.EnumerateFiles(Path.Combine(root, "library"), "*.petpack",
            SearchOption.AllDirectories).Any());
    }

    [TestMethod]
    public void CanonicalLibraryRecoversInterruptedImportOnRestart()
    {
        using var workspace = new TestWorkspace();
        var root = workspace.CreateDirectory("library-root");
        var interrupted = new CanonicalPetLibrary(root);
        _ = interrupted.Import(FixturePath);

        var recovered = new CanonicalPetLibrary(root);

        Assert.IsEmpty(recovered.InstalledPets());
        Assert.IsEmpty(recovered.LoadInstalledPetPacks());
        Assert.IsFalse(File.Exists(Path.Combine(root, "pending-import.json")));
    }

    [TestMethod]
    public void CanonicalLibraryRollsBackFailedUpdateToPreviousVersion()
    {
        using var workspace = new TestWorkspace();
        var root = workspace.CreateDirectory("library-root");
        var library = new CanonicalPetLibrary(root);
        var initial = library.Import(FixturePath);
        library.CommitImport(initial);
        var extracted = workspace.CreateDirectory("updated");
        ZipFile.ExtractToDirectory(FixturePath, extracted);
        var manifestPath = Path.Combine(extracted, "manifest.json");
        var manifest = JsonNode.Parse(File.ReadAllText(manifestPath))!.AsObject();
        manifest["package"]!["contentVersion"] = "1.0.1";
        File.WriteAllText(manifestPath, manifest.ToJsonString(new() { WriteIndented = true }));
        RewriteIntegrity(extracted);
        var updatedPath = workspace.PathFor("updated.petpack");
        ZipFile.CreateFromDirectory(extracted, updatedPath, CompressionLevel.NoCompression,
            includeBaseDirectory: false);
        var updated = library.Import(updatedPath, (_, _) => true);
        Assert.AreEqual(PetImportResult.Updated, updated.Result);

        library.RollbackImport(updated);

        Assert.AreEqual(initial.Current, library.InstalledPets().Single());
        Assert.AreEqual("1.0.0", library.LoadInstalledPetPacks().Single().Manifest.Package.ContentVersion.Value);
        Assert.IsFalse(Directory.Exists(Path.Combine(root, "library", "synthetic-cat-v1", "1.0.1")));
        Assert.IsFalse(Directory.Exists(Path.Combine(root, "cache", "synthetic-cat-v1", "1.0.1")));
    }

    [TestMethod]
    public void CanonicalLibraryRebuildsDeletedCache()
    {
        using var workspace = new TestWorkspace();
        var root = workspace.CreateDirectory("library-root");
        var library = new CanonicalPetLibrary(root);
        var imported = library.Import(FixturePath);
        library.CommitImport(imported);
        var cache = Path.Combine(root, "cache");
        Directory.Delete(cache, recursive: true);
        Directory.CreateDirectory(cache);

        var loaded = library.LoadInstalledPetPacks();

        Assert.HasCount(1, loaded);
        Assert.IsTrue(Directory.EnumerateFiles(cache, "manifest.json", SearchOption.AllDirectories).Any());
    }

    [TestMethod]
    public void CanonicalLibraryRebuildsSameLengthCorruptMediaCache()
    {
        using var workspace = new TestWorkspace();
        var root = workspace.CreateDirectory("library-root");
        var library = new CanonicalPetLibrary(root);
        var imported = library.Import(FixturePath);
        library.CommitImport(imported);
        var installed = library.LoadInstalledPetPacks().Single();
        var media = installed.MediaPath("rest-primary-loop");
        var expected = File.ReadAllBytes(media);
        var corrupt = expected.ToArray();
        corrupt[0] ^= byte.MaxValue;
        File.WriteAllBytes(media, corrupt);

        var rebuilt = library.LoadInstalledPetPacks().Single();

        CollectionAssert.AreEqual(expected, File.ReadAllBytes(rebuilt.MediaPath("rest-primary-loop")));
    }

    [TestMethod]
    public void CanonicalLibraryRejectsSameVersionWithDifferentBytes()
    {
        using var workspace = new TestWorkspace();
        var root = workspace.CreateDirectory("library-root");
        var library = new CanonicalPetLibrary(root);
        var imported = library.Import(FixturePath);
        library.CommitImport(imported);
        var extracted = workspace.CreateDirectory("changed");
        ZipFile.ExtractToDirectory(FixturePath, extracted);
        var manifestPath = Path.Combine(extracted, "manifest.json");
        var manifest = JsonNode.Parse(File.ReadAllText(manifestPath))!.AsObject();
        manifest["package"]!["createdAt"] = "2026-01-02T00:00:00+08:00";
        File.WriteAllText(manifestPath, manifest.ToJsonString(new() { WriteIndented = true }));
        RewriteIntegrity(extracted);
        var changed = workspace.PathFor("same-version-different-bytes.petpack");
        ZipFile.CreateFromDirectory(extracted, changed, CompressionLevel.NoCompression, includeBaseDirectory: false);

        var exception = Assert.Throws<PetPackException>(() => library.Import(changed));

        Assert.AreEqual("version_conflict", exception.Code);
        Assert.HasCount(1, library.LoadInstalledPetPacks());
    }

    [TestMethod]
    public void CanonicalLibraryUninstallAllRemovesManagedPackages()
    {
        using var workspace = new TestWorkspace();
        var root = workspace.CreateDirectory("library-root");
        var library = new CanonicalPetLibrary(root);
        var imported = library.Import(FixturePath);
        library.CommitImport(imported);

        var removed = library.UninstallAll();

        Assert.HasCount(1, removed);
        Assert.IsEmpty(library.InstalledPets());
        Assert.IsEmpty(library.LoadInstalledPetPacks());
        Assert.IsFalse(Directory.EnumerateFiles(Path.Combine(root, "library"), "*.petpack", SearchOption.AllDirectories).Any());
    }

    [TestMethod]
    public void CanonicalLibraryRejectsUnsafeRegistryIdentity()
    {
        using var workspace = new TestWorkspace();
        var root = workspace.CreateDirectory("library-root");
        _ = new CanonicalPetLibrary(root);
        File.WriteAllText(Path.Combine(root, "registry.json"), """
            {
              "formatVersion": 1,
              "packages": [
                {
                  "packageId": "../../outside",
                  "petId": "../../outside",
                  "displayName": "Unsafe",
                  "species": "cat",
                  "contentVersion": "1.0.0",
                  "archiveSha256": "0000000000000000000000000000000000000000000000000000000000000000",
                  "archiveBytes": 1
                }
              ]
            }
            """);
        var exception = Assert.Throws<PetPackException>(() => new CanonicalPetLibrary(root));

        Assert.AreEqual("registry_corrupt", exception.Code);
    }

    [TestMethod]
    public void CanonicalLibraryRejectsDirectoryInPlaceOfRegistry()
    {
        using var workspace = new TestWorkspace();
        var root = workspace.CreateDirectory("library-root");
        Directory.CreateDirectory(Path.Combine(root, "registry.json"));

        var exception = Assert.Throws<PetPackException>(() => new CanonicalPetLibrary(root));

        Assert.AreEqual("registry_corrupt", exception.Code);
    }

    [TestMethod]
    public void CanonicalLibraryRemovesUnjournaledUninstallTransaction()
    {
        using var workspace = new TestWorkspace();
        var root = workspace.CreateDirectory("library-root");
        var orphan = workspace.CreateDirectory(Path.Combine("library-root", "staging", "uninstall-orphan"));

        _ = new CanonicalPetLibrary(root);

        Assert.IsFalse(Directory.Exists(orphan));
    }

    [TestMethod]
    public void CanonicalLibraryRollsBackInterruptedUninstallBeforeRegistryCommit()
    {
        using var workspace = new TestWorkspace();
        var root = workspace.CreateDirectory("library-root");
        var library = new CanonicalPetLibrary(root);
        var outcome = library.Import(FixturePath);
        library.CommitImport(outcome);
        var installed = library.InstalledPets().Single();
        var transaction = StageInterruptedUninstall(root, installed, registryKeepsPet: true);

        var recovered = new CanonicalPetLibrary(root);

        Assert.AreEqual(installed, recovered.InstalledPets().Single());
        Assert.HasCount(1, recovered.LoadInstalledPetPacks());
        Assert.IsFalse(Directory.Exists(transaction));
    }

    [TestMethod]
    public void CanonicalLibraryFinishesInterruptedUninstallAfterRegistryCommit()
    {
        using var workspace = new TestWorkspace();
        var root = workspace.CreateDirectory("library-root");
        var library = new CanonicalPetLibrary(root);
        var outcome = library.Import(FixturePath);
        library.CommitImport(outcome);
        var installed = library.InstalledPets().Single();
        var transaction = StageInterruptedUninstall(root, installed, registryKeepsPet: false);

        var recovered = new CanonicalPetLibrary(root);

        Assert.IsEmpty(recovered.InstalledPets());
        Assert.IsEmpty(recovered.LoadInstalledPetPacks());
        Assert.IsFalse(Directory.Exists(transaction));
    }

    [TestMethod]
    public void ImportRecoveryUsesExactVersionPathIdentity()
    {
        using var workspace = new TestWorkspace();
        var root = workspace.CreateDirectory("library-root");
        _ = new CanonicalPetLibrary(root);
        static string Record(string version) => $$"""
            {
              "packageId": "synthetic-cat-v1",
              "petId": "synthetic-cat-v1",
              "displayName": "Synthetic Cat",
              "species": "cat",
              "contentVersion": "{{version}}",
              "archiveSha256": "0000000000000000000000000000000000000000000000000000000000000000",
              "archiveBytes": 1
            }
            """;
        File.WriteAllText(Path.Combine(root, "registry.json"), $$"""
            { "formatVersion": 1, "packages": [{{Record("1.0.0+two")}}] }
            """);
        File.WriteAllText(Path.Combine(root, "pending-import.json"), $$"""
            { "formatVersion": 1, "current": {{Record("1.0.0+one")}}, "previous": null }
            """);

        var exception = Assert.Throws<PetPackException>(() => new CanonicalPetLibrary(root));

        Assert.AreEqual("import_recovery_failed", exception.Code);
    }

    [TestMethod]
    public void PassiveBehaviorUsesDirectedTransition()
    {
        using var package = LoadedFixture();
        var session = new PassiveBehaviorSession(package.Value, startedAt: 0, seed: 1);

        _ = session.Update(100);
        var transition = session.Update(100.1);
        var stable = session.Update(200);

        Assert.IsTrue(transition.IsTransition);
        Assert.AreEqual("rest-primary-to-rest-secondary", transition.ClipId);
        Assert.IsFalse(stable.IsTransition);
        Assert.AreEqual("rest.secondary", stable.CurrentNodeId);
    }

    [TestMethod]
    public void PassiveBehaviorSessionsAdvanceOnIndependentClocks()
    {
        using var package = LoadedFixture();
        var earlier = new PassiveBehaviorSession(package.Value, startedAt: 0, seed: 3);
        var later = new PassiveBehaviorSession(package.Value, startedAt: 0, seed: 6);

        var earlierAtForty = earlier.Update(40);
        var laterAtForty = later.Update(40);

        Assert.IsNotEmpty(earlierAtForty.PreloadClipIds);
        Assert.IsEmpty(laterAtForty.PreloadClipIds);
        Assert.AreEqual("rest.primary", earlierAtForty.CurrentNodeId);
        Assert.AreEqual("rest.primary", laterAtForty.CurrentNodeId);
    }

    [TestMethod]
    public void PassiveBehaviorPreloadsWholeGatewayPathAndTargetLoop()
    {
        using var fixture = LoadedFixture();
        var package = fixture.Value;
        var primary = package.Graph.Nodes.Single(node => node.Id == "rest.primary");
        var secondary = package.Graph.Nodes.Single(node => node.Id == "rest.secondary");
        var gateway = new PetGraphNode
        {
            Id = "rest.gateway",
            Role = "gateway",
            Scene = "rest",
            AutonomousEligible = false,
        };
        var modified = package with
        {
            Graph = package.Graph with
            {
                Nodes = [primary, gateway, secondary],
                Edges =
                [
                    new()
                    {
                        Id = "primary-to-gateway", From = primary.Id, To = gateway.Id,
                        Clip = "rest-primary-to-rest-secondary", InterruptPolicy = "finish-before-retarget",
                    },
                    new()
                    {
                        Id = "gateway-to-secondary", From = gateway.Id, To = secondary.Id,
                        Clip = "rest-secondary-to-rest-primary", InterruptPolicy = "finish-before-retarget",
                    },
                ],
            },
        };
        var session = new PassiveBehaviorSession(modified, startedAt: 0, seed: 7);

        var planned = session.Update(1_000);

        CollectionAssert.AreEquivalent(
            new[] { "rest-primary-to-rest-secondary", "rest-secondary-to-rest-primary", "rest-secondary-loop" },
            planned.PreloadClipIds.ToArray());
        Assert.IsFalse(planned.IsTransition);
        session.CancelPlannedTransition(1_000);
        Assert.IsEmpty(session.Update(1_000).PreloadClipIds);
    }

    [TestMethod]
    public void PassiveBehaviorAllowsWeightedImmediateRepeatWithoutTransition()
    {
        using var fixture = LoadedFixture();
        var package = fixture.Value;
        var modified = package with
        {
            Behavior = package.Behavior with
            {
                Timing = package.Behavior.Timing with { AvoidImmediateRepeat = false },
                NodeWeights = new(StringComparer.Ordinal)
                {
                    ["rest.primary"] = double.MaxValue,
                    ["rest.secondary"] = double.Epsilon,
                },
            },
        };
        var session = new PassiveBehaviorSession(modified, startedAt: 0, seed: 1);

        var presentation = session.Update(1_000);

        Assert.AreEqual("rest.primary", presentation.CurrentNodeId);
        Assert.IsFalse(presentation.IsTransition);
        Assert.IsEmpty(presentation.PreloadClipIds);
    }

    [TestMethod]
    public void PassiveBehaviorKeepsLoopFrameIndexBoundedAfterLongUptime()
    {
        using var fixture = LoadedFixture();
        var session = new PassiveBehaviorSession(fixture.Value, startedAt: 0, seed: 1);

        var presentation = session.Update(50_000_000);
        var clip = fixture.Value.Clips[presentation.ClipId];

        Assert.IsGreaterThanOrEqualTo(0, presentation.FrameIndex);
        Assert.IsLessThan(clip.FrameCount, presentation.FrameIndex);
    }

    [TestMethod]
    public void HiddenTransitionFinishesAtStableNodeThenPauses()
    {
        using var package = LoadedFixture();
        var session = new PassiveBehaviorSession(package.Value, startedAt: 0, seed: 1);
        _ = session.Update(100);
        var transition = session.Update(100.1);
        Assert.IsTrue(transition.IsTransition);

        session.SetVisible(false, 100.11);
        _ = session.Update(200);

        Assert.IsTrue(session.IsPaused);
        Assert.IsFalse(session.ShouldTickWhenHidden);
        Assert.AreEqual("rest.secondary", session.CurrentStableNodeId);
    }

    [TestMethod]
    public void RendererSwizzlesPremultipliedRgbaToPbgra()
    {
        using var package = LoadedFixture();
        using var renderer = new RgbaFrameRenderer(package.Value);
        var layout = renderer.FrameLayout("rest-primary-loop");
        var pixels = new byte[layout.Bytes];

        renderer.RenderPbgra32("rest-primary-loop", 0, pixels);

        Assert.AreEqual(2, layout.Width);
        Assert.AreEqual(2, layout.Height);
        Assert.AreEqual(8, layout.Stride);
        Assert.AreEqual((byte)7, pixels[0]);
        Assert.AreEqual((byte)31, pixels[2]);
        Assert.AreEqual(byte.MaxValue, pixels[3]);
    }

    [TestMethod]
    public void PlayerStateUsesOneBoundedGlobalScale()
    {
        Assert.AreEqual(0.5, PlayerState.NormalizeScale(0.5));
        Assert.AreEqual(2, PlayerState.NormalizeScale(2));
        Assert.AreEqual(1, PlayerState.NormalizeScale(1.2));
        Assert.HasCount(7, PlayerState.AllowedScales);
    }

    [TestMethod]
    public void LegacyMigrationKeepsOnlyPositionAndResetsVisibility()
    {
        var migrated = PlayerState.MigratedLegacyPet(123, 456);

        Assert.IsTrue(migrated.Visible);
        Assert.AreEqual(123, migrated.AnchorX);
        Assert.AreEqual(456, migrated.AnchorY);
        Assert.IsNull(PlayerState.MigratedLegacyPet(double.PositiveInfinity, double.NaN).AnchorX);
        Assert.IsNull(PlayerState.MigratedLegacyPet(double.PositiveInfinity, double.NaN).AnchorY);
    }

    [TestMethod]
    public void CorruptSettingsFailSafeHidesEveryInstalledPet()
    {
        var state = PlayerState.HiddenFailSafe(["wubai", "feiliu"]);

        CollectionAssert.AreEquivalent(new[] { "wubai", "feiliu" }, state.Pets.Keys.ToArray());
        Assert.IsTrue(state.Pets.Values.All(static pet => !pet.Visible));
    }

    [TestMethod]
    public void StateStoreFailsClosedWhenSettingsAreCorrupt()
    {
        using var workspace = new TestWorkspace();
        using var fixture = LoadedFixture();
        var root = workspace.CreateDirectory("settings-root");
        File.WriteAllText(Path.Combine(root, "settings.json"), "not json");
        var store = new PlayerStateStore(root);

        var state = store.Load([fixture.Value]);

        Assert.IsNotNull(store.LoadWarning);
        Assert.IsFalse(state.Pets[fixture.Value.Manifest.Package.Id].Visible);
    }

    [TestMethod]
    public void StateStoreFailsClosedWhenSettingsPathIsDirectory()
    {
        using var workspace = new TestWorkspace();
        using var fixture = LoadedFixture();
        var root = workspace.CreateDirectory("settings-root");
        Directory.CreateDirectory(Path.Combine(root, "settings.json"));
        var store = new PlayerStateStore(root);

        var state = store.Load([fixture.Value]);

        Assert.IsNotNull(store.LoadWarning);
        Assert.IsFalse(state.Pets[fixture.Value.Manifest.Package.Id].Visible);
    }

    [TestMethod]
    public void StateStoreRoundTripsTwoPetsAndPrunesUninstalledState()
    {
        using var workspace = new TestWorkspace();
        var root = workspace.CreateDirectory("settings-root");
        var primary = new PetPackValidator().ValidateAndExtract(
            FixturePath, workspace.CreateDirectory("primary-runtime")).Package;
        var secondary = new PetPackValidator().ValidateAndExtract(
            ForwardFixturePath, workspace.CreateDirectory("secondary-runtime")).Package;
        var store = new PlayerStateStore(root);
        var state = new PlayerState { GlobalScale = 1.75 };
        state.Pets.Add(primary.Manifest.Package.Id,
            new() { Visible = false, AnchorX = 123.5, AnchorY = 456.25 });
        state.Pets.Add(secondary.Manifest.Package.Id,
            new() { Visible = true, AnchorX = -80, AnchorY = 900 });
        state.Pets.Add("uninstalled-pet",
            new() { Visible = false, AnchorX = 1, AnchorY = 2 });

        store.Save(state);
        var restored = store.Load([primary, secondary]);

        Assert.IsNull(store.LoadWarning);
        Assert.AreEqual(1.75, restored.GlobalScale);
        CollectionAssert.AreEquivalent(
            new[] { primary.Manifest.Package.Id, secondary.Manifest.Package.Id },
            restored.Pets.Keys.ToArray());
        Assert.AreEqual(new PetPlayerState { Visible = false, AnchorX = 123.5, AnchorY = 456.25 },
            restored.Pets[primary.Manifest.Package.Id]);
        Assert.AreEqual(new PetPlayerState { Visible = true, AnchorX = -80, AnchorY = 900 },
            restored.Pets[secondary.Manifest.Package.Id]);
    }

    [TestMethod]
    public void SemanticVersionOrderingFollowsPrereleaseRules()
    {
        Assert.IsTrue(SemanticVersion.Parse("1.0.0-alpha.1") < SemanticVersion.Parse("1.0.0"));
        Assert.IsTrue(SemanticVersion.Parse("1.0.0") < SemanticVersion.Parse("1.0.1"));
        Assert.AreEqual(SemanticVersion.Parse("1.0.0+one"), SemanticVersion.Parse("1.0.0+two"));
        Assert.Throws<PetPackException>(() => SemanticVersion.Parse($"1.0.0+{new string('a', 81)}"));
        Assert.Throws<PetPackException>(() => SemanticVersion.Parse("1.0.0-01"));
        Assert.Throws<PetPackException>(() => SemanticVersion.Parse("1.0.0-alpha..1"));
        Assert.Throws<PetPackException>(() => SemanticVersion.Parse("2147483648.0.0"));
        Assert.IsTrue(SemanticVersion.Parse("1.0.0-999999999999999999999") <
                      SemanticVersion.Parse("1.0.0-1000000000000000000000"));
    }

    private static LoadedFixtureHandle LoadedFixture()
    {
        var workspace = new TestWorkspace();
        try
        {
            var runtime = workspace.CreateDirectory("runtime");
            var package = new PetPackValidator().ValidateAndExtract(FixturePath, runtime).Package;
            return new(workspace, package);
        }
        catch
        {
            workspace.Dispose();
            throw;
        }
    }

    private static string StageInterruptedUninstall(
        string root, InstalledPet installed, bool registryKeepsPet)
    {
        var transaction = Path.Combine(root, "staging", $"uninstall-interrupted-{Guid.NewGuid():N}");
        Directory.CreateDirectory(transaction);
        var record = new JsonObject
        {
            ["packageId"] = installed.PackageId,
            ["petId"] = installed.PetId,
            ["displayName"] = installed.DisplayName,
            ["species"] = installed.Species,
            ["contentVersion"] = installed.ContentVersion.Value,
            ["archiveSha256"] = installed.ArchiveSha256,
            ["archiveBytes"] = installed.ArchiveBytes,
        };
        var journal = new JsonObject
        {
            ["formatVersion"] = 1,
            ["records"] = new JsonArray(record),
        };
        File.WriteAllText(Path.Combine(transaction, "transaction.json"), journal.ToJsonString());
        foreach (var component in new[] { "library", "cache" })
        {
            var source = Path.Combine(root, component, installed.PackageId, installed.ContentVersion.Value);
            var destination = Path.Combine(
                transaction, component, installed.PackageId, installed.ContentVersion.Value);
            Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
            Directory.Move(source, destination);
        }
        if (!registryKeepsPet)
        {
            File.WriteAllText(Path.Combine(root, "registry.json"),
                new JsonObject
                {
                    ["formatVersion"] = 1,
                    ["packages"] = new JsonArray(),
                }.ToJsonString());
        }
        return transaction;
    }

    private const int RegularFileAttributes = unchecked((int)(0x81A4u << 16));
    private const int SymlinkAttributes = unchecked((int)(0xA1FFu << 16));

    private static void WriteArchiveWithExtra(TestWorkspace workspace, string output, string extraPath,
        byte[] extraData, int externalAttributes)
    {
        var extracted = workspace.CreateDirectory($"archive-{Guid.NewGuid():N}");
        ZipFile.ExtractToDirectory(FixturePath, extracted);
        using (var archive = ZipFile.Open(output, ZipArchiveMode.Create))
        {
            foreach (var path in Directory.EnumerateFiles(extracted, "*", SearchOption.AllDirectories)
                         .Order(StringComparer.Ordinal))
            {
                var relative = Path.GetRelativePath(extracted, path).Replace(Path.DirectorySeparatorChar, '/');
                var entry = archive.CreateEntry(relative, CompressionLevel.NoCompression);
                entry.ExternalAttributes = RegularFileAttributes;
                using var input = File.OpenRead(path);
                using var target = entry.Open();
                input.CopyTo(target);
            }
            var extra = archive.CreateEntry(extraPath, CompressionLevel.NoCompression);
            extra.ExternalAttributes = externalAttributes;
            using var stream = extra.Open();
            stream.Write(extraData);
        }
        ForceLastCentralEntryUnixHost(output);
    }

    private static void ForceLastCentralEntryUnixHost(string archivePath)
    {
        var bytes = File.ReadAllBytes(archivePath);
        byte[] eocdSignature = [0x50, 0x4b, 0x05, 0x06];
        var eocdOffset = bytes.AsSpan().LastIndexOf(eocdSignature);
        if (eocdOffset < 0 || eocdOffset + 22 != bytes.Length)
        {
            throw new InvalidDataException("test archive has no canonical ZIP end record");
        }
        var entryCount = BinaryPrimitives.ReadUInt16LittleEndian(bytes.AsSpan(eocdOffset + 10));
        var cursor = checked((int)BinaryPrimitives.ReadUInt32LittleEndian(bytes.AsSpan(eocdOffset + 16)));
        for (var index = 0; index < entryCount; index++)
        {
            if (BinaryPrimitives.ReadUInt32LittleEndian(bytes.AsSpan(cursor)) != 0x02014b50)
            {
                throw new InvalidDataException("test archive central directory is invalid");
            }
            if (index == entryCount - 1)
            {
                var versionMadeBy = BinaryPrimitives.ReadUInt16LittleEndian(bytes.AsSpan(cursor + 4));
                versionMadeBy = (ushort)((versionMadeBy & 0x00ff) | (3 << 8));
                BinaryPrimitives.WriteUInt16LittleEndian(bytes.AsSpan(cursor + 4), versionMadeBy);
            }
            var nameLength = BinaryPrimitives.ReadUInt16LittleEndian(bytes.AsSpan(cursor + 28));
            var extraLength = BinaryPrimitives.ReadUInt16LittleEndian(bytes.AsSpan(cursor + 30));
            var commentLength = BinaryPrimitives.ReadUInt16LittleEndian(bytes.AsSpan(cursor + 32));
            cursor = checked(cursor + 46 + nameLength + extraLength + commentLength);
        }
        File.WriteAllBytes(archivePath, bytes);
    }

    private static void RewriteIntegrity(string extractedRoot)
    {
        var files = new JsonArray();
        foreach (var path in Directory.EnumerateFiles(extractedRoot, "*", SearchOption.AllDirectories)
                     .Where(path => Path.GetFileName(path) != "integrity.json")
                     .Order(StringComparer.Ordinal))
        {
            var relative = Path.GetRelativePath(extractedRoot, path).Replace(Path.DirectorySeparatorChar, '/');
            var bytes = File.ReadAllBytes(path);
            files.Add(new JsonObject
            {
                ["bytes"] = bytes.LongLength,
                ["mediaType"] = relative.EndsWith(".json", StringComparison.Ordinal)
                    ? "application/json"
                    : "application/vnd.petsgraph.rgba8",
                ["path"] = relative,
                ["sha256"] = Convert.ToHexStringLower(SHA256.HashData(bytes)),
            });
        }
        var integrity = new JsonObject
        {
            ["algorithm"] = "sha256",
            ["files"] = files,
            ["formatVersion"] = "1.0.0",
        };
        File.WriteAllText(Path.Combine(extractedRoot, "integrity.json"),
            integrity.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
    }

    private sealed class LoadedFixtureHandle(TestWorkspace workspace, LoadedPetPack value) : IDisposable
    {
        public LoadedPetPack Value { get; } = value;
        public void Dispose() => workspace.Dispose();
    }

    private sealed class TestWorkspace : IDisposable
    {
        public TestWorkspace()
        {
            Root = Path.Combine(Path.GetTempPath(), $"petsgraph-tests-{Guid.NewGuid():N}");
            Directory.CreateDirectory(Root);
        }

        public string Root { get; }
        public string PathFor(string name) => Path.Combine(Root, name);

        public string CreateDirectory(string name)
        {
            var path = PathFor(name);
            Directory.CreateDirectory(path);
            return path;
        }

        public void Dispose()
        {
            if (Directory.Exists(Root))
            {
                Directory.Delete(Root, recursive: true);
            }
        }
    }
}
