import SwiftUI

struct PreviewItem: Identifiable {
    let id = UUID()
    let title: String
    let url: URL
    let compare: URL?
}

struct JobDetailView: View {
    let jobID: UUID
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var jobs: JobStore
    @EnvironmentObject var runner: JobRunner
    @EnvironmentObject var settings: AppSettings

    enum Filter: String, CaseIterable, Identifiable {
        case all = "Todos", warnings = "Com alerta", pending = "Revisão pendente", failed = "Com falha"
        var id: String { rawValue }
    }

    @State private var filter: Filter = .all
    @State private var preview: PreviewItem?
    @State private var exportMessage: String?
    @State private var exportedFolder: URL?
    @State private var exporting = false
    @State private var confirmDelete = false
    @ObservedObject private var speed = SpeedMonitor.shared

    var body: some View {
        if let job = jobs.job(jobID) {
            VStack(spacing: 0) {
                header(job)
                Divider()
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filtered(job)) { item in
                            ItemCard(job: job, item: item, preview: $preview)
                        }
                        if filtered(job).isEmpty {
                            Text("Nada neste filtro.").foregroundStyle(.secondary).padding(40)
                        }
                    }
                    .padding(20)
                }
            }
            .sheet(item: $preview) { PreviewSheet(item: $0) }
            .alert("Exportação", isPresented: Binding(get: { exportMessage != nil }, set: { if !$0 { exportMessage = nil } })) {
                if let exportedFolder { Button("Mostrar no Finder") { AppInfo.reveal(exportedFolder) } }
                Button("OK", role: .cancel) {}
            } message: { Text(exportMessage ?? "") }
            .confirmationDialog("Excluir este lote?", isPresented: $confirmDelete) {
                Button("Excluir lote e imagens intermediárias", role: .destructive) {
                    runner.cancel(jobID)
                    if let job = jobs.job(jobID) { AppLog.warning(.lote, "Lote excluído.", jobID: jobID, jobName: job.name) }
                    model.selection = .home
                    jobs.delete(jobID)
                }
            } message: {
                Text("Os arquivos já exportados não são apagados.")
            }
        } else {
            Text("Lote não encontrado.").foregroundStyle(.secondary)
        }
    }

    private func filtered(_ job: Job) -> [JobItem] {
        switch filter {
        case .all: return job.items
        case .warnings: return job.items.filter { $0.hasWarning }
        case .failed: return job.items.filter { $0.hasFailure }
        case .pending:
            return job.items.filter { item in
                (item.cleanStatus == .done && item.cleanReview == .pending) ||
                    item.variations.contains { $0.status == .done && $0.review == .pending }
            }
        }
    }

    @ViewBuilder
    private func header(_ job: Job) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        Text(job.name).font(.system(size: 22, weight: .bold))
                        StatePill(state: job.state)
                    }
                    Text("\(job.client.name) · \(job.items.count) criativos · \(job.variationsPerItem) variações\(job.isAxisTest ? " (teste de eixos)" : "") · limpeza: \(job.cleanProvider.label) · variações: \(job.variationProvider.label) · saída: \(job.sizeMode.label) \(job.format.label)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(job.costUSD.usd).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    .help("Gasto estimado deste lote")
            }

            if let ins = job.instructions, !ins.isEmpty {
                Label {
                    Text(ins.summary).font(.caption).lineLimit(2)
                } icon: {
                    Image(systemName: "text.bubble").foregroundStyle(Brand.red)
                }
                .help("Instruções deste lote:\n\(ins.raw)\n\n\(ins.summary)")
            }

            HStack(spacing: 10) {
                ProgressView(value: job.progress)
                Text("\(job.finishedSteps)/\(job.totalSteps)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }

            // 1.0.0-beta.19: velocidade da IA das variações enquanto o lote roda
            if job.state == .running, let snap = speed.snapshots[job.variationProvider] {
                Label(snap.line, systemImage: snap.inSafeMode ? "shield.lefthalf.filled" : "speedometer")
                    .font(.caption)
                    .foregroundStyle(snap.inSafeMode ? Brand.warning : .secondary)
                    .help("Configurações → Velocidade. A velocidade só muda quantos pedidos vão juntos; a qualidade não muda.")
            }

            failureSummary(job)

            if let err = job.lastError {
                HStack {
                    ErrorLabel(text: err)
                    if err.contains("Chave") { Button("Configurações") { model.selection = .settings } }
                }
            }

            HStack(spacing: 8) {
                switch job.state {
                case .running:
                    Button { runner.pause(jobID) } label: { Label("Pausar", systemImage: "pause.fill") }
                case .paused, .queued:
                    Button { runner.start(jobID) } label: { Label("Retomar", systemImage: "play.fill") }
                        .buttonStyle(.borderedProminent)
                default:
                    EmptyView()
                }
                if job.failureCount > 0 {
                    Button { runner.retryFailed(jobID) } label: {
                        Label("Tentar falhas de novo (\(job.failureCount))", systemImage: "arrow.clockwise")
                    }
                    .help("Volta para a fila tudo que falhou, usando a mesma IA (com troca automática se estiver ligada).")
                }

                Picker("", selection: $filter) {
                    ForEach(Filter.allCases) { f in Text(f.rawValue).tag(f) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 440)

                Spacer()

                Menu {
                    Button("Aprovar pendentes sem alerta") { bulkApprove(onlyClean: true) }
                    Button("Aprovar todos os pendentes") { bulkApprove(onlyClean: false) }
                    if job.failureCount > 0 {
                        Divider()
                        ForEach(ProviderKind.allCases) { kind in
                            Button("Refazer falhas com \(kind.label)") { runner.retryFailed(jobID, using: kind) }
                                .disabled(!APIKeyStore.hasKey(kind))
                        }
                    }
                    Divider()
                    Button("Ver histórico deste lote") {
                        model.logJobFilter = jobID
                        model.selection = .logs
                    }
                    Button("Abrir pasta dos originais") { AppInfo.open(URL(fileURLWithPath: job.inputFolder)) }
                    Button("Abrir pasta de trabalho do lote") { AppInfo.open(jobs.folder(for: jobID)) }
                    Divider()
                    if job.state == .running || job.state == .paused {
                        Button("Cancelar lote", role: .destructive) { runner.cancel(jobID) }
                    }
                    Button("Excluir lote…", role: .destructive) { confirmDelete = true }
                } label: {
                    Label("Ações", systemImage: "ellipsis.circle")
                }
                .fixedSize()

                Button {
                    Task { await export(job) }
                } label: {
                    if exporting { ProgressView().controlSize(.small) }
                    else { Label("Baixar aprovados (\(job.approvedCount))", systemImage: "square.and.arrow.down") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(job.approvedCount == 0 || exporting)
            }
        }
        .padding(20)
        .background(Color(white: 0.09))
    }

    @ViewBuilder
    private func failureSummary(_ job: Job) -> some View {
        let kinds: [AIErrorKind] = job.items.flatMap { item -> [AIErrorKind] in
            if item.cleanStatus == .failed { return [item.cleanErrorKind ?? .other] }
            return item.variations.filter { $0.status == .failed }.map { $0.errorKind ?? .other }
        }
        let temporary = kinds.filter { $0.isTemporary }.count
        let definitive = kinds.count - temporary
        let waiting = job.items.reduce(0) { acc, item in
            acc + (item.cleanRetryNote != nil ? 1 : 0) + item.variations.filter { $0.retryNote != nil }.count
        }
        if temporary + definitive + waiting > 0 {
            HStack(spacing: 14) {
                if waiting > 0 {
                    Label("\(waiting) aguardando nova tentativa", systemImage: "hourglass").foregroundStyle(Brand.warning)
                }
                if temporary > 0 {
                    Label("\(temporary) falha(s) temporária(s) — IA ocupada ou sem conexão", systemImage: "clock.badge.exclamationmark")
                        .foregroundStyle(Brand.warning)
                }
                if definitive > 0 {
                    Label("\(definitive) falha(s) definitiva(s)", systemImage: "xmark.octagon.fill").foregroundStyle(Brand.red)
                }
                Button("Ver no histórico") {
                    model.logJobFilter = jobID
                    model.selection = .logs
                }
                .buttonStyle(.link)
            }
            .font(.caption)
        }
    }

    private func bulkApprove(onlyClean: Bool) {
        var count = 0
        defer {
            if count > 0, let job = jobs.job(jobID) {
                AppLog.info(.revisao, "\(count) imagem(ns) aprovada(s) em massa" + (onlyClean ? " (só as sem alerta)." : "."),
                            jobID: jobID, jobName: job.name)
            }
        }
        jobs.update(jobID) { job in
            for i in job.items.indices {
                if job.items[i].cleanStatus == .done, job.items[i].cleanReview == .pending,
                   !(onlyClean && job.items[i].cleanWarning != nil) {
                    job.items[i].cleanReview = .approved
                    count += 1
                }
                for v in job.items[i].variations.indices {
                    let variation = job.items[i].variations[v]
                    if variation.status == .done, variation.review == .pending,
                       !(onlyClean && variation.textWarning != nil) {
                        job.items[i].variations[v].review = .approved
                        count += 1
                    }
                }
            }
        }
    }

    private func export(_ job: Job) async {
        let base = URL(fileURLWithPath: settings.defaultOutputFolder)
        guard let dest = Pickers.folder(title: "Onde salvar os aprovados?", start: Paths.ensure(base).path) else { return }
        exporting = true
        defer { exporting = false }
        do {
            let result = try await Exporter.export(job: job, jobFolder: jobs.folder(for: jobID), to: dest)
            jobs.update(jobID) {
                $0.exportedTo = result.folder.path
                if $0.state == .review { $0.state = .exported }
            }
            exportedFolder = result.folder
            exportMessage = "\(result.count) imagens salvas em \(result.folder.path)."
                + (result.failures.isEmpty ? "" : "\nFalharam: \(result.failures.joined(separator: ", "))")
            if result.failures.isEmpty {
                AppLog.success(.exportacao, "\(result.count) imagens exportadas.", details: result.folder.path, jobID: jobID, jobName: job.name)
            } else {
                AppLog.warning(.exportacao, "\(result.count) imagens exportadas, \(result.failures.count) falharam.",
                               details: "Pasta: \(result.folder.path)\nFalharam: \(result.failures.joined(separator: ", "))",
                               jobID: jobID, jobName: job.name)
            }
        } catch {
            exportedFolder = nil
            exportMessage = "Erro ao exportar: \(error.localizedDescription)"
            AppLog.error(.exportacao, "Erro ao exportar: \(error.localizedDescription)", details: dest.path, jobID: jobID, jobName: job.name)
        }
    }
}

// MARK: - Cartão de um criativo

struct ItemCard: View {
    let job: Job
    let item: JobItem
    @Binding var preview: PreviewItem?
    @EnvironmentObject var jobs: JobStore
    @EnvironmentObject var runner: JobRunner

    private let tileWidth: CGFloat = 190

    private func url(_ rel: String?) -> URL? { jobs.fileURL(job: job.id, rel) }

    var body: some View {
        Card(padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(item.sourceName).font(.headline).lineLimit(1)
                    Text("\(item.pixelWidth)×\(item.pixelHeight)").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if let plan = item.plan {
                        Image(systemName: "list.bullet.clipboard").foregroundStyle(.secondary)
                            .help(CreativePlanner.summary(plan))
                    }
                    if let t = item.transcript, !t.isEmpty {
                        Image(systemName: "text.quote").foregroundStyle(.secondary)
                            .help(item.seenText.map { "Texto esperado nas variações:\n\(t)\n\nTexto visto no limpo:\n\($0)" }
                                  ?? "Texto detectado:\n\(t)")
                    }
                }
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(alignment: .top, spacing: 12) {
                        // ORIGINAL
                        Tile(title: "Original", width: tileWidth, imageURL: url(item.originalFile)) {
                            preview = PreviewItem(title: "\(item.sourceName) — original", url: url(item.originalFile)!, compare: nil)
                        } footer: { EmptyView() }

                        // LIMPO (v0)
                        Tile(title: "Limpo · v0", width: tileWidth, imageURL: item.cleanStatus == .done ? url(item.cleanedFile) : nil,
                             status: item.cleanStatus, review: item.cleanReview,
                             note: item.cleanRetryNote, noteUntil: item.cleanRetryAt) {
                            if let u = url(item.cleanedFile) {
                                preview = PreviewItem(title: "\(item.sourceName) — limpo", url: u, compare: url(item.originalFile))
                            }
                        } footer: {
                            if item.cleanStatus == .failed, let e = item.cleanError {
                                FailureLabel(message: e, kind: item.cleanErrorKind)
                                    .contextMenu { copyMenu(step: "Limpeza", message: e, kind: item.cleanErrorKind, details: item.cleanErrorDetails) }
                                AltProviderButton(current: item.cleanProviderUsed ?? item.cleanProviderOverride ?? job.cleanProvider) { kind in
                                    runner.redoClean(job.id, item.id, note: nil, using: kind)
                                }
                            }
                            if item.cleanStatus == .done, let used = item.cleanProviderUsed, used != job.cleanProvider {
                                ProviderUsedLabel(provider: used)
                            }
                            if item.cleanStatus == .done, item.cleanSkipped == true {
                                Label("Nada a remover · usando o original", systemImage: "checkmark.seal")
                                    .font(.caption).foregroundStyle(.secondary)
                                    .help("O plano não encontrou nada para apagar nesta imagem e a checagem confirmou. Use \"Refazer\" para limpar mesmo assim.")
                            }
                            if let w = item.cleanWarning { WarningLabel(text: w) }
                            if item.cleanStatus == .done || item.cleanStatus == .failed {
                                ReviewBar(review: item.cleanReview, canApprove: item.cleanStatus == .done,
                                          approve: { setClean(.approved) },
                                          discard: { setClean(.discarded) },
                                          redo: { note in runner.redoClean(job.id, item.id, note: note) })
                            }
                        }

                        Divider().frame(height: tileWidth)

                        // VARIAÇÕES
                        if item.cleanStatus == .failed {
                            Text("Sem variações: a limpeza falhou.").font(.caption).foregroundStyle(.secondary)
                                .frame(width: tileWidth, height: tileWidth)
                        } else {
                            ForEach(item.variations) { v in
                                Tile(title: "v\(v.index) · \(v.axisLabel)", width: tileWidth,
                                     imageURL: v.status == .done ? url(v.file) : nil,
                                     status: v.status, review: v.review,
                                     note: v.retryNote, noteUntil: v.retryAt) {
                                    if let u = url(v.file) {
                                        preview = PreviewItem(title: "\(item.sourceName) — v\(v.index) (\(v.axisLabel))",
                                                              url: u, compare: url(item.cleanedFile))
                                    }
                                } footer: {
                                    if v.status == .failed, let e = v.error {
                                        FailureLabel(message: e, kind: v.errorKind)
                                            .contextMenu { copyMenu(step: "Variação v\(v.index) (\(v.axisName))", message: e, kind: v.errorKind, details: v.errorDetails) }
                                        AltProviderButton(current: v.providerUsed ?? v.providerOverride ?? job.variationProvider) { kind in
                                            runner.redoVariation(job.id, item.id, v.id, note: nil, using: kind)
                                        }
                                    }
                                    if v.status == .done, let used = v.providerUsed, used != job.variationProvider {
                                        ProviderUsedLabel(provider: used)
                                    }
                                    if let w = v.textWarning { WarningLabel(text: w) }
                                    if v.status == .done || v.status == .failed {
                                        ReviewBar(review: v.review, canApprove: v.status == .done,
                                                  approve: { setVariation(v.id, .approved) },
                                                  discard: { setVariation(v.id, .discarded) },
                                                  redo: { note in runner.redoVariation(job.id, item.id, v.id, note: note) })
                                    }
                                }
                            }
                        }
                    }
                    .padding(.bottom, 6)
                }
            }
        }
    }

    private func setClean(_ r: ReviewStatus) {
        let new: ReviewStatus = item.cleanReview == r ? .pending : r
        jobs.updateItem(job.id, item.id) { $0.cleanReview = new }
        AppLog.info(.revisao, "Limpeza (v0): \(Self.reviewText(new)).", jobID: job.id, jobName: job.name, item: item.sourceName)
    }

    private func setVariation(_ id: UUID, _ r: ReviewStatus) {
        guard let v = item.variations.first(where: { $0.id == id }) else { return }
        let new: ReviewStatus = v.review == r ? .pending : r
        jobs.updateVariation(job.id, item.id, id) { $0.review = new }
        AppLog.info(.revisao, "Variação v\(v.index): \(Self.reviewText(new)).", jobID: job.id, jobName: job.name, item: item.sourceName)
    }

    static func reviewText(_ r: ReviewStatus) -> String {
        switch r {
        case .approved: return "aprovada"
        case .discarded: return "descartada"
        case .pending: return "voltou para pendente"
        }
    }

    @ViewBuilder
    private func copyMenu(step: String, message: String, kind: AIErrorKind?, details: String?) -> some View {
        let k = kind ?? .other
        Button("Copiar erro (para colar no Claude)") {
            var text = """
            IMP Criativos \(AppInfo.version) — erro no lote "\(job.name)"
            Criativo: \(item.sourceName) · Etapa: \(step)
            Tipo: \(k.title)
            Mensagem: \(message)
            """
            if let details, !details.isEmpty { text += "\nDetalhes técnicos:\n\(details)" }
            Clipboard.copy(text)
        }
        Button("Copiar só a mensagem") { Clipboard.copy(message) }
    }
}

struct Tile<Footer: View>: View {
    let title: String
    let width: CGFloat
    let imageURL: URL?
    var status: StepStatus = .done
    var review: ReviewStatus = .pending
    var note: String?
    var noteUntil: Date?
    var onOpen: () -> Void
    @ViewBuilder var footer: Footer

    init(title: String, width: CGFloat, imageURL: URL?, status: StepStatus = .done, review: ReviewStatus = .pending,
         note: String? = nil, noteUntil: Date? = nil,
         onOpen: @escaping () -> Void, @ViewBuilder footer: () -> Footer) {
        self.title = title
        self.width = width
        self.imageURL = imageURL
        self.status = status
        self.review = review
        self.note = note
        self.noteUntil = noteUntil
        self.onOpen = onOpen
        self.footer = footer()
    }

    private var borderColor: Color {
        switch review {
        case .approved: return Brand.success
        case .discarded: return Color.gray.opacity(0.4)
        case .pending: return Brand.stroke
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.medium)).lineLimit(1).foregroundStyle(.secondary)
            ZStack {
                if status == .done {
                    Thumb(url: imageURL).onTapGesture(perform: onOpen)
                        .opacity(review == .discarded ? 0.35 : 1)
                } else {
                    Rectangle().fill(Color.black.opacity(0.35))
                    switch status {
                    case .pending: Label("Na fila", systemImage: "clock").font(.caption).foregroundStyle(.secondary)
                    case .running:
                        if let note {
                            RetryNoteView(note: note, until: noteUntil)
                        } else {
                            VStack(spacing: 6) { ProgressView(); Text("Gerando…").font(.caption) }
                        }
                    case .failed: Image(systemName: "xmark.octagon").font(.title).foregroundStyle(Brand.red)
                    case .done: EmptyView()
                    }
                }
            }
            .frame(width: width, height: width)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(borderColor, lineWidth: review == .approved ? 2.5 : 1))
            footer
        }
        .frame(width: width, alignment: .leading)
    }
}

struct ReviewBar: View {
    let review: ReviewStatus
    let canApprove: Bool
    let approve: () -> Void
    let discard: () -> Void
    let redo: (String?) -> Void

    @State private var showRedo = false
    @State private var note = ""

    var body: some View {
        HStack(spacing: 6) {
            Button(action: approve) {
                Image(systemName: review == .approved ? "checkmark.circle.fill" : "checkmark.circle")
            }
            .foregroundStyle(review == .approved ? Brand.success : .primary)
            .disabled(!canApprove)
            .help("Aprovar")

            Button { showRedo = true } label: { Image(systemName: "arrow.clockwise.circle") }
                .help("Refazer (com observação opcional)")
                .popover(isPresented: $showRedo, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Refazer").font(.headline)
                        Text("O que corrigir? (opcional)").font(.caption).foregroundStyle(.secondary)
                        TextField("Ex.: sobrou o @ no canto inferior", text: $note, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(2...4)
                            .frame(width: 280)
                        HStack {
                            Spacer()
                            Button("Cancelar") { showRedo = false }
                            Button("Refazer") {
                                let n = note.trimmingCharacters(in: .whitespacesAndNewlines)
                                redo(n.isEmpty ? nil : n)
                                note = ""
                                showRedo = false
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(14)
                }

            Button(action: discard) {
                Image(systemName: review == .discarded ? "xmark.circle.fill" : "xmark.circle")
            }
            .foregroundStyle(review == .discarded ? Brand.red : .primary)
            .help("Descartar")
        }
        .buttonStyle(.borderless)
        .font(.title3)
    }
}

struct PreviewSheet: View {
    let item: PreviewItem
    @Environment(\.dismiss) private var dismiss
    @State private var showCompare = false

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(item.title).font(.headline)
                Spacer()
                if item.compare != nil {
                    Toggle("Comparar com a referência", isOn: $showCompare).toggleStyle(.switch)
                }
                Button("Mostrar no Finder") { AppInfo.reveal(item.url) }
                Button("Fechar") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack(spacing: 12) {
                if showCompare, let c = item.compare {
                    VStack { Text("Referência").font(.caption).foregroundStyle(.secondary); Thumb(url: c, maxPixel: 1600) }
                }
                VStack { if showCompare { Text("Resultado").font(.caption).foregroundStyle(.secondary) }; Thumb(url: item.url, maxPixel: 1600) }
            }
        }
        .padding(18)
        .frame(minWidth: 760, idealWidth: 1100, minHeight: 620, idealHeight: 820)
    }
}

/// "Refazer com GPT/Gemini" embaixo de uma etapa que falhou (só aparece se a outra IA tiver chave).
struct AltProviderButton: View {
    let current: ProviderKind
    let redo: (ProviderKind) -> Void

    private var alt: ProviderKind { current == .gemini ? .openai : .gemini }

    var body: some View {
        if APIKeyStore.hasKey(alt) {
            Button { redo(alt) } label: {
                Label("Refazer com \(alt.label)", systemImage: "arrow.triangle.swap").font(.caption)
            }
            .buttonStyle(.link)
        }
    }
}

struct ProviderUsedLabel: View {
    let provider: ProviderKind
    var body: some View {
        Label("feito com \(provider.label)", systemImage: "arrow.triangle.swap")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .help("A IA do lote falhou e esta imagem foi gerada pela outra (troca automática ou refazer com outra IA).")
    }
}
