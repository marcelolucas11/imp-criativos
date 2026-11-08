import Foundation

enum ProviderKind: String, Codable, CaseIterable, Identifiable {
    case gemini, openai
    var id: String { rawValue }
    var label: String {
        switch self {
        case .gemini: return "Gemini"
        case .openai: return "GPT (OpenAI)"
        }
    }
}

enum StepStatus: String, Codable {
    case pending, running, done, failed
}

enum ReviewStatus: String, Codable {
    case pending, approved, discarded
}

enum OutputFormat: String, Codable, CaseIterable, Identifiable {
    case jpg, png
    var id: String { rawValue }
    var label: String { rawValue.uppercased() }
}

enum OutputSizeMode: Codable, Hashable {
    case original
    case fixed(width: Int, height: Int)

    var label: String {
        switch self {
        case .original: return "Manter original"
        case let .fixed(w, h): return "\(w)×\(h)"
        }
    }
}

/// Tamanhos padrão de criativo vertical do Meta Ads.
enum MetaFormat: String, CaseIterable, Identifiable, Codable {
    case feed, story
    var id: String { rawValue }

    var width: Int { 1080 }
    var height: Int { self == .feed ? 1350 : 1920 }
    var aspectRatio: String { self == .feed ? "4:5" : "9:16" }

    var label: String {
        switch self {
        case .feed: return "Feed 4:5 — 1080×1350"
        case .story: return "Stories e Reels 9:16 — 1080×1920"
        }
    }

    var sizeMode: OutputSizeMode { .fixed(width: width, height: height) }
}

enum JobState: String, Codable {
    case queued, running, paused, review, exported, cancelled

    var label: String {
        switch self {
        case .queued: return "Na fila"
        case .running: return "Processando"
        case .paused: return "Pausado"
        case .review: return "Aguardando revisão"
        case .exported: return "Exportado"
        case .cancelled: return "Cancelado"
        }
    }
}

struct Variation: Codable, Identifiable, Hashable {
    var id = UUID()
    var index: Int
    var axisName: String
    var axisInstruction: String
    var file: String?
    var status: StepStatus = .pending
    var error: String?
    var textWarning: String?
    var review: ReviewStatus = .pending
    var redoNote: String?
    var attempts: Int = 0

    // 1.0.0-beta.4 (opcionais para abrir lotes antigos)
    var errorKind: AIErrorKind?
    var errorDetails: String?
    /// Aviso temporário enquanto espera nova tentativa ("Gemini ocupado · tentativa 2/6").
    var retryNote: String?
    var retryAt: Date?
    /// IA que realmente gerou (difere da do lote quando houve troca automática).
    var providerUsed: ProviderKind?
    /// Forçar uma IA nesta variação (botão "Refazer com…").
    var providerOverride: ProviderKind?

    // 1.0.0-beta.7
    /// Quantas vezes o app refez sozinho porque apareceu termo proibido.
    var autoRedos: Int?

    // 1.0.0-beta.19
    /// Número do eixo no catálogo do app (nil = eixo escrito pelo usuário).
    var axisNumber: Int?

    /// "27. Título 3D" para eixos do catálogo; só o nome para os eixos do usuário.
    var axisLabel: String { axisNumber.map { "\($0). \(axisName)" } ?? axisName }
}

struct JobItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var sourceName: String
    var originalFile: String
    var pixelWidth: Int
    var pixelHeight: Int

    var cleanStatus: StepStatus = .pending
    var cleanedFile: String?
    var cleanError: String?
    var cleanWarning: String?
    var cleanReview: ReviewStatus = .pending
    var cleanRedoNote: String?
    var analysisDone = false
    var transcript: String?
    /// 1.0.0-beta.6: texto realmente visto no limpo, quando difere do esperado (alterações de texto do lote).
    var seenText: String?

    // 1.0.0-beta.4 (opcionais para abrir lotes antigos)
    var cleanErrorKind: AIErrorKind?
    var cleanErrorDetails: String?
    var cleanRetryNote: String?
    var cleanRetryAt: Date?
    var cleanProviderUsed: ProviderKind?
    var cleanProviderOverride: ProviderKind?

    // 1.0.0-beta.7 (opcionais para abrir lotes antigos)
    /// Plano feito pela IA de planejamento antes da limpeza.
    var plan: CreativePlan?
    /// O planejamento já rodou (com ou sem sucesso), para não repetir a cada retomada.
    var planDone: Bool?
    /// Quantas vezes o app refez a limpeza sozinho porque sobrou termo proibido.
    var autoCleanRedos: Int?

    // 1.0.0-beta.8 (opcionais para abrir lotes antigos)
    /// A limpeza foi pulada porque o plano disse que não havia nada a remover (o "limpo" é o original).
    var cleanSkipped: Bool?
    /// Obriga a limpeza mesmo que o plano diga que não precisa (checagem achou marca ou o usuário pediu para refazer).
    var forceClean: Bool?

    var variations: [Variation]

    var baseName: String { (sourceName as NSString).deletingPathExtension }

    var hasWarning: Bool {
        cleanWarning != nil || variations.contains { $0.textWarning != nil }
    }

    var hasFailure: Bool {
        cleanStatus == .failed || variations.contains { $0.status == .failed }
    }

    var failureCount: Int {
        (cleanStatus == .failed ? 1 : 0) + (cleanStatus == .failed ? 0 : variations.filter { $0.status == .failed }.count)
    }

    var isFinished: Bool {
        (cleanStatus == .done || cleanStatus == .failed) &&
            (cleanStatus == .failed || variations.allSatisfy { $0.status == .done || $0.status == .failed })
    }
}

struct Job: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var createdAt = Date()
    var client: ClientProfile
    var inputFolder: String
    var cleanProvider: ProviderKind
    var variationProvider: ProviderKind
    var analysisProvider: ProviderKind
    var variationsPerItem: Int
    var sizeMode: OutputSizeMode
    var format: OutputFormat
    var verifyText: Bool
    var state: JobState = .queued
    var items: [JobItem]
    var costUSD: Double = 0
    var exportedTo: String?
    var lastError: String?

    // 1.0.0-beta.6 (opcional para abrir lotes antigos)
    /// Instruções livres do Novo lote, já separadas em remover / texto / direção.
    var instructions: BatchInstructions?

    // 1.0.0-beta.19 (opcional para abrir lotes antigos)
    /// Teste de eixos: cada criativo passa por todos os eixos do cliente, na ordem da lista.
    var axisTest: Bool?

    var isAxisTest: Bool { axisTest ?? false }

    /// Lista do cliente + o que as instruções do lote mandam remover.
    var effectiveRemoveItems: [String] {
        var list = client.removeItems
        for r in instructions?.removeItems ?? [] where !list.contains(r) { list.append(r) }
        return list
    }

    /// Total de etapas de geração (limpeza + variações) para a barra de progresso.
    var totalSteps: Int { items.reduce(0) { $0 + 1 + $1.variations.count } }

    var finishedSteps: Int {
        items.reduce(0) { acc, item in
            let clean = (item.cleanStatus == .done || item.cleanStatus == .failed) ? 1 : 0
            let vars: Int
            if item.cleanStatus == .failed {
                vars = item.variations.count
            } else {
                vars = item.variations.filter { $0.status == .done || $0.status == .failed }.count
            }
            return acc + clean + vars
        }
    }

    var progress: Double { totalSteps == 0 ? 0 : Double(finishedSteps) / Double(totalSteps) }

    var approvedCount: Int {
        items.reduce(0) { acc, item in
            acc + (item.cleanReview == .approved && item.cleanedFile != nil ? 1 : 0)
                + item.variations.filter { $0.review == .approved && $0.file != nil }.count
        }
    }

    var pendingReviewCount: Int {
        items.reduce(0) { acc, item in
            acc + (item.cleanStatus == .done && item.cleanReview == .pending ? 1 : 0)
                + item.variations.filter { $0.status == .done && $0.review == .pending }.count
        }
    }

    var warningCount: Int { items.filter { $0.hasWarning }.count }

    var failureCount: Int { items.reduce(0) { $0 + $1.failureCount } }
}
