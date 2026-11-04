import Foundation
import Combine

/// Preferências do app, salvas no UserDefaults do Mac (as chaves de API ficam no Keychain, não aqui).
final class AppSettings: ObservableObject {
    private let d = UserDefaults.standard

    // Comportamento
    @Published var runInBackground: Bool { didSet { d.set(runInBackground, forKey: "runInBackground") } }
    @Published var notifyOnFinish: Bool { didSet { d.set(notifyOnFinish, forKey: "notifyOnFinish") } }
    @Published var includeBetaUpdates: Bool { didSet { d.set(includeBetaUpdates, forKey: "includeBetaUpdates") } }
    @Published var checkUpdatesOnLaunch: Bool { didSet { d.set(checkUpdatesOnLaunch, forKey: "checkUpdatesOnLaunch") } }

    // Processamento
    @Published var maxConcurrent: Int { didSet { d.set(maxConcurrent, forKey: "maxConcurrent") } }
    @Published var defaultOutputFolder: String { didSet { d.set(defaultOutputFolder, forKey: "defaultOutputFolder") } }
    @Published var defaultCleanProvider: ProviderKind { didSet { d.set(defaultCleanProvider.rawValue, forKey: "defaultCleanProvider") } }
    @Published var defaultVariationProvider: ProviderKind { didSet { d.set(defaultVariationProvider.rawValue, forKey: "defaultVariationProvider") } }
    @Published var defaultAnalysisProvider: ProviderKind { didSet { d.set(defaultAnalysisProvider.rawValue, forKey: "defaultAnalysisProvider") } }

    // Modelos (editáveis: quando sair modelo novo, basta trocar o nome)
    @Published var geminiImageModel: String { didSet { d.set(geminiImageModel, forKey: "geminiImageModel") } }
    @Published var geminiTextModel: String { didSet { d.set(geminiTextModel, forKey: "geminiTextModel") } }
    @Published var geminiImageSize: String { didSet { d.set(geminiImageSize, forKey: "geminiImageSize") } }
    @Published var openaiImageModel: String { didSet { d.set(openaiImageModel, forKey: "openaiImageModel") } }
    @Published var openaiTextModel: String { didSet { d.set(openaiTextModel, forKey: "openaiTextModel") } }
    @Published var openaiQuality: String { didSet { d.set(openaiQuality, forKey: "openaiQuality") } }

    // Preços estimados (US$) — só para a estimativa e o contador de gasto
    @Published var priceGeminiImage: Double { didSet { d.set(priceGeminiImage, forKey: "priceGeminiImage") } }
    @Published var priceOpenAIImage: Double { didSet { d.set(priceOpenAIImage, forKey: "priceOpenAIImage") } }
    @Published var priceAnalysis: Double { didSet { d.set(priceAnalysis, forKey: "priceAnalysis") } }

    static let defaultModels = (
        geminiImage: "gemini-nano-banana-2.1",
        geminiText: "gemini-3.5-flash-lite",
        openaiImage: "gpt-image-2",
        openaiText: "gpt-5-mini"
    )

    init() {
        d.register(defaults: [
            "runInBackground": true,
            "notifyOnFinish": true,
            "includeBetaUpdates": true,
            "checkUpdatesOnLaunch": true,
            "maxConcurrent": 3,
            "defaultCleanProvider": ProviderKind.gemini.rawValue,
            "defaultVariationProvider": ProviderKind.gemini.rawValue,
            "defaultAnalysisProvider": ProviderKind.gemini.rawValue,
            "geminiImageModel": Self.defaultModels.geminiImage,
            "geminiTextModel": Self.defaultModels.geminiText,
            "geminiImageSize": "2K",
            "openaiImageModel": Self.defaultModels.openaiImage,
            "openaiTextModel": Self.defaultModels.openaiText,
            "openaiQuality": "medium",
            "priceGeminiImage": 0.07,
            "priceOpenAIImage": 0.06,
            "priceAnalysis": 0.002,
        ])
        let defaultOut = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("IMP Criativos").path

        runInBackground = d.bool(forKey: "runInBackground")
        notifyOnFinish = d.bool(forKey: "notifyOnFinish")
        includeBetaUpdates = d.bool(forKey: "includeBetaUpdates")
        checkUpdatesOnLaunch = d.bool(forKey: "checkUpdatesOnLaunch")
        maxConcurrent = max(1, d.integer(forKey: "maxConcurrent"))
        defaultOutputFolder = d.string(forKey: "defaultOutputFolder") ?? defaultOut
        defaultCleanProvider = ProviderKind(rawValue: d.string(forKey: "defaultCleanProvider") ?? "") ?? .gemini
        defaultVariationProvider = ProviderKind(rawValue: d.string(forKey: "defaultVariationProvider") ?? "") ?? .gemini
        defaultAnalysisProvider = ProviderKind(rawValue: d.string(forKey: "defaultAnalysisProvider") ?? "") ?? .gemini
        geminiImageModel = d.string(forKey: "geminiImageModel") ?? Self.defaultModels.geminiImage
        geminiTextModel = d.string(forKey: "geminiTextModel") ?? Self.defaultModels.geminiText
        geminiImageSize = d.string(forKey: "geminiImageSize") ?? "2K"
        openaiImageModel = d.string(forKey: "openaiImageModel") ?? Self.defaultModels.openaiImage
        openaiTextModel = d.string(forKey: "openaiTextModel") ?? Self.defaultModels.openaiText
        openaiQuality = d.string(forKey: "openaiQuality") ?? "medium"
        priceGeminiImage = d.double(forKey: "priceGeminiImage")
        priceOpenAIImage = d.double(forKey: "priceOpenAIImage")
        priceAnalysis = d.double(forKey: "priceAnalysis")
    }

    func imagePrice(for p: ProviderKind) -> Double {
        p == .gemini ? priceGeminiImage : priceOpenAIImage
    }

    func resetModels() {
        geminiImageModel = Self.defaultModels.geminiImage
        geminiTextModel = Self.defaultModels.geminiText
        openaiImageModel = Self.defaultModels.openaiImage
        openaiTextModel = Self.defaultModels.openaiText
        geminiImageSize = "2K"
        openaiQuality = "medium"
    }
}
