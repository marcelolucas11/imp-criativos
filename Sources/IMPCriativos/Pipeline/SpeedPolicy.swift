import Foundation

/// 1.0.0-beta.19 — Modo rápido com segurança automática.
///
/// Decide quantos pedidos de imagem cada IA recebe ao mesmo tempo. Começa na velocidade original
/// (Configurações → "Velocidade original") e sobe um degrau por vez enquanto a IA responde bem.
/// Qualquer sinal de risco devolve à velocidade original e trava a subida por um tempo:
/// - erro temporário (IA ocupada 503, limite 429, tempo esgotado, conexão);
/// - IA ficando lenta demais com mais pedidos (mais pedidos não estão rendendo mais imagens);
/// - Mac sob pressão (calor, modo de pouca energia, pouco disco) ou lote sem avanço.
///
/// Só muda QUANTOS pedidos vão juntos. Modelo, qualidade, prompts, checagens e refações
/// continuam iguais, então a qualidade dos criativos não depende da velocidade.
///
/// Arquivo puro (só Foundation) para rodar nos testes automáticos sem o app.
struct SpeedPolicy: Equatable {
    /// Velocidade original: pedidos de imagem ao mesmo tempo por IA (Configurações).
    private(set) var base: Int
    /// Teto do modo rápido.
    private(set) var ceiling: Int
    /// Modo rápido ligado.
    private(set) var fast: Bool
    /// Pedidos ao mesmo tempo agora.
    private(set) var limit: Int

    /// Respostas boas seguidas no nível atual.
    private(set) var streak = 0
    /// Tempo médio por pedido na velocidade original (referência).
    private(set) var baselineLatency: Double?
    private(set) var baselineSamples = 0
    /// Tempo médio recente por pedido.
    private(set) var recentLatency: Double?
    /// Problemas recentes (para medir o risco e decidir quanto tempo ficar no modo seguro).
    private(set) var troubles: [Date] = []
    /// Até quando a velocidade não sobe (modo seguro).
    private(set) var safeUntil: Date = .distantPast
    private(set) var safeReason: String?
    /// Motivo do lado do Mac que segura a velocidade original (nil = Mac tranquilo).
    private(set) var macHold: String?

    /// Respostas boas seguidas para subir um degrau.
    static let streakToRaise = 3
    /// Amostras na velocidade original antes de começar a subir.
    static let baselineSamplesNeeded = 2
    /// Modo seguro depois de um problema.
    static let safeAfterTrouble: TimeInterval = 10 * 60
    /// Modo seguro mais longo quando os problemas se repetem.
    static let longSafe: TimeInterval = 30 * 60
    static let troubleWindow: TimeInterval = 15 * 60
    static let troublesForLongSafe = 3
    /// Mais pedidos só valem se renderem pelo menos 10% mais imagens por minuto.
    static let minThroughputGain = 1.1
    /// Acima disso, cada pedido está lento demais (risco de estourar o tempo limite), seja qual for o ganho.
    static let maxLatencyRatio = 2.5
    static let emaWeight = 0.3
    /// Depois de descer por lentidão, espera este tempo antes de tentar subir de novo.
    static let slowdownHold: TimeInterval = 5 * 60

    enum Change: Equatable {
        case none
        case raised(to: Int)
        case lowered(to: Int, reason: String)
    }

    enum Risk: Int, Comparable {
        case low, medium, high
        static func < (a: Risk, b: Risk) -> Bool { a.rawValue < b.rawValue }
        var label: String {
            switch self {
            case .low: return "baixo"
            case .medium: return "médio"
            case .high: return "alto"
            }
        }
    }

    init(base: Int, ceiling: Int, fast: Bool) {
        let b = max(1, base)
        self.base = b
        self.ceiling = max(b, ceiling)
        self.fast = fast
        self.limit = b
    }

    // MARK: configuração

    /// Aplica as Configurações sem perder o que já foi aprendido. Desligar o modo rápido volta à velocidade original.
    @discardableResult
    mutating func configure(base newBase: Int, ceiling newCeiling: Int, fast newFast: Bool) -> Change {
        let b = max(1, newBase)
        if b != base {
            // a referência de tempo era da velocidade original antiga
            baselineLatency = nil
            baselineSamples = 0
        }
        base = b
        ceiling = max(b, newCeiling)
        fast = newFast
        let old = limit
        let top = fast ? ceiling : base
        limit = min(max(limit, base), top)
        streak = 0
        if limit < old { return .lowered(to: limit, reason: fast ? "teto do modo rápido reduzido" : "modo rápido desligado") }
        return .none
    }

    // MARK: eventos

    /// Uma resposta boa da IA (imagem gerada), com o tempo que levou.
    @discardableResult
    mutating func recordSuccess(seconds: Double, now: Date = Date()) -> Change {
        let s = max(0.1, seconds)
        recentLatency = recentLatency.map { $0 * (1 - Self.emaWeight) + s * Self.emaWeight } ?? s
        if limit == base {
            baselineLatency = baselineLatency.map { $0 * (1 - Self.emaWeight) + s * Self.emaWeight } ?? s
            baselineSamples += 1
        }
        streak += 1

        // mais pedidos não estão rendendo mais imagens (ou cada pedido ficou lento demais): desce um degrau
        if limit > base, streak >= 2, let ratio = latencyRatio {
            let gain = (Double(limit) / Double(base)) / ratio
            if gain < Self.minThroughputGain || ratio > Self.maxLatencyRatio {
                limit -= 1
                streak = 0
                // não volta a subir logo em seguida (evita ficar subindo e descendo)
                let reason = "a IA ficou mais lenta com mais pedidos (\(String(format: "%.1f", ratio))× o tempo normal)"
                let until = now.addingTimeInterval(Self.slowdownHold)
                if until > safeUntil { safeUntil = until; safeReason = reason }
                return .lowered(to: limit, reason: reason)
            }
        }

        if canRaise(now: now), streak >= Self.streakToRaise {
            limit += 1
            streak = 0
            return .raised(to: limit)
        }
        return .none
    }

    /// Problema que indica risco de travar: IA ocupada, limite, tempo esgotado, conexão, lote parado.
    /// Volta na hora para a velocidade original e trava a subida por 10 minutos (30 se repetir).
    @discardableResult
    mutating func recordTrouble(_ reason: String, now: Date = Date()) -> Change {
        troubles = troubles.filter { now.timeIntervalSince($0) < Self.troubleWindow } + [now]
        let duration = troubles.count >= Self.troublesForLongSafe ? Self.longSafe : Self.safeAfterTrouble
        let until = now.addingTimeInterval(duration)
        if until > safeUntil { safeUntil = until }
        safeReason = reason
        streak = 0
        let old = limit
        limit = base
        return old > base ? .lowered(to: base, reason: reason) : .none
    }

    /// Estado do Mac (calor, pouca energia, pouco disco). Com motivo, fica na velocidade original.
    @discardableResult
    mutating func setMacHold(_ reason: String?) -> Change {
        macHold = reason
        guard let reason, limit > base else { return .none }
        limit = base
        streak = 0
        return .lowered(to: base, reason: reason)
    }

    // MARK: leitura

    var latencyRatio: Double? {
        guard let b = baselineLatency, b > 0, let r = recentLatency else { return nil }
        return r / b
    }

    func isSafeMode(now: Date = Date()) -> Bool { safeUntil > now || macHold != nil }

    func canRaise(now: Date = Date()) -> Bool {
        fast && limit < ceiling && macHold == nil && safeUntil <= now && baselineSamples >= Self.baselineSamplesNeeded
    }

    /// Risco de subir a velocidade agora.
    func risk(now: Date = Date()) -> Risk {
        let lastFive = troubles.filter { now.timeIntervalSince($0) < 5 * 60 }.count
        if macHold != nil || lastFive >= 2 { return .high }
        let recent = troubles.contains { now.timeIntervalSince($0) < Self.troubleWindow }
        if recent || safeUntil > now || (latencyRatio ?? 1) > 1.5 { return .medium }
        return .low
    }
}
