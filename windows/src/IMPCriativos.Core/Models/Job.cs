using System.Text.Json;
using System.Text.Json.Serialization;
using IMPCriativos.Core.Pipeline;
using IMPCriativos.Core.Util;

namespace IMPCriativos.Core.Models;

public enum ProviderKind { Gemini, Openai }

public static class ProviderKindExt
{
    public static readonly ProviderKind[] All = { ProviderKind.Gemini, ProviderKind.Openai };

    public static string Raw(this ProviderKind p) => p == ProviderKind.Gemini ? "gemini" : "openai";

    public static string Label(this ProviderKind p) => p == ProviderKind.Gemini ? "Gemini" : "GPT (OpenAI)";

    /// <summary>Nome da plataforma no menu de modelos.</summary>
    public static string PlatformLabel(this ProviderKind p) => p == ProviderKind.Gemini ? "Google (Gemini)" : "OpenAI (GPT)";

    public static ProviderKind Other(this ProviderKind p) => p == ProviderKind.Gemini ? ProviderKind.Openai : ProviderKind.Gemini;

    public static ProviderKind? Parse(string? raw) => raw switch
    {
        "gemini" => ProviderKind.Gemini,
        "openai" => ProviderKind.Openai,
        _ => null,
    };
}

public enum StepStatus { Pending, Running, Done, Failed }

public enum ReviewStatus { Pending, Approved, Discarded }

public enum OutputFormat { Jpg, Png }

public static class OutputFormatExt
{
    public static string Raw(this OutputFormat f) => f == OutputFormat.Png ? "png" : "jpg";
    public static string Label(this OutputFormat f) => f.Raw().ToUpperInvariant();
}

/// <summary>
/// Tamanho de saída. No JSON segue o formato do Swift para enum com valor associado:
/// <c>{"original":{}}</c> ou <c>{"fixed":{"width":1080,"height":1350}}</c>.
/// </summary>
[JsonConverter(typeof(OutputSizeModeConverter))]
public sealed record OutputSizeMode
{
    public bool IsOriginal { get; init; }
    public int Width { get; init; }
    public int Height { get; init; }

    public static readonly OutputSizeMode Original = new() { IsOriginal = true };

    public static OutputSizeMode Fixed(int width, int height) => new() { Width = width, Height = height };

    public string Label => IsOriginal ? "Manter original" : $"{Width}×{Height}";
}

public sealed class OutputSizeModeConverter : JsonConverter<OutputSizeMode>
{
    public override OutputSizeMode Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        using var doc = JsonDocument.ParseValue(ref reader);
        var root = doc.RootElement;
        if (root.ValueKind == JsonValueKind.Object)
        {
            if (root.TryGetProperty("fixed", out var f) && f.ValueKind == JsonValueKind.Object)
            {
                int w = 1080, h = 1350;
                if (f.TryGetProperty("width", out var we) && we.TryGetInt32(out var wv)) w = wv;
                if (f.TryGetProperty("height", out var he) && he.TryGetInt32(out var hv)) h = hv;
                return OutputSizeMode.Fixed(w, h);
            }
            if (root.TryGetProperty("original", out _)) return OutputSizeMode.Original;
        }
        return OutputSizeMode.Original;
    }

    public override void Write(Utf8JsonWriter writer, OutputSizeMode value, JsonSerializerOptions options)
    {
        writer.WriteStartObject();
        if (value.IsOriginal)
        {
            writer.WritePropertyName("original");
            writer.WriteStartObject();
            writer.WriteEndObject();
        }
        else
        {
            writer.WritePropertyName("fixed");
            writer.WriteStartObject();
            writer.WriteNumber("width", value.Width);
            writer.WriteNumber("height", value.Height);
            writer.WriteEndObject();
        }
        writer.WriteEndObject();
    }
}

/// <summary>Tamanhos padrão de criativo vertical do Meta Ads.</summary>
public enum MetaFormat { Feed, Story }

public static class MetaFormatExt
{
    public static readonly MetaFormat[] All = { MetaFormat.Feed, MetaFormat.Story };
    public static int Width(this MetaFormat f) => 1080;
    public static int Height(this MetaFormat f) => f == MetaFormat.Feed ? 1350 : 1920;
    public static string AspectRatio(this MetaFormat f) => f == MetaFormat.Feed ? "4:5" : "9:16";
    public static string Label(this MetaFormat f) =>
        f == MetaFormat.Feed ? "Feed 4:5 — 1080×1350" : "Stories e Reels 9:16 — 1080×1920";
    public static OutputSizeMode SizeMode(this MetaFormat f) => OutputSizeMode.Fixed(f.Width(), f.Height());
}

public enum JobState { Queued, Running, Paused, Review, Exported, Cancelled }

public static class JobStateExt
{
    public static string Label(this JobState s) => s switch
    {
        JobState.Queued => "Na fila",
        JobState.Running => "Processando",
        JobState.Paused => "Pausado",
        JobState.Review => "Aguardando revisão",
        JobState.Exported => "Exportado",
        JobState.Cancelled => "Cancelado",
        _ => "",
    };
}

public sealed class Variation
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public int Index { get; set; }
    public string AxisName { get; set; } = "";
    public string AxisInstruction { get; set; } = "";
    public string? File { get; set; }
    public StepStatus Status { get; set; } = StepStatus.Pending;
    public string? Error { get; set; }
    public string? TextWarning { get; set; }
    public ReviewStatus Review { get; set; } = ReviewStatus.Pending;
    public string? RedoNote { get; set; }
    public int Attempts { get; set; }

    // 1.0.0-beta.4 (opcionais para abrir lotes antigos)
    public AIErrorKind? ErrorKind { get; set; }
    public string? ErrorDetails { get; set; }
    /// <summary>Aviso temporário enquanto espera nova tentativa ("Gemini ocupado · tentativa 2/6").</summary>
    public string? RetryNote { get; set; }
    public DateTime? RetryAt { get; set; }
    /// <summary>IA que realmente gerou (difere da do lote quando houve troca automática).</summary>
    public ProviderKind? ProviderUsed { get; set; }
    /// <summary>Forçar uma IA nesta variação (botão "Refazer com…").</summary>
    public ProviderKind? ProviderOverride { get; set; }

    // 1.0.0-beta.7
    /// <summary>Quantas vezes o app refez sozinho porque apareceu termo proibido.</summary>
    public int? AutoRedos { get; set; }

    // 1.0.0-beta.19
    /// <summary>Número do eixo no catálogo do app (null = eixo escrito pelo usuário).</summary>
    public int? AxisNumber { get; set; }

    /// <summary>"27. Título 3D" para eixos do catálogo; só o nome para os eixos do usuário.</summary>
    [JsonIgnore]
    public string AxisLabel => AxisNumber is int n ? $"{n}. {AxisName}" : AxisName;
}

public sealed class JobItem
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string SourceName { get; set; } = "";
    public string OriginalFile { get; set; } = "";
    public int PixelWidth { get; set; }
    public int PixelHeight { get; set; }

    public StepStatus CleanStatus { get; set; } = StepStatus.Pending;
    public string? CleanedFile { get; set; }
    public string? CleanError { get; set; }
    public string? CleanWarning { get; set; }
    public ReviewStatus CleanReview { get; set; } = ReviewStatus.Pending;
    public string? CleanRedoNote { get; set; }
    public bool AnalysisDone { get; set; }
    public string? Transcript { get; set; }
    /// <summary>1.0.0-beta.6: texto realmente visto no limpo, quando difere do esperado.</summary>
    public string? SeenText { get; set; }

    // 1.0.0-beta.4
    public AIErrorKind? CleanErrorKind { get; set; }
    public string? CleanErrorDetails { get; set; }
    public string? CleanRetryNote { get; set; }
    public DateTime? CleanRetryAt { get; set; }
    public ProviderKind? CleanProviderUsed { get; set; }
    public ProviderKind? CleanProviderOverride { get; set; }

    // 1.0.0-beta.7
    /// <summary>Plano feito pela IA de planejamento antes da limpeza.</summary>
    public CreativePlan? Plan { get; set; }
    /// <summary>O planejamento já rodou (com ou sem sucesso), para não repetir a cada retomada.</summary>
    public bool? PlanDone { get; set; }
    /// <summary>Quantas vezes o app refez a limpeza sozinho porque sobrou termo proibido.</summary>
    public int? AutoCleanRedos { get; set; }

    // 1.0.0-beta.8
    /// <summary>A limpeza foi pulada porque o plano disse que não havia nada a remover (o "limpo" é o original).</summary>
    public bool? CleanSkipped { get; set; }
    /// <summary>Obriga a limpeza mesmo que o plano diga que não precisa.</summary>
    public bool? ForceClean { get; set; }

    public List<Variation> Variations { get; set; } = new();

    [JsonIgnore] public string BaseName => Path.GetFileNameWithoutExtension(SourceName);

    [JsonIgnore]
    public bool HasWarning => CleanWarning != null || Variations.Any(v => v.TextWarning != null);

    [JsonIgnore]
    public bool HasFailure => CleanStatus == StepStatus.Failed || Variations.Any(v => v.Status == StepStatus.Failed);

    [JsonIgnore]
    public int FailureCount =>
        (CleanStatus == StepStatus.Failed ? 1 : 0) +
        (CleanStatus == StepStatus.Failed ? 0 : Variations.Count(v => v.Status == StepStatus.Failed));

    [JsonIgnore]
    public bool IsFinished =>
        (CleanStatus == StepStatus.Done || CleanStatus == StepStatus.Failed) &&
        (CleanStatus == StepStatus.Failed || Variations.All(v => v.Status == StepStatus.Done || v.Status == StepStatus.Failed));
}

public sealed class Job
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = "";
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public ClientProfile Client { get; set; } = new();
    public string InputFolder { get; set; } = "";
    public ProviderKind CleanProvider { get; set; }
    public ProviderKind VariationProvider { get; set; }
    public ProviderKind AnalysisProvider { get; set; }
    public int VariationsPerItem { get; set; }
    public OutputSizeMode SizeMode { get; set; } = OutputSizeMode.Fixed(1080, 1350);
    public OutputFormat Format { get; set; }
    public bool VerifyText { get; set; }
    public JobState State { get; set; } = JobState.Queued;
    public List<JobItem> Items { get; set; } = new();
    [JsonPropertyName("costUSD")] public double CostUSD { get; set; }
    public string? ExportedTo { get; set; }
    public string? LastError { get; set; }

    // 1.0.0-beta.6
    /// <summary>Instruções livres do Novo lote, já separadas em remover / texto / direção.</summary>
    public BatchInstructions? Instructions { get; set; }

    // 1.0.0-beta.19
    /// <summary>Teste de eixos: cada criativo passa por todos os eixos do cliente, na ordem da lista.</summary>
    public bool? AxisTest { get; set; }

    [JsonIgnore] public bool IsAxisTest => AxisTest ?? false;

    // 1.0.0-beta.20
    /// <summary>Módulo "Limpar logo": o lote só limpa (sem variações).</summary>
    public bool? CleanOnly { get; set; }
    /// <summary>Limpeza desligada no lote: as imagens já vêm limpas e vão direto para as variações.</summary>
    public bool? SkipCleaning { get; set; }

    [JsonIgnore] public bool IsCleanOnly => CleanOnly ?? false;
    [JsonIgnore] public bool SkipsCleaning => !IsCleanOnly && (SkipCleaning ?? false);

    /// <summary>"teste de eixos", "só limpeza", "sem limpeza"… para cabeçalhos e registro.</summary>
    [JsonIgnore]
    public string ModeLabel
    {
        get
        {
            if (IsCleanOnly) return "só limpeza";
            var parts = new List<string>();
            if (IsAxisTest) parts.Add("teste de eixos");
            if (SkipsCleaning) parts.Add("limpeza desligada");
            return string.Join(" · ", parts);
        }
    }

    /// <summary>Lista do cliente + o que as instruções do lote mandam remover.</summary>
    [JsonIgnore]
    public List<string> EffectiveRemoveItems
    {
        get
        {
            var list = new List<string>(Client.RemoveItems);
            foreach (var r in Instructions?.RemoveItems ?? new List<string>())
                if (!list.Contains(r)) list.Add(r);
            return list;
        }
    }

    /// <summary>Total de etapas de geração (limpeza + variações) para a barra de progresso.</summary>
    [JsonIgnore] public int TotalSteps => Items.Sum(i => 1 + i.Variations.Count);

    [JsonIgnore]
    public int FinishedSteps => Items.Sum(item =>
    {
        var clean = item.CleanStatus == StepStatus.Done || item.CleanStatus == StepStatus.Failed ? 1 : 0;
        var vars = item.CleanStatus == StepStatus.Failed
            ? item.Variations.Count
            : item.Variations.Count(v => v.Status == StepStatus.Done || v.Status == StepStatus.Failed);
        return clean + vars;
    });

    [JsonIgnore] public double Progress => TotalSteps == 0 ? 0 : (double)FinishedSteps / TotalSteps;

    [JsonIgnore]
    public int ApprovedCount => Items.Sum(item =>
        (item.CleanReview == ReviewStatus.Approved && item.CleanedFile != null ? 1 : 0) +
        item.Variations.Count(v => v.Review == ReviewStatus.Approved && v.File != null));

    [JsonIgnore]
    public int PendingReviewCount => Items.Sum(item =>
        (item.CleanStatus == StepStatus.Done && item.CleanReview == ReviewStatus.Pending ? 1 : 0) +
        item.Variations.Count(v => v.Status == StepStatus.Done && v.Review == ReviewStatus.Pending));

    [JsonIgnore] public int WarningCount => Items.Count(i => i.HasWarning);

    [JsonIgnore] public int FailureCount => Items.Sum(i => i.FailureCount);

    /// <summary>Cópia independente (o Swift trabalha com cópias de valor; aqui a cópia evita mexer no lote de outra thread).</summary>
    public Job Clone() => JsonSerializer.Deserialize<Job>(JsonSerializer.Serialize(this, Json.Compact), Json.Compact)!;
}
