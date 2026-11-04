import Foundation

struct AIError: LocalizedError {
    let message: String
    let retryable: Bool
    init(_ message: String, retryable: Bool = false) {
        self.message = message
        self.retryable = retryable
    }
    var errorDescription: String? { message }
}

enum HTTP {
    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 300
        c.timeoutIntervalForResource = 600
        c.waitsForConnectivity = true
        return URLSession(configuration: c)
    }()

    /// Envia a requisição com até 3 novas tentativas em erros temporários (429, 5xx, rede).
    static func send(_ request: URLRequest, attempts: Int = 4) async throws -> Data {
        var lastError: Error = AIError("Falha desconhecida")
        for attempt in 0..<attempts {
            if attempt > 0 {
                let delay = [0, 3, 8, 20][min(attempt, 3)]
                try await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
            }
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw AIError("Resposta inválida do servidor") }
                if (200..<300).contains(http.statusCode) { return data }
                let msg = apiErrorMessage(data) ?? "HTTP \(http.statusCode)"
                let retry = http.statusCode == 429 || http.statusCode >= 500
                let err = AIError("\(msg) (HTTP \(http.statusCode))", retryable: retry)
                if !retry { throw err }
                lastError = err
            } catch let e as AIError {
                if !e.retryable { throw e }
                lastError = e
            } catch is CancellationError {
                throw CancellationError()
            } catch let e as URLError where e.code == .cancelled {
                throw CancellationError()
            } catch {
                lastError = AIError("Erro de conexão: \(error.localizedDescription)", retryable: true)
            }
        }
        throw lastError
    }

    static func apiErrorMessage(_ data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let s = String(decoding: data.prefix(300), as: UTF8.self)
            return s.isEmpty ? nil : s
        }
        if let err = obj["error"] as? [String: Any], let m = err["message"] as? String { return m }
        if let m = obj["message"] as? String { return m }
        return nil
    }

    static func json(_ data: Data) throws -> Any {
        do { return try JSONSerialization.jsonObject(with: data) }
        catch { throw AIError("Resposta da IA não é um JSON válido") }
    }

    /// Remove o prefixo "data:image/png;base64," quando vier.
    static func decodeBase64(_ s: String) -> Data? {
        let raw = s.range(of: "base64,").map { String(s[$0.upperBound...]) } ?? s
        return Data(base64Encoded: raw, options: .ignoreUnknownCharacters)
    }
}

/// Monta corpo multipart/form-data (usado no endpoint de edição da OpenAI).
struct Multipart {
    let boundary = "IMPBoundary-\(UUID().uuidString)"
    private(set) var body = Data()

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func field(_ name: String, _ value: String) {
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
    }

    mutating func file(_ name: String, filename: String, mime: String, data: Data) {
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\nContent-Type: \(mime)\r\n\r\n")
        body.append(data)
        body.append("\r\n")
    }

    mutating func finish() -> Data {
        body.append("--\(boundary)--\r\n")
        return body
    }
}

private extension Data {
    mutating func append(_ s: String) { append(Data(s.utf8)) }
}

/// Extrai o primeiro objeto JSON {…} de um texto (a IA às vezes envolve em ```json).
enum JSONExtract {
    static func object(from text: String) -> [String: Any]? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return nil }
        let slice = String(text[start...end])
        return (try? JSONSerialization.jsonObject(with: Data(slice.utf8))) as? [String: Any]
    }
}
