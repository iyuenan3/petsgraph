using System.IO;
using System.Text.Json;

namespace PetsGraph.App.Runtime;

internal sealed record PetSettings
{
    public bool Visible { get; set; } = true;
    public double Scale { get; set; } = 1;
    public double? Left { get; set; }
    public double? Top { get; set; }
}

internal sealed record AppSettings
{
    public Dictionary<string, PetSettings> Pets { get; init; } = new(StringComparer.Ordinal);
}

internal sealed class SettingsStore
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true,
    };

    private readonly string path = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "PetsGraph",
        "settings.json");

    public AppSettings Load()
    {
        try
        {
            return File.Exists(path)
                ? JsonSerializer.Deserialize<AppSettings>(File.ReadAllBytes(path), JsonOptions) ?? new()
                : new();
        }
        catch (IOException)
        {
            return new();
        }
        catch (JsonException)
        {
            return new();
        }
    }

    public void Save(AppSettings settings)
    {
        var directory = Path.GetDirectoryName(path)!;
        Directory.CreateDirectory(directory);
        var temporaryPath = Path.Combine(directory, $"settings-{Guid.NewGuid():N}.tmp");
        try
        {
            File.WriteAllBytes(temporaryPath, JsonSerializer.SerializeToUtf8Bytes(settings, JsonOptions));
            File.Move(temporaryPath, path, overwrite: true);
        }
        finally
        {
            if (File.Exists(temporaryPath))
            {
                File.Delete(temporaryPath);
            }
        }
    }
}
