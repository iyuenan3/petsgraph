using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using PetsGraph.Core;
using WpfMouseEventArgs = System.Windows.Input.MouseEventArgs;
using WpfPoint = System.Windows.Point;

namespace PetsGraph.App.Rendering;

internal sealed partial class PetWindow : Window, IDisposable
{
    private const int WmNcHitTest = 0x0084;
    private static readonly IntPtr HtClient = new(1);
    private static readonly IntPtr HtTransparent = new(-1);

    private readonly LoadedPetPackage package;
    private readonly QuietBehaviorSession session;
    private readonly RgbaFrameRenderer renderer;
    private readonly WriteableBitmap bitmap;
    private readonly byte[] pixels;
    private readonly DispatcherTimer timer;
    private bool closingForExit;
    private bool pointerDown;
    private bool dragged;
    private NativePoint dragStartCursor;
    private double dragStartLeft;
    private double dragStartTop;
    private string? renderedClipId;
    private int renderedFrameIndex = -1;
    private double scale = 1;

    public event EventHandler? PositionChanged;
    public event EventHandler<Exception>? Faulted;

    public string PetId => package.Manifest.Pet.Id;
    public string DisplayName => package.Manifest.Pet.DisplayName;
    public string CurrentNodeId => session.CurrentNodeId;
    public QuietInteractionState InteractionState => session.State;
    public double PetScale => scale;
    public IReadOnlyList<GraphNode> SleepPoses { get; }

    public PetWindow(LoadedPetPackage package)
    {
        this.package = package;
        session = new(package);
        renderer = new(package);
        pixels = new byte[renderer.BufferLength];
        bitmap = new(renderer.CanvasWidth, renderer.CanvasHeight, 96, 96, PixelFormats.Pbgra32, null);
        SleepPoses = package.Graph.Nodes
            .Where(node => node.Role == "dwell" && node.AutonomousEligible == true)
            .OrderBy(node => node.Scene, StringComparer.Ordinal)
            .ThenBy(node => node.DisplayName, StringComparer.Ordinal)
            .ToArray();

        Title = $"PetsGraph · {DisplayName}";
        WindowStyle = WindowStyle.None;
        ResizeMode = ResizeMode.NoResize;
        AllowsTransparency = true;
        Background = System.Windows.Media.Brushes.Transparent;
        ShowInTaskbar = false;
        ShowActivated = false;
        Topmost = true;
        SizeToContent = SizeToContent.Manual;
        UseLayoutRounding = true;
        SnapsToDevicePixels = true;
        Content = new System.Windows.Controls.Image
        {
            Source = bitmap,
            Stretch = Stretch.Fill,
            SnapsToDevicePixels = true,
        };

        ApplyScale(1, preserveAnchor: false);
        SourceInitialized += OnSourceInitialized;
        PreviewMouseLeftButtonDown += OnPointerDown;
        PreviewMouseMove += OnPointerMove;
        PreviewMouseLeftButtonUp += OnPointerUp;

        var now = UptimeSeconds();
        session.Start(now);
        Render(now);
        timer = new(DispatcherPriority.Render)
        {
            Interval = TimeSpan.FromSeconds(1.0 / 24.0),
        };
        timer.Tick += OnTimerTick;
    }

    public void Start() => timer.Start();

    public void SetScale(double value)
    {
        if (value is not (0.5 or 0.75 or 1 or 1.25 or 1.5 or 1.75 or 2))
        {
            value = 1;
        }
        ApplyScale(value, preserveAnchor: true);
        PositionChanged?.Invoke(this, EventArgs.Empty);
    }

    public void SetInitialPosition(double? savedLeft, double? savedTop, double fallbackLeft, double fallbackBottom)
    {
        Left = savedLeft ?? fallbackLeft;
        Top = savedTop ?? fallbackBottom - Height;
        if (!IntersectsVirtualDesktop())
        {
            Left = fallbackLeft;
            Top = fallbackBottom - Height;
        }
    }

    public void ShowPet()
    {
        if (!IsVisible)
        {
            Show();
        }
        Start();
    }

    public void HidePet()
    {
        timer.Stop();
        Hide();
    }

    public bool SelectSleepPose(string nodeId)
    {
        var accepted = session.SelectSleepPose(nodeId, UptimeSeconds());
        if (accepted)
        {
        }
        return accepted;
    }

    public void Dispose()
    {
        timer.Stop();
        renderer.Dispose();
        closingForExit = true;
        Close();
    }

    protected override void OnClosing(CancelEventArgs eventArgs)
    {
        if (!closingForExit)
        {
            eventArgs.Cancel = true;
            HidePet();
        }
        base.OnClosing(eventArgs);
    }

    private void OnTimerTick(object? sender, EventArgs eventArgs)
    {
        try
        {
            Render(UptimeSeconds());
        }
        catch (Exception exception) when (exception is IOException or InvalidDataException or PetPackageValidationException)
        {
            timer.Stop();
            Faulted?.Invoke(this, exception);
        }
    }

    private void Render(double now)
    {
        var presentation = session.Update(now);
        if (presentation.Sample.ClipId == renderedClipId && presentation.Sample.SourceFrameIndex == renderedFrameIndex)
        {
            return;
        }
        renderer.RenderPbgra32(presentation.Sample.ClipId, presentation.Sample.SourceFrameIndex, pixels);
        bitmap.WritePixels(new Int32Rect(0, 0, renderer.CanvasWidth, renderer.CanvasHeight), pixels, renderer.CanvasWidth * 4, 0);
        renderedClipId = presentation.Sample.ClipId;
        renderedFrameIndex = presentation.Sample.SourceFrameIndex;
    }

    private void OnSourceInitialized(object? sender, EventArgs eventArgs)
    {
        var source = HwndSource.FromHwnd(new WindowInteropHelper(this).Handle);
        source?.AddHook(WindowProcedure);
    }

    private IntPtr WindowProcedure(IntPtr window, int message, IntPtr wordParameter, IntPtr longParameter, ref bool handled)
    {
        if (message != WmNcHitTest || !GetCursorPos(out var cursor))
        {
            return IntPtr.Zero;
        }
        var local = PointFromScreen(new WpfPoint(cursor.X, cursor.Y));
        handled = true;
        return IsOpaqueAt(local) ? HtClient : HtTransparent;
    }

    private bool IsOpaqueAt(WpfPoint local)
    {
        if (ActualWidth <= 0 || ActualHeight <= 0)
        {
            return false;
        }
        var x = (int)Math.Floor(local.X / ActualWidth * renderer.CanvasWidth);
        var y = (int)Math.Floor(local.Y / ActualHeight * renderer.CanvasHeight);
        return RgbaFrameRenderer.IsOpaqueEnough(pixels, renderer.CanvasWidth, renderer.CanvasHeight, x, y);
    }

    private void OnPointerDown(object sender, MouseButtonEventArgs eventArgs)
    {
        if (!IsOpaqueAt(eventArgs.GetPosition(this)))
        {
            return;
        }
        pointerDown = true;
        dragged = false;
        if (!GetCursorPos(out dragStartCursor))
        {
            var screen = PointToScreen(eventArgs.GetPosition(this));
            dragStartCursor = new() { X = (int)Math.Round(screen.X), Y = (int)Math.Round(screen.Y) };
        }
        dragStartLeft = Left;
        dragStartTop = Top;
        CaptureMouse();
        eventArgs.Handled = true;
    }

    private void OnPointerMove(object sender, WpfMouseEventArgs eventArgs)
    {
        if (!pointerDown || eventArgs.LeftButton != MouseButtonState.Pressed)
        {
            return;
        }
        if (!GetCursorPos(out var current))
        {
            return;
        }
        var dpi = VisualTreeHelper.GetDpi(this);
        var deltaX = (current.X - dragStartCursor.X) / dpi.DpiScaleX;
        var deltaY = (current.Y - dragStartCursor.Y) / dpi.DpiScaleY;
        if (Math.Abs(deltaX) + Math.Abs(deltaY) >= 3)
        {
            dragged = true;
        }
        Left = dragStartLeft + deltaX;
        Top = dragStartTop + deltaY;
        eventArgs.Handled = true;
    }

    private void OnPointerUp(object sender, MouseButtonEventArgs eventArgs)
    {
        if (!pointerDown)
        {
            return;
        }
        pointerDown = false;
        ReleaseMouseCapture();
        if (dragged)
        {
            PositionChanged?.Invoke(this, EventArgs.Empty);
        }
        else
        {
            session.HandlePetClick(UptimeSeconds());
        }
        eventArgs.Handled = true;
    }

    private void ApplyScale(double value, bool preserveAnchor)
    {
        var oldCenterX = Left + Width / 2;
        var oldBottom = Top + Height;
        scale = value;
        var pixelToDip = package.Manifest.Art.BaseHeightPt / renderer.CanvasHeight * value;
        Width = renderer.CanvasWidth * pixelToDip;
        Height = renderer.CanvasHeight * pixelToDip;
        if (preserveAnchor && double.IsFinite(oldCenterX) && double.IsFinite(oldBottom))
        {
            Left = oldCenterX - Width / 2;
            Top = oldBottom - Height;
        }
    }

    private bool IntersectsVirtualDesktop() =>
        Left + Width > SystemParameters.VirtualScreenLeft &&
        Left < SystemParameters.VirtualScreenLeft + SystemParameters.VirtualScreenWidth &&
        Top + Height > SystemParameters.VirtualScreenTop &&
        Top < SystemParameters.VirtualScreenTop + SystemParameters.VirtualScreenHeight;

    private static double UptimeSeconds() => Stopwatch.GetTimestamp() / (double)Stopwatch.Frequency;

    [StructLayout(LayoutKind.Sequential)]
    private struct NativePoint
    {
        public int X;
        public int Y;
    }

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool GetCursorPos(out NativePoint point);
}
