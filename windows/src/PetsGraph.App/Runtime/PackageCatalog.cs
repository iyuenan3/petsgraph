using System.IO;
using PetsGraph.Core;

namespace PetsGraph.App.Runtime;

internal static class PackageCatalog
{
    public static string ResolvePetsDirectory(string? explicitPath)
    {
        if (!string.IsNullOrWhiteSpace(explicitPath))
        {
            return Path.GetFullPath(explicitPath);
        }
        var configured = Environment.GetEnvironmentVariable("PETSGRAPH_PETS_DIR");
        return !string.IsNullOrWhiteSpace(configured)
            ? Path.GetFullPath(configured)
            : Path.Combine(AppContext.BaseDirectory, "Pets");
    }

    public static LoadedPetPackage[] LoadAll(string petsDirectory, bool verifyIntegrity)
    {
        var loader = new PetPackageLoader();
        var packages = PetPackageLoader.FindPackages(petsDirectory)
            .Select(path => loader.Load(path, verifyIntegrity))
            .OrderBy(package => OrderKey(package.Manifest.Pet.Id))
            .ThenBy(package => package.Manifest.Pet.Id, StringComparer.Ordinal)
            .ToArray();
        if (packages.Length == 0)
        {
            throw new DirectoryNotFoundException($"没有在 {petsDirectory} 找到 .petsgraph-pet 宠物包。");
        }
        if (packages.Select(package => package.Manifest.Pet.Id).Distinct(StringComparer.Ordinal).Count() != packages.Length)
        {
            throw new InvalidDataException("宠物包包含重复 pet id。");
        }
        return packages;
    }

    private static int OrderKey(string petId) => petId switch
    {
        "wubai" => 0,
        "feiliu" => 1,
        _ => 2,
    };
}
