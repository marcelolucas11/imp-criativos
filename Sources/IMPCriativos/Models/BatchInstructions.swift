import Foundation

/// Instruções livres digitadas no Novo lote, separadas em três partes
/// para que cada uma vá para a etapa (e para a checagem) certa.
struct BatchInstructions: Codable, Hashable {
    /// O que o usuário digitou, como digitou.
    var raw: String
    /// Itens a remover além da lista do cliente (valem na limpeza e nas checagens).
    var removeItems: [String] = []
    /// Alterações de texto: incluir, trocar ou tirar palavras. Viram o "texto esperado".
    var textChanges: String = ""
    /// Direção visual somada aos eixos de cada variação.
    var direction: String = ""

    var isEmpty: Bool {
        removeItems.isEmpty && textChanges.trimmed.isEmpty && direction.trimmed.isEmpty
    }

    /// Resumo de uma linha para o Histórico e o topo do lote.
    var summary: String {
        var parts: [String] = []
        if !removeItems.isEmpty { parts.append("Remover: " + removeItems.joined(separator: ", ")) }
        if !textChanges.trimmed.isEmpty { parts.append("Texto: " + textChanges.trimmed) }
        if !direction.trimmed.isEmpty { parts.append("Direção: " + direction.trimmed) }
        return parts.joined(separator: " · ")
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// Usa a IA de texto para separar o pedido livre em remover / texto / direção.
enum InstructionInterpreter {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func prompt(for raw: String) -> String {
        """
        You help configure a batch job that edits advertising images. First, each image is cleaned \
        (brand elements are removed). Then several new variations of each image are generated.
        The user wrote instructions for this batch in Brazilian Portuguese. Split them into exactly three groups:

        1. "remove": a list of visual elements, names or words that must be REMOVED from the images \
        (for example a brand or game name, a logo, a handle). One short item per element, in Brazilian Portuguese, \
        keeping names exactly as the user wrote them and putting every word or name to erase between double quotes \
        (example: Palavra "Aviator" (escrita em qualquer lugar)). Every word the user wants gone must appear here, \
        one item per word or name.
        2. "text_changes": changes to the TEXT written in the images: words, names or phrases to add, \
        replace or rewrite. Write it as a short, precise instruction in Brazilian Portuguese, quoting the exact words \
        (example: Incluir o nome "Nome Novo" no topo; Trocar "R$ 10" por "R$ 5"). Empty string if none. \
        Removing a word is NOT a text change, it goes to "remove".
        3. "direction": everything else about how the variations should look (angles, scenery, colors, style, \
        mood, diversity). Short instruction in Brazilian Portuguese. Empty string if none.

        Do not invent anything the user did not ask for. Ignore requests about quantities, file formats or sizes.

        USER INSTRUCTIONS:
        <<<
        \(raw)
        >>>

        Respond ONLY with JSON in this exact shape:
        {"remove": ["..."], "text_changes": "...", "direction": "..."}
        """
    }

    static func parse(_ text: String, raw: String) -> BatchInstructions? {
        guard let obj = JSONExtract.object(from: text) else { return nil }
        let remove = ((obj["remove"] as? [Any]) ?? [])
            .compactMap { ($0 as? String)?.trimmed }
            .filter { !$0.isEmpty }
        let changes = ((obj["text_changes"] as? String) ?? "").trimmed
        let direction = ((obj["direction"] as? String) ?? "").trimmed
        return BatchInstructions(raw: raw, removeItems: remove, textChanges: changes, direction: direction)
    }

    /// Tenta a IA escolhida e, se falhar, a outra (quando houver chave).
    @MainActor
    static func interpret(_ raw: String, preferred: ProviderKind, settings: AppSettings) async throws -> (BatchInstructions, ProviderKind) {
        let config = ProviderConfig(settings)
        let order = [preferred] + ProviderKind.allCases.filter { $0 != preferred && APIKeyStore.hasKey($0) }
        var lastError: Error = Failure(message: "Nenhuma chave de API configurada.")
        for kind in order {
            // 1.0.0-beta.7: usa o modelo de planejamento (mais forte); se não for aceito, o de análise
            for planner in [true, false] {
                do {
                    let provider = try planner ? ProviderFactory.makePlanner(kind, config: config)
                                               : ProviderFactory.make(kind, config: config)
                    let answer = try await provider.complete(prompt: prompt(for: raw))
                    if let parsed = parse(answer, raw: raw) { return (parsed, kind) }
                    lastError = Failure(message: "A resposta do \(kind.label) não veio no formato esperado.")
                    break
                } catch {
                    lastError = error
                    if !(planner && (error.aiKind == .model || error.aiKind == .badRequest)) { break }
                }
            }
        }
        throw lastError
    }
}
