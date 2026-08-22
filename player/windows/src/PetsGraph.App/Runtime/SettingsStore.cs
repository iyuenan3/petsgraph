using System.IO;
using System.Text.Json;
using PetsGraph.Core;

namespace PetsGraph.App.Runtime;

internal sealed class SettingsStore(string root)
{
    private readonly string path = Path.Combine(root, "settings.json");

    public PlayerState Load(IReadOnlyCollection<LoadedPetPack> packages)
    {
        if (!File.Exists(path))
        {
            return new();
        }
        try
        {
            var data = File.ReadAllBytes(path);
            try
            {
                var state = StrictJson.Decode<PlayerState>(data, "settings.json");
                if (state.FormatVersion == PlayerState.CurrentFormatVersion)
                {
                    return Normalize(state, packages);
                }
            }
            catch (PetPackException)
            {
            }
            return MigrateLegacy(data, packages);
        }
        catch (Exception exception) when (exception is IOException or JsonException)
        {
            return new();
        }
    }

    public void Save(PlayerState state)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var temporary = Path.Combine(Path.GetDirectoryName(path)!, $"settings-{Guid.NewGuid():N}.tmp");
        try
        {
            state.FormatVersion = PlayerState.CurrentFormatVersion;
            state.GlobalScale = PlayerState.NormalizeScale(state.GlobalScale);
            var data = JsonSerializer.SerializeToUtf8Bytes(state, StrictJson.WriteOptions);
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None,
                       bufferSize: 64 * 1024, FileOptions.WriteThrough))
            {
                stream.Write(data);
                stream.Flush(flushToDisk: true);
            }
            File.Move(temporary, path, overwrite: true);
        }
        finally
        {
            try
            {
                File.Delete(temporary);
            }
            catch (IOException)
            {
            }
            catch (UnauthorizedAccessException)
            {
            }
        }
    }

    private static PlayerState Normalize(PlayerState state, IReadOnlyCollection<LoadedPetPack> packages)
    {
        var validIds = packages.Select(static package => package.Manifest.Package.Id)
            .ToHashSet(StringComparer.Ordinal);
        state.GlobalScale = PlayerState.NormalizeScale(state.GlobalScale);
        foreach (var id in state.Pets.Keys.Where(id => !validIds.Contains(id)).ToArray())
        {
            state.Pets.Remove(id);
        }
        foreach (var pair in state.Pets)
        {
            if (pair.Value.AnchorX is { } x && !double.IsFinite(x))
            {
                pair.Value.AnchorX = null;
            }
            if (pair.Value.AnchorY is { } y && !double.IsFinite(y))
            {
                pair.Value.AnchorY = null;
            }
        }
        return state;
    }

    private static PlayerState MigrateLegacy(byte[] data, IReadOnlyCollection<LoadedPetPack> packages)
    {
        var state = new PlayerState();
        try
        {
            using var document = JsonDocument.Parse(data);
            var root = document.RootElement;
            if (root.TryGetProperty("scale", out var scale) && scale.TryGetDouble(out var value))
            {
                state.GlobalScale = PlayerState.NormalizeScale(value);
            }
            if (!root.TryGetProperty("pets", out var pets) || pets.ValueKind != JsonValueKind.Object)
            {
                return state;
            }
            foreach (var package in packages)
            {
                var id = package.Manifest.Package.Id;
                if (!pets.TryGetProperty(id, out var legacy) || legacy.ValueKind != JsonValueKind.Object)
                {
                    continue;
                }
                var canvas = package.Manifest.Stage.ReferenceCanvasPx;
                var pixelScale = package.Manifest.Stage.BaseDisplayHeight * state.GlobalScale / canvas[1];
                double? anchorX = null;
                double? anchorY = null;
                if (legacy.TryGetProperty("left", out var left) && left.TryGetDouble(out var oldLeft) &&
                    double.IsFinite(oldLeft))
                {
                    anchorX = oldLeft + canvas[0] * pixelScale / 2;
                }
                if (legacy.TryGetProperty("top", out var top) && top.TryGetDouble(out var oldTop) &&
                    double.IsFinite(oldTop))
                {
                    anchorY = oldTop + canvas[1] * pixelScale;
                }
                state.Pets[id] = PlayerState.MigratedLegacyPet(anchorX, anchorY);
            }
        }
        catch (JsonException)
        {
        }
        return state;
    }
}
