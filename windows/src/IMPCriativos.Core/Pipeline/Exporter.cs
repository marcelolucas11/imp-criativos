using System.Globalization;
using IMPCriativos.Core.Imaging;
using IMPCriativos.Core.Models;
using IMPCriativos.Core.Storage;

namespace IMPCriativos.Core.Pipeline;

/// <summary>
/// Exporta os aprovados no tamanho e formato escolhidos, com nomenclatura padrão:
///   &lt;pasta&gt;\&lt;cliente&gt;\&lt;lote&gt;_&lt;data&gt;\&lt;cliente&gt;_&lt;criativo&gt;_v0.jpg   (limpo)
///   &lt;pasta&gt;\&lt;cliente&gt;\&lt;lote&gt;_&lt;data&gt;\&lt;cliente&gt;_&lt;criativo&gt;_v1.jpg   (variações)
///   &lt;pasta&gt;\&lt;cliente&gt;\&lt;lote&gt;_&lt;data&gt;\&lt;cliente&gt;_&lt;criativo&gt;_limpo.jpg (módulo Limpar logo)
/// </summary>
public static class Exporter
{
    public sealed record Result(string Folder, int Count, List<string> Failures);

    /// <summary>Nomes dos arquivos que sairiam (origem relativa ao lote → nome final, tamanho).</summary>
    public static List<(string Src, string Name, int W, int H)> Plan(Job job)
    {
        var clientSlug = Paths.Slug(job.Client.Name) is { Length: > 0 } c ? c : "cliente";
        var ext = job.Format.Raw();
        var tasks = new List<(string, string, int, int)>();
        foreach (var item in job.Items)
        {
            var (w, h) = job.SizeMode.IsOriginal ? (item.PixelWidth, item.PixelHeight) : (job.SizeMode.Width, job.SizeMode.Height);
            var @base = $"{clientSlug}_{Paths.Slug(item.BaseName)}";
            if (item.CleanReview == ReviewStatus.Approved && item.CleanedFile is string f)
                // 1.0.0-beta.20: no módulo "Limpar logo" o arquivo sai como _limpo
                tasks.Add((f, $"{@base}_{(job.IsCleanOnly ? "limpo" : "v0")}.{ext}", w, h));
            foreach (var v in item.Variations.Where(v => v.Review == ReviewStatus.Approved))
            {
                if (v.File is not string vf) continue;
                // 1.0.0-beta.19: no teste de eixos, o nome leva o eixo (ex.: _v27_e27-titulo-3d) para comparar depois
                var axis = job.IsAxisTest
                    ? "_" + (v.AxisNumber is int n ? $"e{n:00}-" : "") + Paths.Slug(v.AxisName)
                    : "";
                tasks.Add((vf, $"{@base}_v{v.Index}{axis}.{ext}", w, h));
            }
        }
        return tasks;
    }

    public static async Task<Result> Export(Job job, string jobFolder, string destinationBase)
    {
        var stamp = DateTime.Now.ToString("yyyy-MM-dd_HHmm", CultureInfo.InvariantCulture);
        var clientSlug = Paths.Slug(job.Client.Name) is { Length: > 0 } c ? c : "cliente";
        var jobSlug = Paths.Slug(job.Name) is { Length: > 0 } j ? j : "lote";
        var dest = Path.Combine(destinationBase, clientSlug, $"{jobSlug}_{stamp}");
        Directory.CreateDirectory(dest);
        var png = job.Format == OutputFormat.Png;
        var work = Plan(job);

        var (ok, failed) = await Task.Run(() =>
        {
            var count = 0;
            var fails = new List<string>();
            foreach (var t in work)
            {
                try
                {
                    using var img = ImageTools.Load(Path.Combine(jobFolder, t.Src.Replace('/', Path.DirectorySeparatorChar)));
                    if (img == null) { fails.Add(t.Name); continue; }
                    using var src = png ? img.Copy() : ImageTools.Flattened(img);
                    using var sized = ImageTools.AspectFill(src, t.W, t.H);
                    var data = sized == null ? null : png ? ImageTools.EncodePng(sized) : ImageTools.EncodeJpeg(sized, 0.92);
                    if (data == null) { fails.Add(t.Name); continue; }
                    Util.AtomicFile.WriteAllBytes(Path.Combine(dest, t.Name), data);
                    count++;
                }
                catch
                {
                    fails.Add(t.Name);
                }
            }
            return (count, fails);
        });
        return new Result(dest, ok, failed);
    }
}

public static class CostEstimator
{
    public sealed record Estimate(int ImageCalls, int AnalysisCalls, double Usd);

    public static Estimate Calculate(int items, int variations, ProviderKind clean, ProviderKind variation, bool verifyText,
        AppSettings settings, bool cleaning = true)
    {
        // 1.0.0-beta.20: com a limpeza desligada no lote, a imagem enviada é usada como está (sem custo de limpeza)
        var cleanCost = cleaning ? items * settings.ImagePrice(clean) : 0;
        var varCost = items * variations * settings.ImagePrice(variation);
        var analysis = items + (verifyText ? items * variations : 0);
        var planning = settings.PlanningEnabled ? items * settings.PricePlanning : 0;
        var total = cleanCost + varCost + analysis * settings.PriceAnalysis + planning;
        return new Estimate(items * ((cleaning ? 1 : 0) + variations), analysis, total);
    }

    /// <summary>
    /// 1.0.0-beta.19: tempo estimado em minutos (faixa). Usa o tempo médio por imagem medido nesta sessão,
    /// ou 45 s se ainda não houver medida. O mínimo considera o modo rápido no teto; o máximo, a velocidade
    /// original com a IA 50% mais lenta.
    /// </summary>
    public static (int Low, int High) Minutes(int items, int variations, AppSettings settings, double? secondsPerImage, bool cleaning = true)
    {
        if (items <= 0) return (0, 0);
        var lat = Math.Max(10, secondsPerImage ?? 45);
        double @base = Math.Max(1, settings.MaxImageRequests);
        var top = settings.FastMode ? Math.Max(settings.MaxImageRequests, settings.FastImageCeiling) : @base;
        var prelude = (settings.PlanningEnabled ? 40 : 0) + (cleaning ? lat : 0) + 15;
        var rounds = Math.Ceiling((double)items / Math.Max(1, settings.MaxConcurrent));
        double images = items * variations;
        // 1.0.0-beta.20: só limpeza — o tempo é o das rodadas de limpeza (os criativos rodam em paralelo)
        var low = variations == 0 ? rounds * prelude * 0.7 : prelude + images * lat / top;
        var high = rounds * prelude + images * lat * 1.5 / @base;
        var lo = Math.Max(1, (int)Math.Round(low / 60, MidpointRounding.AwayFromZero));
        return (lo, Math.Max(lo, (int)Math.Ceiling(high / 60)));
    }

    public static string MinutesLabel((int Low, int High) r)
    {
        static string F(int m) => m < 60 ? $"{m} min" : $"{m / 60}h{m % 60:00}";
        return r.Low == r.High ? $"~{F(r.Low)}" : $"~{F(r.Low)} a {F(r.High)}";
    }
}

public static class MoneyExt
{
    /// <summary>US$ 0.00 (como o <c>.usd</c> do Mac, com ponto).</summary>
    public static string Usd(this double v) => "US$ " + v.ToString("0.00", CultureInfo.InvariantCulture);
}
