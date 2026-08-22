using System.Security.Cryptography;
using System.Text;
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

    private sealed record UninstallTransaction
    {
        public required int FormatVersion { get; init; }
        public required InstalledPet[] Records { get; init; }
    }

    private sealed record ImportTransaction
    {
        public required int FormatVersion { get; init; }
        public required InstalledPet Current { get; init; }
        public InstalledPet? Previous { get; init; }
    }

    private readonly object sync = new();
    private readonly PetPackValidator validator = new();
    private readonly string libraryRoot;
    private readonly string cacheRoot;
    private readonly string stagingRoot;
    private readonly string registryPath;
    private readonly string pendingImportPath;

    public CanonicalPetLibrary(string? root = null)
    {
        Root = Path.GetFullPath(root ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "PetsGraph"));
        libraryRoot = Path.Combine(Root, "library");
        cacheRoot = Path.Combine(Root, "cache");
        stagingRoot = Path.Combine(Root, "staging");
        registryPath = Path.Combine(Root, "registry.json");
        pendingImportPath = Path.Combine(Root, "pending-import.json");
        Directory.CreateDirectory(libraryRoot);
        Directory.CreateDirectory(cacheRoot);
        Directory.CreateDirectory(stagingRoot);
        RecoverUninstallTransactions();
        RecoverImportTransaction();
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
            if (File.Exists(pendingImportPath) || Directory.Exists(pendingImportPath))
            {
                throw Invalid("import_pending", "a previous PetPack import is awaiting commit");
            }
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
                var reusedArchive = false;
                var reusedRuntime = false;
                if (File.Exists(finalArchive))
                {
                    var existing = new FileInfo(finalArchive);
                    if (existing.Length != proposed.ArchiveBytes ||
                        PetPackValidator.HashFile(finalArchive) != proposed.ArchiveSha256)
                    {
                        throw Invalid("managed_conflict", "unregistered canonical archive has different bytes");
                    }
                    reusedArchive = true;
                }
                if (Directory.Exists(finalRuntime))
                {
                    try
                    {
                        var existing = validator.LoadTrustedRuntime(
                            finalRuntime, proposed.ArchiveSha256, proposed.ArchiveBytes);
                        reusedRuntime = existing.Report.PackageId == proposed.PackageId &&
                            existing.Report.ContentVersion == proposed.ContentVersion;
                        if (!reusedRuntime)
                        {
                            Directory.Delete(finalRuntime, recursive: true);
                        }
                    }
                    catch (Exception exception) when (exception is PetPackException or IOException or UnauthorizedAccessException)
                    {
                        Directory.Delete(finalRuntime, recursive: true);
                    }
                }
                if (!reusedArchive)
                {
                    File.Move(stagedArchive, finalArchive);
                }
                try
                {
                    if (!reusedRuntime)
                    {
                        Directory.Move(stagedRuntime, finalRuntime);
                    }
                }
                catch
                {
                    if (!reusedArchive)
                    {
                        TryDeleteFile(finalArchive);
                    }
                    throw;
                }

                var next = registry.Packages.Where(pet => pet.PackageId != proposed.PackageId)
                    .Append(proposed).OrderBy(static pet => pet.PackageId, StringComparer.Ordinal).ToArray();
                try
                {
                    WriteImportTransaction(new ImportTransaction
                    {
                        FormatVersion = 1,
                        Current = proposed,
                        Previous = current,
                    });
                    WriteRegistry(new Registry { FormatVersion = 1, Packages = next });
                }
                catch
                {
                    TryDeleteFile(pendingImportPath);
                    if (!reusedArchive)
                    {
                        TryDeleteFile(finalArchive);
                    }
                    if (!reusedRuntime)
                    {
                        TryDeleteDirectory(finalRuntime);
                    }
                    throw;
                }
                if (current is not null)
                {
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
            var transaction = StageManagedFiles([current]);
            WriteRegistry(new Registry
            {
                FormatVersion = 1,
                Packages = registry.Packages.Where(pet => pet.PackageId != packageId).ToArray(),
            }, transaction);
            Finish(transaction);
            return current;
        }
    }

    public IReadOnlyList<InstalledPet> UninstallAll()
    {
        lock (sync)
        {
            var current = ReadRegistry().Packages;
            if (current.Length == 0)
            {
                return [];
            }
            var transaction = StageManagedFiles(current);
            WriteRegistry(new Registry { FormatVersion = 1, Packages = [] }, transaction);
            Finish(transaction);
            return current;
        }
    }

    public void DiscardObsolete(IEnumerable<InstalledPet> records)
    {
        lock (sync)
        {
            var installed = ReadRegistry().Packages;
            var obsolete = records.Where(record =>
                !installed.Any(current => SameInstalledPet(current, record))).ToArray();
            if (obsolete.Length != 0)
            {
                Finish(StageManagedFiles(obsolete));
            }
        }
    }

    public void CommitImport(PetImportOutcome outcome)
    {
        if (outcome.Result is not (PetImportResult.Installed or PetImportResult.Updated))
        {
            return;
        }
        lock (sync)
        {
            var transaction = ReadImportTransaction();
            var registered = ReadRegistry().Packages.SingleOrDefault(
                pet => pet.PackageId == outcome.Current.PackageId);
            if (!SameInstalledPet(transaction.Current, outcome.Current) ||
                !SameInstalledPet(registered, outcome.Current))
            {
                throw Invalid("import_commit_conflict",
                    "installed-pet registry changed before import commit");
            }
            File.Delete(pendingImportPath);
        }
    }

    public void RollbackImport(PetImportOutcome outcome)
    {
        if (outcome.Result is not (PetImportResult.Installed or PetImportResult.Updated))
        {
            return;
        }
        lock (sync)
        {
            var current = outcome.Current;
            var previous = outcome.Result == PetImportResult.Updated ? outcome.Previous : null;
            RollbackImported(current, previous);
            ClearImportTransaction(current);
        }
    }

    private void RollbackImported(InstalledPet current, InstalledPet? previous)
    {
        var registry = ReadRegistry();
        if (!SameInstalledPet(
                registry.Packages.SingleOrDefault(pet => pet.PackageId == current.PackageId), current))
        {
            throw Invalid("import_rollback_conflict",
                "installed-pet registry changed before import rollback");
        }
        if (previous is not null)
        {
            if (previous.PackageId != current.PackageId || previous.ContentVersion >= current.ContentVersion)
            {
                throw Invalid("import_rollback_conflict", "import rollback identity is invalid");
            }
            _ = Load(previous);
        }

        var transaction = StageManagedFiles([current]);
        var next = registry.Packages.Where(pet => pet.PackageId != current.PackageId);
        if (previous is not null)
        {
            next = next.Append(previous);
        }
        WriteRegistry(new Registry { FormatVersion = 1, Packages = next.ToArray() }, transaction);
        Finish(transaction);
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
            if (Directory.Exists(registryPath))
            {
                throw Invalid("registry_corrupt", "installed-pet registry is not a regular file");
            }
            return new Registry { FormatVersion = 1, Packages = [] };
        }
        var registry = StrictJson.DecodeFile<Registry>(registryPath, "registry.json");
        if (registry.FormatVersion != 1 ||
            registry.Packages.Select(static pet => pet.PackageId).Distinct(StringComparer.Ordinal).Count() !=
            registry.Packages.Length || registry.Packages.Any(static pet => !IsValidInstalledPet(pet)))
        {
            throw Invalid("registry_corrupt", "installed-pet registry is invalid");
        }
        return registry;
    }

    private void WriteImportTransaction(ImportTransaction transaction)
    {
        if (File.Exists(pendingImportPath) || Directory.Exists(pendingImportPath))
        {
            throw Invalid("import_pending", "a previous PetPack import is awaiting commit");
        }
        var temporary = Path.Combine(Root, $"pending-import-{Guid.NewGuid():N}.tmp");
        try
        {
            var data = JsonSerializer.SerializeToUtf8Bytes(transaction, StrictJson.WriteOptions);
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None,
                       bufferSize: 64 * 1024, FileOptions.WriteThrough))
            {
                stream.Write(data);
                stream.Flush(flushToDisk: true);
            }
            File.Move(temporary, pendingImportPath);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or JsonException)
        {
            throw new PetPackException("import_journal_failed",
                "PetPack import journal could not be created", exception);
        }
        finally
        {
            TryDeleteFile(temporary);
        }
    }

    private ImportTransaction ReadImportTransaction()
    {
        if (!File.Exists(pendingImportPath))
        {
            throw Invalid("import_journal_missing", "PetPack import journal is missing");
        }
        var transaction = StrictJson.DecodeFile<ImportTransaction>(pendingImportPath, "pending-import.json");
        if (transaction.FormatVersion != 1 || !IsValidInstalledPet(transaction.Current) ||
            transaction.Previous is { } previous &&
            (!IsValidInstalledPet(previous) || previous.PackageId != transaction.Current.PackageId ||
             previous.ContentVersion >= transaction.Current.ContentVersion))
        {
            throw Invalid("import_recovery_failed", "PetPack import journal is invalid");
        }
        return transaction;
    }

    private void ClearImportTransaction(InstalledPet expectedCurrent)
    {
        if (!File.Exists(pendingImportPath))
        {
            return;
        }
        if (!SameInstalledPet(ReadImportTransaction().Current, expectedCurrent))
        {
            throw Invalid("import_recovery_failed", "PetPack import journal changed");
        }
        File.Delete(pendingImportPath);
    }

    private void WriteRegistry(Registry registry, string? rollbackTransaction = null)
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
            if (rollbackTransaction is not null)
            {
                try
                {
                    Rollback(rollbackTransaction);
                }
                catch (Exception rollbackException) when (rollbackException is IOException or UnauthorizedAccessException)
                {
                    throw new PetPackException("uninstall_recovery_failed",
                        "registry update failed and managed pet files could not be restored", rollbackException);
                }
            }
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

    private string StageManagedFiles(IReadOnlyCollection<InstalledPet> records)
    {
        var transaction = Path.Combine(stagingRoot, $"uninstall-{Guid.NewGuid():N}");
        Directory.CreateDirectory(transaction);
        var journal = new UninstallTransaction { FormatVersion = 1, Records = records.ToArray() };
        try
        {
            File.WriteAllBytes(Path.Combine(transaction, "transaction.json"),
                JsonSerializer.SerializeToUtf8Bytes(journal, StrictJson.WriteOptions));
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or JsonException)
        {
            Finish(transaction);
            throw new PetPackException("uninstall_stage_failed",
                "managed pet removal journal could not be created", exception);
        }
        try
        {
            foreach (var record in records)
            {
                MoveManagedVersion(Path.GetDirectoryName(ArchivePath(record))!,
                    Path.Combine(transaction, "library", record.PackageId, record.ContentVersion.Value));
                MoveManagedVersion(Path.GetDirectoryName(RuntimePath(record))!,
                    Path.Combine(transaction, "cache", record.PackageId, record.ContentVersion.Value));
            }
            return transaction;
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            try
            {
                Rollback(transaction);
            }
            catch (Exception rollbackException) when (rollbackException is IOException or UnauthorizedAccessException)
            {
                throw new PetPackException("uninstall_recovery_failed",
                    "managed pet files could not be restored after staging failed", rollbackException);
            }
            throw new PetPackException("uninstall_stage_failed",
                "managed pet files could not be prepared for removal", exception);
        }
    }

    private static void MoveManagedVersion(string source, string destination)
    {
        if (!Directory.Exists(source))
        {
            return;
        }
        Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
        Directory.Move(source, destination);
        DeleteIfEmpty(Path.GetDirectoryName(source)!);
    }

    private void Rollback(string transaction)
    {
        var journal = StrictJson.DecodeFile<UninstallTransaction>(
            Path.Combine(transaction, "transaction.json"), "uninstall transaction");
        foreach (var record in journal.Records.Reverse())
        {
            RestoreManagedVersion(
                Path.Combine(transaction, "library", record.PackageId, record.ContentVersion.Value),
                Path.GetDirectoryName(ArchivePath(record))!);
            RestoreManagedVersion(
                Path.Combine(transaction, "cache", record.PackageId, record.ContentVersion.Value),
                Path.GetDirectoryName(RuntimePath(record))!);
        }
        Directory.Delete(transaction, recursive: true);
    }

    private static void RestoreManagedVersion(string source, string destination)
    {
        if (!Directory.Exists(source))
        {
            return;
        }
        if (Directory.Exists(destination))
        {
            throw new IOException("managed pet recovery target already exists");
        }
        Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
        Directory.Move(source, destination);
    }

    private void RecoverUninstallTransactions()
    {
        var installed = ReadRegistry().Packages;
        foreach (var transaction in Directory.EnumerateDirectories(stagingRoot, "uninstall-*"))
        {
            var journalPath = Path.Combine(transaction, "transaction.json");
            if (!File.Exists(journalPath))
            {
                Finish(transaction);
                continue;
            }
            var journal = StrictJson.DecodeFile<UninstallTransaction>(journalPath, "uninstall transaction");
            if (journal.FormatVersion != 1)
            {
                throw Invalid("uninstall_recovery_failed", "unsupported uninstall recovery record");
            }
            var stillInstalled = journal.Records.Count(record =>
                installed.Any(current => SameInstalledPet(current, record)));
            if (stillInstalled == journal.Records.Length)
            {
                Rollback(transaction);
            }
            else if (stillInstalled == 0)
            {
                Finish(transaction);
            }
            else
            {
                throw Invalid("uninstall_recovery_failed", "partial uninstall registry state");
            }
        }
    }

    private void RecoverImportTransaction()
    {
        if (!File.Exists(pendingImportPath))
        {
            if (Directory.Exists(pendingImportPath))
            {
                throw Invalid("import_recovery_failed", "PetPack import journal is not a regular file");
            }
            return;
        }
        var transaction = ReadImportTransaction();
        var registered = ReadRegistry().Packages.SingleOrDefault(
            pet => pet.PackageId == transaction.Current.PackageId);
        if (SameInstalledPet(registered, transaction.Current))
        {
            RollbackImported(transaction.Current, transaction.Previous);
        }
        else
        {
            if (!SameInstalledPet(registered, transaction.Previous))
            {
                throw Invalid("import_recovery_failed",
                    "installed-pet registry conflicts with import recovery");
            }
            Finish(StageManagedFiles([transaction.Current]));
        }
        ClearImportTransaction(transaction.Current);
    }

    private static void Finish(string transaction) => TryDeleteDirectory(transaction);

    private static bool IsValidDisplayName(string value) =>
        value.Length is >= 1 and <= 80 &&
        value.IsNormalized(NormalizationForm.FormC) &&
        !value.Any(char.IsControl);

    private static bool IsValidInstalledPet(InstalledPet pet) =>
        PackageIdPattern().IsMatch(pet.PackageId) && pet.PackageId.Length <= 80 &&
        pet.PackageId == pet.PetId && IsValidDisplayName(pet.DisplayName) &&
        pet.Species is "cat" or "dog" &&
        pet.ArchiveBytes is > 0 and <= SafeZipArchive.MaximumArchiveBytes &&
        Sha256Pattern().IsMatch(pet.ArchiveSha256);

    private static bool SameInstalledPet(InstalledPet? left, InstalledPet? right) =>
        left is null && right is null || left is not null && right is not null &&
        left.PackageId == right.PackageId && left.PetId == right.PetId &&
        left.DisplayName == right.DisplayName && left.Species == right.Species &&
        left.ContentVersion.Value == right.ContentVersion.Value &&
        left.ArchiveSha256 == right.ArchiveSha256 && left.ArchiveBytes == right.ArchiveBytes;

    private static void DeleteIfEmpty(string path)
    {
        if (Directory.Exists(path) && !Directory.EnumerateFileSystemEntries(path).Any())
        {
            Directory.Delete(path);
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
