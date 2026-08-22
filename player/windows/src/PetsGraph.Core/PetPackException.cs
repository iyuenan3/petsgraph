namespace PetsGraph.Core;

public sealed class PetPackException(string code, string detail, Exception? innerException = null)
    : Exception($"PetPack {code}: {detail}", innerException)
{
    public string Code { get; } = code;
    public string Detail { get; } = detail;
}
