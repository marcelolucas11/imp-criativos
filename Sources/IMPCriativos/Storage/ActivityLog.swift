import Foundation
import Combine

enum LogLevel: String, Codable, CaseIterable, Identifiable {
    case info, success, warning, error
    var id: String { rawValue }

    var label: String {
        switch self {
        case .info: return "Info"
        case .success: return "Sucesso"
        case .warning: return "Alerta"
        case .error: return "Erro"
        }
    }

    var symbol: String {
        switch self {
        case .info: return "info.circle"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }
}

enum LogCategory: String, Codable, CaseIterable, Identifiable {
    case lote, limpeza, analise, variacao, revisao, exportacao, ia, clientes, configuracoes, atualizacao, sistema
    var id: String { rawValue }

    var label: String {
        switch self {
        case .lote: return "Lote"
        case .limpeza: return "Limpeza"
        case .analise: return "Análise"
        case .variacao: return "Variação"
        case .revisao: return "Revisão"
        case .exportacao: return "Exportação"
        case .ia: return "IA / conexão"
        case .clientes: return "Clientes"
        case .configuracoes: return "Configurações"
        case .atualizacao: return "Atualização"
        case .sistema: return "Sistema"
        }
    }
}

struct LogEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var date = Date()
    var level: LogLevel
    var category: LogCategory
    var message: String
    var details: String?
    var jobID: UUID?
    var jobName: String?
    var item: String?

    /// Linha de texto pronta para copiar e colar numa conversa de suporte.
    var plainText: String {
        var s = "[\(LogEntry.stamp.string(from: date))] \(level.label.uppercased()) · \(category.label)"
        if let jobName { s += " · lote \"\(jobName)\"" }
        if let item { s += " · \(item)" }
        s += "\n  \(message)"
        if let details, !details.isEmpty {
            s += "\n  " + details.replacingOccurrences(of: "\n", with: "\n  ")
        }
        return s
    }

    static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "dd/MM/yyyy HH:mm:ss"
        return f
    }()
}

/// Histórico de movimentações, edições e erros.
/// Um arquivo JSON Lines por mês em Application Support/IMP Criativos/logs. Pode ser chamado de qualquer thread.
final class ActivityLog: ObservableObject, @unchecked Sendable {
    static let shared = ActivityLog()

    /// Mais recentes primeiro.
    @Published private(set) var entries: [LogEntry] = []
    @Published private(set) var lastSeen: Date

    private let queue = DispatchQueue(label: "com.imperaservices.impcriativos.log")
    private let maxInMemory = 15_000
    private let retentionMonths = 6

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static var folder: URL { Paths.ensure(Paths.appSupport.appendingPathComponent("logs", isDirectory: true)) }

    private init() {
        lastSeen = (UserDefaults.standard.object(forKey: "logLastSeen") as? Date) ?? Date()
        entries = loadFromDisk()
    }

    /// Erros desde a última vez que a tela Histórico foi aberta (para o selo na barra lateral).
    var unseenErrors: Int {
        var n = 0
        for e in entries {
            if e.date <= lastSeen { break }
            if e.level == .error { n += 1 }
        }
        return n
    }

    func markSeen() {
        lastSeen = Date()
        UserDefaults.standard.set(lastSeen, forKey: "logLastSeen")
    }

    func add(_ level: LogLevel, _ category: LogCategory, _ message: String, details: String? = nil,
             jobID: UUID? = nil, jobName: String? = nil, item: String? = nil) {
        let entry = LogEntry(level: level, category: category, message: message, details: details,
                             jobID: jobID, jobName: jobName, item: item)
        queue.async { [weak self] in self?.write(entry) }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.entries.insert(entry, at: 0)
            if self.entries.count > self.maxInMemory { self.entries.removeLast(self.entries.count - self.maxInMemory) }
        }
    }

    func clear() {
        queue.async {
            let files = (try? FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: nil)) ?? []
            files.forEach { try? FileManager.default.removeItem(at: $0) }
        }
        entries = []
        markSeen()
    }

    // MARK: disco

    private static let monthFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM"
        return f
    }()

    private func fileURL(for date: Date) -> URL {
        Self.folder.appendingPathComponent("\(Self.monthFormat.string(from: date)).jsonl")
    }

    private func write(_ entry: LogEntry) {
        guard var data = try? encoder.encode(entry) else { return }
        data.append(0x0A)
        let url = fileURL(for: entry.date)
        if let h = try? FileHandle(forWritingTo: url) {
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: data)
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func loadFromDisk() -> [LogEntry] {
        let fm = FileManager.default
        let files = ((try? fm.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "jsonl" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }

        // apaga meses além da retenção
        for old in files.dropFirst(retentionMonths) { try? fm.removeItem(at: old) }

        var out: [LogEntry] = []
        for file in files.prefix(retentionMonths) {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            var month: [LogEntry] = []
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                if let e = try? decoder.decode(LogEntry.self, from: Data(line.utf8)) { month.append(e) }
            }
            out += month.reversed()
            if out.count >= maxInMemory { break }
        }
        return Array(out.prefix(maxInMemory))
    }
}

/// Atalhos para registrar no histórico.
enum AppLog {
    static func info(_ c: LogCategory, _ m: String, details: String? = nil, jobID: UUID? = nil, jobName: String? = nil, item: String? = nil) {
        ActivityLog.shared.add(.info, c, m, details: details, jobID: jobID, jobName: jobName, item: item)
    }

    static func success(_ c: LogCategory, _ m: String, details: String? = nil, jobID: UUID? = nil, jobName: String? = nil, item: String? = nil) {
        ActivityLog.shared.add(.success, c, m, details: details, jobID: jobID, jobName: jobName, item: item)
    }

    static func warning(_ c: LogCategory, _ m: String, details: String? = nil, jobID: UUID? = nil, jobName: String? = nil, item: String? = nil) {
        ActivityLog.shared.add(.warning, c, m, details: details, jobID: jobID, jobName: jobName, item: item)
    }

    static func error(_ c: LogCategory, _ m: String, details: String? = nil, jobID: UUID? = nil, jobName: String? = nil, item: String? = nil) {
        ActivityLog.shared.add(.error, c, m, details: details, jobID: jobID, jobName: jobName, item: item)
    }
}
