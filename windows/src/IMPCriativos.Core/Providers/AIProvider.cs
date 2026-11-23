using IMPCriativos.Core.Models;
using IMPCriativos.Core.Storage;

namespace IMPCriativos.Core.Providers;

/// <summary>Interface única para os provedores de IA. Cada etapa do lote escolhe qual usar.</summary>
public interface IAIProvider
{
    /// <summary>Edita/gera uma imagem a partir de uma imagem de referência e de uma instrução.</summary>
    Task<byte[]> EditImage(byte[] jpeg, string prompt, string aspectRatio, CancellationToken ct = default);
    /// <summary>Analisa uma imagem e responde em texto (pedimos JSON no prompt).</summary>
    Task<string> Analyze(byte[] jpeg, string prompt, CancellationToken ct = default);
    /// <summary>Pedido só de texto, sem imagem (pedimos JSON no prompt).</summary>
    Task<string> Complete(string prompt, CancellationToken ct = default);
    /// <summary>Confere se a chave funciona.</summary>
    Task TestKey(CancellationToken ct = default);
}

/// <summary>Configuração lida das Configurações no momento em que o lote roda.</summary>
public sealed class ProviderConfig
{
    /// <summary>Resolução pedida ao Gemini. 2K cobre com folga 1080×1350 e 1080×1920.</summary>
    public string GeminiImageSize { get; init; } = "2K";
    public string OpenaiQuality { get; init; }
    /// <summary>1.0.0-beta.11: plataforma + modelo de cada etapa, com reserva.</summary>
    public Dictionary<AIStage, StageAI> Stages { get; init; }

    public ProviderConfig(AppSettings s)
    {
        OpenaiQuality = s.OpenaiQuality;
        var clean = new Dictionary<AIStage, StageAI>();
        foreach (var st in AIStageExt.All)
        {
            var v = s.Stage(st);
            var pm = v.Primary.Model.Trim();
            var primary = v.Primary with { Model = pm.Length == 0 ? st.DefaultModel(v.Primary.Provider) : pm };
            ModelChoice? backup = null;
            if (v.Backup is ModelChoice b)
            {
                var bm = b.Model.Trim();
                backup = b with { Model = bm.Length == 0 ? st.DefaultModel(b.Provider) : bm };
            }
            clean[st] = new StageAI(primary, backup);
        }
        Stages = clean;
    }

    public StageAI Stage(AIStage st) => Stages.TryGetValue(st, out var v) ? v : st.DefaultAI();

    /// <summary>
    /// Ordem de tentativa da etapa: principal e depois a reserva (sem repetir).
    /// <paramref name="prefer"/>: plataforma escolhida no lote ou em "Refazer com…". Se não for a principal, ela vai na frente
    /// (com o modelo configurado para ela nesta etapa, ou o padrão da plataforma) e a principal vira a reserva.
    /// </summary>
    public List<ModelChoice> Chain(AIStage st, ProviderKind? prefer = null)
    {
        var s = Stage(st);
        var list = new List<ModelChoice> { s.Primary };
        if (s.Backup != null) list.Add(s.Backup);
        if (prefer is ProviderKind p && list[0].Provider != p)
        {
            var i = list.FindIndex(c => c.Provider == p);
            if (i >= 0)
            {
                var c = list[i];
                list.RemoveAt(i);
                list.Insert(0, c);
            }
            else list.Insert(0, new ModelChoice(p, st.DefaultModel(p)));
        }
        var seen = new HashSet<ModelChoice>();
        return list.Where(c => seen.Add(c)).Take(2).ToList();
    }
}

public static class ProviderFactory
{
    /// <summary>Teste: troca a criação dos provedores (IA de mentira).</summary>
    public static Func<ModelChoice, ProviderConfig, IAIProvider>? Override { get; set; }

    /// <summary>
    /// Cria o provedor da plataforma com o modelo escolhido (o mesmo nome serve para imagem ou texto;
    /// cada etapa só usa a função do seu tipo).
    /// </summary>
    public static IAIProvider Make(ModelChoice choice, ProviderConfig config)
    {
        if (Override != null) return Override(choice, config);
        var key = ApiKeyStore.Load(choice.Provider)
                  ?? throw new AIError($"Chave do {choice.Provider.Label()} não configurada. Vá em Configurações → Chaves de API.", AIErrorKind.Auth);
        return choice.Provider == ProviderKind.Gemini
            ? new GeminiProvider(key, choice.Model, choice.Model, config.GeminiImageSize)
            : new OpenAIProvider(key, choice.Model, choice.Model, config.OpenaiQuality);
    }
}
