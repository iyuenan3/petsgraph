namespace PetsGraph.Core;

public readonly record struct SquareViewport(double X, double Y, double Side)
{
    public static SquareViewport ForClip(ClipDefinition clip, IReadOnlyList<int> canvasPx)
    {
        if (clip.Media?.CropRectPx is [var cropX, var cropY, var cropWidth, var cropHeight] &&
            cropWidth > 0 && cropHeight > 0)
        {
            return Enclosing(cropX, cropY, cropWidth, cropHeight);
        }

        var validBounds = clip.Frames.Select(frame => frame.ContentBoundsPx)
            .Where(bounds => bounds is [_, _, > 0, > 0])
            .ToArray();
        if (validBounds.Length == 0)
        {
            return Enclosing(0, 0, canvasPx[0], canvasPx[1]);
        }
        var minimumX = validBounds.Min(bounds => bounds[0]) - 4;
        var minimumY = validBounds.Min(bounds => bounds[1]) - 4;
        var maximumX = validBounds.Max(bounds => bounds[0] + bounds[2]) + 4;
        var maximumY = validBounds.Max(bounds => bounds[1] + bounds[3]) + 4;
        return Enclosing(minimumX, minimumY, maximumX - minimumX, maximumY - minimumY);
    }

    private static SquareViewport Enclosing(double x, double y, double width, double height)
    {
        var side = Math.Max(1, Math.Max(width, height));
        return new(x + width / 2 - side / 2, y + height / 2 - side / 2, side);
    }
}
