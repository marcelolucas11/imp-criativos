using System.Text.Json.Nodes;
using System.Text.Json.Serialization;
using IMPCriativos.Core.Providers;
using IMPCriativos.Core.Storage;

namespace IMPCriativos.Core.Models;

/// <summary>
/// Instruções livres digitadas no Novo lote, separadas em três partes
/// para que cada uma vá para a etapa (e para a checagem) certa.
/// </summary>
public sealed class BatchInstructions
{
    /// <summary>O que o usuário digitou, como digitou.</summary>
    public string Raw { get; set; } = "";
    /// <summary>Itens a remover além da lista do cliente (valem na limpeza e nas checagens).</summary>
    public List<string> RemoveItems { get; set; } = new();
    /// <summary>Alterações de texto: incluir, trocar ou tirar palavras. Viram o "texto esperado".</summary>
    public string TextChanges { get; set; } = "";
    /// <summary>Direção visual somada aos eixos de cada variação.</summary>
    public string Direction { get; set; } = "";

    [JsonIgnore]
    public bool IsEmpty => RemoveItems.Count == 0 && TextChanges.Trimmed() == "" && Direction.Trimmed() == "";

    /// <summary>Resumo de uma linha para o Histórico e o topo do lote.</summary>
    [JsonIgnore]
    public string Summary
    {
        get
        {
            var parts = new List<string>();
            if (RemoveItems.Count > 0) parts.Add("Remover: " + string.Join(", ", RemoveItems));
            if (TextChanges.Trimmed() != "") parts.Add("Texto: " + TextChanges.Trimmed());
            if (Direction.Trimmed() != "") parts.Add("Direção: " + Direction.Trimmed());
            return string.Join(" · ", parts);
        }
    }
}

public static class StringExt
{
    /// <summary>Igual ao <c>trimmingCharacters(in: .whitespacesAndNewlines)</c> do Swift.</summary>
    public static string Trimmed(this string? s) => (s ?? "").Trim();

    public static string? NilIfEmpty(this string? s) => string.IsNullOrEmpty(s) ? null : s;
}

/// <summary>Usa a IA de texto para separar o pedido livre em remover / texto / direção.</summary>
public static class InstructionInterpreter
{
    public static string Prompt(string raw) =>
        $$"""
        {{Niche.PromptContext}}

        You help configure a batch job that edits advertising images. First, each image is cleaned (brand elements are removed). Then several new variations of each image are generated.
        The user wrote instructions for this batch in Brazilian Portuguese. Split them into exactly three groups:

        1. "remove": a list of visual elements, names or words that must be REMOVED from the images (for example a brand or game name, a logo, a handle). One short item per element, in Brazilian Portuguese, keeping names exactly as the user wrote them and putting every word or name to erase between double quotes (example: Palavra "Aviator" (escrita em qualquer lugar)). Every word the user wants gone must appear here, one item per word or name.
        2. "text_changes": changes to the TEXT written in the images: words, names or phrases to add, replace or rewrite. Write it as a short, precise instruction in Brazilian Portuguese, quoting the exact words (example: Incluir o nome "Nome Novo" no topo; Trocar "R$ 10" por "R$ 5"). Empty string if none. Removing a word is NOT a text change, it goes to "remove".
        3. "direction": everything else about how the variations should look (angles, scenery, colors, style, mood, diversity). Short instruction in Brazilian Portuguese. Empty string if none.

        Do not invent anything the user did not ask for. Ignore requests about quantities, file formats or sizes.

        USER INSTRUCTIONS:
        <<<
        {{raw}}
        >>>

        Respond ONLY with JSON in this exact shape:
        {"remove": ["..."], "text_changes": "...", "direction": "..."}
        """;

    public static BatchInstructions? Parse(string text, string raw)
    {
        var obj = JsonExtract.Object(text);
        if (obj == null) return null;
        var remove = new List<string>();
        if (obj["remove"] is JsonArray arr)
            foreach (var n in arr)
                if (n is JsonValue v && v.TryGetValue<string>(out var s) && s.Trimmed() != "") remove.Add(s.Trimmed());
        return new BatchInstructions
        {
            Raw = raw,
            RemoveItems = remove,
            TextChanges = JsonExtract.Str(obj, "text_changes").Trimmed(),
            Direction = JsonExtract.Str(obj, "direction").Trimmed(),
        };
    }

    /// <summary>Tenta a IA de planejamento (principal e reserva) e, se falhar, a de análise. Só usa IAs com chave.</summary>
    public static async Task<(BatchInstructions Result, ProviderKind Provider)> Interpret(string raw, ProviderKind preferred,
        AppSettings settings, CancellationToken ct = default)
    {
        var config = new ProviderConfig(settings);
        var seen = new HashSet<ModelChoice>();
        var order = config.Chain(AIStage.Planning).Concat(config.Chain(AIStage.Analysis, preferred))
            .Where(c => ApiKeyStore.HasKey(c.Provider) && seen.Add(c)).ToList();
        Exception lastError = new AIError("Nenhuma chave de API configurada.");
        foreach (var choice in order)
        {
            try
            {
                var provider = ProviderFactory.Make(choice, config);
                var answer = await provider.Complete(Prompt(raw), ct);
                var parsed = Parse(answer, raw);
                if (parsed != null) return (parsed, choice.Provider);
                lastError = new AIError($"A resposta do {choice.Label} não veio no formato esperado.");
            }
            catch (OperationCanceledException) { throw; }
            catch (Exception e)
            {
                lastError = e;
            }
        }
        throw lastError;
    }
}
