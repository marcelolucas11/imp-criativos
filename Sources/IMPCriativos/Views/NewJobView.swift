import SwiftUI

/// Novo lote (limpeza + variações) e, desde a 1.0.0-beta.20, o módulo "Limpar logo" (`cleanOnly`):
/// a mesma tela sem as variações, para limpar anúncios pegos na Biblioteca de Anúncios.
struct NewJobView: View {
    /// Módulo "Limpar logo": só limpa o logo e o nome da empresa, sem variações.
    let cleanOnly: Bool

    init(cleanOnly: Bool = false) {
        self.cleanOnly = cleanOnly
    }

    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var clients: ClientStore
    @EnvironmentObject var jobs: JobStore
    @EnvironmentObject var runner: JobRunner

    @State private var name = ""
    @State private var clientID: UUID?
    @State private var folder: URL?
    @State private var files: [URL] = []
    @State private var variations = 4
    /// 1.0.0-beta.19: Normal ou Teste de eixos.
    @State private var mode: BatchMode = .normal
    @State private var confirmBig = false
    /// 1.0.0-beta.20: desliga a limpeza no lote normal (as imagens já vêm limpas).
    @State private var skipClean = false
    /// 1.0.0-beta.20: tamanho no módulo "Limpar logo" (nil = manter o tamanho original).
    @State private var cleanSize: MetaFormat?
    @ObservedObject private var speed = SpeedMonitor.shared

    enum BatchMode: String, CaseIterable, Identifiable {
        case normal = "Normal"
        case axisTest = "Teste de eixos"
        var id: String { rawValue }
    }

    /// Acima disso, o app pede confirmação antes de iniciar.
    static let bigBatch = 60
    // 1.0.0-beta.11: plataforma + modelo de cada etapa (começa com o que está em Configurações → Modelos de IA)
    @State private var cleanAI = AIStage.clean.defaultAI.primary
    @State private var variationAI = AIStage.variation.defaultAI.primary
    @State private var analysisAI = AIStage.analysis.defaultAI.primary
    @State private var metaFormat: MetaFormat = .feed
    @State private var format: OutputFormat = .jpg
    @State private var verifyText = true
    @State private var error: String?
    @State private var didLoadDefaults = false

    // Instruções do lote (1.0.0-beta.6)
    @State private var instructionsText = ""
    @State private var interpretedRaw: String?
    @State private var interpreting = false
    @State private var interpretNote: String?
    @State private var removeText = ""
    @State private var textChangesText = ""
    @State private var directionText = ""

    private var client: ClientProfile? { clients.client(clientID) }

    private var cleanProvider: ProviderKind { cleanAI.provider }
    private var variationProvider: ProviderKind { variationAI.provider }
    private var analysisProvider: ProviderKind { analysisAI.provider }

    /// O lote passa pela limpeza? (Sempre no módulo "Limpar logo"; no lote normal, a menos que seja desligada.)
    private var cleaning: Bool { cleanOnly || !skipClean }

    /// IAs que este lote vai usar (a chave delas é obrigatória).
    private var usedProviders: [ProviderKind] {
        if cleanOnly { return [cleanProvider, analysisProvider] }
        return (cleaning ? [cleanProvider] : []) + [variationProvider, analysisProvider]
    }

    private var missingKey: ProviderKind? {
        usedProviders.first { !APIKeyStore.hasKey($0) }
    }

    private var sizeMode: OutputSizeMode {
        cleanOnly ? (cleanSize?.sizeMode ?? .original) : metaFormat.sizeMode
    }

    private var hasInstructions: Bool { !instructionsText.trimmed.isEmpty }

    /// Há texto nas instruções que ainda não foi interpretado (ou mudou depois).
    private var needsInterpretation: Bool { hasInstructions && interpretedRaw != instructionsText }

    private var savedInstructions: [String] { client?.savedInstructions ?? [] }

    /// Instruções como serão usadas no lote, já com as edições do usuário.
    private var currentInstructions: BatchInstructions? {
        guard hasInstructions, !needsInterpretation else { return nil }
        let remove = removeText.split(whereSeparator: \.isNewline).map { String($0).trimmed }.filter { !$0.isEmpty }
        let ins = BatchInstructions(raw: instructionsText.trimmed, removeItems: remove,
                                    textChanges: textChangesText.trimmed, direction: cleanOnly ? "" : directionText.trimmed)
        return ins.isEmpty ? nil : ins
    }

    /// Eixos que o lote vai usar (a lista do cliente; vazia = os 50 do catálogo).
    private var axesCount: Int {
        guard let c = client else { return 0 }
        return c.axes.isEmpty ? ClientProfile.defaultAxes.count : c.axes.count
    }

    /// Variações por criativo: no teste de eixos, uma por eixo do cliente.
    private var effectiveVariations: Int { cleanOnly ? 0 : (mode == .axisTest ? axesCount : variations) }

    private var totalVariations: Int { files.count * effectiveVariations }

    private var estimate: CostEstimator.Estimate {
        CostEstimator.estimate(items: files.count, variations: effectiveVariations, clean: cleanProvider,
                               variation: variationProvider, verifyText: verifyText && !cleanOnly, settings: settings,
                               cleaning: cleaning)
    }

    private var timeLabel: String {
        CostEstimator.minutesLabel(CostEstimator.minutes(items: files.count, variations: effectiveVariations, settings: settings,
                                                         secondsPerImage: speed.snapshots[cleanOnly ? cleanProvider : variationProvider]?.latency,
                                                         cleaning: cleaning))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if cleanOnly {
                    PageHeader(title: "Limpar logo",
                               subtitle: "Só remove o logo e o nome da empresa dos anúncios (ex.: pegos na Biblioteca de Anúncios). Não cria variações.")
                } else {
                    PageHeader(title: "Novo lote", subtitle: "Escolha o cliente, a pasta dos criativos e como processar.")
                }

                Form {
                    Section("Lote") {
                        TextField("Nome do lote", text: $name, prompt: Text(cleanOnly ? "Ex.: Biblioteca novembro" : "Ex.: Hilux novembro"))
                        HStack {
                            Picker("Cliente", selection: $clientID) {
                                Text("Selecione…").tag(UUID?.none)
                                ForEach(clients.clients) { c in Text(c.name).tag(UUID?.some(c.id)) }
                            }
                            Button("Gerenciar clientes") { model.selection = .clients }
                        }
                        if let c = client {
                            Text("Remove \(c.removeItems.count) itens · \(c.axes.count) eixos de variação")
                                .font(.caption).foregroundStyle(.secondary)
                            if c.hasPlaceholderTerms {
                                HStack {
                                    WarningLabel(text: "Este cliente ainda tem os nomes de exemplo (\"Minha Bet\", @minhabet). Troque pelos nomes reais para a limpeza saber o que remover.")
                                    Button("Editar cliente") { model.selection = .clients }
                                }
                            }
                        }
                    }

                    Section("Criativos") {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(folder?.lastPathComponent ?? "Nenhuma pasta escolhida")
                                if let folder {
                                    Text(folder.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                }
                            }
                            Spacer()
                            Button("Escolher pasta…") { pickFolder() }
                        }
                        if folder != nil {
                            Text(files.isEmpty ? "Nenhuma imagem (JPG, PNG, WEBP, HEIC) encontrada nessa pasta."
                                               : "\(files.count) imagens encontradas")
                                .foregroundStyle(files.isEmpty ? Brand.warning : .secondary)
                                .font(.callout)
                        }
                    }

                    if cleanOnly {
                        Section("Limpeza") {
                            LabeledContent("IA da limpeza") {
                                ModelMenu(role: .image, selection: cleanAI) { if let c = $0 { cleanAI = c } }
                            }
                            LabeledContent("IA das checagens") {
                                ModelMenu(role: .text, selection: analysisAI) { if let c = $0 { analysisAI = c } }
                            }
                            Text("Remove o que está na lista do cliente (logo, nome, @, site…) mais o que você pedir abaixo. Depois, a checagem lê a imagem limpa e, se ainda sobrar marca, refaz a limpeza sozinha uma vez.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        Section("Processamento") {
                            Picker("Modo do lote", selection: $mode) {
                                ForEach(BatchMode.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            if mode == .normal {
                                Stepper(value: $variations, in: 1...10) {
                                    Text("Variações por criativo: **\(variations)**")
                                }
                            } else {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Cada criativo passa por **todos os \(axesCount) eixos** do cliente, na ordem da lista (sem rodízio), com uma limpeza só.")
                                    Text(files.count == 1
                                         ? "1 imagem → \(axesCount) variações. Na revisão e na exportação cada variação leva o número e o nome do eixo, para comparar."
                                         : "\(files.count) imagens → \(totalVariations) variações. Para comparar os eixos, o ideal é usar 1 imagem.")
                                        .font(.caption).foregroundStyle(files.count > 1 ? Brand.warning : .secondary)
                                    Text("Para escolher os eixos testados, marque-os em Clientes → Eixos de variação (Catálogo do app ou Meus eixos).")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Toggle("Limpar logo e nome antes das variações", isOn: Binding(get: { !skipClean }, set: { skipClean = !$0 }))
                                if skipClean {
                                    Text("Limpeza desligada: as imagens da pasta já vêm limpas e vão direto para as variações, sem custo de limpeza. A checagem ainda lê cada imagem; se achar marca, só avisa na revisão (dá para usar Refazer na limpeza daquela imagem).")
                                        .font(.caption).foregroundStyle(Brand.warning)
                                }
                            }
                            if cleaning {
                                LabeledContent("IA da limpeza") {
                                    ModelMenu(role: .image, selection: cleanAI) { if let c = $0 { cleanAI = c } }
                                }
                            }
                            LabeledContent("IA das variações") {
                                ModelMenu(role: .image, selection: variationAI) { if let c = $0 { variationAI = c } }
                            }
                            LabeledContent("IA das checagens") {
                                ModelMenu(role: .text, selection: analysisAI) { if let c = $0 { analysisAI = c } }
                            }
                            Toggle("Conferir o texto de cada variação", isOn: $verifyText)
                        }
                    }

                    instructionsSection

                    Section("Saída") {
                        if cleanOnly {
                            Picker("Tamanho", selection: $cleanSize) {
                                Text("Manter o tamanho original").tag(MetaFormat?.none)
                                ForEach(MetaFormat.allCases) { Text($0.label).tag(MetaFormat?.some($0)) }
                            }
                        } else {
                            Picker("Tamanho", selection: $metaFormat) {
                                ForEach(MetaFormat.allCases) { Text($0.label).tag($0) }
                            }
                        }
                        Picker("Formato", selection: $format) {
                            ForEach(OutputFormat.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                .formStyle(.grouped)
                .scrollDisabled(true)

                Card {
                    HStack(alignment: .center, spacing: 20) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Estimativa").font(.caption).foregroundStyle(.secondary)
                            Text(estimate.usd.usd).font(.system(size: 26, weight: .semibold, design: .rounded))
                            Text("\(estimate.imageCalls) imagens geradas · \(estimate.analysisCalls) checagens" + (settings.planningEnabled ? " · \(files.count) planejamentos" : ""))
                                .font(.caption).foregroundStyle(.secondary)
                            if !files.isEmpty {
                                Text("Tempo: \(timeLabel)" + (settings.fastMode ? " · modo rápido com segurança" : " · velocidade original"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if let k = missingKey {
                            VStack(alignment: .trailing) {
                                WarningLabel(text: "Falta a chave do \(k.label)")
                                Button("Configurar chave") { model.selection = .settings }
                            }
                        }
                        Button {
                            if needsInterpretation { interpret() }
                            else if totalVariations > Self.bigBatch { confirmBig = true }
                            else { startJob() }
                        } label: {
                            Label(needsInterpretation ? "Interpretar instruções" : (cleanOnly ? "Iniciar limpeza" : "Iniciar lote"),
                                  systemImage: needsInterpretation ? "text.magnifyingglass" : "play.fill")
                                .padding(.horizontal, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(client == nil || files.isEmpty || missingKey != nil || interpreting)
                    }
                }
                Text("Valores estimados com a tabela de preços das Configurações. O custo real é cobrado pelo Google/OpenAI na sua conta.")
                    .font(.caption).foregroundStyle(.secondary)

                if let error { ErrorLabel(text: error) }
            }
            .padding(28)
            .frame(maxWidth: 860, alignment: .leading)
        }
        .onAppear(perform: loadDefaults)
        .confirmationDialog("Lote grande: \(totalVariations) variações", isPresented: $confirmBig) {
            Button("Iniciar (\(estimate.usd.usd), \(timeLabel))") { startJob() }
        } message: {
            Text("\(files.count) criativo(s) × \(effectiveVariations) variações. Custo estimado \(estimate.usd.usd) e tempo \(timeLabel). Dá para pausar a qualquer momento sem perder o que já foi feito.")
        }
        .onChange(of: clientID) { _, _ in
            if let c = client { variations = max(1, c.defaultVariations) }
        }
    }

    private func loadDefaults() {
        guard !didLoadDefaults else { return }
        didLoadDefaults = true
        cleanAI = settings.stage(.clean).primary
        variationAI = settings.stage(.variation).primary
        analysisAI = settings.stage(.analysis).primary
        metaFormat = settings.defaultFormat
        if clientID == nil { clientID = clients.clients.first?.id }
        if let c = client { variations = max(1, c.defaultVariations) }
    }

    private func pickFolder() {
        guard let url = Pickers.folder(title: "Pasta com os criativos") else { return }
        folder = url
        files = Paths.listImages(in: url)
        if name.isEmpty { name = url.lastPathComponent }
    }

    private func startJob() {
        guard let client, let folder else { return }
        error = nil
        let jobName = name.trimmingCharacters(in: .whitespaces).isEmpty
            ? "\(client.name)\(cleanOnly ? " limpeza" : (mode == .axisTest ? " teste de eixos" : "")) \(Date().short)" : name
        let axisTest = !cleanOnly && mode == .axisTest
        do {
            let job = try jobs.createJob(name: jobName, client: client, inputFolder: folder, files: files,
                                         variations: variations, cleanProvider: cleanProvider,
                                         variationProvider: variationProvider, analysisProvider: analysisProvider,
                                         sizeMode: sizeMode, format: format, verifyText: verifyText && !cleanOnly,
                                         instructions: currentInstructions, axisTest: axisTest,
                                         cleanOnly: cleanOnly, skipCleaning: !cleanOnly && skipClean)
            AppLog.info(.lote, "Lote criado: \(files.count) criativos de \(folder.lastPathComponent).",
                        details: "Cliente: \(client.name) · \(cleanOnly ? "só limpeza (módulo Limpar logo)" : (axisTest ? "teste de eixos: \(job.variationsPerItem) eixos por criativo" : "\(variations) variações")) · \(cleaning ? "limpeza ligada" : "limpeza desligada (imagens já limpas)") · \(sizeMode.label) \(format.label)" + (cleanOnly ? "" : " · checagem de texto: \(verifyText ? "sim" : "não")")
                            + (job.instructions.map { "\nInstruções: \($0.raw)\n\($0.summary)" } ?? ""),
                        jobID: job.id, jobName: job.name)
            // a escolha do lote vira a principal de cada etapa (a reserva continua a de Configurações)
            if cleaning { settings.adoptForBatch(cleanAI, for: .clean) }
            if !cleanOnly {
                settings.adoptForBatch(variationAI, for: .variation)
                settings.defaultFormat = metaFormat
            }
            settings.adoptForBatch(analysisAI, for: .analysis)
            runner.start(job.id)
            model.selection = .job(job.id)
            // limpa o formulário para o próximo lote
            self.folder = nil
            files = []
            name = ""
            clearInstructions()
        } catch {
            self.error = "Não foi possível criar o lote: \(error.localizedDescription)"
            AppLog.error(.lote, "Não foi possível criar o lote: \(error.localizedDescription)", details: folder.path)
        }
    }

    // MARK: Instruções do lote

    @ViewBuilder
    private var instructionsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $instructionsText)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .frame(minHeight: 70, maxHeight: 140)
                    if instructionsText.isEmpty {
                        Text(cleanOnly ? "Ex.: tirar também o nome Aviator e o selo do canto"
                                       : "Ex.: tirar todo nome Aviator, tirar o nome X, adicionar o nome Y no topo, criar ângulos bem diferentes e variados")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 11).padding(.vertical, 6)
                            .allowsHitTesting(false)
                    }
                }
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.3)))

                HStack(spacing: 8) {
                    Button {
                        interpret()
                    } label: {
                        Label("Interpretar", systemImage: "text.magnifyingglass")
                    }
                    .disabled(!hasInstructions || interpreting)
                    if interpreting {
                        ProgressView().controlSize(.small)
                        Text("Lendo as instruções…").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu("Instruções salvas") {
                        ForEach(savedInstructions, id: \.self) { t in
                            Button(Self.menuTitle(t)) { instructionsText = t }
                        }
                        if !savedInstructions.isEmpty {
                            Divider()
                            Menu("Apagar") {
                                ForEach(savedInstructions, id: \.self) { t in
                                    Button(Self.menuTitle(t), role: .destructive) { deleteSaved(t) }
                                }
                            }
                        }
                    }
                    .fixedSize()
                    .disabled(savedInstructions.isEmpty)
                    Button("Salvar no cliente") { saveToClient() }
                        .disabled(client == nil || !hasInstructions || savedInstructions.contains(instructionsText.trimmed))
                        .help("Guarda este texto no perfil do cliente para usar em outros lotes")
                }

                if hasInstructions && !needsInterpretation {
                    Divider().padding(.vertical, 2)
                    Text("Confira como o app entendeu. Você pode editar antes de iniciar.")
                        .font(.caption).foregroundStyle(.secondary)
                    instructionField("Remover também (limpeza e checagens)", text: $removeText,
                                     prompt: "Um item por linha. Ex.: Nome Aviator (em qualquer lugar)", lines: 1...5)
                    instructionField("Alterar o texto dos criativos", text: $textChangesText,
                                     prompt: "Ex.: incluir o nome \"Nome Novo\" no topo", lines: 1...3)
                    if !cleanOnly {
                        instructionField("Direção das variações", text: $directionText,
                                         prompt: "Ex.: ângulos bem diferentes e variados", lines: 1...3)
                    }
                    if let interpretNote { WarningLabel(text: interpretNote) }
                } else if needsInterpretation && interpretedRaw != nil {
                    WarningLabel(text: "O texto mudou. Clique em Interpretar de novo.")
                }
            }
            .padding(.vertical, 2)
        } header: {
            Text("Instruções para este lote (opcional)")
        } footer: {
            Text(cleanOnly
                 ? "Valem só para esta limpeza, somadas à lista do cliente. O que for para remover entra na limpeza e na checagem."
                 : "Valem só para este lote, somadas ao perfil do cliente. O que for para remover entra na limpeza e nas checagens; alterações de texto viram o texto esperado das variações; o resto orienta as variações.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func instructionField(_ title: String, text: Binding<String>, prompt: String, lines: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold))
            TextField(text: text, prompt: Text(prompt), axis: .vertical) { EmptyView() }
                .labelsHidden()
                .lineLimit(lines)
                .textFieldStyle(.roundedBorder)
        }
    }

    private static func menuTitle(_ t: String) -> String {
        let one = t.replacingOccurrences(of: "\n", with: " ")
        return one.count > 70 ? String(one.prefix(70)) + "…" : one
    }

    private func apply(_ ins: BatchInstructions) {
        removeText = ins.removeItems.joined(separator: "\n")
        textChangesText = ins.textChanges
        directionText = ins.direction
    }

    private func interpret() {
        let raw = instructionsText
        guard !raw.trimmed.isEmpty, !interpreting else { return }
        interpreting = true
        interpretNote = nil
        Task { @MainActor in
            defer { interpreting = false }
            do {
                let (ins, used) = try await InstructionInterpreter.interpret(raw.trimmed, preferred: analysisProvider, settings: settings)
                guard instructionsText == raw else { return } // mudou enquanto interpretava
                apply(ins)
                if ins.isEmpty { interpretNote = "Nada aproveitável nessas instruções. Preencha os campos à mão se quiser." }
                interpretedRaw = raw
                AppLog.info(.lote, "Instruções do lote interpretadas com \(used.label).", details: "\(raw.trimmed)\n\n\(ins.summary)")
            } catch {
                guard instructionsText == raw else { return }
                apply(BatchInstructions(raw: raw.trimmed, direction: raw.trimmed))
                interpretNote = "Não consegui interpretar (\(error.localizedDescription)). Coloquei tudo em Direção das variações; ajuste os campos se precisar."
                interpretedRaw = raw
                AppLog.warning(.lote, "Não foi possível interpretar as instruções do lote.",
                               details: [raw.trimmed, error.localizedDescription, error.aiDetails].compactMap { $0 }.joined(separator: "\n\n"))
            }
        }
    }

    private func clearInstructions() {
        instructionsText = ""
        interpretedRaw = nil
        interpretNote = nil
        removeText = ""
        textChangesText = ""
        directionText = ""
    }

    private func saveToClient() {
        guard var c = client else { return }
        let t = instructionsText.trimmed
        var list = c.savedInstructions ?? []
        list.removeAll { $0 == t }
        list.insert(t, at: 0)
        c.savedInstructions = Array(list.prefix(20))
        clients.save(c)
        AppLog.info(.clientes, "Instrução de lote salva no cliente \(c.name).", details: t)
    }

    private func deleteSaved(_ t: String) {
        guard var c = client else { return }
        c.savedInstructions = (c.savedInstructions ?? []).filter { $0 != t }
        clients.save(c)
    }
}
