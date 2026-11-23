using System.Globalization;
using System.Text;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using IMPCriativos.Core.Models;

namespace IMPCriativos.Core.Pipeline;

/// <summary>
/// 1.0.0-beta.7: plano de cada criativo, feito por uma IA de raciocínio mais forte ANTES da limpeza.
/// Ela olha a imagem original junto com tudo o que o usuário pediu (perfil do cliente + instruções do lote)
/// e devolve instruções exatas para as outras etapas. O código depois confere o resultado contra o plano.
/// </summary>
public sealed class CreativePlan
{
    /// <summary>Palavras, nomes, @ e sites que não podem aparecer em nenhuma imagem final (limpo e variações).</summary>
    public List<string> ForbiddenTerms { get; set; } = new();
    /// <summary>Texto do criativo original, como está.</summary>
    public string OriginalText { get; set; } = "";
    /// <summary>Texto exato que o criativo deve ter depois de TODOS os pedidos (remoções e alterações).</summary>
    public string FinalText { get; set; } = "";
    /// <summary>Instrução de edição específica para esta imagem (em inglês, para o modelo de imagem).</summary>
    public string CleanInstruction { get; set; } = "";
    /// <summary>Regras que toda variação deste criativo precisa seguir (em inglês).</summary>
    public string VariationRules { get; set; } = "";
    /// <summary>Dúvidas ou ambiguidades que a IA encontrou no pedido (português).</summary>
    public string Doubts { get; set; } = "";
    /// <summary>Modelo que fez o plano (para o Histórico).</summary>
    public string? Model { get; set; }
    /// <summary>
    /// 1.0.0-beta.8: false quando não há nada para apagar nem mudar nesta imagem; o app pula a limpeza
    /// e usa o original. null (planos antigos ou resposta sem o campo) conta como "precisa limpar".
    /// </summary>
    public bool? NeedsCleaning { get; set; }

    /// <summary>A limpeza só é pulada quando o plano diz explicitamente que não há nada a fazer.</summary>
    [JsonIgnore] public bool SkipsCleaning => NeedsCleaning == false;

    public CreativePlan Copy() => (CreativePlan)MemberwiseClone();
}

public static class CreativePlanner
{
    public static string Prompt(IReadOnlyList<string> removeItems, string extra, BatchInstructions? instructions)
    {
        var list = removeItems.Count == 0 ? "(none)" : string.Join("\n", removeItems.Select(r => $"- {r}"));
        var p = $$"""
            {{Niche.PromptContext}}

            You are the art director orchestrating an automated pipeline that edits one advertising image (attached). Cheaper models will execute your instructions literally and cannot see this request, so you must turn the user's wishes into exact, complete, unambiguous instructions for THIS specific image.

            Pipeline: (1) an image-editing model cleans the image following your "clean_instruction"; (2) other image models create new variations that must contain exactly your "final_text"; (3) checkers verify that none of the "forbidden_terms" appear anywhere and that the text matches.

            WHAT THE USER WANTS REMOVED (client profile + this batch, Brazilian Portuguese):
            {{list}}
            """;
        if (extra.Trimmed().Length > 0)
            p += $"\n\nCLIENT STANDING INSTRUCTIONS (Brazilian Portuguese):\n{extra.Trimmed()}";
        if (instructions != null)
        {
            if (instructions.Raw.Trimmed().Length > 0)
                p += $"\n\nTHE USER'S OWN WORDS FOR THIS BATCH (Brazilian Portuguese) — this is the source of truth, follow every part of it:\n<<<\n{instructions.Raw.Trimmed()}\n>>>";
            if (instructions.TextChanges.Trimmed().Length > 0)
                p += $"\n\nREQUESTED TEXT CHANGES (Brazilian Portuguese):\n{instructions.TextChanges.Trimmed()}";
            if (instructions.Direction.Trimmed().Length > 0)
                p += $"\n\nDIRECTION FOR THE VARIATIONS (Brazilian Portuguese):\n{instructions.Direction.Trimmed()}";
        }
        p += $$"""


            Rules:
            - Read every request literally and completely. If the user asks to remove a word or name "anywhere" or "all of it", it must disappear from EVERY place: headlines, titles, buttons, screens, signs, logos, small print.
            - Look at the image carefully and list in "forbidden_terms" every word, name, handle (@), website or phone that must not appear in any final image, written exactly as it appears in the image (one entry per term, e.g. "AVIATOR", "@marca", "marca.com"). Include terms the user asked to remove even if they are not visible. Do not include generic words that are not part of the request.
            - "original_text": transcribe all visible text exactly (Brazilian Portuguese, keep accents and line breaks).
            - "final_text": the exact text the image must have after applying ALL requests. When removing a word breaks a sentence, rewrite that sentence minimally so it stays natural and correct in Brazilian Portuguese, keeping the same meaning and offer (e.g. "GOSTA DE <removed>?" → "GOSTA DE JOGAR?"). Never introduce another brand, game or company name. Never keep a forbidden term. Keep everything else identical, including amounts, odds, multipliers, bonuses and other numbers. Never add a promise or claim of winnings that the original does not make.
            - Age and responsible-gambling notices: {{Niche.NoticesRule}}
            - "clean_instruction": an English instruction for the image-editing model, specific to this image. Name each element to erase and where it is. For every text line that changes, quote the old line and the exact new line ("Replace the headline 'X' with 'Y', same font, colors and effects"). Say what must stay unchanged. Small text inside phone screens, game thumbnails or signs that shows a forbidden term must be blurred, erased or replaced with a neutral graphic.
            - "variation_rules": English rules every variation must follow (user's direction and constraints, what must never appear, what must stay faithful: say which game or sport this is and which elements identify it, so the variations never drift to another game, sport or theme; if there is a 3D character or mascot, describe it precisely (species or design, colors, outfit, accessories) so every variation keeps the identical character). Empty only if there is nothing beyond the defaults.
            - "doubts": in Brazilian Portuguese, anything ambiguous you had to decide (empty string if none).
            - "needs_cleaning": false ONLY when this image has nothing to erase or change at all: none of the requested elements or forbidden terms are visible, "final_text" is identical to "original_text", and no other edit was requested for this image. Otherwise true. When in doubt, true.

            Respond ONLY with JSON in this exact shape:
            {"forbidden_terms": ["..."], "original_text": "...", "final_text": "...", "clean_instruction": "...", "variation_rules": "...", "doubts": "...", "needs_cleaning": true or false}
            """;
        return p;
    }

    public static CreativePlan? Parse(string text, string model)
    {
        var obj = Providers.JsonExtract.Object(text);
        if (obj == null) return null;
        var terms = new List<string>();
        if (obj["forbidden_terms"] is System.Text.Json.Nodes.JsonArray arr)
            foreach (var n in arr)
                if (n is System.Text.Json.Nodes.JsonValue v && v.TryGetValue<string>(out var s) && s.Trimmed().Length >= 2)
                    terms.Add(s.Trimmed());
        var clean = Providers.JsonExtract.Str(obj, "clean_instruction").Trimmed();
        if (clean.Length == 0) return null;
        var plan = new CreativePlan
        {
            ForbiddenTerms = ForbiddenTerms.Dedup(terms),
            OriginalText = Providers.JsonExtract.Str(obj, "original_text").Trimmed(),
            FinalText = Providers.JsonExtract.Str(obj, "final_text").Trimmed(),
            CleanInstruction = clean,
            VariationRules = Providers.JsonExtract.Str(obj, "variation_rules").Trimmed(),
            Doubts = Providers.JsonExtract.Str(obj, "doubts").Trimmed(),
            Model = model,
            NeedsCleaning = Providers.JsonExtract.Bool(obj, "needs_cleaning"),
        };
        // Garantia: o texto final nunca carrega termo proibido, mesmo que a IA erre.
        if (ForbiddenTerms.Found(plan.FinalText, plan.ForbiddenTerms).Count > 0)
            plan.FinalText = ForbiddenTerms.Strip(plan.ForbiddenTerms, plan.FinalText);
        return plan;
    }

    /// <summary>Resumo para o Histórico.</summary>
    public static string Summary(CreativePlan plan)
    {
        var lines = new List<string>
        {
            "Termos proibidos: " + (plan.ForbiddenTerms.Count == 0 ? "nenhum" : string.Join(", ", plan.ForbiddenTerms)),
            $"Texto original:\n{plan.OriginalText}",
            $"Texto final:\n{plan.FinalText}",
            $"Instrução de limpeza:\n{plan.CleanInstruction}",
        };
        if (plan.VariationRules.Length > 0) lines.Add($"Regras das variações:\n{plan.VariationRules}");
        if (plan.SkipsCleaning) lines.Add("Limpeza: nada a remover nesta imagem (o app usa o original)");
        if (plan.Doubts.Length > 0) lines.Add($"Dúvidas resolvidas pela IA: {plan.Doubts}");
        if (plan.Model != null) lines.Add($"Modelo: {plan.Model}");
        return string.Join("\n\n", lines);
    }
}

/// <summary>Conferência por código dos termos proibidos (sem IA): ignora maiúsculas, acentos e pontuação.</summary>
public static class ForbiddenTerms
{
    public static string Normalize(string s)
    {
        var folded = Storage.Paths.FoldDiacritics(s.Normalize(NormalizationForm.FormKC)).ToLowerInvariant();
        var sb = new StringBuilder(folded.Length);
        foreach (var ch in folded)
        {
            var cat = CharUnicodeInfo.GetUnicodeCategory(ch);
            var alnum = char.IsLetterOrDigit(ch) || cat is UnicodeCategory.NonSpacingMark or UnicodeCategory.SpacingCombiningMark
                or UnicodeCategory.EnclosingMark or UnicodeCategory.LetterNumber or UnicodeCategory.OtherNumber;
            sb.Append(alnum || ch == '@' ? ch : ' ');
        }
        return string.Join(" ", sb.ToString().Split(' ', StringSplitOptions.RemoveEmptyEntries));
    }

    public static List<string> Dedup(IEnumerable<string> terms)
    {
        var seen = new HashSet<string>();
        var o = new List<string>();
        foreach (var t in terms)
        {
            var n = Normalize(t);
            if (n.Length == 0 || !seen.Add(n)) continue;
            o.Add(t);
        }
        return o;
    }

    /// <summary>
    /// Termos que aparecem no texto (palavra inteira; "fera" não casa com "ferramenta").
    /// Também pega o termo escrito sem espaços ("AVI ATOR" lido pelo OCR como "AVIATOR" e vice-versa).
    /// </summary>
    public static List<string> Found(string text, IEnumerable<string> terms)
    {
        var hay = " " + Normalize(text) + " ";
        var squashed = hay.Replace(" ", "");
        return terms.Where(term =>
        {
            var n = Normalize(term);
            if (n.Length == 0) return false;
            if (hay.Contains(" " + n + " ")) return true;
            var nsq = n.Replace(" ", "");
            // sem espaços só para termos longos, para não gerar falso positivo com palavras curtas
            return nsq.Length >= 6 && squashed.Contains(nsq);
        }).ToList();
    }

    /// <summary>Tira os termos do texto (último recurso, quando o plano ou a transcrição ainda os trazem).</summary>
    public static string Strip(IEnumerable<string> terms, string text)
    {
        var o = text;
        foreach (var term in terms.Where(t => t.Trimmed().Length > 0))
        {
            var pattern = @"(?<![\p{L}\p{N}])" + Regex.Escape(term.Trimmed()) + @"(?![\p{L}\p{N}])";
            try { o = Regex.Replace(o, pattern, "", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant); } catch { }
        }
        var lines = Regex.Split(o, "\r\n|\n|\r| | |\u0085").Select(line =>
        {
            var l = Regex.Replace(line, @"\s{2,}", " ");
            l = Regex.Replace(l, @"\s+([?!.,:;])", "$1");
            return l.Trimmed();
        });
        return string.Join("\n", lines.Where(l => l.Length > 0));
    }

    /// <summary>
    /// Plano B quando o planejamento falha: tira dos itens de remoção as palavras citadas
    /// (entre aspas, "nome X", "palavra X", ou item curto como "Aviator").
    /// </summary>
    public static List<string> Fallback(IEnumerable<string> items)
    {
        var namePrefixes = new HashSet<string> { "nome", "nomes", "palavra", "palavras", "termo", "termos", "texto", "escrita" };
        var fillers = new HashSet<string> { "o", "a", "os", "as", "todo", "toda", "todos", "todas", "qualquer", "do", "da", "de", "dos", "das" };
        var generic = new HashSet<string>
        {
            "logo", "logotipo", "logomarca", "marca", "selo", "icone", "site", "telefone", "whatsapp",
            "cnpj", "instagram", "endereco", "empresa", "cliente", "rodape", "agua", "redes", "sociais",
            "internet", "qr", "codigo", "watermark",
        };
        var result = new List<string>();
        foreach (var item in items)
        {
            var quoted = Regex.Matches(item, "[\"“”']([^\"“”']{2,})[\"“”']").Select(m => m.Groups[1].Value.Trimmed()).ToList();
            if (quoted.Count > 0) { result.AddRange(quoted); continue; }
            var @base = Regex.Replace(item, @"\([^)]*\)", " ");
            var tokens = @base.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).ToList();
            var hadPrefix = false;
            while (tokens.Count > 0 && (fillers.Contains(Normalize(tokens[0])) || namePrefixes.Contains(Normalize(tokens[0]))))
            {
                if (namePrefixes.Contains(Normalize(tokens[0]))) hadPrefix = true;
                tokens.RemoveAt(0);
            }
            var rest = string.Join(" ", tokens);
            var parts = rest.Split(',', ';', '/')
                .SelectMany(x => x.Split(" e "))
                .Select(x => x.Trimmed())
                .Where(x => x.Length > 0);
            foreach (var part in parts)
            {
                var words = Normalize(part).Split(' ', StringSplitOptions.RemoveEmptyEntries);
                if (words.Length == 0 || words.Length > 3 || words.Any(generic.Contains)) continue;
                if (hadPrefix || words.Length <= 2) result.Add(part);
            }
        }
        return Dedup(result);
    }
}

/// <summary>
/// Leitura de texto feita pelo próprio computador, sem custo e sem IA externa (segunda opinião, independente da IA
/// que gerou a imagem). No Mac é o Vision; no Windows o App liga o <c>Windows.Media.Ocr</c>.
/// </summary>
public interface ILocalTextReader
{
    /// <summary>Texto lido (linhas separadas por \n), ou null se não houver OCR disponível.</summary>
    string? Text(string imagePath);

    /// <summary>Descrição curta (idioma usado) para o Histórico; null = sem OCR.</summary>
    string? Description { get; }
}

public static class LocalOCR
{
    public static ILocalTextReader? Reader { get; set; }
    private static int _warned;

    /// <summary>
    /// Texto lido pelo computador. Sem OCR disponível, devolve null e avisa uma vez no Histórico
    /// (a conferência local é pulada; a checagem por IA continua).
    /// </summary>
    public static string? Text(string path)
    {
        var r = Reader;
        if (r == null || r.Description == null)
        {
            if (Interlocked.Exchange(ref _warned, 1) == 0)
                Storage.AppLog.Warning(Storage.LogCategory.Analise,
                    "Leitura de texto do Windows indisponível: a conferência local foi pulada (a checagem por IA continua).",
                    details: "Para ligar, instale o idioma Português (Brasil) em Configurações do Windows → Hora e idioma → Idioma e região.");
            return null;
        }
        try { return r.Text(path); } catch { return null; }
    }
}
