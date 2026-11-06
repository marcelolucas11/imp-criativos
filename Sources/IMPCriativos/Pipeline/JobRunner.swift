import Foundation
import Combine

/// Executa os lotes: planejamento → limpeza → análise → variações → checagem de texto.
/// Cada passo é salvo em disco; pausar, fechar o app ou desligar o Mac não perde trabalho.
@MainActor
final class JobRunner: ObservableObject {
    @Published private(set) var running: Set<UUID> = []

    private let store: JobStore
    private let settings: AppSettings
    private var tasks: [UUID: Task<Void, Never>] = [:]
    /// 1.0.0-beta.8: imagens bloqueadas pelo filtro de conteúdo, por lote e por IA (disjuntor).
    private var imageBlocks: [UUID: [ProviderKind: Int]] = [:]
    /// 1.0.0-beta.8: até quando o modelo de planejamento de cada IA fica "em pausa" depois de um 503/429.
    private var plannerCooldown: [ProviderKind: Date] = [:]

    /// Depois de quantos bloqueios de imagem no mesmo lote a IA deixa de ser tentada nas próximas imagens dele.
    static let imageBlockLimit = 2
    /// Tentativas do modelo de planejamento quando há outra IA de reserva (em vez das 6 do lote).
    static let plannerQuickAttempts = 2
    /// Quanto tempo o modelo de planejamento sobrecarregado fica de lado.
    static let plannerCooldownSeconds: TimeInterval = 5 * 60

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
            item.autoCleanRedos = 0
            item.cleanSkipped = false
            item.forceClean = true
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
            v.autoRedos = 0
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
        var planners: [ProviderKind: AIProvider] = [:]
        let required = Set([job.cleanProvider, job.variationProvider, job.analysisProvider])
        for kind in ProviderKind.allCases {
            do {
                providers[kind] = try ProviderFactory.make(kind, config: config)
                planners[kind] = try ProviderFactory.makePlanner(kind, config: config)
            }
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

        imageBlocks[jobID] = [:]
        let workers = max(1, settings.maxConcurrent)
        let available = providers
        let availablePlanners = planners
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
                            await self?.process(jobID: jobID, itemID: id, providers: available, planners: availablePlanners,
                                                config: config, rule: rule, attempts: attempts)
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
    /// - imageOp: pedido de imagem (limpeza/variação). Conta bloqueios do filtro de conteúdo por lote; depois de
    ///   `imageBlockLimit` bloqueios da mesma IA, as próximas imagens do lote vão direto para a outra (1.0.0-beta.8).
    /// - explicit: o usuário escolheu esta IA para esta etapa ("refazer com…"); o disjuntor não interfere.
    private func withFallback<T>(_ primary: ProviderKind,
                                 _ providers: [ProviderKind: AIProvider],
                                 rule: FallbackRule,
                                 ctx: RequestContext,
                                 imageOp: Bool = false,
                                 explicit: Bool = false,
                                 _ op: (AIProvider) async throws -> T) async throws -> (T, ProviderKind) {
        let other: (ProviderKind) -> ProviderKind = { $0 == .gemini ? .openai : .gemini }
        let blockedRule = rule.applies(to: AIError("", kind: .blocked))
        var first = primary
        if imageOp, !explicit, blockedRule, providers[other(primary)] != nil, blockCount(ctx.jobID, primary) >= Self.imageBlockLimit {
            first = other(primary)
            ctx.onStatus?("Indo direto para \(first.label)…", nil)
        }
        guard let main = providers[first] else {
            throw AIError("Chave do \(first.label) não configurada. Vá em Configurações → Chaves de API.", kind: .auth)
        }
        var firstCtx = ctx
        if first != primary { firstCtx.step = ctx.step + " (\(first.label))" }
        do {
            let value = try await RequestContext.$current.withValue(firstCtx) { try await op(main) }
            return (value, first)
        } catch {
            if error is CancellationError || Task.isCancelled { throw error }
            if imageOp, error.aiKind == .blocked { registerBlock(first, ctx: ctx, canSwitch: blockedRule && providers[other(first)] != nil) }
            let alt = other(first)
            guard rule.applies(to: error), let backup = providers[alt] else { throw error }
            ctx.log(.warning, "\(first.label) falhou (\(error.aiKind.title)). Refazendo automaticamente com \(alt.label).",
                    details: error.aiDetails ?? error.localizedDescription)
            ctx.onStatus?("Trocando para \(alt.label)…", nil)
            var altCtx = ctx
            altCtx.step = ctx.step + " (\(alt.label))"
            let value = try await RequestContext.$current.withValue(altCtx) { try await op(backup) }
            return (value, alt)
        }
    }

    private func blockCount(_ jobID: UUID?, _ kind: ProviderKind) -> Int {
        guard let jobID else { return 0 }
        return imageBlocks[jobID]?[kind] ?? 0
    }

    /// Conta um bloqueio de imagem; ao atingir o limite, avisa uma vez no Histórico.
    private func registerBlock(_ kind: ProviderKind, ctx: RequestContext, canSwitch: Bool) {
        guard let jobID = ctx.jobID else { return }
        let n = (imageBlocks[jobID]?[kind] ?? 0) + 1
        imageBlocks[jobID, default: [:]][kind] = n
        guard n == Self.imageBlockLimit, canSwitch else { return }
        let alt: ProviderKind = kind == .gemini ? .openai : .gemini
        AppLog.warning(.lote, "\(kind.label) bloqueou \(n) imagens neste lote. As próximas imagens deste lote vão direto para \(alt.label).",
                       details: "Vale até o lote terminar ou ser pausado. \"Refazer com \(kind.label)\" continua disponível em cada imagem.",
                       jobID: jobID, jobName: ctx.jobName)
    }

    private func context(_ job: Job, _ item: JobItem, step: String, category: LogCategory, attempts: Int,
                         onStatus: (@Sendable (String?, Date?) -> Void)?) -> RequestContext {
        RequestContext(jobID: job.id, jobName: job.name, item: item.sourceName, step: step, category: category,
                       maxAttempts: attempts, onStatus: onStatus)
    }

    /// Quantas vezes o app refaz sozinho quando aparece termo proibido (limpeza e cada variação).
    static let autoRedoLimit = 1

    /// Faz o plano com o modelo de planejamento; se o modelo não for aceito, usa o de análise;
    /// se a IA falhar (e a troca automática estiver ligada), tenta a outra.
    /// 1.0.0-beta.8: com outra IA de reserva, desiste na 2ª falha temporária (503/429) em vez de esperar as 6
    /// tentativas, e deixa o modelo sobrecarregado de lado por 5 minutos (os próximos criativos já começam pela outra).
    /// Se as duas estiverem sobrecarregadas, o último recurso é o modelo de análise da IA principal.
    private func makePlan(_ jpeg: Data, prompt: String, primary: ProviderKind,
                          planners: [ProviderKind: AIProvider], providers: [ProviderKind: AIProvider],
                          config: ProviderConfig, rule: FallbackRule, ctx: RequestContext) async throws -> CreativePlan {
        let alt: ProviderKind = primary == .gemini ? .openai : .gemini
        let canSwitch = rule.enabled && planners[alt] != nil
        var order: [ProviderKind] = [primary] + (canSwitch ? [alt] : [])
        if canSwitch, let until = plannerCooldown[primary], until > Date() {
            order = [alt, primary]
            ctx.log(.info, "\(config.plannerModel(primary)) estava sobrecarregado há pouco; planejando com \(alt.label) (\(config.plannerModel(alt))).")
        }
        var lastError: Error = AIError("Nenhuma IA disponível para o planejamento.")
        for (i, kind) in order.enumerated() {
            guard let planner = planners[kind] else { continue }
            let model = config.plannerModel(kind)
            if i > 0 {
                ctx.log(.warning, "refazendo o planejamento com \(kind.label) (\(model)).", details: lastError.aiDetails ?? lastError.localizedDescription)
            }
            var attemptCtx = ctx
            if i < order.count - 1 { attemptCtx.maxAttempts = min(ctx.maxAttempts, Self.plannerQuickAttempts) }
            do {
                let raw = try await RequestContext.$current.withValue(attemptCtx) { try await planner.analyze(jpeg, prompt: prompt) }
                if let plan = CreativePlanner.parse(raw, model: model) { return plan }
                lastError = AIError("O planejamento do \(kind.label) veio fora do formato esperado.", details: String(raw.prefix(600)))
            } catch {
                if error is CancellationError || Task.isCancelled { throw error }
                lastError = error
                if error.aiKind == .temporary || error.aiKind == .rateLimit {
                    plannerCooldown[kind] = Date().addingTimeInterval(Self.plannerCooldownSeconds)
                    continue
                }
                guard error.aiKind == .model || error.aiKind == .badRequest, let basic = providers[kind] else { continue }
                let basicModel = kind == .gemini ? config.geminiTextModel : config.openaiTextModel
                ctx.log(.warning, "o modelo de planejamento \(model) não foi aceito; usando \(basicModel). Confira o nome em Configurações → Modelos de IA.",
                        details: error.aiDetails)
                do {
                    let raw = try await RequestContext.$current.withValue(ctx) { try await basic.analyze(jpeg, prompt: prompt) }
                    if let plan = CreativePlanner.parse(raw, model: basicModel) { return plan }
                    lastError = AIError("O planejamento veio fora do formato esperado.", details: String(raw.prefix(600)))
                } catch {
                    if error is CancellationError || Task.isCancelled { throw error }
                    lastError = error
                }
            }
        }
        // último recurso em sobrecarga: o modelo de análise da IA principal (mais leve, costuma ter folga)
        if lastError.aiKind.isTemporary, let basic = providers[primary] {
            let basicModel = primary == .gemini ? config.geminiTextModel : config.openaiTextModel
            ctx.log(.warning, "modelos de planejamento sobrecarregados; planejando com \(basicModel).", details: lastError.aiDetails)
            do {
                let raw = try await RequestContext.$current.withValue(ctx) { try await basic.analyze(jpeg, prompt: prompt) }
                if let plan = CreativePlanner.parse(raw, model: basicModel) { return plan }
                lastError = AIError("O planejamento veio fora do formato esperado.", details: String(raw.prefix(600)))
            } catch {
                if error is CancellationError || Task.isCancelled { throw error }
                lastError = error
            }
        }
        throw lastError
    }

    private static func joinNotes(_ a: String?, _ b: String?) -> String? {
        let parts = [a, b].compactMap { $0?.trimmed }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private func process(jobID: UUID, itemID: UUID, providers: [ProviderKind: AIProvider], planners: [ProviderKind: AIProvider],
                         config: ProviderConfig, rule: FallbackRule, attempts: Int) async {
        guard let job = store.job(jobID), let first = job.items.first(where: { $0.id == itemID }) else { return }
        let folder = store.folder(for: jobID)
        let removeItems = job.effectiveRemoveItems
        let extra = job.client.extraInstructions
        let textChanges = job.instructions?.textChanges ?? ""
        let direction = job.instructions?.direction ?? ""
        let name = first.sourceName

        // 0. PLANEJAMENTO: a IA mais forte lê o pedido e o criativo e escreve as instruções exatas
        if first.planDone != true && first.cleanStatus != .done {
            if settings.planningEnabled {
                store.updateItem(jobID, itemID) { $0.cleanStatus = .running; $0.cleanRetryNote = "Planejando o criativo…"; $0.cleanRetryAt = nil }
                let ctx = context(job, first, step: "Planejamento", category: .analise, attempts: attempts, onStatus: nil)
                let started = Date()
                do {
                    let src = folder.appendingPathComponent(first.originalFile)
                    guard let upload = await Task.detached(operation: { ImageTools.uploadJPEG(src) }).value else {
                        throw AIError("Não foi possível ler a imagem original.")
                    }
                    let prompt = CreativePlanner.prompt(removeItems: removeItems, extra: extra, instructions: job.instructions)
                    let plan = try await makePlan(upload, prompt: prompt, primary: job.analysisProvider, planners: planners,
                                                  providers: providers, config: config, rule: rule, ctx: ctx)
                    store.update(jobID) { $0.costUSD += self.settings.pricePlanning }
                    store.updateItem(jobID, itemID) { $0.plan = plan; $0.planDone = true; $0.cleanRetryNote = nil }
                    ctx.log(.info, "plano pronto em \(Self.elapsed(started)) · termos proibidos: "
                            + (plan.forbiddenTerms.isEmpty ? "nenhum" : plan.forbiddenTerms.joined(separator: ", ")),
                            details: CreativePlanner.summary(plan))
                } catch {
                    if error is CancellationError || Task.isCancelled {
                        store.updateItem(jobID, itemID) { $0.cleanStatus = .pending; $0.cleanRetryNote = nil }
                        return
                    }
                    store.updateItem(jobID, itemID) { $0.planDone = true; $0.plan = nil; $0.cleanRetryNote = nil }
                    ctx.log(.warning, "não foi possível planejar (o criativo segue com as instruções diretas). \(error.localizedDescription)",
                            details: error.aiDetails)
                }
            } else {
                store.updateItem(jobID, itemID) { $0.planDone = true }
            }
        }

        guard let item = store.job(jobID)?.items.first(where: { $0.id == itemID }) else { return }
        let plan = item.plan
        // termos do plano + palavras citadas nos itens de remoção (rede de segurança se o plano esquecer algum)
        let forbidden = ForbiddenTerms.dedup((plan?.forbiddenTerms ?? []) + ForbiddenTerms.fallback(from: removeItems))

        // 1a. NADA A REMOVER (1.0.0-beta.8): o plano disse que a imagem já está limpa → usa o original, sem custo.
        // A análise logo abaixo confere; se ela achar marca, a limpeza é feita normalmente.
        var cleanDone = item.cleanStatus == .done
        if !cleanDone, plan?.skipsCleaning == true, item.forceClean != true, (item.cleanRedoNote ?? "").trimmed.isEmpty {
            let src = folder.appendingPathComponent(item.originalFile)
            let rel = "limpos/\(Self.short(itemID))-original-\(Self.short(UUID())).png"
            Paths.ensure(folder.appendingPathComponent("limpos", isDirectory: true))
            let dst = folder.appendingPathComponent(rel)
            let ok = await Task.detached(operation: { ImageTools.copyAsPNG(src, to: dst) }).value
            if ok {
                store.updateItem(jobID, itemID) {
                    $0.cleanedFile = rel
                    $0.cleanStatus = .done
                    $0.cleanSkipped = true
                    $0.cleanProviderUsed = nil
                    $0.cleanRetryNote = nil
                    $0.cleanRetryAt = nil
                    $0.analysisDone = false
                }
                AppLog.success(.limpeza, "Limpeza: nada a remover segundo o plano; usando o original (sem custo).",
                               jobID: jobID, jobName: job.name, item: name)
                cleanDone = true
            }
        }

        // 1. LIMPEZA
        if !cleanDone {
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
                let prompt: String
                if let plan {
                    var p = plan
                    p.forbiddenTerms = forbidden
                    prompt = Prompts.cleanFromPlan(p, extra: extra, redoNote: item.cleanRedoNote)
                } else {
                    prompt = Prompts.clean(removeItems: removeItems, extra: extra, textChanges: textChanges,
                                           forbidden: forbidden, redoNote: item.cleanRedoNote)
                }
                let primary = item.cleanProviderOverride ?? job.cleanProvider
                let (result, used) = try await withFallback(primary, providers, rule: rule, ctx: ctx,
                                                            imageOp: true, explicit: item.cleanProviderOverride != nil) {
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
                    $0.cleanSkipped = false
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

        // 2. ANÁLISE: checa sobras (IA + leitura do próprio Mac) e define o texto travado das variações
        guard let cleaned = store.job(jobID)?.items.first(where: { $0.id == itemID }),
              let cleanedRel = cleaned.cleanedFile else { return }
        let cleanedURL = folder.appendingPathComponent(cleanedRel)
        if !cleaned.analysisDone {
            let ctx = context(job, cleaned, step: "Análise", category: .analise, attempts: attempts, onStatus: nil)
            let ocr = await Task.detached(operation: { LocalOCR.text(at: cleanedURL) }).value ?? ""
            var aiText = ""
            var aiWarnings: [String] = []
            var aiFinalText: String?
            var changesMissing = false
            var analysisFailed: String?
            do {
                guard let jpeg = await Task.detached(operation: { ImageTools.uploadJPEG(cleanedURL) }).value else {
                    throw AIError("Não foi possível ler a imagem limpa.")
                }
                // com plano, o texto final já está decidido; a análise só confere e transcreve
                let changesForAI = plan == nil ? textChanges : ""
                let prompt = Prompts.analysis(removeItems: removeItems, textChanges: changesForAI, forbidden: forbidden)
                let (raw, _) = try await withFallback(job.analysisProvider, providers, rule: rule, ctx: ctx) {
                    try await $0.analyze(jpeg, prompt: prompt)
                }
                store.update(jobID) { $0.costUSD += self.settings.priceAnalysis }
                let obj = JSONExtract.object(from: raw) ?? [:]
                let isClean = (obj["clean"] as? Bool) ?? true
                let found = (obj["found"] as? [String]) ?? []
                aiText = (obj["text"] as? String) ?? ""
                aiFinalText = ((obj["final_text"] as? String)?.trimmed).flatMap { $0.isEmpty ? nil : $0 }
                changesMissing = !changesForAI.trimmed.isEmpty && (obj["changes_applied"] as? Bool) == false
                if !isClean { aiWarnings.append("Possível sobra de marca: " + (found.isEmpty ? "verifique" : found.joined(separator: ", "))) }
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                analysisFailed = error.localizedDescription
                ctx.log(.warning, "a IA não conseguiu conferir a limpeza (segue com a leitura do Mac). \(error.localizedDescription)",
                        details: error.aiDetails)
            }

            // Conferência por código: termo proibido lido pela IA ou pelo OCR do Mac → refaz sozinho uma vez
            let leftovers = ForbiddenTerms.found(in: aiText + "\n" + ocr, terms: forbidden)

            // 1.0.0-beta.8: a limpeza foi pulada, mas a checagem achou marca → faz a limpeza de verdade
            if cleaned.cleanSkipped == true && (!leftovers.isEmpty || !aiWarnings.isEmpty) {
                let found = (leftovers.isEmpty ? [] : ["termos: " + leftovers.joined(separator: ", ")]) + aiWarnings
                store.updateItem(jobID, itemID) {
                    $0.cleanSkipped = false
                    $0.forceClean = true
                    $0.cleanStatus = .pending
                    $0.analysisDone = false
                }
                ctx.log(.warning, "o plano dizia que não havia nada a remover, mas a checagem encontrou marca. Fazendo a limpeza.",
                        details: found.joined(separator: "\n"))
                return
            }
            if !leftovers.isEmpty && (cleaned.autoCleanRedos ?? 0) < Self.autoRedoLimit {
                let note = "Ainda aparece: \(leftovers.joined(separator: ", ")). Apague esses termos de TODA a imagem, inclusive do título, das telas e das miniaturas, reescrevendo a frase só o necessário."
                store.updateItem(jobID, itemID) {
                    $0.autoCleanRedos = ($0.autoCleanRedos ?? 0) + 1
                    $0.cleanRedoNote = Self.joinNotes($0.cleanRedoNote, note)
                    $0.cleanStatus = .pending
                    $0.analysisDone = false
                }
                ctx.log(.warning, "termo proibido ainda aparece no limpo (\(leftovers.joined(separator: ", "))). Refazendo a limpeza automaticamente.",
                        details: "Leitura da IA:\n\(aiText)\n\nLeitura do Mac:\n\(ocr)")
                return
            }

            // texto travado das variações: o final do plano; sem plano, o que a análise viu (com as alterações pedidas)
            var expected: String
            if let final = plan?.finalText, !final.isEmpty {
                expected = final
            } else {
                let seen = aiText.trimmed.isEmpty ? ocr : aiText
                expected = textChanges.trimmed.isEmpty ? seen : (aiFinalText ?? seen)
            }
            if !ForbiddenTerms.found(in: expected, terms: forbidden).isEmpty {
                expected = ForbiddenTerms.strip(forbidden, from: expected)
            }

            var warnings = aiWarnings
            if !leftovers.isEmpty {
                warnings.append("Termo proibido no limpo mesmo após refazer: \(leftovers.joined(separator: ", ")) (as variações foram instruídas a não escrever)")
            }
            if changesMissing { warnings.append("Alteração de texto não aplicada no limpo (as variações vão aplicar): \(textChanges.trimmed)") }
            if let analysisFailed, leftovers.isEmpty { warnings.append("Não foi possível conferir a limpeza com a IA: \(analysisFailed)") }
            let warning = warnings.isEmpty ? nil : warnings.joined(separator: " · ")
            let seenText: String? = aiText.trimmed.isEmpty ? nil : aiText
            let finalExpected = expected
            store.updateItem(jobID, itemID) {
                $0.transcript = finalExpected.trimmed.isEmpty ? nil : finalExpected
                $0.seenText = seenText == finalExpected ? nil : seenText
                $0.cleanWarning = warning
                $0.analysisDone = true
            }
            if let warning { ctx.log(.warning, warning) }
        }

        // 3. VARIAÇÕES
        guard let ready = store.job(jobID)?.items.first(where: { $0.id == itemID }) else { return }
        let reference = await Task.detached(operation: { ImageTools.uploadJPEG(cleanedURL) }).value
        guard let reference else {
            AppLog.error(.variacao, "Não foi possível ler a imagem limpa para gerar as variações.", jobID: jobID, jobName: job.name, item: name)
            return
        }
        let aspect = Self.aspect(job.sizeMode, width: ready.pixelWidth, height: ready.pixelHeight)
        let rules = plan?.variationRules ?? ""

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
                let primary = v.providerOverride ?? job.variationProvider
                var autoNote: String?
                var redosUsed = v.autoRedos ?? 0
                var out = cleanedURL
                var ocrLeftovers: [String] = []
                var used = primary

                while true {
                    let prompt = Prompts.variation(axis: axis, transcript: ready.transcript, extra: extra, direction: direction,
                                                   textChanges: textChanges, forbidden: forbidden, rules: rules,
                                                   redoNote: Self.joinNotes(v.redoNote, autoNote))
                    let (result, provider) = try await withFallback(primary, providers, rule: rule, ctx: ctx,
                                                                    imageOp: true, explicit: v.providerOverride != nil) {
                        try await $0.editImage(reference, prompt: prompt, aspectRatio: aspect)
                    }
                    used = provider
                    let rel = "variacoes/\(Self.short(itemID))-v\(v.index)-\(Self.short(UUID())).png"
                    Paths.ensure(folder.appendingPathComponent("variacoes", isDirectory: true))
                    out = folder.appendingPathComponent(rel)
                    try ImageTools.saveGenerated(result, to: out)
                    store.update(jobID) { $0.costUSD += self.settings.imagePrice(for: provider) }
                    store.updateVariation(jobID, itemID, varID) { $0.file = rel }

                    // leitura do próprio Mac: termo proibido → refaz sozinho uma vez
                    let target = out
                    let ocr = await Task.detached(operation: { LocalOCR.text(at: target) }).value ?? ""
                    ocrLeftovers = ForbiddenTerms.found(in: ocr, terms: forbidden)
                    guard !ocrLeftovers.isEmpty, redosUsed < Self.autoRedoLimit, !Task.isCancelled else { break }
                    redosUsed += 1
                    let redos = redosUsed
                    store.updateVariation(jobID, itemID, varID) { $0.autoRedos = redos }
                    autoNote = "Apareceu: \(ocrLeftovers.joined(separator: ", ")). Não escreva esses termos em nenhum lugar da imagem."
                    ctx.log(.warning, "termo proibido apareceu (\(ocrLeftovers.joined(separator: ", "))). Refazendo automaticamente.",
                            details: "Leitura do Mac:\n\(ocr)")
                    ctx.onStatus?("Refazendo: termo proibido apareceu…", nil)
                }

                store.updateVariation(jobID, itemID, varID) {
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
                var warnings: [String] = []
                if !ocrLeftovers.isEmpty { warnings.append("Termo proibido: " + ocrLeftovers.joined(separator: ", ")) }
                let finalOut = out
                if job.verifyText, let jpeg = await Task.detached(operation: { ImageTools.uploadJPEG(finalOut) }).value,
                   (ready.transcript?.isEmpty == false || !forbidden.isEmpty) {
                    var checkCtx = ctx
                    checkCtx.step = "Checagem de texto v\(v.index)"
                    checkCtx.category = .analise
                    checkCtx.onStatus = nil
                    do {
                        let prompt = Prompts.textCheck(expected: ready.transcript ?? "(no text)", removeItems: removeItems, forbidden: forbidden)
                        let (raw, _) = try await withFallback(job.analysisProvider, providers, rule: rule, ctx: checkCtx) {
                            try await $0.analyze(jpeg, prompt: prompt)
                        }
                        store.update(jobID) { $0.costUSD += self.settings.priceAnalysis }
                        let obj = JSONExtract.object(from: raw) ?? [:]
                        let match = (obj["match"] as? Bool) ?? true
                        let diff = (obj["differences"] as? String) ?? ""
                        let brand = (obj["brand_found"] as? [String]) ?? []
                        if !match && ready.transcript?.isEmpty == false { warnings.append("Texto diferente: " + (diff.isEmpty ? "verifique" : diff)) }
                        if !brand.isEmpty { warnings.append("Marca apareceu: " + brand.joined(separator: ", ")) }
                    } catch {
                        // checagem é auxiliar: falha aqui não derruba a variação
                        if !(error is CancellationError) {
                            checkCtx.log(.warning, "checagem não concluída (a variação foi mantida). \(error.localizedDescription)",
                                         details: error.aiDetails)
                        }
                    }
                }
                let joined = warnings.isEmpty ? nil : warnings.joined(separator: " · ")
                store.updateVariation(jobID, itemID, varID) { $0.textWarning = joined }
                if let joined { ctx.log(.warning, joined) }
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
