using IMPCriativos.Core.Imaging;
using SkiaSharp;

namespace IMPCriativos.Core.Story;

/// <summary>
/// 1.0.0-beta.21: motor do Otimizador em Lote (Stories 9:16). 100% local: SkiaSharp para enquadrar e ajustar
/// e libjpeg-turbo para gravar o JPEG. Nenhuma chamada de rede, nenhuma IA.
///
/// Mesma ordem do Mac (Core Image), por imagem:
///   leitura (orientação EXIF aplicada, maior lado até 4096 px) → espelho (opcional) → enquadramento 9:16
///   → micro-recorte/rotação → micro-perspectiva → brilho/contraste/saturação → temperatura → nitidez ou suavização
///   → deslocamento de canal → granulação → riscos diagonais → vinheta → aberração cromática RGB → bloom/ofuscação
///   → micro-ruído → pixels novos em sRGB → serrilhado das bordas → linhas diagonais (pixel exato)
///   → JPEG (libjpeg-turbo) ou PNG, sem metadados.
///
/// Os metadados somem porque a imagem é redesenhada do zero num buffer novo: EXIF, IPTC, XMP, GPS, comentários
/// e perfis de cor antigos não passam para o arquivo. Só entra um perfil sRGB limpo.
/// Os arquivos não são idênticos bit a bit aos do Mac (Core Image e Skia arredondam diferente), mas os limites,
/// a ordem e os parâmetros sorteados são os mesmos; e aqui a mesma semente gera sempre o mesmo arquivo.
/// </summary>
public static class StoryOptimizer
{
    public const int Width = 1080;
    public const int Height = 1920;
    /// <summary>Limite de leitura: fotos enormes são lidas já reduzidas.</summary>
    public const int MaxSourcePixel = 4096;

    public sealed class Failure : Exception
    {
        public Failure(string message) : base(message) { }
        public static Failure Unreadable => new("Não consegui abrir a imagem (arquivo corrompido ou formato não suportado).");
        public static Failure Render => new("Falha ao desenhar a imagem final.");
        public static Failure Encode(string msg) => new($"Falha ao gravar o arquivo: {msg}");
    }

    // MARK: - Entrada

    public static SKBitmap? LoadSource(string path) => ImageTools.Load(path, MaxSourcePixel);

    /// <summary>Cor de fundo do modo "Cor sólida" (e da transparência de PNGs).</summary>
    public static RGBColor BackgroundColor(SKBitmap source, StoryOptions options)
    {
        if (options.Fit != StoryFit.Solid) return new RGBColor(1, 1, 1);
        return options.SolidColor switch
        {
            StorySolidColor.Black => RGBColor.Black,
            StorySolidColor.Custom => options.CustomColor,
            _ => DominantColorOf(source) ?? RGBColor.Black,
        };
    }

    public static RGBColor? DominantColorOf(SKBitmap source)
    {
        const int side = 64;
        using var small = new SKBitmap(new SKImageInfo(side, side, SKColorType.Rgba8888, SKAlphaType.Premul, SKColorSpace.CreateSrgb()));
        using (var c = new SKCanvas(small))
        {
            c.Clear(SKColors.Transparent);
            using var img = SKImage.FromBitmap(source);
            c.DrawImage(img, new SKRect(0, 0, side, side), new SKSamplingOptions(SKFilterMode.Linear, SKMipmapMode.Linear));
        }
        return DominantColor.Compute(small.Bytes);
    }

    private static SKColor ToColor(RGBColor c) => new(
        (byte)Math.Clamp(R.Round(c.R * 255), 0, 255), (byte)Math.Clamp(R.Round(c.G * 255), 0, 255), (byte)Math.Clamp(R.Round(c.B * 255), 0, 255));

    private static SKBitmap NewCanvasBitmap() =>
        new(new SKImageInfo(Width, Height, SKColorType.Rgba8888, SKAlphaType.Premul, SKColorSpace.CreateSrgb()));

    // MARK: - Composição

    /// <summary>Monta a imagem final 1080×1920 em ponto flutuante (RGB 0–1, de cima para baixo). Usada no lote e no preview.</summary>
    public static float[] Compose(SKBitmap source, StoryOptions options, StoryParams p, RGBColor background)
    {
        float W = Width, H = Height;
        var bg = ToColor(background);

        // espelho + transparência sobre o fundo escolhido (cor sólida) ou branco
        using var flat = new SKBitmap(new SKImageInfo(source.Width, source.Height, SKColorType.Rgba8888, SKAlphaType.Premul, SKColorSpace.CreateSrgb()));
        using (var c = new SKCanvas(flat))
        {
            c.Clear(bg);
            if (p.Mirror) c.SetMatrix(new SKMatrix(-1, 0, source.Width, 0, 1, 0, 0, 0, 1));
            c.DrawBitmap(source, 0, 0);
        }
        using var img = SKImage.FromBitmap(flat);

        // 1) Enquadramento 9:16
        float sw = Math.Max(img.Width, 1), sh = Math.Max(img.Height, 1);
        var coverScale = Math.Max(W / sw, H / sh);
        var fitScale = Math.Min(W / sw, H / sh);
        using var framed = NewCanvasBitmap();
        using (var c = new SKCanvas(framed))
        {
            switch (options.Fit)
            {
                case StoryFit.Cover:
                    c.Clear(SKColors.White);
                    DrawCentered(c, img, coverScale);
                    break;
                case StoryFit.BlurFit:
                {
                    // cópia ampliada (um pouco além do necessário), desfocada e levemente escurecida
                    using var back = NewCanvasBitmap();
                    using (var bc = new SKCanvas(back))
                    {
                        bc.Clear(SKColors.Black);
                        DrawCentered(bc, img, coverScale * 1.08f);
                    }
                    using var backImg = SKImage.FromBitmap(back);
                    using var paint = new SKPaint
                    {
                        ImageFilter = SKImageFilter.CreateBlur(36, 36, SKShaderTileMode.Clamp),
                        ColorFilter = SKColorFilter.CreateColorMatrix(new float[]
                        {
                            1, 0, 0, 0, -0.06f,
                            0, 1, 0, 0, -0.06f,
                            0, 0, 1, 0, -0.06f,
                            0, 0, 0, 1, 0,
                        }),
                    };
                    c.Clear(SKColors.Black);
                    c.DrawImage(backImg, 0, 0, paint);
                    DrawCentered(c, img, fitScale);
                    break;
                }
                default:
                    c.Clear(bg);
                    DrawCentered(c, img, fitScale);
                    break;
            }
        }

        var current = framed.Copy();

        // 2) Micro-recorte e micro-rotação, voltando a exatos 1080×1920
        if (p.CropFraction > 0 || p.RotationDegrees != 0)
        {
            var zoomCrop = 1 / (1 - 2 * Math.Min(p.CropFraction, 0.1));
            var zoomRot = StoryParams.RotationZoom(W, H, p.RotationDegrees);
            // a sobra do recorte deixa a janela escorregar para um lado (90% da folga, por segurança nas bordas)
            var dx = (float)(p.CropShiftX * (zoomCrop - 1) / 2 * 0.9) * W;
            // no Core Image o y cresce para cima: o deslocamento vertical inverte aqui
            var dy = -(float)(p.CropShiftY * (zoomCrop - 1) / 2 * 0.9) * H;
            var m = SKMatrix.CreateTranslation(-W / 2, -H / 2)
                .PostConcat(SKMatrix.CreateScale((float)(zoomCrop * zoomRot), (float)(zoomCrop * zoomRot)))
                // ângulo positivo gira no sentido anti-horário, como no Core Image (y para cima)
                .PostConcat(SKMatrix.CreateRotationDegrees((float)-p.RotationDegrees))
                .PostConcat(SKMatrix.CreateTranslation(W / 2 + dx, H / 2 + dy));
            var next = DrawTransformed(current, m);
            current.Dispose();
            current = next;
        }

        // 2b) Micro-perspectiva (beta.22): amplia pela folga e move cada canto dentro dela — o quadro continua coberto
        if (p.PerspectiveMax > 0 && p.Perspective.Length == 8)
        {
            var mm = (float)Math.Min(p.PerspectiveMax, 0.05);
            float ex = mm * W, ey = mm * H;
            var cc = p.Perspective.Select(v => (float)(Math.Max(-mm, Math.Min(mm, v)) * 0.9)).ToArray();
            // cantos do Core Image (y para cima) convertidos para y para baixo: (x, y) → (x, H − y)
            var bl = new SKPoint(-ex + cc[0] * W, H - (-ey + cc[1] * H));
            var br = new SKPoint(W + ex + cc[2] * W, H - (-ey + cc[3] * H));
            var tr = new SKPoint(W + ex + cc[4] * W, H - (H + ey + cc[5] * H));
            var tl = new SKPoint(-ex + cc[6] * W, H - (H + ey + cc[7] * H));
            var m = Homography(new[] { new SKPoint(0, 0), new SKPoint(W, 0), new SKPoint(W, H), new SKPoint(0, H) },
                new[] { tl, tr, br, bl });
            var next = DrawTransformed(current, m);
            current.Dispose();
            current = next;
        }

        var px = ToFloat(current);
        current.Dispose();

        // 3) Brilho, contraste e saturação (mesma fórmula do CIColorControls)
        if (p.Brightness != 0 || p.Contrast != 0 || p.Saturation != 0)
            ColorControls(px, (float)p.Brightness, (float)(1 + p.Contrast), (float)(1 + p.Saturation));

        // 3b) Temperatura de cor (beta.22): + mais quente, − mais fria
        if (p.TemperatureKelvin != 0) Temperature(px, p.TemperatureKelvin);

        // 4) Micro-nitidez (Unsharp Mask) ou suavização mínima
        if (p.SharpenIntensity > 0)
        {
            var blur = Blur.Gaussian(px, Width, Height, 1.2f);
            var k = (float)p.SharpenIntensity;
            for (var i = 0; i < px.Length; i++) px[i] += k * (px[i] - blur[i]);
        }
        else if (p.SoftenRadius > 0)
        {
            px = Blur.Gaussian(px, Width, Height, (float)p.SoftenRadius);
        }

        // 5) Deslocamento de canal: R ou B andam 1px (deslocamento inteiro, sem reamostrar)
        if (p.ChromaticChannel is ChromaticChannel ch)
            ShiftChannel(px, ch == ChromaticChannel.Red ? 0 : 2, p.ChromaticDX, -p.ChromaticDY);

        // 6) Granulação de filme (monocromática, overlay ou soft-light)
        if (p.GrainOpacity > 0) Grain(px, p);

        // 6b) Riscos diagonais pixel a pixel (beta.22): base ± k, média zero
        if (p.DiagonalAmplitude > 0)
        {
            var per = p.DiagonalPeriod == 4 ? 4 : 3;
            var k = (float)(p.DiagonalAmplitude / 255);
            for (var y = 0; y < Height; y++)
            for (var x = 0; x < Width; x++)
            {
                // o padrão do Mac é ancorado embaixo (y para cima): usa a mesma linha contada de baixo
                var sign = StoryParams.DiagonalSign(x, Height - 1 - y, per, p.DiagonalAnti, p.DiagonalPhase);
                if (sign == 0) continue;
                var o = (y * Width + x) * 3;
                px[o] += sign * k; px[o + 1] += sign * k; px[o + 2] += sign * k;
            }
        }

        // 6c) Vinheta (beta.22): cantos somam ±v da escala, o centro fica igual
        if (p.Vignette != 0)
        {
            var half = MathF.Sqrt(W * W + H * H) / 2;
            float r0 = half * 0.45f, r1 = half, v = (float)p.Vignette;
            for (var y = 0; y < Height; y++)
            for (var x = 0; x < Width; x++)
            {
                var d = MathF.Sqrt((x + 0.5f - W / 2) * (x + 0.5f - W / 2) + (y + 0.5f - H / 2) * (y + 0.5f - H / 2));
                var t = Math.Clamp((d - r0) / (r1 - r0), 0, 1);
                if (t == 0) continue;
                var o = (y * Width + x) * 3;
                px[o] += v * t; px[o + 1] += v * t; px[o + 2] += v * t;
            }
        }

        // 6d) Aberração cromática RGB (beta.23): R anda (+dx, +dy), B anda (−dx, −dy) e G fica
        if (p.AberrationDX != 0 || p.AberrationDY != 0)
        {
            ShiftChannel(px, 0, p.AberrationDX, -p.AberrationDY);
            ShiftChannel(px, 2, -p.AberrationDX, p.AberrationDY);
        }

        // 6e) Ofuscação (beta.23): micro-desfoque direcional + bloom nas luzes, misturados com o original
        if (p.BloomLevel > 0) BloomPass(px, p);

        // 7) Micro-ruído uniforme de ±N níveis por canal (quebra faixas de cor na compressão do Instagram)
        if (p.NoiseAmplitude > 0)
        {
            var k = (float)(p.NoiseAmplitude / 255);
            int ox = (int)p.NoiseOffsetX, oy = (int)p.NoiseOffsetY;
            for (var y = 0; y < Height; y++)
            for (var x = 0; x < Width; x++)
            {
                var o = (y * Width + x) * 3;
                for (var c = 0; c < 3; c++)
                    px[o + c] += (2 * Noise01(x + ox, y + oy, c) - 1) * k;
            }
        }
        return px;
    }

    private static void DrawCentered(SKCanvas c, SKImage img, float scale)
    {
        var dw = img.Width * scale;
        var dh = img.Height * scale;
        // deslocamento inteiro (não borra os pixels), como o `centered` do Mac
        var dx = MathF.Round((Width - dw) / 2, MidpointRounding.AwayFromZero);
        var dy = MathF.Round((Height - dh) / 2, MidpointRounding.AwayFromZero);
        c.DrawImage(img, SKRect.Create(dx, dy, dw, dh), ImageTools.Lanczos);
    }

    /// <summary>Desenha a imagem com a matriz, repetindo as bordas (como o <c>clampedToExtent</c>).</summary>
    private static SKBitmap DrawTransformed(SKBitmap src, SKMatrix m)
    {
        var dst = NewCanvasBitmap();
        using var c = new SKCanvas(dst);
        using var img = SKImage.FromBitmap(src);
        using var shader = img.ToShader(SKShaderTileMode.Clamp, SKShaderTileMode.Clamp, ImageTools.Lanczos, m);
        using var paint = new SKPaint { Shader = shader };
        c.DrawRect(0, 0, Width, Height, paint);
        return dst;
    }

    /// <summary>Matriz de perspectiva que leva os 4 pontos de origem nos 4 de destino.</summary>
    public static SKMatrix Homography(SKPoint[] s, SKPoint[] d)
    {
        var a = new double[8, 9];
        for (var i = 0; i < 4; i++)
        {
            double x = s[i].X, y = s[i].Y, u = d[i].X, v = d[i].Y;
            double[] r1 = { x, y, 1, 0, 0, 0, -u * x, -u * y, u };
            double[] r2 = { 0, 0, 0, x, y, 1, -v * x, -v * y, v };
            for (var k = 0; k < 9; k++) { a[2 * i, k] = r1[k]; a[2 * i + 1, k] = r2[k]; }
        }
        for (var col = 0; col < 8; col++)
        {
            var piv = col;
            for (var r = col + 1; r < 8; r++) if (Math.Abs(a[r, col]) > Math.Abs(a[piv, col])) piv = r;
            for (var k = 0; k < 9; k++) (a[col, k], a[piv, k]) = (a[piv, k], a[col, k]);
            var div = a[col, col];
            for (var k = 0; k < 9; k++) a[col, k] /= div;
            for (var r = 0; r < 8; r++)
            {
                if (r == col) continue;
                var f = a[r, col];
                if (f == 0) continue;
                for (var k = 0; k < 9; k++) a[r, k] -= f * a[col, k];
            }
        }
        return new SKMatrix((float)a[0, 8], (float)a[1, 8], (float)a[2, 8], (float)a[3, 8], (float)a[4, 8], (float)a[5, 8],
            (float)a[6, 8], (float)a[7, 8], 1);
    }

    private static float[] ToFloat(SKBitmap bmp)
    {
        var bytes = bmp.Bytes; // RGBA premultiplicado (opaco aqui)
        var px = new float[Width * Height * 3];
        for (int i = 0, j = 0; i < Width * Height; i++, j += 4)
        {
            px[i * 3] = bytes[j] / 255f;
            px[i * 3 + 1] = bytes[j + 1] / 255f;
            px[i * 3 + 2] = bytes[j + 2] / 255f;
        }
        return px;
    }

    private static void ColorControls(float[] px, float brightness, float contrast, float saturation)
    {
        for (var i = 0; i < px.Length; i += 3)
        {
            float r = px[i], g = px[i + 1], b = px[i + 2];
            var l = 0.2125f * r + 0.7154f * g + 0.0721f * b;
            r = l + (r - l) * saturation; g = l + (g - l) * saturation; b = l + (b - l) * saturation;
            r += brightness; g += brightness; b += brightness;
            px[i] = (r - 0.5f) * contrast + 0.5f;
            px[i + 1] = (g - 0.5f) * contrast + 0.5f;
            px[i + 2] = (b - 0.5f) * contrast + 0.5f;
        }
    }

    /// <summary>Cor de um corpo negro em kelvin (aproximação de Tanner Helland), 0–1.</summary>
    private static (double R, double G, double B) Kelvin(double k)
    {
        var t = k / 100;
        double r, g, b;
        if (t <= 66) { r = 255; g = 99.4708025861 * Math.Log(t) - 161.1195681661; }
        else { r = 329.698727446 * Math.Pow(t - 60, -0.1332047592); g = 288.1221695283 * Math.Pow(t - 60, -0.0755148492); }
        if (t >= 66) b = 255;
        else if (t <= 19) b = 0;
        else b = 138.5177312231 * Math.Log(t - 10) - 305.0447927307;
        return (Math.Clamp(r, 0, 255) / 255, Math.Clamp(g, 0, 255) / 255, Math.Clamp(b, 0, 255) / 255);
    }

    private static void Temperature(float[] px, double kelvin)
    {
        // neutro 6500 K lido como (6500 + K): positivo esquenta, negativo esfria
        var a = Kelvin(6500);
        var b = Kelvin(6500 + kelvin);
        double mr = a.R / b.R, mg = a.G / b.G, mb = a.B / b.B;
        var norm = mg;
        float fr = (float)(mr / norm), fg = 1, fb = (float)(mb / norm);
        for (var i = 0; i < px.Length; i += 3)
        {
            px[i] *= fr;
            px[i + 1] *= fg;
            px[i + 2] *= fb;
        }
    }

    /// <summary>Move um canal (0 = R, 2 = B) em pixels inteiros, repetindo a borda.</summary>
    private static void ShiftChannel(float[] px, int channel, int dx, int dy)
    {
        if (dx == 0 && dy == 0) return;
        var src = new float[Width * Height];
        for (var i = 0; i < Width * Height; i++) src[i] = px[i * 3 + channel];
        for (var y = 0; y < Height; y++)
        {
            var sy = Math.Clamp(y - dy, 0, Height - 1);
            for (var x = 0; x < Width; x++)
            {
                var sx = Math.Clamp(x - dx, 0, Width - 1);
                px[(y * Width + x) * 3 + channel] = src[sy * Width + sx];
            }
        }
    }

    /// <summary>Ruído determinístico de 0 a 1 por pixel (substitui o CIRandomGenerator; mesma posição → mesmo valor).</summary>
    public static float Noise01(int x, int y, int c)
    {
        unchecked
        {
            var h = (ulong)(uint)x * 0x9E3779B97F4A7C15UL ^ (ulong)(uint)y * 0xC2B2AE3D27D4EB4FUL ^ (ulong)(c + 1) * 0x165667B19E3779F9UL;
            h ^= h >> 30; h *= 0xBF58476D1CE4E5B9UL;
            h ^= h >> 27; h *= 0x94D049BB133111EBUL;
            h ^= h >> 31;
            return (h >> 40) / 16777216f;
        }
    }

    private static void Grain(float[] px, StoryParams p)
    {
        int ox = (int)p.GrainOffsetX, oy = (int)p.GrainOffsetY;
        var g = new float[Width * Height * 3];
        for (var y = 0; y < Height; y++)
        for (var x = 0; x < Width; x++)
        {
            var v = Noise01(x + ox, y + oy, 0);
            var o = (y * Width + x) * 3;
            g[o] = v; g[o + 1] = v; g[o + 2] = v;
        }
        g = Blur.Gaussian(g, Width, Height, 0.6f);
        var op = (float)p.GrainOpacity;
        for (var i = 0; i < px.Length; i++)
        {
            var b = Math.Clamp(px[i], 0, 1);
            var s = g[i];
            float blended;
            if (p.GrainSoftLight)
                blended = s <= 0.5f ? b - (1 - 2 * s) * b * (1 - b) : b + (2 * s - 1) * ((b <= 0.25f ? ((16 * b - 12) * b + 4) * b : MathF.Sqrt(b)) - b);
            else
                blended = b < 0.5f ? 2 * b * s : 1 - 2 * (1 - b) * (1 - s);
            px[i] = px[i] * (1 - op) + blended * op;
        }
    }

    private static void BloomPass(float[] px, StoryParams p)
    {
        var l = (float)Math.Min(p.BloomLevel, 1);
        // micro-desfoque direcional
        var radius = 0.4f + 4.2f * l;
        var steps = Math.Max(1, (int)MathF.Ceiling(radius));
        float cx = MathF.Cos((float)p.BlurAngle), cy = -MathF.Sin((float)p.BlurAngle);
        var soft = new float[px.Length];
        for (var y = 0; y < Height; y++)
        for (var x = 0; x < Width; x++)
        {
            float r = 0, g = 0, b = 0;
            var n = 0;
            for (var s = -steps; s <= steps; s++)
            {
                var t = s * radius / steps;
                var sx = Math.Clamp((int)MathF.Round(x + cx * t), 0, Width - 1);
                var sy = Math.Clamp((int)MathF.Round(y + cy * t), 0, Height - 1);
                var o2 = (sy * Width + sx) * 3;
                r += px[o2]; g += px[o2 + 1]; b += px[o2 + 2];
                n++;
            }
            var o = (y * Width + x) * 3;
            soft[o] = r / n; soft[o + 1] = g / n; soft[o + 2] = b / n;
        }
        // bloom: brilho espalhado das luzes somado por cima
        var glow = Blur.Gaussian(soft, Width, Height, 3 + 12 * l);
        var intensity = 0.15f + 0.65f * l;
        var mix = 0.25f + 0.7f * l;
        for (var i = 0; i < px.Length; i++)
        {
            var bright = Math.Max(0, glow[i] - 0.5f) * 2;
            var s = soft[i] + intensity * bright * glow[i];
            px[i] = px[i] * (1 - mix) + s * mix;
        }
    }

    // MARK: - Saída

    /// <summary>Pixels novos RGBX 8 bits sRGB (de cima para baixo). Nada do arquivo original passa daqui.</summary>
    public static byte[] Rasterize(float[] px)
    {
        var o = new byte[Width * Height * 4];
        for (int i = 0, j = 0; i < Width * Height; i++, j += 4)
        {
            o[j] = (byte)Math.Clamp(R.Round(px[i * 3] * 255.0), 0, 255);
            o[j + 1] = (byte)Math.Clamp(R.Round(px[i * 3 + 1] * 255.0), 0, 255);
            o[j + 2] = (byte)Math.Clamp(R.Round(px[i * 3 + 2] * 255.0), 0, 255);
            o[j + 3] = 255;
        }
        return o;
    }

    /// <summary>Etapas de textura que rodam nos pixels (beta.23): serrilhado das bordas e, por último, as linhas.</summary>
    public static void ApplyTexture(byte[] rgbx, StoryParams p)
    {
        if (!p.NeedsRasterPass) return;
        if (p.JitterLevel > 0) StoryTextureEffects.ApplyEdgeJitter(rgbx, Width, Height, p.JitterLevel, p.JitterSeed);
        if (p.LineOpacity > 0) StoryTextureEffects.ApplyLines(rgbx, Width, Height, p);
    }

    private static byte[]? _icc;

    /// <summary>Perfil sRGB limpo (tirado de um JPEG mínimo gravado pelo próprio Skia).</summary>
    public static byte[]? SrgbIcc
    {
        get
        {
            if (_icc != null) return _icc.Length == 0 ? null : _icc;
            try
            {
                using var b = new SKBitmap(new SKImageInfo(1, 1, SKColorType.Rgba8888, SKAlphaType.Opaque, SKColorSpace.CreateSrgb()));
                using var data = b.Encode(SKEncodedImageFormat.Jpeg, 90);
                _icc = ExtractIcc(data.ToArray()) ?? Array.Empty<byte>();
            }
            catch { _icc = Array.Empty<byte>(); }
            return _icc.Length == 0 ? null : _icc;
        }
    }

    /// <summary>Lê o perfil ICC dos marcadores APP2 de um JPEG.</summary>
    public static byte[]? ExtractIcc(byte[] jpeg)
    {
        var parts = new SortedDictionary<int, byte[]>();
        var i = 2;
        while (i + 4 < jpeg.Length && jpeg[i] == 0xFF)
        {
            var marker = jpeg[i + 1];
            if (marker == 0xDA) break;
            var len = (jpeg[i + 2] << 8) | jpeg[i + 3];
            if (marker == 0xE2 && len > 16 && System.Text.Encoding.ASCII.GetString(jpeg, i + 4, 11) == "ICC_PROFILE")
            {
                var seq = jpeg[i + 4 + 12];
                parts[seq] = jpeg[(i + 4 + 14)..(i + 2 + len)];
            }
            i += 2 + len;
        }
        return parts.Count == 0 ? null : parts.Values.SelectMany(x => x).ToArray();
    }

    public static IReadOnlyList<(string Marker, int Length)> JpegSegments(byte[] jpeg)
    {
        var list = new List<(string, int)>();
        var i = 2;
        while (i + 4 < jpeg.Length && jpeg[i] == 0xFF)
        {
            var marker = jpeg[i + 1];
            if (marker == 0xDA) { list.Add(("SOS", 0)); break; }
            var len = (jpeg[i + 2] << 8) | jpeg[i + 3];
            list.Add(($"{marker:X2}", len));
            i += 2 + len;
        }
        return list;
    }

    public static byte[] EncodeJpeg(byte[] rgbx, StoryParams p)
    {
        if (TurboJpeg.Available)
        {
            try { return TurboJpeg.Compress(rgbx, Width, Height, p.Quality, p.Chroma444, p.Progressive, SrgbIcc); }
            catch (Exception e) { throw Failure.Encode(e.Message); }
        }
        // sem a libjpeg-turbo: o Skia grava (sem escolher subamostragem nem progressivo)
        using var bmp = FromRgbx(rgbx);
        using var data = bmp.Encode(SKEncodedImageFormat.Jpeg, p.Quality) ?? throw Failure.Encode("JPEG não finalizou");
        return data.ToArray();
    }

    public static SKBitmap FromRgbx(byte[] rgbx)
    {
        var bmp = new SKBitmap(new SKImageInfo(Width, Height, SKColorType.Rgba8888, SKAlphaType.Opaque, SKColorSpace.CreateSrgb()));
        System.Runtime.InteropServices.Marshal.Copy(rgbx, 0, bmp.GetPixels(), rgbx.Length);
        return bmp;
    }

    /// <summary>PNG sem metadados (só os blocos de imagem e de cor).</summary>
    public static byte[] EncodePng(byte[] rgbx)
    {
        using var bmp = FromRgbx(rgbx);
        using var data = bmp.Encode(SKEncodedImageFormat.Png, 100) ?? throw Failure.Encode("PNG não finalizou");
        return CleanPng(data.ToArray());
    }

    /// <summary>Blocos do PNG que ficam: imagem e cor. Qualquer outro (eXIf, textos, data, etc.) sai do arquivo.</summary>
    public static readonly HashSet<string> KeptPngChunks = new() { "IHDR", "PLTE", "IDAT", "IEND", "iCCP", "sRGB", "gAMA", "cHRM" };

    public static byte[] CleanPng(byte[] b)
    {
        byte[] signature = { 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A };
        if (b.Length <= 8 || !b.Take(8).SequenceEqual(signature)) return b;
        var o = new List<byte>(signature);
        var i = 8;
        while (i + 12 <= b.Length)
        {
            var length = (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
            var end = i + 12 + length;
            if (length < 0 || end > b.Length) return b;
            var type = System.Text.Encoding.ASCII.GetString(b, i + 4, 4);
            if (KeptPngChunks.Contains(type)) o.AddRange(b[i..end]);
            i = end;
            if (type == "IEND") break;
        }
        return o.ToArray();
    }

    /// <summary>Pixels finais (RGBX) de uma imagem: composição + texturas. O mesmo caminho do arquivo e do preview.</summary>
    public static byte[] Render(SKBitmap source, StoryOptions options, StoryParams p)
    {
        var composed = Compose(source, options, p, BackgroundColor(source, options));
        var rgbx = Rasterize(composed);
        ApplyTexture(rgbx, p);
        return rgbx;
    }

    /// <summary>Processa uma imagem do lote e grava em <paramref name="output"/>. Devolve o tamanho do arquivo em bytes.</summary>
    public static int Process(string sourcePath, StoryOptions options, StoryParams p, string output)
    {
        using var src = LoadSource(sourcePath) ?? throw Failure.Unreadable;
        var rgbx = Render(src, options, p);
        var data = options.Format == StoryOutputFormat.Jpg ? EncodeJpeg(rgbx, p) : EncodePng(rgbx);
        Util.AtomicFile.WriteAllBytes(output, data);
        return data.Length;
    }

    /// <summary>Imagem do preview (mesma composição do arquivo final), em RGBX 1080×1920.</summary>
    public static byte[] Preview(SKBitmap source, StoryOptions options, StoryParams p) => Render(source, options, p);
}

/// <summary>Desfoque gaussiano em ponto flutuante (RGB intercalado), repetindo as bordas.</summary>
public static class Blur
{
    public static float[] Gaussian(float[] src, int w, int h, float sigma)
    {
        if (sigma <= 0) return (float[])src.Clone();
        if (sigma < 2.5f) return Separable(src, w, h, Kernel(sigma));
        // sigma grande: três passadas de caixa (aproximação clássica, linear no tamanho)
        var boxes = BoxSizes(sigma, 3);
        var o = src;
        foreach (var b in boxes) o = Box(o, w, h, (b - 1) / 2);
        return o;
    }

    private static float[] Kernel(float sigma)
    {
        var r = Math.Max(1, (int)MathF.Ceiling(sigma * 3));
        var k = new float[2 * r + 1];
        float sum = 0;
        for (var i = -r; i <= r; i++) { k[i + r] = MathF.Exp(-(i * i) / (2 * sigma * sigma)); sum += k[i + r]; }
        for (var i = 0; i < k.Length; i++) k[i] /= sum;
        return k;
    }

    private static float[] Separable(float[] src, int w, int h, float[] k)
    {
        var r = k.Length / 2;
        var tmp = new float[src.Length];
        var o = new float[src.Length];
        for (var y = 0; y < h; y++)
        for (var x = 0; x < w; x++)
        for (var c = 0; c < 3; c++)
        {
            float s = 0;
            for (var i = -r; i <= r; i++) s += k[i + r] * src[(y * w + Math.Clamp(x + i, 0, w - 1)) * 3 + c];
            tmp[(y * w + x) * 3 + c] = s;
        }
        for (var y = 0; y < h; y++)
        for (var x = 0; x < w; x++)
        for (var c = 0; c < 3; c++)
        {
            float s = 0;
            for (var i = -r; i <= r; i++) s += k[i + r] * tmp[(Math.Clamp(y + i, 0, h - 1) * w + x) * 3 + c];
            o[(y * w + x) * 3 + c] = s;
        }
        return o;
    }

    private static int[] BoxSizes(float sigma, int n)
    {
        var wIdeal = Math.Sqrt(12 * sigma * sigma / n + 1);
        var wl = (int)Math.Floor(wIdeal);
        if (wl % 2 == 0) wl--;
        var wu = wl + 2;
        var mIdeal = (12 * sigma * sigma - n * wl * wl - 4 * n * wl - 3 * n) / (-4.0 * wl - 4);
        var m = (int)Math.Round(mIdeal, MidpointRounding.AwayFromZero);
        return Enumerable.Range(0, n).Select(i => i < m ? wl : wu).ToArray();
    }

    private static float[] Box(float[] src, int w, int h, int r)
    {
        if (r <= 0) return src;
        var tmp = new float[src.Length];
        var o = new float[src.Length];
        float norm = 1f / (2 * r + 1);
        for (var y = 0; y < h; y++)
        for (var c = 0; c < 3; c++)
        {
            float acc = 0;
            for (var i = -r; i <= r; i++) acc += src[(y * w + Math.Clamp(i, 0, w - 1)) * 3 + c];
            for (var x = 0; x < w; x++)
            {
                tmp[(y * w + x) * 3 + c] = acc * norm;
                acc += src[(y * w + Math.Min(x + r + 1, w - 1)) * 3 + c] - src[(y * w + Math.Max(x - r, 0)) * 3 + c];
            }
        }
        for (var x = 0; x < w; x++)
        for (var c = 0; c < 3; c++)
        {
            float acc = 0;
            for (var i = -r; i <= r; i++) acc += tmp[(Math.Clamp(i, 0, h - 1) * w + x) * 3 + c];
            for (var y = 0; y < h; y++)
            {
                o[(y * w + x) * 3 + c] = acc * norm;
                acc += tmp[(Math.Min(y + r + 1, h - 1) * w + x) * 3 + c] - tmp[(Math.Max(y - r, 0) * w + x) * 3 + c];
            }
        }
        return o;
    }
}
