using System.Reflection;
using System.Windows;
using PetsGraph.App.Rendering;
using PetsGraph.Core;
using Drawing = System.Drawing;
using Forms = System.Windows.Forms;

namespace PetsGraph.App.Runtime;

internal sealed class PetsGraphApplication : System.Windows.Application, IDisposable
{
    private static readonly double[] AllowedScales = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2];
    private readonly LoadedPetPackage[] packages;
    private readonly SettingsStore settingsStore = new();
    private readonly List<PetWindow> windows = [];
    private AppSettings settings = new();
    private Forms.NotifyIcon? trayIcon;
    private bool disposed;

    public PetsGraphApplication(LoadedPetPackage[] packages)
    {
        this.packages = packages;
        ShutdownMode = ShutdownMode.OnExplicitShutdown;
    }

    protected override void OnStartup(StartupEventArgs eventArgs)
    {
        base.OnStartup(eventArgs);
        settings = settingsStore.Load();
        var workArea = SystemParameters.WorkArea;
        var nextLeft = workArea.Left + 12;
        foreach (var package in packages)
        {
            var petId = package.Manifest.Pet.Id;
            if (!settings.Pets.TryGetValue(petId, out var petSettings))
            {
                petSettings = new();
                settings.Pets.Add(petId, petSettings);
            }
            var window = new PetWindow(package);
            window.SetScale(settings.Scale);
            window.SetInitialPosition(petSettings.Left, petSettings.Top, nextLeft, workArea.Bottom - 12);
            window.PositionChanged += OnWindowPositionChanged;
            window.Faulted += OnWindowFaulted;
            windows.Add(window);
            nextLeft = window.Left + window.Width + 12;
            if (petSettings.Visible)
            {
                window.ShowPet();
            }
        }
        CreateTrayIcon();
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
        foreach (var window in windows)
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
        trayIcon.DoubleClick += (_, _) => SetAllVisible(true);
    }

    private void RebuildMenu(Forms.ContextMenuStrip menu)
    {
        menu.Items.Clear();
        foreach (var window in windows)
        {
            var title = new Forms.ToolStripMenuItem($"当前宠物：{window.DisplayName}") { Enabled = false };
            menu.Items.Add(title);

            var visibility = new Forms.ToolStripMenuItem(window.IsVisible ? "隐藏" : "显示")
            {
                Checked = window.IsVisible,
            };
            visibility.Click += (_, _) => SetVisible(window, !window.IsVisible);
            menu.Items.Add(visibility);

            var status = new Forms.ToolStripMenuItem(StateTitle(window.InteractionState)) { Enabled = false };
            menu.Items.Add(status);

            var poses = new Forms.ToolStripMenuItem("选择睡姿");
            foreach (var pose in window.SleepPoses)
            {
                var item = new Forms.ToolStripMenuItem(pose.DisplayName ?? pose.Id)
                {
                    Checked = window.CurrentNodeId == pose.Id,
                    Tag = pose.Id,
                };
                item.Click += (_, _) => window.SelectSleepPose((string)item.Tag);
                poses.DropDownItems.Add(item);
            }
            menu.Items.Add(poses);

            menu.Items.Add(new Forms.ToolStripSeparator());
        }

        var sizes = new Forms.ToolStripMenuItem("全局大小");
        foreach (var value in AllowedScales)
        {
            var item = new Forms.ToolStripMenuItem($"{value:0.##}×")
            {
                Checked = Math.Abs(settings.Scale - value) < 0.001,
                Tag = value,
            };
            item.Click += (_, _) => SetGlobalScale((double)item.Tag);
            sizes.DropDownItems.Add(item);
        }
        menu.Items.Add(sizes);

        var showAll = new Forms.ToolStripMenuItem("显示全部");
        showAll.Click += (_, _) => SetAllVisible(true);
        menu.Items.Add(showAll);
        var hideAll = new Forms.ToolStripMenuItem("隐藏全部");
        hideAll.Click += (_, _) => SetAllVisible(false);
        menu.Items.Add(hideAll);
        menu.Items.Add(new Forms.ToolStripSeparator());
        var exit = new Forms.ToolStripMenuItem("退出 PetsGraph");
        exit.Click += (_, _) => Shutdown();
        menu.Items.Add(exit);
    }

    private void SetAllVisible(bool visible)
    {
        foreach (var window in windows)
        {
            SetVisible(window, visible, save: false);
        }
        SaveSettings();
    }

    private void SetGlobalScale(double value)
    {
        settings.Scale = value;
        foreach (var window in windows)
        {
            window.SetScale(value);
        }
        SaveSettings();
    }

    private void SetVisible(PetWindow window, bool visible, bool save = true)
    {
        if (visible)
        {
            window.ShowPet();
        }
        else
        {
            window.HidePet();
        }
        settings.Pets[window.PetId].Visible = visible;
        if (save)
        {
            SaveSettings();
        }
    }

    private void OnWindowPositionChanged(object? sender, EventArgs eventArgs) => SaveSettings();

    private void OnWindowFaulted(object? sender, Exception exception)
    {
        if (sender is PetWindow window)
        {
            SetVisible(window, false);
            System.Windows.MessageBox.Show($"{window.DisplayName} 的宠物包读取失败：\n{exception.Message}", "PetsGraph", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void SaveSettings()
    {
        foreach (var window in windows)
        {
            var pet = settings.Pets[window.PetId];
            pet.Visible = window.IsVisible;
            pet.Left = window.PersistentCanvasLeft;
            pet.Top = window.CanvasTop;
        }
        settingsStore.Save(settings);
    }

    private static string StateTitle(QuietInteractionState state) => state switch
    {
        QuietInteractionState.Sleeping => "当前状态：睡眠",
        QuietInteractionState.ChangingSleep => "当前状态：切换睡姿",
        QuietInteractionState.Waking => "当前状态：正在起身",
        QuietInteractionState.Sitting => "当前状态：坐好",
        QuietInteractionState.ReturningToSleep => "当前状态：正在入睡",
        _ => "当前状态：动作进行中",
    };
}
