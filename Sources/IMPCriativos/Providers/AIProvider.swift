import Foundation

/// Interface única para os provedores de IA. Cada etapa do lote escolhe qual usar.
protocol AIProvider {
    /// Edita/gera uma imagem a partir de uma imagem de referência e de uma instrução.
    func editImage(_ jpeg: Data, prompt: String, aspectRatio: String) async throws -> Data
    /// Analisa uma imagem e responde em texto (pedimos JSON no prompt).
    func analyze(_ jpeg: Data, prompt: String) async throws -> String
    /// Confere se a chave funciona.
    func testKey() async throws
}

/// Configuração lida das Configurações no momento em que o lote roda.
struct ProviderConfig {
    var geminiImageModel: String
    var geminiTextModel: String
    var geminiImageSize: String
    var openaiImageModel: String
    var openaiTextModel: String
    var openaiQuality: String

    @MainActor
    init(_ s: AppSettings) {
        geminiImageModel = s.geminiImageModel.trimmingCharacters(in: .whitespaces)
        geminiTextModel = s.geminiTextModel.trimmingCharacters(in: .whitespaces)
        geminiImageSize = s.geminiImageSize
        openaiImageModel = s.openaiImageModel.trimmingCharacters(in: .whitespaces)
        openaiTextModel = s.openaiTextModel.trimmingCharacters(in: .whitespaces)
        openaiQuality = s.openaiQuality
    }
}

enum ProviderFactory {
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
