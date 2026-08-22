using System.Buffers.Binary;
using System.IO.Compression;
using System.Text;

namespace PetsGraph.Core;

public sealed record PetPackZipEntry(
    string Path,
    long CompressedSize,
    long UncompressedSize,
    uint Crc32,
    ushort CompressionMethod,
    ushort Flags,
    long LocalHeaderOffset,
    long DataOffset,
    long LocalRecordEnd);

public sealed record PetPackZipIndex(
    string ArchivePath,
    long ArchiveBytes,
    long UncompressedBytes,
    IReadOnlyList<PetPackZipEntry> Entries);

public sealed class SafeZipArchive
{
    public const int MaximumEntries = 100_000;
    public const long MaximumArchiveBytes = 64L * 1024 * 1024 * 1024;
    public const long MaximumUncompressedBytes = 64L * 1024 * 1024 * 1024;
    public const long MaximumEntryBytes = 32L * 1024 * 1024 * 1024;
    public const long MaximumJsonBytes = 16L * 1024 * 1024;
    public const int MaximumCompressionRatio = 200;

    private static readonly UTF8Encoding StrictUtf8 = new(false, true);
    private static readonly HashSet<string> WindowsReservedNames = new(StringComparer.OrdinalIgnoreCase)
    {
        "CON", "PRN", "AUX", "NUL", "CLOCK$",
        "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
        "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9",
    };

    public PetPackZipIndex Inspect(string sourcePath)
    {
        var archivePath = Path.GetFullPath(sourcePath);
        if (!File.Exists(archivePath) || !string.Equals(Path.GetExtension(archivePath), ".petpack", StringComparison.OrdinalIgnoreCase))
        {
            throw Invalid("archive_type", "selected file is not a .petpack archive");
        }

        using var stream = new FileStream(archivePath, FileMode.Open, FileAccess.Read, FileShare.Read,
            bufferSize: 1 << 20, FileOptions.RandomAccess);
        var length = stream.Length;
        if (length is < 22 or > MaximumArchiveBytes)
        {
            throw Invalid("archive_budget", "archive size is outside the supported budget");
        }
        if (ReadUInt32(stream, 0) != 0x04034b50)
        {
            throw Invalid("archive_prefix", "archive must begin with a ZIP local header");
        }

        var eocdOffset = length - 22;
        var eocd = ReadExact(stream, eocdOffset, 22);
        if (BinaryPrimitives.ReadUInt32LittleEndian(eocd) != 0x06054b50 ||
            BinaryPrimitives.ReadUInt16LittleEndian(eocd.AsSpan(20)) != 0)
        {
            throw Invalid("archive_trailing", "archive must end at an uncommented ZIP end record");
        }
        if (BinaryPrimitives.ReadUInt16LittleEndian(eocd.AsSpan(4)) != 0 ||
            BinaryPrimitives.ReadUInt16LittleEndian(eocd.AsSpan(6)) != 0)
        {
            throw Invalid("archive_split", "split ZIP archives are not supported");
        }

        var entriesOnDisk16 = BinaryPrimitives.ReadUInt16LittleEndian(eocd.AsSpan(8));
        var entryCount16 = BinaryPrimitives.ReadUInt16LittleEndian(eocd.AsSpan(10));
        var centralSize32 = BinaryPrimitives.ReadUInt32LittleEndian(eocd.AsSpan(12));
        var centralOffset32 = BinaryPrimitives.ReadUInt32LittleEndian(eocd.AsSpan(16));
        long entryCount;
        long centralSize;
        long centralOffset;
        long centralEnd;
        var needsZip64 = entriesOnDisk16 == ushort.MaxValue || entryCount16 == ushort.MaxValue ||
            centralSize32 == uint.MaxValue || centralOffset32 == uint.MaxValue;
        if (needsZip64)
        {
            if (eocdOffset < 20)
            {
                throw Invalid("zip64_missing", "ZIP64 locator is missing");
            }
            var locatorOffset = eocdOffset - 20;
            var locator = ReadExact(stream, locatorOffset, 20);
            if (BinaryPrimitives.ReadUInt32LittleEndian(locator) != 0x07064b50 ||
                BinaryPrimitives.ReadUInt32LittleEndian(locator.AsSpan(4)) != 0 ||
                BinaryPrimitives.ReadUInt32LittleEndian(locator.AsSpan(16)) != 1)
            {
                throw Invalid("zip64_locator", "ZIP64 locator is invalid");
            }
            var zip64Offset = CheckedLong(BinaryPrimitives.ReadUInt64LittleEndian(locator.AsSpan(8)), "ZIP64 offset");
            var zip64Header = ReadExact(stream, zip64Offset, 56);
            if (BinaryPrimitives.ReadUInt32LittleEndian(zip64Header) != 0x06064b50)
            {
                throw Invalid("zip64_record", "ZIP64 end record is invalid");
            }
            var recordSize = CheckedLong(BinaryPrimitives.ReadUInt64LittleEndian(zip64Header.AsSpan(4)), "ZIP64 record size");
            if (recordSize < 44 || checked(zip64Offset + 12 + recordSize) != locatorOffset ||
                BinaryPrimitives.ReadUInt32LittleEndian(zip64Header.AsSpan(16)) != 0 ||
                BinaryPrimitives.ReadUInt32LittleEndian(zip64Header.AsSpan(20)) != 0)
            {
                throw Invalid("zip64_record", "ZIP64 end record boundaries are invalid");
            }
            var entriesOnDisk = CheckedLong(BinaryPrimitives.ReadUInt64LittleEndian(zip64Header.AsSpan(24)), "ZIP64 entry count");
            entryCount = CheckedLong(BinaryPrimitives.ReadUInt64LittleEndian(zip64Header.AsSpan(32)), "ZIP64 entry count");
            centralSize = CheckedLong(BinaryPrimitives.ReadUInt64LittleEndian(zip64Header.AsSpan(40)), "ZIP64 central size");
            centralOffset = CheckedLong(BinaryPrimitives.ReadUInt64LittleEndian(zip64Header.AsSpan(48)), "ZIP64 central offset");
            if (entriesOnDisk != entryCount)
            {
                throw Invalid("archive_split", "ZIP64 entry counts disagree");
            }
            centralEnd = zip64Offset;
        }
        else
        {
            if (entriesOnDisk16 != entryCount16)
            {
                throw Invalid("archive_split", "ZIP entry counts disagree");
            }
            entryCount = entryCount16;
            centralSize = centralSize32;
            centralOffset = centralOffset32;
            centralEnd = eocdOffset;
        }

        if (entryCount is < 1 or > MaximumEntries || centralOffset < 0 || centralSize < 0 ||
            checked(centralOffset + centralSize) != centralEnd)
        {
            throw Invalid("central_directory", "central directory boundaries are invalid");
        }

        var entries = new List<PetPackZipEntry>((int)entryCount);
        var exactPaths = new HashSet<string>(StringComparer.Ordinal);
        var foldedPaths = new HashSet<string>(StringComparer.Ordinal);
        var cursor = centralOffset;
        long totalUncompressed = 0;
        for (long index = 0; index < entryCount; index++)
        {
            var fixedHeader = ReadExact(stream, cursor, 46);
            if (BinaryPrimitives.ReadUInt32LittleEndian(fixedHeader) != 0x02014b50)
            {
                throw Invalid("central_directory", "central directory entry is invalid");
            }
            var versionMadeBy = BinaryPrimitives.ReadUInt16LittleEndian(fixedHeader.AsSpan(4));
            var flags = BinaryPrimitives.ReadUInt16LittleEndian(fixedHeader.AsSpan(8));
            var method = BinaryPrimitives.ReadUInt16LittleEndian(fixedHeader.AsSpan(10));
            var crc32 = BinaryPrimitives.ReadUInt32LittleEndian(fixedHeader.AsSpan(16));
            var compressed32 = BinaryPrimitives.ReadUInt32LittleEndian(fixedHeader.AsSpan(20));
            var uncompressed32 = BinaryPrimitives.ReadUInt32LittleEndian(fixedHeader.AsSpan(24));
            var nameLength = BinaryPrimitives.ReadUInt16LittleEndian(fixedHeader.AsSpan(28));
            var extraLength = BinaryPrimitives.ReadUInt16LittleEndian(fixedHeader.AsSpan(30));
            var commentLength = BinaryPrimitives.ReadUInt16LittleEndian(fixedHeader.AsSpan(32));
            var diskStart16 = BinaryPrimitives.ReadUInt16LittleEndian(fixedHeader.AsSpan(34));
            var externalAttributes = BinaryPrimitives.ReadUInt32LittleEndian(fixedHeader.AsSpan(38));
            var localOffset32 = BinaryPrimitives.ReadUInt32LittleEndian(fixedHeader.AsSpan(42));
            if ((flags & 0x0001) != 0 || (flags & 0x0040) != 0 || method is not (0 or 8) ||
                nameLength == 0 || commentLength != 0)
            {
                throw Invalid("unsupported_zip", "archive uses encryption, comments, or unsupported compression");
            }
            var variable = ReadExact(stream, cursor + 46, checked(nameLength + extraLength));
            var nameBytes = variable.AsSpan(0, nameLength);
            var extra = variable.AsSpan(nameLength, extraLength);
            var path = DecodeName(nameBytes, flags);
            ValidatePath(path);
            if (!exactPaths.Add(path) || !foldedPaths.Add(path.ToUpperInvariant()))
            {
                throw Invalid("path_conflict", "archive contains duplicate or cross-platform conflicting paths");
            }

            var needUncompressed = uncompressed32 == uint.MaxValue;
            var needCompressed = compressed32 == uint.MaxValue;
            var needOffset = localOffset32 == uint.MaxValue;
            var needDisk = diskStart16 == ushort.MaxValue;
            var zip64 = ParseZip64(extra, needUncompressed, needCompressed, needOffset, needDisk);
            var uncompressed = needUncompressed ? zip64.Uncompressed : uncompressed32;
            var compressed = needCompressed ? zip64.Compressed : compressed32;
            var localOffset = needOffset ? zip64.Offset : localOffset32;
            var diskStart = needDisk ? zip64.Disk : diskStart16;
            if (diskStart != 0 || uncompressed < 0 || compressed < 0 || localOffset < 0 ||
                uncompressed > MaximumEntryBytes ||
                (path.EndsWith(".json", StringComparison.Ordinal) && uncompressed > MaximumJsonBytes) ||
                (compressed == 0 ? uncompressed != 0 : uncompressed / (double)compressed > MaximumCompressionRatio))
            {
                throw Invalid("entry_budget", "archive entry is outside the supported budget");
            }
            totalUncompressed = checked(totalUncompressed + uncompressed);
            if (totalUncompressed > MaximumUncompressedBytes)
            {
                throw Invalid("archive_budget", "expanded archive is outside the supported budget");
            }

            var host = versionMadeBy >> 8;
            var unixMode = host == 3 ? externalAttributes >> 16 : 0;
            if ((unixMode & 0xF000) == 0xA000 || (unixMode & 0x49) != 0)
            {
                throw Invalid("unsafe_entry", "symlink and executable entries are forbidden");
            }

            var local = ReadLocalRecord(stream, path, flags, method, crc32, compressed, uncompressed, localOffset, centralOffset);
            entries.Add(new(path, compressed, uncompressed, crc32, method, flags, localOffset,
                local.DataOffset, local.RecordEnd));
            cursor = checked(cursor + 46 + nameLength + extraLength + commentLength);
        }
        if (cursor != centralEnd)
        {
            throw Invalid("central_directory", "central directory size does not match its entries");
        }

        var ordered = entries.OrderBy(static entry => entry.LocalHeaderOffset).ToArray();
        var expectedOffset = 0L;
        foreach (var entry in ordered)
        {
            if (entry.LocalHeaderOffset != expectedOffset)
            {
                throw Invalid("archive_gap", "archive local records are not contiguous");
            }
            expectedOffset = entry.LocalRecordEnd;
        }
        if (expectedOffset != centralOffset)
        {
            throw Invalid("archive_gap", "archive has data outside declared local records");
        }
        return new(archivePath, length, totalUncompressed, entries);
    }

    public void Extract(PetPackZipIndex index, string destinationRoot)
    {
        var root = Path.GetFullPath(destinationRoot);
        if (!Directory.Exists(root) || Directory.EnumerateFileSystemEntries(root).Any())
        {
            throw Invalid("extract_destination", "extraction destination must be an empty existing directory");
        }
        EnsureNoReparsePoint(root, root);

        try
        {
            using var file = new FileStream(index.ArchivePath, FileMode.Open, FileAccess.Read, FileShare.Read,
                bufferSize: 1 << 20, FileOptions.SequentialScan);
            using var archive = new ZipArchive(file, ZipArchiveMode.Read, leaveOpen: false, StrictUtf8);
            var archiveEntries = archive.Entries.ToDictionary(static entry => entry.FullName, StringComparer.Ordinal);
            if (archiveEntries.Count != index.Entries.Count)
            {
                throw Invalid("central_directory", "runtime ZIP view differs from the validated index");
            }
            foreach (var expected in index.Entries)
            {
                if (!archiveEntries.TryGetValue(expected.Path, out var entry) ||
                    entry.Length != expected.UncompressedSize || entry.CompressedLength != expected.CompressedSize)
                {
                    throw Invalid("central_directory", "runtime ZIP entry differs from the validated index");
                }
                var destination = ResolveDestination(root, expected.Path);
                var parent = Path.GetDirectoryName(destination)!;
                Directory.CreateDirectory(parent);
                EnsureNoReparsePoint(root, parent);
                using var input = entry.Open();
                using var output = new FileStream(destination, FileMode.CreateNew, FileAccess.Write, FileShare.None,
                    bufferSize: 1 << 20, FileOptions.SequentialScan);
                var crc = new Crc32Accumulator();
                var buffer = new byte[1 << 20];
                long copied = 0;
                int count;
                while ((count = input.Read(buffer, 0, buffer.Length)) != 0)
                {
                    copied = checked(copied + count);
                    if (copied > expected.UncompressedSize)
                    {
                        throw Invalid("entry_size", "expanded entry exceeds its declared size");
                    }
                    crc.Append(buffer.AsSpan(0, count));
                    output.Write(buffer, 0, count);
                }
                output.Flush(flushToDisk: true);
                if (copied != expected.UncompressedSize || crc.Value != expected.Crc32)
                {
                    throw Invalid("entry_crc", "expanded entry differs from its ZIP checksum");
                }
            }
        }
        catch (PetPackException)
        {
            throw;
        }
        catch (Exception exception) when (exception is IOException or InvalidDataException or UnauthorizedAccessException)
        {
            throw new PetPackException("extract_failed", "archive could not be safely extracted", exception);
        }
    }

    public static string ResolveDestination(string root, string relativePath)
    {
        var destination = Path.GetFullPath(Path.Combine(root, relativePath.Replace('/', Path.DirectorySeparatorChar)));
        var prefix = root.EndsWith(Path.DirectorySeparatorChar) ? root : root + Path.DirectorySeparatorChar;
        if (!destination.StartsWith(prefix, StringComparison.Ordinal))
        {
            throw Invalid("unsafe_path", "archive entry escapes the runtime root");
        }
        return destination;
    }

    public static void ValidatePath(string path)
    {
        if (string.IsNullOrEmpty(path) || path.Length > 240 || path[0] == '/' || path[^1] == '/' ||
            path.Contains('\\', StringComparison.Ordinal) || path.Contains(':', StringComparison.Ordinal) ||
            !path.IsNormalized(NormalizationForm.FormC) || path.Any(char.IsControl))
        {
            throw Invalid("unsafe_path", "archive entry path is not portable");
        }
        var segments = path.Split('/', StringSplitOptions.None);
        foreach (var segment in segments)
        {
            if (segment is "" or "." or ".." || segment.EndsWith(' ') || segment.EndsWith('.') ||
                WindowsReservedNames.Contains(segment.Split('.')[0]))
            {
                throw Invalid("unsafe_path", "archive entry path is not portable");
            }
        }
    }

    private static (long DataOffset, long RecordEnd) ReadLocalRecord(FileStream stream, string expectedPath,
        ushort expectedFlags, ushort expectedMethod, uint expectedCrc, long expectedCompressed,
        long expectedUncompressed, long localOffset, long centralOffset)
    {
        var header = ReadExact(stream, localOffset, 30);
        if (BinaryPrimitives.ReadUInt32LittleEndian(header) != 0x04034b50)
        {
            throw Invalid("local_header", "local ZIP header is invalid");
        }
        var flags = BinaryPrimitives.ReadUInt16LittleEndian(header.AsSpan(6));
        var method = BinaryPrimitives.ReadUInt16LittleEndian(header.AsSpan(8));
        var crc = BinaryPrimitives.ReadUInt32LittleEndian(header.AsSpan(14));
        var compressed32 = BinaryPrimitives.ReadUInt32LittleEndian(header.AsSpan(18));
        var uncompressed32 = BinaryPrimitives.ReadUInt32LittleEndian(header.AsSpan(22));
        var nameLength = BinaryPrimitives.ReadUInt16LittleEndian(header.AsSpan(26));
        var extraLength = BinaryPrimitives.ReadUInt16LittleEndian(header.AsSpan(28));
        var variable = ReadExact(stream, localOffset + 30, checked(nameLength + extraLength));
        var path = DecodeName(variable.AsSpan(0, nameLength), flags);
        if (path != expectedPath || flags != expectedFlags || method != expectedMethod)
        {
            throw Invalid("local_header", "local and central ZIP headers disagree");
        }
        var hasDescriptor = (flags & 0x0008) != 0;
        if (!hasDescriptor && (crc != expectedCrc ||
            (compressed32 != uint.MaxValue && compressed32 != expectedCompressed) ||
            (uncompressed32 != uint.MaxValue && uncompressed32 != expectedUncompressed)))
        {
            throw Invalid("local_header", "local ZIP sizes disagree with the central directory");
        }
        var dataOffset = checked(localOffset + 30 + nameLength + extraLength);
        var recordEnd = checked(dataOffset + expectedCompressed);
        if (recordEnd > centralOffset)
        {
            throw Invalid("local_header", "local ZIP data overlaps the central directory");
        }
        if (hasDescriptor)
        {
            var zip64 = expectedCompressed > uint.MaxValue || expectedUncompressed > uint.MaxValue;
            var first = ReadUInt32(stream, recordEnd);
            var signed = first == 0x08074b50;
            var descriptorOffset = recordEnd + (signed ? 4 : 0);
            var size = zip64 ? 20 : 12;
            var descriptor = ReadExact(stream, descriptorOffset, size);
            var descriptorCrc = BinaryPrimitives.ReadUInt32LittleEndian(descriptor);
            var descriptorCompressed = zip64
                ? CheckedLong(BinaryPrimitives.ReadUInt64LittleEndian(descriptor.AsSpan(4)), "descriptor size")
                : BinaryPrimitives.ReadUInt32LittleEndian(descriptor.AsSpan(4));
            var descriptorUncompressed = zip64
                ? CheckedLong(BinaryPrimitives.ReadUInt64LittleEndian(descriptor.AsSpan(12)), "descriptor size")
                : BinaryPrimitives.ReadUInt32LittleEndian(descriptor.AsSpan(8));
            if (descriptorCrc != expectedCrc || descriptorCompressed != expectedCompressed ||
                descriptorUncompressed != expectedUncompressed)
            {
                throw Invalid("data_descriptor", "ZIP data descriptor disagrees with the central directory");
            }
            recordEnd = checked(descriptorOffset + size);
        }
        return (dataOffset, recordEnd);
    }

    private static (long Uncompressed, long Compressed, long Offset, long Disk) ParseZip64(
        ReadOnlySpan<byte> extra, bool needUncompressed, bool needCompressed, bool needOffset, bool needDisk)
    {
        var cursor = 0;
        byte[] payload = [];
        while (cursor + 4 <= extra.Length)
        {
            var id = BinaryPrimitives.ReadUInt16LittleEndian(extra[cursor..]);
            var length = BinaryPrimitives.ReadUInt16LittleEndian(extra[(cursor + 2)..]);
            cursor += 4;
            if (cursor + length > extra.Length)
            {
                throw Invalid("zip_extra", "ZIP extra field is truncated");
            }
            if (id == 0x0001)
            {
                if (payload.Length != 0)
                {
                    throw Invalid("zip64_extra", "ZIP64 extra field is duplicated");
                }
                payload = extra.Slice(cursor, length).ToArray();
            }
            cursor += length;
        }
        if (cursor != extra.Length || ((needUncompressed || needCompressed || needOffset || needDisk) && payload.Length == 0))
        {
            throw Invalid("zip64_extra", "ZIP64 extra field is missing or malformed");
        }
        var position = 0;
        long Read64(bool needed)
        {
            if (!needed)
            {
                return -1;
            }
            if (position + 8 > payload.Length)
            {
                throw Invalid("zip64_extra", "ZIP64 extra field is truncated");
            }
            var value = CheckedLong(BinaryPrimitives.ReadUInt64LittleEndian(payload.AsSpan(position)), "ZIP64 value");
            position += 8;
            return value;
        }
        var uncompressed = Read64(needUncompressed);
        var compressed = Read64(needCompressed);
        var offset = Read64(needOffset);
        long disk = -1;
        if (needDisk)
        {
            if (position + 4 > payload.Length)
            {
                throw Invalid("zip64_extra", "ZIP64 disk value is truncated");
            }
            disk = BinaryPrimitives.ReadUInt32LittleEndian(payload.AsSpan(position));
        }
        return (uncompressed, compressed, offset, disk);
    }

    private static string DecodeName(ReadOnlySpan<byte> bytes, ushort flags)
    {
        try
        {
            var hasNonAscii = false;
            foreach (var value in bytes)
            {
                if (value < 0x80)
                {
                    continue;
                }
                hasNonAscii = true;
                break;
            }
            if ((flags & 0x0800) == 0 && hasNonAscii)
            {
                throw Invalid("path_encoding", "non-ASCII ZIP paths must declare UTF-8");
            }
            return StrictUtf8.GetString(bytes);
        }
        catch (DecoderFallbackException exception)
        {
            throw new PetPackException("path_encoding", "ZIP path is not valid UTF-8", exception);
        }
    }

    private static void EnsureNoReparsePoint(string root, string path)
    {
        var current = Path.GetFullPath(path);
        while (true)
        {
            if ((File.GetAttributes(current) & FileAttributes.ReparsePoint) != 0)
            {
                throw Invalid("unsafe_destination", "extraction destination contains a reparse point");
            }
            if (string.Equals(current, root, StringComparison.Ordinal))
            {
                return;
            }
            current = Path.GetDirectoryName(current)
                ?? throw Invalid("unsafe_destination", "extraction destination escapes its root");
        }
    }

    private static byte[] ReadExact(FileStream stream, long offset, int count)
    {
        if (offset < 0 || count < 0 || offset > stream.Length - count)
        {
            throw Invalid("archive_truncated", "ZIP structure is truncated");
        }
        var buffer = new byte[count];
        stream.Position = offset;
        var total = 0;
        while (total < count)
        {
            var read = stream.Read(buffer, total, count - total);
            if (read == 0)
            {
                throw Invalid("archive_truncated", "ZIP structure is truncated");
            }
            total += read;
        }
        return buffer;
    }

    private static uint ReadUInt32(FileStream stream, long offset) =>
        BinaryPrimitives.ReadUInt32LittleEndian(ReadExact(stream, offset, 4));

    private static long CheckedLong(ulong value, string field)
    {
        if (value > long.MaxValue)
        {
            throw Invalid("archive_budget", $"{field} exceeds the supported range");
        }
        return (long)value;
    }

    private static PetPackException Invalid(string code, string detail) => new(code, detail);
}

internal sealed class Crc32Accumulator
{
    private static readonly uint[] Table = BuildTable();
    private uint state = uint.MaxValue;

    public uint Value => state ^ uint.MaxValue;

    public void Append(ReadOnlySpan<byte> bytes)
    {
        foreach (var value in bytes)
        {
            state = Table[(state ^ value) & 0xff] ^ (state >> 8);
        }
    }

    private static uint[] BuildTable()
    {
        var table = new uint[256];
        for (uint index = 0; index < table.Length; index++)
        {
            var value = index;
            for (var bit = 0; bit < 8; bit++)
            {
                value = (value & 1) != 0 ? 0xedb88320 ^ (value >> 1) : value >> 1;
            }
            table[index] = value;
        }
        return table;
    }
}
