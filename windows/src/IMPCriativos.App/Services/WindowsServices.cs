using System.Diagnostics;
using System.IO.Pipes;
using System.Runtime.InteropServices.WindowsRuntime;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using IMPCriativos.Core.Imaging;
using IMPCriativos.Core.Pipeline;
using IMPCriativos.Core.Storage;
using Microsoft.Win32;
using SkiaSharp;

namespace IMPCriativos.App.Services;

/// <summary>
/// Leitura de texto local pelo Windows (<c>Windows.Media.Ocr</c>), no lugar do Vision do Mac.
/// Ordem de idioma: português (Brasil), depois qualquer idioma instalado. Sem idioma com OCR, a conferência local é pulada.
/// </summary>
public sealed class WindowsOcr : ILocalTextReader
{
    private readonly Windows.Media.Ocr.OcrEngine? _engine;

    public WindowsOcr()
    {
        try
        {
            _engine = Windows.Media.Ocr.OcrEngine.TryCreateFromLanguage(new Windows.Globalization.Language("pt-BR"))
                      ?? Windows.Media.Ocr.OcrEngine.TryCreateFromUserProfileLanguages();
            if (_engine == null)
            {
                foreach (var lang in Windows.Media.Ocr.OcrEngine.AvailableRecognizerLanguages)
                {
                    _engine = Windows.Media.Ocr.OcrEngine.TryCreateFromLanguage(lang);
                    if (_engine != null) break;
                }
            }
        }
        catch { _engine = null; }
    }

    public string? Description => _engine == null ? null : _engine.RecognizerLanguage.DisplayName;

    public string? Text(string imagePath)
    {
        if (_engine == null) return null;
        using var img = ImageTools.Load(imagePath, (int)Windows.Media.Ocr.OcrEngine.MaxImageDimension);
        if (img == null) return null;
        // o OCR do Windows recebe BGRA 8 bits
        using var bgra = new SKBitmap(new SKImageInfo(img.Width, img.Height, SKColorType.Bgra8888, SKAlphaType.Premul));
        using (var c = new SKCanvas(bgra)) { c.Clear(SKColors.White); c.DrawBitmap(img, 0, 0); }
        var sb = new Windows.Graphics.Imaging.SoftwareBitmap(Windows.Graphics.Imaging.BitmapPixelFormat.Bgra8,
            bgra.Width, bgra.Height, Windows.Graphics.Imaging.BitmapAlphaMode.Premultiplied);
        sb.CopyFromBuffer(bgra.Bytes.AsBuffer());
        var result = _engine.RecognizeAsync(sb).AsTask().GetAwaiter().GetResult();
        return string.Join("\n", result.Lines.Select(l => l.Text));
    }
}

/// <summary>HEIC/HEIF pelo WIC do Windows (precisa das Extensões de Imagem HEIF da Microsoft Store).</summary>
public sealed class WicDecoder : IImageDecoderExtension
{
    public const string HeicMessage = "Instale as Extensões de Imagem HEIF da Microsoft Store para abrir HEIC.";

    public SKBitmap? Decode(string path)
    {
        try
        {
            using var fs = File.OpenRead(path);
            var dec = BitmapDecoder.Create(fs, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad);
            BitmapSource frame = dec.Frames[0];
            // aplica a orientação do EXIF, quando houver
            if (frame.Metadata is BitmapMetadata md)
            {
                try
                {
                    if (md.GetQuery("System.Photo.Orientation") is ushort o && o is >= 2 and <= 8)
                    {
                        var t = new TransformGroup();
                        switch (o)
                        {
                            case 2: t.Children.Add(new ScaleTransform(-1, 1)); break;
                            case 3: t.Children.Add(new RotateTransform(180)); break;
                            case 4: t.Children.Add(new ScaleTransform(1, -1)); break;
                            case 5: t.Children.Add(new ScaleTransform(-1, 1)); t.Children.Add(new RotateTransform(270)); break;
                            case 6: t.Children.Add(new RotateTransform(90)); break;
                            case 7: t.Children.Add(new ScaleTransform(-1, 1)); t.Children.Add(new RotateTransform(90)); break;
                            case 8: t.Children.Add(new RotateTransform(270)); break;
                        }
                        frame = new TransformedBitmap(frame, t);
                    }
                }
                catch { }
            }
            var conv = new FormatConvertedBitmap(frame, PixelFormats.Pbgra32, null, 0);
            var w = conv.PixelWidth;
            var h = conv.PixelHeight;
            var px = new byte[w * h * 4];
            conv.CopyPixels(px, w * 4, 0);
            var bmp = new SKBitmap(new SKImageInfo(w, h, SKColorType.Bgra8888, SKAlphaType.Premul, SKColorSpace.CreateSrgb()));
            System.Runtime.InteropServices.Marshal.Copy(px, 0, bmp.GetPixels(), px.Length);
            var rgba = new SKBitmap(new SKImageInfo(w, h, SKColorType.Rgba8888, SKAlphaType.Premul, SKColorSpace.CreateSrgb()));
            using (var c = new SKCanvas(rgba)) c.DrawBitmap(bmp, 0, 0);
            bmp.Dispose();
            return rgba;
        }
        catch { return null; }
    }

    public string? UnsupportedMessage(string path) => ImageTools.IsHeic(path) ? HeicMessage : null;
}

/// <summary>"Iniciar com o Windows": HKCU\Software\Microsoft\Windows\CurrentVersion\Run, com o argumento --background.</summary>
public static class StartupItem
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string Name = "IMP Criativos";

    public static bool IsEnabled
    {
        get
        {
            try
            {
                using var k = Registry.CurrentUser.OpenSubKey(RunKey);
                return k?.GetValue(Name) is string;
            }
            catch { return false; }
        }
    }

    public static void Set(bool enabled)
    {
        using var k = Registry.CurrentUser.OpenSubKey(RunKey, writable: true) ?? Registry.CurrentUser.CreateSubKey(RunKey);
        if (enabled) k.SetValue(Name, $"\"{Environment.ProcessPath}\" --background");
        else k.DeleteValue(Name, throwOnMissingValue: false);
    }
}

/// <summary>Notificações: toast do Windows; se falhar, balão do ícone da bandeja.</summary>
/// <summary>
/// Notificação de "lote terminou": balão do ícone da bandeja, que o Windows 10/11 mostra como notificação
/// (Central de Ações) com o nome e o ícone do app.
/// </summary>
public static class Toast
{
    public static Action<string, string>? Handler { get; set; }

    public static void Post(string title, string body)
    {
        try { Handler?.Invoke(title, body); } catch { }
    }
}

/// <summary>Seletores de pasta e arquivo do Windows.</summary>
public static class Pickers
{
    public static string? Folder(string title, string? start = null)
    {
        var d = new OpenFolderDialog { Title = title, Multiselect = false };
        if (start != null && Directory.Exists(start)) d.InitialDirectory = start;
        return d.ShowDialog() == true ? d.FolderName : null;
    }

    public static string? OpenFile(string title, string filter)
    {
        var d = new OpenFileDialog { Title = title, Filter = filter, Multiselect = false };
        return d.ShowDialog() == true ? d.FileName : null;
    }

    /// <summary>1.0.0-beta.21: várias imagens de uma vez — Otimizador em Lote.</summary>
    public static string[] Images(string title)
    {
        var d = new OpenFileDialog
        {
            Title = title,
            Multiselect = true,
            Filter = "Imagens (JPG, PNG, WebP, HEIC)|*.jpg;*.jpeg;*.png;*.webp;*.heic;*.heif|Todos os arquivos|*.*",
        };
        return d.ShowDialog() == true ? d.FileNames : Array.Empty<string>();
    }

    public static string? SaveFile(string title, string name, string filter)
    {
        var d = new SaveFileDialog { Title = title, FileName = name, Filter = filter };
        return d.ShowDialog() == true ? d.FileName : null;
    }
}

public static class Shell
{
    public static void Open(string path)
    {
        try { Process.Start(new ProcessStartInfo { FileName = path, UseShellExecute = true }); } catch { }
    }

    /// <summary>Mostra o arquivo selecionado no Explorador de Arquivos.</summary>
    public static void Reveal(string path)
    {
        try
        {
            if (File.Exists(path)) Process.Start("explorer.exe", $"/select,\"{path}\"");
            else if (Directory.Exists(path)) Process.Start("explorer.exe", $"\"{path}\"");
        }
        catch { }
    }

    public static void Copy(string text)
    {
        try { Clipboard.SetText(text); } catch { }
    }
}

/// <summary>Instância única (Mutex nomeado). A segunda abertura só pede para a primeira mostrar a janela.</summary>
public sealed class SingleInstance : IDisposable
{
    private const string MutexName = @"Local\IMPCriativos.Windows.Instancia";
    private const string PipeName = "IMPCriativos.Windows.Mostrar";
    private readonly Mutex _mutex;
    private readonly CancellationTokenSource _cts = new();
    public bool IsFirst { get; }

    public SingleInstance()
    {
        _mutex = new Mutex(true, MutexName, out var created);
        IsFirst = created;
    }

    /// <summary>Fica ouvindo pedidos de "mostrar a janela" das próximas aberturas.</summary>
    public void Listen(Action onShow)
    {
        Task.Run(async () =>
        {
            while (!_cts.IsCancellationRequested)
            {
                try
                {
                    await using var server = new NamedPipeServerStream(PipeName, PipeDirection.In, 1, PipeTransmissionMode.Byte, PipeOptions.Asynchronous);
                    await server.WaitForConnectionAsync(_cts.Token);
                    onShow();
                }
                catch (OperationCanceledException) { break; }
                catch { await Task.Delay(500); }
            }
        });
    }

    public static void SignalFirst()
    {
        try
        {
            using var client = new NamedPipeClientStream(".", PipeName, PipeDirection.Out);
            client.Connect(1500);
        }
        catch { }
    }

    public void Dispose()
    {
        _cts.Cancel();
        try { if (IsFirst) _mutex.ReleaseMutex(); } catch { }
        _mutex.Dispose();
    }
}

/// <summary>Sinais de risco do computador para o Modo rápido com segurança (economia de bateria ligada).</summary>
public static class PowerRisk
{
    public static string? Check()
    {
        try
        {
            if (System.Windows.Forms.SystemInformation.PowerStatus.BatteryChargeStatus.HasFlag(System.Windows.Forms.BatteryChargeStatus.Low) &&
                System.Windows.Forms.SystemInformation.PowerStatus.PowerLineStatus == System.Windows.Forms.PowerLineStatus.Offline)
                return "bateria fraca e fora da tomada";
        }
        catch { }
        return null;
    }
}
