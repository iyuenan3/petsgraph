using System.Text.Json;
using System.Text.Json.Serialization;

namespace PetsGraph.Core;

public static class StrictJson
{
    public static readonly JsonSerializerOptions ReadOptions = new()
    {
        AllowTrailingCommas = false,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = false,
        ReadCommentHandling = JsonCommentHandling.Disallow,
        RespectNullableAnnotations = true,
        UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow,
    };

    public static readonly JsonSerializerOptions WriteOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true,
    };

    public static T Decode<T>(byte[] data, string logicalPath)
    {
        RejectDuplicateKeys(data, logicalPath);
        try
        {
            return JsonSerializer.Deserialize<T>(data, ReadOptions)
                ?? throw new JsonException("document is null");
        }
        catch (JsonException exception)
        {
            throw new PetPackException("invalid_json", $"{logicalPath} does not match PetPack 1.0", exception);
        }
    }

    public static T DecodeFile<T>(string path, string logicalPath)
    {
        try
        {
            return Decode<T>(File.ReadAllBytes(path), logicalPath);
        }
        catch (IOException exception)
        {
            throw new PetPackException("read_failed", $"could not read {logicalPath}", exception);
        }
    }

    private static void RejectDuplicateKeys(ReadOnlySpan<byte> data, string logicalPath)
    {
        try
        {
            var reader = new Utf8JsonReader(data, new JsonReaderOptions
            {
                AllowTrailingCommas = false,
                CommentHandling = JsonCommentHandling.Disallow,
                MaxDepth = 128,
            });
            var scopes = new Stack<HashSet<string>?>();
            while (reader.Read())
            {
                switch (reader.TokenType)
                {
                    case JsonTokenType.StartObject:
                        scopes.Push(new(StringComparer.Ordinal));
                        break;
                    case JsonTokenType.StartArray:
                        scopes.Push(null);
                        break;
                    case JsonTokenType.EndObject:
                    case JsonTokenType.EndArray:
                        if (scopes.Count == 0)
                        {
                            throw new JsonException("unbalanced JSON container");
                        }
                        scopes.Pop();
                        break;
                    case JsonTokenType.PropertyName:
                        if (scopes.Count == 0 || scopes.Peek() is not { } names ||
                            !names.Add(reader.GetString() ?? ""))
                        {
                            throw new JsonException("duplicate JSON object key");
                        }
                        break;
                }
            }
            if (scopes.Count != 0)
            {
                throw new JsonException("unterminated JSON container");
            }
        }
        catch (JsonException exception)
        {
            throw new PetPackException("invalid_json", $"{logicalPath} is not strict JSON", exception);
        }
    }
}
