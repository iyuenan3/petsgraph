using System.Reflection;
using System.IO;
using System.Windows;
using Microsoft.Win32;
using PetsGraph.App.Rendering;
using PetsGraph.Core;
using Drawing = System.Drawing;
using Forms = System.Windows.Forms;

namespace PetsGraph.App.Runtime;

internal sealed class PetsGraphApplication : System.Windows.Application, IDisposable
{
    private readonly CanonicalPetLibrary library;
    private readonly SettingsStore settingsStore;
    private readonly Dictionary<string, LoadedPetPack> packages = new(StringComparer.Ordinal);
    private readonly Dictionary<string, PetWindow> windows = new(StringComparer.Ordinal);
    private PlayerState state = new();
    private Forms.NotifyIcon? trayIcon;
    private bool disposed;

    public PetsGraphApplication(CanonicalPetLibrary library)
    {
        this.library = library;
        settingsStore = new(library.Root);
        ShutdownMode = ShutdownMode.OnExplicitShutdown;
    }

    protected override void OnStartup(StartupEventArgs eventArgs)
    {
        base.OnStartup(eventArgs);
        var loaded = library.LoadInstalledPetPacks();
        foreach (var package in loaded)
        {
            packages.Add(package.Manifest.Package.Id, package);
        }
        state = settingsStore.Load(loaded);
        CreateTrayIcon();
        foreach (var package in OrderedPackages())
        {
            InstallWindow(package);
        }
        SaveSettings();
    }

    protected override void OnExit(ExitEventArgs eventArgs)
    {
        Dispose();
        base.OnExit(eventArgs);
    }

    public void Dispose()
    {
        if (disposed)
        {
            return;
        }
        disposed = true;
        SaveSettings();
        foreach (var window in windows.Values)
        {
            window.Dispose();
        }
        windows.Clear();
        if (trayIcon is not null)
        {
            trayIcon.Visible = false;
            trayIcon.Dispose();
            trayIcon = null;
        }
    }

    private void CreateTrayIcon()
    {
        using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("PetsGraph.ico")
            ?? throw new InvalidOperationException("缺少内嵌 PetsGraph 图标。");
        var menu = new Forms.ContextMenuStrip();
        menu.Opening += (_, _) => RebuildMenu(menu);
        trayIcon = new Forms.NotifyIcon
        {
            Icon = new Drawing.Icon(stream),
            Text = "PetsGraph",
            ContextMenuStrip = menu,
            Visible = true,
        };
        RebuildMenu(menu);
    }

    private void RebuildMenu(Forms.ContextMenuStrip menu)
    {
        menu.Items.Clear();
        var load = new Forms.ToolStripMenuItem("装载宠物包…");
        load.Click += (_, _) => LoadPetPacks();
        menu.Items.Add(load);
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add(VisibilityMenu("显示宠物", visible: true));
        menu.Items.Add(VisibilityMenu("隐藏宠物", visible: false));
        menu.Items.Add(UninstallMenu());
        menu.Items.Add(new Forms.ToolStripSeparator());

        var sizes = new Forms.ToolStripMenuItem("大小");
        foreach (var value in PlayerState.AllowedScales)
        {
            var item = new Forms.ToolStripMenuItem($"{value:0.##}×")
            {
                Checked = Math.Abs(state.GlobalScale - value) < 0.000001,
                Tag = value,
            };
            item.Click += (_, _) => SetGlobalScale((double)item.Tag);
            sizes.DropDownItems.Add(item);
        }
        menu.Items.Add(sizes);
        menu.Items.Add(new Forms.ToolStripSeparator());
        var exit = new Forms.ToolStripMenuItem("退出 PetsGraph");
        exit.Click += (_, _) => Shutdown();
        menu.Items.Add(exit);
    }

    private Forms.ToolStripMenuItem VisibilityMenu(string title, bool visible)
    {
        var root = new Forms.ToolStripMenuItem(title);
        var all = new Forms.ToolStripMenuItem("全部")
        {
            Enabled = windows.Values.Any(window => window.PetVisible != visible),
        };
        all.Click += (_, _) => SetAllVisible(visible);
        root.DropDownItems.Add(all);
        if (windows.Count != 0)
        {
            root.DropDownItems.Add(new Forms.ToolStripSeparator());
        }
        foreach (var package in OrderedPackages())
        {
            var window = windows[package.Manifest.Package.Id];
            var item = new Forms.ToolStripMenuItem(package.Manifest.Pet.DisplayName)
            {
                Tag = package.Manifest.Package.Id,
                Enabled = window.PetVisible != visible,
            };
            item.Click += (_, _) => SetVisible((string)item.Tag, visible);
            root.DropDownItems.Add(item);
        }
        return root;
    }

    private Forms.ToolStripMenuItem UninstallMenu()
    {
        var root = new Forms.ToolStripMenuItem("卸载宠物");
        var all = new Forms.ToolStripMenuItem("全部") { Enabled = packages.Count != 0 };
        all.Click += (_, _) => UninstallAll();
        root.DropDownItems.Add(all);
        if (packages.Count != 0)
        {
            root.DropDownItems.Add(new Forms.ToolStripSeparator());
        }
        foreach (var package in OrderedPackages())
        {
            var item = new Forms.ToolStripMenuItem(package.Manifest.Pet.DisplayName)
            {
                Tag = package.Manifest.Package.Id,
            };
            item.Click += (_, _) => Uninstall((string)item.Tag);
            root.DropDownItems.Add(item);
        }
        return root;
    }

    private void LoadPetPacks()
    {
        var dialog = new Microsoft.Win32.OpenFileDialog
        {
            Title = "装载宠物包",
            Filter = "PetsGraph 宠物包 (*.petpack)|*.petpack",
            CheckFileExists = true,
            Multiselect = true,
        };
        if (dialog.ShowDialog() != true)
        {
            return;
        }
        var messages = new List<string>();
        foreach (var path in dialog.FileNames)
        {
            try
            {
                var outcome = library.Import(path, ConfirmUpdate);
                messages.Add(outcome.Result switch
                {
                    PetImportResult.Installed => $"已装载 {outcome.Current.DisplayName}",
                    PetImportResult.Updated => $"已更新 {outcome.Current.DisplayName}",
                    PetImportResult.AlreadyInstalled => $"{outcome.Current.DisplayName} 已经装载",
                    PetImportResult.UpdateCancelled => $"已取消更新 {outcome.Current.DisplayName}",
                    _ => "装载结果未知",
                });
            }
            catch (PetPackException exception)
            {
                messages.Add($"{Path.GetFileName(path)}：{exception.Detail}");
            }
        }
        try
        {
            ReloadPackagesAndWindows();
        }
        catch (PetPackException exception)
        {
            messages.Add($"重新读取内部宠物库失败：{exception.Detail}");
        }
        SaveSettings();
        if (messages.Count != 0)
        {
            System.Windows.MessageBox.Show(string.Join(Environment.NewLine, messages), "装载结果",
                MessageBoxButton.OK, MessageBoxImage.Information);
        }
    }

    private bool ConfirmUpdate(InstalledPet current, InstalledPet proposed) =>
        System.Windows.MessageBox.Show(
            $"将 {current.DisplayName} 从 {current.ContentVersion} 更新到 {proposed.ContentVersion}。位置和显示状态会保留。",
            $"更新 {current.DisplayName}？", MessageBoxButton.OKCancel, MessageBoxImage.Question) == MessageBoxResult.OK;

    private void ReloadPackagesAndWindows()
    {
        var loaded = library.LoadInstalledPetPacks();
        var next = loaded.ToDictionary(static package => package.Manifest.Package.Id, StringComparer.Ordinal);
        foreach (var id in windows.Keys.Where(id => !next.ContainsKey(id) ||
                     packages[id].Manifest.Package.ContentVersion != next[id].Manifest.Package.ContentVersion).ToArray())
        {
            windows[id].Dispose();
            windows.Remove(id);
        }
        packages.Clear();
        foreach (var pair in next)
        {
            packages.Add(pair.Key, pair.Value);
            if (!windows.ContainsKey(pair.Key))
            {
                InstallWindow(pair.Value);
            }
        }
    }

    private void InstallWindow(LoadedPetPack package)
    {
        var id = package.Manifest.Package.Id;
        if (!state.Pets.TryGetValue(id, out var petState))
        {
            petState = new();
            state.Pets.Add(id, petState);
        }
        var (fallbackX, fallbackY) = NextDefaultAnchor(package);
        var window = new PetWindow(package, state.GlobalScale,
            petState.AnchorX is { } x && double.IsFinite(x) ? x : fallbackX,
            petState.AnchorY is { } y && double.IsFinite(y) ? y : fallbackY);
        window.PositionChanged += (_, _) => SaveSettings();
        window.Faulted += (_, exception) => OnWindowFaulted(window, exception);
        windows.Add(id, window);
        if (petState.Visible)
        {
            window.ShowPet();
        }
        petState.AnchorX = window.AnchorX;
        petState.AnchorY = window.AnchorY;
    }

    private (double X, double Y) NextDefaultAnchor(LoadedPetPack package)
    {
        var work = SystemParameters.WorkArea;
        var canvas = package.Manifest.Stage.ReferenceCanvasPx;
        var height = package.Manifest.Stage.BaseDisplayHeight * state.GlobalScale;
        var width = height * canvas[0] / canvas[1];
        var right = windows.Values.Select(static window => window.AnchorX + window.Width / 2).DefaultIfEmpty(work.Left).Max();
        var x = right + 12 + width / 2;
        if (x + width / 2 > work.Right)
        {
            x = work.Left + 12 + width / 2;
        }
        return (x, work.Bottom - 12);
    }

    private void SetAllVisible(bool visible)
    {
        foreach (var id in windows.Keys)
        {
            SetVisible(id, visible, save: false);
        }
        SaveSettings();
    }

    private void SetVisible(string packageId, bool visible, bool save = true)
    {
        if (!windows.TryGetValue(packageId, out var window))
        {
            return;
        }
        if (visible)
        {
            window.ShowPet();
        }
        else
        {
            window.HidePet();
        }
        state.Pets[packageId].Visible = visible;
        if (save)
        {
            SaveSettings();
        }
    }

    private void SetGlobalScale(double value)
    {
        state.GlobalScale = PlayerState.NormalizeScale(value);
        foreach (var window in windows.Values)
        {
            window.SetScale(state.GlobalScale);
        }
        SaveSettings();
    }

    private void Uninstall(string packageId)
    {
        if (!packages.TryGetValue(packageId, out var package) ||
            !ConfirmUninstall(package.Manifest.Pet.DisplayName, all: false))
        {
            return;
        }
        try
        {
            _ = library.Uninstall(packageId);
            windows.Remove(packageId, out var window);
            window?.Dispose();
            packages.Remove(packageId);
            state.Pets.Remove(packageId);
            SaveSettings();
        }
        catch (PetPackException exception)
        {
            System.Windows.MessageBox.Show(exception.Detail, "卸载失败", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void UninstallAll()
    {
        if (packages.Count == 0 || !ConfirmUninstall("全部宠物", all: true))
        {
            return;
        }
        try
        {
            _ = library.UninstallAll();
            foreach (var window in windows.Values)
            {
                window.Dispose();
            }
            windows.Clear();
            packages.Clear();
            state.Pets.Clear();
            SaveSettings();
        }
        catch (PetPackException exception)
        {
            System.Windows.MessageBox.Show(exception.Detail, "卸载失败", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private static bool ConfirmUninstall(string name, bool all) =>
        System.Windows.MessageBox.Show(
            "卸载会删除 PetsGraph 内部保存的宠物包、缓存、位置和显示状态。以后恢复必须重新提供原始 .petpack 文件。",
            all ? "卸载全部宠物？" : $"卸载 {name}？",
            MessageBoxButton.OKCancel, MessageBoxImage.Warning) == MessageBoxResult.OK;

    private void OnWindowFaulted(PetWindow window, Exception exception)
    {
        SetVisible(window.PackageId, false);
        var detail = exception is PetPackException petPack ? petPack.Detail : "本地媒体读取失败。";
        System.Windows.MessageBox.Show($"{window.DisplayName}：{detail}", "宠物播放已暂停",
            MessageBoxButton.OK, MessageBoxImage.Error);
    }

    private IReadOnlyList<LoadedPetPack> OrderedPackages() => packages.Values
        .OrderBy(static package => package.Manifest.Pet.DisplayName, StringComparer.CurrentCulture)
        .ThenBy(static package => package.Manifest.Package.Id, StringComparer.Ordinal).ToArray();

    private void SaveSettings()
    {
        foreach (var pair in windows)
        {
            if (!state.Pets.TryGetValue(pair.Key, out var pet))
            {
                pet = new();
                state.Pets.Add(pair.Key, pet);
            }
            pet.Visible = pair.Value.PetVisible;
            pet.AnchorX = pair.Value.AnchorX;
            pet.AnchorY = pair.Value.AnchorY;
        }
        settingsStore.Save(state);
    }
}
