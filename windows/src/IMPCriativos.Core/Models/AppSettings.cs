using System.ComponentModel;
using System.Runtime.CompilerServices;
using IMPCriativos.Core.Providers;
using IMPCriativos.Core.Storage;

namespace IMPCriativos.Core.Models;

/// <summary>
/// Preferências do app, salvas em <c>preferencias.json</c> (no Mac, UserDefaults) com as mesmas chaves e valores de fábrica.
/// As chaves de API ficam em <c>chaves.json</c>, não aqui.
/// </summary>
public sealed class AppSettings : INotifyPropertyChanged
{
    private readonly Preferences d;

    public event PropertyChangedEventHandler? PropertyChanged;

    public AppSettings(Preferences? prefs = null)
    {
        d = prefs ?? Preferences.Shared;
        d.Register(new Dictionary<string, object?>
        {
            ["runInBackground"] = true,
            ["notifyOnFinish"] = true,
            ["includeBetaUpdates"] = true,
            ["checkUpdatesOnLaunch"] = true,
            ["maxConcurrent"] = 3,
            ["maxImageRequests"] = 2,
            ["fastMode"] = true,
            ["fastImageCeiling"] = 4,
            ["retryAttempts"] = 6,
            ["fallbackEnabled"] = true,
            ["fallbackOnBlocked"] = true,
            ["defaultFormat"] = "feed",
            ["openaiQuality"] = "medium",
            ["priceGeminiImage"] = 0.07,
            ["priceOpenAIImage"] = 0.06,
            ["priceAnalysis"] = 0.002,
            ["planningEnabled"] = true,
            ["pricePlanning"] = 0.02,
            [Niche.KeepNoticesKey] = false,
        });
        _stageAI = LoadStageAI();
    }

    private void Notify([CallerMemberName] string? name = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));

    private bool B(string key) => d.GetBool(key);
    private void SetB(string key, bool v, [CallerMemberName] string? name = null) { d.Set(key, v); Notify(name); }
    private void SetI(string key, int v, [CallerMemberName] string? name = null) { d.Set(key, v); Notify(name); }
    private void SetD(string key, double v, [CallerMemberName] string? name = null) { d.Set(key, v); Notify(name); }

    // Comportamento
    public bool RunInBackground { get => B("runInBackground"); set => SetB("runInBackground", value); }
    public bool NotifyOnFinish { get => B("notifyOnFinish"); set => SetB("notifyOnFinish", value); }
    public bool IncludeBetaUpdates { get => B("includeBetaUpdates"); set => SetB("includeBetaUpdates", value); }
    public bool CheckUpdatesOnLaunch { get => B("checkUpdatesOnLaunch"); set => SetB("checkUpdatesOnLaunch", value); }

    // Processamento
    public int MaxConcurrent { get => Math.Max(1, d.GetInt("maxConcurrent")); set => SetI("maxConcurrent", value); }
    /// <summary>Pedidos de imagem ao mesmo tempo para cada IA, somando todos os lotes.</summary>
    public int MaxImageRequests { get => Math.Max(1, d.GetInt("maxImageRequests")); set => SetI("maxImageRequests", value); }
    /// <summary>
    /// 1.0.0-beta.19: Modo rápido com segurança — sobe os pedidos de imagem enquanto a IA responde bem
    /// e volta para <see cref="MaxImageRequests"/> (velocidade original) ao primeiro sinal de risco.
    /// </summary>
    public bool FastMode { get => B("fastMode"); set => SetB("fastMode", value); }
    /// <summary>Teto do modo rápido: pedidos de imagem ao mesmo tempo por IA.</summary>
    public int FastImageCeiling { get => Math.Max(1, d.GetInt("fastImageCeiling")); set => SetI("fastImageCeiling", value); }
    /// <summary>Tentativas em erro temporário (503, 429, conexão), contando a primeira.</summary>
    public int RetryAttempts { get => Math.Max(1, d.GetInt("retryAttempts")); set => SetI("retryAttempts", value); }
    /// <summary>Se uma IA falhar por erro temporário, refaz com a outra (quando houver chave).</summary>
    public bool FallbackEnabled { get => B("fallbackEnabled"); set => SetB("fallbackEnabled", value); }
    /// <summary>Também troca de IA quando a imagem for bloqueada pelo filtro de conteúdo.</summary>
    public bool FallbackOnBlocked { get => B("fallbackOnBlocked"); set => SetB("fallbackOnBlocked", value); }

    public static string DefaultOutputFolderPath =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyPictures) is { Length: > 0 } pics
            ? pics
            : Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "IMP Criativos");

    public string DefaultOutputFolder
    {
        get => d.GetString("defaultOutputFolder") ?? DefaultOutputFolderPath;
        set { d.Set("defaultOutputFolder", value); Notify(); }
    }

    public MetaFormat DefaultFormat
    {
        get => d.GetString("defaultFormat") == "story" ? MetaFormat.Story : MetaFormat.Feed;
        set { d.Set("defaultFormat", value == MetaFormat.Story ? "story" : "feed"); Notify(); }
    }

    private Dictionary<AIStage, StageAI> _stageAI;

    /// <summary>1.0.0-beta.11: plataforma + modelo de cada etapa, com a reserva usada quando a principal falha.</summary>
    public IReadOnlyDictionary<AIStage, StageAI> StageAIs => _stageAI;

    public string OpenaiQuality { get => d.GetString("openaiQuality") ?? "medium"; set { d.Set("openaiQuality", value); Notify(); } }
    /// <summary>Liga a etapa de planejamento (recomendado).</summary>
    public bool PlanningEnabled { get => B("planningEnabled"); set => SetB("planningEnabled", value); }
    /// <summary>
    /// 1.0.0-beta.17: ligado = mantém os avisos 18+ / jogo responsável / advertências; desligado (padrão) = remove.
    /// Lido pelos prompts em <see cref="Niche.NoticesRule"/>.
    /// </summary>
    public bool KeepWarningNotices { get => B(Niche.KeepNoticesKey); set => SetB(Niche.KeepNoticesKey, value); }

    // Preços estimados (US$) — só para a estimativa e o contador de gasto
    public double PriceGeminiImage { get => d.GetDouble("priceGeminiImage"); set => SetD("priceGeminiImage", value); }
    public double PriceOpenAIImage { get => d.GetDouble("priceOpenAIImage"); set => SetD("priceOpenAIImage", value); }
    public double PriceAnalysis { get => d.GetDouble("priceAnalysis"); set => SetD("priceAnalysis", value); }
    public double PricePlanning { get => d.GetDouble("pricePlanning"); set => SetD("pricePlanning", value); }

    // MARK: IA por etapa

    public StageAI Stage(AIStage s) => _stageAI.TryGetValue(s, out var v) ? v : s.DefaultAI();

    /// <summary>Se o modelo escolhido era a reserva, a antiga principal passa a ser a reserva (as duas não ficam iguais).</summary>
    public void SetPrimary(ModelChoice c, AIStage s)
    {
        var v = Stage(s);
        if (v.Primary == c) return;
        var backup = v.Backup == c ? v.Primary : v.Backup;
        SetStage(s, new StageAI(c, backup));
    }

    /// <summary>
    /// Escolha feita no Novo lote. Se a plataforma nova era a da reserva, a antiga principal vira a reserva,
    /// para a etapa continuar com uma reserva de outra plataforma.
    /// </summary>
    public void AdoptForBatch(ModelChoice c, AIStage s)
    {
        var v = Stage(s);
        if (v.Primary == c) return;
        var backup = v.Backup;
        if (v.Backup == c || (v.Backup?.Provider == c.Provider && v.Primary.Provider != c.Provider)) backup = v.Primary;
        SetStage(s, new StageAI(c, backup));
    }

    public void SetBackup(ModelChoice? c, AIStage s) => SetStage(s, Stage(s) with { Backup = c });

    private void SetStage(AIStage s, StageAI v)
    {
        _stageAI = new Dictionary<AIStage, StageAI>(_stageAI) { [s] = v };
        SaveStageAI();
        Notify(nameof(StageAIs));
    }

    private const string StageKey = "stageAI";

    private void SaveStageAI() =>
        d.SetObject(StageKey, _stageAI.ToDictionary(kv => kv.Key.Raw(), kv => kv.Value));

    private Dictionary<AIStage, StageAI> LoadStageAI()
    {
        var raw = d.GetObject<Dictionary<string, StageAI>>(StageKey);
        var o = new Dictionary<AIStage, StageAI>();
        if (raw != null)
            foreach (var (k, v) in raw)
                if (AIStageExt.Parse(k) is AIStage st && v?.Primary != null) o[st] = v;
        foreach (var st in AIStageExt.All)
            if (!o.ContainsKey(st)) o[st] = st.DefaultAI();
        return o;
    }

    /// <summary>Passa velocidade original, teto e modo rápido para as filas de imagem (vale na hora, inclusive com lote rodando).</summary>
    public void ApplySpeed()
    {
        ProviderGate.Configure(MaxImageRequests, FastImageCeiling, FastMode);
        SpeedMonitor.Shared.Refresh();
    }

    public double ImagePrice(ProviderKind p) => p == ProviderKind.Gemini ? PriceGeminiImage : PriceOpenAIImage;

    /// <summary>Resumo da configuração para o histórico e o diagnóstico (sem chaves).</summary>
    public string Summary
    {
        get
        {
            var stages = string.Join("\n", AIStageExt.All.Select(st =>
            {
                var v = Stage(st);
                return $"{st.Label()}: {v.Primary.Label} → reserva {v.Backup?.Label ?? "nenhuma"}";
            }));
            var fallback = FallbackEnabled
                ? "ligada" + (FallbackOnBlocked ? " (também em bloqueio de conteúdo)" : " (só em erro temporário)")
                : "desligada";
            return $"""
                {stages}
                OpenAI qualidade {OpenaiQuality} · Planejamento {(PlanningEnabled ? "ligado" : "desligado")}
                Processamento: {MaxConcurrent} criativos por lote ao mesmo tempo · {MaxImageRequests} pedidos de imagem por IA (velocidade original) · {RetryAttempts} tentativas em erro temporário
                Modo rápido com segurança: {(FastMode ? $"ligado, teto de {Math.Max(MaxImageRequests, FastImageCeiling)} pedidos de imagem por IA" : "desligado")}
                Troca automática de IA: {fallback}
                Avisos 18+ e de jogo responsável: {(KeepWarningNotices ? "mantidos" : "removidos")}
                """;
        }
    }

    public void ResetModels()
    {
        _stageAI = AIStageExt.All.ToDictionary(s => s, s => s.DefaultAI());
        SaveStageAI();
        OpenaiQuality = "medium";
        Notify(nameof(StageAIs));
    }
}
