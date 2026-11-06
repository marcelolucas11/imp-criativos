import Foundation
import Combine

// 1.0.0-beta.11: cada etapa escolhe plataforma + modelo, e uma reserva (plataforma + modelo) para quando falhar.

/// O que o modelo precisa saber fazer. Define quais modelos aparecem na lista de cada etapa.
enum ModelRole: String, Codable {
    /// Edita/gera imagem a partir de uma imagem de referência (limpeza e variações).
    case image
    /// Lê imagem/texto e responde em JSON (análise, checagem, planejamento, interpretação).
    case text
}

/// Etapas do lote que usam IA.
enum AIStage: String, Codable, CaseIterable, Identifiable {
    case clean, variation, analysis, planning

    var id: String { rawValue }

    var label: String {
        switch self {
        case .clean: return "Limpeza"
        case .variation: return "Variações"
        case .analysis: return "Análise e checagem"
        case .planning: return "Planejamento"
        }
    }

    var help: String {
        switch self {
        case .clean: return "Remove logo, nome, @ e site do criativo original."
        case .variation: return "Cria as variações a partir do criativo limpo."
        case .analysis: return "Confere a limpeza e o texto de cada variação. Modelo rápido e barato basta."
        case .planning: return "Lê o seu pedido e cada criativo antes da limpeza e interpreta as instruções do lote. Use o modelo mais forte."
        }
    }

    var role: ModelRole {
        switch self {
        case .clean, .variation: return .image
        case .analysis, .planning: return .text
        }
    }

    /// Modelo padrão de cada plataforma para esta etapa.
    func defaultModel(_ p: ProviderKind) -> String {
        switch (self, p) {
        case (.clean, .gemini), (.variation, .gemini): return "gemini-nano-banana-2.1"
        case (.clean, .openai), (.variation, .openai): return "gpt-image-2"
        case (.analysis, .gemini): return "gemini-3.5-flash-lite"
        case (.analysis, .openai): return "gpt-5-mini"
        case (.planning, .gemini): return "gemini-4-argon"
        case (.planning, .openai): return "gpt-6-sol"
        }
    }

    /// Configuração de fábrica: limpeza no GPT (o filtro de imagem do Gemini bloqueava quase todas), o resto no Gemini,
    /// e a outra plataforma como reserva.
    var defaultAI: StageAI {
        let main: ProviderKind = self == .clean ? .openai : .gemini
        let alt: ProviderKind = main == .gemini ? .openai : .gemini
        return StageAI(primary: ModelChoice(provider: main, model: defaultModel(main)),
                       backup: ModelChoice(provider: alt, model: defaultModel(alt)))
    }
}

extension ProviderKind {
    /// Nome da plataforma no menu de modelos.
    var platformLabel: String {
        switch self {
        case .gemini: return "Google (Gemini)"
        case .openai: return "OpenAI (GPT)"
        }
    }
}

/// Uma plataforma e um modelo dela.
struct ModelChoice: Codable, Hashable {
    var provider: ProviderKind
    var model: String

    var label: String { "\(provider.label) · \(model)" }
}

/// IA principal e reserva de uma etapa.
struct StageAI: Codable, Hashable {
    var primary: ModelChoice
    /// nil = não troca de IA nesta etapa.
    var backup: ModelChoice?
}

/// Lista de modelos de cada plataforma: os padrões do app + os que a sua chave enxerga na API (Atualizar lista).
@MainActor
final class ModelCatalog: ObservableObject {
    static let shared = ModelCatalog()

    @Published private(set) var fetched: [String: [String]] = [:]
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var refreshing = false
    @Published private(set) var lastError: String?

    private let d = UserDefaults.standard
    private static let cacheKey = "modelCatalogCache"
    private static let dateKey = "modelCatalogUpdated"

    private init() {
        fetched = (d.dictionary(forKey: Self.cacheKey) as? [String: [String]]) ?? [:]
        lastUpdated = d.object(forKey: Self.dateKey) as? Date
    }

    private static func key(_ p: ProviderKind, _ role: ModelRole) -> String { "\(p.rawValue).\(role.rawValue)" }

    /// Modelos para o menu: padrões do app primeiro, depois os da API (mais novos no topo).
    /// `including` garante que o modelo já escolhido apareça mesmo que não esteja em nenhuma lista.
    func models(_ p: ProviderKind, role: ModelRole, including extra: [String] = []) -> [String] {
        let defaults = AIStage.allCases.filter { $0.role == role }.map { $0.defaultModel(p) }
        let api = (fetched[Self.key(p, role)] ?? [])
            .sorted { $0.localizedStandardCompare($1) == .orderedDescending }
        var seen = Set<String>()
        return (defaults + extra.filter { !$0.isEmpty } + api).filter { seen.insert($0).inserted }
    }

    /// Atualiza sozinho quando a lista tem mais de 1 dia.
    func refreshIfStale() async {
        if let lastUpdated, Date().timeIntervalSince(lastUpdated) < 24 * 3600 { return }
        await refresh()
    }

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        var errors: [String] = []
        var updated = fetched
        var any = false
        for p in ProviderKind.allCases {
            guard let key = APIKeyStore.load(p) else { continue }
            do {
                let ids = try await Self.list(p, apiKey: key)
                updated[Self.key(p, .image)] = ids.filter { Self.isImageModel(p, $0) }
                updated[Self.key(p, .text)] = ids.filter { Self.isTextModel(p, $0) }
                any = true
            } catch {
                errors.append("\(p.label): \(error.localizedDescription)")
            }
        }
        fetched = updated
        lastError = errors.isEmpty ? nil : errors.joined(separator: " · ")
        if any {
            lastUpdated = Date()
            d.set(updated, forKey: Self.cacheKey)
            d.set(lastUpdated, forKey: Self.dateKey)
            AppLog.info(.configuracoes, "Lista de modelos atualizada.",
                        details: updated.keys.sorted().map { "\($0): \(updated[$0]?.count ?? 0)" }.joined(separator: " · "))
        }
        if let lastError { AppLog.warning(.configuracoes, "Não foi possível atualizar a lista de modelos.", details: lastError) }
    }

    // MARK: APIs de listagem

    private static func list(_ p: ProviderKind, apiKey: String) async throws -> [String] {
        switch p {
        case .gemini:
            var ids: [String] = []
            var pageToken: String?
            repeat {
                var comps = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models")!
                comps.queryItems = [URLQueryItem(name: "pageSize", value: "1000")]
                    + (pageToken.map { [URLQueryItem(name: "pageToken", value: $0)] } ?? [])
                var req = URLRequest(url: comps.url!)
                req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
                let obj = try HTTP.json(try await HTTP.send(req, label: "Gemini · lista de modelos", attempts: 2)) as? [String: Any]
                for m in (obj?["models"] as? [[String: Any]]) ?? [] {
                    guard let name = m["name"] as? String else { continue }
                    ids.append(name.hasPrefix("models/") ? String(name.dropFirst("models/".count)) : name)
                }
                pageToken = (obj?["nextPageToken"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            } while pageToken != nil && ids.count < 5000
            return ids
        case .openai:
            var req = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            let obj = try HTTP.json(try await HTTP.send(req, label: "OpenAI · lista de modelos", attempts: 2)) as? [String: Any]
            return ((obj?["data"] as? [[String: Any]]) ?? []).compactMap { $0["id"] as? String }
        }
    }

    private static func has(_ id: String, _ parts: [String]) -> Bool {
        let s = id.lowercased()
        return parts.contains { s.contains($0) }
    }

    /// Modelos que editam imagem pelo mesmo caminho que o app usa.
    static func isImageModel(_ p: ProviderKind, _ id: String) -> Bool {
        switch p {
        case .gemini: return id.hasPrefix("gemini") && has(id, ["image", "nano-banana"])
        case .openai: return has(id, ["gpt-image", "chatgpt-image"])
        }
    }

    /// Modelos de texto/visão que respondem no endpoint de conversa que o app usa.
    static func isTextModel(_ p: ProviderKind, _ id: String) -> Bool {
        switch p {
        case .gemini:
            return id.hasPrefix("gemini")
                && !has(id, ["image", "nano-banana", "embedding", "tts", "audio", "live", "aqa", "computer-use"])
        case .openai:
            let s = id.lowercased()
            let family = s.hasPrefix("gpt-") || s.hasPrefix("chatgpt-") || (s.first == "o" && s.dropFirst().first?.isNumber == true)
            return family && !has(id, ["image", "audio", "realtime", "tts", "transcribe", "search", "embedding",
                                       "moderation", "instruct", "codex", "-pro", "deep-research", "computer-use"])
        }
    }
}
