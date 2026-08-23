namespace PetsGraph.Core;

public sealed record PlayerScaleOption(double Value, string Label);

public sealed record PetPlayerState
{
    public bool Visible { get; set; } = true;
    public double? AnchorX { get; set; }
    public double? AnchorY { get; set; }
}

public sealed record PlayerState
{
    public const int CurrentFormatVersion = 1;
    public static readonly PlayerScaleOption[] ScaleOptions =
    [
        new(0.5, "0.5"),
        new(0.75, "0.75"),
        new(1, "1.0"),
        new(1.25, "1.25"),
        new(1.5, "1.5"),
        new(1.75, "1.75"),
        new(2, "2.0"),
    ];
    public static readonly double[] AllowedScales = [.. ScaleOptions.Select(option => option.Value)];

    public int FormatVersion { get; set; } = CurrentFormatVersion;
    public double GlobalScale { get; set; } = 1;
    public Dictionary<string, PetPlayerState> Pets { get; init; } = new(StringComparer.Ordinal);

    public static double NormalizeScale(double value) => AllowedScales.Contains(value) ? value : 1;

    public static PetPlayerState MigratedLegacyPet(double? anchorX, double? anchorY) => new()
    {
        Visible = true,
        AnchorX = anchorX is { } x && double.IsFinite(x) ? x : null,
        AnchorY = anchorY is { } y && double.IsFinite(y) ? y : null,
    };

    public static PlayerState HiddenFailSafe(IEnumerable<string> packageIds)
    {
        var state = new PlayerState();
        foreach (var packageId in packageIds)
        {
            state.Pets[packageId] = new() { Visible = false };
        }
        return state;
    }
}
