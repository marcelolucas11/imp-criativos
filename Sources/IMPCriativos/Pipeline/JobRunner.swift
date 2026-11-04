import Foundation
import Combine

/// Executa os lotes: limpeza → análise → variações → checagem de texto.
/// Cada passo é salvo em disco; pausar, fechar o app ou desligar o Mac não perde trabalho.
@MainActor
final class JobRunner: ObservableObject {
    @Published private(set) var running: Set<UUID> = []

    private let store: JobStore
    private let settings: AppSettings
    private var tasks: [UUID: Task<Void, Never>] = [:]

    init(store: JobStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
    }

    var hasActiveWork: Bool { !running.isEmpty }

    // MARK: controle

    func start(_ jobID: UUID) {
        guard tasks[jobID] == nil, let job = store.job(jobID), job.state != .cancelled else { return }
        store.update(jobID) { $0.state = .running; $0.lastError = nil }
        running.insert(jobID)
        tasks[jobID] = Task { [weak self] in
            await self?.run(jobID)
            self?.tasks[jobID] = nil
            self?.running.remove(jobID)
        }
    }

    func pause(_ jobID: UUID) {
        tasks[jobID]?.cancel()
        store.update(jobID) { $0.state = .paused }
    }

    func cancel(_ jobID: UUID) {
        tasks[jobID]?.cancel()
        store.update(jobID) { $0.state = .cancelled }
    }

    func pauseAll() { running.forEach(pause) }

    /// Ao abrir o app: retoma lotes que estavam rodando quando ele foi fechado.
    func resumeInterrupted() {
        for job in store.jobs where job.state == .running || job.state == .queued {
            start(job.id)
        }
    }

    func redoClean(_ jobID: UUID, _ itemID: UUID, note: String?) {
        store.updateItem(jobID, itemID) { item in
            item.cleanStatus = .pending
            item.cleanError = nil
            item.cleanWarning = nil
            item.cleanReview = .pending
            item.cleanRedoNote = note
            item.analysisDone = false
        }
        start(jobID)
    }

    func redoVariation(_ jobID: UUID, _ itemID: UUID, _ varID: UUID, note: String?) {
        store.updateVariation(jobID, itemID, varID) { v in
            v.status = .pending
            v.error = nil
            v.textWarning = nil
            v.review = .pending
            v.redoNote = note
        }
        start(jobID)
    }

    func retryFailed(_ jobID: UUID) {
        store.update(jobID) { job in
            for i in job.items.indices {
                if job.items[i].cleanStatus == .failed {
                    job.items[i].cleanStatus = .pending
                    job.items[i].cleanError = nil
                }
                for v in job.items[i].variations.indices where job.items[i].variations[v].status == .failed {
                    job.items[i].variations[v].status = .pending
                    job.items[i].variations[v].error = nil
                }
            }
        }
        start(jobID)
    }

    // MARK: execução

    private func needsWork(_ item: JobItem) -> Bool {
        if item.cleanStatus == .pending || item.cleanStatus == .running { return true }
        guard item.cleanStatus == .done else { return false }
        return !item.analysisDone || item.variations.contains { $0.status == .pending || $0.status == .running }
    }

    private func run(_ jobID: UUID) async {
        guard let job = store.job(jobID) else { return }
        let config = ProviderConfig(settings)

        // prepara os provedores das três etapas
        var providers: [ProviderKind: AIProvider] = [:]
        for kind in Set([job.cleanProvider, job.variationProvider, job.analysisProvider]) {
            do { providers[kind] = try ProviderFactory.make(kind, config: config) }
            catch {
                store.update(jobID) { $0.state = .paused; $0.lastError = error.localizedDescription }
                return
            }
        }

        // passos interrompidos no meio voltam para "pendente"
        store.update(jobID) { job in
            for i in job.items.indices {
                if job.items[i].cleanStatus == .running { job.items[i].cleanStatus = .pending }
                for v in job.items[i].variations.indices where job.items[i].variations[v].status == .running {
                    job.items[i].variations[v].status = .pending
                }
            }
        }

        let workers = max(1, settings.maxConcurrent)

        // repete enquanto aparecer trabalho novo (ex.: "refazer" clicado durante o lote)
        while !Task.isCancelled {
            guard let current = store.job(jobID) else { return }
            let pending = current.items.filter { needsWork($0) }.map(\.id)
            if pending.isEmpty { break }
            let queue = WorkQueue(pending)

            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<min(workers, pending.count) {
                    group.addTask { @MainActor [weak self] in
                        while !Task.isCancelled, let id = queue.next() {
                            await self?.process(jobID: jobID, itemID: id, providers: providers)
                        }
                    }
                }
            }
        }

        guard !Task.isCancelled, let finished = store.job(jobID), finished.state == .running else { return }
        store.update(jobID) { $0.state = .review }
        if settings.notifyOnFinish {
            let failed = finished.items.filter { $0.hasFailure }.count
            Notifier.post(title: "Lote pronto para revisão",
                          body: "\(finished.name): \(finished.items.count) criativos processados"
                              + (failed > 0 ? ", \(failed) com falha." : "."))
        }
    }

    private func process(jobID: UUID, itemID: UUID, providers: [ProviderKind: AIProvider]) async {
        guard let job = store.job(jobID), let item = job.items.first(where: { $0.id == itemID }) else { return }
        let folder = store.folder(for: jobID)
        let removeItems = job.client.removeItems
        let extra = job.client.extraInstructions

        // 1. LIMPEZA
        if item.cleanStatus != .done {
            store.updateItem(jobID, itemID) { $0.cleanStatus = .running }
            do {
                let src = folder.appendingPathComponent(item.originalFile)
                guard let upload = await Task.detached(operation: { ImageTools.uploadJPEG(src) }).value else {
                    throw AIError("Não foi possível ler a imagem original.")
                }
                let aspect = ImageTools.nearestAspectRatio(width: item.pixelWidth, height: item.pixelHeight)
                let prompt = Prompts.clean(removeItems: removeItems, extra: extra, redoNote: item.cleanRedoNote)
                let result = try await providers[job.cleanProvider]!.editImage(upload, prompt: prompt, aspectRatio: aspect)
                let rel = "limpos/\(Self.short(itemID))-\(Self.short(UUID())).png"
                Paths.ensure(folder.appendingPathComponent("limpos", isDirectory: true))
                try ImageTools.saveGenerated(result, to: folder.appendingPathComponent(rel))
                store.update(jobID) { $0.costUSD += self.settings.imagePrice(for: job.cleanProvider) }
                store.updateItem(jobID, itemID) {
                    $0.cleanedFile = rel
                    $0.cleanStatus = .done
                    $0.analysisDone = false
                }
            } catch is CancellationError {
                store.updateItem(jobID, itemID) { $0.cleanStatus = .pending }
                return
            } catch {
                if Task.isCancelled { store.updateItem(jobID, itemID) { $0.cleanStatus = .pending }; return }
                store.updateItem(jobID, itemID) {
                    $0.cleanStatus = .failed
                    $0.cleanError = error.localizedDescription
                }
                return
            }
        }

        // 2. ANÁLISE: checa sobras de marca e transcreve o texto
        guard let cleaned = store.job(jobID)?.items.first(where: { $0.id == itemID }),
              let cleanedRel = cleaned.cleanedFile else { return }
        let cleanedURL = folder.appendingPathComponent(cleanedRel)
        if !cleaned.analysisDone {
            do {
                guard let jpeg = await Task.detached(operation: { ImageTools.uploadJPEG(cleanedURL) }).value else {
                    throw AIError("Não foi possível ler a imagem limpa.")
                }
                let raw = try await providers[job.analysisProvider]!.analyze(jpeg, prompt: Prompts.analysis(removeItems: removeItems))
                store.update(jobID) { $0.costUSD += self.settings.priceAnalysis }
                let obj = JSONExtract.object(from: raw) ?? [:]
                let isClean = (obj["clean"] as? Bool) ?? true
                let found = (obj["found"] as? [String]) ?? []
                let text = (obj["text"] as? String) ?? ""
                store.updateItem(jobID, itemID) {
                    $0.transcript = text
                    $0.cleanWarning = isClean ? nil : "Possível sobra de marca: " + (found.isEmpty ? "verifique" : found.joined(separator: ", "))
                    $0.analysisDone = true
                }
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                // sem análise o lote continua; as variações só não terão o texto travado
                store.updateItem(jobID, itemID) {
                    $0.cleanWarning = "Não foi possível conferir a limpeza: \(error.localizedDescription)"
                    $0.analysisDone = true
                }
            }
        }

        // 3. VARIAÇÕES
        guard let ready = store.job(jobID)?.items.first(where: { $0.id == itemID }) else { return }
        let reference = await Task.detached(operation: { ImageTools.uploadJPEG(cleanedURL) }).value
        guard let reference else { return }
        let aspect = ImageTools.nearestAspectRatio(width: ready.pixelWidth, height: ready.pixelHeight)

        for v in ready.variations where v.status == .pending || v.status == .running {
            if Task.isCancelled { return }
            store.updateVariation(jobID, itemID, v.id) { $0.status = .running; $0.attempts += 1 }
            do {
                let axis = VariationAxis(name: v.axisName, instruction: v.axisInstruction)
                let prompt = Prompts.variation(axis: axis, transcript: ready.transcript, extra: extra, redoNote: v.redoNote)
                let result = try await providers[job.variationProvider]!.editImage(reference, prompt: prompt, aspectRatio: aspect)
                let rel = "variacoes/\(Self.short(itemID))-v\(v.index)-\(Self.short(UUID())).png"
                Paths.ensure(folder.appendingPathComponent("variacoes", isDirectory: true))
                let out = folder.appendingPathComponent(rel)
                try ImageTools.saveGenerated(result, to: out)
                store.update(jobID) { $0.costUSD += self.settings.imagePrice(for: job.variationProvider) }
                store.updateVariation(jobID, itemID, v.id) {
                    $0.file = rel
                    $0.status = .done
                    $0.error = nil
                }

                // 4. CHECAGEM DO TEXTO
                if job.verifyText, let expected = ready.transcript, !expected.isEmpty,
                   let jpeg = await Task.detached(operation: { ImageTools.uploadJPEG(out) }).value {
                    do {
                        let raw = try await providers[job.analysisProvider]!.analyze(
                            jpeg, prompt: Prompts.textCheck(expected: expected, removeItems: removeItems))
                        store.update(jobID) { $0.costUSD += self.settings.priceAnalysis }
                        let obj = JSONExtract.object(from: raw) ?? [:]
                        let match = (obj["match"] as? Bool) ?? true
                        let diff = (obj["differences"] as? String) ?? ""
                        let brand = (obj["brand_found"] as? [String]) ?? []
                        var warnings: [String] = []
                        if !match { warnings.append("Texto diferente: " + (diff.isEmpty ? "verifique" : diff)) }
                        if !brand.isEmpty { warnings.append("Marca apareceu: " + brand.joined(separator: ", ")) }
                        store.updateVariation(jobID, itemID, v.id) {
                            $0.textWarning = warnings.isEmpty ? nil : warnings.joined(separator: " · ")
                        }
                    } catch {
                        // checagem é auxiliar: falha aqui não derruba a variação
                    }
                }
            } catch is CancellationError {
                store.updateVariation(jobID, itemID, v.id) { $0.status = .pending }
                return
            } catch {
                if Task.isCancelled { store.updateVariation(jobID, itemID, v.id) { $0.status = .pending }; return }
                store.updateVariation(jobID, itemID, v.id) {
                    $0.status = .failed
                    $0.error = error.localizedDescription
                }
            }
        }
    }

    static func short(_ id: UUID) -> String { String(id.uuidString.prefix(8)).lowercased() }
}

/// Fila simples compartilhada entre os "trabalhadores" de um lote (tudo no MainActor).
@MainActor
final class WorkQueue {
    private var ids: [UUID]
    init(_ ids: [UUID]) { self.ids = ids.reversed() }
    func next() -> UUID? { ids.popLast() }
}
