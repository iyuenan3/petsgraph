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

        try
        {
            var petsDirectory = PackageCatalog.ResolvePetsDirectory(options.PetsDirectory);
            var packages = PackageCatalog.LoadAll(petsDirectory, options.VerifyIntegrity);
            if (options.ValidateOnly)
            {
                AttachParentConsole();
                ValidateRenderableFrames(packages);
                Console.WriteLine($"PetsGraph validation passed: {packages.Length} package(s), {petsDirectory}");
                return 0;
            }

            using var singleInstance = new Mutex(initiallyOwned: false, @"Local\PetsGraph.Win11.x64");
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
                System.Windows.MessageBox.Show("PetsGraph 已经在运行，请查看系统托盘。", "PetsGraph", MessageBoxButton.OK, MessageBoxImage.Information);
                return 0;
            }
            try
            {
                using var application = new PetsGraphApplication(packages);
                return application.Run();
            }
            finally
            {
                singleInstance.ReleaseMutex();
            }
        }
        catch (Exception exception) when (exception is ArgumentException or IOException or InvalidDataException or PetPackageValidationException)
        {
            if (options.ValidateOnly)
            {
                AttachParentConsole();
                Console.Error.WriteLine(exception.Message);
            }
            else
            {
                System.Windows.MessageBox.Show(exception.Message, "PetsGraph 启动失败", MessageBoxButton.OK, MessageBoxImage.Error);
            }
            return 1;
        }
    }

    private static void ValidateRenderableFrames(IEnumerable<LoadedPetPackage> packages)
    {
        foreach (var package in packages)
        {
            using var renderer = new RgbaFrameRenderer(package);
            var buffer = new byte[renderer.BufferLength];
            foreach (var clip in package.Clips.Values)
            {
                renderer.RenderPbgra32(clip.Id, 0, buffer);
                if (clip.Frames.Length > 1)
                {
                    renderer.RenderPbgra32(clip.Id, clip.Frames.Length - 1, buffer);
                }
            }
        }
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

internal sealed record CommandLineOptions(
    bool ValidateOnly,
    bool VerifyIntegrity,
    bool ShowHelp,
    string? PetsDirectory)
{
    public const string HelpText = """
        PetsGraph for Windows

        用法：
          PetsGraph.exe [--pets-dir <目录>]
          PetsGraph.exe --validate-only [--verify-integrity] [--pets-dir <目录>]
        """;

    public static CommandLineOptions Parse(string[] args)
    {
        var validateOnly = false;
        var verifyIntegrity = false;
        var showHelp = false;
        string? petsDirectory = null;
        for (var index = 0; index < args.Length; index++)
        {
            switch (args[index])
            {
                case "--validate-only":
                    validateOnly = true;
                    break;
                case "--verify-integrity":
                    verifyIntegrity = true;
                    break;
                case "--pets-dir" when index + 1 < args.Length:
                    petsDirectory = args[++index];
                    break;
                case "--help" or "-h" or "/?":
                    showHelp = true;
                    break;
                default:
                    throw new ArgumentException($"未知参数：{args[index]}");
            }
        }
        if (verifyIntegrity && !validateOnly)
        {
            throw new ArgumentException("--verify-integrity 只能与 --validate-only 一起使用。");
        }
        return new(validateOnly, verifyIntegrity, showHelp, petsDirectory);
    }
}
