using System.Text.Json;
using IMPCriativos.Core.Story;
using IMPCriativos.Core.Util;
using SkiaSharp;
using Xunit;
using Xunit.Abstractions;

namespace IMPCriativos.Tests;

/// <summary>
/// Texturas, linhas e bordas: sorteio e opções (puros), efeitos nos pixels (CPU) e o motor (aberração e bloom).
/// Porte de Tests/IMPCriativosLogicTests/StoryTextureTests.swift. As duas folhas de amostra com texto de verdade
/// (níveis e direções das linhas) só existem no Mac, porque dependem do CoreText; o resto é o mesmo.
/// </summary>
[Collection("Preferencias")]
public sealed class StoryTextureTests : IDisposable
{
    private readonly ITestOutputHelper _out;
    private readonly string _tmp;
    private static readonly string? Samples = Environment.GetEnvironmentVariable("IMP_STORY_SAMPLES");

    public StoryTextureTests(ITestOutputHelper output)
    {
        _out = output;
        _tmp = Path.Combine(Path.GetTempPath(), "texture-tests-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_tmp);
    }

    public void Dispose()
    {
        try { Directory.Delete(_tmp, true); } catch { }
    }

    // MARK: - Ajudantes

    private static byte[] Buffer(int w, int h, byte value = 128) => Enumerable.Repeat(value, w * h * 4).ToArray();

    private static void SetPixel(byte[] px, int x, int y, int width, byte v)
    {
        var o = (y * width + x) * 4;
        px[o] = v; px[o + 1] = v; px[o + 2] = v;
    }

    private static int Gray(byte[] px, int x, int y, int width) => px[(y * width + x) * 4 + 1];

    /// <summary>Opções com as linhas ligadas (Tom, direção aleatória) e o nível de texturas ainda em Desligado.</summary>
    private static StoryOptions TextureOptions => new() { Fit = StoryFit.Cover, LinesEnabled = true };

    private static StoryParams LinesParams(StoryLineDirection direction, StoryLineBlend blend = StoryLineBlend.HardLight) => new()
    {
        LineOpacity = 0.85, LineSpacing = 8, LineThickness = 4, LineDirection = direction, LineBlend = blend, LinePhase = 3, LinePhase2 = 5,
    };

    private static void Near(double expected, double actual, double accuracy, string? msg = null) =>
        Assert.True(Math.Abs(expected - actual) <= accuracy, $"{msg} esperado {expected} ± {accuracy}, veio {actual}");

    private static StoryOptions Decode(string json) => JsonSerializer.Deserialize<StoryOptions>(json, Json.Compact)!;

    private static StoryOptions RoundTrip(StoryOptions o) => Decode(JsonSerializer.Serialize(o, Json.Compact));

    // MARK: - Opções e sorteio

    [Fact]
    public void TexturesAreOffByDefaultAndDoNotChangeOlderValues()
    {
        var off = TextureOptions;
        var on = TextureOptions;
        on.TexturePreset = StoryTexturePreset.Intense;
        Assert.Equal(StoryTexturePreset.Off, off.TexturePreset);
        Assert.False(off.Texture.IsActive);
        foreach (var seed in new ulong[] { 1, 2, 3, 99, 12345, 987_654_321 })
        {
            var a = StoryParams.Sample(off, seed);
            var b = StoryParams.Sample(on, seed);
            Assert.False(a.HasTexture, "desligado de fábrica");
            Assert.True(b.HasTexture);
            Assert.Equal(a.Code, b.Code);
            Assert.Equal(a.CropFraction, b.CropFraction);
            Assert.Equal(a.RotationDegrees, b.RotationDegrees);
            Assert.Equal(a.NoiseAmplitude, b.NoiseAmplitude);
            Assert.Equal(a.Quality, b.Quality);
            Assert.Equal(a.DiagonalAmplitude, b.DiagonalAmplitude);
            Assert.Equal(a.Vignette, b.Vignette);
            Assert.Equal(a.GrainOpacity, b.GrainOpacity);
            Assert.False(b.WithoutTexture.HasTexture);
        }
    }

    [Fact]
    public void PresetsActivateTheEffectsTheyPromise()
    {
        for (ulong seed = 1; seed <= 40; seed++)
        {
            var o = TextureOptions;
            o.TexturePreset = StoryTexturePreset.Subtle;
            var s = StoryParams.Sample(o, seed);
            Assert.True(s.LineOpacity > 0);
            Assert.Equal(StoryLineStyle.Tone, s.LineStyle);
            Assert.True(s.LineOpacity <= StoryTexture.ToneAmplitude(0.3) + 1e-9, "linhas leves");
            Assert.Equal(10, s.LineSpacing);
            Assert.Equal(2, s.LineThickness);
            Near(55, s.LineAngle, 3.0001);
            Near(0.6, s.LineIrregularity, 1e-9);
            Assert.True(s.JitterLevel > 0);
            Assert.True(s.JitterLevel <= 0.15 + 1e-9, "serrilhado mínimo");
            Assert.True(s.AberrationDX != 0 || s.AberrationDY != 0);
            Assert.True(Math.Max(Math.Abs(s.AberrationDX), Math.Abs(s.AberrationDY)) <= 2, "micro-aberração");
            Assert.Equal(0, s.BloomLevel);

            o.TexturePreset = StoryTexturePreset.Balanced;
            var b = StoryParams.Sample(o, seed);
            Assert.Equal(StoryLineStyle.Tone, b.LineStyle);
            Assert.True(b.LineOpacity >= StoryTexture.ToneAmplitude(0.54) - 1e-9, "60%: visível");
            Assert.True(b.LineOpacity <= StoryTexture.ToneAmplitude(0.6) + 1e-9);
            Assert.Equal(9, b.LineSpacing);
            Assert.Equal(3, b.LineThickness);
            Assert.True(b.JitterLevel >= 0.45 * 0.7 - 1e-9);
            Assert.True(b.JitterLevel <= 0.45 + 1e-9);
            Assert.Equal(0, b.BloomLevel);
            Assert.True(Math.Max(Math.Abs(b.AberrationDX), Math.Abs(b.AberrationDY)) >= 1);

            o.TexturePreset = StoryTexturePreset.Intense;
            o.LineStyle = StoryLineStyle.Ink;
            o.LineDirection = StoryLineDirection.Cross;
            var i = StoryParams.Sample(o, seed);
            Assert.Equal(StoryLineDirection.Cross, i.LineDirection);
            Assert.Equal(StoryLineStyle.Ink, i.LineStyle);
            Assert.Equal(4, i.LineThickness);
            Assert.Equal(8, i.LineSpacing);
            Assert.True(i.BloomLevel >= 0.7 * 0.7 - 1e-9);
            Assert.True(i.BloomLevel <= 0.7 + 1e-9);
            Assert.True(i.JitterLevel >= 0.8 * 0.7 - 1e-9);
            Assert.True(i.LineOpacity <= StoryTexture.LineAlpha(0.85) + 1e-9);
            Assert.True(i.LineOpacity > b.LineOpacity, "Intenso marca mais que Equilibrado");
            Assert.True(StoryTexture.LineOpacityCap < 1);
        }
    }

    [Fact]
    public void RandomLineDirectionCoversAllThreeAndFixedOnesStayFixed()
    {
        var o = TextureOptions;
        o.TexturePreset = StoryTexturePreset.Subtle;
        var seen = new HashSet<StoryLineDirection>();
        for (ulong seed = 1; seed <= 80; seed++) seen.Add(StoryParams.Sample(o, seed).LineDirection);
        Assert.True(seen.SetEquals(new[] { StoryLineDirection.Backslash, StoryLineDirection.Slash, StoryLineDirection.Cross }));
        o.TexturePreset = StoryTexturePreset.Custom;
        o.CustomTexture = StoryTexture.Balanced;
        foreach (var direction in new[] { StoryLineDirection.Backslash, StoryLineDirection.Slash, StoryLineDirection.Cross })
        {
            o.LineDirection = direction;
            for (ulong seed = 1; seed <= 20; seed++) Assert.Equal(direction, StoryParams.Sample(o, seed).LineDirection);
        }
    }

    [Fact]
    public void AberrationStaysBetweenOneAndSixPixels()
    {
        var o = TextureOptions;
        o.TexturePreset = StoryTexturePreset.Custom;
        o.CustomTexture = new StoryTexture { Aberration = true, AberrationPercent = 100 };
        var biggest = 0;
        for (ulong seed = 1; seed <= 200; seed++)
        {
            var p = StoryParams.Sample(o, seed);
            var m = Math.Max(Math.Abs(p.AberrationDX), Math.Abs(p.AberrationDY));
            Assert.True(m >= 1, "sempre desloca pelo menos 1px");
            Assert.True(m <= StoryTexture.AberrationMaxPixels);
            biggest = Math.Max(biggest, m);
        }
        Assert.True(biggest >= 5, "no nível máximo chega perto dos 6px");
        o.CustomTexture.AberrationPercent = 1;
        for (ulong seed = 1; seed <= 50; seed++)
        {
            var p = StoryParams.Sample(o, seed);
            Assert.True(Math.Max(Math.Abs(p.AberrationDX), Math.Abs(p.AberrationDY)) <= 1);
        }
    }

    [Fact]
    public void EachEffectTurnsOffByItself()
    {
        var o = TextureOptions;
        o.TexturePreset = StoryTexturePreset.Custom;
        o.CustomTexture = StoryTexture.Intense;
        o.LinesEnabled = false;
        var p = StoryParams.Sample(o, 5);
        Assert.Equal(0, p.LineOpacity);
        Assert.True(p.JitterLevel > 0);
        o.CustomTexture.Jitter = false;
        p = StoryParams.Sample(o, 5);
        Assert.Equal(0, p.JitterLevel);
        Assert.True(p.AberrationDX != 0 || p.AberrationDY != 0);
        o.CustomTexture.Aberration = false;
        o.CustomTexture.Bloom = false;
        p = StoryParams.Sample(o, 5);
        Assert.False(p.HasTexture);
        Assert.False(o.Texture.IsActive);
        o.CustomTexture = StoryTexture.Intense;
        o.LinesEnabled = true;
        o.CustomToneLines.OpacityPercent = 0;
        Assert.Equal(0, StoryParams.Sample(o, 5).LineOpacity);
    }

    [Fact]
    public void CustomTextureIsClampedAndThicknessStaysBelowSpacing()
    {
        var t = new StoryTexture { LineSpacing = 2, LineThickness = 1, LineOpacityPercent = 250, JitterPercent = -10, AberrationPercent = double.NaN };
        var c = t.Clamped();
        Assert.Equal(4, c.LineSpacing);
        Assert.Equal(2, c.LineThickness);
        Assert.Equal(100, c.LineOpacityPercent);
        Assert.Equal(0, c.JitterPercent);
        Assert.Equal(0, c.AberrationPercent);
        t.LineSpacing = 18;
        t.LineThickness = 8;
        Assert.Equal(8, t.Clamped().LineThickness);
        t.LineSpacing = 99;
        Assert.Equal(18, t.Clamped().LineSpacing);
        t.LineSpacing = 8;
        Assert.Equal(6, t.Clamped().LineThickness);
        Assert.Equal(10, new StoryTexture().LineSpacing);
        Assert.Equal(2, new StoryTexture().LineThickness);
        Assert.Equal(StoryLineStyle.Tone, new StoryTexture().LineStyle);
        t.LineAngle = 5;
        t.LineIrregularity = 300;
        Assert.Equal(30, t.Clamped().LineAngle);
        Assert.Equal(100, t.Clamped().LineIrregularity);
        t.LineAngle = 120;
        Assert.Equal(75, t.Clamped().LineAngle);
        var o = TextureOptions;
        o.TexturePreset = StoryTexturePreset.Custom;
        o.CustomToneLines = StoryLineSettings.FromTexture(t);
        var p = StoryParams.Sample(o, 3);
        Assert.True(p.LineThickness <= p.LineSpacing - 2);
        Assert.True(p.LineThickness >= 2);
    }

    [Fact]
    public void ChoosingCustomStartsFromThePresetInUse()
    {
        var o = new StoryOptions { TexturePreset = StoryTexturePreset.Intense };
        o.SelectTexturePreset(StoryTexturePreset.Custom);
        Assert.Equal(StoryTexturePreset.Custom, o.TexturePreset);
        Assert.Equal(StoryTexture.Intense, o.CustomTexture);
        o.CustomTexture.JitterPercent = 10;
        o.SelectTexturePreset(StoryTexturePreset.Subtle);
        o.SelectTexturePreset(StoryTexturePreset.Custom);
        Assert.Equal(StoryTexture.Subtle, o.CustomTexture);

        var fresh = new StoryOptions();
        fresh.SelectTexturePreset(StoryTexturePreset.Custom);
        Assert.Equal(StoryTexture.Balanced, fresh.CustomTexture);
        Assert.Equal(StoryLineSettings.Preset(StoryTexturePreset.Balanced, StoryLineStyle.Tone), fresh.CustomToneLines);
        Assert.Equal(StoryLineSettings.Preset(StoryTexturePreset.Balanced, StoryLineStyle.Ink), fresh.CustomInkLines);
        fresh.CustomTexture.BloomPercent = 55;
        fresh.SelectTexturePreset(StoryTexturePreset.Custom);
        Assert.Equal(55, fresh.CustomTexture.BloomPercent);
    }

    // MARK: - Linhas escolhidas antes do nível (beta.26)

    [Fact]
    public void LinesAreChosenBeforeTheLevelAndEachStyleHasItsOwnLevels()
    {
        Assert.False(new StoryOptions().LinesEnabled);
        var o = TextureOptions;
        foreach (var level in new[] { StoryTexturePreset.Subtle, StoryTexturePreset.Balanced, StoryTexturePreset.Intense })
        {
            o.TexturePreset = level;
            foreach (var style in StoryLabels.Styles)
            {
                o.LineStyle = style;
                o.LineDirection = StoryLineDirection.Slash;
                var t = o.Texture;
                var expected = StoryLineSettings.Preset(level, style);
                Assert.True(t.Lines);
                Assert.Equal(style, t.LineStyle);
                Assert.Equal(StoryLineDirection.Slash, t.LineDirection);
                Assert.Equal(expected.OpacityPercent, t.LineOpacityPercent);
                Assert.Equal(expected.Spacing, t.LineSpacing);
                Assert.Equal(expected.Thickness, t.LineThickness);
                Assert.Equal(StoryOptions.BaseTexture(level).JitterPercent, t.JitterPercent);
                var p = StoryParams.Sample(o, 11);
                Assert.Equal(style, p.LineStyle);
                Assert.Equal(StoryLineDirection.Slash, p.LineDirection);
            }
        }
        foreach (var style in StoryLabels.Styles)
        {
            var s = StoryLineSettings.Preset(StoryTexturePreset.Subtle, style);
            var b = StoryLineSettings.Preset(StoryTexturePreset.Balanced, style);
            var i = StoryLineSettings.Preset(StoryTexturePreset.Intense, style);
            Assert.True(s.OpacityPercent < b.OpacityPercent);
            Assert.True(b.OpacityPercent < i.OpacityPercent);
        }
        Assert.NotEqual(StoryLineSettings.Preset(StoryTexturePreset.Balanced, StoryLineStyle.Tone), StoryLineSettings.Preset(StoryTexturePreset.Balanced, StoryLineStyle.Ink));

        o.LinesEnabled = false;
        o.TexturePreset = StoryTexturePreset.Intense;
        Assert.False(o.Texture.Lines);
        Assert.Equal(0, StoryParams.Sample(o, 3).LineOpacity);
        Assert.True(StoryParams.Sample(o, 3).JitterLevel > 0);

        var fresh = new StoryOptions();
        fresh.SetLinesEnabled(true);
        Assert.Equal(StoryTexturePreset.Balanced, fresh.TexturePreset);
        fresh.TexturePreset = StoryTexturePreset.Subtle;
        fresh.SetLinesEnabled(false);
        fresh.SetLinesEnabled(true);
        Assert.Equal(StoryTexturePreset.Subtle, fresh.TexturePreset);
    }

    [Fact]
    public void CustomLinesAreKeptSeparatelyForEachStyle()
    {
        var o = TextureOptions;
        o.TexturePreset = StoryTexturePreset.Subtle;
        o.SelectTexturePreset(StoryTexturePreset.Custom);
        Assert.Equal(StoryLineSettings.Preset(StoryTexturePreset.Subtle, StoryLineStyle.Tone), o.CustomToneLines);
        Assert.Equal(StoryLineSettings.Preset(StoryTexturePreset.Subtle, StoryLineStyle.Ink), o.CustomInkLines);
        o.LineStyle = StoryLineStyle.Tone;
        o.CustomLines.OpacityPercent = 77;
        o.CustomLines.Angle = 65;
        o.LineStyle = StoryLineStyle.Ink;
        Assert.Equal(StoryLineSettings.Preset(StoryTexturePreset.Subtle, StoryLineStyle.Ink), o.CustomLines);
        o.CustomLines.Blend = StoryLineBlend.Overlay;
        Assert.Equal(StoryLineBlend.Overlay, o.Texture.LineBlend);
        o.LineStyle = StoryLineStyle.Tone;
        Assert.Equal(77, o.Texture.LineOpacityPercent);
        Assert.Equal(65, o.Texture.LineAngle);
        Assert.Equal(StoryLineBlend.Overlay, o.CustomInkLines.Blend);
    }

    [Fact]
    public void OptionsSavedBeforeBeta26MoveTheirLinesOut()
    {
        var c = Decode("""{"texturePreset":"custom","customTexture":{"lines":true,"lineStyle":"tone","lineDirection":"slash","lineOpacityPercent":42,"lineSpacing":11,"lineThickness":3,"lineAngle":62,"lineIrregularity":20}}""");
        Assert.True(c.LinesEnabled);
        Assert.Equal(StoryLineStyle.Tone, c.LineStyle);
        Assert.Equal(StoryLineDirection.Slash, c.LineDirection);
        Assert.Equal(42, c.CustomToneLines.OpacityPercent);
        Assert.Equal(62, c.CustomToneLines.Angle);
        Assert.Equal(11, c.Texture.LineSpacing);
        var i = Decode("""{"texturePreset":"intense"}""");
        Assert.True(i.LinesEnabled);
        Assert.Equal(StoryLineStyle.Ink, i.LineStyle);
        Assert.Equal(StoryLineDirection.Cross, i.LineDirection);
        Assert.False(Decode("""{"texturePreset":"custom","customTexture":{"lines":false}}""").LinesEnabled);
        var n = new StoryOptions { LinesEnabled = true, LineStyle = StoryLineStyle.Ink, LineDirection = StoryLineDirection.Backslash };
        n.CustomInkLines.Blend = StoryLineBlend.Overlay;
        Assert.Equal(n, RoundTrip(n));
    }

    [Fact]
    public void OldSavedOptionsStillDecodeWithTexturesOff()
    {
        var o = Decode("""{"fit":"cover","intensity":"normal","format":"png","versionsPerImage":3}""");
        Assert.Equal(StoryTexturePreset.Off, o.TexturePreset);
        Assert.Equal(StoryIntensity.Normal, o.Intensity);
        Assert.Equal(3, o.Versions);
        Assert.Equal(StoryTexture.Balanced, o.CustomTexture);

        var n = new StoryOptions { TexturePreset = StoryTexturePreset.Custom, CustomTexture = StoryTexture.Intense };
        n.CustomTexture.LineDirection = StoryLineDirection.Slash;
        n.CustomTexture.LineBlend = StoryLineBlend.Overlay;
        Assert.Equal(n, RoundTrip(n));

        var p = Decode("""{"texturePreset":"balanced","customTexture":{"lines":true,"lineSpacing":9}}""");
        Assert.Equal(StoryTexturePreset.Balanced, p.TexturePreset);
        Assert.Equal(9, p.CustomTexture.LineSpacing);
        Assert.Equal(StoryLineStyle.Ink, p.CustomTexture.LineStyle);
        Assert.True(p.LinesEnabled);
        Assert.Equal(StoryLineStyle.Tone, p.LineStyle);
        Assert.False(o.LinesEnabled);
        n.CustomTexture.LineStyle = StoryLineStyle.Tone;
        n.CustomTexture.LineAngle = 62;
        n.CustomTexture.LineIrregularity = 35;
        Assert.Equal(n, RoundTrip(n));
        var q = Decode("""{"customTexture":{"lines":true,"lineBlend":"softLight"}}""");
        Assert.Equal(StoryLineBlend.HardLight, q.CustomTexture.LineBlend);
        Assert.True(q.CustomTexture.Lines);
        Assert.Equal(new StoryTexture().JitterPercent, p.CustomTexture.JitterPercent);
    }

    [Fact]
    public void SummaryMentionsTheActiveTextures()
    {
        var o = TextureOptions;
        o.TexturePreset = StoryTexturePreset.Intense;
        var s = StoryParams.Sample(o, 8).Summary;
        Assert.Contains("linhas", s);
        Assert.Contains("serrilhado", s);
        Assert.Contains("aberração", s);
        Assert.Contains("ofuscação", s);
        Assert.DoesNotContain("serrilhado", StoryParams.Sample(TextureOptions, 8).Summary);
    }

    // MARK: - Linhas (CPU)

    [Fact]
    public void LinesMatchTheirGeometryInEveryDirection()
    {
        const int W = 96, H = 80;
        foreach (var direction in new[] { StoryLineDirection.Backslash, StoryLineDirection.Slash, StoryLineDirection.Cross })
        {
            var px = Buffer(W, H, 200);
            var p = LinesParams(direction);
            StoryTextureEffects.ApplyLines(px, W, H, p);
            var cross = direction == StoryLineDirection.Cross;
            var luts = StoryTextureEffects.LineLUTs(p.LineBlend, p.LineOpacity, cross);
            var h = StoryTexture.LineHighlightWidth(8, 4);
            Assert.Equal(1, h);
            int dark = 0, light = 0;
            for (var y = 0; y < H; y++)
            {
                for (var x = 0; x < W; x++)
                {
                    var expected = 200;
                    if (direction != StoryLineDirection.Slash)
                    {
                        var st = StoryTextureEffects.BandState(x, y, 8, 4, h, false, 3);
                        if (st == StoryTextureEffects.BandDark) expected = luts.Dark[expected];
                        else if (st == StoryTextureEffects.BandLight) expected = luts.Light[expected];
                    }
                    if (direction != StoryLineDirection.Backslash)
                    {
                        var st = StoryTextureEffects.BandState(x, y, 8, 4, h, true, cross ? 5 : 3);
                        if (st == StoryTextureEffects.BandDark) expected = luts.Dark[expected];
                        else if (st == StoryTextureEffects.BandLight) expected = luts.Light[expected];
                    }
                    var got = Gray(px, x, y, W);
                    Assert.True(expected == got, $"({x},{y}) {direction}: esperado {expected}, veio {got}");
                    if (got < 200) dark++; else if (got > 200) light++;
                }
            }
            if (!cross)
            {
                Near(0.5, dark / (double)(W * H), 0.01, "faixa escura = 4 de cada 8 px");
                Near(0.125, light / (double)(W * H), 0.01, "realce = 1 de cada 8 px");
            }
            Assert.True(light > 0);
            Assert.True(dark > 0);
        }
    }

    private static Dictionary<int, int> Histogram(byte[] px, int n)
    {
        var h = new Dictionary<int, int>();
        for (var i = 0; i < n; i++) { var v = px[i * 4 + 1]; h[v] = h.GetValueOrDefault(v) + 1; }
        return h;
    }

    [Fact]
    public void BackslashAndSlashHaveExactlyTheSameStrength()
    {
        const int W = 96, H = 80;
        var back = Buffer(W, H, 150);
        var fwd = Buffer(W, H, 150);
        StoryTextureEffects.ApplyLines(back, W, H, LinesParams(StoryLineDirection.Backslash));
        StoryTextureEffects.ApplyLines(fwd, W, H, LinesParams(StoryLineDirection.Slash));
        Assert.Equal(Histogram(back, W * H).OrderBy(k => k.Key), Histogram(fwd, W * H).OrderBy(k => k.Key));
        var mirrored = new byte[back.Length];
        for (var y = 0; y < H; y++)
            for (var x = 0; x < W; x++)
                for (var c = 0; c < 4; c++) mirrored[(y * W + (W - 1 - x)) * 4 + c] = back[(y * W + x) * 4 + c];
        Assert.Equal(Histogram(mirrored, W * H).OrderBy(k => k.Key), Histogram(fwd, W * H).OrderBy(k => k.Key));
    }

    [Fact]
    public void LinesAreClearlyVisibleOnDarkMidAndLightColours()
    {
        var luts = StoryTextureEffects.LineLUTs(StoryLineBlend.HardLight, StoryTexture.LineAlpha(0.5));
        for (var v = 0; v < 256; v++)
        {
            var delta = Math.Max(Math.Abs(luts.Dark[v] - v), Math.Abs(luts.Light[v] - v));
            Assert.True(delta >= 30, $"em {v} pelo menos uma das faixas se destaca");
        }
        Assert.Equal(0, luts.Dark[0]);
        Assert.True(luts.Light[0] > 60);
        Assert.Equal(255, luts.Light[255]);
        Assert.True(luts.Dark[255] < 150);
    }

    private static double Mean(byte[] px, int n)
    {
        long sum = 0;
        for (var i = 0; i < n; i++) sum += px[i * 4 + 1];
        return sum / (double)n;
    }

    [Fact]
    public void CrossKeepsTheOverallBrightnessCloseToASingleDirection()
    {
        const int W = 96, H = 80;
        var p = LinesParams(StoryLineDirection.Backslash);
        p.LineOpacity = StoryTexture.LineAlpha(0.5);
        var single = Buffer(W, H, 128);
        var cross = Buffer(W, H, 128);
        StoryTextureEffects.ApplyLines(single, W, H, p);
        p.LineDirection = StoryLineDirection.Cross;
        StoryTextureEffects.ApplyLines(cross, W, H, p);
        double ms = Mean(single, W * H), mc = Mean(cross, W * H);
        _out.WriteLine($"brilho médio de 128: uma direção {ms} · X {mc}");
        Assert.True(ms > 85 && ms < 128);
        Assert.True(mc > 85 && mc < 128);
        Assert.True(Math.Abs(mc - ms) < 12);
        Assert.NotEqual(single, cross);
    }

    [Fact]
    public void LineCurveMatchesTheRequestedFeel()
    {
        Assert.Equal(0, StoryTexture.LineAlpha(0));
        Near(StoryTexture.LineOpacityCap, StoryTexture.LineAlpha(1), 1e-9);
        var last = -1.0;
        for (var i = 0; i <= 100; i++)
        {
            var a = StoryTexture.LineAlpha(i / 100.0);
            Assert.True(a >= last);
            Assert.True(a <= StoryTexture.LineOpacityCap + 1e-9);
            last = a;
        }
        Assert.True(StoryTexture.LineAlpha(0.10) > 0.12);
        Assert.True(StoryTexture.LineAlpha(0.25) < 0.40);
        Near(0.52, StoryTexture.LineAlpha(0.5), 0.05);
        Assert.True(StoryTexture.LineAlpha(0.8) > 0.68);
        Assert.True(StoryTexture.LineAlpha(1) < 0.9);
    }

    [Fact]
    public void LinePhaseChangesFromImageToImage()
    {
        var o = TextureOptions;
        o.TexturePreset = StoryTexturePreset.Balanced;
        var phases = new HashSet<int>();
        for (ulong seed = 1; seed <= 60; seed++) phases.Add(StoryParams.Sample(o, seed).LinePhase);
        Assert.True(phases.Count >= 5);
        Assert.True(phases.All(x => x is >= 0 and < 9));
        o.TexturePreset = StoryTexturePreset.Intense;
        var phases2 = new HashSet<int>();
        for (ulong seed = 1; seed <= 60; seed++)
        {
            var p = StoryParams.Sample(o, seed);
            Assert.True(p.LinePhase2 < p.LineSpacing);
            phases2.Add(p.LinePhase2);
        }
        Assert.True(phases2.Count >= 5);
    }

    // MARK: - Linhas no tom (beta.25)

    private static StoryParams ToneParams(StoryLineDirection direction, double amplitude = 0.3, double angle = 55, double irregularity = 0) => new()
    {
        LineStyle = StoryLineStyle.Tone, LineOpacity = amplitude, LineSpacing = 10, LineThickness = 3, LineDirection = direction,
        LineAngle = angle, LineIrregularity = irregularity, LinePhase = 2, LinePhase2 = 7, LineSeed = 42,
    };

    private static byte[] Coloured(int w, int h, byte r, byte g, byte b)
    {
        var px = Enumerable.Repeat((byte)255, w * h * 4).ToArray();
        for (var i = 0; i < w * h; i++) { px[i * 4] = r; px[i * 4 + 1] = g; px[i * 4 + 2] = b; }
        return px;
    }

    private static (double H, double S, double V) Hsv(byte r, byte g, byte b)
    {
        double R = r / 255.0, G = g / 255.0, B = b / 255.0;
        double mx = Math.Max(R, Math.Max(G, B)), mn = Math.Min(R, Math.Min(G, B)), d = mx - mn;
        var h = 0.0;
        if (d > 0)
        {
            if (mx == R) h = ((G - B) / d) % 6;
            else if (mx == G) h = (B - R) / d + 2;
            else h = (R - G) / d + 4;
            h *= 60;
            if (h < 0) h += 360;
        }
        return (h, mx > 0 ? d / mx : 0, mx);
    }

    [Fact]
    public void ToneLinesKeepTheColourAndOnlyChangeBrightness()
    {
        const int W = 120, H = 90;
        foreach (var (r, g, b) in new (byte, byte, byte)[] { (30, 110, 100), (200, 140, 40), (90, 20, 150), (40, 40, 40) })
        {
            foreach (var direction in new[] { StoryLineDirection.Backslash, StoryLineDirection.Slash, StoryLineDirection.Cross })
            {
                var px = Coloured(W, H, r, g, b);
                StoryTextureEffects.ApplyLines(px, W, H, ToneParams(direction, 0.35, irregularity: 0.6));
                var orig = Hsv(r, g, b);
                int darker = 0, lighter = 0;
                var minV = 1.0;
                for (var i = 0; i < W * H; i++)
                {
                    var o = i * 4;
                    var c = Hsv(px[o], px[o + 1], px[o + 2]);
                    if (c.V < orig.V - 0.01) darker++;
                    if (c.V > orig.V + 0.01) lighter++;
                    minV = Math.Min(minV, c.V);
                    if (orig.S > 0.2 && c.V > 0.08)
                    {
                        var dh = Math.Abs(c.H - orig.H);
                        Assert.True(Math.Min(dh, 360 - dh) < 4, $"matiz em ({r},{g},{b}) {direction}");
                        Near(orig.S, c.S, 0.05, $"saturação em ({r},{g},{b}) {direction}");
                    }
                }
                Assert.True(darker > W * H / 20, $"tem linha escura ({r},{g},{b}) {direction}");
                Assert.True(lighter > 0, $"tem brilho claro colado ({r},{g},{b}) {direction}");
                Assert.True(minV > orig.V * (direction == StoryLineDirection.Cross ? 1 - 0.42 : 1 - 0.36), "nunca vira preto");
            }
        }
    }

    [Fact]
    public void ToneLinesLeaveVeryBrightAreasAlmostUntouched()
    {
        const int W = 120, H = 90;
        var white = Coloured(W, H, 255, 255, 255);
        StoryTextureEffects.ApplyLines(white, W, H, ToneParams(StoryLineDirection.Cross, 0.35));
        Assert.True(white.Select((v, i) => i % 4 == 3 || v >= 253).All(x => x), "texto branco fica limpo");
        var mid = Coloured(W, H, 120, 120, 120);
        StoryTextureEffects.ApplyLines(mid, W, H, ToneParams(StoryLineDirection.Cross, 0.35));
        Assert.True(mid.Where((_, i) => i % 4 == 1).Min() < 100, "no meio-tom a linha aparece");
    }

    [Fact]
    public void ToneLinesFollowTheChosenAngleAndDirection()
    {
        const int W = 160, H = 160;
        int[] Pattern(StoryLineDirection direction, double angle)
        {
            var px = Coloured(W, H, 140, 140, 140);
            StoryTextureEffects.ApplyLines(px, W, H, ToneParams(direction, 0.35, angle));
            return Enumerable.Range(0, W * H).Select(i => (int)px[i * 4 + 1]).ToArray();
        }
        double MeanDiff(int[] v, double dx, double dy)
        {
            long sum = 0, n = 0;
            for (var y = 20; y < H - 20; y++)
                for (var x = 20; x < W - 20; x++)
                {
                    var x2 = x + (int)Math.Round(dx, MidpointRounding.AwayFromZero);
                    var y2 = y + (int)Math.Round(dy, MidpointRounding.AwayFromZero);
                    sum += Math.Abs(v[y * W + x] - v[y2 * W + x2]); n++;
                }
            return sum / (double)n;
        }
        foreach (var angle in new[] { 45.0, 55.0, 70.0 })
        {
            double t = angle * Math.PI / 180, d = 12;
            var back = Pattern(StoryLineDirection.Backslash, angle);
            var fwd = Pattern(StoryLineDirection.Slash, angle);
            Assert.True(MeanDiff(back, d * Math.Cos(t), d * Math.Sin(t)) * 2.5 < MeanDiff(back, d * Math.Cos(t), -d * Math.Sin(t)), $"\\ a {angle}°");
            Assert.True(MeanDiff(fwd, d * Math.Cos(t), -d * Math.Sin(t)) * 2.5 < MeanDiff(fwd, d * Math.Cos(t), d * Math.Sin(t)), $"/ a {angle}°");
            Near(back.Average(), fwd.Average(), 3, $"\\ e / com a mesma força a {angle}°");
        }
    }

    [Fact]
    public void ToneIrregularityBreaksTheLinesAndSeedChangesTheDrawing()
    {
        const int W = 200, H = 200;
        byte[] Render(double irregularity, ulong seed = 42)
        {
            var px = Coloured(W, H, 120, 120, 120);
            var p = ToneParams(StoryLineDirection.Backslash, 0.35, irregularity: irregularity);
            p.LineSeed = seed;
            StoryTextureEffects.ApplyLines(px, W, H, p);
            return px;
        }
        int DarkCount(byte[] px) => Enumerable.Range(0, W * H).Count(i => px[i * 4 + 1] < 100);
        var regular = Render(0);
        var irregular = Render(1);
        Assert.True(DarkCount(irregular) < DarkCount(regular) * 0.85);
        Assert.True(DarkCount(irregular) > DarkCount(regular) / 5);
        Assert.Equal(Render(1), Render(1));
        Assert.NotEqual(Render(1, 1), Render(1, 2));
        Assert.Equal(Render(0, 1), Render(0, 2));
    }

    [Fact]
    public void ToneCrossStaysBalanced()
    {
        const int W = 120, H = 120;
        double M(StoryLineDirection d)
        {
            var px = Coloured(W, H, 128, 128, 128);
            StoryTextureEffects.ApplyLines(px, W, H, ToneParams(d, 0.35));
            return Mean(px, W * H);
        }
        double single = M(StoryLineDirection.Backslash), cross = M(StoryLineDirection.Cross);
        _out.WriteLine($"tom: brilho médio de 128 → uma direção {single} · X {cross}");
        Assert.True(single < 128 && single > 100);
        Assert.True(Math.Abs(cross - single) < 8);
    }

    [Fact]
    public void ToneSamplingKeepsTheOlderDrawsAndVariesTheAngle()
    {
        var o = TextureOptions;
        o.TexturePreset = StoryTexturePreset.Custom;
        o.CustomTexture = StoryTexture.Balanced;
        var inkOnly = o.Clone();
        inkOnly.LineStyle = StoryLineStyle.Ink;
        inkOnly.CustomInkLines.Spacing = o.CustomToneLines.Spacing;
        o.LineStyle = StoryLineStyle.Tone;
        var angles = new HashSet<int>();
        for (ulong seed = 1; seed <= 40; seed++)
        {
            var tone = StoryParams.Sample(o, seed);
            var ink = StoryParams.Sample(inkOnly, seed);
            Assert.Equal(tone.Code, ink.Code);
            Assert.Equal(tone.LineDirection, ink.LineDirection);
            Assert.Equal(tone.LinePhase, ink.LinePhase);
            Assert.Equal(tone.JitterSeed, ink.JitterSeed);
            Assert.Equal(45, ink.LineAngle);
            Assert.True(tone.LineAngle >= 52 - 1e-9 && tone.LineAngle <= 58 + 1e-9);
            Assert.NotEqual(0UL, tone.LineSeed);
            angles.Add((int)(tone.LineAngle * 10));
            Assert.Contains("linhas no tom", tone.Summary);
        }
        Assert.True(angles.Count > 10);
        Assert.Equal(0, StoryTexture.ToneAmplitude(0));
        Near(StoryTexture.ToneAmplitudeCap, StoryTexture.ToneAmplitude(1), 1e-9);
        Near(0.20, StoryTexture.ToneAmplitude(0.5), 0.01);
    }

    [Fact]
    public void BackslashRunsTopLeftToBottomRightAndSlashTheOtherWay()
    {
        const int W = 96, H = 80;
        var back = Buffer(W, H, 200);
        var fwd = Buffer(W, H, 200);
        StoryTextureEffects.ApplyLines(back, W, H, LinesParams(StoryLineDirection.Backslash));
        StoryTextureEffects.ApplyLines(fwd, W, H, LinesParams(StoryLineDirection.Slash));
        for (var y = 1; y < H - 1; y++)
            for (var x = 1; x < W - 1; x++)
            {
                Assert.Equal(Gray(back, x, y, W), Gray(back, x + 1, Math.Min(y + 1, H - 1), W));
                Assert.Equal(Gray(fwd, x, y, W), Gray(fwd, Math.Min(x + 1, W - 1), y - 1, W));
            }
        Assert.NotEqual(back, fwd);
    }

    [Fact]
    public void LineBlendModesAndOpacity()
    {
        var identity = Enumerable.Range(0, 256).Select(v => (byte)v).ToArray();
        var off = StoryTextureEffects.LineLUTs(StoryLineBlend.HardLight, 0);
        Assert.Equal(identity, off.Dark);
        Assert.Equal(identity, off.Light);
        var full = StoryTextureEffects.LineLUTs(StoryLineBlend.HardLight, 1);
        Assert.Equal(0, full.Dark[200]);
        Near(193, full.Light[100], 1);
        Near(100, StoryTextureEffects.LineLUTs(StoryLineBlend.HardLight, 0.5).Dark[200], 1);
        var overlay = StoryTextureEffects.LineLUTs(StoryLineBlend.Overlay, 1);
        Near(145, overlay.Dark[200], 1);
        Assert.Equal(0, overlay.Dark[100]);
        Near(160, overlay.Light[100], 1);
        Near(233, overlay.Light[200], 1);
        var cross = StoryTextureEffects.LineLUTs(StoryLineBlend.HardLight, 1, true);
        Near(200 * (1 - StoryTexture.LineCrossBalance), cross.Dark[200], 1);
        foreach (var blend in StoryLabels.Blends)
        {
            var l = StoryTextureEffects.LineLUTs(blend, 0.6);
            for (var v = 1; v < 256; v++)
            {
                Assert.True(l.Dark[v] >= l.Dark[v - 1]);
                Assert.True(l.Light[v] >= l.Light[v - 1]);
            }
            for (var v = 0; v < 256; v++)
            {
                Assert.True(l.Dark[v] <= v);
                Assert.True(l.Light[v] >= v);
            }
        }
    }

    [Fact]
    public void LinesOnlyChangeLinePixelsAndLeaveTheRestIntact()
    {
        const int W = 64, H = 64;
        var px = Buffer(W, H, 90);
        for (var i = 0; i < W * H; i++) px[i * 4 + 3] = 7;
        var p = LinesParams(StoryLineDirection.Cross, StoryLineBlend.Overlay);
        p.LineOpacity = 0;
        var same = (byte[])px.Clone();
        StoryTextureEffects.ApplyLines(px, W, H, p);
        Assert.Equal(same, px);
        p.LineOpacity = 0.5;
        StoryTextureEffects.ApplyLines(px, W, H, p);
        for (var i = 0; i < W * H; i++) Assert.Equal(7, px[i * 4 + 3]);
    }

    // MARK: - Serrilhado (CPU)

    /// <summary>Ruído determinístico de ±amp em volta de <paramref name="baseV"/> (o mesmo xorshift do Mac).</summary>
    private static byte[] Noisy(int w, int h, int baseV, int amp)
    {
        var px = Buffer(w, h);
        ulong state = 88_172_645_463_325_252;
        for (var i = 0; i < w * h; i++)
        {
            state ^= state << 13; state ^= state >> 7; state ^= state << 17;
            var v = (byte)(baseV + (int)(state % (ulong)(2 * amp + 1)) - amp);
            px[i * 4] = v; px[i * 4 + 1] = v; px[i * 4 + 2] = v;
        }
        return px;
    }

    [Fact]
    public void EdgeJitterLeavesFlatAndNoisyAreasAlone()
    {
        const int W = 200, H = 120;
        var flat = Buffer(W, H, 120);
        var flatBefore = (byte[])flat.Clone();
        StoryTextureEffects.ApplyEdgeJitter(flat, W, H, 1, 11);
        Assert.Equal(flatBefore, flat);
        var grain = Noisy(W, H, 120, 6);
        var grainBefore = (byte[])grain.Clone();
        StoryTextureEffects.ApplyEdgeJitter(grain, W, H, 1, 11);
        Assert.Equal(grainBefore, grain);
        var soft = Buffer(W, H);
        for (var y = 0; y < H; y++) for (var x = 0; x < W; x++) SetPixel(soft, x, y, W, (byte)(40 + x));
        var softBefore = (byte[])soft.Clone();
        StoryTextureEffects.ApplyEdgeJitter(soft, W, H, 1, 11);
        Assert.Equal(softBefore, soft);
    }

    [Fact]
    public void EdgeJitterOnlyTouchesTheNeighbourhoodOfStrongEdgesAndBreaksThem()
    {
        const int W = 200, H = 120;
        var px = Buffer(W, H);
        for (var y = 0; y < H; y++) for (var x = 0; x < W; x++) SetPixel(px, x, y, W, (byte)(x < 100 ? 20 : 235));
        var before = (byte[])px.Clone();
        StoryTextureEffects.ApplyEdgeJitter(px, W, H, 1, 7);
        var changed = new HashSet<int>();
        for (var y = 0; y < H; y++) for (var x = 0; x < W; x++) if (Gray(px, x, y, W) != Gray(before, x, y, W)) changed.Add(x);
        Assert.NotEmpty(changed);
        Assert.True(changed.Min() >= 95);
        Assert.True(changed.Max() <= 104);
        var positions = new HashSet<int>();
        for (var y = 0; y < H; y++)
            for (var x = 0; x < W; x++)
                if (Gray(px, x, y, W) > 127) { positions.Add(x); break; }
        Assert.True(positions.Count >= 3, "a borda deixou de ser reta");
        Assert.Equal(20, Gray(px, 10, 50, W));
        Assert.Equal(235, Gray(px, 190, 50, W));
    }

    [Fact]
    public void EdgeJitterAlsoBreaksHorizontalEdges()
    {
        const int W = 200, H = 120;
        var px = Buffer(W, H);
        for (var y = 0; y < H; y++) for (var x = 0; x < W; x++) SetPixel(px, x, y, W, (byte)(y < 60 ? 15 : 240));
        StoryTextureEffects.ApplyEdgeJitter(px, W, H, 1, 21);
        var positions = new HashSet<int>();
        for (var x = 0; x < W; x++)
            for (var y = 0; y < H; y++)
                if (Gray(px, x, y, W) > 127) { positions.Add(y); break; }
        Assert.True(positions.Count >= 3);
    }

    [Fact]
    public void EdgeJitterLevelControlsStrengthAndIsDeterministic()
    {
        const int W = 200, H = 120;
        var baseImg = Buffer(W, H);
        for (var y = 0; y < H; y++) for (var x = 0; x < W; x++) SetPixel(baseImg, x, y, W, (byte)((x / 20 + y / 20) % 2 == 0 ? 30 : 225));
        (byte[] Px, int Count) Changed(double level, ulong seed)
        {
            var p = (byte[])baseImg.Clone();
            StoryTextureEffects.ApplyEdgeJitter(p, W, H, level, seed);
            var n = 0;
            for (var i = 0; i < W * H; i++) if (p[i * 4 + 1] != baseImg[i * 4 + 1]) n++;
            return (p, n);
        }
        Assert.Equal(0, Changed(0, 1).Count);
        var low = Changed(0.15, 4);
        var mid = Changed(0.5, 4);
        var high = Changed(1, 4);
        Assert.True(high.Count > low.Count, $"{low.Count} → {mid.Count} → {high.Count}");
        Assert.Equal(mid.Px, Changed(0.5, 4).Px);
        Assert.NotEqual(mid.Px, Changed(0.5, 5).Px);
    }

    [Fact]
    public void EdgeMaskFindsTextLikeBarsOnly()
    {
        const int W = 200, H = 120;
        var px = Buffer(W, H, 60);
        for (var y = 40; y < 60; y++) for (var x = 30; x < 170; x++) SetPixel(px, x, y, W, 250);
        var mask = StoryTextureEffects.EdgeMask(px, W, H);
        Assert.Equal(0, mask[10 * W + 10]);
        Assert.Equal(0, mask[50 * W + 100]);
        Assert.True(mask[40 * W + 100] > StoryTextureEffects.EdgeHigh);
        Assert.True(mask[38 * W + 100] > StoryTextureEffects.EdgeLow);
    }

    // MARK: - Motor (Skia + CPU)

    private static SKBitmap MakeImage(int width, int height, Action<SKCanvas> draw)
    {
        var bmp = new SKBitmap(new SKImageInfo(width, height, SKColorType.Rgba8888, SKAlphaType.Premul));
        using var c = new SKCanvas(bmp);
        c.Clear(SKColors.Black);
        draw(c);
        return bmp;
    }

    private static SKBitmap HalfBlackHalfWhite() => MakeImage(1080, 1920, c =>
    {
        using var p = new SKPaint { Color = SKColors.White };
        c.DrawRect(540, 0, 540, 1920, p);
    });

    private static byte[] Composed(SKBitmap img, StoryParams p)
    {
        var o = TextureOptions;
        return StoryOptimizer.Rasterize(StoryOptimizer.Compose(img, o, p, StoryOptimizer.BackgroundColor(img, o)));
    }

    [Fact]
    public void AberrationMovesRedAndBlueInOppositeDirections()
    {
        using var img = HalfBlackHalfWhite();
        var px = Composed(img, new StoryParams { AberrationDX = 3, AberrationDY = 0 });
        int Edge(int ch)
        {
            for (var x = 0; x < 1079; x++) if (px[(960 * 1080 + x) * 4 + ch] > 127) return x;
            throw new Exception("sem borda");
        }
        int r = Edge(0), g = Edge(1), b = Edge(2);
        _out.WriteLine($"aberração 3px: R {r} G {g} B {b}");
        Assert.Equal(3, r - g);
        Assert.Equal(3, g - b);
        Assert.Equal(540, g);
    }

    [Fact]
    public void BloomGlowsAroundBrightAreasAndKeepsTheFarBackgroundDark()
    {
        using var img = HalfBlackHalfWhite();
        var px = Composed(img, new StoryParams { BloomLevel = 1, BlurAngle = 0 });
        int near = Gray(px, 536, 960, 1080), far = Gray(px, 100, 960, 1080), inside = Gray(px, 900, 960, 1080);
        _out.WriteLine($"ofuscação 100%: perto {near} longe {far} dentro {inside}");
        Assert.True(near > 8);
        Assert.True(far < 3);
        Assert.True(inside > 235);
        var soft = Composed(img, new StoryParams { BloomLevel = 0.1 });
        Assert.True(Gray(soft, 536, 960, 1080) < near);
    }

    [Fact]
    public void RasterPassRunsAfterDrawingAndNeutralParamsSkipIt()
    {
        using var flat = MakeImage(1080, 1920, c => c.Clear(new SKColor(153, 153, 153)));
        var neutral = Composed(flat, new StoryParams());
        var copy = (byte[])neutral.Clone();
        StoryOptimizer.ApplyTexture(copy, new StoryParams());
        Assert.Equal(neutral, copy);
        var lined = (byte[])neutral.Clone();
        StoryOptimizer.ApplyTexture(lined, LinesParams(StoryLineDirection.Backslash));
        Assert.Equal(neutral.Length, lined.Length);
        foreach (var (x, y) in new[] { (10, 10), (11, 10), (12, 10), (13, 10), (14, 10), (15, 10), (500, 900), (501, 900), (502, 900), (503, 900) })
        {
            var on = StoryTextureEffects.BandState(x, y, 8, 4, 1, false, 3) != StoryTextureEffects.BandNone;
            Assert.Equal(on, Gray(lined, x, y, 1080) != Gray(neutral, x, y, 1080));
        }
    }

    // MARK: - Arquivo final e amostras

    private static SKBitmap Creative() => MakeImage(1600, 1200, c =>
    {
        using (var shader = SKShader.CreateLinearGradient(new SKPoint(0, 1200), new SKPoint(1600, 0),
                   new[] { new SKColor(115, 13, 153), new SKColor(13, 26, 89) }, SKShaderTileMode.Clamp))
        using (var p = new SKPaint { Shader = shader })
            c.DrawRect(0, 0, 1600, 1200, p);
        using (var p = new SKPaint { Color = new SKColor(255, 204, 26), IsAntialias = true }) c.DrawOval(new SKRect(540, 340, 1060, 860), p);
        using (var p = new SKPaint { Color = new SKColor(230, 38, 51) }) c.DrawRect(80, 1000, 300, 120, p);
        using (var p = new SKPaint { Color = SKColors.White })
            for (var i = 0; i < 4; i++) c.DrawRect(120, 124 + i * 70, 1360 - i * 180, 36, p);
    });

    private string WritePng(SKBitmap bmp, string name)
    {
        var path = Path.Combine(_tmp, name);
        using var img = SKImage.FromBitmap(bmp);
        using var data = img.Encode(SKEncodedImageFormat.Png, 100);
        File.WriteAllBytes(path, data.ToArray());
        return path;
    }

    /// <summary>Cada preset, no arquivo final: JPEG válido de 1080×1920, sem metadados, e com tempo razoável.</summary>
    [Fact]
    public void PresetsWriteValidFilesAndSamples()
    {
        using var creative = Creative();
        var source = WritePng(creative, "criativo.png");
        var folder = Samples ?? Path.Combine(_tmp, "amostras");
        Directory.CreateDirectory(folder);
        var timings = new List<double>();
        foreach (var preset in new[] { StoryTexturePreset.Off, StoryTexturePreset.Subtle, StoryTexturePreset.Balanced, StoryTexturePreset.Intense })
        {
            var o = new StoryOptions { Fit = StoryFit.BlurFit, Intensity = StoryIntensity.Light, TexturePreset = preset };
            var p = StoryParams.Sample(o, 2026);
            Assert.Equal(preset != StoryTexturePreset.Off, p.HasTexture);
            var output = Path.Combine(folder, $"texturas-{preset.ToString().ToLowerInvariant()}.jpg");
            var sw = System.Diagnostics.Stopwatch.StartNew();
            var bytes = StoryOptimizer.Process(source, o, p, output);
            timings.Add(sw.Elapsed.TotalSeconds);
            _out.WriteLine($"textura {preset}: {bytes} bytes · {p.Summary}");
            Assert.True(bytes > 20_000);
            using var decoded = SKBitmap.Decode(output);
            Assert.Equal(1080, decoded.Width);
            Assert.Equal(1920, decoded.Height);
        }
        _out.WriteLine("Otimizador: tempos por preset " + string.Join(", ", timings.Select(t => t.ToString("0.00"))));
        Assert.True(timings.Skip(1).Average() < 60);
    }

    [Fact]
    public void TextureFileIsReproducibleFromTheSameSeed()
    {
        using var creative = Creative();
        var source = WritePng(creative, "repro.png");
        var o = new StoryOptions { Fit = StoryFit.Cover, Format = StoryOutputFormat.Png, TexturePreset = StoryTexturePreset.Balanced };
        var p = StoryParams.Sample(o, 31);
        string a = Path.Combine(_tmp, "a.png"), b = Path.Combine(_tmp, "b.png"), c = Path.Combine(_tmp, "c.png");
        StoryOptimizer.Process(source, o, p, a);
        StoryOptimizer.Process(source, o, p, b);
        Assert.Equal(File.ReadAllBytes(a), File.ReadAllBytes(b));
        StoryOptimizer.Process(source, o, StoryParams.Sample(o, 32), c);
        Assert.NotEqual(File.ReadAllBytes(a), File.ReadAllBytes(c));
    }
}
