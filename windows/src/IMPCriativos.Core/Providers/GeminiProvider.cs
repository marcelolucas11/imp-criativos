using System.Net.Http.Headers;
using System.Text;
using System.Text.Json.Nodes;
using IMPCriativos.Core.Pipeline;
using IMPCriativos.Core.Storage;

namespace IMPCriativos.Core.Providers;

/// <summary>
/// Google Gemini via Interactions API (v1beta/interactions).
/// Modelos padrão: gemini-nano-banana-2.1 (imagem) e gemini-3.5-flash-lite (análise).
/// </summary>
public sealed class GeminiProvider : IAIProvider
{
    private readonly string _apiKey;
    private readonly string _imageModel;
    private readonly string _textModel;
    private readonly string _imageSize;

    private const string Endpoint = "https://generativelanguage.googleapis.com/v1beta/interactions";

    public GeminiProvider(string apiKey, string imageModel, string textModel, string imageSize)
    {
        _apiKey = apiKey;
        _imageModel = imageModel;
        _textModel = textModel;
        _imageSize = imageSize;
    }

    /// <summary>
    /// Filtros de segurança ajustáveis do Gemini, todos desligados.
    /// Criativos de cassino/apostas legalizados não entram em nenhuma dessas categorias,
    /// mas o filtro às vezes confunde. As proteções fixas do Google (não ajustáveis) continuam valendo.
    /// </summary>
    private static JsonArray SafetyOff()
    {
        var a = new JsonArray();
        foreach (var t in new[] { "harassment", "hate_speech", "sexually_explicit", "dangerous_content", "jailbreak" })
            a.Add(new JsonObject { ["type"] = t, ["threshold"] = "off" });
        return a;
    }

    public async Task<byte[]> EditImage(byte[] jpeg, string prompt, string aspectRatio, CancellationToken ct = default)
    {
        try
        {
            return await EditOnce(jpeg, prompt, aspectRatio, ct);
        }
        catch (AIError e) when (e.Kind == AIErrorKind.Blocked && !IsImageSafety(e))
        {
            // Bloqueio do pedido (sem imagem na resposta): uma nova tentativa com a instrução em tom neutro.
            // 1.0.0-beta.8: no bloqueio do filtro de IMAGEM (image_safety) não repete.
            RequestContext.Current?.Log(LogLevel.Info, "Gemini bloqueou o pedido; tentando de novo com instrução neutra.", e.Details);
            RequestContext.Current?.OnStatus?.Invoke("Gemini bloqueou · tentando com instrução neutra…", null);
            return await EditOnce(jpeg, Prompts.Neutral(prompt), aspectRatio, ct);
        }
    }

    private static JsonArray Input(string prompt, byte[]? jpeg)
    {
        var a = new JsonArray { new JsonObject { ["type"] = "text", ["text"] = prompt } };
        if (jpeg != null)
            a.Add(new JsonObject { ["type"] = "image", ["mime_type"] = "image/jpeg", ["data"] = Convert.ToBase64String(jpeg) });
        return a;
    }

    private async Task<byte[]> EditOnce(byte[] jpeg, string prompt, string aspectRatio, CancellationToken ct)
    {
        // 1.0.0-beta.8: o modelo de imagem só devolve JPEG; o app converte para PNG ao salvar.
        JsonObject Format() => new()
        {
            ["type"] = "image",
            ["mime_type"] = "image/jpeg",
            ["aspect_ratio"] = aspectRatio,
            ["image_size"] = _imageSize,
        };
        // Do mais completo ao mais simples: se o modelo recusar algum campo (HTTP 400), tenta sem ele.
        var variants = new List<(string Label, Func<JsonObject> Body)>
        {
            ("completo", () => new JsonObject { ["model"] = _imageModel, ["input"] = Input(prompt, jpeg), ["response_format"] = Format(), ["safety_settings"] = SafetyOff() }),
            ("sem proporção/resolução", () => new JsonObject { ["model"] = _imageModel, ["input"] = Input(prompt, jpeg), ["safety_settings"] = SafetyOff() }),
            ("sem ajustes de filtro", () => new JsonObject { ["model"] = _imageModel, ["input"] = Input(prompt, jpeg) }),
        };
        var data = await PostVariants(variants, _imageModel, ProviderGate.Image(Models.ProviderKind.Gemini), ct);
        var obj = Http.Json(data);
        var img = FindImage(obj);
        if (img != null) return img;
        var text = FindText(obj);
        var reason = BlockReason(obj);
        throw new AIError(text.Length == 0
                ? "O Gemini não devolveu imagem (pode ter sido bloqueado pelo filtro de segurança)."
                : $"O Gemini não devolveu imagem: {text[..Math.Min(200, text.Length)]}",
            AIErrorKind.Blocked,
            details: $"Gemini · {_imageModel}{(reason != null ? $" · motivo: {reason}" : "")}\nResposta: {Encoding.UTF8.GetString(data, 0, Math.Min(700, data.Length))}");
    }

    public async Task<string> Analyze(byte[] jpeg, string prompt, CancellationToken ct = default)
    {
        var variants = new List<(string, Func<JsonObject>)>
        {
            ("completo", () => new JsonObject { ["model"] = _textModel, ["input"] = Input(prompt, jpeg), ["safety_settings"] = SafetyOff() }),
            ("sem ajustes de filtro", () => new JsonObject { ["model"] = _textModel, ["input"] = Input(prompt, jpeg) }),
        };
        var obj = Http.Json(await PostVariants(variants, _textModel, ProviderGate.Text(Models.ProviderKind.Gemini), ct));
        var text = FindText(obj);
        if (text.Length == 0) throw new AIError("O Gemini não devolveu a análise.", AIErrorKind.Blocked);
        return text;
    }

    public async Task<string> Complete(string prompt, CancellationToken ct = default)
    {
        var variants = new List<(string, Func<JsonObject>)>
        {
            ("completo", () => new JsonObject { ["model"] = _textModel, ["input"] = Input(prompt, null), ["safety_settings"] = SafetyOff() }),
            ("sem ajustes de filtro", () => new JsonObject { ["model"] = _textModel, ["input"] = Input(prompt, null) }),
        };
        var obj = Http.Json(await PostVariants(variants, _textModel, ProviderGate.Text(Models.ProviderKind.Gemini), ct));
        var text = FindText(obj);
        if (text.Length == 0) throw new AIError("O Gemini não devolveu resposta.", AIErrorKind.Blocked);
        return text;
    }

    /// <summary>Envia a primeira variante; em HTTP 400 "pedido inválido" passa para a seguinte.</summary>
    private async Task<byte[]> PostVariants(List<(string Label, Func<JsonObject> Body)> variants, string model, ProviderGate gate, CancellationToken ct)
    {
        Exception? lastError = null;
        for (var i = 0; i < variants.Count; i++)
        {
            try
            {
                return await Post(variants[i].Body(), model, gate, ct);
            }
            catch (AIError e) when (e.Status == 400 && e.Kind == AIErrorKind.BadRequest && i < variants.Count - 1)
            {
                RequestContext.Current?.Log(LogLevel.Info, $"Gemini recusou o pedido {variants[i].Label}; repetindo com {variants[i + 1].Label}.", e.Details);
                lastError = e;
            }
        }
        throw lastError ?? new AIError("O Gemini não respondeu.");
    }

    public async Task TestKey(CancellationToken ct = default)
    {
        var req = new HttpRequestMessage(HttpMethod.Get, "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1");
        req.Headers.TryAddWithoutValidation("x-goog-api-key", _apiKey);
        await Http.Send(req, "Gemini · teste da chave", attempts: 1, ct: ct);
    }

    private Task<byte[]> Post(JsonObject body, string model, ProviderGate gate, CancellationToken ct)
    {
        var bytes = Encoding.UTF8.GetBytes(body.ToJsonString());
        return Http.Send(() =>
        {
            var req = new HttpRequestMessage(HttpMethod.Post, Endpoint) { Content = new ByteArrayContent(bytes) };
            req.Content.Headers.ContentType = new MediaTypeHeaderValue("application/json");
            req.Headers.TryAddWithoutValidation("x-goog-api-key", _apiKey);
            return req;
        }, $"Gemini · {model}", gate, ct: ct);
    }

    /// <summary>Bloqueio do filtro de saída de imagem do Google ("image_safety"), que não é ajustável.</summary>
    public static bool IsImageSafety(AIError e)
    {
        var text = (e.Message + " " + (e.Details ?? "")).ToLowerInvariant();
        return text.Contains("image_safety") || text.Contains("image generation blocked");
    }

    private static string? AsString(JsonNode? n) => n is JsonValue v && v.TryGetValue<string>(out var s) ? s : null;

    /// <summary>Motivo de bloqueio quando o Gemini informa (finishReason / blockReason).</summary>
    public static string? BlockReason(JsonNode? obj)
    {
        string? found = null;
        void Walk(JsonNode? v)
        {
            if (found != null) return;
            if (v is JsonObject d)
            {
                foreach (var key in new[] { "blockReason", "block_reason", "finishReason", "finish_reason", "status" })
                {
                    var s = AsString(d[key]);
                    if (s != null && s is not ("STOP" or "completed" or "COMPLETED")) { found = $"{key}={s}"; return; }
                }
                foreach (var (_, child) in d) Walk(child);
            }
            else if (v is JsonArray a) foreach (var c in a) Walk(c);
        }
        Walk(obj);
        return found;
    }

    // MARK: leitura da resposta (tolerante a variações de formato)

    /// <summary>Procura a última imagem na resposta: output_image, steps[].content[] ou inlineData (formato antigo).</summary>
    public static byte[]? FindImage(JsonNode? obj)
    {
        if (obj is JsonObject d)
        {
            if (d["output_image"] is JsonObject o && AsString(o["data"]) is string s0 && Http.DecodeBase64(s0) is byte[] i0) return i0;
            // imagens finais ficam em steps do tipo model_output (as de "thought" são rascunhos)
            if (d["steps"] is JsonArray steps)
            {
                byte[]? last = null;
                foreach (var step in steps.OfType<JsonObject>().Where(st => AsString(st["type"]) == "model_output"))
                    foreach (var c in (step["content"] as JsonArray ?? new JsonArray()).OfType<JsonObject>().Where(c => AsString(c["type"]) == "image"))
                        if (AsString(c["data"]) is string s && Http.DecodeBase64(s) is byte[] img) last = img;
                if (last != null) return last;
            }
        }
        byte[]? found = null;
        void Walk(JsonNode? v)
        {
            if (v is JsonObject o)
            {
                if (AsString(o["type"]) == "image" && AsString(o["data"]) is string s1 && Http.DecodeBase64(s1) is byte[] a) found = a;
                if (o["output_image"] is JsonObject oi && AsString(oi["data"]) is string s2 && Http.DecodeBase64(s2) is byte[] b) found = b;
                if ((o["inlineData"] ?? o["inline_data"]) is JsonObject inl && AsString(inl["data"]) is string s3 && Http.DecodeBase64(s3) is byte[] c) found = c;
                foreach (var (k, child) in o) if (k != "output_image") Walk(child);
            }
            else if (v is JsonArray arr) foreach (var x in arr) Walk(x);
        }
        Walk(obj);
        return found;
    }

    /// <summary>Junta o texto da saída do modelo (ignorando resumos de "pensamento").</summary>
    public static string FindText(JsonNode? obj)
    {
        if (obj is not JsonObject d) return "";
        if (AsString(d["output_text"]) is { Length: > 0 } t) return t;
        var parts = new List<string>();
        if (d["steps"] is JsonArray steps)
            foreach (var step in steps.OfType<JsonObject>().Where(st => AsString(st["type"]) == "model_output"))
                foreach (var c in (step["content"] as JsonArray ?? new JsonArray()).OfType<JsonObject>().Where(c => AsString(c["type"]) == "text"))
                    if (AsString(c["text"]) is string s) parts.Add(s);
        if (parts.Count == 0 && d["candidates"] is JsonArray cands)
            foreach (var c in cands.OfType<JsonObject>())
                foreach (var p in ((c["content"] as JsonObject)?["parts"] as JsonArray ?? new JsonArray()).OfType<JsonObject>())
                    if (AsString(p["text"]) is string s) parts.Add(s);
        return string.Join("\n", parts);
    }
}
