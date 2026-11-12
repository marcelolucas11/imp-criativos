import Foundation
import Combine

/// Lotes de processamento. Cada lote tem sua pasta em Application Support/jobs/<id>
/// com o job.json e todas as imagens intermediárias — por isso o app retoma de onde parou.
@MainActor
final class JobStore: ObservableObject {
    @Published private(set) var jobs: [Job] = []

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init() { load() }

    func load() {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: Paths.jobs, includingPropertiesForKeys: nil)) ?? []
        jobs = dirs
            .compactMap { try? decoder.decode(Job.self, from: Data(contentsOf: $0.appendingPathComponent("job.json"))) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func job(_ id: UUID) -> Job? { jobs.first { $0.id == id } }

    func folder(for id: UUID) -> URL { Paths.jobFolder(id) }

    func fileURL(job: UUID, _ name: String?) -> URL? {
        guard let name else { return nil }
        return folder(for: job).appendingPathComponent(name)
    }

    func save(_ job: Job) {
        if let i = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[i] = job
        } else {
            jobs.insert(job, at: 0)
        }
        persist(job)
    }

    private func persist(_ job: Job) {
        let url = folder(for: job.id).appendingPathComponent("job.json")
        if let data = try? encoder.encode(job) {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Altera um lote e salva em disco.
    func update(_ id: UUID, _ change: (inout Job) -> Void) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[i])
        persist(jobs[i])
    }

    func updateItem(_ jobID: UUID, _ itemID: UUID, _ change: (inout JobItem) -> Void) {
        update(jobID) { job in
            guard let i = job.items.firstIndex(where: { $0.id == itemID }) else { return }
            change(&job.items[i])
        }
    }

    func updateVariation(_ jobID: UUID, _ itemID: UUID, _ varID: UUID, _ change: (inout Variation) -> Void) {
        updateItem(jobID, itemID) { item in
            guard let i = item.variations.firstIndex(where: { $0.id == varID }) else { return }
            change(&item.variations[i])
        }
    }

    func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: folder(for: id))
        jobs.removeAll { $0.id == id }
    }

    /// Cria um lote: copia os originais para a pasta do lote e prepara as variações.
    func createJob(name: String,
                   client: ClientProfile,
                   inputFolder: URL,
                   files: [URL],
                   variations: Int,
                   cleanProvider: ProviderKind,
                   variationProvider: ProviderKind,
                   analysisProvider: ProviderKind,
                   sizeMode: OutputSizeMode,
                   format: OutputFormat,
                   verifyText: Bool,
                   instructions: BatchInstructions? = nil,
                   axisTest: Bool = false,
                   cleanOnly: Bool = false,
                   skipCleaning: Bool = false) throws -> Job {
        let id = UUID()
        let folder = folder(for: id)
        let originals = Paths.ensure(folder.appendingPathComponent("originais", isDirectory: true))
        let axes = client.axes.isEmpty ? ClientProfile.defaultAxes : client.axes
        let rotate = client.rotatesAxes
        // 1.0.0-beta.19: no teste de eixos, cada criativo passa por todos os eixos da lista, na ordem
        // 1.0.0-beta.20: no módulo "Limpar logo" não há variações
        let perItem = cleanOnly ? 0 : (axisTest ? axes.count : max(1, variations))

        var items: [JobItem] = []
        for (n, src) in files.enumerated() {
            let ext = src.pathExtension.lowercased()
            let rel = "originais/\(String(format: "%03d", n + 1)).\(ext)"
            let dst = originals.appendingPathComponent("\(String(format: "%03d", n + 1)).\(ext)")
            try FileManager.default.copyItem(at: src, to: dst)
            let size = ImageTools.pixelSize(of: dst) ?? CGSize(width: 1080, height: 1080)
            // Rodízio (beta.14; chave por cliente desde a beta.18): com 4 variações, o 1º criativo usa os eixos 1–4,
            // o 2º os eixos 5–8… e no fim da lista recomeça. Desligado: todo criativo usa os N primeiros da lista.
            let vars = (0..<perItem).map { i -> Variation in
                let axis = axisTest ? axes[i] : axes[(rotate ? n * perItem + i : i) % axes.count]
                var v = Variation(index: i + 1, axisName: axis.name, axisInstruction: axis.instruction)
                v.axisNumber = AxisCatalog.entry(matching: axis)?.number
                return v
            }
            items.append(JobItem(sourceName: src.lastPathComponent,
                                 originalFile: rel,
                                 pixelWidth: Int(size.width),
                                 pixelHeight: Int(size.height),
                                 variations: vars))
        }

        let job = Job(id: id,
                      name: name,
                      client: client,
                      inputFolder: inputFolder.path,
                      cleanProvider: cleanProvider,
                      variationProvider: variationProvider,
                      analysisProvider: analysisProvider,
                      variationsPerItem: perItem,
                      sizeMode: sizeMode,
                      format: format,
                      verifyText: verifyText,
                      items: items,
                      instructions: (instructions?.isEmpty ?? true) ? nil : instructions,
                      axisTest: (axisTest && !cleanOnly) ? true : nil,
                      cleanOnly: cleanOnly ? true : nil,
                      skipCleaning: (skipCleaning && !cleanOnly) ? true : nil)
        save(job)
        return job
    }

    /// 1.0.0-beta.19 — integridade: etapa marcada como pronta cuja imagem sumiu do disco volta para a fila.
    /// Roda antes de cada rodada do lote, então nada termina "pronto" sem o arquivo existir.
    /// Devolve quantas etapas voltaram.
    @discardableResult
    func repairMissingFiles(_ id: UUID) -> Int {
        guard let job = job(id) else { return 0 }
        let base = folder(for: id)
        let exists: (String?) -> Bool = { rel in
            guard let rel else { return false }
            return FileManager.default.fileExists(atPath: base.appendingPathComponent(rel).path)
        }
        var broken = 0
        for item in job.items {
            if item.cleanStatus == .done && !exists(item.cleanedFile) { broken += 1 }
            broken += item.variations.filter { $0.status == .done && !exists($0.file) }.count
        }
        guard broken > 0 else { return 0 }
        update(id) { job in
            for i in job.items.indices {
                if job.items[i].cleanStatus == .done && !exists(job.items[i].cleanedFile) {
                    job.items[i].cleanStatus = .pending
                    job.items[i].cleanedFile = nil
                    job.items[i].analysisDone = false
                    job.items[i].cleanReview = .pending
                }
                for v in job.items[i].variations.indices
                where job.items[i].variations[v].status == .done && !exists(job.items[i].variations[v].file) {
                    job.items[i].variations[v].status = .pending
                    job.items[i].variations[v].file = nil
                    job.items[i].variations[v].review = .pending
                }
            }
        }
        return broken
    }

    /// Gasto (estimado) no mês corrente, somando todos os lotes.
    var monthCost: Double {
        let cal = Calendar.current
        let now = Date()
        return jobs.filter { cal.isDate($0.createdAt, equalTo: now, toGranularity: .month) }
            .reduce(0) { $0 + $1.costUSD }
    }
}
