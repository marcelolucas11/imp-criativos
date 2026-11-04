import Foundation

/// Google Gemini via Interactions API (v1beta/interactions).
/// Modelos padrão: gemini-nano-banana-2.1 (imagem) e gemini-3.5-flash-lite (análise).
struct GeminiProvider: AIProvider {
    let apiKey: String
    let imageModel: String
    let textModel: String
    let imageSize: String

    private let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/interactions")!

    /// Filtros de segurança ajustáveis do Gemini, todos desligados.
    /// Criativos de cassino/apostas legalizados não entram em nenhuma dessas categorias,
    /// mas o filtro às vezes confunde. As proteções fixas do Google (não ajustáveis) continuam valendo.
    static let safetyOff: [[String: Any]] = ["harassment", "hate_speech", "sexually_explicit", "dangerous_content", "jailbreak"]
        .map { ["type": $0, "threshold": "off"] }

    func editImage(_ jpeg: Data, prompt: String, aspectRatio: String) async throws -> Data {
        do {
            return try await editOnce(jpeg, prompt: prompt, aspectRatio: aspectRatio)
        } catch let e as AIError where e.kind == .blocked {
            // Bloqueio por conteúdo: uma nova tentativa com a instrução reformulada em tom neutro.
            RequestContext.current?.log(.info, "Gemini bloqueou o pedido; tentando de novo com instrução neutra.", details: e.details)
            RequestContext.current?.onStatus?("Gemini bloqueou · tentando com instrução neutra…", nil)
            return try await editOnce(jpeg, prompt: Prompts.neutral(prompt), aspectRatio: aspectRatio)
        }
    }

    private func editOnce(_ jpeg: Data, prompt: String, aspectRatio: String) async throws -> Data {
        let input: [[String: Any]] = [
            ["type": "text", "text": prompt],
            ["type": "image", "mime_type": "image/jpeg", "data": jpeg.base64EncodedString()],
        ]
        let format: [String: Any] = [
            "type": "image",
            "mime_type": "image/png",
            "aspect_ratio": aspectRatio,
            "image_size": imageSize,
        ]
        // Do mais completo ao mais simples: se o modelo recusar algum campo (HTTP 400),
        // tenta sem ele. A exportação ajusta o tamanho final de qualquer jeito.
        let variants: [(String, [String: Any])] = [
            ("completo", ["model": imageModel, "input": input, "response_format": format, "safety_settings": Self.safetyOff]),
            ("sem proporção/resolução", ["model": imageModel, "input": input, "safety_settings": Self.safetyOff]),
            ("sem ajustes de filtro", ["model": imageModel, "input": input]),
        ]
        let data = try await postVariants(variants, model: imageModel, gate: .image(.gemini))
        let obj = try HTTP.json(data)
        if let img = Self.findImage(in: obj) { return img }
        let text = Self.findText(in: obj)
        let reason = Self.blockReason(in: obj)
        throw AIError(text.isEmpty
            ? "O Gemini não devolveu imagem (pode ter sido bloqueado pelo filtro de segurança)."
            : "O Gemini não devolveu imagem: \(text.prefix(200))",
            kind: .blocked,
            details: "Gemini · \(imageModel)\(reason.map { " · motivo: \($0)" } ?? "")\nResposta: \(String(decoding: data.prefix(700), as: UTF8.self))")
    }

    func analyze(_ jpeg: Data, prompt: String) async throws -> String {
        let input: [[String: Any]] = [
            ["type": "text", "text": prompt],
            ["type": "image", "mime_type": "image/jpeg", "data": jpeg.base64EncodedString()],
        ]
        let variants: [(String, [String: Any])] = [
            ("completo", ["model": textModel, "input": input, "safety_settings": Self.safetyOff]),
            ("sem ajustes de filtro", ["model": textModel, "input": input]),
        ]
        let obj = try HTTP.json(try await postVariants(variants, model: textModel, gate: .text(.gemini)))
        let text = Self.findText(in: obj)
        if text.isEmpty { throw AIError("O Gemini não devolveu a análise.", kind: .blocked) }
        return text
    }

    func complete(prompt: String) async throws -> String {
        let input: [[String: Any]] = [["type": "text", "text": prompt]]
        let variants: [(String, [String: Any])] = [
            ("completo", ["model": textModel, "input": input, "safety_settings": Self.safetyOff]),
            ("sem ajustes de filtro", ["model": textModel, "input": input]),
        ]
        let obj = try HTTP.json(try await postVariants(variants, model: textModel, gate: .text(.gemini)))
        let text = Self.findText(in: obj)
        if text.isEmpty { throw AIError("O Gemini não devolveu resposta.", kind: .blocked) }
        return text
    }

    /// Envia a primeira variante; em HTTP 400 "pedido inválido" passa para a seguinte.
    private func postVariants(_ variants: [(String, [String: Any])], model: String, gate: ProviderGate) async throws -> Data {
        var lastError: Error?
        for (i, (label, body)) in variants.enumerated() {
            do {
                return try await post(body, model: model, gate: gate)
            } catch let e as AIError where e.status == 400 && e.kind == .badRequest && i < variants.count - 1 {
                RequestContext.current?.log(.info, "Gemini recusou o pedido \(label); repetindo com \(variants[i + 1].0).", details: e.details)
                lastError = e
            }
        }
        throw lastError ?? AIError("O Gemini não respondeu.")
    }

    func testKey() async throws {
        var req = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1")!)
        req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        _ = try await HTTP.send(req, label: "Gemini · teste da chave", attempts: 1)
    }

    private func post(_ body: [String: Any], model: String, gate: ProviderGate) async throws -> Data {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await HTTP.send(req, label: "Gemini · \(model)", gate: gate)
    }

    /// Motivo de bloqueio quando o Gemini informa (finishReason / blockReason).
    static func blockReason(in obj: Any) -> String? {
        var found: String?
        func walk(_ v: Any) {
            if found != nil { return }
            if let d = v as? [String: Any] {
                for key in ["blockReason", "block_reason", "finishReason", "finish_reason", "status"] {
                    if let s = d[key] as? String, !["STOP", "completed", "COMPLETED"].contains(s) { found = "\(key)=\(s)"; return }
                }
                d.values.forEach(walk)
            } else if let a = v as? [Any] { a.forEach(walk) }
        }
        walk(obj)
        return found
    }

    // MARK: leitura da resposta (tolerante a variações de formato)

    /// Procura a última imagem na resposta: output_image, steps[].content[] ou inlineData (formato antigo).
    static func findImage(in obj: Any) -> Data? {
        if let d = obj as? [String: Any] {
            if let out = d["output_image"] as? [String: Any], let s = out["data"] as? String, let img = HTTP.decodeBase64(s) {
                return img
            }
            // imagens finais ficam em steps do tipo model_output (as de "thought" são rascunhos)
            if let steps = d["steps"] as? [[String: Any]] {
                var last: Data?
                for step in steps where (step["type"] as? String) == "model_output" {
                    for c in (step["content"] as? [[String: Any]]) ?? [] where (c["type"] as? String) == "image" {
                        if let s = c["data"] as? String, let img = HTTP.decodeBase64(s) { last = img }
                    }
                }
                if let last { return last }
            }
        }
        var found: Data?
        func walk(_ v: Any) {
            if let d = v as? [String: Any] {
                if let t = d["type"] as? String, t == "image", let s = d["data"] as? String, let img = HTTP.decodeBase64(s) {
                    found = img
                }
                if let out = d["output_image"] as? [String: Any], let s = out["data"] as? String, let img = HTTP.decodeBase64(s) {
                    found = img
                }
                if let inline = (d["inlineData"] ?? d["inline_data"]) as? [String: Any],
                   let s = inline["data"] as? String, let img = HTTP.decodeBase64(s) {
                    found = img
                }
                for (k, child) in d where k != "output_image" { walk(child) }
            } else if let a = v as? [Any] {
                a.forEach(walk)
            }
        }
        walk(obj)
        return found
    }

    /// Junta o texto da saída do modelo (ignorando resumos de "pensamento").
    static func findText(in obj: Any) -> String {
        guard let d = obj as? [String: Any] else { return "" }
        if let t = d["output_text"] as? String, !t.isEmpty { return t }
        var parts: [String] = []
        if let steps = d["steps"] as? [[String: Any]] {
            for step in steps where (step["type"] as? String) == "model_output" {
                for c in (step["content"] as? [[String: Any]]) ?? [] where (c["type"] as? String) == "text" {
                    if let t = c["text"] as? String { parts.append(t) }
                }
            }
        }
        if parts.isEmpty, let cands = d["candidates"] as? [[String: Any]] {
            for c in cands {
                let ps = ((c["content"] as? [String: Any])?["parts"] as? [[String: Any]]) ?? []
                parts += ps.compactMap { $0["text"] as? String }
            }
        }
        return parts.joined(separator: "\n")
    }
}
