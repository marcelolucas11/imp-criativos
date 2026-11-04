import Foundation

/// OpenAI: edição em /v1/images/edits (gpt-image-2) e análise em /v1/chat/completions (gpt-5-mini).
struct OpenAIProvider: AIProvider {
    let apiKey: String
    let imageModel: String
    let textModel: String
    let quality: String

    func editImage(_ jpeg: Data, prompt: String, aspectRatio: String) async throws -> Data {
        // Formatos verticais (4:5, 9:16) saem em retrato; a exportação ajusta para 1080×1350 ou 1080×1920.
        let vertical = ["4:5", "9:16", "3:4", "2:3"].contains(aspectRatio)
        do {
            return try await edit(jpeg, prompt: prompt, size: vertical ? "1024x1536" : "auto")
        } catch let e as AIError where vertical && e.message.contains("HTTP 400") && !e.message.lowercased().contains("api key") {
            return try await edit(jpeg, prompt: prompt, size: "auto")
        }
    }

    private func edit(_ jpeg: Data, prompt: String, size: String) async throws -> Data {
        var form = Multipart()
        form.field("model", imageModel)
        form.field("prompt", prompt)
        form.field("size", size)
        if !quality.isEmpty { form.field("quality", quality) }
        form.file("image", filename: "criativo.jpg", mime: "image/jpeg", data: jpeg)

        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/images/edits")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        req.httpBody = form.finish()

        let obj = try HTTP.json(try await HTTP.send(req))
        guard let d = obj as? [String: Any], let first = (d["data"] as? [[String: Any]])?.first else {
            throw AIError("A OpenAI não devolveu imagem.")
        }
        if let b64 = first["b64_json"] as? String, let img = HTTP.decodeBase64(b64) { return img }
        if let urlString = first["url"] as? String, let url = URL(string: urlString) {
            return try await HTTP.send(URLRequest(url: url))
        }
        throw AIError("A OpenAI não devolveu imagem.")
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

        let obj = try HTTP.json(try await HTTP.send(req))
        guard let d = obj as? [String: Any],
              let choice = (d["choices"] as? [[String: Any]])?.first,
              let msg = choice["message"] as? [String: Any],
              let text = msg["content"] as? String, !text.isEmpty else {
            throw AIError("A OpenAI não devolveu a análise.")
        }
        return text
    }

    func testKey() async throws {
        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        _ = try await HTTP.send(req, attempts: 1)
    }
}
