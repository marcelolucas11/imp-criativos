using System.Diagnostics;
using System.Text;
using IMPCriativos.Core.Story;
using SkiaSharp;
using Xunit;
using Xunit.Abstractions;

namespace IMPCriativos.Tests;

/// <summary>
/// Otimizador em Lote: roda o motor de verdade (Skia + libjpeg-turbo) em imagens fabricadas e confere o resultado
/// pixel a pixel. Porte de Tests/IMPCriativosLogicTests/StoryOptimizerImageTests.swift.
/// Grava amostras em IMP_STORY_SAMPLES (o GitHub Actions guarda essa pasta para conferência visual).
/// </summary>
[Collection("Preferencias")]
public sealed class StoryOptimizerImageTests : IDisposable
{
    private readonly ITestOutputHelper _out;
    private readonly string _tmp;
    private static readonly string? Samples = Environment.GetEnvironmentVariable("IMP_STORY_SAMPLES");

    public StoryOptimizerImageTests(ITestOutputHelper output)
    {
        _out = output;
        _tmp = Path.Combine(Path.GetTempPath(), "story-tests-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_tmp);
        if (Samples != null) Directory.CreateDirectory(Samples);
    }

    public void Dispose()
    {
        try { Directory.Delete(_tmp, true); } catch { }
    }

    // MARK: - Imagens fabricadas

    private static SKBitmap MakeImage(int width, int height, Action<SKCanvas> draw)
    {
        var bmp = new SKBitmap(new SKImageInfo(width, height, SKColorType.Rgba8888, SKAlphaType.Premul));
        using var c = new SKCanvas(bmp);
        c.Clear(SKColors.Black);
        draw(c);
        c.Flush();
        return bmp;
    }

    private static SKColor C(double r, double g, double b) =>
        new((byte)Math.Round(r * 255, MidpointRounding.AwayFromZero), (byte)Math.Round(g * 255, MidpointRounding.AwayFromZero), (byte)Math.Round(b * 255, MidpointRounding.AwayFromZero));

    private static void Fill(SKCanvas c, SKColor color, float x, float y, float w, float h)
    {
        using var p = new SKPaint { Color = color, IsAntialias = false };
        c.DrawRect(x, y, w, h, p);
    }

    private static SKBitmap Flat(double r, double g, double b, int width = 1080, int height = 1920) =>
        MakeImage(width, height, c => Fill(c, C(r, g, b), 0, 0, width, height));

    /// <summary>Criativo de mentira: degradê, formas e barras brancas no lugar do texto.</summary>
    private static SKBitmap Colorful(int width = 1600, int height = 1200) => MakeImage(width, height, c =>
    {
        using (var shader = SKShader.CreateLinearGradient(new SKPoint(0, 0), new SKPoint(width, height),
                   new[] { C(0.45, 0.05, 0.6), C(0.05, 0.1, 0.35) }, SKShaderTileMode.Clamp))
        using (var p = new SKPaint { Shader = shader })
            c.DrawRect(0, 0, width, height, p);
        using (var p = new SKPaint { Color = C(1, 0.8, 0.1), IsAntialias = true })
            c.DrawOval(new SKRect(width / 2f - 260, height / 2f - 260, width / 2f + 260, height / 2f + 260), p);
        Fill(c, C(0.9, 0.15, 0.2), 80, height - 200, 300, 120);
        for (var i = 0; i < 4; i++) Fill(c, SKColors.White, 120, 124 + i * 70, width - 240 - i * 180, 36);
    });

    private string WritePng(SKBitmap bmp, string name)
    {
        var path = Path.Combine(_tmp, name);
        using var img = SKImage.FromBitmap(bmp);
        using var data = img.Encode(SKEncodedImageFormat.Png, 100);
        File.WriteAllBytes(path, data.ToArray());
        return path;
    }

    private string WriteJpeg(SKBitmap bmp, string name, byte[]? app1 = null)
    {
        var path = Path.Combine(_tmp, name);
        using var img = SKImage.FromBitmap(bmp);
        using var data = img.Encode(SKEncodedImageFormat.Jpeg, 92);
        var bytes = data.ToArray();
        if (app1 != null)
        {
            // insere o APP1 (EXIF) logo depois do SOI
            var seg = new List<byte> { 0xFF, 0xD8, 0xFF, 0xE1, (byte)((app1.Length + 2) >> 8), (byte)((app1.Length + 2) & 255) };
            seg.AddRange(app1);
            seg.AddRange(bytes.Skip(2));
            bytes = seg.ToArray();
        }
        File.WriteAllBytes(path, bytes);
        return path;
    }

    /// <summary>EXIF big-endian com orientação 6, Make, Software e um "GPS" de mentira (só para conferir que some).</summary>
    private static byte[] FakeExif()
    {
        var tiff = new List<byte>();
        void U16(int v) { tiff.Add((byte)(v >> 8)); tiff.Add((byte)v); }
        void U32(int v) { tiff.Add((byte)(v >> 24)); tiff.Add((byte)(v >> 16)); tiff.Add((byte)(v >> 8)); tiff.Add((byte)v); }
        var make = Encoding.ASCII.GetBytes("SecretCam\0");
        var soft = Encoding.ASCII.GetBytes("SpyWare 9\0");
        var comment = Encoding.ASCII.GetBytes("comentario secreto GPS 29.95 S\0");
        tiff.AddRange(new byte[] { (byte)'M', (byte)'M', 0, 42 });
        U32(8);
        const int entries = 4;
        var dataStart = 8 + 2 + entries * 12 + 4;
        U16(entries);
        U16(0x010F); U16(2); U32(make.Length); U32(dataStart);
        U16(0x0112); U16(3); U32(1); U16(6); U16(0);
        U16(0x0131); U16(2); U32(soft.Length); U32(dataStart + make.Length);
        U16(0x010E); U16(2); U32(comment.Length); U32(dataStart + make.Length + soft.Length);
        U32(0);
        tiff.AddRange(make);
        tiff.AddRange(soft);
        tiff.AddRange(comment);
        var app1 = new List<byte>(Encoding.ASCII.GetBytes("Exif\0\0"));
        app1.AddRange(tiff);
        return app1.ToArray();
    }

    private static byte[] Pixels(float[] composed) => StoryOptimizer.Rasterize(composed);

    private static (int W, int H, byte[] Px)? Decode(string path)
    {
        using var bmp = SKBitmap.Decode(path);
        if (bmp == null) return null;
        using var rgba = new SKBitmap(new SKImageInfo(bmp.Width, bmp.Height, SKColorType.Rgba8888, SKAlphaType.Opaque));
        using var canvas = new SKCanvas(rgba);
        canvas.DrawBitmap(bmp, 0, 0);
        return (bmp.Width, bmp.Height, rgba.Bytes);
    }

    private static (int R, int G, int B) Pixel(byte[] px, int x, int y, int width = 1080)
    {
        var i = (y * width + x) * 4;
        return (px[i], px[i + 1], px[i + 2]);
    }

    private static (double Mean, double Sd, int Min, int Max) ChannelStats(byte[] px, int channel)
    {
        double sum = 0, sq = 0, n = 0;
        int lo = 255, hi = 0;
        for (var i = channel; i < px.Length; i += 4)
        {
            int v = px[i];
            sum += v; sq += v * v; lo = Math.Min(lo, v); hi = Math.Max(hi, v); n++;
        }
        var mean = sum / n;
        return (mean, Math.Sqrt(sq / n - mean * mean), lo, hi);
    }

    private static StoryOptions CoverOptions => new() { Fit = StoryFit.Cover };

    private static float[] Compose(SKBitmap img, StoryOptions options, StoryParams p) =>
        StoryOptimizer.Compose(img, options, p, StoryOptimizer.BackgroundColor(img, options));

    private static void Near(double expected, double actual, double accuracy, string? msg = null) =>
        Assert.True(Math.Abs(expected - actual) <= accuracy, $"{msg} esperado {expected} ± {accuracy}, veio {actual}");

    // MARK: - Geometria e enquadramento

    [Fact]
    public void NeutralParamsKeepAFlatImage()
    {
        using var img = Flat(0.5, 0.5, 0.5);
        var px = Pixels(Compose(img, CoverOptions, new StoryParams()));
        Assert.Equal(1080 * 1920 * 4, px.Length);
        var s = ChannelStats(px, 1);
        Assert.True(s.Max - s.Min <= 1, "sem variações, a imagem lisa continua lisa");
    }

    [Fact]
    public void RotationAndCropLeaveNoEmptyCorners()
    {
        using var green = Flat(0.1, 0.8, 0.2);
        foreach (var shift in new[] { -1.0, 1.0 })
        {
            var p = new StoryParams { RotationDegrees = 0.8 * shift, CropFraction = 0.015, CropShiftX = shift, CropShiftY = -shift };
            var px = Pixels(Compose(green, CoverOptions, p));
            foreach (var (x, y) in new[] { (0, 0), (1079, 0), (0, 1919), (1079, 1919) })
            {
                var c = Pixel(px, x, y);
                Assert.True(c.G > 180, $"canto ({x},{y}) vazio com rotação {p.RotationDegrees}");
                Assert.True(c.R < 60);
            }
        }
    }

    [Fact]
    public void MirrorSwapsSides()
    {
        using var img = MakeImage(1080, 1920, c =>
        {
            Fill(c, C(1, 0, 0), 0, 0, 540, 1920);
            Fill(c, C(0, 0, 1), 540, 0, 540, 1920);
        });
        var p = new StoryParams();
        var plain = Pixels(Compose(img, CoverOptions, p));
        Assert.True(Pixel(plain, 100, 960).R > 200);
        p.Mirror = true;
        var mirrored = Pixels(Compose(img, CoverOptions, p));
        var px = Pixel(mirrored, 100, 960);
        Assert.True(px.B > 200, "espelhado: o azul passa para a esquerda");
        Assert.True(px.R < 40);
    }

    [Fact]
    public void BlurFitFillsTopAndBottomWithTheImage()
    {
        var o = new StoryOptions { Fit = StoryFit.BlurFit };
        using var wide = Flat(0.9, 0.5, 0.1, 1600, 900);
        var px = Pixels(Compose(wide, o, new StoryParams()));
        foreach (var c in new[] { Pixel(px, 540, 100), Pixel(px, 540, 1820) })
        {
            Assert.True(c.R > 150, "o fundo é a própria imagem desfocada, não preto");
            Assert.True(c.B < 80, "nem branco");
        }
        Near(230, Pixel(px, 540, 960).R, 3);
    }

    [Fact]
    public void SolidUsesDominantColor()
    {
        var o = new StoryOptions { Fit = StoryFit.Solid, SolidColor = StorySolidColor.Dominant };
        using var img = MakeImage(1600, 900, c =>
        {
            Fill(c, new SKColor(220, 30, 30), 0, 0, 1600, 900);
            Fill(c, C(0, 0, 1), 600, 300, 300, 300);
        });
        var dominant = Pixels(Compose(img, o, new StoryParams()));
        var px = Pixel(dominant, 10, 10);
        Near(220, px.R, 6);
        Near(30, px.G, 6);
        o.SolidColor = StorySolidColor.Black;
        var black = Pixels(Compose(img, o, new StoryParams()));
        Assert.True(Pixel(black, 10, 10).R < 3);
    }

    // MARK: - Cor, ruído, canal, granulação

    [Fact]
    public void BrightnessShiftMatchesPercent()
    {
        using var gray = Flat(0.5, 0.5, 0.5);
        var baseMean = ChannelStats(Pixels(Compose(gray, CoverOptions, new StoryParams())), 0).Mean;
        var s = ChannelStats(Pixels(Compose(gray, CoverOptions, new StoryParams { Brightness = 0.02 })), 0);
        Near(baseMean + 5.1, s.Mean, 1.6, "+2% de brilho ≈ +5 níveis");
    }

    /// <summary>O ruído fica dentro de ±N níveis, com média no lugar (não clareia nem escurece a imagem).</summary>
    [Fact]
    public void NoiseStaysWithinAmplitude()
    {
        using var gray = Flat(0.5, 0.5, 0.5);
        var baseMean = ChannelStats(Pixels(Compose(gray, CoverOptions, new StoryParams())), 0).Mean;
        var px = Pixels(Compose(gray, CoverOptions, new StoryParams { NoiseAmplitude = 3, NoiseOffsetX = 777, NoiseOffsetY = 1234 }));
        for (var channel = 0; channel < 3; channel++)
        {
            var s = ChannelStats(px, channel);
            _out.WriteLine($"ruído ±3 canal {channel}: média {s.Mean} desvio {s.Sd} min {s.Min} max {s.Max}");
            Near(baseMean, s.Mean, 0.8);
            Assert.True(s.Sd > 1.2, "o ruído existe");
            Assert.True(s.Sd < 2.3);
            Assert.True(s.Min >= baseMean - 4.5);
            Assert.True(s.Max <= baseMean + 4.5);
        }
    }

    [Fact]
    public void ChromaticShiftMovesOneChannelByOnePixel()
    {
        using var img = MakeImage(1080, 1920, c => Fill(c, SKColors.White, 540, 0, 540, 1920));
        var px = Pixels(Compose(img, CoverOptions, new StoryParams { ChromaticChannel = ChromaticChannel.Red, ChromaticDX = 1 }));
        int? Edge(int channel)
        {
            for (var x = 0; x < 1079; x++) if (px[(960 * 1080 + x) * 4 + channel] > 127) return x;
            return null;
        }
        var g = Edge(1)!.Value;
        var r = Edge(0)!.Value;
        var b = Edge(2)!.Value;
        Assert.Equal(g, b);
        Assert.Equal(1, Math.Abs(r - g));
    }

    [Fact]
    public void FilmGrainIsSubtle()
    {
        using var gray = Flat(0.5, 0.5, 0.5);
        var baseMean = ChannelStats(Pixels(Compose(gray, CoverOptions, new StoryParams())), 1).Mean;
        var s = ChannelStats(Pixels(Compose(gray, CoverOptions, new StoryParams { GrainOpacity = 0.03, GrainOffsetX = 50 })), 1);
        _out.WriteLine($"granulação 3%: média {s.Mean} desvio {s.Sd} min {s.Min} max {s.Max}");
        Near(baseMean, s.Mean, 1.5);
        Assert.True(s.Max - s.Min > 0, "a granulação existe");
        Assert.True(s.Max - s.Min <= 10);
    }

    // MARK: - Riscos diagonais, temperatura, vinheta, perspectiva

    /// <summary>Imagem lisa + riscos: só três níveis (base − a, base, base + a), constantes ao longo de uma diagonal, média igual.</summary>
    [Fact]
    public void DiagonalLinesDarkenLightenAndKeepTone()
    {
        using var gray = Flat(0.5, 0.5, 0.5);
        var flatPx = Pixels(Compose(gray, CoverOptions, new StoryParams()));
        int baseV = flatPx[4];
        foreach (var (period, anti) in new[] { (3, false), (4, true) })
        {
            var p = new StoryParams { DiagonalAmplitude = 6, DiagonalPeriod = period, DiagonalAnti = anti, DiagonalPhase = 1 };
            var px = Pixels(Compose(gray, CoverOptions, p));
            var s = ChannelStats(px, 1);
            _out.WriteLine($"riscos período {period}: média {s.Mean} min {s.Min} max {s.Max}");
            Near(baseV, s.Mean, 0.6, "o tom geral não muda");
            Near(baseV - 6, s.Min, 1);
            Near(baseV + 6, s.Max, 1);
            var levels = new HashSet<int>();
            int down = 0, up = 0, samples = 0;
            for (var y = 100; y < 1800; y += 37)
            {
                for (var x = 50; x < 1000; x += 29)
                {
                    int v = px[(y * 1080 + x) * 4 + 1];
                    levels.Add(v);
                    if (v == px[((y + 1) * 1080 + x + 1) * 4 + 1]) down++;
                    if (v == px[((y - 1) * 1080 + x + 1) * 4 + 1]) up++;
                    samples++;
                }
            }
            Assert.True(levels.Count <= 5, $"só escurece, mantém e clareia: {string.Join(",", levels.OrderBy(v => v))}");
            Assert.Equal(samples, Math.Max(down, up));
        }
    }

    [Fact]
    public void TemperaturePositiveIsWarmer()
    {
        using var gray = Flat(0.5, 0.5, 0.5);
        var w = Pixel(Pixels(Compose(gray, CoverOptions, new StoryParams { TemperatureKelvin = 500 })), 540, 960);
        var c = Pixel(Pixels(Compose(gray, CoverOptions, new StoryParams { TemperatureKelvin = -500 })), 540, 960);
        _out.WriteLine($"temperatura +500K: {w} · −500K: {c}");
        Assert.True(w.R - w.B > 2, "+ deixa mais quente (mais vermelho que azul)");
        Assert.True(c.R - c.B < -2, "− deixa mais fria");
        Assert.True(Math.Abs(w.R - w.B) < 40, "sutil");
    }

    [Fact]
    public void VignetteChangesCornersNotCenter()
    {
        using var gray = Flat(0.5, 0.5, 0.5);
        var baseG = Pixel(Pixels(Compose(gray, CoverOptions, new StoryParams())), 540, 960).G;
        var dark = Pixels(Compose(gray, CoverOptions, new StoryParams { Vignette = -0.10 }));
        Near(baseG, Pixel(dark, 540, 960).G, 1);
        Near(baseG - 25.5, Pixel(dark, 0, 0).G, 3, "canto escurece 10% da escala");
        var light = Pixels(Compose(gray, CoverOptions, new StoryParams { Vignette = 0.10 }));
        Near(baseG + 25.5, Pixel(light, 1079, 1919).G, 3);
    }

    /// <summary>Agressivo no extremo de tudo (recorte, rotação, perspectiva): nenhum canto vazio.</summary>
    [Fact]
    public void AggressiveGeometryLeavesNoEmptyCorners()
    {
        using var green = Flat(0.1, 0.8, 0.2);
        foreach (var sign in new[] { -1.0, 1.0 })
        {
            var p = new StoryParams
            {
                CropFraction = 0.05, CropShiftX = sign, CropShiftY = sign, RotationDegrees = 2 * sign, PerspectiveMax = 0.015,
                Perspective = Enumerable.Range(0, 8).Select(i => (i % 2 == 0 ? sign : -sign) * 0.015).ToArray(),
            };
            var px = Pixels(Compose(green, CoverOptions, p));
            foreach (var (x, y) in new[] { (0, 0), (1079, 0), (0, 1919), (1079, 1919), (540, 0), (0, 960) })
                Assert.True(Pixel(px, x, y).G > 180, $"ponto ({x},{y}) vazio");
        }
    }

    // MARK: - Arquivo final

    private sealed record JpegInfo(bool Progressive, byte? Sampling, bool Exif, bool Xmp, bool Icc, bool Comment);

    private static JpegInfo Info(byte[] b)
    {
        bool progressive = false, exif = false, xmp = false, icc = false, comment = false;
        byte? sampling = null;
        var i = 2;
        while (i + 4 < b.Length && b[i] == 0xFF)
        {
            var m = b[i + 1];
            var len = (b[i + 2] << 8) | b[i + 3];
            var seg = b.AsSpan(i + 4, Math.Max(0, Math.Min(len - 2, b.Length - i - 4)));
            switch (m)
            {
                case 0xE1:
                    if (seg.StartsWith("Exif"u8)) exif = true;
                    if (Encoding.UTF8.GetString(seg).Contains("ns.adobe.com/xap")) xmp = true;
                    break;
                case 0xE2:
                    if (seg.StartsWith("ICC_PROFILE"u8)) icc = true;
                    break;
                case 0xFE:
                    comment = true;
                    break;
                case 0xC0 or 0xC1 or 0xC2:
                    progressive = m == 0xC2;
                    sampling = b[i + 11];
                    break;
                case 0xDA:
                    return new JpegInfo(progressive, sampling, exif, xmp, icc, comment);
            }
            i += 2 + len;
        }
        return new JpegInfo(progressive, sampling, exif, xmp, icc, comment);
    }

    private static bool Contains(byte[] data, string text) => data.AsSpan().IndexOf(Encoding.ASCII.GetBytes(text)) >= 0;

    [Fact]
    public void OutputIsCleanStoryJpeg()
    {
        using var colorful = Colorful(1200, 1600);
        var source = WriteJpeg(colorful, "entrada.jpg", FakeExif());
        Assert.True(Contains(File.ReadAllBytes(source), "SecretCam"), "a entrada tem metadados (conferência do teste)");
        using (var check = SKCodec.Create(source)) Assert.Equal(SKEncodedOrigin.RightTop, check.EncodedOrigin);

        var o = new StoryOptions { Intensity = StoryIntensity.Moderate };
        foreach (var (seed, name) in new[] { (11UL, "a"), (12UL, "b"), (13UL, "c"), (14UL, "d") })
        {
            var p = StoryParams.Sample(o, seed);
            var output = Path.Combine(_tmp, $"story_{name}.jpg");
            StoryOptimizer.Process(source, o, p, output);
            var data = File.ReadAllBytes(output);
            var info = Info(data);
            Assert.False(Contains(data, "SecretCam"));
            Assert.False(Contains(data, "SpyWare"));
            Assert.False(Contains(data, "secreto"));
            Assert.False(info.Exif, "sem EXIF");
            Assert.False(info.Xmp, "sem XMP");
            Assert.False(info.Comment, "sem comentário");
            Assert.True(info.Icc, "com perfil sRGB");
            if (TurboJpeg.Available)
            {
                Assert.Equal(p.Progressive, info.Progressive);
                Assert.Equal(p.Chroma444 ? (byte)0x11 : (byte)0x22, info.Sampling);
            }
            var decoded = Decode(output);
            Assert.NotNull(decoded);
            Assert.Equal(1080, decoded!.Value.W);
            Assert.Equal(1920, decoded.Value.H);
        }
    }

    [Fact]
    public void SameSeedGivesIdenticalFileAndDifferentSeedsDiffer()
    {
        using var colorful = Colorful();
        var source = WritePng(colorful, "fonte.png");
        var o = new StoryOptions { Intensity = StoryIntensity.Moderate };
        var p1 = StoryParams.Sample(o, 5);
        var p2 = StoryParams.Sample(o, 6);
        string a = Path.Combine(_tmp, "a.jpg"), b = Path.Combine(_tmp, "b.jpg"), c = Path.Combine(_tmp, "c.jpg");
        StoryOptimizer.Process(source, o, p1, a);
        StoryOptimizer.Process(source, o, p1, b);
        StoryOptimizer.Process(source, o, p2, c);
        Assert.Equal(File.ReadAllBytes(a), File.ReadAllBytes(b));
        Assert.NotEqual(File.ReadAllBytes(a), File.ReadAllBytes(c));
    }

    [Fact]
    public void PngOutputHasNoMetadata()
    {
        using var colorful = Colorful();
        var source = WritePng(colorful, "fonte.png");
        var o = new StoryOptions { Format = StoryOutputFormat.Png };
        var output = Path.Combine(_tmp, "story.png");
        StoryOptimizer.Process(source, o, StoryParams.Sample(o, 3), output);
        var decoded = Decode(output);
        Assert.Equal(1080, decoded!.Value.W);
        Assert.Equal(1920, decoded.Value.H);
        var bytes = File.ReadAllBytes(output);
        var types = new List<string>();
        var i = 8;
        while (i + 12 <= bytes.Length)
        {
            var length = (bytes[i] << 24) | (bytes[i + 1] << 16) | (bytes[i + 2] << 8) | bytes[i + 3];
            types.Add(Encoding.ASCII.GetString(bytes, i + 4, 4));
            i += 12 + length;
        }
        _out.WriteLine("PNG blocos: " + string.Join(",", types));
        Assert.Equal("IHDR", types.First());
        Assert.Equal("IEND", types.Last());
        Assert.True(types.All(StoryOptimizer.KeptPngChunks.Contains), "só blocos de imagem e cor: " + string.Join(",", types));
        Assert.DoesNotContain("eXIf", types);
    }

    [Fact]
    public void CleanPngDropsTextAndExifChunks()
    {
        static byte[] Chunk(string type, byte[] payload)
        {
            var n = payload.Length;
            return new[] { (byte)(n >> 24), (byte)(n >> 16), (byte)(n >> 8), (byte)n }
                .Concat(Encoding.ASCII.GetBytes(type)).Concat(payload).Concat(new byte[4]).ToArray();
        }
        var sig = new byte[] { 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A };
        var ihdr = Chunk("IHDR", Enumerable.Repeat((byte)1, 13).ToArray());
        var idat = Chunk("IDAT", new byte[] { 9, 9, 9 });
        var iend = Chunk("IEND", Array.Empty<byte>());
        var dirty = sig.Concat(ihdr).Concat(Chunk("eXIf", Encoding.ASCII.GetBytes("SecretCam")))
            .Concat(Chunk("tEXt", Encoding.ASCII.GetBytes("Software Spy"))).Concat(idat).Concat(iend).ToArray();
        Assert.Equal(sig.Concat(ihdr).Concat(idat).Concat(iend).ToArray(), StoryOptimizer.CleanPng(dirty));
    }

    /// <summary>Amostras para conferir a olho (guardadas pelo GitHub Actions) e tempo por imagem.</summary>
    [Fact]
    public void WriteSamplesAndMeasureSpeed()
    {
        using var big = Colorful(4000, 3000);
        var source = WritePng(big, "fonte-grande.png");
        var folder = Samples ?? Path.Combine(_tmp, "amostras");
        Directory.CreateDirectory(folder);
        File.Copy(source, Path.Combine(folder, "0-entrada-4000x3000.png"), true);
        var timings = new List<double>();
        var fits = StoryLabels.Fits;
        for (var i = 0; i < fits.Length; i++)
        {
            foreach (var intensity in new[] { StoryIntensity.Light, StoryIntensity.Moderate, StoryIntensity.Normal, StoryIntensity.Aggressive })
            {
                var o = new StoryOptions { Fit = fits[i], Intensity = intensity, SolidColor = StorySolidColor.Dominant };
                var output = Path.Combine(folder, $"{i + 1}-{Raw(fits[i])}-{intensity.ToString().ToLowerInvariant()}.jpg");
                var sw = Stopwatch.StartNew();
                StoryOptimizer.Process(source, o, StoryParams.Sample(o, (ulong)(100 + i)), output);
                timings.Add(sw.Elapsed.TotalSeconds);
            }
        }
        var avg = timings.Average();
        _out.WriteLine($"Otimizador: {avg:0.000} s por imagem (entrada 4000×3000, {timings.Count} amostras)");
        Assert.True(avg < 8, "uma imagem não pode levar mais que alguns segundos");
    }

    private static string Raw(StoryFit f) => f switch { StoryFit.Cover => "cover", StoryFit.BlurFit => "blurFit", _ => "solid" };
}
