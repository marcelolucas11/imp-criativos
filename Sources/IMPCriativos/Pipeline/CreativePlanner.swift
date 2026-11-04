import Foundation
import ImageIO
import Vision

/// 1.0.0-beta.7: plano de cada criativo, feito por uma IA de raciocínio mais forte ANTES da limpeza.
/// Ela olha a imagem original junto com tudo o que o usuário pediu (perfil do cliente + instruções do lote)
/// e devolve instruções exatas para as outras etapas. O código depois confere o resultado contra o plano.
struct CreativePlan: Codable, Hashable {
    /// Palavras, nomes, @ e sites que não podem aparecer em nenhuma imagem final (limpo e variações).
    var forbiddenTerms: [String]
    /// Texto do criativo original, como está.
    var originalText: String
    /// Texto exato que o criativo deve ter depois de TODOS os pedidos (remoções e alterações).
    var finalText: String
    /// Instrução de edição específica para esta imagem (em inglês, para o modelo de imagem).
    var cleanInstruction: String
    /// Regras que toda variação deste criativo precisa seguir (em inglês).
    var variationRules: String
    /// Dúvidas ou ambiguidades que a IA encontrou no pedido (português).
    var doubts: String
    /// Modelo que fez o plano (para o Histórico).
    var model: String?
}

enum CreativePlanner {
    static func prompt(removeItems: [String], extra: String, instructions: BatchInstructions?) -> String {
        let list = removeItems.isEmpty ? "(none)" : removeItems.map { "- \($0)" }.joined(separator: "\n")
        var p = """
        You are the art director orchestrating an automated pipeline that edits one advertising image (attached). \
        Cheaper models will execute your instructions literally and cannot see this request, so you must turn the \
        user's wishes into exact, complete, unambiguous instructions for THIS specific image.

        Pipeline: (1) an image-editing model cleans the image following your "clean_instruction"; \
        (2) other image models create new variations that must contain exactly your "final_text"; \
        (3) checkers verify that none of the "forbidden_terms" appear anywhere and that the text matches.

        WHAT THE USER WANTS REMOVED (client profile + this batch, Brazilian Portuguese):
        \(list)
        """
        if !extra.trimmed.isEmpty {
            p += "\n\nCLIENT STANDING INSTRUCTIONS (Brazilian Portuguese):\n\(extra.trimmed)"
        }
        if let ins = instructions {
            if !ins.raw.trimmed.isEmpty {
                p += "\n\nTHE USER'S OWN WORDS FOR THIS BATCH (Brazilian Portuguese) — this is the source of truth, follow every part of it:\n<<<\n\(ins.raw.trimmed)\n>>>"
            }
            if !ins.textChanges.trimmed.isEmpty {
                p += "\n\nREQUESTED TEXT CHANGES (Brazilian Portuguese):\n\(ins.textChanges.trimmed)"
            }
            if !ins.direction.trimmed.isEmpty {
                p += "\n\nDIRECTION FOR THE VARIATIONS (Brazilian Portuguese):\n\(ins.direction.trimmed)"
            }
        }
        p += """


        Rules:
        - Read every request literally and completely. If the user asks to remove a word or name "anywhere" or "all of it", \
        it must disappear from EVERY place: headlines, titles, buttons, screens, signs, logos, small print.
        - Look at the image carefully and list in "forbidden_terms" every word, name, handle (@), website or phone that \
        must not appear in any final image, written exactly as it appears in the image (one entry per term, \
        e.g. "AVIATOR", "@marca", "marca.com"). Include terms the user asked to remove even if they are not visible. \
        Do not include generic words that are not part of the request.
        - "original_text": transcribe all visible text exactly (Brazilian Portuguese, keep accents and line breaks).
        - "final_text": the exact text the image must have after applying ALL requests. When removing a word breaks a \
        sentence, rewrite that sentence minimally so it stays natural and correct in Brazilian Portuguese, keeping the \
        same meaning and offer (e.g. "GOSTA DE <removed>?" → "GOSTA DE JOGAR?"). Never introduce another brand, game \
        or company name. Never keep a forbidden term. Keep everything else identical, including prices and numbers.
        - "clean_instruction": an English instruction for the image-editing model, specific to this image. Name each \
        element to erase and where it is. For every text line that changes, quote the old line and the exact new line \
        ("Replace the headline 'X' with 'Y', same font, colors and effects"). Say what must stay unchanged. \
        Small text inside phone screens, game thumbnails or signs that shows a forbidden term must be blurred, \
        erased or replaced with a neutral graphic.
        - "variation_rules": English rules every variation must follow (user's direction and constraints, what must \
        never appear, what must stay faithful). Empty if nothing beyond the defaults.
        - "doubts": in Brazilian Portuguese, anything ambiguous you had to decide (empty string if none).

        Respond ONLY with JSON in this exact shape:
        {"forbidden_terms": ["..."], "original_text": "...", "final_text": "...", "clean_instruction": "...", \
        "variation_rules": "...", "doubts": "..."}
        """
        return p
    }

    static func parse(_ text: String, model: String) -> CreativePlan? {
        guard let obj = JSONExtract.object(from: text) else { return nil }
        let terms = ((obj["forbidden_terms"] as? [Any]) ?? [])
            .compactMap { ($0 as? String)?.trimmed }
            .filter { $0.count >= 2 }
        let clean = ((obj["clean_instruction"] as? String) ?? "").trimmed
        guard !clean.isEmpty else { return nil }
        var plan = CreativePlan(forbiddenTerms: ForbiddenTerms.dedup(terms),
                                originalText: ((obj["original_text"] as? String) ?? "").trimmed,
                                finalText: ((obj["final_text"] as? String) ?? "").trimmed,
                                cleanInstruction: clean,
                                variationRules: ((obj["variation_rules"] as? String) ?? "").trimmed,
                                doubts: ((obj["doubts"] as? String) ?? "").trimmed,
                                model: model)
        // Garantia: o texto final nunca carrega termo proibido, mesmo que a IA erre.
        if !ForbiddenTerms.found(in: plan.finalText, terms: plan.forbiddenTerms).isEmpty {
            plan.finalText = ForbiddenTerms.strip(plan.forbiddenTerms, from: plan.finalText)
        }
        return plan
    }

    /// Resumo para o Histórico.
    static func summary(_ plan: CreativePlan) -> String {
        var lines = [
            "Termos proibidos: " + (plan.forbiddenTerms.isEmpty ? "nenhum" : plan.forbiddenTerms.joined(separator: ", ")),
            "Texto original:\n\(plan.originalText)",
            "Texto final:\n\(plan.finalText)",
            "Instrução de limpeza:\n\(plan.cleanInstruction)",
        ]
        if !plan.variationRules.isEmpty { lines.append("Regras das variações:\n\(plan.variationRules)") }
        if !plan.doubts.isEmpty { lines.append("Dúvidas resolvidas pela IA: \(plan.doubts)") }
        if let m = plan.model { lines.append("Modelo: \(m)") }
        return lines.joined(separator: "\n\n")
    }
}

/// Conferência por código dos termos proibidos (sem IA): ignora maiúsculas, acentos e pontuação.
enum ForbiddenTerms {
    static func normalize(_ s: String) -> String {
        let folded = s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "pt_BR"))
        let mapped = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || $0 == "@" ? Character($0) : " " }
        return String(mapped).split(separator: " ").joined(separator: " ")
    }

    static func dedup(_ terms: [String]) -> [String] {
        var seen = Set<String>()
        return terms.filter { t in
            let n = normalize(t)
            guard !n.isEmpty, !seen.contains(n) else { return false }
            seen.insert(n)
            return true
        }
    }

    /// Termos que aparecem no texto (palavra inteira; "fera" não casa com "ferramenta").
    /// Também pega o termo escrito sem espaços ("AVI ATOR" lido pelo OCR como "AVIATOR" e vice-versa).
    static func found(in text: String, terms: [String]) -> [String] {
        let hay = " " + normalize(text) + " "
        let squashed = hay.replacingOccurrences(of: " ", with: "")
        return terms.filter { term in
            let n = normalize(term)
            guard !n.isEmpty else { return false }
            if hay.contains(" " + n + " ") { return true }
            let nsq = n.replacingOccurrences(of: " ", with: "")
            // sem espaços só para termos longos, para não gerar falso positivo com palavras curtas
            return nsq.count >= 6 && squashed.contains(nsq)
        }
    }

    /// Tira os termos do texto (último recurso, quando o plano ou a transcrição ainda os trazem).
    static func strip(_ terms: [String], from text: String) -> String {
        var out = text
        for term in terms where !term.trimmed.isEmpty {
            let escaped = NSRegularExpression.escapedPattern(for: term.trimmed)
            let pattern = "(?<![\\p{L}\\p{N}])" + escaped + "(?![\\p{L}\\p{N}])"
            if let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                out = re.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: "")
            }
        }
        let lines = out.components(separatedBy: .newlines).map { line -> String in
            var l = line.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            l = l.replacingOccurrences(of: "\\s+([?!.,:;])", with: "$1", options: .regularExpression)
            return l.trimmed
        }
        return lines.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// Plano B quando o planejamento falha: tira dos itens de remoção as palavras citadas
    /// (entre aspas, "nome X", "palavra X", ou item curto como "Aviator").
    static func fallback(from items: [String]) -> [String] {
        let namePrefixes: Set<String> = ["nome", "nomes", "palavra", "palavras", "termo", "termos", "texto", "escrita"]
        let fillers: Set<String> = ["o", "a", "os", "as", "todo", "toda", "todos", "todas", "qualquer", "do", "da", "de", "dos", "das"]
        let generic: Set<String> = ["logo", "logotipo", "logomarca", "marca", "selo", "icone", "site", "telefone", "whatsapp",
                                    "cnpj", "instagram", "endereco", "empresa", "cliente", "rodape", "agua", "redes", "sociais",
                                    "internet", "qr", "codigo", "watermark"]
        var result: [String] = []
        for item in items {
            let quoted = matches(of: "[\"“”']([^\"“”']{2,})[\"“”']", in: item)
            if !quoted.isEmpty { result += quoted; continue }
            let base = item.replacingOccurrences(of: "\\([^)]*\\)", with: " ", options: .regularExpression)
            var tokens = base.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            var hadPrefix = false
            while let first = tokens.first, fillers.contains(normalize(first)) || namePrefixes.contains(normalize(first)) {
                if namePrefixes.contains(normalize(first)) { hadPrefix = true }
                tokens.removeFirst()
            }
            let rest = tokens.joined(separator: " ")
            let parts = rest.components(separatedBy: CharacterSet(charactersIn: ",;/"))
                .flatMap { $0.components(separatedBy: " e ") }
                .map { $0.trimmed }
                .filter { !$0.isEmpty }
            for part in parts {
                let words = normalize(part).split(separator: " ").map(String.init)
                guard !words.isEmpty, words.count <= 3, !words.contains(where: { generic.contains($0) }) else { continue }
                if hadPrefix || words.count <= 2 { result.append(part) }
            }
        }
        return dedup(result)
    }

    private static func matches(of pattern: String, in s: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        return re.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap {
            Range($0.range(at: 1), in: s).map { String(s[$0]).trimmed }
        }
    }
}

/// Leitura de texto feita pelo próprio Mac (Vision), sem custo e sem IA externa.
/// Serve de segunda opinião, independente da IA que gerou a imagem.
enum LocalOCR {
    static func text(at url: URL) -> String? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["pt-BR", "en-US"]
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do { try handler.perform([request]) } catch { return nil }
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
    }
}
