using System.Text.Json.Nodes;
using IMPCriativos.Core.Providers;
using IMPCriativos.Core.Storage;

namespace IMPCriativos.Core.Models;

// 1.0.0-beta.11: cada etapa escolhe plataforma + modelo, e uma reserva (plataforma + modelo) para quando falhar.

/// <summary>O que o modelo precisa saber fazer. Define quais modelos aparecem na lista de cada etapa.</summary>
public enum ModelRole
{
    /// <summary>Edita/gera imagem a partir de uma imagem de referência (limpeza e variações).</summary>
    Image,
    /// <summary>Lê imagem/texto e responde em JSON (análise, checagem, planejamento, interpretação).</summary>
    Text,
}

/// <summary>Etapas do lote que usam IA.</summary>
public enum AIStage { Clean, Variation, Analysis, Planning }

public static class AIStageExt
{
    public static readonly AIStage[] All = { AIStage.Clean, AIStage.Variation, AIStage.Analysis, AIStage.Planning };

    public static string Raw(this AIStage s) => s switch
    {
        AIStage.Clean => "clean",
        AIStage.Variation => "variation",
        AIStage.Analysis => "analysis",
        _ => "planning",
    };

    public static AIStage? Parse(string raw) => raw switch
    {
        "clean" => AIStage.Clean,
        "variation" => AIStage.Variation,
        "analysis" => AIStage.Analysis,
        "planning" => AIStage.Planning,
        _ => null,
    };

    public static string Label(this AIStage s) => s switch
    {
        AIStage.Clean => "Limpeza",
        AIStage.Variation => "Variações",
        AIStage.Analysis => "Análise e checagem",
        _ => "Planejamento",
    };

    public static string Help(this AIStage s) => s switch
    {
        AIStage.Clean => "Remove logo, nome, @ e site do criativo original.",
        AIStage.Variation => "Cria as variações a partir do criativo limpo.",
        AIStage.Analysis => "Confere a limpeza e o texto de cada variação. Modelo rápido e barato basta.",
        _ => "Lê o seu pedido e cada criativo antes da limpeza e interpreta as instruções do lote. Use o modelo mais forte.",
    };

    public static ModelRole Role(this AIStage s) =>
        s is AIStage.Clean or AIStage.Variation ? ModelRole.Image : ModelRole.Text;

    /// <summary>Modelo padrão de cada plataforma para esta etapa.</summary>
    public static string DefaultModel(this AIStage s, ProviderKind p) => (s, p) switch
    {
        (AIStage.Clean or AIStage.Variation, ProviderKind.Gemini) => "gemini-nano-banana-2.1",
        (AIStage.Clean or AIStage.Variation, ProviderKind.Openai) => "gpt-image-2",
        (AIStage.Analysis, ProviderKind.Gemini) => "gemini-3.5-flash-lite",
        (AIStage.Analysis, ProviderKind.Openai) => "gpt-5-mini",
        (AIStage.Planning, ProviderKind.Gemini) => "gemini-4-argon",
        _ => "gpt-6-sol",
    };

    /// <summary>
    /// Configuração de fábrica: limpeza no GPT (o filtro de imagem do Gemini bloqueava quase todas), o resto no Gemini,
    /// e a outra plataforma como reserva.
    /// </summary>
    public static StageAI DefaultAI(this AIStage s)
    {
        var main = s == AIStage.Clean ? ProviderKind.Openai : ProviderKind.Gemini;
        var alt = main.Other();
        return new StageAI(new ModelChoice(main, s.DefaultModel(main)), new ModelChoice(alt, s.DefaultModel(alt)));
    }
}

/// <summary>Uma plataforma e um modelo dela.</summary>
public sealed record ModelChoice(ProviderKind Provider, string Model)
{
    public string Label => $"{Provider.Label()} · {Model}";
}

/// <summary>IA principal e reserva de uma etapa.</summary>
public sealed record StageAI(ModelChoice Primary, ModelChoice? Backup);

public enum ModelTier { Strong, Fast, Current, Older }

public static class ModelTierExt
{
    public static readonly ModelTier[] All = { ModelTier.Strong, ModelTier.Fast, ModelTier.Current, ModelTier.Older };

    public static string Title(this ModelTier t) => t switch
    {
        ModelTier.Strong => "Mais fortes (bons para o planejamento)",
        ModelTier.Fast => "Rápidos e baratos (bons para análise e checagem)",
        ModelTier.Current => "Atuais",
        _ => "Versões anteriores",
    };
}

/// <summary>Um modelo da lista fixa do app.</summary>
public sealed record ModelOption(string Id, string Note, ModelTier Tier)
{
    public string MenuLabel => $"{Id}  —  {Note}";
}

/// <summary>
/// 1.0.0-beta.12: todos os modelos que funcionam no app, já prontos no menu (sem precisar digitar nem ter a chave).
/// Conferido nas páginas oficiais do Google e da OpenAI em 06/11/2026. Só entram modelos que respondem
/// pelo mesmo caminho que o app usa (Interactions API no Gemini; images/edits e chat/completions na OpenAI).
/// Cópia de <c>Models/AIModels.swift</c>.
/// </summary>
public static class BuiltInModels
{
    public static List<ModelOption> List(ProviderKind p, ModelRole role) => (p, role) switch
    {
        (ProviderKind.Gemini, ModelRole.Image) => new()
        {
            new("gemini-nano-banana-2.1", "Nano Banana 2.1 · padrão do app", ModelTier.Current),
            new("gemini-3-pro-image", "Nano Banana Pro · melhor texto na imagem, mais caro", ModelTier.Current),
            new("gemini-3.1-flash-image", "Nano Banana 2", ModelTier.Current),
            new("gemini-3.1-flash-lite-image", "Nano Banana 2 Lite · mais rápido e barato, só 1K", ModelTier.Current),
            new("gemini-2.5-flash-image", "Nano Banana original", ModelTier.Older),
        },
        (ProviderKind.Openai, ModelRole.Image) => new()
        {
            new("gpt-image-2.6-sunburst", "Images 2.6 · mais fiel na edição, mais lento", ModelTier.Current),
            new("gpt-image-2.6-flare", "Images 2.6 · rápido", ModelTier.Current),
            new("gpt-image-2.5-sunburst", "Images 2.5 · mais fiel na edição, mais lento", ModelTier.Current),
            new("gpt-image-2.5-flare", "Images 2.5 · rápido", ModelTier.Current),
            new("gpt-image-2", "padrão do app", ModelTier.Current),
            new("gpt-image-1.5", "descontinuado", ModelTier.Older),
            new("gpt-image-1-mini", "barato · descontinuado", ModelTier.Older),
        },
        (ProviderKind.Gemini, ModelRole.Text) => new()
        {
            new("gemini-4-argon", "o mais forte · padrão do planejamento · só plano pago", ModelTier.Strong),
            new("gemini-3.1-pro-preview", "Pro (prévia)", ModelTier.Strong),
            new("gemini-3.8-flash", "Flash mais novo · forte e rápido", ModelTier.Strong),
            new("gemini-3.7-flash", "Flash", ModelTier.Fast),
            new("gemini-3.6-flash", "Flash", ModelTier.Fast),
            new("gemini-3.5-flash", "Flash", ModelTier.Fast),
            new("gemini-3.5-flash-lite", "padrão da análise · rápido e barato", ModelTier.Fast),
            new("gemini-3.1-flash-lite", "o mais barato", ModelTier.Fast),
            new("gemini-2.5-pro", "2.5 Pro", ModelTier.Older),
            new("gemini-2.5-flash", "2.5 Flash", ModelTier.Older),
            new("gemini-2.5-flash-lite", "2.5 Flash-Lite", ModelTier.Older),
        },
        _ => new()
        {
            new("gpt-6-astra", "o mais forte · caro", ModelTier.Strong),
            new("gpt-6.1-sol", "quase Astra, bem mais barato", ModelTier.Strong),
            new("gpt-6-sol", "padrão do planejamento", ModelTier.Strong),
            new("gpt-6.1-terra", "rápido, bom em leitura de imagem", ModelTier.Fast),
            new("gpt-6-luna", "o mais barato da linha 6", ModelTier.Fast),
            new("gpt-5.4-mini", "mini", ModelTier.Fast),
            new("gpt-5-mini", "padrão da análise · descontinuado", ModelTier.Fast),
            new("gpt-5.6-sol", "5.6 Sol", ModelTier.Older),
            new("gpt-5.6-terra", "5.6 Terra", ModelTier.Older),
            new("gpt-5.6-luna", "5.6 Luna", ModelTier.Older),
            new("gpt-5.5", "5.5", ModelTier.Older),
            new("gpt-5.4", "5.4", ModelTier.Older),
            new("gpt-5.4-nano", "nano · descontinuado", ModelTier.Older),
        },
    };
}

/// <summary>Lista de modelos de cada plataforma: a lista fixa do app + os que a sua chave enxerga na API (Atualizar lista).</summary>
public sealed class ModelCatalog
{
    public static ModelCatalog Shared { get; } = new();

    private readonly object _lock = new();
    private Dictionary<string, List<string>> _fetched = new();

    public DateTime? LastUpdated { get; private set; }
    public bool Refreshing { get; private set; }
    public string? LastError { get; private set; }

    public event Action? Changed;

    private const string CacheKey = "modelCatalogCache";
    private const string DateKey = "modelCatalogUpdated";

    private ModelCatalog()
    {
        _fetched = Preferences.Shared.GetObject<Dictionary<string, List<string>>>(CacheKey) ?? new();
        LastUpdated = Preferences.Shared.GetDate(DateKey);
    }

    private static string Key(ProviderKind p, ModelRole role) => $"{p.Raw()}.{(role == ModelRole.Image ? "image" : "text")}";

    /// <summary>Lista fixa do app para o menu (aparece sempre, com ou sem chave).</summary>
    public List<ModelOption> Options(ProviderKind p, ModelRole role)
    {
        var list = BuiltInModels.List(p, role);
        // Garante que o padrão de cada etapa esteja na lista, mesmo se alguém mexer só no DefaultModel.
        var ids = list.Select(m => m.Id).ToHashSet();
        foreach (var m in AIStageExt.All.Where(s => s.Role() == role).Select(s => s.DefaultModel(p)))
            if (ids.Add(m)) list.Add(new ModelOption(m, "padrão do app", role == ModelRole.Image ? ModelTier.Current : ModelTier.Fast));
        return list;
    }

    /// <summary>
    /// Modelos que a sua chave enxerga e ainda não estão na lista fixa (lançamentos novos), mais novos no topo.
    /// <paramref name="current"/> garante que um modelo já escolhido fora da lista continue aparecendo.
    /// </summary>
    public List<string> ExtraModels(ProviderKind p, ModelRole role, string? current = null)
    {
        var seen = Options(p, role).Select(m => m.Id).ToHashSet();
        List<string> api;
        lock (_lock) api = _fetched.TryGetValue(Key(p, role), out var l) ? new List<string>(l) : new List<string>();
        api.Sort((a, b) => NaturalComparer.Instance.Compare(b, a));
        var result = new List<string>();
        foreach (var m in new[] { current ?? "" }.Concat(api))
            if (!string.IsNullOrEmpty(m) && seen.Add(m)) result.Add(m);
        return result;
    }

    /// <summary>Atualiza sozinho quando a lista tem mais de 1 dia.</summary>
    public async Task RefreshIfStale()
    {
        if (LastUpdated is DateTime d && (DateTime.UtcNow - d).TotalHours < 24) return;
        await Refresh();
    }

    public async Task Refresh()
    {
        if (Refreshing) return;
        Refreshing = true;
        Changed?.Invoke();
        try
        {
            var errors = new List<string>();
            Dictionary<string, List<string>> updated;
            lock (_lock) updated = new Dictionary<string, List<string>>(_fetched);
            var any = false;
            foreach (var p in ProviderKindExt.All)
            {
                var key = ApiKeyStore.Load(p);
                if (key == null) continue;
                try
                {
                    var ids = await ListModels(p, key);
                    updated[Key(p, ModelRole.Image)] = ids.Where(id => IsImageModel(p, id)).ToList();
                    updated[Key(p, ModelRole.Text)] = ids.Where(id => IsTextModel(p, id)).ToList();
                    any = true;
                }
                catch (Exception e)
                {
                    errors.Add($"{p.Label()}: {e.Message}");
                }
            }
            lock (_lock) _fetched = updated;
            LastError = errors.Count == 0 ? null : string.Join(" · ", errors);
            if (any)
            {
                LastUpdated = DateTime.UtcNow;
                Preferences.Shared.SetObject(CacheKey, updated);
                Preferences.Shared.Set(DateKey, LastUpdated);
                AppLog.Info(LogCategory.Configuracoes, "Lista de modelos atualizada.",
                    details: string.Join(" · ", updated.Keys.OrderBy(k => k, StringComparer.Ordinal).Select(k => $"{k}: {updated[k].Count}")));
            }
            if (LastError != null) AppLog.Warning(LogCategory.Configuracoes, "Não foi possível atualizar a lista de modelos.", details: LastError);
        }
        finally
        {
            Refreshing = false;
            Changed?.Invoke();
        }
    }

    // MARK: APIs de listagem

    private static async Task<List<string>> ListModels(ProviderKind p, string apiKey)
    {
        if (p == ProviderKind.Gemini)
        {
            var ids = new List<string>();
            string? pageToken = null;
            do
            {
                var url = "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000" +
                          (pageToken != null ? "&pageToken=" + Uri.EscapeDataString(pageToken) : "");
                var req = new HttpRequestMessage(HttpMethod.Get, url);
                req.Headers.TryAddWithoutValidation("x-goog-api-key", apiKey);
                var obj = Http.Json(await Http.Send(req, label: "Gemini · lista de modelos", attempts: 2)) as JsonObject;
                foreach (var m in (obj?["models"] as JsonArray) ?? new JsonArray())
                {
                    var name = (string?)m?["name"];
                    if (name == null) continue;
                    ids.Add(name.StartsWith("models/") ? name["models/".Length..] : name);
                }
                var next = (string?)obj?["nextPageToken"];
                pageToken = string.IsNullOrEmpty(next) ? null : next;
            } while (pageToken != null && ids.Count < 5000);
            return ids;
        }
        var oreq = new HttpRequestMessage(HttpMethod.Get, "https://api.openai.com/v1/models");
        oreq.Headers.TryAddWithoutValidation("Authorization", $"Bearer {apiKey}");
        var o = Http.Json(await Http.Send(oreq, label: "OpenAI · lista de modelos", attempts: 2)) as JsonObject;
        return ((o?["data"] as JsonArray) ?? new JsonArray()).Select(d => (string?)d?["id"]).Where(s => s != null).Select(s => s!).ToList();
    }

    private static bool Has(string id, params string[] parts)
    {
        var s = id.ToLowerInvariant();
        return parts.Any(p => s.Contains(p));
    }

    /// <summary>Modelos que editam imagem pelo mesmo caminho que o app usa.</summary>
    public static bool IsImageModel(ProviderKind p, string id) => p == ProviderKind.Gemini
        ? id.StartsWith("gemini") && Has(id, "image", "nano-banana")
        : Has(id, "gpt-image", "chatgpt-image");

    /// <summary>Modelos de texto/visão que respondem no endpoint de conversa que o app usa.</summary>
    public static bool IsTextModel(ProviderKind p, string id)
    {
        if (p == ProviderKind.Gemini)
            return id.StartsWith("gemini") &&
                   !Has(id, "image", "nano-banana", "embedding", "tts", "audio", "live", "aqa", "computer-use");
        var s = id.ToLowerInvariant();
        var family = s.StartsWith("gpt-") || s.StartsWith("chatgpt-") || (s.Length > 1 && s[0] == 'o' && char.IsDigit(s[1]));
        return family && !Has(id, "image", "audio", "realtime", "tts", "transcribe", "search", "embedding",
            "moderation", "instruct", "codex", "-pro", "deep-research", "computer-use");
    }
}
