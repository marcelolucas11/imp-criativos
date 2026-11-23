using System.Globalization;

namespace IMPCriativos.Core.Pipeline;

/// <summary>
/// 1.0.0-beta.19 — Modo rápido com segurança automática.
///
/// Decide quantos pedidos de imagem cada IA recebe ao mesmo tempo. Começa na velocidade original
/// (Configurações → "Velocidade original") e sobe um degrau por vez enquanto a IA responde bem.
/// Qualquer sinal de risco devolve à velocidade original e trava a subida por um tempo:
/// - erro temporário (IA ocupada 503, limite 429, tempo esgotado, conexão);
/// - IA ficando lenta demais com mais pedidos (mais pedidos não estão rendendo mais imagens);
/// - computador sob pressão (pouco disco, economia de bateria) ou lote sem avanço.
///
/// Só muda QUANTOS pedidos vão juntos. Modelo, qualidade, prompts, checagens e refações
/// continuam iguais, então a qualidade dos criativos não depende da velocidade.
/// Mesma lógica de <c>Pipeline/SpeedPolicy.swift</c>.
/// </summary>
public sealed class SpeedPolicy
{
    /// <summary>Velocidade original: pedidos de imagem ao mesmo tempo por IA (Configurações).</summary>
    public int Base { get; private set; }
    /// <summary>Teto do modo rápido.</summary>
    public int Ceiling { get; private set; }
    /// <summary>Modo rápido ligado.</summary>
    public bool Fast { get; private set; }
    /// <summary>Pedidos ao mesmo tempo agora.</summary>
    public int Limit { get; private set; }

    /// <summary>Respostas boas seguidas no nível atual.</summary>
    public int Streak { get; private set; }
    /// <summary>Tempo médio por pedido na velocidade original (referência).</summary>
    public double? BaselineLatency { get; private set; }
    public int BaselineSamples { get; private set; }
    /// <summary>Tempo médio recente por pedido.</summary>
    public double? RecentLatency { get; private set; }
    /// <summary>Problemas recentes (para medir o risco e decidir quanto tempo ficar no modo seguro).</summary>
    public List<DateTime> Troubles { get; private set; } = new();
    /// <summary>Até quando a velocidade não sobe (modo seguro).</summary>
    public DateTime SafeUntil { get; private set; } = DateTime.MinValue;
    public string? SafeReason { get; private set; }
    /// <summary>Motivo do lado do computador que segura a velocidade original (null = tranquilo).</summary>
    public string? MacHold { get; private set; }

    /// <summary>Respostas boas seguidas para subir um degrau.</summary>
    public const int StreakToRaise = 3;
    /// <summary>Amostras na velocidade original antes de começar a subir.</summary>
    public const int BaselineSamplesNeeded = 2;
    /// <summary>Modo seguro depois de um problema.</summary>
    public static readonly TimeSpan SafeAfterTrouble = TimeSpan.FromMinutes(10);
    /// <summary>Modo seguro mais longo quando os problemas se repetem.</summary>
    public static readonly TimeSpan LongSafe = TimeSpan.FromMinutes(30);
    public static readonly TimeSpan TroubleWindow = TimeSpan.FromMinutes(15);
    public const int TroublesForLongSafe = 3;
    /// <summary>Mais pedidos só valem se renderem pelo menos 10% mais imagens por minuto.</summary>
    public const double MinThroughputGain = 1.1;
    /// <summary>Acima disso, cada pedido está lento demais (risco de estourar o tempo limite), seja qual for o ganho.</summary>
    public const double MaxLatencyRatio = 2.5;
    public const double EmaWeight = 0.3;
    /// <summary>Depois de descer por lentidão, espera este tempo antes de tentar subir de novo.</summary>
    public static readonly TimeSpan SlowdownHold = TimeSpan.FromMinutes(5);

    public enum Risk { Low, Medium, High }

    public static string RiskLabel(Risk r) => r switch { Risk.Low => "baixo", Risk.Medium => "médio", _ => "alto" };

    public SpeedPolicy(int @base, int ceiling, bool fast)
    {
        var b = Math.Max(1, @base);
        Base = b;
        Ceiling = Math.Max(b, ceiling);
        Fast = fast;
        Limit = b;
    }

    // MARK: configuração

    /// <summary>Aplica as Configurações sem perder o que já foi aprendido. Desligar o modo rápido volta à velocidade original.</summary>
    public SpeedChange Configure(int newBase, int newCeiling, bool newFast)
    {
        var b = Math.Max(1, newBase);
        if (b != Base)
        {
            // a referência de tempo era da velocidade original antiga
            BaselineLatency = null;
            BaselineSamples = 0;
        }
        Base = b;
        Ceiling = Math.Max(b, newCeiling);
        Fast = newFast;
        var old = Limit;
        var top = Fast ? Ceiling : Base;
        Limit = Math.Min(Math.Max(Limit, Base), top);
        Streak = 0;
        if (Limit < old) return SpeedChange.Lowered(Limit, Fast ? "teto do modo rápido reduzido" : "modo rápido desligado");
        return SpeedChange.None;
    }

    // MARK: eventos

    /// <summary>Uma resposta boa da IA (imagem gerada), com o tempo que levou.</summary>
    public SpeedChange RecordSuccess(double seconds, DateTime? now = null)
    {
        var t = now ?? DateTime.UtcNow;
        var s = Math.Max(0.1, seconds);
        RecentLatency = RecentLatency is double r ? r * (1 - EmaWeight) + s * EmaWeight : s;
        if (Limit == Base)
        {
            BaselineLatency = BaselineLatency is double bl ? bl * (1 - EmaWeight) + s * EmaWeight : s;
            BaselineSamples += 1;
        }
        Streak += 1;

        // mais pedidos não estão rendendo mais imagens (ou cada pedido ficou lento demais): desce um degrau
        if (Limit > Base && Streak >= 2 && LatencyRatio is double ratio)
        {
            var gain = ((double)Limit / Base) / ratio;
            if (gain < MinThroughputGain || ratio > MaxLatencyRatio)
            {
                Limit -= 1;
                Streak = 0;
                // não volta a subir logo em seguida (evita ficar subindo e descendo)
                var reason = $"a IA ficou mais lenta com mais pedidos ({ratio.ToString("0.0", CultureInfo.InvariantCulture)}× o tempo normal)";
                var until = t + SlowdownHold;
                if (until > SafeUntil) { SafeUntil = until; SafeReason = reason; }
                return SpeedChange.Lowered(Limit, reason);
            }
        }

        if (CanRaise(t) && Streak >= StreakToRaise)
        {
            Limit += 1;
            Streak = 0;
            return SpeedChange.Raised(Limit);
        }
        return SpeedChange.None;
    }

    /// <summary>
    /// Problema que indica risco de travar: IA ocupada, limite, tempo esgotado, conexão, lote parado.
    /// Volta na hora para a velocidade original e trava a subida por 10 minutos (30 se repetir).
    /// </summary>
    public SpeedChange RecordTrouble(string reason, DateTime? now = null)
    {
        var t = now ?? DateTime.UtcNow;
        Troubles = Troubles.Where(d => t - d < TroubleWindow).Append(t).ToList();
        var duration = Troubles.Count >= TroublesForLongSafe ? LongSafe : SafeAfterTrouble;
        var until = t + duration;
        if (until > SafeUntil) SafeUntil = until;
        SafeReason = reason;
        Streak = 0;
        var old = Limit;
        Limit = Base;
        return old > Base ? SpeedChange.Lowered(Base, reason) : SpeedChange.None;
    }

    /// <summary>Estado do computador (pouco disco, economia de bateria). Com motivo, fica na velocidade original.</summary>
    public SpeedChange SetMacHold(string? reason)
    {
        MacHold = reason;
        if (reason == null || Limit <= Base) return SpeedChange.None;
        Limit = Base;
        Streak = 0;
        return SpeedChange.Lowered(Base, reason);
    }

    // MARK: leitura

    public double? LatencyRatio =>
        BaselineLatency is double b && b > 0 && RecentLatency is double r ? r / b : null;

    public bool IsSafeMode(DateTime? now = null) => SafeUntil > (now ?? DateTime.UtcNow) || MacHold != null;

    public bool CanRaise(DateTime? now = null) =>
        Fast && Limit < Ceiling && MacHold == null && SafeUntil <= (now ?? DateTime.UtcNow) && BaselineSamples >= BaselineSamplesNeeded;

    /// <summary>Risco de subir a velocidade agora.</summary>
    public Risk CurrentRisk(DateTime? now = null)
    {
        var t = now ?? DateTime.UtcNow;
        var lastFive = Troubles.Count(d => t - d < TimeSpan.FromMinutes(5));
        if (MacHold != null || lastFive >= 2) return Risk.High;
        var recent = Troubles.Any(d => t - d < TroubleWindow);
        if (recent || SafeUntil > t || (LatencyRatio ?? 1) > 1.5) return Risk.Medium;
        return Risk.Low;
    }
}

/// <summary>Mudança de velocidade (para o Histórico).</summary>
public sealed record SpeedChange(SpeedChange.Kinds Kind, int To = 0, string Reason = "")
{
    public enum Kinds { None, Raised, Lowered }

    public static readonly SpeedChange None = new(Kinds.None);
    public static SpeedChange Raised(int to) => new(Kinds.Raised, to);
    public static SpeedChange Lowered(int to, string reason) => new(Kinds.Lowered, to, reason);
}
