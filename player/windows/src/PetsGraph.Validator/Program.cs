using System.Text;
using PetsGraph.Core;

Console.OutputEncoding = Encoding.UTF8;

if (args.Length is < 1 or > 2 || args[0] is "--help" or "-h")
{
    Console.WriteLine("Usage: PetsGraph.Validator <pets-directory> [--verify-integrity]");
    return args.Length > 0 && args[0] is "--help" or "-h" ? 0 : 2;
}

var petsDirectory = Path.GetFullPath(args[0]);
var verifyIntegrity = args.Length == 2 && args[1] == "--verify-integrity";
if (args.Length == 2 && !verifyIntegrity)
{
    Console.Error.WriteLine($"Unknown option: {args[1]}");
    return 2;
}

try
{
    var paths = PetPackageLoader.FindPackages(petsDirectory).ToArray();
    if (paths.Length == 0)
    {
        throw new DirectoryNotFoundException($"No .petsgraph-pet package found in {petsDirectory}");
    }

    var loader = new PetPackageLoader();
    var totalClips = 0;
    var totalFrames = 0;
    foreach (var path in paths)
    {
        var package = loader.Load(path, verifyIntegrity);
        using var renderer = new RgbaFrameRenderer(package);
        var buffer = new byte[renderer.BufferLength];
        foreach (var clip in package.Clips.Values)
        {
            renderer.RenderPbgra32(clip.Id, 0, buffer);
            if (clip.Frames.Length > 1)
            {
                renderer.RenderPbgra32(clip.Id, clip.Frames.Length - 1, buffer);
            }
            totalFrames += clip.Frames.Length;
        }
        totalClips += package.Clips.Count;
        Console.WriteLine($"validated {package.Manifest.Pet.Id}: {package.Clips.Count} clips");
    }
    Console.WriteLine($"PetsGraph package validation passed: {paths.Length} pets, {totalClips} clips, {totalFrames} frames");
    return 0;
}
catch (Exception exception) when (exception is IOException or PetPackageValidationException)
{
    Console.Error.WriteLine(exception.Message);
    return 1;
}
