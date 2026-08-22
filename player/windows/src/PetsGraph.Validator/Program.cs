using System.Text;
using PetsGraph.Core;

Console.OutputEncoding = Encoding.UTF8;

if (args.Length == 0 || args[0] is "--help" or "-h" or "/?")
{
    Console.WriteLine("Usage: PetsGraph.Validator <file.petpack> [more.petpack ...]");
    return args.Length == 0 ? 2 : 0;
}

var validator = new PetPackValidator();
foreach (var argument in args)
{
    var source = Path.GetFullPath(argument);
    var temporary = Path.Combine(Path.GetTempPath(), $"petsgraph-validator-{Guid.NewGuid():N}");
    Directory.CreateDirectory(temporary);
    try
    {
        var validated = validator.ValidateAndExtract(source, temporary);
        var report = validated.Report;
        Console.WriteLine(
            $"valid {Path.GetFileName(source)} sha256={report.ArchiveSha256} clips={report.ClipCount} nodes={report.NodeCount} edges={report.EdgeCount}");
    }
    catch (Exception exception) when (exception is PetPackException or IOException or UnauthorizedAccessException)
    {
        Console.Error.WriteLine(exception is PetPackException petPack
            ? $"invalid {Path.GetFileName(source)}: {petPack.Code}"
            : $"invalid {Path.GetFileName(source)}: local_io_error");
        return 1;
    }
    finally
    {
        try
        {
            Directory.Delete(temporary, recursive: true);
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }
    }
}
return 0;
