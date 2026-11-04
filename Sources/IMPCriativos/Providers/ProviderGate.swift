import Foundation

/// Fila de cada IA: limita quantos pedidos vão ao mesmo tempo (somando todos os lotes)
/// e, quando a IA responde "ocupado", segura os próximos pedidos por alguns segundos
/// em vez de todos insistirem juntos.
actor ProviderGate {
    let name: String
    private var limit: Int
    private var inUse = 0
    private var pausedUntil = Date.distantPast

    init(name: String, limit: Int) {
        self.name = name
        self.limit = max(1, limit)
    }

    static let geminiImage = ProviderGate(name: "Gemini (imagem)", limit: 2)
    static let openaiImage = ProviderGate(name: "OpenAI (imagem)", limit: 2)
    static let geminiText = ProviderGate(name: "Gemini (análise)", limit: 4)
    static let openaiText = ProviderGate(name: "OpenAI (análise)", limit: 4)

    static func image(_ kind: ProviderKind) -> ProviderGate { kind == .gemini ? geminiImage : openaiImage }
    static func text(_ kind: ProviderKind) -> ProviderGate { kind == .gemini ? geminiText : openaiText }

    /// Aplica o limite das Configurações às filas de imagem.
    static func configure(imageLimit: Int) async {
        await geminiImage.setLimit(imageLimit)
        await openaiImage.setLimit(imageLimit)
    }

    func setLimit(_ n: Int) { limit = max(1, n) }

    func pause(for seconds: TimeInterval) {
        let until = Date().addingTimeInterval(seconds)
        if until > pausedUntil { pausedUntil = until }
    }

    func release() { inUse = max(0, inUse - 1) }

    /// nil = conseguiu a vaga; senão, quantos segundos esperar antes de tentar de novo.
    private func tryAcquire() -> TimeInterval? {
        let wait = pausedUntil.timeIntervalSinceNow
        if wait > 0 { return wait }
        if inUse >= limit { return 0.3 }
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
