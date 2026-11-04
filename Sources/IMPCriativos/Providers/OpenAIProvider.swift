import Foundation

/// OpenAI: edição em /v1/images/edits (gpt-image-2) e análise em /v1/chat/completions (gpt-5-mini).
struct OpenAIProvider: AIProvider {
    let apiKey: String
    let imageModel: String
    let textModel: String
    let quality: String

    func editImage(_ jpeg: Data, prompt: String, aspectRatio: String) async throws -> Data {
        do {
            return try await editOnce(jpeg, prompt: prompt, aspectRatio: aspectRatio)
        } catch let e as AIError where e.kind == .blocked {
            // Bloqueio por conteúdo: uma nova tentativa com a instrução reformulada em tom neutro.
            RequestContext.current?.log(.info, "OpenAI bloqueou o pedido; tentando de novo com instrução neutra.", details: e.details)
            RequestContext.current?.onStatus?("OpenAI bloqueou · tentando com instrução neutra…", nil)
            return try await editOnce(jpeg, prompt: Prompts.neutral(prompt), aspectRatio: aspectRatio)
        }
    }

    private func editOnce(_ jpeg: Data, prompt: String, aspectRatio: String) async throws -> Data {
        // Formatos verticais (4:5, 9:16) saem em retrato; a exportação ajusta para 1080×1350 ou 1080×1920.
        let vertical = ["4:5", "9:16", "3:4", "2:3"].contains(aspectRatio)
        // moderation "low" = filtro menos restritivo que a OpenAI permite. Se o modelo recusar
        // algum campo (HTTP 400), tenta sem ele.
        var variants: [(label: String, size: String, low: Bool)] = []
        if vertical { variants.append(("vertical", "1024x1536", true)) }
        variants.append(("tamanho automático", "auto", true))
        variants.append(("sem ajuste de moderação", vertical ? "1024x1536" : "auto", false))
        var lastError: Error?
        for (i, v) in variants.enumerated() {
            do {
                return try await edit(jpeg, prompt: prompt, size: v.size, lowModeration: v.low)
            } catch let e as AIError where e.status == 400 && e.kind == .badRequest && i < variants.count - 1 {
                RequestContext.current?.log(.info, "OpenAI recusou o pedido (\(v.label)); repetindo com \(variants[i + 1].label).", details: e.details)
                lastError = e
            }
        }
        throw lastError ?? AIError("A OpenAI não respondeu.")
    }

    private func edit(_ jpeg: Data, prompt: String, size: String, lowModeration: Bool) async throws -> Data {
        var form = Multipart()
        form.field("model", imageModel)
        form.field("prompt", prompt)
        form.field("size", size)
        if lowModeration { form.field("moderation", "low") }
        if !quality.isEmpty { form.field("quality", quality) }
        form.file("image", filename: "criativo.jpg", mime: "image/jpeg", data: jpeg)

        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/images/edits")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        req.httpBody = form.finish()

        let obj = try HTTP.json(try await HTTP.send(req, label: "OpenAI · \(imageModel)", gate: .image(.openai)))
        guard let d = obj as? [String: Any], let first = (d["data"] as? [[String: Any]])?.first else {
            throw AIError("A OpenAI não devolveu imagem.", kind: .blocked)
        }
        if let b64 = first["b64_json"] as? String, let img = HTTP.decodeBase64(b64) { return img }
        if let urlString = first["url"] as? String, let url = URL(string: urlString) {
            return try await HTTP.send(URLRequest(url: url), label: "OpenAI · download da imagem")
        }
        throw AIError("A OpenAI não devolveu imagem.", kind: .blocked)
    }

    func analyze(_ jpeg: Data, prompt: String) async throws -> String {
        let body: [String: Any] = [
            "model": textModel,
            "response_format": ["type": "json_object"],
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "text", "text": prompt],
                    ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(jpeg.base64EncodedString())"]],
                ],
            ]],
        ]
        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let obj = try HTTP.json(try await HTTP.send(req, label: "OpenAI · \(textModel)", gate: .text(.openai)))
        guard let d = obj as? [String: Any],
              let choice = (d["choices"] as? [[String: Any]])?.first,
              let msg = choice["message"] as? [String: Any],
              let text = msg["content"] as? String, !text.isEmpty else {
            throw AIError("A OpenAI não devolveu a análise.", kind: .blocked)
        }
        return text
    }

    func testKey() async throws {
        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        _ = try await HTTP.send(req, label: "OpenAI · teste da chave", attempts: 1)
    }
}
