using IMPCriativos.Core.Models;
using IMPCriativos.Core.Pipeline;
using IMPCriativos.Core.Storage;

namespace IMPCriativos.Core.Providers;

/// <summary>
/// Fila de cada IA: limita quantos pedidos vão ao mesmo tempo (somando todos os lotes)
/// e, quando a IA responde "ocupado", segura os próximos pedidos por alguns segundos
/// em vez de todos insistirem juntos.
///
/// 1.0.0-beta.19: as filas de imagem têm o Modo rápido com segurança (<see cref="SpeedPolicy"/>): o limite sobe
/// sozinho enquanto a IA responde bem e volta para a velocidade original ao primeiro sinal de risco.
/// </summary>
public sealed class ProviderGate
{
    public string Name { get; }
    /// <summary>Fila de pedidos de imagem (define o tempo máximo padrão de cada pedido).</summary>
    public bool IsImage => Name.Contains("imagem");
    /// <summary>Plataforma da fila (para o painel de velocidade).</summary>
    public ProviderKind Provider { get; }

    private readonly object _lock = new();
    private readonly SpeedPolicy _policy;
    private int _inUse;
    private DateTime _pausedUntil = DateTime.MinValue;

    public ProviderGate(string name, ProviderKind provider, int limit)
    {
        Name = name;
        Provider = provider;
        _policy = new SpeedPolicy(limit, limit, false);
    }

    public static readonly ProviderGate GeminiImage = new("Gemini (imagem)", ProviderKind.Gemini, 2);
    public static readonly ProviderGate OpenaiImage = new("OpenAI (imagem)", ProviderKind.Openai, 2);
    public static readonly ProviderGate GeminiText = new("Gemini (análise)", ProviderKind.Gemini, 4);
    public static readonly ProviderGate OpenaiText = new("OpenAI (análise)", ProviderKind.Openai, 4);

    public static ProviderGate Image(ProviderKind kind) => kind == ProviderKind.Gemini ? GeminiImage : OpenaiImage;
    public static ProviderGate Text(ProviderKind kind) => kind == ProviderKind.Gemini ? GeminiText : OpenaiText;
    public static ProviderGate[] ImageGates => new[] { GeminiImage, OpenaiImage };

    /// <summary>Aplica as Configurações às filas de imagem: velocidade original, teto e modo rápido.</summary>
    public static void Configure(int imageLimit, int fastCeiling, bool fast)
    {
        foreach (var g in ImageGates) g.ConfigureGate(imageLimit, fastCeiling, fast);
    }

    /// <summary>Sinal de risco do lado do computador (pouco disco, economia de bateria); null = tudo bem.</summary>
    public static void SetMacHoldAll(string? reason)
    {
        foreach (var g in ImageGates) g.SetMacHold(reason);
    }

    /// <summary>Lote sem avanço: as duas filas de imagem voltam à velocidade original.</summary>
    public static void ReportStall(string reason)
    {
        foreach (var g in ImageGates) g.ReportTrouble(reason);
    }

    public void ConfigureGate(int @base, int ceiling, bool fast)
    {
        SpeedChange c;
        lock (_lock) c = _policy.Configure(@base, ceiling, fast);
        Apply(c);
    }

    public void SetMacHold(string? reason)
    {
        SpeedChange c;
        bool changed;
        lock (_lock)
        {
            changed = _policy.MacHold != reason;
            c = _policy.SetMacHold(reason);
        }
        Apply(c);
        if (changed) Publish();
    }

    /// <summary>Quantos pedidos podem ir juntos agora.</summary>
    public int CurrentLimit()
    {
        lock (_lock) return _policy.Limit;
    }

    public void Pause(double seconds)
    {
        lock (_lock)
        {
            var until = DateTime.UtcNow.AddSeconds(seconds);
            if (until > _pausedUntil) _pausedUntil = until;
        }
    }

    public void Release()
    {
        lock (_lock) _inUse = Math.Max(0, _inUse - 1);
    }

    /// <summary>Resposta boa da IA, com o tempo do pedido (só conta nas filas de imagem).</summary>
    public void ReportSuccess(double seconds)
    {
        if (!IsImage) return;
        SpeedChange c;
        lock (_lock) c = _policy.RecordSuccess(seconds);
        Apply(c);
    }

    /// <summary>IA ocupada, limite, tempo esgotado, conexão ou lote parado.</summary>
    public void ReportTrouble(string reason)
    {
        if (!IsImage) return;
        SpeedChange c;
        lock (_lock) c = _policy.RecordTrouble(reason);
        Apply(c);
        Publish();
    }

    public SpeedSnapshot Snapshot()
    {
        lock (_lock)
            return new SpeedSnapshot(Provider, Name, _policy.Limit, _policy.Base, _policy.Ceiling, _policy.Fast, _inUse,
                _policy.CurrentRisk(), _policy.SafeUntil, _policy.SafeReason, _policy.MacHold, _policy.RecentLatency,
                _policy.LatencyRatio);
    }

    private void Apply(SpeedChange change)
    {
        if (!IsImage) return;
        switch (change.Kind)
        {
            case SpeedChange.Kinds.None:
                return;
            case SpeedChange.Kinds.Raised:
                AppLog.Info(LogCategory.Ia, $"Modo rápido: {Name} subiu para {change.To} pedidos ao mesmo tempo (a IA está respondendo bem).");
                break;
            case SpeedChange.Kinds.Lowered:
                AppLog.Warning(LogCategory.Ia, $"Segurança: {Name} voltou para {change.To} pedidos ao mesmo tempo — {change.Reason}.",
                    details: "Nada é perdido: os pedidos em andamento continuam e os próximos esperam a vez. A velocidade só volta a subir quando o risco passar.");
                break;
        }
        Publish();
    }

    private void Publish() => SpeedMonitor.Shared.Update(Snapshot());

    /// <summary>null = conseguiu a vaga; senão, quantos segundos esperar antes de tentar de novo.</summary>
    private double? TryAcquire()
    {
        lock (_lock)
        {
            var wait = (_pausedUntil - DateTime.UtcNow).TotalSeconds;
            if (wait > 0) return wait;
            if (_inUse >= _policy.Limit) return 0.3;
            _inUse += 1;
            return null;
        }
    }

    /// <summary>Espera uma vaga. <paramref name="onWait"/>(segundos, até quando) é chamado quando a IA está em pausa por estar sobrecarregada.</summary>
    public async Task Acquire(Action<int, DateTime>? onWait = null, CancellationToken ct = default)
    {
        while (true)
        {
            ct.ThrowIfCancellationRequested();
            if (TryAcquire() is not double wait) return;
            if (wait > 1.5) onWait?.Invoke((int)Math.Ceiling(wait), DateTime.UtcNow.AddSeconds(wait));
            await Task.Delay(TimeSpan.FromSeconds(Math.Min(wait, 1.0)), ct);
        }
    }
}

/// <summary>Retrato da fila de imagem de uma IA, para as telas.</summary>
public sealed record SpeedSnapshot(ProviderKind Provider, string Name, int Limit, int Base, int Ceiling, bool Fast, int InUse,
    SpeedPolicy.Risk Risk, DateTime SafeUntil, string? SafeReason, string? MacHold, double? Latency, double? LatencyRatio)
{
    public bool InSafeMode => SafeUntil > DateTime.UtcNow || MacHold != null;

    /// <summary>Uma linha para a tela do lote e as Configurações.</summary>
    public string Line
    {
        get
        {
            var who = Provider.Label();
            if (MacHold != null) return $"Segurança: {who} na velocidade original ({Base} por vez) — {MacHold}.";
            if (SafeUntil > DateTime.UtcNow)
                return $"Segurança: {who} na velocidade original ({Base} por vez) até {SafeUntil.ToLocalTime():HH:mm}" +
                       (SafeReason != null ? $" — {SafeReason}" : "") + ".";
            if (!Fast) return $"{who}: {Limit} imagens por vez (modo rápido desligado).";
            var lat = Latency is double l ? $" · ~{(int)Math.Round(l, MidpointRounding.AwayFromZero)}s por imagem" : "";
            if (Limit > Base) return $"Modo rápido: {who} com {Limit} imagens por vez (teto {Ceiling}) · risco {SpeedPolicy.RiskLabel(Risk)}{lat}.";
            return $"Modo rápido: {who} com {Limit} imagens por vez, medindo para subir até {Ceiling} · risco {SpeedPolicy.RiskLabel(Risk)}{lat}.";
        }
    }
}

/// <summary>Painel de velocidade observado pelas telas (atualizado pelas filas).</summary>
public sealed class SpeedMonitor
{
    public static SpeedMonitor Shared { get; } = new();

    private readonly object _lock = new();
    private readonly Dictionary<ProviderKind, SpeedSnapshot> _snapshots = new();

    public event Action? Changed;

    public Dictionary<ProviderKind, SpeedSnapshot> Snapshots
    {
        get { lock (_lock) return new Dictionary<ProviderKind, SpeedSnapshot>(_snapshots); }
    }

    public void Update(SpeedSnapshot s)
    {
        lock (_lock) _snapshots[s.Provider] = s;
        Changed?.Invoke();
    }

    public void Refresh()
    {
        foreach (var g in ProviderGate.ImageGates) Update(g.Snapshot());
    }

    /// <summary>Verificador de risco do computador (o App troca por um que lê a bateria do Windows).</summary>
    public static Func<string?>? ExtraRisk { get; set; }

    /// <summary>Sinais de risco do próprio computador. null = tudo bem.</summary>
    public static string? MacRisk()
    {
        try
        {
            var extra = ExtraRisk?.Invoke();
            if (extra != null) return extra;
            var root = Path.GetPathRoot(Paths.AppSupport);
            if (!string.IsNullOrEmpty(root))
            {
                var drive = new DriveInfo(root);
                if (drive.IsReady && drive.AvailableFreeSpace < 2_000_000_000) return "menos de 2 GB livres no disco";
            }
        }
        catch { }
        return null;
    }
}
