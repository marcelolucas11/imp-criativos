import Foundation
import AppKit
import CoreGraphics

/// 1.0.0-beta.21: estado do Otimizador em Lote (Stories 9:16) — lista de imagens, opções, fila e preview.
///
/// Fica num objeto único do app (não na tela), então o lote continua rodando se você trocar de aba.
/// Não entra no Histórico de lotes: não usa IA, não tem revisão e não gera custo. Só um resumo vai para o Histórico.
@MainActor
final class StoryBatch: ObservableObject {
    static let shared = StoryBatch()

    static let maxItems = 100
    /// Imagens processadas ao mesmo tempo (não trava a tela nem estoura a memória).
    static let concurrency = 4
    static let accepted: Set<String> = ["jpg", "jpeg", "png", "webp", "heic", "heif"]

    private static let optionsKey = "storyOptimizer.options"
    private static let folderKey = "storyOptimizer.outputFolder"

    enum Status: Equatable {
        case pending
        case processing
        case done
        case failed(String)
        case cancelled

        var label: String {
            switch self {
            case .pending: return "Aguardando"
            case .processing: return "Processando"
            case .done: return "Pronto"
            case let .failed(msg): return "Erro: \(msg)"
            case .cancelled: return "Cancelado"
            }
        }

        var isFinished: Bool {
            switch self {
            case .done, .failed: return true
            default: return false
            }
        }
    }

    struct Item: Identifiable, Equatable {
        let id = UUID()
        let url: URL
        var seed: UInt64
        var status: Status = .pending
        var output: URL?
        var bytes: Int?
        var summary: String?
        /// 1.0.0-beta.22: versões desta imagem já gravadas (com várias versões por imagem).
        var doneVersions = 0
    }

    @Published private(set) var items: [Item] = []
    @Published var selectedID: UUID? = nil { didSet { if selectedID != oldValue { refreshPreview() } } }
    @Published var options: StoryOptions {
        didSet {
            guard options != oldValue else { return }
            if previewVersion > options.versions { previewVersion = options.versions }
            save()
            refreshPreview()
        }
    }
    @Published var outputFolder: URL? = nil {
        didSet { UserDefaults.standard.set(outputFolder?.path, forKey: Self.folderKey) }
    }
    @Published private(set) var running = false
    @Published private(set) var cancelling = false
    @Published private(set) var lastRunFolder: URL? = nil
    @Published private(set) var zipping = false
    /// 1.0.0-beta.22: arquivos do lote (imagens × versões) e quantos já terminaram (prontos ou com erro).
    @Published private(set) var totalOutputs = 0
    @Published private(set) var processedOutputs = 0
    @Published private(set) var writtenOutputs = 0
    /// Versão mostrada no preview (1…versões por imagem).
    @Published var previewVersion = 1 { didSet { if previewVersion != oldValue { refreshPreview() } } }
    @Published var notice: String? = nil

    // preview
    @Published private(set) var previewBefore: CGImage? = nil
    @Published private(set) var previewAfter: CGImage? = nil
    @Published private(set) var previewSummary = ""
    @Published private(set) var previewLoading = false
    /// 1.0.0-beta.23: modal de inspeção Antes / Depois. Enquanto aberto, o preview também desenha duas imagens de referência
    /// em 1080×1920 (as mesmas do arquivo final): o original só enquadrado e a versão com tudo menos as texturas.
    @Published var inspecting = false {
        didSet {
            guard inspecting != oldValue else { return }
            if inspecting {
                refreshPreview()
            } else {
                inspectOriginal = nil
                inspectPlain = nil
            }
        }
    }
    @Published private(set) var inspectOriginal: CGImage? = nil
    @Published private(set) var inspectPlain: CGImage? = nil
    private var previewSource: (url: URL, image: CGImage)?
    private var previewTask: Task<Void, Never>?

    private var runTask: Task<Void, Never>?

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.optionsKey),
           let saved = try? JSONDecoder().decode(StoryOptions.self, from: data) {
            options = saved
        } else {
            options = StoryOptions()
        }
        if let path = UserDefaults.standard.string(forKey: Self.folderKey), FileManager.default.fileExists(atPath: path) {
            outputFolder = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            outputFolder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(options) { UserDefaults.standard.set(data, forKey: Self.optionsKey) }
    }

    // MARK: - Lista

    var selected: Item? { items.first { $0.id == selectedID } }
    var doneCount: Int { items.filter { $0.status == .done }.count }
    var failedCount: Int { items.filter { if case .failed = $0.status { return true } else { return false } }.count }
    var finishedCount: Int { items.filter { $0.status.isFinished }.count }

    private static func newSeed() -> UInt64 { UInt64.random(in: 1...UInt64.max) }

    /// Adiciona arquivos (ou pastas, que são abertas) até o limite de 100.
    func add(_ urls: [URL]) {
        guard !running else { return }
        var candidates: [URL] = []
        var unsupported = 0
        for url in urls {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                candidates += Paths.listImages(in: url)
            } else if Self.accepted.contains(url.pathExtension.lowercased()) {
                candidates.append(url)
            } else {
                unsupported += 1
            }
        }
        var known = Set(items.map { $0.url.standardizedFileURL.path })
        var added = 0, duplicated = 0, overLimit = 0
        for url in candidates {
            let key = url.standardizedFileURL.path
            if known.contains(key) { duplicated += 1; continue }
            if items.count >= Self.maxItems { overLimit += 1; continue }
            items.append(Item(url: url, seed: Self.newSeed()))
            known.insert(key)
            added += 1
        }
        var parts: [String] = []
        if overLimit > 0 { parts.append("Limite de \(Self.maxItems) imagens por lote: \(overLimit) ficaram de fora.") }
        if duplicated > 0 { parts.append("\(duplicated) já estavam na lista.") }
        if unsupported > 0 { parts.append("\(unsupported) arquivo(s) ignorado(s) — aceita JPG, PNG, WebP e HEIC.") }
        notice = parts.isEmpty ? nil : parts.joined(separator: " ")
        if added > 0 { resetResults() }
        if selectedID == nil || selected == nil { selectedID = items.first?.id }
    }

    func remove(_ id: UUID) {
        guard !running else { return }
        items.removeAll { $0.id == id }
        if selectedID == id { selectedID = items.first?.id }
    }

    func clear() {
        guard !running else { return }
        items.removeAll()
        selectedID = nil
        lastRunFolder = nil
        notice = nil
        previewSource = nil
        previewBefore = nil
        previewAfter = nil
        previewSummary = ""
    }

    /// Troca a semente de uma imagem (outro sorteio dentro dos mesmos limites).
    func reroll(_ id: UUID) {
        guard !running, let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].seed = Self.newSeed()
        refreshPreview()
    }

    private func resetResults() {
        for i in items.indices where items[i].status != .pending {
            items[i].status = .pending
            items[i].output = nil
            items[i].bytes = nil
            items[i].summary = nil
            items[i].doneVersions = 0
        }
        processedOutputs = 0
        writtenOutputs = 0
        totalOutputs = 0
    }

    // MARK: - Fila

    func start() {
        guard !running, !items.isEmpty else { return }
        guard let base = outputFolder else { notice = "Escolha a pasta de saída."; return }
        let stamp: String = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd_HHmmss"
            return f.string(from: Date())
        }()
        let dest = base.appendingPathComponent("stories_\(stamp)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        } catch {
            notice = "Não consegui criar a pasta de saída: \(error.localizedDescription)"
            return
        }

        resetResults()
        notice = nil
        lastRunFolder = dest
        running = true
        cancelling = false

        let opts = options
        let total = items.count
        let versions = opts.versions
        var jobs: [(id: UUID, url: URL, params: StoryParams, name: String)] = []
        // 1.0.0-beta.22: cada imagem sai em N versões, cada uma com o seu sorteio (a versão 1 é a do preview)
        for (index, item) in items.enumerated() {
            for v in 1...versions {
                let p = StoryParams.sample(opts, seed: StoryVersions.seed(item.seed, version: v))
                let name = StoryNames.fileName(index: index + 1, total: total, prefix: opts.prefix, code: p.code,
                                               naming: opts.naming, ext: opts.format.fileExtension,
                                               version: versions > 1 ? v : nil)
                jobs.append((item.id, item.url, p, name))
            }
        }
        totalOutputs = jobs.count
        let cap = Self.concurrency
        let started = Date()
        AppLog.info(.exportacao, "Otimizador em Lote: \(total) imagem(ns) × \(versions) versão(ões) → \(dest.lastPathComponent)",
                    details: "Enquadramento: \(opts.fit.label) · Intensidade: \(opts.intensity.label) · Linhas: \(opts.linesEnabled ? "\(opts.lineStyle.label), \(opts.lineDirection.label.lowercased())" : "não") · Texturas: \(opts.texturePreset.label) · Formato: \(opts.format.label)\(opts.mirror ? " · espelhado" : "")")

        runTask = Task { [weak self] in
            await BoundedParallel.run(jobs, limit: { cap }, work: { job -> Void? in
                guard !Task.isCancelled else { return nil }
                await self?.update(job.id) { if $0.status == .pending { $0.status = .processing } }
                let out = dest.appendingPathComponent(job.name)
                do {
                    let bytes = try StoryOptimizer.process(source: job.url, options: opts, params: job.params, to: out)
                    await self?.update(job.id, written: true) {
                        $0.doneVersions += 1
                        if $0.output == nil {
                            $0.output = out
                            $0.bytes = bytes
                            $0.summary = job.params.summary
                        }
                        if $0.doneVersions >= versions, $0.status == .processing { $0.status = .done }
                    }
                } catch {
                    let msg = error.localizedDescription
                    await self?.update(job.id, written: false) { $0.status = .failed(msg) }
                }
                return nil
            }, followUp: { (_: Void) in })
            await self?.finishRun(started: started)
        }
    }

    func cancel() {
        guard running else { return }
        cancelling = true
        runTask?.cancel()
    }

    /// `written`: nil = só muda o status; true/false = um arquivo terminou (gravado ou com erro).
    private func update(_ id: UUID, written: Bool? = nil, _ change: (inout Item) -> Void) {
        if let written {
            processedOutputs += 1
            if written { writtenOutputs += 1 }
        }
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[i])
    }

    private func finishRun(started: Date) {
        for i in items.indices where !items[i].status.isFinished {
            items[i].status = .cancelled
        }
        let wasCancelled = cancelling
        running = false
        cancelling = false
        runTask = nil
        let seconds = Int(Date().timeIntervalSince(started).rounded())
        let done = doneCount, failed = failedCount
        var text = totalOutputs > items.count
            ? "\(writtenOutputs) de \(totalOutputs) arquivos (\(done) de \(items.count) imagens completas) em \(seconds)s"
            : "\(done) de \(items.count) imagens prontas em \(seconds)s"
        if failed > 0 { text += " · \(failed) com erro" }
        if wasCancelled { text += " · lote cancelado" }
        notice = text + "."
        let failures = items.compactMap { item -> String? in
            if case let .failed(msg) = item.status { return "\(item.url.lastPathComponent): \(msg)" } else { return nil }
        }
        if failed > 0 || wasCancelled {
            AppLog.warning(.exportacao, "Otimizador em Lote: \(text)", details: failures.isEmpty ? nil : failures.joined(separator: "\n"))
        } else {
            AppLog.success(.exportacao, "Otimizador em Lote: \(text)", details: lastRunFolder?.path)
        }
        if !NSApp.isActive {
            Notifier.post(title: "Otimizador em Lote", body: text)
        }
    }

    // MARK: - ZIP

    /// Compacta a pasta do último lote com o `ditto` do próprio macOS (sem arquivos ocultos do Mac dentro do ZIP).
    func makeZip() {
        guard !running, !zipping, let folder = lastRunFolder else { return }
        guard let target = Pickers.saveFile(title: "Salvar ZIP dos stories", name: folder.lastPathComponent + ".zip") else { return }
        zipping = true
        Task {
            let failure: String? = await Task.detached(priority: .userInitiated) { () -> String? in
                try? FileManager.default.removeItem(at: target)
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                process.arguments = ["-c", "-k", "--norsrc", "--noextattr", "--keepParent", folder.path, target.path]
                let errPipe = Pipe()
                process.standardError = errPipe
                do {
                    try process.run()
                    process.waitUntilExit()
                } catch {
                    return error.localizedDescription
                }
                guard process.terminationStatus == 0 else {
                    let msg = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return (msg?.isEmpty == false) ? msg : "código \(process.terminationStatus)"
                }
                return nil
            }.value
            zipping = false
            if let failure {
                notice = "Não consegui criar o ZIP: \(failure)"
                AppLog.error(.exportacao, "Otimizador em Lote: falha ao criar o ZIP", details: failure)
            } else {
                notice = "ZIP salvo: \(target.lastPathComponent)"
                AppInfo.reveal(target)
            }
        }
    }

    // MARK: - Preview

    /// Redesenha o antes/depois da imagem selecionada com as opções atuais (mesma semente do arquivo final).
    func refreshPreview() {
        previewTask?.cancel()
        guard let item = selected else {
            previewBefore = nil
            previewAfter = nil
            previewSummary = ""
            previewLoading = false
            inspectOriginal = nil
            inspectPlain = nil
            return
        }
        let opts = options
        let inspect = inspecting
        let seed = StoryVersions.seed(item.seed, version: min(previewVersion, opts.versions))
        let url = item.url
        let cached = previewSource?.url == url ? previewSource?.image : nil
        previewLoading = true
        previewTask = Task { [weak self] in
            // espera um instante: arrastar um slider não redesenha a cada pixel
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            let result: (source: CGImage?, after: CGImage?, original: CGImage?, plain: CGImage?, summary: String) =
                await Task.detached(priority: .userInitiated) { () -> (CGImage?, CGImage?, CGImage?, CGImage?, String) in
                    let params = StoryParams.sample(opts, seed: seed)
                    guard let source = cached ?? StoryOptimizer.loadSource(url) else { return (nil, nil, nil, nil, params.summary) }
                    let after = StoryOptimizer.preview(source, options: opts, params: params)
                    var original: CGImage? = nil, plain: CGImage? = nil
                    if inspect {
                        // sem nenhuma variação (nem espelho): só o enquadramento 9:16 escolhido
                        original = StoryOptimizer.preview(source, options: opts, params: StoryParams())
                        // tudo igual ao arquivo final, menos as texturas — mesma geometria, dá para comparar pixel a pixel
                        plain = params.hasTexture ? StoryOptimizer.preview(source, options: opts, params: params.withoutTexture) : after
                    }
                    return (source, after, original, plain, params.summary)
                }.value
            guard !Task.isCancelled, let self else { return }
            if let source = result.source { self.previewSource = (url, source) }
            self.previewBefore = result.source
            self.previewAfter = result.after
            self.inspectOriginal = inspect ? result.original : nil
            self.inspectPlain = inspect ? result.plain : nil
            self.previewSummary = result.source == nil ? "Não consegui abrir esta imagem." : result.summary
            self.previewLoading = false
        }
    }
}
