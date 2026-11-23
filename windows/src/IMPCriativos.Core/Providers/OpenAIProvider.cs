using System.Net.Http.Headers;
using System.Text;
using System.Text.Json.Nodes;
using IMPCriativos.Core.Models;
using IMPCriativos.Core.Pipeline;
using IMPCriativos.Core.Storage;

namespace IMPCriativos.Core.Providers;

/// <summary>OpenAI: edição em /v1/images/edits (gpt-image-2) e análise em /v1/chat/completions (gpt-5-mini).</summary>
public sealed class OpenAIProvider : IAIProvider
{
    private readonly string _apiKey;
    private readonly string _imageModel;
    private readonly string _textModel;
    private readonly string _quality;

    public OpenAIProvider(string apiKey, string imageModel, string textModel, string quality)
    {
        _apiKey = apiKey;
        _imageModel = imageModel;
        _textModel = textModel;
        _quality = quality;
    }

    public async Task<byte[]> EditImage(byte[] jpeg, string prompt, string aspectRatio, CancellationToken ct = default)
    {
        try
        {
            return await EditOnce(jpeg, prompt, aspectRatio, ct);
        }
        catch (AIError e) when (e.Kind == AIErrorKind.Blocked)
        {
            // Bloqueio por conteúdo: uma nova tentativa com a instrução reformulada em tom neutro.
            RequestContext.Current?.Log(LogLevel.Info, "OpenAI bloqueou o pedido; tentando de novo com instrução neutra.", e.Details);
            RequestContext.Current?.OnStatus?.Invoke("OpenAI bloqueou · tentando com instrução neutra…", null);
            return await EditOnce(jpeg, Prompts.Neutral(prompt), aspectRatio, ct);
        }
    }

    private async Task<byte[]> EditOnce(byte[] jpeg, string prompt, string aspectRatio, CancellationToken ct)
    {
        // Formatos verticais (4:5, 9:16) saem em retrato; a exportação ajusta para 1080×1350 ou 1080×1920.
        var vertical = aspectRatio is "4:5" or "9:16" or "3:4" or "2:3";
        // moderation "low" = filtro menos restritivo que a OpenAI permite. Se o modelo recusar
        // algum campo (HTTP 400), tenta sem ele.
        var variants = new List<(string Label, string Size, bool Low)>();
        if (vertical) variants.Add(("vertical", "1024x1536", true));
        variants.Add(("tamanho automático", "auto", true));
        variants.Add(("sem ajuste de moderação", vertical ? "1024x1536" : "auto", false));
        Exception? lastError = null;
        for (var i = 0; i < variants.Count; i++)
        {
            try
            {
                return await Edit(jpeg, prompt, variants[i].Size, variants[i].Low, ct);
            }
            catch (AIError e) when (e.Status == 400 && e.Kind == AIErrorKind.BadRequest && i < variants.Count - 1)
            {
                RequestContext.Current?.Log(LogLevel.Info, $"OpenAI recusou o pedido ({variants[i].Label}); repetindo com {variants[i + 1].Label}.", e.Details);
                lastError = e;
            }
        }
        throw lastError ?? new AIError("A OpenAI não respondeu.");
    }

    private async Task<byte[]> Edit(byte[] jpeg, string prompt, string size, bool lowModeration, CancellationToken ct)
    {
        var form = new Multipart();
        form.Field("model", _imageModel);
        form.Field("prompt", prompt);
        form.Field("size", size);
        if (lowModeration) form.Field("moderation", "low");
        if (_quality.Length > 0) form.Field("quality", _quality);
        form.File("image", "criativo.jpg", "image/jpeg", jpeg);
        var body = form.Finish();
        var type = form.ContentType;

        var obj = Http.Json(await Http.Send(() =>
        {
            var req = new HttpRequestMessage(HttpMethod.Post, "https://api.openai.com/v1/images/edits") { Content = new ByteArrayContent(body) };
            req.Content.Headers.TryAddWithoutValidation("Content-Type", type);
            req.Headers.TryAddWithoutValidation("Authorization", $"Bearer {_apiKey}");
            return req;
        }, $"OpenAI · {_imageModel}", ProviderGate.Image(ProviderKind.Openai), ct: ct));
        if (obj is not JsonObject d || (d["data"] as JsonArray)?.FirstOrDefault() is not JsonObject first)
            throw new AIError("A OpenAI não devolveu imagem.", AIErrorKind.Blocked);
        if (first["b64_json"] is JsonValue b && b.TryGetValue<string>(out var b64) && Http.DecodeBase64(b64) is byte[] img) return img;
        if (first["url"] is JsonValue u && u.TryGetValue<string>(out var url) && Uri.TryCreate(url, UriKind.Absolute, out var uri))
            return await Http.Send(() => new HttpRequestMessage(HttpMethod.Get, uri), "OpenAI · download da imagem", ct: ct);
        throw new AIError("A OpenAI não devolveu imagem.", AIErrorKind.Blocked);
    }

    private async Task<string> Chat(JsonObject body, string failMessage, CancellationToken ct)
    {
        var bytes = Encoding.UTF8.GetBytes(body.ToJsonString());
        var obj = Http.Json(await Http.Send(() =>
        {
            var req = new HttpRequestMessage(HttpMethod.Post, "https://api.openai.com/v1/chat/completions") { Content = new ByteArrayContent(bytes) };
            req.Content.Headers.ContentType = new MediaTypeHeaderValue("application/json");
            req.Headers.TryAddWithoutValidation("Authorization", $"Bearer {_apiKey}");
            return req;
        }, $"OpenAI · {_textModel}", ProviderGate.Text(ProviderKind.Openai), ct: ct));
        var text = ((obj as JsonObject)?["choices"] as JsonArray)?.FirstOrDefault()?["message"]?["content"];
        if (text is JsonValue v && v.TryGetValue<string>(out var s) && s.Length > 0) return s;
        throw new AIError(failMessage, AIErrorKind.Blocked);
    }

    public Task<string> Analyze(byte[] jpeg, string prompt, CancellationToken ct = default) =>
        Chat(new JsonObject
        {
            ["model"] = _textModel,
            ["response_format"] = new JsonObject { ["type"] = "json_object" },
            ["messages"] = new JsonArray
            {
                new JsonObject
                {
                    ["role"] = "user",
                    ["content"] = new JsonArray
                    {
                        new JsonObject { ["type"] = "text", ["text"] = prompt },
                        new JsonObject
                        {
                            ["type"] = "image_url",
                            ["image_url"] = new JsonObject { ["url"] = $"data:image/jpeg;base64,{Convert.ToBase64String(jpeg)}" },
                        },
                    },
                },
            },
        }, "A OpenAI não devolveu a análise.", ct);

    public Task<string> Complete(string prompt, CancellationToken ct = default) =>
        Chat(new JsonObject
        {
            ["model"] = _textModel,
            ["response_format"] = new JsonObject { ["type"] = "json_object" },
            ["messages"] = new JsonArray { new JsonObject { ["role"] = "user", ["content"] = prompt } },
        }, "A OpenAI não devolveu resposta.", ct);

    public async Task TestKey(CancellationToken ct = default)
    {
        var req = new HttpRequestMessage(HttpMethod.Get, "https://api.openai.com/v1/models");
        req.Headers.TryAddWithoutValidation("Authorization", $"Bearer {_apiKey}");
        await Http.Send(req, "OpenAI · teste da chave", attempts: 1, ct: ct);
    }
}
