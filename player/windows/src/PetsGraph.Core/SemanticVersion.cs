using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace PetsGraph.Core;

[JsonConverter(typeof(SemanticVersionJsonConverter))]
public sealed partial class SemanticVersion : IComparable<SemanticVersion>, IEquatable<SemanticVersion>
{
    private static readonly Regex Pattern = VersionPattern();

    private SemanticVersion(int major, int minor, int patch, string[] preRelease, string? build, string value)
    {
        Major = major;
        Minor = minor;
        Patch = patch;
        PreRelease = preRelease;
        Build = build;
        Value = value;
    }

    public int Major { get; }
    public int Minor { get; }
    public int Patch { get; }
    public IReadOnlyList<string> PreRelease { get; }
    public string? Build { get; }
    public string Value { get; }

    public static SemanticVersion Parse(string value)
    {
        var match = Pattern.Match(value);
        if (value.Length is < 1 or > 80 || !match.Success ||
            !int.TryParse(match.Groups["major"].Value, NumberStyles.None, CultureInfo.InvariantCulture, out var major) ||
            !int.TryParse(match.Groups["minor"].Value, NumberStyles.None, CultureInfo.InvariantCulture, out var minor) ||
            !int.TryParse(match.Groups["patch"].Value, NumberStyles.None, CultureInfo.InvariantCulture, out var patch))
        {
            throw new PetPackException("invalid_version", "contentVersion is not valid semantic versioning");
        }

        var preRelease = match.Groups["pre"].Success
            ? match.Groups["pre"].Value.Split('.', StringSplitOptions.None)
            : [];
        if (preRelease.Any(static part =>
                part.Length == 0 ||
                (part.All(char.IsDigit) && part.Length > 1 && part[0] == '0')))
        {
            throw new PetPackException("invalid_version", "contentVersion prerelease is invalid");
        }

        return new(major, minor, patch, preRelease,
            match.Groups["build"].Success ? match.Groups["build"].Value : null, value);
    }

    public int CompareTo(SemanticVersion? other)
    {
        if (other is null)
        {
            return 1;
        }
        var result = Major.CompareTo(other.Major);
        if (result == 0)
        {
            result = Minor.CompareTo(other.Minor);
        }
        if (result == 0)
        {
            result = Patch.CompareTo(other.Patch);
        }
        if (result != 0)
        {
            return result;
        }
        if (PreRelease.Count == 0 || other.PreRelease.Count == 0)
        {
            return PreRelease.Count == other.PreRelease.Count ? 0 : PreRelease.Count == 0 ? 1 : -1;
        }
        for (var index = 0; index < Math.Min(PreRelease.Count, other.PreRelease.Count); index++)
        {
            var left = PreRelease[index];
            var right = other.PreRelease[index];
            var leftNumeric = left.All(char.IsAsciiDigit);
            var rightNumeric = right.All(char.IsAsciiDigit);
            result = leftNumeric && rightNumeric
                ? left.Length != right.Length
                    ? left.Length.CompareTo(right.Length)
                    : string.CompareOrdinal(left, right)
                : leftNumeric != rightNumeric
                    ? leftNumeric ? -1 : 1
                    : string.CompareOrdinal(left, right);
            if (result != 0)
            {
                return result;
            }
        }
        return PreRelease.Count.CompareTo(other.PreRelease.Count);
    }

    public override string ToString() => Value;

    public bool Equals(SemanticVersion? other) => other is not null && CompareTo(other) == 0;

    public override bool Equals(object? obj) => obj is SemanticVersion other && Equals(other);

    public override int GetHashCode()
    {
        var hash = new HashCode();
        hash.Add(Major);
        hash.Add(Minor);
        hash.Add(Patch);
        foreach (var part in PreRelease)
        {
            hash.Add(part, StringComparer.Ordinal);
        }
        return hash.ToHashCode();
    }

    public static bool operator <(SemanticVersion left, SemanticVersion right) => left.CompareTo(right) < 0;
    public static bool operator >(SemanticVersion left, SemanticVersion right) => left.CompareTo(right) > 0;
    public static bool operator <=(SemanticVersion left, SemanticVersion right) => left.CompareTo(right) <= 0;
    public static bool operator >=(SemanticVersion left, SemanticVersion right) => left.CompareTo(right) >= 0;
    public static bool operator ==(SemanticVersion? left, SemanticVersion? right) =>
        ReferenceEquals(left, right) || left?.Equals(right) == true;
    public static bool operator !=(SemanticVersion? left, SemanticVersion? right) => !(left == right);

    [GeneratedRegex(
        "^(?<major>0|[1-9][0-9]*)\\.(?<minor>0|[1-9][0-9]*)\\.(?<patch>0|[1-9][0-9]*)(?:-(?<pre>[0-9A-Za-z-]+(?:\\.[0-9A-Za-z-]+)*))?(?:\\+(?<build>[0-9A-Za-z-]+(?:\\.[0-9A-Za-z-]+)*))?$",
        RegexOptions.CultureInvariant)]
    private static partial Regex VersionPattern();
}

public sealed class SemanticVersionJsonConverter : JsonConverter<SemanticVersion>
{
    public override SemanticVersion Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        if (reader.TokenType != JsonTokenType.String)
        {
            throw new JsonException("semantic version must be a string");
        }
        try
        {
            return SemanticVersion.Parse(reader.GetString() ?? "");
        }
        catch (PetPackException exception)
        {
            throw new JsonException(exception.Detail, exception);
        }
    }

    public override void Write(Utf8JsonWriter writer, SemanticVersion value, JsonSerializerOptions options) =>
        writer.WriteStringValue(value.Value);
}
