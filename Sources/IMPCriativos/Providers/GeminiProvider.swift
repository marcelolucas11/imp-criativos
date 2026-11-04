import Foundation

/// Google Gemini via Interactions API (v1beta/interactions).
/// Modelos padrão: gemini-nano-banana-2.1 (imagem) e gemini-3.5-flash-lite (análise).
struct GeminiProvider: AIProvider {
    let apiKey: String
    let imageModel: String
    let textModel: String
    let imageSize: String

    private let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/interactions")!

    func editImage(_ jpeg: Data, prompt: String, aspectRatio: String) async throws -> Data {
        let input: [[String: Any]] = [
            ["type": "text", "text": prompt],
            ["type": "image", "mime_type": "image/jpeg", "data": jpeg.base64EncodedString()],
        ]
        // 1ª tentativa: com proporção e resolução. Se o modelo recusar esses campos (HTTP 400),
        // tenta de novo sem eles — a exportação ajusta o tamanho final de qualquer jeito.
        let full: [String: Any] = [
            "model": imageModel,
            "input": input,
            "response_format": [
                "type": "image",
                "mime_type": "image/png",
                "aspect_ratio": aspectRatio,
                "image_size": imageSize,
            ],
        ]
        let minimal: [String: Any] = ["model": imageModel, "input": input]

        var data: Data
        do {
            data = try await post(full)
        } catch let e as AIError where e.message.contains("HTTP 400") && !e.message.lowercased().contains("api key") {
            data = try await post(minimal)
        }
        let obj = try HTTP.json(data)
        if let img = Self.findImage(in: obj) { return img }
        let text = Self.findText(in: obj)
        throw AIError(text.isEmpty
            ? "O Gemini não devolveu imagem (pode ter sido bloqueado pelo filtro de segurança)."
            : "O Gemini não devolveu imagem: \(text.prefix(200))")
    }

    func analyze(_ jpeg: Data, prompt: String) async throws -> String {
        let body: [String: Any] = [
            "model": textModel,
            "input": [
                ["type": "text", "text": prompt],
                ["type": "image", "mime_type": "image/jpeg", "data": jpeg.base64EncodedString()],
            ],
        ]
        let obj = try HTTP.json(try await post(body))
        let text = Self.findText(in: obj)
        if text.isEmpty { throw AIError("O Gemini não devolveu a análise.") }
        return text
    }

    func testKey() async throws {
        var req = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1")!)
        req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        _ = try await HTTP.send(req, attempts: 1)
    }

    private func post(_ body: [String: Any]) async throws -> Data {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await HTTP.send(req)
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
