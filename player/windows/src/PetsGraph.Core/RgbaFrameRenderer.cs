using System.IO.MemoryMappedFiles;

namespace PetsGraph.Core;

public sealed class RgbaFrameRenderer : IDisposable
{
    private sealed class ClipStore : IDisposable
    {
        private readonly MemoryMappedFile mapping;
        private readonly MemoryMappedViewAccessor accessor;
        private readonly byte[] scratch;

        public ClipStore(LoadedPetPack package, PetClip clip)
        {
            Clip = clip;
            Representation = clip.Representations.Single();
            var path = package.MediaPath(clip.Id);
            if (new FileInfo(path).Length != Representation.Bytes)
            {
                throw Invalid("invalid_media_length", "runtime media length changed");
            }
            mapping = MemoryMappedFile.CreateFromFile(path, FileMode.Open, null, 0, MemoryMappedFileAccess.Read);
            accessor = mapping.CreateViewAccessor(0, Representation.Bytes, MemoryMappedFileAccess.Read);
            scratch = new byte[checked(Representation.BytesPerRow * Representation.HeightPx)];
        }

        public PetClip Clip { get; }
        public ClipRepresentation Representation { get; }
        public int FrameBytes => scratch.Length;

        public void RenderPbgra32(int frameIndex, Span<byte> destination)
        {
            if (frameIndex < 0 || frameIndex >= Clip.FrameCount || destination.Length < scratch.Length)
            {
                throw Invalid("invalid_frame", "runtime requested an invalid frame or buffer");
            }
            var offset = checked((long)frameIndex * scratch.Length);
            if (accessor.ReadArray(offset, scratch, 0, scratch.Length) != scratch.Length)
            {
                throw Invalid("invalid_media_length", "runtime frame exceeds its media");
            }
            for (var index = 0; index < scratch.Length; index += 4)
            {
                destination[index] = scratch[index + 2];
                destination[index + 1] = scratch[index + 1];
                destination[index + 2] = scratch[index];
                destination[index + 3] = scratch[index + 3];
            }
        }

        public double Alpha(int frameIndex, int canvasX, int canvasY)
        {
            if (Clip.Geometry.CropPx is not [var x, var y, var width, var height] ||
                frameIndex < 0 || frameIndex >= Clip.FrameCount || canvasX < x || canvasY < y ||
                canvasX >= x + width || canvasY >= y + height)
            {
                return 0;
            }
            var localX = canvasX - x;
            var localY = canvasY - y;
            var offset = checked((long)frameIndex * FrameBytes +
                (long)localY * Representation.BytesPerRow + localX * 4 + 3);
            return accessor.ReadByte(offset) / 255.0;
        }

        public void Dispose()
        {
            accessor.Dispose();
            mapping.Dispose();
        }
    }

    private readonly LoadedPetPack package;
    private readonly Dictionary<string, ClipStore> stores = new(StringComparer.Ordinal);
    private bool disposed;

    public RgbaFrameRenderer(LoadedPetPack package)
    {
        this.package = package;
    }

    public (int Width, int Height, int Stride, int Bytes) FrameLayout(string clipId)
    {
        var store = Store(clipId);
        return (store.Representation.WidthPx, store.Representation.HeightPx,
            store.Representation.BytesPerRow, store.FrameBytes);
    }

    public void Preload(string clipId) => _ = Store(clipId);

    public void RenderPbgra32(string clipId, int frameIndex, Span<byte> destination) =>
        Store(clipId).RenderPbgra32(frameIndex, destination);

    public double Alpha(string clipId, int frameIndex, int canvasX, int canvasY) =>
        Store(clipId).Alpha(frameIndex, canvasX, canvasY);

    public int CachedClipCount => stores.Count;

    public void RetainClips(IEnumerable<string> clipIds)
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        var retained = new HashSet<string>(clipIds, StringComparer.Ordinal);
        foreach (var clipId in stores.Keys.Where(clipId => !retained.Contains(clipId)).ToArray())
        {
            stores.Remove(clipId, out var obsolete);
            obsolete?.Dispose();
        }
    }

    public void Dispose()
    {
        if (disposed)
        {
            return;
        }
        disposed = true;
        foreach (var store in stores.Values)
        {
            store.Dispose();
        }
        stores.Clear();
    }

    private ClipStore Store(string clipId)
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        if (stores.TryGetValue(clipId, out var existing))
        {
            return existing;
        }
        if (!package.Clips.TryGetValue(clipId, out var clip))
        {
            throw Invalid("missing_clip", "runtime requested a missing clip");
        }
        var store = new ClipStore(package, clip);
        stores.Add(clipId, store);
        return store;
    }

    private static PetPackException Invalid(string code, string detail) => new(code, detail);
}
