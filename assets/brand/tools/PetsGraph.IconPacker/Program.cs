using System.Buffers.Binary;
using System.Text;

if (args.Length != 3)
{
    Console.Error.WriteLine("Usage: PetsGraph.IconPacker <icns|ico> <input-iconset> <output-file>");
    return 2;
}

var format = args[0];
var inputDirectory = Path.GetFullPath(args[1]);
var outputPath = Path.GetFullPath(args[2]);

if (!Directory.Exists(inputDirectory))
{
    Console.Error.WriteLine($"Iconset directory does not exist: {inputDirectory}");
    return 2;
}

Directory.CreateDirectory(Path.GetDirectoryName(outputPath)!);

switch (format)
{
    case "icns":
        WriteIcns(inputDirectory, outputPath);
        break;
    case "ico":
        WriteIco(inputDirectory, outputPath);
        break;
    default:
        Console.Error.WriteLine($"Unsupported icon format: {format}");
        return 2;
}

Console.WriteLine(outputPath);
return 0;

static void WriteIcns(string inputDirectory, string outputPath)
{
    (string Type, string File)[] entries =
    [
        ("icp4", "icon_16x16.png"),
        ("ic11", "icon_16x16@2x.png"),
        ("icp5", "icon_32x32.png"),
        ("ic12", "icon_32x32@2x.png"),
        ("ic07", "icon_128x128.png"),
        ("ic13", "icon_128x128@2x.png"),
        ("ic08", "icon_256x256.png"),
        ("ic14", "icon_256x256@2x.png"),
        ("ic09", "icon_512x512.png"),
        ("ic10", "icon_512x512@2x.png"),
    ];

    var chunks = entries.Select(entry =>
    {
        var payload = File.ReadAllBytes(Path.Combine(inputDirectory, entry.File));
        return (entry.Type, Payload: payload);
    }).ToArray();

    var totalLength = checked(8 + chunks.Sum(chunk => 8 + chunk.Payload.Length));
    using var stream = File.Create(outputPath);
    WriteAscii(stream, "icns");
    WriteUInt32BigEndian(stream, checked((uint)totalLength));
    foreach (var chunk in chunks)
    {
        WriteAscii(stream, chunk.Type);
        WriteUInt32BigEndian(stream, checked((uint)(chunk.Payload.Length + 8)));
        stream.Write(chunk.Payload);
    }
}

static void WriteIco(string inputDirectory, string outputPath)
{
    (byte Size, string File)[] entries =
    [
        (16, "icon_16x16.png"),
        (32, "icon_32x32.png"),
        (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"),
        (0, "icon_256x256.png"),
    ];
    var images = entries.Select(entry =>
        (entry.Size, Payload: File.ReadAllBytes(Path.Combine(inputDirectory, entry.File)))).ToArray();

    using var stream = File.Create(outputPath);
    WriteUInt16LittleEndian(stream, 0);
    WriteUInt16LittleEndian(stream, 1);
    WriteUInt16LittleEndian(stream, checked((ushort)images.Length));

    var offset = checked((uint)(6 + images.Length * 16));
    foreach (var image in images)
    {
        stream.WriteByte(image.Size);
        stream.WriteByte(image.Size);
        stream.WriteByte(0);
        stream.WriteByte(0);
        WriteUInt16LittleEndian(stream, 1);
        WriteUInt16LittleEndian(stream, 32);
        WriteUInt32LittleEndian(stream, checked((uint)image.Payload.Length));
        WriteUInt32LittleEndian(stream, offset);
        offset = checked(offset + (uint)image.Payload.Length);
    }

    foreach (var image in images)
    {
        stream.Write(image.Payload);
    }
}

static void WriteAscii(Stream stream, string value)
{
    var bytes = Encoding.ASCII.GetBytes(value);
    if (bytes.Length != 4)
    {
        throw new InvalidDataException("ICNS type names must contain four ASCII bytes.");
    }
    stream.Write(bytes);
}

static void WriteUInt16LittleEndian(Stream stream, ushort value)
{
    Span<byte> buffer = stackalloc byte[sizeof(ushort)];
    BinaryPrimitives.WriteUInt16LittleEndian(buffer, value);
    stream.Write(buffer);
}

static void WriteUInt32LittleEndian(Stream stream, uint value)
{
    Span<byte> buffer = stackalloc byte[sizeof(uint)];
    BinaryPrimitives.WriteUInt32LittleEndian(buffer, value);
    stream.Write(buffer);
}

static void WriteUInt32BigEndian(Stream stream, uint value)
{
    Span<byte> buffer = stackalloc byte[sizeof(uint)];
    BinaryPrimitives.WriteUInt32BigEndian(buffer, value);
    stream.Write(buffer);
}
