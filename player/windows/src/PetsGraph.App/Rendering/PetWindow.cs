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

    private readonly LoadedPetPack package;
    private readonly PassiveBehaviorSession session;
    private readonly RgbaFrameRenderer renderer;
    private readonly Rect contentEnvelopePx;
    private readonly System.Windows.Controls.Canvas surface;
    private readonly System.Windows.Controls.Image image;
    private readonly DispatcherTimer timer;
    private WriteableBitmap? bitmap;
    private byte[] pixels = [];
    private string? renderedClipId;
    private int renderedFrameIndex = -1;
    private double scale = 1;
    private double anchorX;
    private double anchorY;
    private bool petVisible;
    private bool closingForExit;
    private bool pointerDown;
    private bool dragged;
    private NativePoint dragStartCursor;
    private double dragStartAnchorX;
    private double dragStartAnchorY;

    public PetWindow(LoadedPetPack package, double initialScale, double initialAnchorX, double initialAnchorY)
    {
        this.package = package;
        scale = PlayerState.NormalizeScale(initialScale);
        anchorX = initialAnchorX;
        anchorY = initialAnchorY;
        session = new(package, UptimeSeconds());
        renderer = new(package);
        contentEnvelopePx = ContentEnvelope(package);

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
        ApplyGeometry();
        ClampAnchor();
        ApplyGeometry();

        SourceInitialized += OnSourceInitialized;
        PreviewMouseLeftButtonDown += OnPointerDown;
        PreviewMouseMove += OnPointerMove;
        PreviewMouseLeftButtonUp += OnPointerUp;
        timer = new(DispatcherPriority.Render)
        {
            Interval = TimeSpan.FromSeconds(1.0 / 60.0),
        };
        timer.Tick += OnTimerTick;
        Render(UptimeSeconds());
    }

    public event EventHandler? PositionChanged;
    public event EventHandler<Exception>? Faulted;

    public string PackageId => package.Manifest.Package.Id;
    public string DisplayName => package.Manifest.Pet.DisplayName;
    public bool PetVisible => petVisible;
    public double AnchorX => anchorX;
    public double AnchorY => anchorY;

    public void ShowPet()
    {
        session.SetVisible(true, UptimeSeconds());
        petVisible = true;
        if (!IsVisible)
        {
            Show();
        }
        timer.Start();
    }

    public void HidePet()
    {
        session.SetVisible(false, UptimeSeconds());
        petVisible = false;
        Hide();
        if (session.ShouldTickWhenHidden)
        {
            timer.Start();
        }
        else
        {
            timer.Stop();
        }
    }

    public void SetScale(double value)
    {
        scale = PlayerState.NormalizeScale(value);
        ApplyGeometry();
        ClampAnchor();
        ApplyGeometry();
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
            if (!petVisible && !session.ShouldTickWhenHidden)
            {
                timer.Stop();
            }
        }
        catch (Exception exception) when (exception is PetPackException or IOException or UnauthorizedAccessException)
        {
            timer.Stop();
            Faulted?.Invoke(this, exception);
        }
    }

    private void Render(double now)
    {
        var presentation = session.Update(now);
        var retainedClipIds = presentation.PreloadClipIds
            .Append(presentation.ClipId)
            .ToHashSet(StringComparer.Ordinal);
        try
        {
            foreach (var clipId in presentation.PreloadClipIds)
            {
                renderer.Preload(clipId);
            }
        }
        catch (Exception exception) when (!presentation.IsTransition &&
            exception is PetPackException or IOException or UnauthorizedAccessException)
        {
            renderer.RetainClips([presentation.ClipId]);
            session.CancelPlannedTransition(now);
            return;
        }
        if (renderedClipId == presentation.ClipId && renderedFrameIndex == presentation.FrameIndex)
        {
            renderer.RetainClips(retainedClipIds);
            return;
        }
        var clip = package.Clips[presentation.ClipId];
        var layout = renderer.FrameLayout(clip.Id);
        if (bitmap is null || bitmap.PixelWidth != layout.Width || bitmap.PixelHeight != layout.Height)
        {
            bitmap = new(layout.Width, layout.Height, 96, 96, PixelFormats.Pbgra32, null);
            image.Source = bitmap;
            pixels = new byte[layout.Bytes];
        }
        renderer.RenderPbgra32(clip.Id, presentation.FrameIndex, pixels);
        bitmap.WritePixels(new Int32Rect(0, 0, layout.Width, layout.Height), pixels, layout.Stride, 0);
        var pixelScale = PixelScale();
        image.Width = layout.Width * pixelScale;
        image.Height = layout.Height * pixelScale;
        System.Windows.Controls.Canvas.SetLeft(image, clip.Geometry.CropPx[0] * pixelScale);
        System.Windows.Controls.Canvas.SetTop(image, clip.Geometry.CropPx[1] * pixelScale);
        renderedClipId = clip.Id;
        renderedFrameIndex = presentation.FrameIndex;
        renderer.RetainClips(retainedClipIds);
    }

    private void ApplyGeometry()
    {
        var canvas = package.Manifest.Stage.ReferenceCanvasPx;
        var pixelScale = PixelScale();
        Width = canvas[0] * pixelScale;
        Height = canvas[1] * pixelScale;
        Left = anchorX - Width / 2;
        Top = anchorY - Height;
        surface.Width = Width;
        surface.Height = Height;
        if (renderedClipId is { } clipId)
        {
            var clip = package.Clips[clipId];
            var layout = renderer.FrameLayout(clipId);
            image.Width = layout.Width * pixelScale;
            image.Height = layout.Height * pixelScale;
            System.Windows.Controls.Canvas.SetLeft(image, clip.Geometry.CropPx[0] * pixelScale);
            System.Windows.Controls.Canvas.SetTop(image, clip.Geometry.CropPx[1] * pixelScale);
        }
    }

    private double PixelScale() =>
        package.Manifest.Stage.BaseDisplayHeight * scale / package.Manifest.Stage.ReferenceCanvasPx[1];

    private void OnSourceInitialized(object? sender, EventArgs eventArgs)
    {
        HwndSource.FromHwnd(new WindowInteropHelper(this).Handle)?.AddHook(WindowProcedure);
    }

    private IntPtr WindowProcedure(IntPtr window, int message, IntPtr wordParameter, IntPtr longParameter,
        ref bool handled)
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
        if (!petVisible || renderedClipId is null || renderedFrameIndex < 0 || ActualWidth <= 0 || ActualHeight <= 0)
        {
            return false;
        }
        var canvas = package.Manifest.Stage.ReferenceCanvasPx;
        var x = Math.Clamp((int)Math.Floor(local.X / ActualWidth * canvas[0]), 0, canvas[0] - 1);
        var y = Math.Clamp((int)Math.Floor(local.Y / ActualHeight * canvas[1]), 0, canvas[1] - 1);
        return renderer.Alpha(renderedClipId, renderedFrameIndex, x, y) > 0.05;
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
        dragStartAnchorX = anchorX;
        dragStartAnchorY = anchorY;
        CaptureMouse();
        eventArgs.Handled = true;
    }

    private void OnPointerMove(object sender, WpfMouseEventArgs eventArgs)
    {
        if (!pointerDown || eventArgs.LeftButton != MouseButtonState.Pressed || !GetCursorPos(out var current))
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
        anchorX = dragStartAnchorX + deltaX;
        anchorY = dragStartAnchorY + deltaY;
        ClampAnchor();
        ApplyGeometry();
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
        eventArgs.Handled = true;
    }

    private void ClampAnchor()
    {
        var left = SystemParameters.VirtualScreenLeft;
        var top = SystemParameters.VirtualScreenTop;
        var right = left + SystemParameters.VirtualScreenWidth;
        var bottom = top + SystemParameters.VirtualScreenHeight;
        var pixelScale = PixelScale();
        var localMinX = contentEnvelopePx.Left * pixelScale;
        var localMaxX = contentEnvelopePx.Right * pixelScale;
        var localMinY = contentEnvelopePx.Top * pixelScale;
        var localMaxY = contentEnvelopePx.Bottom * pixelScale;
        var minimumX = left + Width / 2 - localMinX;
        var maximumX = right + Width / 2 - localMaxX;
        var minimumY = top + Height - localMinY;
        var maximumY = bottom + Height - localMaxY;
        anchorX = minimumX > maximumX
            ? (left + right) / 2 + Width / 2 - (localMinX + localMaxX) / 2
            : Math.Clamp(anchorX, minimumX, maximumX);
        anchorY = minimumY > maximumY
            ? (top + bottom) / 2 + Height - (localMinY + localMaxY) / 2
            : Math.Clamp(anchorY, minimumY, maximumY);
    }

    private static Rect ContentEnvelope(LoadedPetPack package)
    {
        var left = package.Clips.Values.Min(clip => clip.Geometry.CropPx[0]);
        var top = package.Clips.Values.Min(clip => clip.Geometry.CropPx[1]);
        var right = package.Clips.Values.Max(clip => clip.Geometry.CropPx[0] + clip.Geometry.CropPx[2]);
        var bottom = package.Clips.Values.Max(clip => clip.Geometry.CropPx[1] + clip.Geometry.CropPx[3]);
        return new(left, top, right - left, bottom - top);
    }

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
