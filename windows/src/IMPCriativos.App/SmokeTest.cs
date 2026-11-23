using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using IMPCriativos.App.UI;
using IMPCriativos.App.Views;
using IMPCriativos.Core.Models;
using IMPCriativos.Core.Providers;
using IMPCriativos.Core.Story;
using IMPCriativos.Core.Storage;
using SkiaSharp;

namespace IMPCriativos.App;

/// <summary>
/// Teste de fumaça do CI (<c>"IMP Criativos.exe" --smoke-test pasta</c>): abre cada tela com dados de exemplo,
/// salva uma captura PNG de cada uma, roda o Otimizador em 3 imagens geradas e confere 1080×1920, sem EXIF/GPS/XMP
/// e o mesmo arquivo para a mesma semente. Usa uma pasta de dados própria (não mexe nos dados de ninguém).
/// </summary>
public static class SmokeTest
{
    private static readonly List<string> Report = new();
    private static int _failures;

    public static int Run(string folder)
    {
        folder = Path.GetFullPath(folder);
        Directory.CreateDirectory(folder);
        var data = Path.Combine(folder, "dados");
        if (Directory.Exists(data)) Directory.Delete(data, true);
        Paths.OverrideRoot(data);
        Environment.SetEnvironmentVariable("IMP_CRIATIVOS_DATA", data);

        var code = 1;
        var app = new App { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        app.Startup += async (_, _) =>
        {
            try
            {
                app.ThemeMode = ThemeMode.Dark;
                Theme.Apply(app);
                App.ConfigureServices();
                App.SkipQuitConfirmation = true;
                await Steps(folder);
                code = _failures == 0 ? 0 : 1;
            }
            catch (Exception e)
            {
                Fail($"exceção: {e}");
                code = 1;
            }
            File.WriteAllLines(Path.Combine(folder, "resultado.txt"), Report);
            foreach (var line in Report) Console.WriteLine(line);
            Environment.Exit(code);
        };
        app.Run();
        return code;
    }

    private static void Ok(string text) => Report.Add("OK    " + text);

    private static void Fail(string text)
    {
        _failures++;
        Report.Add("FALHA " + text);
    }

    private static void Check(bool condition, string text)
    {
        if (condition) Ok(text); else Fail(text);
    }

    private static async Task Pump(int ms = 300)
    {
        await Dispatcher.Yield(DispatcherPriority.ApplicationIdle);
        await Task.Delay(ms);
        await Dispatcher.Yield(DispatcherPriority.ApplicationIdle);
    }

    private static async Task WaitFor(Func<bool> condition, int timeoutMs = 30000)
    {
        var until = DateTime.UtcNow.AddMilliseconds(timeoutMs);
        while (!condition() && DateTime.UtcNow < until) await Pump(150);
    }

    private static void Capture(Window w, string path)
    {
        w.UpdateLayout();
        var dpi = VisualTreeHelper.GetDpi(w);
        var element = (FrameworkElement)w.Content;
        var width = (int)Math.Ceiling(element.ActualWidth * dpi.DpiScaleX);
        var height = (int)Math.Ceiling(element.ActualHeight * dpi.DpiScaleY);
        var rtb = new RenderTargetBitmap(Math.Max(width, 1), Math.Max(height, 1), 96 * dpi.DpiScaleX, 96 * dpi.DpiScaleY, PixelFormats.Pbgra32);
        var visual = new DrawingVisual();
        using (var dc = visual.RenderOpen())
        {
            dc.DrawRectangle(Brand.Background, null, new Rect(0, 0, element.ActualWidth, element.ActualHeight));
            dc.DrawRectangle(new VisualBrush(element), null, new Rect(0, 0, element.ActualWidth, element.ActualHeight));
        }
        rtb.Render(visual);
        var enc = new PngBitmapEncoder();
        enc.Frames.Add(BitmapFrame.Create(rtb));
        using (var fs = File.Create(path)) enc.Save(fs);

        // prévia pequena em JPEG (o smoke.ps1 imprime no log, para conferir sem baixar o artefato)
        var previews = Path.Combine(Path.GetDirectoryName(path)!, "..", "previas");
        Directory.CreateDirectory(previews);
        var small = new TransformedBitmap(rtb, new ScaleTransform(0.6 / dpi.DpiScaleX, 0.6 / dpi.DpiScaleY));
        var jpg = new JpegBitmapEncoder { QualityLevel = 72 };
        jpg.Frames.Add(BitmapFrame.Create(small));
        using var js = File.Create(Path.Combine(previews, Path.GetFileNameWithoutExtension(path) + ".jpg"));
        jpg.Save(js);
    }

    /// <summary>Imagem de teste: degradê, faixas e blocos de "texto" de alto contraste.</summary>
    private static string MakeImage(string folder, int index, int w, int h)
    {
        using var bmp = new SKBitmap(w, h);
        using var canvas = new SKCanvas(bmp);
        var hue = index * 110f;
        using (var shader = SKShader.CreateLinearGradient(new SKPoint(0, 0), new SKPoint(w, h),
                   new[] { SKColor.FromHsl(hue, 70, 40), SKColor.FromHsl(hue + 60, 80, 60) }, SKShaderTileMode.Clamp))
        using (var p = new SKPaint { Shader = shader })
            canvas.DrawRect(0, 0, w, h, p);
        using var white = new SKPaint { Color = SKColors.White, IsAntialias = true };
        using var black = new SKPaint { Color = SKColors.Black, IsAntialias = true };
        for (var i = 0; i < 6; i++)
        {
            canvas.DrawRoundRect(new SKRect(w * 0.08f, h * (0.15f + i * 0.1f), w * (0.5f + i * 0.06f), h * (0.2f + i * 0.1f)), 8, 8, i % 2 == 0 ? white : black);
        }
        canvas.DrawCircle(w * 0.75f, h * 0.8f, Math.Min(w, h) * 0.12f, white);
        var path = Path.Combine(folder, $"criativo_{index + 1}.{(index == 1 ? "png" : "jpg")}");
        using var image = SKImage.FromBitmap(bmp);
        using var encoded = index == 1 ? image.Encode(SKEncodedImageFormat.Png, 100) : image.Encode(SKEncodedImageFormat.Jpeg, 92);
        File.WriteAllBytes(path, encoded.ToArray());
        return path;
    }

    private static async Task Steps(string folder)
    {
        var shots = Path.Combine(folder, "capturas");
        Directory.CreateDirectory(shots);
        var inputs = Path.Combine(folder, "entrada");
        Directory.CreateDirectory(inputs);
        var images = new[] { MakeImage(inputs, 0, 1080, 1350), MakeImage(inputs, 1, 1200, 1200), MakeImage(inputs, 2, 1920, 1080) };
        Ok($"3 imagens de teste geradas em {inputs}");

        // dados de exemplo: um cliente e um lote com a limpeza pronta
        var model = AppModel.Shared;
        var client = model.Clients.Clients.FirstOrDefault() ?? ClientProfile.Example;
        if (model.Clients.Clients.Count == 0) model.Clients.Save(client);
        var job = model.Jobs.CreateJob("Lote de exemplo", client, inputs, images, 2, ProviderKind.Gemini, ProviderKind.Gemini, ProviderKind.Gemini,
            OutputSizeMode.Original, OutputFormat.Png, verifyText: true);
        model.Jobs.Update(job.Id, j =>
        {
            j.State = JobState.Review;
            foreach (var item in j.Items)
            {
                item.CleanStatus = StepStatus.Done;
                item.CleanedFile = item.OriginalFile;
                item.CleanReview = ReviewStatus.Approved;
                foreach (var v in item.Variations) v.Status = StepStatus.Pending;
            }
            if (j.Items.Count > 0 && j.Items[0].Variations.Count > 0)
            {
                var v = j.Items[0].Variations[0];
                v.Status = StepStatus.Failed;
                v.Error = "A IA está ocupada (503). Tente de novo em alguns minutos.";
                v.ErrorKind = AIErrorKind.Temporary;
            }
        });
        AppLog.Info(LogCategory.Sistema, "Teste de fumaça iniciado.");
        AppLog.Warning(LogCategory.Lote, "Exemplo de alerta.", jobID: job.Id, jobName: job.Name);
        AppLog.Error(LogCategory.Lote, "Exemplo de erro.", details: "detalhes técnicos de exemplo", jobID: job.Id, jobName: job.Name);
        Ok("cliente, lote e histórico de exemplo criados");

        // Otimizador: 3 imagens, pasta de saída e preview
        var batch = StoryBatch.Shared;
        batch.Edit(o =>
        {
            o.Intensity = StoryIntensity.Normal;
            o.SetLinesEnabled(true);
            o.SelectTexturePreset(StoryTexturePreset.Balanced);
        });
        var outFolder = Path.Combine(folder, "stories");
        Directory.CreateDirectory(outFolder);
        batch.SetOutputFolder(outFolder);
        batch.Add(images);
        Check(batch.Items.Count == 3, $"Otimizador aceitou as 3 imagens ({batch.Items.Count})");

        var window = new MainWindow { Width = 1360, Height = 900, WindowStartupLocation = WindowStartupLocation.Manual, Left = 0, Top = 0 };
        window.Show();
        await Pump(800);

        var screens = new (string Name, SidebarItem Item)[]
        {
            ("01-inicio", new SidebarItem.Home()),
            ("02-novo-lote", new SidebarItem.NewJob()),
            ("03-limpar-logo", new SidebarItem.CleanOnly()),
            ("04-otimizador-stories", new SidebarItem.StoryOptimizer()),
            ("05-lote", new SidebarItem.JobItem(job.Id)),
            ("06-clientes", new SidebarItem.Clients()),
            ("07-historico", new SidebarItem.Logs()),
            ("08-configuracoes", new SidebarItem.Settings()),
        };
        foreach (var (name, item) in screens)
        {
            try
            {
                model.Selection = item;
                await Pump(900);
                if (item is SidebarItem.StoryOptimizer)
                {
                    await WaitFor(() => !batch.PreviewLoading && batch.PreviewAfter != null);
                    await Pump(600);
                }
                Capture(window, Path.Combine(shots, name + ".png"));
                Ok($"tela {name} aberta e capturada");
            }
            catch (Exception e)
            {
                Fail($"tela {name}: {e.Message}");
            }
        }

        // inspetor Antes / Depois (não modal, para capturar)
        try
        {
            var inspector = new StoryInspectorWindow { Owner = window, Left = 0, Top = 0, WindowStartupLocation = WindowStartupLocation.Manual };
            inspector.Show();
            await WaitFor(() => !batch.PreviewLoading && batch.InspectOriginal != null && batch.PreviewAfter != null);
            await Pump(700);
            Capture(inspector, Path.Combine(shots, "09-inspecionar-antes-depois.png"));
            inspector.Close();
            Ok("inspetor Antes / Depois aberto e capturado");
        }
        catch (Exception e)
        {
            Fail($"inspetor: {e.Message}");
        }

        // processa o lote do Otimizador
        await batch.Start();
        await WaitFor(() => !batch.Running, 120000);
        Check(batch.DoneCount == 3, $"Otimizador processou as 3 imagens ({batch.DoneCount} prontas, {batch.FailedCount} com erro)");
        model.Selection = new SidebarItem.StoryOptimizer();
        await Pump(900);
        Capture(window, Path.Combine(shots, "10-otimizador-pronto.png"));

        var outputs = batch.Items.Select(i => i.Output).Where(o => o != null).Cast<string>().ToList();
        foreach (var output in outputs)
        {
            var bytes = File.ReadAllBytes(output);
            using var decoded = SKBitmap.Decode(bytes);
            Check(decoded != null && decoded.Width == 1080 && decoded.Height == 1920, $"{Path.GetFileName(output)}: 1080×1920");
            var segments = StoryOptimizer.JpegSegments(bytes).Select(s => s.Marker).ToList();
            Check(!segments.Contains("E1"), $"{Path.GetFileName(output)}: sem EXIF/GPS/XMP (APP1)");
            Check(!segments.Contains("ED") && !segments.Contains("FE"), $"{Path.GetFileName(output)}: sem IPTC nem comentário");
            Check(segments.Contains("E2"), $"{Path.GetFileName(output)}: com perfil sRGB (APP2)");
        }

        // mesma semente → mesmo arquivo
        var options = batch.Options;
        var p = StoryParams.Sample(options, 424242UL);
        var a = Path.Combine(folder, "mesma-semente-a.jpg");
        var b = Path.Combine(folder, "mesma-semente-b.jpg");
        StoryOptimizer.Process(images[0], options, p, a);
        StoryOptimizer.Process(images[0], options, StoryParams.Sample(options, 424242UL), b);
        Check(File.ReadAllBytes(a).AsSpan().SequenceEqual(File.ReadAllBytes(b)), "mesma semente gera o mesmo arquivo");

        // .zip do lote
        if (batch.LastRunFolder != null)
        {
            var zipPath = Path.Combine(folder, "stories.zip");
            var error = await batch.MakeZip(zipPath);
            Check(error == null && File.Exists(zipPath) && new FileInfo(zipPath).Length > 1000, "Baixar Tudo (.ZIP) gerou o arquivo" + (error != null ? $": {error}" : ""));
        }

        window.Hide();
    }
}
