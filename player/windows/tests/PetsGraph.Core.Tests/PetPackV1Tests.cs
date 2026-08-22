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
    public void CanonicalLibraryOwnsCopyAndImportsIdempotently()
    {
        using var workspace = new TestWorkspace();
        var source = workspace.PathFor("owned.petpack");
        File.Copy(FixturePath, source);
        var library = new CanonicalPetLibrary(workspace.CreateDirectory("library-root"));

        var first = library.Import(source);
        File.Delete(source);
        var second = library.Import(FixturePath);
        var loaded = library.LoadInstalledPetPacks();

        Assert.AreEqual(PetImportResult.Installed, first.Result);
        Assert.AreEqual(PetImportResult.AlreadyInstalled, second.Result);
        Assert.HasCount(1, loaded);
        Assert.AreEqual("synthetic-cat-v1", loaded[0].Manifest.Package.Id);
    }

    [TestMethod]
    public void CanonicalLibraryRebuildsDeletedCache()
    {
        using var workspace = new TestWorkspace();
        var root = workspace.CreateDirectory("library-root");
        var library = new CanonicalPetLibrary(root);
        _ = library.Import(FixturePath);
        var cache = Path.Combine(root, "cache");
        Directory.Delete(cache, recursive: true);
        Directory.CreateDirectory(cache);

        var loaded = library.LoadInstalledPetPacks();

        Assert.HasCount(1, loaded);
        Assert.IsTrue(Directory.EnumerateFiles(cache, "manifest.json", SearchOption.AllDirectories).Any());
    }

    [TestMethod]
    public void CanonicalLibraryRejectsSameVersionWithDifferentBytes()
    {
        using var workspace = new TestWorkspace();
        var root = workspace.CreateDirectory("library-root");
        var library = new CanonicalPetLibrary(root);
        _ = library.Import(FixturePath);
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
        _ = library.Import(FixturePath);

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
        var library = new CanonicalPetLibrary(root);

        var exception = Assert.Throws<PetPackException>(() => library.InstalledPets());

        Assert.AreEqual("registry_corrupt", exception.Code);
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
    public void SemanticVersionOrderingFollowsPrereleaseRules()
    {
        Assert.IsTrue(SemanticVersion.Parse("1.0.0-alpha.1") < SemanticVersion.Parse("1.0.0"));
        Assert.IsTrue(SemanticVersion.Parse("1.0.0") < SemanticVersion.Parse("1.0.1"));
        Assert.AreEqual(SemanticVersion.Parse("1.0.0+one"), SemanticVersion.Parse("1.0.0+two"));
        Assert.Throws<PetPackException>(() => SemanticVersion.Parse($"1.0.0+{new string('a', 81)}"));
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
