import Foundation
import UniformTypeIdentifiers

/// Exporta os aprovados no tamanho e formato escolhidos, com nomenclatura padrão:
///   <pasta>/<cliente>/<lote>_<data>/<cliente>_<criativo>_v0.jpg   (limpo)
///   <pasta>/<cliente>/<lote>_<data>/<cliente>_<criativo>_v1.jpg   (variações)
enum Exporter {
    struct Result {
        let folder: URL
        let count: Int
        let failures: [String]
    }

    static func export(job: Job, jobFolder: URL, to base: URL) async throws -> Result {
        let stamp: String = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd_HHmm"
            return f.string(from: Date())
        }()
        let clientSlug = Paths.slug(job.client.name).isEmpty ? "cliente" : Paths.slug(job.client.name)
        let jobSlug = Paths.slug(job.name).isEmpty ? "lote" : Paths.slug(job.name)
        let dest = base.appendingPathComponent(clientSlug, isDirectory: true)
            .appendingPathComponent("\(jobSlug)_\(stamp)", isDirectory: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)

        let type: UTType = job.format == .png ? .png : .jpeg
        let ext = job.format.rawValue

        var tasks: [(src: URL, name: String, size: CGSize)] = []
        for item in job.items {
            let original = CGSize(width: item.pixelWidth, height: item.pixelHeight)
            let target: CGSize
            switch job.sizeMode {
            case .original: target = original
            case let .fixed(w, h): target = CGSize(width: w, height: h)
            }
            let base = "\(clientSlug)_\(Paths.slug(item.baseName))"
            if item.cleanReview == .approved, let f = item.cleanedFile {
                tasks.append((jobFolder.appendingPathComponent(f), "\(base)_v0.\(ext)", target))
            }
            for v in item.variations where v.review == .approved {
                if let f = v.file {
                    tasks.append((jobFolder.appendingPathComponent(f), "\(base)_v\(v.index).\(ext)", target))
                }
            }
        }

        let output = dest
        let work = tasks
        let outcome: (Int, [String]) = await Task.detached {
            var ok = 0
            var failed: [String] = []
            for t in work {
                guard let img = ImageTools.loadCGImage(t.src),
                      let sized = ImageTools.aspectFill(type == .jpeg ? ImageTools.flattened(img) : img, to: t.size),
                      let data = ImageTools.encode(type == .jpeg ? ImageTools.flattened(sized) : sized, as: type, quality: 0.92)
                else { failed.append(t.name); continue }
                do {
                    try data.write(to: output.appendingPathComponent(t.name), options: .atomic)
                    ok += 1
                } catch {
                    failed.append(t.name)
                }
            }
            return (ok, failed)
        }.value

        return Result(folder: dest, count: outcome.0, failures: outcome.1)
    }
}

enum CostEstimator {
    struct Estimate {
        let imageCalls: Int
        let analysisCalls: Int
        let usd: Double
    }

    @MainActor
    static func estimate(items: Int, variations: Int, clean: ProviderKind, variation: ProviderKind,
                         verifyText: Bool, settings: AppSettings) -> Estimate {
        let cleanCost = Double(items) * settings.imagePrice(for: clean)
        let varCost = Double(items * variations) * settings.imagePrice(for: variation)
        let analysis = items + (verifyText ? items * variations : 0)
        let total = cleanCost + varCost + Double(analysis) * settings.priceAnalysis
        return Estimate(imageCalls: items * (1 + variations), analysisCalls: analysis, usd: total)
    }
}
