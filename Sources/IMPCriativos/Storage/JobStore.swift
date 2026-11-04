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
                   verifyText: Bool) throws -> Job {
        let id = UUID()
        let folder = folder(for: id)
        let originals = Paths.ensure(folder.appendingPathComponent("originais", isDirectory: true))
        let axes = client.axes.isEmpty ? ClientProfile.defaultAxes : client.axes

        var items: [JobItem] = []
        for (n, src) in files.enumerated() {
            let ext = src.pathExtension.lowercased()
            let rel = "originais/\(String(format: "%03d", n + 1)).\(ext)"
            let dst = originals.appendingPathComponent("\(String(format: "%03d", n + 1)).\(ext)")
            try FileManager.default.copyItem(at: src, to: dst)
            let size = ImageTools.pixelSize(of: dst) ?? CGSize(width: 1080, height: 1080)
            let vars = (0..<variations).map { i -> Variation in
                let axis = axes[i % axes.count]
                return Variation(index: i + 1, axisName: axis.name, axisInstruction: axis.instruction)
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
                      variationsPerItem: variations,
                      sizeMode: sizeMode,
                      format: format,
                      verifyText: verifyText,
                      items: items)
        save(job)
        return job
    }

    /// Gasto (estimado) no mês corrente, somando todos os lotes.
    var monthCost: Double {
        let cal = Calendar.current
        let now = Date()
        return jobs.filter { cal.isDate($0.createdAt, equalTo: now, toGranularity: .month) }
            .reduce(0) { $0 + $1.costUSD }
    }
}
