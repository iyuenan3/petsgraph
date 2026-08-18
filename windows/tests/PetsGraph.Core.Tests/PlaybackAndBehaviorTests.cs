namespace PetsGraph.Core.Tests;

[TestClass]
public sealed class PlaybackAndBehaviorTests
{
    [TestMethod]
    public void RendererSwizzlesPremultipliedRgbaToPbgra()
    {
        using var fixture = new TestPackageFixture();
        var package = new PetPackageLoader().Load(fixture.RootPath);
        using var renderer = new RgbaFrameRenderer(package);
        var buffer = new byte[renderer.BufferLength];

        renderer.RenderPbgra32("rest-loop", 0, buffer);

        CollectionAssert.AreEqual(new byte[] { 30, 20, 10, 255, 60, 50, 40, 128 }, buffer);
        Assert.IsTrue(RgbaFrameRenderer.IsOpaqueEnough(buffer, 2, 1, 0, 0));
        Assert.IsFalse(RgbaFrameRenderer.IsOpaqueEnough(buffer, 2, 1, 2, 0));
    }

    [TestMethod]
    public void ClickWakesThenReturnsToThePreviousSleepPose()
    {
        using var fixture = new TestPackageFixture();
        var package = new PetPackageLoader().Load(fixture.RootPath);
        var session = new QuietBehaviorSession(package, randomSeed: 1);
        session.Start(0);

        Assert.AreEqual(PetClickResult.WakeStarted, session.HandlePetClick(1));
        Assert.AreEqual(QuietInteractionState.Waking, session.Update(1.05).State);
        Assert.AreEqual(QuietInteractionState.Sitting, session.Update(1.25).State);

        Assert.AreEqual(PetClickResult.SleepStarted, session.HandlePetClick(2));
        Assert.AreEqual(QuietInteractionState.Sleeping, session.Update(2.25).State);
        Assert.AreEqual("rest.floor", session.CurrentNodeId);
    }

    [TestMethod]
    public void TimelineRepeatsLoopFramesWithoutEnding()
    {
        using var fixture = new TestPackageFixture();
        var package = new PetPackageLoader().Load(fixture.RootPath);
        var timeline = new PlaybackTimeline(package.Clips, package.DemoSequence);

        Assert.AreEqual("rest-loop", timeline.Sample(10).ClipId);
        Assert.AreEqual(0, timeline.Sample(10).SourceFrameIndex);
        Assert.AreEqual(0, timeline.FiniteDurationSeconds, 0.000001);
    }
}
