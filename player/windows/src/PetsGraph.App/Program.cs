using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows;
using PetsGraph.App.Runtime;
using PetsGraph.Core;

namespace PetsGraph.App;

internal static partial class Program
{
    [STAThread]
    public static int Main(string[] args)
    {
        CommandLineOptions options;
        try
        {
            options = CommandLineOptions.Parse(args);
        }
        catch (ArgumentException exception)
        {
            AttachParentConsole();
            Console.Error.WriteLine(exception.Message);
            return 2;
        }
        if (options.ShowHelp)
        {
            AttachParentConsole();
            Console.WriteLine(CommandLineOptions.HelpText);
            return 0;
        }
        if (options.ValidationPaths.Count != 0)
        {
            AttachParentConsole();
            return Validate(options.ValidationPaths);
        }

        try
        {
            using var singleInstance = new Mutex(initiallyOwned: false, @"Local\PetsGraph.Player.Win.x64");
            bool ownsMutex;
            try
            {
                ownsMutex = singleInstance.WaitOne(0, exitContext: false);
            }
            catch (AbandonedMutexException)
            {
                ownsMutex = true;
            }
            if (!ownsMutex)
            {
                System.Windows.MessageBox.Show("PetsGraph 已经在运行，请查看系统托盘。", "PetsGraph",
                    MessageBoxButton.OK, MessageBoxImage.Information);
                return 0;
            }
            try
            {
                var library = new CanonicalPetLibrary();
                using var application = new PetsGraphApplication(library);
                return application.Run();
            }
            finally
            {
                singleInstance.ReleaseMutex();
            }
        }
        catch (Exception exception) when (exception is PetPackException or IOException or UnauthorizedAccessException)
        {
            var detail = exception is PetPackException petPack
                ? petPack.Detail
                : "无法读取 PetsGraph 本地数据。";
            System.Windows.MessageBox.Show(detail, "PetsGraph 启动失败", MessageBoxButton.OK, MessageBoxImage.Error);
            return 1;
        }
    }

    private static int Validate(IReadOnlyList<string> paths)
    {
        var validator = new PetPackValidator();
        foreach (var item in paths)
        {
            var source = Path.GetFullPath(item);
            var temporary = Path.Combine(Path.GetTempPath(), $"petsgraph-app-validate-{Guid.NewGuid():N}");
            Directory.CreateDirectory(temporary);
            try
            {
                var validated = validator.ValidateAndExtract(source, temporary);
                using var renderer = new RgbaFrameRenderer(validated.Package);
                foreach (var clip in validated.Package.Clips.Values)
                {
                    var layout = renderer.FrameLayout(clip.Id);
                    var buffer = new byte[layout.Bytes];
                    renderer.RenderPbgra32(clip.Id, 0, buffer);
                    renderer.RenderPbgra32(clip.Id, clip.FrameCount - 1, buffer);
                }
                Console.WriteLine($"valid {Path.GetFileName(source)} sha256={validated.Report.ArchiveSha256}");
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
    }

    private static void AttachParentConsole()
    {
        if (AttachConsole(unchecked((uint)-1)))
        {
            Console.OutputEncoding = Encoding.UTF8;
        }
    }

    [LibraryImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool AttachConsole(uint processId);
}

internal sealed record CommandLineOptions(bool ShowHelp, IReadOnlyList<string> ValidationPaths)
{
    public const string HelpText = """
        PetsGraph Player for Windows x64

        用法：
          PetsGraph.exe
          PetsGraph.exe --validate-only <file.petpack> [more.petpack ...]
        """;

    public static CommandLineOptions Parse(string[] args)
    {
        if (args.Length == 0)
        {
            return new(false, []);
        }
        if (args.Length == 1 && args[0] is "--help" or "-h" or "/?")
        {
            return new(true, []);
        }
        if (args.Length >= 2 && args[0] == "--validate-only" &&
            args.Skip(1).All(static path => !path.StartsWith("-", StringComparison.Ordinal)))
        {
            return new(false, args.Skip(1).ToArray());
        }
        throw new ArgumentException("参数无效。使用 --help 查看用法。");
    }
}
