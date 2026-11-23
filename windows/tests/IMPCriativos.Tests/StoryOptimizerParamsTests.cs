using IMPCriativos.Core.Story;
using IMPCriativos.Core.Util;
using Xunit;

namespace IMPCriativos.Tests;

/// <summary>Otimizador em Lote (1.0.0-beta.21): sorteio, presets, nomes e cor dominante. Porte de StoryOptimizerParamsTests.swift.</summary>
public class StoryOptimizerParamsTests
{
    private static StoryOptions Options(StoryIntensity intensity, StoryOutputFormat format = StoryOutputFormat.Jpg) =>
        new() { Intensity = intensity, Format = format };

    private static bool In(double v, double lo, double hi) => v >= lo && v <= hi;

    [Fact]
    public void SameSeedGivesSameParams()
    {
        var o = Options(StoryIntensity.Moderate);
        Assert.Equal(StoryParams.Sample(o, 42), StoryParams.Sample(o, 42));
    }

    [Fact]
    public void DifferentSeedsGiveDifferentParams()
    {
        var o = Options(StoryIntensity.Moderate);
        var codes = new HashSet<string>();
        for (ulong s = 0; s < 500; s++) codes.Add(StoryParams.Sample(o, s).Code);
        Assert.True(codes.Count > 495);
    }

    [Fact]
    public void ModerateStaysWithinRequestedRanges()
    {
        var o = Options(StoryIntensity.Moderate);
        for (ulong s = 0; s < 2000; s++)
        {
            var p = StoryParams.Sample(o, unchecked(s * 2_654_435_761));
            Assert.True(In(p.CropFraction, 0.005, 0.015));
            Assert.True(Math.Abs(p.RotationDegrees) <= 0.8);
            Assert.True(Math.Abs(p.Brightness) <= 0.02);
            Assert.True(Math.Abs(p.Contrast) <= 0.02);
            Assert.True(Math.Abs(p.Saturation) <= 0.03);
            Assert.True(In(p.NoiseAmplitude, 2, 4));
            Assert.True(In(p.GrainOpacity, 0.01, 0.03));
            Assert.NotNull(p.ChromaticChannel);
            Assert.Equal(1, Math.Abs(p.ChromaticDX) + Math.Abs(p.ChromaticDY));
            Assert.InRange(p.Quality, 88, 93);
            Assert.True(p.SharpenIntensity == 0 ? p.SoftenRadius == 0.2 : In(p.SharpenIntensity, 0.2, 0.4) && p.SoftenRadius == 0);
            Assert.True(In(p.CropShiftX, -1, 1) && In(p.CropShiftY, -1, 1));
            Assert.Equal(5, p.Code.Length);
            Assert.False(p.Mirror);
        }
    }

    [Fact]
    public void LightIsSubtlerAndSkipsChannelShiftAndGrain()
    {
        var o = Options(StoryIntensity.Light);
        for (ulong s = 0; s < 1000; s++)
        {
            var p = StoryParams.Sample(o, s);
            Assert.True(p.CropFraction <= 0.008 + 1e-12);
            Assert.True(Math.Abs(p.RotationDegrees) <= 0.3);
            Assert.True(Math.Abs(p.Brightness) <= 0.01);
            Assert.True(p.NoiseAmplitude <= 2.5);
            Assert.Null(p.ChromaticChannel);
            Assert.Equal(0, p.GrainOpacity);
        }
    }

    [Fact]
    public void NormalAndAggressiveRanges()
    {
        foreach (var (intensity, a) in new[] { (StoryIntensity.Normal, StoryAdjustments.Normal), (StoryIntensity.Aggressive, StoryAdjustments.Aggressive) })
        {
            var o = Options(intensity);
            var periods = new HashSet<int>();
            var anti = new HashSet<bool>();
            var twoPx = false;
            for (ulong s = 0; s < 1500; s++)
            {
                var p = StoryParams.Sample(o, unchecked(s * 6_364_136_223_846_793_005));
                Assert.True(In(p.CropFraction, a.CropMinPercent / 100 - 1e-12, a.CropMaxPercent / 100 + 1e-12));
                Assert.True(Math.Abs(p.RotationDegrees) <= a.RotationMaxDegrees);
                Assert.True(Math.Abs(p.Brightness) <= a.BrightnessMaxPercent / 100 + 1e-12);
                Assert.True(Math.Abs(p.Saturation) <= a.SaturationMaxPercent / 100 + 1e-12);
                Assert.True(Math.Abs(p.TemperatureKelvin) <= a.TemperatureMaxKelvin);
                Assert.True(In(p.NoiseAmplitude, a.NoiseMinAmplitude, a.NoiseMaxAmplitude));
                Assert.True(In(p.DiagonalAmplitude, a.DiagonalMinAmplitude, a.DiagonalMaxAmplitude));
                Assert.True(In(p.GrainOpacity, a.GrainMinOpacityPercent / 100 - 1e-12, a.GrainMaxOpacityPercent / 100 + 1e-12));
                Assert.True(Math.Abs(p.Vignette) <= a.VignetteMaxPercent / 100 + 1e-12);
                Assert.Equal(8, p.Perspective.Length);
                Assert.All(p.Perspective, v => Assert.True(Math.Abs(v) <= a.PerspectiveMaxPercent / 100 + 1e-12));
                Assert.InRange(p.DiagonalPhase, 0, p.DiagonalPeriod - 1);
                var shift = Math.Abs(p.ChromaticDX) + Math.Abs(p.ChromaticDY);
                Assert.InRange(shift, 1, a.ChromaticMaxPixels);
                if (shift == 2) twoPx = true;
                periods.Add(p.DiagonalPeriod);
                anti.Add(p.DiagonalAnti);
            }
            Assert.Equal(new HashSet<int> { 3, 4 }, periods);
            Assert.Equal(new HashSet<bool> { true, false }, anti);
            Assert.Equal(intensity == StoryIntensity.Aggressive, twoPx);
        }
        Assert.True(StoryAdjustments.Aggressive.CropMaxPercent > StoryAdjustments.Normal.CropMaxPercent);
        Assert.True(StoryAdjustments.Normal.CropMaxPercent > StoryAdjustments.Moderate.CropMaxPercent);
    }

    [Fact]
    public void OlderLevelsKeepNewStepsOff()
    {
        foreach (var i in new[] { StoryIntensity.Light, StoryIntensity.Moderate })
        {
            var p = StoryParams.Sample(Options(i), 77);
            Assert.Equal(0, p.DiagonalAmplitude);
            Assert.Empty(p.Perspective);
            Assert.Equal(0, p.TemperatureKelvin);
            Assert.Equal(0, p.Vignette);
        }
    }

    [Fact]
    public void DiagonalPatternDarkensLightensAndKeeps()
    {
        foreach (var period in new[] { 3, 4 })
        foreach (var anti in new[] { false, true })
        {
            var sum = 0;
            var seen = new HashSet<int>();
            for (var y = 0; y < 12; y++)
            for (var x = 0; x < 12; x++)
            {
                var v = StoryParams.DiagonalSign(x, y, period, anti, 1);
                sum += v;
                seen.Add(v);
                var (nx, ny) = anti ? (x + 1, y + 1) : (x + 1, y - 1);
                Assert.Equal(v, StoryParams.DiagonalSign(nx, ny, period, anti, 1));
            }
            Assert.Equal(new HashSet<int> { -1, 0, 1 }, seen);
            Assert.Equal(0, sum);
        }
    }

    [Fact]
    public void VersionsHaveDistinctSeedsAndNames()
    {
        var seeds = Enumerable.Range(1, 10).Select(v => StoryVersions.Seed(42, v)).ToList();
        Assert.Equal(42UL, seeds[0]);
        Assert.Equal(10, seeds.Distinct().Count());
        Assert.Equal("story_003_v2_abcde.jpg", StoryNames.FileName(3, 50, "story", "abcde", StoryNaming.SequentialCode, "jpg", 2));
        Assert.Equal(10, new StoryOptions { VersionsPerImage = 99 }.Versions);
    }

    [Fact]
    public void OldSavedCustomAdjustmentsStillDecode()
    {
        var o = Json.Deserialize<StoryOptions>("""{"intensity":"custom","custom":{"geometry":false,"noiseMaxAmplitude":3}}""")!;
        Assert.Equal(StoryIntensity.Custom, o.Intensity);
        Assert.False(o.Custom.Geometry);
        Assert.Equal(3, o.Custom.NoiseMaxAmplitude);
        Assert.False(o.Custom.Diagonal);
        Assert.Equal(1, o.Versions);
    }

    [Fact]
    public void AllQualitiesAndBothJPEGModesAppear()
    {
        var o = Options(StoryIntensity.Moderate);
        var q = new HashSet<int>();
        var prog = new HashSet<bool>();
        var chroma = new HashSet<bool>();
        for (ulong s = 0; s < 500; s++)
        {
            var p = StoryParams.Sample(o, s);
            q.Add(p.Quality); prog.Add(p.Progressive); chroma.Add(p.Chroma444);
        }
        Assert.Equal(Enumerable.Range(88, 6).ToHashSet(), q);
        Assert.Equal(2, prog.Count);
        Assert.Equal(2, chroma.Count);
    }

    [Fact]
    public void PNGNeverVariesJPEGEncoding()
    {
        var o = Options(StoryIntensity.Moderate, StoryOutputFormat.Png);
        for (ulong s = 0; s < 200; s++)
        {
            var p = StoryParams.Sample(o, s);
            Assert.False(p.Progressive);
            Assert.False(p.Chroma444);
        }
    }

    [Fact]
    public void TurningOffOneStepKeepsTheOthers()
    {
        var o = Options(StoryIntensity.Custom);
        var before = StoryParams.Sample(o, 7);
        o.Custom.Noise = false;
        o.Custom.ChromaticShift = false;
        var after = StoryParams.Sample(o, 7);
        Assert.Equal(0, after.NoiseAmplitude);
        Assert.Null(after.ChromaticChannel);
        Assert.Equal(before.CropFraction, after.CropFraction);
        Assert.Equal(before.RotationDegrees, after.RotationDegrees);
        Assert.Equal(before.Brightness, after.Brightness);
        Assert.Equal(before.GrainOpacity, after.GrainOpacity);
        Assert.Equal(before.Quality, after.Quality);
        Assert.Equal(before.Code, after.Code);
    }

    [Fact]
    public void EverythingOffIsNeutralExceptEncoding()
    {
        var o = Options(StoryIntensity.Custom);
        o.Custom.Geometry = false;
        o.Custom.Photometric = false;
        o.Custom.Noise = false;
        o.Custom.ChromaticShift = false;
        o.Custom.FilmGrain = false;
        o.Custom.Detail = false;
        o.Custom.JpegVariation = false;
        var p = StoryParams.Sample(o, 99);
        Assert.Equal(0, p.CropFraction);
        Assert.Equal(0, p.RotationDegrees);
        Assert.Equal(0, p.Brightness);
        Assert.Equal(0, p.NoiseAmplitude);
        Assert.Equal(0, p.GrainOpacity);
        Assert.Equal(0, p.SharpenIntensity);
        Assert.Equal(0, p.SoftenRadius);
        Assert.False(p.Progressive);
        Assert.InRange(p.Quality, 88, 93);
    }

    [Fact]
    public void MirrorOnlyWhenEnabled()
    {
        var o = Options(StoryIntensity.Light);
        Assert.False(StoryParams.Sample(o, 1).Mirror);
        o.Mirror = true;
        Assert.True(StoryParams.Sample(o, 1).Mirror);
    }

    [Fact]
    public void CustomValuesAreClampedToRequestedLimits()
    {
        var o = Options(StoryIntensity.Custom);
        o.Custom.CropMaxPercent = 9;
        o.Custom.RotationMaxDegrees = 5;
        o.Custom.NoiseMaxAmplitude = 50;
        o.Custom.GrainMaxOpacityPercent = double.NaN;
        o.Custom.DiagonalMaxAmplitude = 99;
        o.Custom.ChromaticMaxPixels = 7;
        o.Custom.NoiseMinAmplitude = 6;
        o.Custom.NoiseMaxAmplitude = 3;
        var a = o.Adjustments;
        Assert.Equal(5, a.CropMaxPercent);
        Assert.Equal(3, a.RotationMaxDegrees);
        Assert.Equal(3, a.NoiseMaxAmplitude);
        Assert.Equal(3, a.NoiseMinAmplitude);
        Assert.Equal(1, a.GrainMaxOpacityPercent);
        Assert.Equal(12, a.DiagonalMaxAmplitude);
        Assert.Equal(2, a.ChromaticMaxPixels);
    }

    [Fact]
    public void RotationZoomCoversCorners()
    {
        Assert.Equal(1, StoryParams.RotationZoom(1080, 1920, 0));
        var z = StoryParams.RotationZoom(1080, 1920, 0.8);
        Assert.True(z > 1.02 && z < 1.03);
        Assert.Equal(z, StoryParams.RotationZoom(1080, 1920, -0.8), 12);
    }

    [Fact]
    public void FileNames()
    {
        Assert.Equal("story_001_a8f3k.jpg", StoryNames.FileName(1, 100, "story", "a8f3k", StoryNaming.SequentialCode, "jpg"));
        Assert.Equal("story_042.png", StoryNames.FileName(42, 7, "story", "x", StoryNaming.Sequential, "png"));
        Assert.Equal("promocao_marco_0007.jpg", StoryNames.FileName(7, 1000, "Promoção Março!", "abcde", StoryNaming.Sequential, "jpg"));
        Assert.Equal("story", StoryNames.CleanPrefix("   "));
    }

    [Fact]
    public void DecodingOldOrPartialSettingsKeepsDefaults()
    {
        var o = Json.Deserialize<StoryOptions>("""{"fit":"solid","prefix":"cliente"}""")!;
        Assert.Equal(StoryFit.Solid, o.Fit);
        Assert.Equal("cliente", o.Prefix);
        Assert.Equal(StoryIntensity.Light, o.Intensity);
        Assert.False(o.Mirror);
    }

    [Fact]
    public void DominantColorPicksMostFrequent()
    {
        var px = new List<byte>();
        for (var i = 0; i < 70; i++) px.AddRange(new byte[] { 220, 30, 30, 255 });
        for (var i = 0; i < 30; i++) px.AddRange(new byte[] { 20, 20, 200, 255 });
        for (var i = 0; i < 50; i++) px.AddRange(new byte[] { 0, 255, 0, 10 });
        var c = DominantColor.Compute(px.ToArray());
        Assert.NotNull(c);
        Assert.Equal(220.0 / 255, c!.R, 2);
        Assert.Equal(30.0 / 255, c.B, 2);
        Assert.Null(DominantColor.Compute(new byte[] { 0, 0, 0, 0 }));
    }

    [Fact]
    public void SplitMix64MatchesKnownValues()
    {
        // valores de referência do SplitMix64 (semente 0), iguais ao SeededRandom do Swift
        var r = new SeededRandom(0);
        Assert.Equal(0xE220A8397B1DCDAFUL, r.Next());
        Assert.Equal(0x6E789E6AA1B965F4UL, r.Next());
        Assert.Equal(0x06C45D188009454FUL, r.Next());
    }
}
