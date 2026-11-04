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

    /// Regras de troca automática de IA, lidas das Configurações quando o lote começa.
    struct FallbackRule {
        var enabled: Bool
        var onBlocked: Bool

        func applies(to error: Error) -> Bool {
            guard enabled else { return false }
            let kind = error.aiKind
            return kind.isTemporary || (onBlocked && kind == .blocked)
        }
    }

    // MARK: controle

    func start(_ jobID: UUID) {
        guard tasks[jobID] == nil, let job = store.job(jobID), job.state != .cancelled else { return }
        let wasStarted = job.finishedSteps > 0
        store.update(jobID) { $0.state = .running; $0.lastError = nil }
        AppLog.info(.lote, wasStarted ? "Lote retomado." : "Lote iniciado.",
                    details: """
                    \(job.items.count) criativos · \(job.variationsPerItem) variações cada · saída \(job.sizeMode.label) \(job.format.label)
                    Limpeza: \(job.cleanProvider.label) · Variações: \(job.variationProvider.label) · Análise: \(job.analysisProvider.label)
                    \(settings.summary)
                    """,
                    jobID: jobID, jobName: job.name)
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
        if let job = store.job(jobID) { AppLog.info(.lote, "Lote pausado.", jobID: jobID, jobName: job.name) }
    }

    func cancel(_ jobID: UUID) {
        tasks[jobID]?.cancel()
        store.update(jobID) { $0.state = .cancelled }
        if let job = store.job(jobID) { AppLog.warning(.lote, "Lote cancelado.", jobID: jobID, jobName: job.name) }
    }

    func pauseAll() { running.forEach(pause) }

    /// Ao abrir o app: retoma lotes que estavam rodando quando ele foi fechado.
    func resumeInterrupted() {
        for job in store.jobs where job.state == .running || job.state == .queued {
            AppLog.info(.sistema, "Retomando lote interrompido quando o app fechou.", jobID: job.id, jobName: job.name)
            start(job.id)
        }
    }

    func redoClean(_ jobID: UUID, _ itemID: UUID, note: String?, using provider: ProviderKind? = nil) {
        store.updateItem(jobID, itemID) { item in
            item.cleanStatus = .pending
            item.cleanError = nil
            item.cleanErrorKind = nil
            item.cleanErrorDetails = nil
            item.cleanWarning = nil
            item.cleanReview = .pending
            item.cleanRedoNote = note
            item.cleanProviderOverride = provider ?? item.cleanProviderOverride
            item.analysisDone = false
        }
        if let job = store.job(jobID), let item = job.items.first(where: { $0.id == itemID }) {
            var msg = "Limpeza enviada para refazer"
            if let provider { msg += " com \(provider.label)" }
            AppLog.info(.revisao, msg + ".", details: note.map { "Observação: \($0)" },
                        jobID: jobID, jobName: job.name, item: item.sourceName)
        }
        start(jobID)
    }

    func redoVariation(_ jobID: UUID, _ itemID: UUID, _ varID: UUID, note: String?, using provider: ProviderKind? = nil) {
        store.updateVariation(jobID, itemID, varID) { v in
            v.status = .pending
            v.error = nil
            v.errorKind = nil
            v.errorDetails = nil
            v.textWarning = nil
            v.review = .pending
            v.redoNote = note
            v.providerOverride = provider ?? v.providerOverride
        }
        if let job = store.job(jobID), let item = job.items.first(where: { $0.id == itemID }),
           let v = item.variations.first(where: { $0.id == varID }) {
            var msg = "Variação v\(v.index) enviada para refazer"
            if let provider { msg += " com \(provider.label)" }
            AppLog.info(.revisao, msg + ".", details: note.map { "Observação: \($0)" },
                        jobID: jobID, jobName: job.name, item: item.sourceName)
        }
        start(jobID)
    }

    /// Volta para a fila tudo que falhou. Com `provider`, força essa IA nas etapas refeitas.
    func retryFailed(_ jobID: UUID, using provider: ProviderKind? = nil) {
        var count = 0
        store.update(jobID) { job in
            for i in job.items.indices {
                if job.items[i].cleanStatus == .failed {
                    job.items[i].cleanStatus = .pending
                    job.items[i].cleanError = nil
                    job.items[i].cleanErrorKind = nil
                    job.items[i].cleanErrorDetails = nil
                    if let provider { job.items[i].cleanProviderOverride = provider }
                    count += 1
                }
                for v in job.items[i].variations.indices where job.items[i].variations[v].status == .failed {
                    job.items[i].variations[v].status = .pending
                    job.items[i].variations[v].error = nil
                    job.items[i].variations[v].errorKind = nil
                    job.items[i].variations[v].errorDetails = nil
                    if let provider { job.items[i].variations[v].providerOverride = provider }
                    count += 1
                }
            }
        }
        guard count > 0, let job = store.job(jobID) else { return }
        AppLog.info(.lote, "\(count) etapa(s) com falha voltaram para a fila" + (provider.map { " usando \($0.label)" } ?? "") + ".",
                    jobID: jobID, jobName: job.name)
        start(jobID)
    }

    /// "Tentar falhas de novo" em todos os lotes de uma vez.
    func retryAllFailed() {
        for job in store.jobs where job.failureCount > 0 && job.state != .cancelled {
            retryFailed(job.id)
        }
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
        await ProviderGate.configure(imageLimit: settings.maxImageRequests)

        // provedores escolhidos no lote são obrigatórios; o outro entra como reserva se tiver chave
        var providers: [ProviderKind: AIProvider] = [:]
        let required = Set([job.cleanProvider, job.variationProvider, job.analysisProvider])
        for kind in ProviderKind.allCases {
            do { providers[kind] = try ProviderFactory.make(kind, config: config) }
            catch {
                guard required.contains(kind) else { continue }
                store.update(jobID) { $0.state = .paused; $0.lastError = error.localizedDescription }
                AppLog.error(.lote, "Lote pausado: \(error.localizedDescription)", jobID: jobID, jobName: job.name)
                return
            }
        }

        // passos interrompidos no meio voltam para "pendente"
        store.update(jobID) { job in
            for i in job.items.indices {
                job.items[i].cleanRetryNote = nil
                job.items[i].cleanRetryAt = nil
                if job.items[i].cleanStatus == .running { job.items[i].cleanStatus = .pending }
                for v in job.items[i].variations.indices {
                    job.items[i].variations[v].retryNote = nil
                    job.items[i].variations[v].retryAt = nil
                    if job.items[i].variations[v].status == .running { job.items[i].variations[v].status = .pending }
                }
            }
        }

        let workers = max(1, settings.maxConcurrent)
        let available = providers
        let rule = FallbackRule(enabled: settings.fallbackEnabled, onBlocked: settings.fallbackOnBlocked)
        let attempts = max(1, settings.retryAttempts)

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
                            await self?.process(jobID: jobID, itemID: id, providers: available, rule: rule, attempts: attempts)
                        }
                    }
                }
            }
        }

        guard !Task.isCancelled, let finished = store.job(jobID), finished.state == .running else { return }
        store.update(jobID) { $0.state = .review }
        let failed = finished.failureCount
        let summary = "\(finished.items.count) criativos · \(finished.failureCount) etapa(s) com falha · \(finished.warningCount) com alerta · gasto estimado \(finished.costUSD.usd)"
        if failed > 0 {
            AppLog.warning(.lote, "Lote terminou com falhas. Use \"Tentar falhas de novo\".", details: summary, jobID: jobID, jobName: finished.name)
        } else {
            AppLog.success(.lote, "Lote concluído, pronto para revisão.", details: summary, jobID: jobID, jobName: finished.name)
        }
        if settings.notifyOnFinish {
            Notifier.post(title: "Lote pronto para revisão",
                          body: "\(finished.name): \(finished.items.count) criativos processados"
                              + (failed > 0 ? ", \(failed) etapa(s) com falha." : "."))
        }
    }

    /// Chama a IA principal; se falhar por erro temporário (ou bloqueio, se ligado) e houver chave da outra, refaz com ela.
    private func withFallback<T>(_ primary: ProviderKind,
                                 _ providers: [ProviderKind: AIProvider],
                                 rule: FallbackRule,
                                 ctx: RequestContext,
                                 _ op: (AIProvider) async throws -> T) async throws -> (T, ProviderKind) {
        guard let main = providers[primary] else {
            throw AIError("Chave do \(primary.label) não configurada. Vá em Configurações → Chaves de API.", kind: .auth)
        }
        do {
            let value = try await RequestContext.$current.withValue(ctx) { try await op(main) }
            return (value, primary)
        } catch {
            if error is CancellationError || Task.isCancelled { throw error }
            let alt: ProviderKind = primary == .gemini ? .openai : .gemini
            guard rule.applies(to: error), let other = providers[alt] else { throw error }
            ctx.log(.warning, "\(primary.label) falhou (\(error.aiKind.title)). Refazendo automaticamente com \(alt.label).",
                    details: error.aiDetails ?? error.localizedDescription)
            ctx.onStatus?("Trocando para \(alt.label)…", nil)
            var altCtx = ctx
            altCtx.step = ctx.step + " (\(alt.label))"
            let value = try await RequestContext.$current.withValue(altCtx) { try await op(other) }
            return (value, alt)
        }
    }

    private func context(_ job: Job, _ item: JobItem, step: String, category: LogCategory, attempts: Int,
                         onStatus: (@Sendable (String?, Date?) -> Void)?) -> RequestContext {
        RequestContext(jobID: job.id, jobName: job.name, item: item.sourceName, step: step, category: category,
                       maxAttempts: attempts, onStatus: onStatus)
    }

    private func process(jobID: UUID, itemID: UUID, providers: [ProviderKind: AIProvider], rule: FallbackRule, attempts: Int) async {
        guard let job = store.job(jobID), let item = job.items.first(where: { $0.id == itemID }) else { return }
        let folder = store.folder(for: jobID)
        let removeItems = job.effectiveRemoveItems
        let extra = job.client.extraInstructions
        let textChanges = job.instructions?.textChanges ?? ""
        let direction = job.instructions?.direction ?? ""
        let name = item.sourceName

        // 1. LIMPEZA
        if item.cleanStatus != .done {
            store.updateItem(jobID, itemID) { $0.cleanStatus = .running; $0.cleanRetryNote = nil; $0.cleanRetryAt = nil }
            let started = Date()
            let ctx = context(job, item, step: "Limpeza", category: .limpeza, attempts: attempts) { [weak self] note, until in
                Task { @MainActor in
                    self?.store.updateItem(jobID, itemID) {
                        guard $0.cleanStatus == .running else { return }
                        $0.cleanRetryNote = note
                        $0.cleanRetryAt = until
                    }
                }
            }
            do {
                let src = folder.appendingPathComponent(item.originalFile)
                guard let upload = await Task.detached(operation: { ImageTools.uploadJPEG(src) }).value else {
                    throw AIError("Não foi possível ler a imagem original.")
                }
                let aspect = Self.aspect(job.sizeMode, width: item.pixelWidth, height: item.pixelHeight)
                let prompt = Prompts.clean(removeItems: removeItems, extra: extra, textChanges: textChanges, redoNote: item.cleanRedoNote)
                let primary = item.cleanProviderOverride ?? job.cleanProvider
                let (result, used) = try await withFallback(primary, providers, rule: rule, ctx: ctx) {
                    try await $0.editImage(upload, prompt: prompt, aspectRatio: aspect)
                }
                let rel = "limpos/\(Self.short(itemID))-\(Self.short(UUID())).png"
                Paths.ensure(folder.appendingPathComponent("limpos", isDirectory: true))
                try ImageTools.saveGenerated(result, to: folder.appendingPathComponent(rel))
                store.update(jobID) { $0.costUSD += self.settings.imagePrice(for: used) }
                store.updateItem(jobID, itemID) {
                    $0.cleanedFile = rel
                    $0.cleanStatus = .done
                    $0.cleanRetryNote = nil
                    $0.cleanRetryAt = nil
                    $0.cleanProviderUsed = used
                    $0.analysisDone = false
                }
                ctx.log(.success, "concluída com \(used.label) em \(Self.elapsed(started)).")
            } catch is CancellationError {
                store.updateItem(jobID, itemID) { $0.cleanStatus = .pending; $0.cleanRetryNote = nil; $0.cleanRetryAt = nil }
                return
            } catch {
                if Task.isCancelled {
                    store.updateItem(jobID, itemID) { $0.cleanStatus = .pending; $0.cleanRetryNote = nil; $0.cleanRetryAt = nil }
                    return
                }
                store.updateItem(jobID, itemID) {
                    $0.cleanStatus = .failed
                    $0.cleanError = error.localizedDescription
                    $0.cleanErrorKind = error.aiKind
                    $0.cleanErrorDetails = error.aiDetails
                    $0.cleanRetryNote = nil
                    $0.cleanRetryAt = nil
                }
                ctx.log(.error, "falhou — \(error.aiKind.title). \(error.localizedDescription)",
                        details: [error.aiDetails, "Sugestão: \(error.aiKind.hint)"].compactMap { $0 }.joined(separator: "\n"))
                return
            }
        }

        // 2. ANÁLISE: checa sobras de marca e transcreve o texto
        guard let cleaned = store.job(jobID)?.items.first(where: { $0.id == itemID }),
              let cleanedRel = cleaned.cleanedFile else { return }
        let cleanedURL = folder.appendingPathComponent(cleanedRel)
        if !cleaned.analysisDone {
            let ctx = context(job, cleaned, step: "Análise", category: .analise, attempts: attempts, onStatus: nil)
            do {
                guard let jpeg = await Task.detached(operation: { ImageTools.uploadJPEG(cleanedURL) }).value else {
                    throw AIError("Não foi possível ler a imagem limpa.")
                }
                let prompt = Prompts.analysis(removeItems: removeItems, textChanges: textChanges)
                let (raw, _) = try await withFallback(job.analysisProvider, providers, rule: rule, ctx: ctx) {
                    try await $0.analyze(jpeg, prompt: prompt)
                }
                store.update(jobID) { $0.costUSD += self.settings.priceAnalysis }
                let obj = JSONExtract.object(from: raw) ?? [:]
                let isClean = (obj["clean"] as? Bool) ?? true
                let found = (obj["found"] as? [String]) ?? []
                let text = (obj["text"] as? String) ?? ""
                // Com alterações de texto no lote, o texto esperado das variações é o final (já alterado).
                let finalText = ((obj["final_text"] as? String)?.trimmed).flatMap { $0.isEmpty ? nil : $0 }
                let expected = textChanges.trimmed.isEmpty ? text : (finalText ?? text)
                let changesMissing = !textChanges.trimmed.isEmpty && (obj["changes_applied"] as? Bool) == false
                var warnings: [String] = []
                if !isClean { warnings.append("Possível sobra de marca: " + (found.isEmpty ? "verifique" : found.joined(separator: ", "))) }
                if changesMissing { warnings.append("Alteração de texto não aplicada no limpo (as variações vão aplicar): \(textChanges.trimmed)") }
                let warning = warnings.isEmpty ? nil : warnings.joined(separator: " · ")
                store.updateItem(jobID, itemID) {
                    $0.transcript = expected
                    $0.seenText = expected == text ? nil : text
                    $0.cleanWarning = warning
                    $0.analysisDone = true
                }
                if let warning { ctx.log(.warning, warning) }
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                // sem análise o lote continua; as variações só não terão o texto travado
                store.updateItem(jobID, itemID) {
                    $0.cleanWarning = "Não foi possível conferir a limpeza: \(error.localizedDescription)"
                    $0.analysisDone = true
                }
                ctx.log(.warning, "não foi possível conferir a limpeza (o lote continua). \(error.localizedDescription)",
                        details: error.aiDetails)
            }
        }

        // 3. VARIAÇÕES
        guard let ready = store.job(jobID)?.items.first(where: { $0.id == itemID }) else { return }
        let reference = await Task.detached(operation: { ImageTools.uploadJPEG(cleanedURL) }).value
        guard let reference else {
            AppLog.error(.variacao, "Não foi possível ler a imagem limpa para gerar as variações.", jobID: jobID, jobName: job.name, item: name)
            return
        }
        let aspect = Self.aspect(job.sizeMode, width: ready.pixelWidth, height: ready.pixelHeight)

        for v in ready.variations where v.status == .pending || v.status == .running {
            if Task.isCancelled { return }
            let varID = v.id
            store.updateVariation(jobID, itemID, varID) { $0.status = .running; $0.attempts += 1; $0.retryNote = nil; $0.retryAt = nil }
            let started = Date()
            let ctx = context(job, ready, step: "Variação v\(v.index) (\(v.axisName))", category: .variacao, attempts: attempts) { [weak self] note, until in
                Task { @MainActor in
                    self?.store.updateVariation(jobID, itemID, varID) {
                        guard $0.status == .running else { return }
                        $0.retryNote = note
                        $0.retryAt = until
                    }
                }
            }
            do {
                let axis = VariationAxis(name: v.axisName, instruction: v.axisInstruction)
                let prompt = Prompts.variation(axis: axis, transcript: ready.transcript, extra: extra, direction: direction,
                                               textChanges: textChanges, redoNote: v.redoNote)
                let primary = v.providerOverride ?? job.variationProvider
                let (result, used) = try await withFallback(primary, providers, rule: rule, ctx: ctx) {
                    try await $0.editImage(reference, prompt: prompt, aspectRatio: aspect)
                }
                let rel = "variacoes/\(Self.short(itemID))-v\(v.index)-\(Self.short(UUID())).png"
                Paths.ensure(folder.appendingPathComponent("variacoes", isDirectory: true))
                let out = folder.appendingPathComponent(rel)
                try ImageTools.saveGenerated(result, to: out)
                store.update(jobID) { $0.costUSD += self.settings.imagePrice(for: used) }
                store.updateVariation(jobID, itemID, varID) {
                    $0.file = rel
                    $0.status = .done
                    $0.error = nil
                    $0.errorKind = nil
                    $0.errorDetails = nil
                    $0.retryNote = nil
                    $0.retryAt = nil
                    $0.providerUsed = used
                }
                ctx.log(.success, "gerada com \(used.label) em \(Self.elapsed(started)).")

                // 4. CHECAGEM DO TEXTO
                if job.verifyText, let expected = ready.transcript, !expected.isEmpty,
                   let jpeg = await Task.detached(operation: { ImageTools.uploadJPEG(out) }).value {
                    var checkCtx = ctx
                    checkCtx.step = "Checagem de texto v\(v.index)"
                    checkCtx.category = .analise
                    checkCtx.onStatus = nil
                    do {
                        let prompt = Prompts.textCheck(expected: expected, removeItems: removeItems)
                        let (raw, _) = try await withFallback(job.analysisProvider, providers, rule: rule, ctx: checkCtx) {
                            try await $0.analyze(jpeg, prompt: prompt)
                        }
                        store.update(jobID) { $0.costUSD += self.settings.priceAnalysis }
                        let obj = JSONExtract.object(from: raw) ?? [:]
                        let match = (obj["match"] as? Bool) ?? true
                        let diff = (obj["differences"] as? String) ?? ""
                        let brand = (obj["brand_found"] as? [String]) ?? []
                        var warnings: [String] = []
                        if !match { warnings.append("Texto diferente: " + (diff.isEmpty ? "verifique" : diff)) }
                        if !brand.isEmpty { warnings.append("Marca apareceu: " + brand.joined(separator: ", ")) }
                        let joined = warnings.isEmpty ? nil : warnings.joined(separator: " · ")
                        store.updateVariation(jobID, itemID, varID) { $0.textWarning = joined }
                        if let joined { checkCtx.log(.warning, joined) }
                    } catch {
                        // checagem é auxiliar: falha aqui não derruba a variação
                        if !(error is CancellationError) {
                            checkCtx.log(.warning, "checagem não concluída (a variação foi mantida). \(error.localizedDescription)",
                                         details: error.aiDetails)
                        }
                    }
                }
            } catch is CancellationError {
                store.updateVariation(jobID, itemID, varID) { $0.status = .pending; $0.retryNote = nil; $0.retryAt = nil }
                return
            } catch {
                if Task.isCancelled {
                    store.updateVariation(jobID, itemID, varID) { $0.status = .pending; $0.retryNote = nil; $0.retryAt = nil }
                    return
                }
                store.updateVariation(jobID, itemID, varID) {
                    $0.status = .failed
                    $0.error = error.localizedDescription
                    $0.errorKind = error.aiKind
                    $0.errorDetails = error.aiDetails
                    $0.retryNote = nil
                    $0.retryAt = nil
                }
                ctx.log(.error, "falhou — \(error.aiKind.title). \(error.localizedDescription)",
                        details: [error.aiDetails, "Sugestão: \(error.aiKind.hint)"].compactMap { $0 }.joined(separator: "\n"))
            }
        }
    }

    static func short(_ id: UUID) -> String { String(id.uuidString.prefix(8)).lowercased() }

    static func elapsed(_ since: Date) -> String {
        let s = Date().timeIntervalSince(since)
        return s < 60 ? String(format: "%.0fs", s) : String(format: "%ldmin %02lds", Int(s) / 60, Int(s) % 60)
    }

    /// Proporção pedida à IA: a do tamanho de saída (4:5 ou 9:16), para a imagem já nascer vertical.
    /// Lotes antigos em "manter original" seguem a proporção de cada criativo.
    static func aspect(_ mode: OutputSizeMode, width: Int, height: Int) -> String {
        switch mode {
        case let .fixed(w, h): return ImageTools.nearestAspectRatio(width: w, height: h)
        case .original: return ImageTools.nearestAspectRatio(width: width, height: height)
        }
    }
}

/// Fila simples compartilhada entre os "trabalhadores" de um lote (tudo no MainActor).
@MainActor
final class WorkQueue {
    private var ids: [UUID]
    init(_ ids: [UUID]) { self.ids = ids.reversed() }
    func next() -> UUID? { ids.popLast() }
}
