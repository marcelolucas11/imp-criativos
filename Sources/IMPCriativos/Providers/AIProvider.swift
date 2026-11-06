import Foundation

/// Interface única para os provedores de IA. Cada etapa do lote escolhe qual usar.
protocol AIProvider {
    /// Edita/gera uma imagem a partir de uma imagem de referência e de uma instrução.
    func editImage(_ jpeg: Data, prompt: String, aspectRatio: String) async throws -> Data
    /// Analisa uma imagem e responde em texto (pedimos JSON no prompt).
    func analyze(_ jpeg: Data, prompt: String) async throws -> String
    /// Pedido só de texto, sem imagem (pedimos JSON no prompt). Usado para interpretar as instruções do lote.
    func complete(prompt: String) async throws -> String
    /// Confere se a chave funciona.
    func testKey() async throws
}

/// Configuração lida das Configurações no momento em que o lote roda.
struct ProviderConfig {
    /// Resolução pedida ao Gemini. 2K cobre com folga 1080×1350 e 1080×1920.
    var geminiImageSize = "2K"
    var openaiQuality: String
    /// 1.0.0-beta.11: plataforma + modelo de cada etapa, com reserva.
    var stages: [AIStage: StageAI]

    @MainActor
    init(_ s: AppSettings) {
        openaiQuality = s.openaiQuality
        var clean: [AIStage: StageAI] = [:]
        for st in AIStage.allCases {
            var v = s.stage(st)
            v.primary.model = v.primary.model.trimmingCharacters(in: .whitespaces)
            v.backup?.model = v.backup?.model.trimmingCharacters(in: .whitespaces) ?? ""
            if v.primary.model.isEmpty { v.primary.model = st.defaultModel(v.primary.provider) }
            if let b = v.backup, b.model.isEmpty { v.backup?.model = st.defaultModel(b.provider) }
            clean[st] = v
        }
        stages = clean
    }

    func stage(_ st: AIStage) -> StageAI { stages[st] ?? st.defaultAI }

    /// Ordem de tentativa da etapa: principal e depois a reserva (sem repetir).
    /// `prefer`: plataforma escolhida no lote ou em "Refazer com…". Se não for a principal, ela vai na frente
    /// (com o modelo configurado para ela nesta etapa, ou o padrão da plataforma) e a principal vira a reserva.
    func chain(_ st: AIStage, prefer: ProviderKind? = nil) -> [ModelChoice] {
        let s = stage(st)
        var list = [s.primary] + (s.backup.map { [$0] } ?? [])
        if let p = prefer, list.first?.provider != p {
            if let i = list.firstIndex(where: { $0.provider == p }) {
                list.insert(list.remove(at: i), at: 0)
            } else {
                list.insert(ModelChoice(provider: p, model: st.defaultModel(p)), at: 0)
            }
        }
        var seen = Set<ModelChoice>()
        return Array(list.filter { seen.insert($0).inserted }.prefix(2))
    }
}

enum ProviderFactory {
    /// Cria o provedor da plataforma com o modelo escolhido (o mesmo nome serve para imagem ou texto;
    /// cada etapa só usa a função do seu tipo).
    static func make(_ choice: ModelChoice, config: ProviderConfig) throws -> AIProvider {
        guard let key = APIKeyStore.load(choice.provider) else {
            throw AIError("Chave do \(choice.provider.label) não configurada. Vá em Configurações → Chaves de API.", kind: .auth)
        }
        switch choice.provider {
        case .gemini:
            return GeminiProvider(apiKey: key, imageModel: choice.model,
                                  textModel: choice.model, imageSize: config.geminiImageSize)
        case .openai:
            return OpenAIProvider(apiKey: key, imageModel: choice.model,
                                  textModel: choice.model, quality: config.openaiQuality)
        }
    }
}
