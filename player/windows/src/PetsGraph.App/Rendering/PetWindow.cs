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
    private readonly System.Windows.Controls.Canvas surface;
    private readonly System.Windows.Controls.Image image;
    private readonly IReadOnlyDictionary<string, SquareViewport> viewports;
    private readonly DispatcherTimer timer;
    private bool closingForExit;
    private bool pointerDown;
    private bool dragged;
    private NativePoint dragStartCursor;
    private double dragStartCanvasLeft;
    private double dragStartCanvasTop;
    private string? renderedClipId;
    private int renderedFrameIndex = -1;
    private double scale = 1;
    private double pixelScale;
    private double canvasOriginLeft;
    private double canvasOriginTop;
    private double behaviorRootMotionXPt;
    private double presentationOffsetX;
    private double temporaryBoundaryOffsetDip;
    private SquareViewport activeViewport;

    public event EventHandler? PositionChanged;
    public event EventHandler<Exception>? Faulted;

    public string PetId => package.Manifest.Pet.Id;
    public string DisplayName => package.Manifest.Pet.DisplayName;
    public string CurrentNodeId => session.CurrentNodeId;
    public QuietInteractionState InteractionState => session.State;
    public double PersistentCanvasLeft => canvasOriginLeft + behaviorRootMotionXPt * scale;
    public double CanvasTop => canvasOriginTop;
    public IReadOnlyList<GraphNode> SleepPoses { get; }

    public PetWindow(LoadedPetPackage package)
    {
        this.package = package;
        session = new(package);
        renderer = new(package);
        pixels = new byte[renderer.BufferLength];
        bitmap = new(renderer.CanvasWidth, renderer.CanvasHeight, 96, 96, PixelFormats.Pbgra32, null);
        viewports = package.Clips.ToDictionary(
            pair => pair.Key,
            pair => SquareViewport.ForClip(pair.Value, package.Manifest.Art.CanvasPx),
            StringComparer.Ordinal);
        var defaultLoop = package.Graph.Nodes.FirstOrDefault(node => node.Id == package.Manifest.Art.DefaultNode)?.LoopClip;
        if (defaultLoop is null || !viewports.TryGetValue(defaultLoop, out activeViewport))
        {
            throw new PetPackageValidationException("Invalid pet package: default node has no square viewport");
        }
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
        image = new System.Windows.Controls.Image
        {
            Source = bitmap,
            Stretch = Stretch.Fill,
            SnapsToDevicePixels = true,
        };
        surface = new System.Windows.Controls.Canvas
        {
            ClipToBounds = true,
            Background = System.Windows.Media.Brushes.Transparent,
        };
        surface.Children.Add(image);
        Content = surface;

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

    public void SetInitialPosition(double? savedLeft, double? savedTop, double fallbackLeft, double fallbackGroundY)
    {
        if (savedLeft is { } left && savedTop is { } top)
        {
            canvasOriginLeft = left;
            canvasOriginTop = top;
        }
        else
        {
            canvasOriginLeft = fallbackLeft - activeViewport.X * pixelScale;
            canvasOriginTop = fallbackGroundY - package.Manifest.Art.GroundYPx * pixelScale;
        }
        UpdateWindowGeometry();
        if (!IntersectsVirtualDesktop())
        {
            canvasOriginLeft = fallbackLeft - activeViewport.X * pixelScale;
            canvasOriginTop = fallbackGroundY - package.Manifest.Art.GroundYPx * pixelScale;
            UpdateWindowGeometry();
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
        return session.SelectSleepPose(nodeId, UptimeSeconds());
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
        var clip = package.Clips[presentation.Sample.ClipId];
        var frame = clip.Frames[presentation.Sample.SourceFrameIndex];
        var nextViewport = viewports[presentation.Sample.ClipId];
        activeViewport = nextViewport;
        presentationOffsetX = frame.PresentationOffsetPx?[0] ?? 0;
        behaviorRootMotionXPt = presentation.TotalRootMotionXPt;
        ConstrainVisibleContent(frame);
        UpdateWindowGeometry();
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
        var x = (int)Math.Floor(activeViewport.X + local.X / ActualWidth * activeViewport.Side);
        var y = (int)Math.Floor(activeViewport.Y + local.Y / ActualHeight * activeViewport.Side);
        if (!RgbaFrameRenderer.IsOpaqueEnough(pixels, renderer.CanvasWidth, renderer.CanvasHeight, x, y))
        {
            return false;
        }
        if (renderedClipId is null || renderedFrameIndex < 0 ||
            package.Clips[renderedClipId].Frames[renderedFrameIndex].Collision.PetHitEllipsePx is not [var ellipseX, var ellipseY, var ellipseWidth, var ellipseHeight])
        {
            return true;
        }
        var radiusX = ellipseWidth / 2;
        var radiusY = ellipseHeight / 2;
        if (radiusX <= 0 || radiusY <= 0)
        {
            return false;
        }
        var normalizedX = (x - (ellipseX + radiusX)) / radiusX;
        var normalizedY = (y - (ellipseY + radiusY)) / radiusY;
        return normalizedX * normalizedX + normalizedY * normalizedY <= 1;
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
        dragStartCanvasLeft = canvasOriginLeft;
        dragStartCanvasTop = canvasOriginTop;
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
        canvasOriginLeft = dragStartCanvasLeft + deltaX;
        canvasOriginTop = dragStartCanvasTop + deltaY;
        UpdateWindowGeometry();
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
        var anchor = CurrentGroundAnchor();
        var oldAnchorX = canvasOriginLeft + behaviorRootMotionXPt * scale + presentationOffsetX * pixelScale +
            temporaryBoundaryOffsetDip + anchor.X * pixelScale;
        var oldAnchorY = canvasOriginTop + anchor.Y * pixelScale;
        scale = value;
        pixelScale = package.Manifest.Art.BaseHeightPt / renderer.CanvasHeight * value;
        temporaryBoundaryOffsetDip = 0;
        if (preserveAnchor && double.IsFinite(oldAnchorX) && double.IsFinite(oldAnchorY))
        {
            canvasOriginLeft = oldAnchorX - behaviorRootMotionXPt * scale - presentationOffsetX * pixelScale -
                anchor.X * pixelScale;
            canvasOriginTop = oldAnchorY - anchor.Y * pixelScale;
        }
        UpdateWindowGeometry();
    }

    private (double X, double Y) CurrentGroundAnchor()
    {
        if (renderedClipId is not null && renderedFrameIndex >= 0 &&
            package.Clips[renderedClipId].Frames[renderedFrameIndex].AnchorsPx.Ground is [var x, var y])
        {
            return (x, y);
        }
        return (renderer.CanvasWidth / 2.0, package.Manifest.Art.GroundYPx);
    }

    private void UpdateWindowGeometry()
    {
        var side = activeViewport.Side * pixelScale;
        Width = side;
        Height = side;
        Left = canvasOriginLeft + behaviorRootMotionXPt * scale + (activeViewport.X + presentationOffsetX) * pixelScale +
            temporaryBoundaryOffsetDip;
        Top = canvasOriginTop + activeViewport.Y * pixelScale;
        surface.Width = side;
        surface.Height = side;
        image.Width = renderer.CanvasWidth * pixelScale;
        image.Height = renderer.CanvasHeight * pixelScale;
        System.Windows.Controls.Canvas.SetLeft(image, -activeViewport.X * pixelScale);
        System.Windows.Controls.Canvas.SetTop(image, -activeViewport.Y * pixelScale);
    }

    private void ConstrainVisibleContent(ClipFrame frame)
    {
        temporaryBoundaryOffsetDip = 0;
        var contentLeft = canvasOriginLeft + behaviorRootMotionXPt * scale + presentationOffsetX * pixelScale +
            frame.ContentBoundsPx[0] * pixelScale;
        var contentRight = contentLeft + frame.ContentBoundsPx[2] * pixelScale;
        var desktopLeft = SystemParameters.VirtualScreenLeft;
        var desktopRight = desktopLeft + SystemParameters.VirtualScreenWidth;
        var adjustment = contentLeft < desktopLeft
            ? desktopLeft - contentLeft
            : contentRight > desktopRight
                ? desktopRight - contentRight
                : 0;
        if (Math.Abs(adjustment) < 0.000001)
        {
            return;
        }
        if (Math.Abs(presentationOffsetX) < 0.000001)
        {
            canvasOriginLeft += adjustment;
        }
        else
        {
            temporaryBoundaryOffsetDip = adjustment;
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
