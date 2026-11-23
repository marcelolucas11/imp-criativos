using System.Collections.Concurrent;
using SkiaSharp;

namespace IMPCriativos.Core.Imaging;

/// <summary>
/// Leitores extras de imagem que o Skia não abre (HEIC/HEIF no Windows, pelo WIC). O App registra o dele na abertura.
/// </summary>
public interface IImageDecoderExtension
{
    /// <summary>Abre a imagem já com a orientação aplicada (RGBA, sRGB) ou devolve null.</summary>
    SKBitmap? Decode(string path);

    /// <summary>Mensagem para o usuário quando o formato não abre (ex.: falta o codec HEIF).</summary>
    string? UnsupportedMessage(string path);
}

/// <summary>Operações de imagem com SkiaSharp (equivalente do ImageIO/CoreGraphics do Mac).</summary>
public static class ImageTools
{
    public static IImageDecoderExtension? Extension { get; set; }

    public static readonly SKSamplingOptions HighQuality = new(new SKCubicResampler(1f / 3, 1f / 3));
    public static readonly SKSamplingOptions Lanczos = new(SKCubicResampler.CatmullRom);

    public static bool IsHeic(string path) => Path.GetExtension(path).ToLowerInvariant() is ".heic" or ".heif";

    public static (int Width, int Height)? PixelSize(string path)
    {
        try
        {
            using var codec = SKCodec.Create(path);
            if (codec != null)
            {
                var w = codec.Info.Width;
                var h = codec.Info.Height;
                // fotos com rotação EXIF 5–8 têm largura/altura trocadas na exibição
                return SwapsAxes(codec.EncodedOrigin) ? (h, w) : (w, h);
            }
        }
        catch { }
        using var bmp = DecodeExtension(path);
        return bmp == null ? null : (bmp.Width, bmp.Height);
    }

    private static SKBitmap? DecodeExtension(string path)
    {
        try { return Extension?.Decode(path); } catch { return null; }
    }

    private static bool SwapsAxes(SKEncodedOrigin o) =>
        o is SKEncodedOrigin.LeftTop or SKEncodedOrigin.RightTop or SKEncodedOrigin.RightBottom or SKEncodedOrigin.LeftBottom;

    /// <summary>Carrega já com a orientação EXIF aplicada (RGBA 8 bits, sRGB), limitando o maior lado.</summary>
    public static SKBitmap? Load(string path, int? maxPixel = null)
    {
        SKBitmap? bmp = null;
        try
        {
            using var stream = File.OpenRead(path);
            using var codec = SKCodec.Create(stream);
            if (codec != null) bmp = DecodeCodec(codec);
        }
        catch { bmp = null; }
        bmp ??= DecodeExtension(path);
        return bmp == null ? null : Limit(bmp, maxPixel);
    }

    public static SKBitmap? FromBytes(byte[] data, int maxPixel = 8192)
    {
        try
        {
            using var sk = SKData.CreateCopy(data);
            using var codec = SKCodec.Create(sk);
            if (codec == null) return null;
            var bmp = DecodeCodec(codec);
            return bmp == null ? null : Limit(bmp, maxPixel);
        }
        catch { return null; }
    }

    private static SKBitmap? DecodeCodec(SKCodec codec)
    {
        var info = new SKImageInfo(codec.Info.Width, codec.Info.Height, SKColorType.Rgba8888, SKAlphaType.Premul, SKColorSpace.CreateSrgb());
        var bmp = new SKBitmap(info);
        var r = codec.GetPixels(info, bmp.GetPixels());
        if (r != SKCodecResult.Success && r != SKCodecResult.IncompleteInput)
        {
            bmp.Dispose();
            return null;
        }
        return ApplyOrigin(bmp, codec.EncodedOrigin);
    }

    private static SKBitmap Limit(SKBitmap bmp, int? maxPixel)
    {
        var longest = Math.Max(bmp.Width, bmp.Height);
        if (maxPixel is not int m || longest <= m || m <= 0) return bmp;
        var scale = (double)m / longest;
        var w = Math.Max(1, (int)Math.Round(bmp.Width * scale, MidpointRounding.AwayFromZero));
        var h = Math.Max(1, (int)Math.Round(bmp.Height * scale, MidpointRounding.AwayFromZero));
        var resized = Resize(bmp, w, h);
        bmp.Dispose();
        return resized;
    }

    public static SKBitmap Resize(SKBitmap src, int w, int h)
    {
        var dst = new SKBitmap(new SKImageInfo(w, h, SKColorType.Rgba8888, SKAlphaType.Premul, SKColorSpace.CreateSrgb()));
        using var canvas = new SKCanvas(dst);
        using var img = SKImage.FromBitmap(src);
        canvas.Clear(SKColors.Transparent);
        canvas.DrawImage(img, new SKRect(0, 0, w, h), HighQuality);
        return dst;
    }

    /// <summary>Aplica a orientação EXIF (como o <c>kCGImageSourceCreateThumbnailWithTransform</c>).</summary>
    public static SKBitmap ApplyOrigin(SKBitmap bmp, SKEncodedOrigin origin)
    {
        if (origin == SKEncodedOrigin.TopLeft || origin == SKEncodedOrigin.Default) return bmp;
        var swap = SwapsAxes(origin);
        var w = swap ? bmp.Height : bmp.Width;
        var h = swap ? bmp.Width : bmp.Height;
        var dst = new SKBitmap(new SKImageInfo(w, h, bmp.ColorType, bmp.AlphaType, bmp.ColorSpace));
        using (var c = new SKCanvas(dst))
        {
            float W = bmp.Width, H = bmp.Height;
            // x' = a·x + b·y + c · y' = d·x + e·y + f (mesmas transformações da tabela EXIF)
            SKMatrix m = origin switch
            {
                SKEncodedOrigin.TopRight => new SKMatrix(-1, 0, W, 0, 1, 0, 0, 0, 1),
                SKEncodedOrigin.BottomRight => new SKMatrix(-1, 0, W, 0, -1, H, 0, 0, 1),
                SKEncodedOrigin.BottomLeft => new SKMatrix(1, 0, 0, 0, -1, H, 0, 0, 1),
                SKEncodedOrigin.LeftTop => new SKMatrix(0, 1, 0, 1, 0, 0, 0, 0, 1),
                SKEncodedOrigin.RightTop => new SKMatrix(0, -1, H, 1, 0, 0, 0, 0, 1),
                SKEncodedOrigin.RightBottom => new SKMatrix(0, -1, H, -1, 0, W, 0, 0, 1),
                SKEncodedOrigin.LeftBottom => new SKMatrix(0, 1, 0, -1, 0, W, 0, 0, 1),
                _ => SKMatrix.Identity,
            };
            c.SetMatrix(m);
            c.DrawBitmap(bmp, 0, 0);
        }
        bmp.Dispose();
        return dst;
    }

    /// <summary>Remove transparência (fundo branco) — JPEG não tem canal alfa.</summary>
    public static SKBitmap Flattened(SKBitmap img)
    {
        var dst = new SKBitmap(new SKImageInfo(img.Width, img.Height, SKColorType.Rgba8888, SKAlphaType.Opaque, SKColorSpace.CreateSrgb()));
        using var c = new SKCanvas(dst);
        c.Clear(SKColors.White);
        c.DrawBitmap(img, 0, 0);
        return dst;
    }

    public static byte[]? EncodeJpeg(SKBitmap image, double quality = 0.92)
    {
        using var flat = Flattened(image);
        using var data = flat.Encode(SKEncodedImageFormat.Jpeg, (int)Math.Round(quality * 100, MidpointRounding.AwayFromZero));
        return data?.ToArray();
    }

    public static byte[]? EncodePng(SKBitmap image)
    {
        using var data = image.Encode(SKEncodedImageFormat.Png, 100);
        return data?.ToArray();
    }

    /// <summary>Versão para enviar à IA: JPEG, maior lado até 2048 px.</summary>
    public static byte[]? UploadJpeg(string path)
    {
        using var img = Load(path, 2048);
        return img == null ? null : EncodeJpeg(img, 0.9);
    }

    /// <summary>Redimensiona preenchendo o quadro (corta o excesso pelo centro).</summary>
    public static SKBitmap? AspectFill(SKBitmap img, int tw, int th)
    {
        if (tw <= 0 || th <= 0) return null;
        var dst = new SKBitmap(new SKImageInfo(tw, th, SKColorType.Rgba8888, SKAlphaType.Premul, SKColorSpace.CreateSrgb()));
        using var c = new SKCanvas(dst);
        c.Clear(SKColors.White);
        float sw = img.Width, sh = img.Height;
        var scale = Math.Max(tw / sw, th / sh);
        float dw = sw * scale, dh = sh * scale;
        var rect = SKRect.Create((tw - dw) / 2, (th - dh) / 2, dw, dh);
        using var image = SKImage.FromBitmap(img);
        c.DrawImage(image, rect, HighQuality);
        return dst;
    }

    /// <summary>Proporção suportada pelo Gemini mais próxima da imagem original.</summary>
    public static string NearestAspectRatio(int width, int height)
    {
        (string, double)[] options =
        {
            ("1:1", 1), ("4:5", 0.8), ("5:4", 1.25), ("3:4", 0.75), ("4:3", 4.0 / 3),
            ("2:3", 2.0 / 3), ("3:2", 1.5), ("9:16", 9.0 / 16), ("16:9", 16.0 / 9), ("21:9", 21.0 / 9),
        };
        var r = (double)width / Math.Max(height, 1);
        var best = options[0];
        foreach (var o in options)
            if (Math.Abs(Math.Log(o.Item2 / r)) < Math.Abs(Math.Log(best.Item2 / r))) best = o;
        return best.Item1;
    }

    /// <summary>Salva a resposta da IA como PNG na pasta do lote.</summary>
    public static void SaveGenerated(byte[] data, string path)
    {
        using var img = FromBytes(data);
        var png = img == null ? null : EncodePng(img);
        Util.AtomicFile.WriteAllBytes(path, png ?? data);
    }

    /// <summary>
    /// 1.0.0-beta.8: copia o original como PNG (com a rotação EXIF aplicada) para servir de "limpo"
    /// quando não há nada a remover. Devolve false se não conseguir ler ou gravar.
    /// </summary>
    public static bool CopyAsPng(string src, string dst)
    {
        using var img = Load(src);
        var png = img == null ? null : EncodePng(img);
        if (png == null) return false;
        try { Util.AtomicFile.WriteAllBytes(dst, png); return true; } catch { return false; }
    }

    /// <summary>Confere se os bytes são uma imagem que o app consegue abrir.</summary>
    public static bool IsValidImage(byte[] data)
    {
        try
        {
            using var sk = SKData.CreateCopy(data);
            using var codec = SKCodec.Create(sk);
            return codec != null && codec.Info.Width > 0;
        }
        catch { return false; }
    }

    // MARK: miniaturas para as telas (o App converte para a imagem da tela)

    private static readonly ConcurrentDictionary<string, byte[]> ThumbCache = new();

    /// <summary>Miniatura em PNG (cache por caminho e tamanho).</summary>
    public static byte[]? ThumbnailPng(string path, int maxPixel = 480)
    {
        var key = $"{path}#{maxPixel}";
        if (ThumbCache.TryGetValue(key, out var hit)) return hit;
        using var img = Load(path, maxPixel);
        var png = img == null ? null : EncodePng(img);
        if (png != null)
        {
            if (ThumbCache.Count > 600) ThumbCache.Clear();
            ThumbCache[key] = png;
        }
        return png;
    }

    public static void InvalidateThumbnails() => ThumbCache.Clear();
}
