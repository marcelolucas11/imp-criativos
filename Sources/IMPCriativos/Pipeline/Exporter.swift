import Foundation
import UniformTypeIdentifiers

/// Exporta os aprovados no tamanho e formato escolhidos, com nomenclatura padrão:
///   <pasta>/<cliente>/<lote>_<data>/<cliente>_<criativo>_v0.jpg   (limpo)
///   <pasta>/<cliente>/<lote>_<data>/<cliente>_<criativo>_v1.jpg   (variações)
///   <pasta>/<cliente>/<lote>_<data>/<cliente>_<criativo>_limpo.jpg (módulo Limpar logo)
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
                // 1.0.0-beta.20: no módulo "Limpar logo" o arquivo sai como _limpo
                tasks.append((jobFolder.appendingPathComponent(f), "\(base)_\(job.isCleanOnly ? "limpo" : "v0").\(ext)", target))
            }
            for v in item.variations where v.review == .approved {
                if let f = v.file {
                    // 1.0.0-beta.19: no teste de eixos, o nome leva o eixo (ex.: _v27_e27-titulo-3d) para comparar depois
                    let axis = job.isAxisTest ? "_" + (v.axisNumber.map { String(format: "e%02d-", $0) } ?? "") + Paths.slug(v.axisName) : ""
                    tasks.append((jobFolder.appendingPathComponent(f), "\(base)_v\(v.index)\(axis).\(ext)", target))
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
                         verifyText: Bool, settings: AppSettings, cleaning: Bool = true) -> Estimate {
        // 1.0.0-beta.20: com a limpeza desligada no lote, a imagem enviada é usada como está (sem custo de limpeza)
        let cleanCost = cleaning ? Double(items) * settings.imagePrice(for: clean) : 0
        let varCost = Double(items * variations) * settings.imagePrice(for: variation)
        let analysis = items + (verifyText ? items * variations : 0)
        let planning = settings.planningEnabled ? Double(items) * settings.pricePlanning : 0
        let total = cleanCost + varCost + Double(analysis) * settings.priceAnalysis + planning
        return Estimate(imageCalls: items * ((cleaning ? 1 : 0) + variations), analysisCalls: analysis, usd: total)
    }

    /// 1.0.0-beta.19: tempo estimado em minutos (faixa). Usa o tempo médio por imagem medido nesta sessão,
    /// ou 45 s se ainda não houver medida. O mínimo considera o modo rápido no teto; o máximo, a velocidade
    /// original com a IA 50% mais lenta.
    @MainActor
    static func minutes(items: Int, variations: Int, settings: AppSettings, secondsPerImage: Double?,
                        cleaning: Bool = true) -> ClosedRange<Int> {
        guard items > 0 else { return 0...0 }
        let lat = max(10, secondsPerImage ?? 45)
        let base = Double(max(1, settings.maxImageRequests))
        let top = settings.fastMode ? Double(max(settings.maxImageRequests, settings.fastImageCeiling)) : base
        let prelude = (settings.planningEnabled ? 40 : 0) + (cleaning ? lat : 0) + 15
        let rounds = (Double(items) / Double(max(1, settings.maxConcurrent))).rounded(.up)
        let images = Double(items * variations)
        // 1.0.0-beta.20: só limpeza — o tempo é o das rodadas de limpeza (os criativos rodam em paralelo)
        let low = variations == 0 ? rounds * prelude * 0.7 : prelude + images * lat / top
        let high = rounds * prelude + images * lat * 1.5 / base
        let lo = max(1, Int((low / 60).rounded()))
        return lo...max(lo, Int((high / 60).rounded(.up)))
    }

    static func minutesLabel(_ r: ClosedRange<Int>) -> String {
        func f(_ m: Int) -> String { m < 60 ? "\(m) min" : String(format: "%dh%02d", m / 60, m % 60) }
        return r.lowerBound == r.upperBound ? "~\(f(r.lowerBound))" : "~\(f(r.lowerBound)) a \(f(r.upperBound))"
    }
}
