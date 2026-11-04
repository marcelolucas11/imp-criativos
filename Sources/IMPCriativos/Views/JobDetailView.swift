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
                    Text("\(job.client.name) · \(job.items.count) criativos · \(job.variationsPerItem) variações · limpeza: \(job.cleanProvider.label) · variações: \(job.variationProvider.label) · saída: \(job.sizeMode.label) \(job.format.label)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(job.costUSD.usd).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    .help("Gasto estimado deste lote")
            }

            HStack(spacing: 10) {
                ProgressView(value: job.progress)
                Text("\(job.finishedSteps)/\(job.totalSteps)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }

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
                if job.items.contains(where: { $0.hasFailure }) && job.state != .running {
                    Button { runner.retryFailed(jobID) } label: { Label("Tentar falhas de novo", systemImage: "arrow.clockwise") }
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
                    Divider()
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

    private func bulkApprove(onlyClean: Bool) {
        jobs.update(jobID) { job in
            for i in job.items.indices {
                if job.items[i].cleanStatus == .done, job.items[i].cleanReview == .pending,
                   !(onlyClean && job.items[i].cleanWarning != nil) {
                    job.items[i].cleanReview = .approved
                }
                for v in job.items[i].variations.indices {
                    let variation = job.items[i].variations[v]
                    if variation.status == .done, variation.review == .pending,
                       !(onlyClean && variation.textWarning != nil) {
                        job.items[i].variations[v].review = .approved
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
        } catch {
            exportedFolder = nil
            exportMessage = "Erro ao exportar: \(error.localizedDescription)"
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
                    if let t = item.transcript, !t.isEmpty {
                        Image(systemName: "text.quote").foregroundStyle(.secondary).help("Texto detectado:\n\(t)")
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
                             status: item.cleanStatus, review: item.cleanReview) {
                            if let u = url(item.cleanedFile) {
                                preview = PreviewItem(title: "\(item.sourceName) — limpo", url: u, compare: url(item.originalFile))
                            }
                        } footer: {
                            if let e = item.cleanError { ErrorLabel(text: e) }
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
                                Tile(title: "v\(v.index) · \(v.axisName)", width: tileWidth,
                                     imageURL: v.status == .done ? url(v.file) : nil,
                                     status: v.status, review: v.review) {
                                    if let u = url(v.file) {
                                        preview = PreviewItem(title: "\(item.sourceName) — v\(v.index) (\(v.axisName))",
                                                              url: u, compare: url(item.cleanedFile))
                                    }
                                } footer: {
                                    if let e = v.error { ErrorLabel(text: e) }
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
        jobs.updateItem(job.id, item.id) { $0.cleanReview = ($0.cleanReview == r ? .pending : r) }
    }

    private func setVariation(_ id: UUID, _ r: ReviewStatus) {
        jobs.updateVariation(job.id, item.id, id) { $0.review = ($0.review == r ? .pending : r) }
    }
}

struct Tile<Footer: View>: View {
    let title: String
    let width: CGFloat
    let imageURL: URL?
    var status: StepStatus = .done
    var review: ReviewStatus = .pending
    var onOpen: () -> Void
    @ViewBuilder var footer: Footer

    init(title: String, width: CGFloat, imageURL: URL?, status: StepStatus = .done, review: ReviewStatus = .pending,
         onOpen: @escaping () -> Void, @ViewBuilder footer: () -> Footer) {
        self.title = title
        self.width = width
        self.imageURL = imageURL
        self.status = status
        self.review = review
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
                    case .running: VStack(spacing: 6) { ProgressView(); Text("Gerando…").font(.caption) }
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
