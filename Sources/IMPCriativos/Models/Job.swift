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

    var variations: [Variation]

    var baseName: String { (sourceName as NSString).deletingPathExtension }

    var hasWarning: Bool {
        cleanWarning != nil || variations.contains { $0.textWarning != nil }
    }

    var hasFailure: Bool {
        cleanStatus == .failed || variations.contains { $0.status == .failed }
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
}
