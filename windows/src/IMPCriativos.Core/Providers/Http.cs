using System.Globalization;
using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json.Nodes;
using IMPCriativos.Core.Models;
using IMPCriativos.Core.Storage;

namespace IMPCriativos.Core.Providers;

/// <summary>Tipo do erro: decide se vale tentar de novo, se cabe trocar de IA e o que mostrar na tela.</summary>
public enum AIErrorKind { Temporary, RateLimit, Network, Timeout, Blocked, Auth, Model, BadRequest, Other }

public static class AIErrorKindExt
{
    /// <summary>Erros que costumam passar sozinhos: servidor ocupado, limite por minuto, internet.</summary>
    public static bool IsTemporary(this AIErrorKind k) =>
        k is AIErrorKind.Temporary or AIErrorKind.RateLimit or AIErrorKind.Network or AIErrorKind.Timeout;

    public static string Title(this AIErrorKind k) => k switch
    {
        AIErrorKind.Temporary => "IA sobrecarregada (temporário)",
        AIErrorKind.RateLimit => "Limite de uso atingido (temporário)",
        AIErrorKind.Network => "Falha de conexão (temporário)",
        AIErrorKind.Timeout => "Tempo esgotado (temporário)",
        AIErrorKind.Blocked => "Bloqueado pelo filtro de conteúdo da IA",
        AIErrorKind.Auth => "Chave de API inválida ou sem permissão",
        AIErrorKind.Model => "Modelo não encontrado",
        AIErrorKind.BadRequest => "Pedido recusado pela IA",
        _ => "Erro",
    };

    /// <summary>O que fazer a respeito.</summary>
    public static string Hint(this AIErrorKind k) => k switch
    {
        AIErrorKind.Temporary => "O servidor da IA estava cheio. Tente de novo em alguns minutos ou refaça com a outra IA.",
        AIErrorKind.RateLimit => "Sua conta atingiu o limite por minuto ou a cota. Espere um pouco, diminua os pedidos simultâneos ou confira o faturamento.",
        AIErrorKind.Network => "Confira a internet do computador e tente de novo.",
        AIErrorKind.Timeout => "A IA não respondeu dentro do tempo limite (servidor lento ou travado). Tente de novo ou refaça com a outra IA.",
        AIErrorKind.Blocked => "A IA recusou a imagem ou o pedido. Refaça com a outra IA ou deixe a instrução do cliente mais neutra.",
        AIErrorKind.Auth => "Confira a chave em Configurações → Chaves de API e use o botão Testar.",
        AIErrorKind.Model => "Confira o nome do modelo em Configurações → Modelos de IA (ou restaure os padrões).",
        _ => "Copie o erro no Histórico e cole na conversa com o Claude para investigar.",
    };

    public static AIErrorKind Classify(int status, string message)
    {
        var m = message.ToLowerInvariant();
        string[] blockedWords = { "safety", "blocked", "moderation", "content policy", "prohibited", "content_filter", "violat", "responsible ai" };
        if (status == 408 || (status >= 500 && status <= 599)) return AIErrorKind.Temporary;
        if (status == 429) return AIErrorKind.RateLimit;
        if (status is 401 or 403) return AIErrorKind.Auth;
        if (status == 404) return AIErrorKind.Model;
        if (status is 400 or 422)
        {
            // campo desconhecido/valor inválido (ex.: "safety_settings" ou "moderation" que o modelo não aceita)
            // é pedido inválido, não bloqueio — assim o app tenta de novo sem o campo.
            string[] fieldWords = { "unknown name", "unknown parameter", "unrecognized", "invalid json payload", "invalid value", "not supported", "unsupported" };
            if (fieldWords.Any(m.Contains)) return AIErrorKind.BadRequest;
            if (blockedWords.Any(m.Contains)) return AIErrorKind.Blocked;
            if (m.Contains("api key") || m.Contains("api_key")) return AIErrorKind.Auth;
            return AIErrorKind.BadRequest;
        }
        return AIErrorKind.Other;
    }
}

public sealed class AIError : Exception
{
    public AIErrorKind Kind { get; }
    public int? Status { get; }
    /// <summary>Dados técnicos para o histórico (modelo, endereço, código, trecho da resposta).</summary>
    public string? Details { get; }

    public AIError(string message, AIErrorKind kind = AIErrorKind.Other, int? status = null, string? details = null)
        : base(message)
    {
        Kind = kind;
        Status = status;
        Details = details;
    }

    public bool Retryable => Kind.IsTemporary();
}

public static class ErrorExt
{
    /// <summary>Tipo do erro (erros que não vieram da IA contam como "outro").</summary>
    public static AIErrorKind AiKind(this Exception e) => (e as AIError)?.Kind ?? AIErrorKind.Other;
    public static string? AiDetails(this Exception e) => (e as AIError)?.Details;
}

/// <summary>
/// Contexto da chamada em andamento (qual lote, qual criativo, qual etapa).
/// Vai junto com a tarefa assíncrona (<see cref="AsyncLocal{T}"/>) sem precisar passar parâmetro por todas as funções.
/// </summary>
public sealed record RequestContext
{
    public Guid? JobID { get; init; }
    public string? JobName { get; init; }
    public string? Item { get; init; }
    public string Step { get; init; } = "";
    public LogCategory Category { get; init; } = LogCategory.Ia;
    public int MaxAttempts { get; init; } = 6;
    /// <summary>1.0.0-beta.9: tempo máximo de cada tentativa, em segundos (null = padrão do tipo de pedido).</summary>
    public double? Timeout { get; init; }
    /// <summary>Avisa a tela: (texto, até quando) — null limpa o aviso.</summary>
    public Action<string?, DateTime?>? OnStatus { get; init; }

    private static readonly AsyncLocal<RequestContext?> CurrentLocal = new();

    public static RequestContext? Current => CurrentLocal.Value;

    /// <summary>Roda <paramref name="op"/> com este contexto (como o <c>$current.withValue</c> do Swift).</summary>
    public static async Task<T> With<T>(RequestContext ctx, Func<Task<T>> op)
    {
        var previous = CurrentLocal.Value;
        CurrentLocal.Value = ctx;
        try { return await op(); }
        finally { CurrentLocal.Value = previous; }
    }

    public void Log(LogLevel level, string message, string? details = null)
    {
        var prefix = Step.Length == 0 ? "" : $"{Step}: ";
        ActivityLog.Shared.Add(level, Category, prefix + message, details, JobID, JobName, Item);
    }
}

public static class Http
{
    /// <summary>1.0.0-beta.9: tempos máximos por tentativa.</summary>
    public const double AnalysisTimeout = 90;
    public const double PlannerTimeout = 240;
    public const double ImageTimeout = 300;
    /// <summary>Pedido de texto que passa disso entra no Histórico com o tempo que levou.</summary>
    public const double SlowTextSeconds = 45;

    /// <summary>Sem tempo definido pelo lote: imagem 5 min, texto 4 min, resto 2 min.</summary>
    public static double DefaultTimeout(ProviderGate? gate) => gate == null ? 120 : gate.IsImage ? ImageTimeout : PlannerTimeout;

    public static string Duration(double seconds)
    {
        var s = (int)Math.Round(seconds, MidpointRounding.AwayFromZero);
        return s < 60 ? $"{s}s" : $"{s / 60}min {s % 60:00}s";
    }

    public static readonly HttpClient Client = CreateClient();

    private static HttpClient CreateClient()
    {
        var handler = new SocketsHttpHandler
        {
            PooledConnectionLifetime = TimeSpan.FromMinutes(5),
            AutomaticDecompression = DecompressionMethods.All,
        };
        var c = new HttpClient(handler) { Timeout = System.Threading.Timeout.InfiniteTimeSpan };
        c.DefaultRequestHeaders.UserAgent.ParseAdd("IMP-Criativos-Windows");
        return c;
    }

    /// <summary>
    /// Espera antes da próxima tentativa: cresce a cada falha, com variação aleatória
    /// (para vários pedidos não voltarem todos no mesmo segundo) e respeita o Retry-After do servidor.
    /// </summary>
    public static double Backoff(int attempt, double? retryAfter)
    {
        double[] baseDelays = { 2, 5, 10, 20, 40, 60 };
        var b = baseDelays[Math.Min(Math.Max(attempt - 1, 0), baseDelays.Length - 1)];
        var delay = b * (0.8 + Random.Shared.NextDouble() * 0.5);
        if (retryAfter is double ra && ra > delay) delay = ra;
        return Math.Min(delay, 90);
    }

    /// <summary>Uma cópia nova do pedido para cada tentativa (o .NET não reenvia o mesmo objeto).</summary>
    public static Func<HttpRequestMessage> Factory(HttpRequestMessage request)
    {
        byte[]? body = null;
        MediaTypeHeaderValue? type = null;
        if (request.Content != null)
        {
            body = request.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult();
            type = request.Content.Headers.ContentType;
        }
        var headers = request.Headers.Select(h => (h.Key, h.Value.ToArray())).ToList();
        var method = request.Method;
        var uri = request.RequestUri;
        return () =>
        {
            var r = new HttpRequestMessage(method, uri);
            foreach (var (k, v) in headers) r.Headers.TryAddWithoutValidation(k, v);
            if (body != null)
            {
                r.Content = new ByteArrayContent(body);
                if (type != null) r.Content.Headers.ContentType = type;
            }
            return r;
        };
    }

    public static Task<byte[]> Send(HttpRequestMessage request, string label = "", ProviderGate? gate = null, int? attempts = null,
        CancellationToken ct = default) => Send(Factory(request), label, gate, attempts, ct);

    /// <summary>
    /// Envia a requisição. Em erro temporário (429, 5xx, rede) tenta de novo com espera crescente.
    /// - label: "Gemini · modelo", usado nos avisos e no histórico.
    /// - gate: limita quantos pedidos vão ao mesmo tempo para a mesma IA e segura os outros quando ela está sobrecarregada.
    /// - attempts: força um número de tentativas (senão usa o do contexto do lote, ou 4).
    /// </summary>
    public static async Task<byte[]> Send(Func<HttpRequestMessage> make, string label = "", ProviderGate? gate = null,
        int? attempts = null, CancellationToken ct = default)
    {
        var ctx = RequestContext.Current;
        var maxAttempts = Math.Max(1, attempts ?? ctx?.MaxAttempts ?? 4);
        var sample = make();
        var host = sample.RequestUri?.Host ?? "servidor";
        var path = sample.RequestUri?.AbsolutePath ?? "";
        var methodName = sample.Method.Method;
        sample.Dispose();
        var name = label.Length == 0 ? host : label;
        var shortName = name.Split(" · ")[0];
        var lastError = new AIError("Falha desconhecida");
        var timeout = ctx?.Timeout ?? DefaultTimeout(gate);

        for (var attempt = 1; attempt <= maxAttempts; attempt++)
        {
            double? retryAfter = null;
            var started = DateTime.UtcNow;
            try
            {
                if (gate != null)
                    await gate.Acquire((seconds, until) => ctx?.OnStatus?.Invoke($"{shortName} ocupado — aguardando vez ({seconds}s)", until), ct);
                HttpResponseMessage response;
                byte[] data;
                using var deadline = CancellationTokenSource.CreateLinkedTokenSource(ct);
                deadline.CancelAfter(TimeSpan.FromSeconds(timeout));
                try
                {
                    using var req = make();
                    response = await Client.SendAsync(req, HttpCompletionOption.ResponseContentRead, deadline.Token);
                    data = await response.Content.ReadAsByteArrayAsync(deadline.Token);
                }
                catch (OperationCanceledException) when (!ct.IsCancellationRequested)
                {
                    gate?.Release();
                    throw new TimeoutException();
                }
                catch
                {
                    gate?.Release();
                    throw;
                }
                gate?.Release();

                var status = (int)response.StatusCode;
                if (status >= 200 && status < 300)
                {
                    var took = (DateTime.UtcNow - started).TotalSeconds;
                    // 1.0.0-beta.19: o Modo rápido com segurança mede o tempo de cada imagem
                    gate?.ReportSuccess(took);
                    if (gate != null && !gate.IsImage && took > SlowTextSeconds)
                        ctx?.Log(LogLevel.Info, $"{name} respondeu, mas demorou {Duration(took)}.");
                    if (attempt > 1)
                    {
                        ctx?.Log(LogLevel.Success, $"{name} respondeu na tentativa {attempt} de {maxAttempts}.");
                        ctx?.OnStatus?.Invoke(null, null);
                    }
                    return data;
                }
                var raw = ApiErrorMessage(data) ?? $"HTTP {status}";
                var kind = AIErrorKindExt.Classify(status, raw);
                if (response.Headers.TryGetValues("Retry-After", out var ras) &&
                    double.TryParse(ras.FirstOrDefault()?.Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out var secsRa))
                    retryAfter = secsRa;
                var secs = (DateTime.UtcNow - started).TotalSeconds.ToString("0.0", CultureInfo.InvariantCulture);
                var details = $"""
                    {name} · {methodName} {host}{path}
                    HTTP {status} · {secs}s · tentativa {attempt}/{maxAttempts}
                    Resposta: {Encoding.UTF8.GetString(data, 0, Math.Min(700, data.Length))}
                    """;
                var err = new AIError($"{raw} (HTTP {status})", kind, status, details);
                if (!kind.IsTemporary()) throw err;
                lastError = err;
                // servidor cheio: segura também os outros pedidos para esta IA
                if (gate != null && kind is AIErrorKind.Temporary or AIErrorKind.RateLimit)
                {
                    gate.Pause(Backoff(attempt, retryAfter) * 0.7);
                    gate.ReportTrouble($"{shortName} respondeu {(kind == AIErrorKind.RateLimit ? "limite de uso" : "ocupado")} (HTTP {status})");
                }
            }
            catch (AIError e)
            {
                if (!e.Retryable) throw;
                lastError = e;
                gate?.ReportTrouble($"{shortName}: {e.Kind.Title().ToLowerInvariant()}");
            }
            catch (OperationCanceledException) when (ct.IsCancellationRequested)
            {
                throw;
            }
            catch (TimeoutException)
            {
                lastError = TimeoutError(name, host, attempt, maxAttempts, timeout, null);
                gate?.ReportTrouble($"{shortName} não respondeu em {Duration(timeout)}");
            }
            catch (Exception e)
            {
                lastError = new AIError($"Erro de conexão: {e.Message}", AIErrorKind.Network,
                    details: $"{name} · {host} · tentativa {attempt}/{maxAttempts}\n{e}");
                gate?.ReportTrouble($"falha de conexão com {shortName}");
            }

            if (attempt >= maxAttempts) break;
            var delay = Backoff(attempt, retryAfter);
            var code = lastError.Status is int st ? $" ({st})" : "";
            ctx?.Log(LogLevel.Warning,
                $"{name}: {lastError.Kind.Title()}{code}. Tentativa {attempt} de {maxAttempts}; nova tentativa em {(int)Math.Round(delay, MidpointRounding.AwayFromZero)}s.",
                lastError.Details);
            var state = lastError.Kind == AIErrorKind.Network ? "sem conexão" : lastError.Kind == AIErrorKind.Timeout ? "não respondeu" : "ocupado";
            ctx?.OnStatus?.Invoke($"{shortName} {state}{code} · tentativa {attempt + 1}/{maxAttempts}", DateTime.UtcNow.AddSeconds(delay));
            await Task.Delay(TimeSpan.FromSeconds(delay), ct);
        }
        ctx?.OnStatus?.Invoke(null, null);
        if (maxAttempts > 1)
            throw new AIError($"{lastError.Message} — desistiu após {maxAttempts} tentativas", lastError.Kind, lastError.Status, lastError.Details);
        throw lastError;
    }

    private static AIError TimeoutError(string name, string host, int attempt, int maxAttempts, double timeout, Exception? underlying) =>
        new($"A IA não respondeu em {Duration(timeout)}", AIErrorKind.Timeout,
            details: $"{name} · {host} · tentativa {attempt}/{maxAttempts} · limite {Duration(timeout)}" +
                     (underlying != null ? $"\n{underlying}" : ""));

    public static string? ApiErrorMessage(byte[] data)
    {
        JsonNode? obj = null;
        try { obj = JsonNode.Parse(data); } catch { }
        if (obj is not JsonObject o)
        {
            var s = Encoding.UTF8.GetString(data, 0, Math.Min(300, data.Length));
            return s.Length == 0 ? null : s;
        }
        if (o["error"] is JsonObject err && err["message"] is JsonValue m && m.TryGetValue<string>(out var msg)) return msg;
        if (o["message"] is JsonValue mm && mm.TryGetValue<string>(out var msg2)) return msg2;
        return null;
    }

    public static JsonNode Json(byte[] data)
    {
        try { return JsonNode.Parse(data) ?? throw new Exception(); }
        catch
        {
            throw new AIError("Resposta da IA não é um JSON válido", AIErrorKind.Other,
                details: Encoding.UTF8.GetString(data, 0, Math.Min(700, data.Length)));
        }
    }

    /// <summary>Remove o prefixo "data:image/png;base64," quando vier.</summary>
    public static byte[]? DecodeBase64(string s)
    {
        var i = s.IndexOf("base64,", StringComparison.Ordinal);
        var raw = i >= 0 ? s[(i + 7)..] : s;
        raw = new string(raw.Where(c => char.IsLetterOrDigit(c) || c is '+' or '/' or '=').ToArray());
        try { return Convert.FromBase64String(raw); } catch { return null; }
    }
}

/// <summary>Monta corpo multipart/form-data (usado no endpoint de edição da OpenAI).</summary>
public sealed class Multipart
{
    public string Boundary { get; } = $"IMPBoundary-{Guid.NewGuid().ToString().ToUpperInvariant()}";
    private readonly MemoryStream _body = new();

    public string ContentType => $"multipart/form-data; boundary={Boundary}";

    private void Append(string s) { var b = Encoding.UTF8.GetBytes(s); _body.Write(b, 0, b.Length); }

    public void Field(string name, string value) =>
        Append($"--{Boundary}\r\nContent-Disposition: form-data; name=\"{name}\"\r\n\r\n{value}\r\n");

    public void File(string name, string filename, string mime, byte[] data)
    {
        Append($"--{Boundary}\r\nContent-Disposition: form-data; name=\"{name}\"; filename=\"{filename}\"\r\nContent-Type: {mime}\r\n\r\n");
        _body.Write(data, 0, data.Length);
        Append("\r\n");
    }

    public byte[] Finish()
    {
        Append($"--{Boundary}--\r\n");
        return _body.ToArray();
    }
}

/// <summary>Extrai o primeiro objeto JSON {…} de um texto (a IA às vezes envolve em ```json).</summary>
public static class JsonExtract
{
    public static JsonObject? Object(string text)
    {
        var start = text.IndexOf('{');
        var end = text.LastIndexOf('}');
        if (start < 0 || end < 0 || start >= end) return null;
        try { return JsonNode.Parse(text[start..(end + 1)]) as JsonObject; } catch { return null; }
    }

    public static string Str(JsonObject o, string key) =>
        o[key] is JsonValue v && v.TryGetValue<string>(out var s) ? s : "";

    public static string? OptStr(JsonObject o, string key) =>
        o[key] is JsonValue v && v.TryGetValue<string>(out var s) ? s : null;

    public static bool? Bool(JsonObject o, string key) =>
        o[key] is JsonValue v && v.TryGetValue<bool>(out var b) ? b : null;

    /// <summary>Lista de textos (como <c>as? [String]</c>: se algum item não for texto, devolve null).</summary>
    public static List<string>? Strings(JsonObject o, string key)
    {
        if (o[key] is not JsonArray a) return null;
        var list = new List<string>();
        foreach (var n in a)
        {
            if (n is JsonValue v && v.TryGetValue<string>(out var s)) list.Add(s);
            else return null;
        }
        return list;
    }
}
