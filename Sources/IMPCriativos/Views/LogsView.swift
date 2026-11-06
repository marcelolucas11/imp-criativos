import SwiftUI
import AppKit

/// Histórico de movimentações, edições e erros, com filtros e cópia pronta para colar numa conversa de suporte.
struct LogsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var log: ActivityLog
    @EnvironmentObject var settings: AppSettings

    enum LevelFilter: String, CaseIterable, Identifiable {
        case all = "Tudo", problems = "Erros e alertas", errors = "Só erros"
        var id: String { rawValue }
    }

    enum Period: String, CaseIterable, Identifiable {
        case today = "Hoje", week = "Últimos 7 dias", month = "Últimos 30 dias", all = "Tudo"
        var id: String { rawValue }

        var start: Date? {
            let cal = Calendar.current
            switch self {
            case .today: return cal.startOfDay(for: Date())
            case .week: return cal.date(byAdding: .day, value: -7, to: Date())
            case .month: return cal.date(byAdding: .day, value: -30, to: Date())
            case .all: return nil
            }
        }
    }

    @State private var search = ""
    @State private var level: LevelFilter = .all
    @State private var category: LogCategory?
    @State private var jobFilter: UUID?
    @State private var period: Period = .week
    @State private var selection: LogEntry.ID?
    @State private var confirmClear = false
    @State private var flash: String?

    private let maxRows = 3000

    private var filtered: [LogEntry] {
        let start = period.start
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return log.entries.filter { e in
            if let start, e.date < start { return false }
            switch level {
            case .all: break
            case .problems: if e.level != .error && e.level != .warning { return false }
            case .errors: if e.level != .error { return false }
            }
            if let category, e.category != category { return false }
            if let jobFilter, e.jobID != jobFilter { return false }
            if !q.isEmpty {
                let hay = [e.message, e.details ?? "", e.jobName ?? "", e.item ?? "", e.category.label].joined(separator: " ").lowercased()
                if !hay.contains(q) { return false }
            }
            return true
        }
    }

    struct JobOption: Identifiable {
        let id: UUID
        let name: String
    }

    /// Lotes que aparecem no histórico (mais recentes primeiro).
    private var jobOptions: [JobOption] {
        var seen = Set<UUID>()
        var out: [JobOption] = []
        for e in log.entries {
            guard let id = e.jobID, !seen.contains(id) else { continue }
            seen.insert(id)
            out.append(JobOption(id: id, name: e.jobName ?? "Lote"))
        }
        return out
    }

    var body: some View {
        let rows = filtered
        let shown = Array(rows.prefix(maxRows))
        VStack(spacing: 0) {
            header(rows)
            Divider()
            if shown.isEmpty {
                ContentUnavailableView("Nada por aqui",
                                       systemImage: "list.bullet.rectangle",
                                       description: Text(log.entries.isEmpty
                                           ? "As movimentações, edições e erros vão aparecer aqui."
                                           : "Nenhum registro com esses filtros."))
            } else {
                VSplitView {
                    table(shown)
                        .frame(minHeight: 220)
                    detail(shown.first { $0.id == selection })
                        .frame(minHeight: 150, idealHeight: 220)
                }
            }
        }
        .onAppear {
            log.markSeen()
            applyJobFilterFromModel()
        }
        .onDisappear { log.markSeen() }
        .onChange(of: model.logJobFilter) { _, _ in applyJobFilterFromModel() }
        .confirmationDialog("Apagar todo o histórico?", isPresented: $confirmClear) {
            Button("Apagar histórico", role: .destructive) {
                log.clear()
                selection = nil
            }
        } message: {
            Text("Os lotes e imagens não são afetados, só os registros.")
        }
    }

    private func applyJobFilterFromModel() {
        guard let id = model.logJobFilter else { return }
        jobFilter = id
        period = .all
        level = .all
        category = nil
        search = ""
        model.logJobFilter = nil
    }

    // MARK: cabeçalho

    @ViewBuilder
    private func header(_ rows: [LogEntry]) -> some View {
        let errors = rows.filter { $0.level == .error }.count
        let warnings = rows.filter { $0.level == .warning }.count
        VStack(alignment: .leading, spacing: 12) {
            PageHeader(title: "Histórico",
                       subtitle: "Movimentações, edições e erros. Para buscar uma solução, copie o erro ou o diagnóstico e cole na conversa com o Claude.")

            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Buscar (ex.: 503, nome do criativo, chave)", text: $search)
                        .textFieldStyle(.plain)
                    if !search.isEmpty {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.borderless).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: 7))
                .frame(minWidth: 220, maxWidth: 320)

                Picker("", selection: $level) {
                    ForEach(LevelFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 290)

                Picker("Categoria", selection: $category) {
                    Text("Todas as categorias").tag(LogCategory?.none)
                    Divider()
                    ForEach(LogCategory.allCases) { Text($0.label).tag(LogCategory?.some($0)) }
                }
                .labelsHidden()
                .fixedSize()

                Picker("Lote", selection: $jobFilter) {
                    Text("Todos os lotes").tag(UUID?.none)
                    Divider()
                    ForEach(jobOptions) { option in
                        Text(option.name).tag(UUID?.some(option.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 200)

                Picker("Período", selection: $period) {
                    ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }

            HStack(spacing: 14) {
                Text("\(rows.count) registro(s)").foregroundStyle(.secondary)
                if errors > 0 { Label("\(errors) erro(s)", systemImage: "xmark.octagon.fill").foregroundStyle(Brand.red) }
                if warnings > 0 { Label("\(warnings) alerta(s)", systemImage: "exclamationmark.triangle.fill").foregroundStyle(Brand.warning) }
                if rows.count > maxRows {
                    Text("mostrando os \(maxRows) mais recentes").foregroundStyle(.secondary)
                }
                if let flash {
                    Label(flash, systemImage: "checkmark.circle.fill").foregroundStyle(Brand.success).transition(.opacity)
                }
                Spacer()
                Button {
                    Clipboard.copy(diagnostic(rows))
                    showFlash("Diagnóstico copiado — cole na conversa com o Claude")
                } label: { Label("Copiar diagnóstico", systemImage: "stethoscope") }
                .help("Copia versão do app, configuração (sem chaves) e os registros filtrados (até 300).")
                .disabled(rows.isEmpty)

                Menu {
                    Button("Exportar registros filtrados…") { export(rows) }.disabled(rows.isEmpty)
                    Button("Abrir pasta dos registros") { AppInfo.open(ActivityLog.folder) }
                    Divider()
                    Button("Apagar histórico…", role: .destructive) { confirmClear = true }
                } label: {
                    Label("Mais", systemImage: "ellipsis.circle")
                }
                .fixedSize()
            }
            .font(.callout)
        }
        .padding(20)
        .background(Color(white: 0.09))
    }

    // MARK: tabela

    private func table(_ rows: [LogEntry]) -> some View {
        Table(rows, selection: $selection) {
            TableColumn("Quando") { e in
                Text(LogEntry.stamp.string(from: e.date)).monospacedDigit().foregroundStyle(.secondary)
            }
            .width(min: 125, ideal: 135, max: 150)

            TableColumn("Tipo") { e in
                Label(e.level.label, systemImage: e.level.symbol).foregroundStyle(color(e.level))
            }
            .width(min: 75, ideal: 85, max: 100)

            TableColumn("Categoria") { e in
                Text(e.category.label)
            }
            .width(min: 80, ideal: 100, max: 130)

            TableColumn("Lote · criativo") { e in
                Text([e.jobName, e.item].compactMap { $0 }.joined(separator: " · "))
                    .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
            }
            .width(min: 110, ideal: 190, max: 320)

            TableColumn("O que aconteceu") { e in
                Text(e.message).lineLimit(2)
            }
        }
        .contextMenu(forSelectionType: LogEntry.ID.self) { ids in
            let picked = rows.filter { ids.contains($0.id) }
            Button("Copiar (para colar no Claude)") {
                Clipboard.copy(picked.map(\.plainText).joined(separator: "\n\n"))
                showFlash("Copiado")
            }
            .disabled(picked.isEmpty)
            if let first = picked.first, let jobID = first.jobID {
                Button("Abrir o lote") { model.selection = .job(jobID) }
            }
        }
    }

    // MARK: detalhe

    @ViewBuilder
    private func detail(_ entry: LogEntry?) -> some View {
        if let e = entry {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Label(e.level.label, systemImage: e.level.symbol).foregroundStyle(color(e.level)).font(.headline)
                    Text(e.category.label).foregroundStyle(.secondary)
                    Text(LogEntry.stamp.string(from: e.date)).monospacedDigit().foregroundStyle(.secondary)
                    Spacer()
                    if let jobID = e.jobID {
                        Button("Abrir o lote") { model.selection = .job(jobID) }
                    }
                    Button {
                        Clipboard.copy(e.plainText)
                        showFlash("Registro copiado")
                    } label: { Label("Copiar este registro", systemImage: "doc.on.doc") }
                    Button {
                        Clipboard.copy(diagnostic(context(around: e)))
                        showFlash("Registro e contexto copiados")
                    } label: { Label("Copiar com contexto", systemImage: "doc.on.doc.fill") }
                    .help("Copia este registro, os 20 registros em volta e a configuração do app.")
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if let name = e.jobName {
                            Text("Lote: \(name)" + (e.item.map { " · Criativo: \($0)" } ?? "")).foregroundStyle(.secondary)
                        }
                        Text(e.message).font(.body).textSelection(.enabled)
                        if let d = e.details, !d.isEmpty {
                            Text(d)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Brand.surface)
        } else {
            Text("Selecione um registro para ver os detalhes técnicos.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Brand.surface)
        }
    }

    // MARK: utilidades

    private func color(_ level: LogLevel) -> Color {
        switch level {
        case .info: return .secondary
        case .success: return Brand.success
        case .warning: return Brand.warning
        case .error: return Brand.red
        }
    }

    private func showFlash(_ text: String) {
        withAnimation { flash = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { withAnimation { if flash == text { flash = nil } } }
    }

    /// O registro e os 10 antes e 10 depois dele no histórico completo.
    private func context(around entry: LogEntry) -> [LogEntry] {
        guard let i = log.entries.firstIndex(where: { $0.id == entry.id }) else { return [entry] }
        let lo = max(0, i - 10)
        let hi = min(log.entries.count, i + 11)
        return Array(log.entries[lo..<hi])
    }

    private var filterDescription: String {
        var parts = [level.rawValue, period.rawValue]
        if let category { parts.append(category.label) }
        if let jobFilter, let name = jobOptions.first(where: { $0.id == jobFilter })?.name { parts.append("lote \"\(name)\"") }
        if !search.isEmpty { parts.append("busca \"\(search)\"") }
        return parts.joined(separator: " · ")
    }

    /// Texto para colar numa conversa de suporte: versão, configuração (sem chaves) e registros.
    private func diagnostic(_ entries: [LogEntry], limit: Int = 300) -> String {
        var lines: [String] = [
            "=== Diagnóstico IMP Criativos ===",
            "Versão: \(AppInfo.version) (build \(AppInfo.build)) · macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Gerado em: \(LogEntry.stamp.string(from: Date()))",
            "Chaves: Gemini \(APIKeyStore.hasKey(.gemini) ? "salva" : "não configurada") · OpenAI \(APIKeyStore.hasKey(.openai) ? "salva" : "não configurada")",
            settings.summary,
            "Filtro: \(filterDescription)",
            "",
            "--- Registros (mais recentes primeiro; \(min(limit, entries.count)) de \(entries.count)) ---",
        ]
        lines += entries.prefix(limit).map(\.plainText)
        return lines.joined(separator: "\n")
    }

    private func export(_ rows: [LogEntry]) {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmm"
        guard let url = Pickers.saveFile(title: "Exportar histórico", name: "imp-criativos-historico_\(f.string(from: Date())).txt") else { return }
        do {
            try diagnostic(rows, limit: rows.count).write(to: url, atomically: true, encoding: .utf8)
            showFlash("Exportado")
            AppInfo.reveal(url)
        } catch {
            AppLog.error(.sistema, "Não foi possível exportar o histórico: \(error.localizedDescription)", details: url.path)
        }
    }
}
