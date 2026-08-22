namespace PetsGraph.Core.Tests;

[TestClass]
public sealed class PetPackageLoaderTests
{
    [TestMethod]
    public void LoadsApprovedSchema04PackageAndVerifiesIntegrity()
    {
        using var fixture = new TestPackageFixture();
        var package = new PetPackageLoader().Load(fixture.RootPath, verifyIntegrity: true);

        Assert.AreEqual("testcat", package.Manifest.Pet.Id);
        Assert.HasCount(4, package.Clips);
        Assert.AreEqual("quiet-sleep-companion", package.Behavior.Profile);
    }

    [TestMethod]
    public void RejectsGraphPathThatEscapesPackageRoot()
    {
        using var fixture = new TestPackageFixture();
        var manifestPath = Path.Combine(fixture.RootPath, "package.json");
        var text = File.ReadAllText(manifestPath).Replace("\"graph\": \"graph.json\"", "\"graph\": \"../graph.json\"");
        File.WriteAllText(manifestPath, text);

        var exception = Assert.Throws<PetPackageValidationException>(() => new PetPackageLoader().Load(fixture.RootPath));
        StringAssert.Contains(exception.Message, "escaping file");
    }

    [TestMethod]
    public void LoadsReleasedPackagesWhenExplicitlyProvided()
    {
        var petsDirectory = Environment.GetEnvironmentVariable("PETSGRAPH_TEST_PETS_DIR");
        if (string.IsNullOrWhiteSpace(petsDirectory) || !Directory.Exists(petsDirectory))
        {
            return;
        }

        var paths = PetPackageLoader.FindPackages(petsDirectory).ToArray();
        Assert.IsGreaterThanOrEqualTo(paths.Length, 2, "Expected the released dual-pet package set.");
        foreach (var path in paths)
        {
            var package = new PetPackageLoader().Load(path);
            using var renderer = new RgbaFrameRenderer(package);
            var buffer = new byte[renderer.BufferLength];
            var firstNode = package.Graph.Nodes[0];
            renderer.RenderPbgra32(firstNode.LoopClip, 0, buffer);
            Assert.IsTrue(buffer.Any(value => value != 0), $"{package.Manifest.Pet.Id} first frame should render pixels.");
        }
    }
}
