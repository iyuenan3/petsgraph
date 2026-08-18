using System.Buffers;

namespace PetsGraph.Core;

public sealed class RgbaFrameRenderer : IDisposable
{
    private readonly LoadedPetPackage package;
    private readonly Dictionary<string, FileStream> streams = new(StringComparer.Ordinal);

    public int CanvasWidth => package.Manifest.Art.CanvasPx[0];
    public int CanvasHeight => package.Manifest.Art.CanvasPx[1];
    public int BufferLength => checked(CanvasWidth * CanvasHeight * 4);

    public RgbaFrameRenderer(LoadedPetPackage package)
    {
        this.package = package;
    }

    public void RenderPbgra32(string clipId, int frameIndex, Span<byte> destination)
    {
        if (destination.Length != BufferLength)
        {
            throw new ArgumentException($"Destination buffer must contain {BufferLength} bytes.", nameof(destination));
        }
        if (!package.Clips.TryGetValue(clipId, out var clip) || clip.Media is not { } media ||
            media.CropRectPx is not [var cropX, var cropY, var cropWidth, var cropHeight] ||
            media.FrameByteCount is not { } frameByteCount || frameIndex < 0 || frameIndex >= clip.Frames.Length)
        {
            throw new ArgumentOutOfRangeException(nameof(frameIndex), "Unknown clip or invalid frame index.");
        }

        destination.Clear();
        var source = ArrayPool<byte>.Shared.Rent(frameByteCount);
        try
        {
            var stream = GetStream(media.Src);
            stream.Position = checked((long)frameIndex * frameByteCount);
            stream.ReadExactly(source.AsSpan(0, frameByteCount));

            var targetX = cropX;
            var targetY = cropY;
            if (targetX < 0 || targetY < 0 || targetX + cropWidth > CanvasWidth || targetY + cropHeight > CanvasHeight)
            {
                throw new InvalidDataException($"Frame {clipId}:{frameIndex} falls outside the package canvas.");
            }

            for (var row = 0; row < cropHeight; row++)
            {
                var sourceRow = source.AsSpan(row * cropWidth * 4, cropWidth * 4);
                var targetRow = destination.Slice(((targetY + row) * CanvasWidth + targetX) * 4, cropWidth * 4);
                for (var column = 0; column < cropWidth; column++)
                {
                    var offset = column * 4;
                    targetRow[offset] = sourceRow[offset + 2];
                    targetRow[offset + 1] = sourceRow[offset + 1];
                    targetRow[offset + 2] = sourceRow[offset];
                    targetRow[offset + 3] = sourceRow[offset + 3];
                }
            }
        }
        finally
        {
            ArrayPool<byte>.Shared.Return(source);
        }
    }

    public static bool IsOpaqueEnough(ReadOnlySpan<byte> pbgraBuffer, int width, int height, int x, int y, byte threshold = 12)
    {
        if (x < 0 || y < 0 || x >= width || y >= height || pbgraBuffer.Length != checked(width * height * 4))
        {
            return false;
        }
        return pbgraBuffer[(y * width + x) * 4 + 3] >= threshold;
    }

    public void Dispose()
    {
        foreach (var stream in streams.Values)
        {
            stream.Dispose();
        }
        streams.Clear();
    }

    private FileStream GetStream(string relativePath)
    {
        if (streams.TryGetValue(relativePath, out var existing))
        {
            return existing;
        }
        var path = PetPackageLoader.ResolveRegularFile(package.RootPath, relativePath);
        var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, 64 * 1024,
            FileOptions.RandomAccess);
        streams.Add(relativePath, stream);
        return stream;
    }
}
