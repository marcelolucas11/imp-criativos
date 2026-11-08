import Foundation

/// Tipo do erro: decide se vale tentar de novo, se cabe trocar de IA e o que mostrar na tela.
enum AIErrorKind: String, Codable {
    case temporary, rateLimit, network, timeout, blocked, auth, model, badRequest, other

    /// Erros que costumam passar sozinhos: servidor ocupado, limite por minuto, internet.
    var isTemporary: Bool { self == .temporary || self == .rateLimit || self == .network || self == .timeout }

    var title: String {
        switch self {
        case .temporary: return "IA sobrecarregada (temporário)"
        case .rateLimit: return "Limite de uso atingido (temporário)"
        case .network: return "Falha de conexão (temporário)"
        case .timeout: return "Tempo esgotado (temporário)"
        case .blocked: return "Bloqueado pelo filtro de conteúdo da IA"
        case .auth: return "Chave de API inválida ou sem permissão"
        case .model: return "Modelo não encontrado"
        case .badRequest: return "Pedido recusado pela IA"
        case .other: return "Erro"
        }
    }

    /// O que fazer a respeito.
    var hint: String {
        switch self {
        case .temporary: return "O servidor da IA estava cheio. Tente de novo em alguns minutos ou refaça com a outra IA."
        case .rateLimit: return "Sua conta atingiu o limite por minuto ou a cota. Espere um pouco, diminua os pedidos simultâneos ou confira o faturamento."
        case .network: return "Confira a internet do Mac e tente de novo."
        case .timeout: return "A IA não respondeu dentro do tempo limite (servidor lento ou travado). Tente de novo ou refaça com a outra IA."
        case .blocked: return "A IA recusou a imagem ou o pedido. Refaça com a outra IA ou deixe a instrução do cliente mais neutra."
        case .auth: return "Confira a chave em Configurações → Chaves de API e use o botão Testar."
        case .model: return "Confira o nome do modelo em Configurações → Modelos de IA (ou restaure os padrões)."
        case .badRequest: return "Copie o erro no Histórico e cole na conversa com o Claude para investigar."
        case .other: return "Copie o erro no Histórico e cole na conversa com o Claude para investigar."
        }
    }

    static func classify(status: Int, message: String) -> AIErrorKind {
        let m = message.lowercased()
        let blockedWords = ["safety", "blocked", "moderation", "content policy", "prohibited", "content_filter", "violat", "responsible ai"]
        switch status {
        case 408, 500...599: return .temporary
        case 429: return .rateLimit
        case 401, 403: return .auth
        case 404: return .model
        case 400, 422:
            // campo desconhecido/valor inválido (ex.: "safety_settings" ou "moderation" que o modelo não aceita)
            // é pedido inválido, não bloqueio — assim o app tenta de novo sem o campo.
            let fieldWords = ["unknown name", "unknown parameter", "unrecognized", "invalid json payload", "invalid value", "not supported", "unsupported"]
            if fieldWords.contains(where: { m.contains($0) }) { return .badRequest }
            if blockedWords.contains(where: { m.contains($0) }) { return .blocked }
            if m.contains("api key") || m.contains("api_key") { return .auth }
            return .badRequest
        default: return .other
        }
    }
}

struct AIError: LocalizedError {
    let message: String
    let kind: AIErrorKind
    let status: Int?
    /// Dados técnicos para o histórico (modelo, endereço, código, trecho da resposta).
    let details: String?

    init(_ message: String, kind: AIErrorKind = .other, status: Int? = nil, details: String? = nil) {
        self.message = message
        self.kind = kind
        self.status = status
        self.details = details
    }

    var retryable: Bool { kind.isTemporary }
    var errorDescription: String? { message }
}

extension Error {
    /// Tipo do erro (erros que não vieram da IA contam como "outro").
    var aiKind: AIErrorKind { (self as? AIError)?.kind ?? .other }
    var aiDetails: String? { (self as? AIError)?.details }
}

/// Contexto da chamada em andamento (qual lote, qual criativo, qual etapa).
/// Vai junto com a tarefa assíncrona sem precisar passar parâmetro por todas as funções.
struct RequestContext: Sendable {
    var jobID: UUID?
    var jobName: String?
    var item: String?
    var step: String = ""
    var category: LogCategory = .ia
    var maxAttempts: Int = 6
    /// 1.0.0-beta.9: tempo máximo de cada tentativa, em segundos (nil = padrão do tipo de pedido, ver `HTTP.defaultTimeout`).
    var timeout: TimeInterval?
    /// Avisa a tela: (texto, até quando) — nil limpa o aviso.
    var onStatus: (@Sendable (String?, Date?) -> Void)?

    @TaskLocal static var current: RequestContext? = nil

    func log(_ level: LogLevel, _ message: String, details: String? = nil) {
        let prefix = step.isEmpty ? "" : "\(step): "
        ActivityLog.shared.add(level, category, prefix + message, details: details, jobID: jobID, jobName: jobName, item: item)
    }
}

/// 1.0.0-beta.9: a tentativa passou do tempo máximo.
struct DeadlineExceeded: Error {}

enum HTTP {
    /// 1.0.0-beta.9: tempos máximos por tentativa (antes, qualquer pedido podia esperar até 10 minutos).
    static let analysisTimeout: TimeInterval = 90
    static let plannerTimeout: TimeInterval = 240
    static let imageTimeout: TimeInterval = 300
    /// Pedido de texto que passa disso entra no Histórico com o tempo que levou.
    static let slowTextSeconds: TimeInterval = 45

    /// Sem tempo definido pelo lote: imagem 5 min, texto 4 min (cobre o planejamento e as instruções do lote), resto 2 min.
    static func defaultTimeout(gate: ProviderGate?) -> TimeInterval {
        guard let gate else { return 120 }
        return gate.isImage ? imageTimeout : plannerTimeout
    }

    /// Roda `op` com prazo: passou de `seconds`, cancela o pedido e lança `DeadlineExceeded`.
    static func withDeadline<T: Sendable>(_ seconds: TimeInterval, _ op: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await op() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw DeadlineExceeded()
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw CancellationError() }
            return first
        }
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        return s < 60 ? "\(s)s" : String(format: "%dmin %02ds", s / 60, s % 60)
    }

    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 300
        c.timeoutIntervalForResource = 600
        c.waitsForConnectivity = true
        return URLSession(configuration: c)
    }()

    /// Espera antes da próxima tentativa: cresce a cada falha, com variação aleatória
    /// (para vários pedidos não voltarem todos no mesmo segundo) e respeita o Retry-After do servidor.
    static func backoff(attempt: Int, retryAfter: Double?) -> Double {
        let base: [Double] = [2, 5, 10, 20, 40, 60]
        let b = base[min(max(attempt - 1, 0), base.count - 1)]
        var delay = b * Double.random(in: 0.8...1.3)
        if let retryAfter, retryAfter > delay { delay = retryAfter }
        return min(delay, 90)
    }

    /// Envia a requisição. Em erro temporário (429, 5xx, rede) tenta de novo com espera crescente.
    /// - label: "Gemini · modelo", usado nos avisos e no histórico.
    /// - gate: limita quantos pedidos vão ao mesmo tempo para a mesma IA e segura os outros quando ela está sobrecarregada.
    /// - attempts: força um número de tentativas (senão usa o do contexto do lote, ou 4).
    static func send(_ request: URLRequest, label: String = "", gate: ProviderGate? = nil, attempts: Int? = nil) async throws -> Data {
        let ctx = RequestContext.current
        let maxAttempts = max(1, attempts ?? ctx?.maxAttempts ?? 4)
        let name = label.isEmpty ? (request.url?.host ?? "servidor") : label
        let shortName = name.components(separatedBy: " · ").first ?? name
        var lastError = AIError("Falha desconhecida")
        let timeout = ctx?.timeout ?? defaultTimeout(gate: gate)
        var timedRequest = request
        timedRequest.timeoutInterval = timeout
        let sendable = timedRequest

        for attempt in 1...maxAttempts {
            var retryAfter: Double?
            let started = Date()
            do {
                if let gate {
                    try await gate.acquire { seconds, until in
                        ctx?.onStatus?("\(shortName) ocupado — aguardando vez (\(seconds)s)", until)
                    }
                }
                let result: (Data, URLResponse)
                do {
                    result = try await withDeadline(timeout) { try await session.data(for: sendable) }
                    if let gate { await gate.release() }
                } catch {
                    if let gate { await gate.release() }
                    throw error
                }
                let (data, response) = result
                guard let http = response as? HTTPURLResponse else {
                    throw AIError("Resposta inválida do servidor", kind: .network)
                }
                if (200..<300).contains(http.statusCode) {
                    let took = Date().timeIntervalSince(started)
                    // 1.0.0-beta.19: o Modo rápido com segurança mede o tempo de cada imagem
                    if let gate { await gate.reportSuccess(seconds: took) }
                    if let gate, !gate.isImage, took > slowTextSeconds {
                        ctx?.log(.info, "\(name) respondeu, mas demorou \(duration(took)).")
                    }
                    if attempt > 1 {
                        ctx?.log(.success, "\(name) respondeu na tentativa \(attempt) de \(maxAttempts).")
                        ctx?.onStatus?(nil, nil)
                    }
                    return data
                }
                let raw = apiErrorMessage(data) ?? "HTTP \(http.statusCode)"
                let kind = AIErrorKind.classify(status: http.statusCode, message: raw)
                if let ra = http.value(forHTTPHeaderField: "Retry-After"), let secs = Double(ra.trimmingCharacters(in: .whitespaces)) {
                    retryAfter = secs
                }
                let secs = String(format: "%.1f", Date().timeIntervalSince(started))
                let details = """
                \(name) · \(request.httpMethod ?? "GET") \(request.url?.host ?? "")\(request.url?.path ?? "")
                HTTP \(http.statusCode) · \(secs)s · tentativa \(attempt)/\(maxAttempts)
                Resposta: \(String(decoding: data.prefix(700), as: UTF8.self))
                """
                let err = AIError("\(raw) (HTTP \(http.statusCode))", kind: kind, status: http.statusCode, details: details)
                if !kind.isTemporary { throw err }
                lastError = err
                // servidor cheio: segura também os outros pedidos para esta IA
                if let gate, kind == .temporary || kind == .rateLimit {
                    await gate.pause(for: backoff(attempt: attempt, retryAfter: retryAfter) * 0.7)
                    await gate.reportTrouble("\(shortName) respondeu \(kind == .rateLimit ? "limite de uso" : "ocupado") (HTTP \(http.statusCode))")
                }
            } catch let e as AIError {
                if !e.retryable { throw e }
                lastError = e
                if let gate { await gate.reportTrouble("\(shortName): \(e.kind.title.lowercased())") }
            } catch is CancellationError {
                throw CancellationError()
            } catch let e as URLError where e.code == .cancelled {
                if Task.isCancelled { throw CancellationError() }
                lastError = timeoutError(name, request, attempt, maxAttempts, timeout, e)
                if let gate { await gate.reportTrouble("\(shortName) não respondeu a tempo") }
            } catch is DeadlineExceeded {
                lastError = timeoutError(name, request, attempt, maxAttempts, timeout, nil)
                if let gate { await gate.reportTrouble("\(shortName) não respondeu em \(duration(timeout))") }
            } catch let e as URLError where e.code == .timedOut {
                lastError = timeoutError(name, request, attempt, maxAttempts, timeout, e)
                if let gate { await gate.reportTrouble("\(shortName) não respondeu a tempo") }
            } catch {
                lastError = AIError("Erro de conexão: \(error.localizedDescription)", kind: .network,
                                    details: "\(name) · \(request.url?.host ?? "") · tentativa \(attempt)/\(maxAttempts)\n\(error)")
                if let gate { await gate.reportTrouble("falha de conexão com \(shortName)") }
            }

            guard attempt < maxAttempts else { break }
            let delay = backoff(attempt: attempt, retryAfter: retryAfter)
            let code = lastError.status.map { " (\($0))" } ?? ""
            ctx?.log(.warning,
                     "\(name): \(lastError.kind.title)\(code). Tentativa \(attempt) de \(maxAttempts); nova tentativa em \(Int(delay.rounded()))s.",
                     details: lastError.details)
            let state = lastError.kind == .network ? "sem conexão" : lastError.kind == .timeout ? "não respondeu" : "ocupado"
            ctx?.onStatus?("\(shortName) \(state)\(code) · tentativa \(attempt + 1)/\(maxAttempts)",
                           Date().addingTimeInterval(delay))
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        ctx?.onStatus?(nil, nil)
        if maxAttempts > 1 {
            throw AIError("\(lastError.message) — desistiu após \(maxAttempts) tentativas", kind: lastError.kind,
                          status: lastError.status, details: lastError.details)
        }
        throw lastError
    }

    private static func timeoutError(_ name: String, _ request: URLRequest, _ attempt: Int, _ maxAttempts: Int,
                                     _ timeout: TimeInterval, _ underlying: Error?) -> AIError {
        AIError("A IA não respondeu em \(duration(timeout))", kind: .timeout,
                details: "\(name) · \(request.url?.host ?? "") · tentativa \(attempt)/\(maxAttempts) · limite \(duration(timeout))"
                    + (underlying.map { "\n\($0)" } ?? ""))
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
        catch {
            throw AIError("Resposta da IA não é um JSON válido", kind: .other,
                          details: String(decoding: data.prefix(700), as: UTF8.self))
        }
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
