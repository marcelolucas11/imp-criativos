import Foundation

/// Fila de cada IA: limita quantos pedidos vão ao mesmo tempo (somando todos os lotes)
/// e, quando a IA responde "ocupado", segura os próximos pedidos por alguns segundos
/// em vez de todos insistirem juntos.
///
/// 1.0.0-beta.19: as filas de imagem têm o Modo rápido com segurança (`SpeedPolicy`): o limite sobe
/// sozinho enquanto a IA responde bem e volta para a velocidade original ao primeiro sinal de risco.
actor ProviderGate {
    let name: String
    /// Fila de pedidos de imagem (define o tempo máximo padrão de cada pedido).
    nonisolated var isImage: Bool { name.contains("imagem") }
    /// Plataforma da fila (para o painel de velocidade).
    nonisolated let provider: ProviderKind
    private var policy: SpeedPolicy
    private var inUse = 0
    private var pausedUntil = Date.distantPast

    init(name: String, provider: ProviderKind, limit: Int) {
        self.name = name
        self.provider = provider
        self.policy = SpeedPolicy(base: limit, ceiling: limit, fast: false)
    }

    static let geminiImage = ProviderGate(name: "Gemini (imagem)", provider: .gemini, limit: 2)
    static let openaiImage = ProviderGate(name: "OpenAI (imagem)", provider: .openai, limit: 2)
    static let geminiText = ProviderGate(name: "Gemini (análise)", provider: .gemini, limit: 4)
    static let openaiText = ProviderGate(name: "OpenAI (análise)", provider: .openai, limit: 4)

    static func image(_ kind: ProviderKind) -> ProviderGate { kind == .gemini ? geminiImage : openaiImage }
    static func text(_ kind: ProviderKind) -> ProviderGate { kind == .gemini ? geminiText : openaiText }
    static var imageGates: [ProviderGate] { [geminiImage, openaiImage] }

    /// Aplica as Configurações às filas de imagem: velocidade original, teto e modo rápido.
    static func configure(imageLimit: Int, fastCeiling: Int, fast: Bool) async {
        for gate in imageGates { await gate.configure(base: imageLimit, ceiling: fastCeiling, fast: fast) }
    }

    /// Sinal de risco do lado do Mac (calor, pouca energia, pouco disco); nil = tudo bem.
    static func setMacHold(_ reason: String?) async {
        for gate in imageGates { await gate.setMacHold(reason) }
    }

    /// Lote sem avanço: as duas filas de imagem voltam à velocidade original.
    static func reportStall(_ reason: String) async {
        for gate in imageGates { await gate.reportTrouble(reason) }
    }

    func configure(base: Int, ceiling: Int, fast: Bool) {
        apply(policy.configure(base: base, ceiling: ceiling, fast: fast))
    }

    func setMacHold(_ reason: String?) {
        let changed = policy.macHold != reason
        apply(policy.setMacHold(reason))
        if changed { publish() }
    }

    /// Quantos pedidos podem ir juntos agora.
    func currentLimit() -> Int { policy.limit }

    func pause(for seconds: TimeInterval) {
        let until = Date().addingTimeInterval(seconds)
        if until > pausedUntil { pausedUntil = until }
    }

    func release() { inUse = max(0, inUse - 1) }

    /// Resposta boa da IA, com o tempo do pedido (só conta nas filas de imagem).
    func reportSuccess(seconds: TimeInterval) {
        guard isImage else { return }
        apply(policy.recordSuccess(seconds: seconds))
    }

    /// IA ocupada, limite, tempo esgotado, conexão ou lote parado.
    func reportTrouble(_ reason: String) {
        guard isImage else { return }
        apply(policy.recordTrouble(reason))
        publish()
    }

    func snapshot() -> SpeedSnapshot {
        SpeedSnapshot(provider: provider, name: name, limit: policy.limit, base: policy.base, ceiling: policy.ceiling,
                      fast: policy.fast, inUse: inUse, risk: policy.risk(), safeUntil: policy.safeUntil,
                      safeReason: policy.safeReason, macHold: policy.macHold,
                      latency: policy.recentLatency, latencyRatio: policy.latencyRatio)
    }

    private func apply(_ change: SpeedPolicy.Change) {
        guard isImage else { return }
        let label = name
        switch change {
        case .none:
            return
        case let .raised(to: n):
            AppLog.info(.ia, "Modo rápido: \(label) subiu para \(n) pedidos ao mesmo tempo (a IA está respondendo bem).")
        case let .lowered(to: n, reason: reason):
            AppLog.warning(.ia, "Segurança: \(label) voltou para \(n) pedidos ao mesmo tempo — \(reason).",
                           details: "Nada é perdido: os pedidos em andamento continuam e os próximos esperam a vez. A velocidade só volta a subir quando o risco passar.")
        }
        publish()
    }

    private func publish() {
        let snap = snapshot()
        Task { @MainActor in SpeedMonitor.shared.update(snap) }
    }

    /// nil = conseguiu a vaga; senão, quantos segundos esperar antes de tentar de novo.
    private func tryAcquire() -> TimeInterval? {
        let wait = pausedUntil.timeIntervalSinceNow
        if wait > 0 { return wait }
        if inUse >= policy.limit { return 0.3 }
        inUse += 1
        return nil
    }

    /// Espera uma vaga. `onWait(segundos, até quando)` é chamado quando a IA está em pausa por estar sobrecarregada.
    nonisolated func acquire(onWait: (@Sendable (Int, Date) -> Void)? = nil) async throws {
        while true {
            try Task.checkCancellation()
            guard let wait = await tryAcquire() else { return }
            if wait > 1.5 {
                onWait?(Int(wait.rounded(.up)), Date().addingTimeInterval(wait))
            }
            try await Task.sleep(nanoseconds: UInt64(min(wait, 1.0) * 1_000_000_000))
        }
    }
}

/// Retrato da fila de imagem de uma IA, para as telas.
struct SpeedSnapshot: Equatable, Sendable {
    let provider: ProviderKind
    let name: String
    let limit: Int
    let base: Int
    let ceiling: Int
    let fast: Bool
    let inUse: Int
    let risk: SpeedPolicy.Risk
    let safeUntil: Date
    let safeReason: String?
    let macHold: String?
    let latency: Double?
    let latencyRatio: Double?

    var inSafeMode: Bool { safeUntil > Date() || macHold != nil }

    /// Uma linha para a tela do lote e as Configurações.
    var line: String {
        let who = provider.label
        if let macHold { return "Segurança: \(who) na velocidade original (\(base) por vez) — \(macHold)." }
        if safeUntil > Date() {
            return "Segurança: \(who) na velocidade original (\(base) por vez) até \(safeUntil.hourMinute)"
                + (safeReason.map { " — \($0)" } ?? "") + "."
        }
        if !fast { return "\(who): \(limit) imagens por vez (modo rápido desligado)." }
        let lat = latency.map { " · ~\(Int($0.rounded()))s por imagem" } ?? ""
        if limit > base { return "Modo rápido: \(who) com \(limit) imagens por vez (teto \(ceiling)) · risco \(risk.label)\(lat)." }
        return "Modo rápido: \(who) com \(limit) imagens por vez, medindo para subir até \(ceiling) · risco \(risk.label)\(lat)."
    }
}

/// Painel de velocidade observado pelas telas (atualizado pelas filas).
@MainActor
final class SpeedMonitor: ObservableObject {
    static let shared = SpeedMonitor()
    @Published private(set) var snapshots: [ProviderKind: SpeedSnapshot] = [:]

    func update(_ s: SpeedSnapshot) { snapshots[s.provider] = s }

    func refresh() async {
        for gate in ProviderGate.imageGates { update(await gate.snapshot()) }
    }

    /// Sinais de risco do próprio Mac. nil = tudo bem.
    nonisolated static func macRisk() -> String? {
        let info = ProcessInfo.processInfo
        switch info.thermalState {
        case .serious, .critical: return "o Mac está quente (macOS pediu para reduzir o esforço)"
        default: break
        }
        if info.isLowPowerModeEnabled { return "modo de pouca energia ligado" }
        if let free = try? Paths.appSupport.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage, free < 2_000_000_000 {
            return "menos de 2 GB livres no disco"
        }
        return nil
    }
}

extension Date {
    var hourMinute: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: self)
    }
}
