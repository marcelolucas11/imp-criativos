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
    var geminiImageModel: String
    var geminiTextModel: String
    /// Resolução pedida ao Gemini. 2K cobre com folga 1080×1350 e 1080×1920.
    var geminiImageSize = "2K"
    var openaiImageModel: String
    var openaiTextModel: String
    var openaiQuality: String
    var geminiPlannerModel: String = ""
    var openaiPlannerModel: String = ""

    @MainActor
    init(_ s: AppSettings) {
        geminiImageModel = s.geminiImageModel.trimmingCharacters(in: .whitespaces)
        geminiTextModel = s.geminiTextModel.trimmingCharacters(in: .whitespaces)
        openaiImageModel = s.openaiImageModel.trimmingCharacters(in: .whitespaces)
        openaiTextModel = s.openaiTextModel.trimmingCharacters(in: .whitespaces)
        openaiQuality = s.openaiQuality
        geminiPlannerModel = s.geminiPlannerModel.trimmingCharacters(in: .whitespaces)
        openaiPlannerModel = s.openaiPlannerModel.trimmingCharacters(in: .whitespaces)
    }

    /// Modelo de planejamento de cada IA (cai no de análise se estiver vazio).
    func plannerModel(_ kind: ProviderKind) -> String {
        let m = kind == .gemini ? geminiPlannerModel : openaiPlannerModel
        return m.isEmpty ? (kind == .gemini ? geminiTextModel : openaiTextModel) : m
    }
}

enum ProviderFactory {
    /// Mesma IA, mas com o modelo de planejamento (mais forte) no lugar do de análise.
    static func makePlanner(_ kind: ProviderKind, config: ProviderConfig) throws -> AIProvider {
        var c = config
        if kind == .gemini { c.geminiTextModel = config.plannerModel(.gemini) }
        else { c.openaiTextModel = config.plannerModel(.openai) }
        return try make(kind, config: c)
    }

    static func make(_ kind: ProviderKind, config: ProviderConfig) throws -> AIProvider {
        guard let key = KeychainStore.load(kind) else {
            throw AIError("Chave do \(kind.label) não configurada. Vá em Configurações → Chaves de API.")
        }
        switch kind {
        case .gemini:
            return GeminiProvider(apiKey: key, imageModel: config.geminiImageModel,
                                  textModel: config.geminiTextModel, imageSize: config.geminiImageSize)
        case .openai:
            return OpenAIProvider(apiKey: key, imageModel: config.openaiImageModel,
                                  textModel: config.openaiTextModel, quality: config.openaiQuality)
        }
    }
}
