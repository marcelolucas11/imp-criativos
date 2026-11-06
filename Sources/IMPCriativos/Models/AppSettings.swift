import Foundation
import Combine

/// Preferências do app, salvas no UserDefaults do Mac (as chaves de API ficam em chaves.json, não aqui).
final class AppSettings: ObservableObject {
    private let d = UserDefaults.standard

    // Comportamento
    @Published var runInBackground: Bool { didSet { d.set(runInBackground, forKey: "runInBackground") } }
    @Published var notifyOnFinish: Bool { didSet { d.set(notifyOnFinish, forKey: "notifyOnFinish") } }
    @Published var includeBetaUpdates: Bool { didSet { d.set(includeBetaUpdates, forKey: "includeBetaUpdates") } }
    @Published var checkUpdatesOnLaunch: Bool { didSet { d.set(checkUpdatesOnLaunch, forKey: "checkUpdatesOnLaunch") } }

    // Processamento
    @Published var maxConcurrent: Int { didSet { d.set(maxConcurrent, forKey: "maxConcurrent") } }
    /// Pedidos de imagem ao mesmo tempo para cada IA, somando todos os lotes.
    @Published var maxImageRequests: Int { didSet { d.set(maxImageRequests, forKey: "maxImageRequests") } }
    /// Tentativas em erro temporário (503, 429, conexão), contando a primeira.
    @Published var retryAttempts: Int { didSet { d.set(retryAttempts, forKey: "retryAttempts") } }
    /// Se uma IA falhar por erro temporário, refaz com a outra (quando houver chave).
    @Published var fallbackEnabled: Bool { didSet { d.set(fallbackEnabled, forKey: "fallbackEnabled") } }
    /// Também troca de IA quando a imagem for bloqueada pelo filtro de conteúdo.
    @Published var fallbackOnBlocked: Bool { didSet { d.set(fallbackOnBlocked, forKey: "fallbackOnBlocked") } }
    @Published var defaultOutputFolder: String { didSet { d.set(defaultOutputFolder, forKey: "defaultOutputFolder") } }
    @Published var defaultFormat: MetaFormat { didSet { d.set(defaultFormat.rawValue, forKey: "defaultFormat") } }

    /// 1.0.0-beta.11: plataforma + modelo de cada etapa, com a reserva usada quando a principal falha.
    @Published var stageAI: [AIStage: StageAI] { didSet { saveStageAI() } }
    @Published var openaiQuality: String { didSet { d.set(openaiQuality, forKey: "openaiQuality") } }
    /// Liga a etapa de planejamento (recomendado).
    @Published var planningEnabled: Bool { didSet { d.set(planningEnabled, forKey: "planningEnabled") } }

    // Preços estimados (US$) — só para a estimativa e o contador de gasto
    @Published var priceGeminiImage: Double { didSet { d.set(priceGeminiImage, forKey: "priceGeminiImage") } }
    @Published var priceOpenAIImage: Double { didSet { d.set(priceOpenAIImage, forKey: "priceOpenAIImage") } }
    @Published var priceAnalysis: Double { didSet { d.set(priceAnalysis, forKey: "priceAnalysis") } }
    @Published var pricePlanning: Double { didSet { d.set(pricePlanning, forKey: "pricePlanning") } }

    init() {
        d.register(defaults: [
            "runInBackground": true,
            "notifyOnFinish": true,
            "includeBetaUpdates": true,
            "checkUpdatesOnLaunch": true,
            "maxConcurrent": 3,
            "maxImageRequests": 2,
            "retryAttempts": 6,
            "fallbackEnabled": true,
            "fallbackOnBlocked": true,
            "defaultFormat": MetaFormat.feed.rawValue,
            "openaiQuality": "medium",
            "priceGeminiImage": 0.07,
            "priceOpenAIImage": 0.06,
            "priceAnalysis": 0.002,
            "planningEnabled": true,
            "pricePlanning": 0.02,
        ])
        let defaultOut = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("IMP Criativos").path

        runInBackground = d.bool(forKey: "runInBackground")
        notifyOnFinish = d.bool(forKey: "notifyOnFinish")
        includeBetaUpdates = d.bool(forKey: "includeBetaUpdates")
        checkUpdatesOnLaunch = d.bool(forKey: "checkUpdatesOnLaunch")
        maxConcurrent = max(1, d.integer(forKey: "maxConcurrent"))
        maxImageRequests = max(1, d.integer(forKey: "maxImageRequests"))
        retryAttempts = max(1, d.integer(forKey: "retryAttempts"))
        fallbackEnabled = d.bool(forKey: "fallbackEnabled")
        fallbackOnBlocked = d.bool(forKey: "fallbackOnBlocked")
        defaultOutputFolder = d.string(forKey: "defaultOutputFolder") ?? defaultOut
        defaultFormat = MetaFormat(rawValue: d.string(forKey: "defaultFormat") ?? "") ?? .feed
        openaiQuality = d.string(forKey: "openaiQuality") ?? "medium"
        priceGeminiImage = d.double(forKey: "priceGeminiImage")
        priceOpenAIImage = d.double(forKey: "priceOpenAIImage")
        priceAnalysis = d.double(forKey: "priceAnalysis")
        planningEnabled = d.bool(forKey: "planningEnabled")
        pricePlanning = d.double(forKey: "pricePlanning")
        stageAI = Self.loadStageAI(d)
    }

    // MARK: IA por etapa

    func stage(_ s: AIStage) -> StageAI { stageAI[s] ?? s.defaultAI }

    /// Se o modelo escolhido era a reserva, a antiga principal passa a ser a reserva (as duas não ficam iguais).
    func setPrimary(_ c: ModelChoice, for s: AIStage) {
        var v = stage(s)
        guard v.primary != c else { return }
        if v.backup == c { v.backup = v.primary }
        v.primary = c
        stageAI[s] = v
    }

    /// Escolha feita no Novo lote. Se a plataforma nova era a da reserva, a antiga principal vira a reserva,
    /// para a etapa continuar com uma reserva de outra plataforma.
    func adoptForBatch(_ c: ModelChoice, for s: AIStage) {
        var v = stage(s)
        guard v.primary != c else { return }
        if v.backup == c || (v.backup?.provider == c.provider && v.primary.provider != c.provider) { v.backup = v.primary }
        v.primary = c
        stageAI[s] = v
    }

    func setBackup(_ c: ModelChoice?, for s: AIStage) {
        var v = stage(s)
        v.backup = c
        stageAI[s] = v
    }

    private static let stageKey = "stageAI"

    private func saveStageAI() {
        let raw = Dictionary(uniqueKeysWithValues: stageAI.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(raw) { d.set(data, forKey: Self.stageKey) }
    }

    /// Lê a configuração por etapa. Na primeira abertura da beta.11, monta a partir das escolhas antigas
    /// (IA de cada etapa no Novo lote + nomes de modelo por plataforma), com a outra plataforma de reserva.
    private static func loadStageAI(_ d: UserDefaults) -> [AIStage: StageAI] {
        if let data = d.data(forKey: stageKey),
           let raw = try? JSONDecoder().decode([String: StageAI].self, from: data) {
            var out: [AIStage: StageAI] = [:]
            for (k, v) in raw { if let st = AIStage(rawValue: k) { out[st] = v } }
            for st in AIStage.allCases where out[st] == nil { out[st] = st.defaultAI }
            return out
        }

        func old(_ key: String) -> String? {
            d.string(forKey: key)?.trimmingCharacters(in: .whitespaces).nilIfEmpty
        }
        func provider(_ key: String, _ fallback: ProviderKind) -> ProviderKind {
            ProviderKind(rawValue: d.string(forKey: key) ?? "") ?? fallback
        }
        func model(_ st: AIStage, _ p: ProviderKind) -> String {
            let key: String
            switch (st, p) {
            case (.clean, .gemini), (.variation, .gemini): key = "geminiImageModel"
            case (.clean, .openai), (.variation, .openai): key = "openaiImageModel"
            case (.analysis, .gemini): key = "geminiTextModel"
            case (.analysis, .openai): key = "openaiTextModel"
            case (.planning, .gemini): key = "geminiPlannerModel"
            case (.planning, .openai): key = "openaiPlannerModel"
            }
            return old(key) ?? st.defaultModel(p)
        }
        func build(_ st: AIStage, _ main: ProviderKind) -> StageAI {
            let alt: ProviderKind = main == .gemini ? .openai : .gemini
            return StageAI(primary: ModelChoice(provider: main, model: model(st, main)),
                           backup: ModelChoice(provider: alt, model: model(st, alt)))
        }
        var clean = provider("defaultCleanProvider", .openai)
        // quem vem de antes da beta.8 e ainda limpava no Gemini passa para o GPT (se tiver a chave)
        if !d.bool(forKey: "migratedCleanProviderB8") && clean == .gemini && APIKeyStore.hasKey(.openai) { clean = .openai }
        let analysis = provider("defaultAnalysisProvider", .gemini)
        let out: [AIStage: StageAI] = [
            .clean: build(.clean, clean),
            .variation: build(.variation, provider("defaultVariationProvider", .gemini)),
            .analysis: build(.analysis, analysis),
            // antes, o planejamento seguia a IA de análise do lote
            .planning: build(.planning, analysis),
        ]
        let raw = Dictionary(uniqueKeysWithValues: out.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(raw) { d.set(data, forKey: stageKey) }
        return out
    }

    func imagePrice(for p: ProviderKind) -> Double {
        p == .gemini ? priceGeminiImage : priceOpenAIImage
    }

    /// Resumo da configuração para o histórico e o diagnóstico (sem chaves).
    var summary: String {
        let stages = AIStage.allCases.map { st -> String in
            let v = stage(st)
            return "\(st.label): \(v.primary.label) → reserva \(v.backup?.label ?? "nenhuma")"
        }.joined(separator: "\n")
        return """
        \(stages)
        OpenAI qualidade \(openaiQuality) · Planejamento \(planningEnabled ? "ligado" : "desligado")
        Processamento: \(maxConcurrent) criativos por lote ao mesmo tempo · \(maxImageRequests) pedidos de imagem por IA · \(retryAttempts) tentativas em erro temporário
        Troca automática de IA: \(fallbackEnabled ? "ligada" : "desligada")\(fallbackEnabled ? (fallbackOnBlocked ? " (também em bloqueio de conteúdo)" : " (só em erro temporário)") : "")
        """
    }

    func resetModels() {
        stageAI = Dictionary(uniqueKeysWithValues: AIStage.allCases.map { ($0, $0.defaultAI) })
        openaiQuality = "medium"
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
