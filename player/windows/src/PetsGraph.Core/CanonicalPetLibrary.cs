using System.Security.Cryptography;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace PetsGraph.Core;

public sealed record InstalledPet
{
    public required string PackageId { get; init; }
    public required string PetId { get; init; }
    public required string DisplayName { get; init; }
    public required string Species { get; init; }
    public required SemanticVersion ContentVersion { get; init; }
    public required string ArchiveSha256 { get; init; }
    public required long ArchiveBytes { get; init; }
}

public enum PetImportResult
{
    Installed,
    Updated,
    AlreadyInstalled,
    UpdateCancelled,
}

public sealed record PetImportOutcome(
    PetImportResult Result,
    InstalledPet Current,
    InstalledPet? Previous = null);

public sealed partial class CanonicalPetLibrary
{
    private sealed record Registry
    {
        public required int FormatVersion { get; init; }
        public required InstalledPet[] Packages { get; init; }
    }

    private readonly object sync = new();
    private readonly PetPackValidator validator = new();
    private readonly string libraryRoot;
    private readonly string cacheRoot;
    private readonly string stagingRoot;
    private readonly string registryPath;

    public CanonicalPetLibrary(string? root = null)
    {
        Root = Path.GetFullPath(root ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "PetsGraph"));
        libraryRoot = Path.Combine(Root, "library");
        cacheRoot = Path.Combine(Root, "cache");
        stagingRoot = Path.Combine(Root, "staging");
        registryPath = Path.Combine(Root, "registry.json");
        Directory.CreateDirectory(libraryRoot);
        Directory.CreateDirectory(cacheRoot);
        Directory.CreateDirectory(stagingRoot);
    }

    public string Root { get; }

    public IReadOnlyList<InstalledPet> InstalledPets()
    {
        lock (sync)
        {
            return ReadRegistry().Packages.OrderBy(static pet => pet.PackageId, StringComparer.Ordinal).ToArray();
        }
    }

    public PetImportOutcome Import(string sourcePath,
        Func<InstalledPet, InstalledPet, bool>? confirmUpdate = null)
    {
        lock (sync)
        {
            var source = Path.GetFullPath(sourcePath);
            if (!File.Exists(source) || (File.GetAttributes(source) & FileAttributes.ReparsePoint) != 0)
            {
                throw Invalid("import_source", "selected PetPack is missing or is a reparse point");
            }
            var stage = Path.Combine(stagingRoot, Guid.NewGuid().ToString("N"));
            var stagedArchive = Path.Combine(stage, "source.petpack");
            var stagedRuntime = Path.Combine(stage, "runtime");
            Directory.CreateDirectory(stagedRuntime);
            try
            {
                File.Copy(source, stagedArchive, overwrite: false);
                var validated = validator.ValidateAndExtract(stagedArchive, stagedRuntime);
                var proposed = ToInstalled(validated);
                var registry = ReadRegistry();
                var current = registry.Packages.SingleOrDefault(pet => pet.PackageId == proposed.PackageId);
                if (current is not null)
                {
                    var comparison = proposed.ContentVersion.CompareTo(current.ContentVersion);
                    if (comparison == 0)
                    {
                        if (!string.Equals(current.ArchiveSha256, proposed.ArchiveSha256, StringComparison.Ordinal))
                        {
                            throw Invalid("version_conflict",
                                "the same package id and content version have different bytes");
                        }
                        return new(PetImportResult.AlreadyInstalled, current);
                    }
                    if (comparison < 0)
                    {
                        throw Invalid("downgrade_rejected", "installing an older content version is not allowed");
                    }
                    if (confirmUpdate is null || !confirmUpdate(current, proposed))
                    {
                        return new(PetImportResult.UpdateCancelled, current, proposed);
                    }
                }

                var finalArchive = ArchivePath(proposed);
                var finalRuntime = RuntimePath(proposed);
                Directory.CreateDirectory(Path.GetDirectoryName(finalArchive)!);
                Directory.CreateDirectory(Path.GetDirectoryName(finalRuntime)!);
                if (File.Exists(finalArchive) || Directory.Exists(finalRuntime))
                {
                    throw Invalid("managed_conflict", "managed library target already exists outside the registry");
                }
                File.Move(stagedArchive, finalArchive);
                try
                {
                    Directory.Move(stagedRuntime, finalRuntime);
                }
                catch
                {
                    TryDeleteFile(finalArchive);
                    throw;
                }

                var next = registry.Packages.Where(pet => pet.PackageId != proposed.PackageId)
                    .Append(proposed).OrderBy(static pet => pet.PackageId, StringComparer.Ordinal).ToArray();
                try
                {
                    WriteRegistry(new Registry { FormatVersion = 1, Packages = next });
                }
                catch
                {
                    TryDeleteFile(finalArchive);
                    TryDeleteDirectory(finalRuntime);
                    throw;
                }
                if (current is not null)
                {
                    RemoveManagedFiles(current);
                    return new(PetImportResult.Updated, proposed, current);
                }
                return new(PetImportResult.Installed, proposed);
            }
            catch (PetPackException)
            {
                throw;
            }
            catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or JsonException)
            {
                throw new PetPackException("import_failed", "selected PetPack could not be imported", exception);
            }
            finally
            {
                TryDeleteDirectory(stage);
            }
        }
    }

    public IReadOnlyList<LoadedPetPack> LoadInstalledPetPacks()
    {
        lock (sync)
        {
            return ReadRegistry().Packages.OrderBy(static pet => pet.PackageId, StringComparer.Ordinal)
                .Select(Load).ToArray();
        }
    }

    public InstalledPet? Uninstall(string packageId)
    {
        lock (sync)
        {
            var registry = ReadRegistry();
            var current = registry.Packages.SingleOrDefault(pet => pet.PackageId == packageId);
            if (current is null)
            {
                return null;
            }
            WriteRegistry(new Registry
            {
                FormatVersion = 1,
                Packages = registry.Packages.Where(pet => pet.PackageId != packageId).ToArray(),
            });
            RemoveManagedFiles(current);
            return current;
        }
    }

    public IReadOnlyList<InstalledPet> UninstallAll()
    {
        lock (sync)
        {
            var current = ReadRegistry().Packages;
            WriteRegistry(new Registry { FormatVersion = 1, Packages = [] });
            foreach (var pet in current)
            {
                RemoveManagedFiles(pet);
            }
            return current;
        }
    }

    private LoadedPetPack Load(InstalledPet record)
    {
        var runtime = RuntimePath(record);
        try
        {
            return validator.LoadTrustedRuntime(runtime, record.ArchiveSha256, record.ArchiveBytes).Package;
        }
        catch (Exception exception) when (exception is PetPackException or IOException or UnauthorizedAccessException)
        {
            var archive = ArchivePath(record);
            if (!File.Exists(archive) || new FileInfo(archive).Length != record.ArchiveBytes ||
                PetPackValidator.HashFile(archive) != record.ArchiveSha256)
            {
                throw Invalid("canonical_missing", "internal canonical PetPack is missing or changed");
            }
            var stage = Path.Combine(stagingRoot, Guid.NewGuid().ToString("N"));
            var stagedRuntime = Path.Combine(stage, "runtime");
            Directory.CreateDirectory(stagedRuntime);
            try
            {
                var rebuilt = validator.ValidateAndExtract(archive, stagedRuntime);
                if (rebuilt.Report.PackageId != record.PackageId ||
                    rebuilt.Report.ContentVersion != record.ContentVersion ||
                    rebuilt.Report.ArchiveSha256 != record.ArchiveSha256)
                {
                    throw Invalid("canonical_mismatch", "internal canonical PetPack identity changed");
                }
                TryDeleteDirectory(runtime);
                Directory.CreateDirectory(Path.GetDirectoryName(runtime)!);
                Directory.Move(stagedRuntime, runtime);
                return rebuilt.Package with { RuntimeRoot = runtime };
            }
            finally
            {
                TryDeleteDirectory(stage);
            }
        }
    }

    private Registry ReadRegistry()
    {
        if (!File.Exists(registryPath))
        {
            return new Registry { FormatVersion = 1, Packages = [] };
        }
        var registry = StrictJson.DecodeFile<Registry>(registryPath, "registry.json");
        if (registry.FormatVersion != 1 ||
            registry.Packages.Select(static pet => pet.PackageId).Distinct(StringComparer.Ordinal).Count() !=
            registry.Packages.Length || registry.Packages.Any(static pet =>
                !PackageIdPattern().IsMatch(pet.PackageId) || pet.PackageId.Length > 80 ||
                pet.PackageId != pet.PetId || pet.DisplayName.Length is < 1 or > 80 ||
                pet.Species is not ("cat" or "dog") ||
                pet.ArchiveBytes is <= 0 or > SafeZipArchive.MaximumArchiveBytes ||
                !Sha256Pattern().IsMatch(pet.ArchiveSha256)))
        {
            throw Invalid("registry_corrupt", "installed-pet registry is invalid");
        }
        return registry;
    }

    private void WriteRegistry(Registry registry)
    {
        Directory.CreateDirectory(Root);
        var temporary = Path.Combine(Root, $"registry-{Guid.NewGuid():N}.tmp");
        try
        {
            var data = JsonSerializer.SerializeToUtf8Bytes(registry with
            {
                Packages = registry.Packages.OrderBy(static pet => pet.PackageId, StringComparer.Ordinal).ToArray(),
            }, StrictJson.WriteOptions);
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None,
                       bufferSize: 64 * 1024, FileOptions.WriteThrough))
            {
                stream.Write(data);
                stream.Flush(flushToDisk: true);
            }
            File.Move(temporary, registryPath, overwrite: true);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or JsonException)
        {
            throw new PetPackException("registry_write_failed", "installed-pet registry could not be updated", exception);
        }
        finally
        {
            TryDeleteFile(temporary);
        }
    }

    private string ArchivePath(InstalledPet record) => Path.Combine(libraryRoot, record.PackageId,
        record.ContentVersion.Value, $"{record.ArchiveSha256}.petpack");

    private string RuntimePath(InstalledPet record) => Path.Combine(cacheRoot, record.PackageId,
        record.ContentVersion.Value, record.ArchiveSha256);

    private static InstalledPet ToInstalled(ValidatedPetPack validated) => new()
    {
        PackageId = validated.Report.PackageId,
        PetId = validated.Report.PetId,
        DisplayName = validated.Report.DisplayName,
        Species = validated.Report.Species,
        ContentVersion = validated.Report.ContentVersion,
        ArchiveSha256 = validated.Report.ArchiveSha256,
        ArchiveBytes = validated.Report.ArchiveBytes,
    };

    private void RemoveManagedFiles(InstalledPet record)
    {
        var archiveVersion = Path.GetDirectoryName(ArchivePath(record))!;
        var cacheVersion = Path.GetDirectoryName(RuntimePath(record))!;
        TryDeleteDirectory(archiveVersion);
        TryDeleteDirectory(cacheVersion);
        TryDeleteIfEmpty(Path.GetDirectoryName(archiveVersion)!);
        TryDeleteIfEmpty(Path.GetDirectoryName(cacheVersion)!);
    }

    private static void TryDeleteIfEmpty(string path)
    {
        try
        {
            if (Directory.Exists(path) && !Directory.EnumerateFileSystemEntries(path).Any())
            {
                Directory.Delete(path);
            }
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }
    }

    private static void TryDeleteDirectory(string path)
    {
        try
        {
            if (Directory.Exists(path))
            {
                Directory.Delete(path, recursive: true);
            }
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }
    }

    private static void TryDeleteFile(string path)
    {
        try
        {
            File.Delete(path);
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }
    }

    private static PetPackException Invalid(string code, string detail) => new(code, detail);

    [GeneratedRegex("^[a-z0-9]+(?:-[a-z0-9]+)*$", RegexOptions.CultureInvariant)]
    private static partial Regex PackageIdPattern();

    [GeneratedRegex("^[0-9a-f]{64}$", RegexOptions.CultureInvariant)]
    private static partial Regex Sha256Pattern();
}
