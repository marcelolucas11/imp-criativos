import SwiftUI

struct NewJobView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var clients: ClientStore
    @EnvironmentObject var jobs: JobStore
    @EnvironmentObject var runner: JobRunner

    enum SizeChoice: String, CaseIterable, Identifiable {
        case original, square, feed, story, custom
        var id: String { rawValue }
        var label: String {
            switch self {
            case .original: return "Manter original (mesmo tamanho de cada criativo)"
            case .square: return "Forçar 1080×1080 (quadrado)"
            case .feed: return "Forçar 1080×1350 (feed 4:5)"
            case .story: return "Forçar 1080×1920 (stories 9:16)"
            case .custom: return "Forçar tamanho personalizado"
            }
        }
    }

    @State private var name = ""
    @State private var clientID: UUID?
    @State private var folder: URL?
    @State private var files: [URL] = []
    @State private var variations = 4
    @State private var cleanProvider: ProviderKind = .gemini
    @State private var variationProvider: ProviderKind = .gemini
    @State private var analysisProvider: ProviderKind = .gemini
    @State private var sizeChoice: SizeChoice = .original
    @State private var customW = 1080
    @State private var customH = 1080
    @State private var format: OutputFormat = .jpg
    @State private var verifyText = true
    @State private var error: String?
    @State private var didLoadDefaults = false

    private var client: ClientProfile? { clients.client(clientID) }

    private var sizeMode: OutputSizeMode {
        switch sizeChoice {
        case .original: return .original
        case .square: return .fixed(width: 1080, height: 1080)
        case .feed: return .fixed(width: 1080, height: 1350)
        case .story: return .fixed(width: 1080, height: 1920)
        case .custom: return .fixed(width: max(64, customW), height: max(64, customH))
        }
    }

    private var missingKey: ProviderKind? {
        [cleanProvider, variationProvider, analysisProvider].first { !KeychainStore.hasKey($0) }
    }

    private var estimate: CostEstimator.Estimate {
        CostEstimator.estimate(items: files.count, variations: variations, clean: cleanProvider,
                               variation: variationProvider, verifyText: verifyText, settings: settings)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "Novo lote", subtitle: "Escolha o cliente, a pasta dos criativos e como processar.")

                Form {
                    Section("Lote") {
                        TextField("Nome do lote", text: $name, prompt: Text("Ex.: Hilux novembro"))
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

                    Section("Processamento") {
                        Stepper(value: $variations, in: 1...10) {
                            Text("Variações por criativo: **\(variations)**")
                        }
                        Picker("IA da limpeza", selection: $cleanProvider) {
                            ForEach(ProviderKind.allCases) { Text($0.label).tag($0) }
                        }
                        Picker("IA das variações", selection: $variationProvider) {
                            ForEach(ProviderKind.allCases) { Text($0.label).tag($0) }
                        }
                        Picker("IA das checagens", selection: $analysisProvider) {
                            ForEach(ProviderKind.allCases) { Text($0.label).tag($0) }
                        }
                        Toggle("Conferir o texto de cada variação", isOn: $verifyText)
                    }

                    Section("Saída") {
                        Picker("Tamanho", selection: $sizeChoice) {
                            ForEach(SizeChoice.allCases) { Text($0.label).tag($0) }
                        }
                        if sizeChoice == .custom {
                            HStack {
                                TextField("Largura", value: $customW, format: .number).frame(width: 90)
                                Text("×")
                                TextField("Altura", value: $customH, format: .number).frame(width: 90)
                                Text("px").foregroundStyle(.secondary)
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
                            Text("\(estimate.imageCalls) imagens geradas · \(estimate.analysisCalls) checagens")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let k = missingKey {
                            VStack(alignment: .trailing) {
                                WarningLabel(text: "Falta a chave do \(k.label)")
                                Button("Configurar chave") { model.selection = .settings }
                            }
                        }
                        Button {
                            startJob()
                        } label: {
                            Label("Iniciar lote", systemImage: "play.fill").padding(.horizontal, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(client == nil || files.isEmpty || missingKey != nil)
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
        .onChange(of: clientID) { _, _ in
            if let c = client { variations = max(1, c.defaultVariations) }
        }
    }

    private func loadDefaults() {
        guard !didLoadDefaults else { return }
        didLoadDefaults = true
        cleanProvider = settings.defaultCleanProvider
        variationProvider = settings.defaultVariationProvider
        analysisProvider = settings.defaultAnalysisProvider
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
            ? "\(client.name) \(Date().short)" : name
        do {
            let job = try jobs.createJob(name: jobName, client: client, inputFolder: folder, files: files,
                                         variations: variations, cleanProvider: cleanProvider,
                                         variationProvider: variationProvider, analysisProvider: analysisProvider,
                                         sizeMode: sizeMode, format: format, verifyText: verifyText)
            settings.defaultCleanProvider = cleanProvider
            settings.defaultVariationProvider = variationProvider
            settings.defaultAnalysisProvider = analysisProvider
            runner.start(job.id)
            model.selection = .job(job.id)
            // limpa o formulário para o próximo lote
            self.folder = nil
            files = []
            name = ""
        } catch {
            self.error = "Não foi possível criar o lote: \(error.localizedDescription)"
        }
    }
}
