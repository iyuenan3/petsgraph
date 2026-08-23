using System.Reflection;

namespace PetsGraph.Core;

public sealed record PlayerAboutInfo(string? Version)
{
    public string VersionLine => string.IsNullOrWhiteSpace(Version)
        ? "开发版本"
        : $"版本 {Version.Trim()}";

    public static PlayerAboutInfo FromAssembly(Assembly assembly)
    {
        var informational = assembly
            .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?
            .InformationalVersion;
        var normalized = informational?.Split('+', 2)[0].Trim();
        if (string.IsNullOrWhiteSpace(normalized))
        {
            var version = assembly.GetName().Version;
            normalized = version is null ? null : $"{version.Major}.{version.Minor}.{version.Build}";
        }
        return new(normalized);
    }
}
