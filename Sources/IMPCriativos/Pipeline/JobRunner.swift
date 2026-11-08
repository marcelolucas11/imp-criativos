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
    private var imageBlocks: [UUID: [ModelChoice: Int]] = [:]
    /// 1.0.0-beta.8: até quando o modelo de planejamento de cada IA fica "em pausa" depois de um 503/429.
    private var plannerCooldown: [ModelChoice: Date] = [:]

    /// Depois de quantos bloqueios de imagem no mesmo lote a IA deixa de ser tentada nas próximas imagens dele.
    static let imageBlockLimit = 2
    /// Tentativas do modelo de planejamento quando há outra IA de reserva (em vez das 6 do lote).
    static let plannerQuickAttempts = 2
    /// Quanto tempo o modelo de planejamento sobrecarregado fica de lado.
    static let plannerCooldownSeconds: TimeInterval = 5 * 60
    /// 1.0.0-beta.9: até quando o modelo de análise de cada IA fica de lado depois de travar (tempo esgotado, 503, 429).
    private var analysisCooldown: [ModelChoice: Date] = [:]
    /// Tentativas da análise/checagem na IA principal quando há outra de reserva (em vez das 6 do lote).
    static let analysisQuickAttempts = 2
    /// Tentativas da análise/checagem na IA de reserva (a checagem é auxiliar; não vale esperar muito).
    static let analysisBackupAttempts = 3
    /// Quanto tempo o modelo de análise que travou fica de lado.
    static let analysisCooldownSeconds: TimeInterval = 5 * 60

    /// 1.0.0-beta.19: vigia de travamento. Último avanço de cada lote (etapas concluídas e quando).
    private var progressMark: [UUID: (steps: Int, at: Date)] = [:]
    /// Lote sem nenhuma etapa concluída por este tempo = sinal de travamento (a velocidade volta à original).
    static let stallSeconds: TimeInterval = 12 * 60
    /// De quanto em quanto tempo o vigia confere o lote e o Mac.
    static let watchInterval: UInt64 = 30

    init(store: JobStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
    }

    var hasActiveWork: Bool { !running.isEmpty }

    /// Regras de troca automática de IA, lidas das Configurações quando o lote começa.
    struct FallbackRule {
        var enabled: Bool
        var onBlocked: Bool

        /// 1.0.0-beta.11: com uma reserva escolhida por etapa, qualquer erro troca para ela
        /// (modelo inexistente, chave, pedido recusado…); bloqueio de conteúdo só se a opção estiver ligada.
        func applies(to error: Error) -> Bool {
            guard enabled else { return false }
            return error.aiKind == .blocked ? onBlocked : true
        }
    }

    // MARK: controle

    func start(_ jobID: UUID) {
        guard tasks[jobID] == nil, let job = store.job(jobID), job.state != .cancelled else { return }
        let wasStarted = job.finishedSteps > 0
        store.update(jobID) { $0.state = .running; $0.lastError = nil }
        AppLog.info(.lote, wasStarted ? "Lote retomado." : "Lote iniciado.",
                    details: """
                    \(job.items.count) criativos · \(job.variationsPerItem) variações cada\(job.isAxisTest ? " (teste de eixos: todos os eixos do cliente)" : "") · saída \(job.sizeMode.label) \(job.format.label)
                    IA do lote — limpeza: \(job.cleanProvider.label) · variações: \(job.variationProvider.label) · análise: \(job.analysisProvider.label)
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
        await ProviderGate.configure(imageLimit: settings.maxImageRequests, fastCeiling: settings.fastImageCeiling,
                                     fast: settings.fastMode)
        await ProviderGate.setMacHold(SpeedMonitor.macRisk())
        await SpeedMonitor.shared.refresh()

        // as plataformas escolhidas no lote são obrigatórias; a reserva de cada etapa só entra se tiver chave
        let required = [job.cleanProvider, job.variationProvider, job.analysisProvider]
        if let missing = required.first(where: { !APIKeyStore.hasKey($0) }) {
            let msg = "Chave do \(missing.label) não configurada. Vá em Configurações → Chaves de API."
            store.update(jobID) { $0.state = .paused; $0.lastError = msg }
            AppLog.error(.lote, "Lote pausado: \(msg)", jobID: jobID, jobName: job.name)
            return
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
        progressMark[jobID] = (store.job(jobID)?.finishedSteps ?? 0, Date())
        // 1.0.0-beta.19: vigia do lote — Mac sob pressão ou lote parado devolvem a velocidade original
        let watchdog = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.watchInterval * 1_000_000_000)
                guard !Task.isCancelled, let self else { return }
                await self.watch(jobID)
            }
        }
        defer {
            watchdog.cancel()
            progressMark[jobID] = nil
        }
        let workers = max(1, settings.maxConcurrent)
        let rule = FallbackRule(enabled: settings.fallbackEnabled, onBlocked: settings.fallbackOnBlocked)
        let attempts = max(1, settings.retryAttempts)

        // repete enquanto aparecer trabalho novo (ex.: "refazer" clicado durante o lote)
        while !Task.isCancelled {
            // integridade: o que está "pronto" sem a imagem no disco volta para a fila antes de cada rodada
            let repaired = store.repairMissingFiles(jobID)
            if repaired > 0, let j = store.job(jobID) {
                AppLog.warning(.lote, "Integridade: \(repaired) imagem(ns) prontas não estavam no disco e voltaram para a fila.",
                               jobID: jobID, jobName: j.name)
            }
            guard let current = store.job(jobID) else { return }
            let pending = current.items.filter { needsWork($0) }.map(\.id)
            if pending.isEmpty { break }
            let queue = WorkQueue(pending)

            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<min(workers, pending.count) {
                    group.addTask { @MainActor [weak self] in
                        while !Task.isCancelled, let id = queue.next() {
                            await self?.process(jobID: jobID, itemID: id, config: config, rule: rule, attempts: attempts)
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

    /// 1.0.0-beta.19: vigia do lote, a cada 30 s enquanto ele roda.
    /// - Mac quente, em pouca energia ou com pouco disco → filas de imagem na velocidade original.
    /// - Nenhuma etapa concluída em 12 minutos → trata como travamento: velocidade original e modo seguro.
    /// Não cancela nada; só segura os próximos pedidos.
    private func watch(_ jobID: UUID) async {
        await ProviderGate.setMacHold(SpeedMonitor.macRisk())
        guard let job = store.job(jobID), job.state == .running else { return }
        let steps = job.finishedSteps
        let now = Date()
        guard let mark = progressMark[jobID], mark.steps == steps else {
            progressMark[jobID] = (steps, now)
            return
        }
        guard now.timeIntervalSince(mark.at) >= Self.stallSeconds else { return }
        progressMark[jobID] = (steps, now)
        let minutes = Int(Self.stallSeconds / 60)
        AppLog.warning(.lote, "Segurança: o lote está há \(minutes) minutos sem concluir nenhuma etapa. A velocidade voltou para a original.",
                       details: "Os pedidos em andamento continuam (cada um tem tempo limite). Se nada mudar, pause e retome o lote ou veja os erros em Histórico.",
                       jobID: jobID, jobName: job.name)
        await ProviderGate.reportStall("lote sem avanço há \(minutes) minutos")
    }

    /// 1.0.0-beta.19 — integridade: a resposta da IA precisa ser uma imagem que o Mac consegue abrir.
    /// Se não for, conta como falha temporária (a etapa é refeita com a reserva, se houver).
    nonisolated static func validImage(_ data: Data) throws -> Data {
        guard ImageTools.cgImage(from: data) != nil else {
            throw AIError("A IA devolveu um arquivo que não é uma imagem válida.", kind: .temporary,
                          details: "\(data.count) bytes recebidos")
        }
        return data
    }

    /// 1.0.0-beta.19 — integridade: a imagem gravada precisa existir e abrir.
    nonisolated static func verifySaved(_ url: URL) throws {
        guard ImageTools.pixelSize(of: url) != nil else {
            throw AIError("A imagem não foi gravada corretamente no disco.", kind: .other, details: url.path)
        }
    }

    /// Chama a IA principal da etapa; se falhar (e a troca automática estiver ligada) e a reserva tiver chave, refaz com ela.
    /// `chain`: principal e reserva da etapa (ProviderConfig.chain).
    /// - imageOp: pedido de imagem (limpeza/variação). Conta bloqueios do filtro de conteúdo por lote; depois de
    ///   `imageBlockLimit` bloqueios do mesmo modelo, as próximas imagens do lote vão direto para a reserva (1.0.0-beta.8).
    /// - explicit: o usuário escolheu esta IA para esta etapa ("refazer com…"); o disjuntor não interfere.
    /// - quickSwitch: análise/checagem (1.0.0-beta.9). Com reserva, desiste na 2ª falha temporária
    ///   (tempo esgotado, 503, 429) em vez das 6 tentativas, e deixa o modelo que travou de lado por 5 minutos.
    private func withFallback<T>(_ chain: [ModelChoice],
                                 config: ProviderConfig,
                                 rule: FallbackRule,
                                 ctx: RequestContext,
                                 imageOp: Bool = false,
                                 explicit: Bool = false,
                                 quickSwitch: Bool = false,
                                 _ op: (AIProvider) async throws -> T) async throws -> (T, ModelChoice) {
        guard let primary = chain.first else { throw AIError("Nenhuma IA configurada para esta etapa.") }
        let reserve: ModelChoice? = chain.dropFirst().first { APIKeyStore.hasKey($0.provider) }
        let other: (ModelChoice) -> ModelChoice? = { c in
            guard let reserve else { return nil }
            return c == primary ? reserve : primary
        }
        let blockedRule = rule.applies(to: AIError("", kind: .blocked))
        var first = primary
        if imageOp, !explicit, blockedRule, let r = reserve, blockCount(ctx.jobID, primary) >= Self.imageBlockLimit {
            first = r
            ctx.onStatus?("Indo direto para \(r.provider.label)…", nil)
        }
        let canQuickSwitch = quickSwitch && rule.enabled && reserve != nil
        if canQuickSwitch, let r = reserve, let until = analysisCooldown[primary], until > Date() {
            first = r
        }
        var firstCtx = ctx
        if first != primary { firstCtx.step = ctx.step + " (\(first.label))" }
        if canQuickSwitch { firstCtx.maxAttempts = min(ctx.maxAttempts, Self.analysisQuickAttempts) }
        do {
            let main = try ProviderFactory.make(first, config: config)
            let value = try await RequestContext.$current.withValue(firstCtx) { try await op(main) }
            return (value, first)
        } catch {
            if error is CancellationError || Task.isCancelled { throw error }
            if imageOp, error.aiKind == .blocked { registerBlock(first, reserve: other(first), ctx: ctx, canSwitch: blockedRule) }
            guard rule.applies(to: error), let alt = other(first), let backup = try? ProviderFactory.make(alt, config: config) else { throw error }
            var cooldownNote = ""
            if canQuickSwitch, error.aiKind.isTemporary {
                let wasCooling = (analysisCooldown[first] ?? .distantPast) > Date()
                analysisCooldown[first] = Date().addingTimeInterval(Self.analysisCooldownSeconds)
                if !wasCooling && first == primary {
                    cooldownNote = " Nos próximos \(Int(Self.analysisCooldownSeconds / 60)) minutos, as análises e checagens vão direto para \(alt.label)."
                }
            }
            ctx.log(.warning, "\(first.label) falhou (\(error.aiKind.title)). Refazendo automaticamente com a reserva \(alt.label).\(cooldownNote)",
                    details: error.aiDetails ?? error.localizedDescription)
            ctx.onStatus?("Trocando para \(alt.provider.label)…", nil)
            var altCtx = ctx
            altCtx.step = ctx.step + " (\(alt.label))"
            if canQuickSwitch { altCtx.maxAttempts = min(ctx.maxAttempts, Self.analysisBackupAttempts) }
            let value = try await RequestContext.$current.withValue(altCtx) { try await op(backup) }
            return (value, alt)
        }
    }

    private func blockCount(_ jobID: UUID?, _ choice: ModelChoice) -> Int {
        guard let jobID else { return 0 }
        return imageBlocks[jobID]?[choice] ?? 0
    }

    /// Conta um bloqueio de imagem; ao atingir o limite, avisa uma vez no Histórico.
    private func registerBlock(_ choice: ModelChoice, reserve: ModelChoice?, ctx: RequestContext, canSwitch: Bool) {
        guard let jobID = ctx.jobID else { return }
        let n = (imageBlocks[jobID]?[choice] ?? 0) + 1
        imageBlocks[jobID, default: [:]][choice] = n
        guard n == Self.imageBlockLimit, canSwitch, let reserve else { return }
        AppLog.warning(.lote, "\(choice.label) bloqueou \(n) imagens neste lote. As próximas imagens deste lote vão direto para \(reserve.label).",
                       details: "Vale até o lote terminar ou ser pausado. \"Refazer com \(choice.provider.label)\" continua disponível em cada imagem.",
                       jobID: jobID, jobName: ctx.jobName)
    }

    /// 1.0.0-beta.9: o tempo máximo de cada tentativa sai da etapa (análise 90s, imagem 5 min; o planejamento passa 4 min).
    private func context(_ job: Job, _ item: JobItem, step: String, category: LogCategory, attempts: Int,
                         timeout: TimeInterval? = nil,
                         onStatus: (@Sendable (String?, Date?) -> Void)?) -> RequestContext {
        RequestContext(jobID: job.id, jobName: job.name, item: item.sourceName, step: step, category: category,
                       maxAttempts: attempts,
                       timeout: timeout ?? (category == .analise ? HTTP.analysisTimeout : HTTP.imageTimeout),
                       onStatus: onStatus)
    }

    /// Quantas vezes o app refaz sozinho quando aparece termo proibido (limpeza e cada variação).
    static let autoRedoLimit = 1

    /// Faz o plano com a IA de planejamento escolhida; se falhar (e a troca automática estiver ligada), tenta a reserva.
    /// 1.0.0-beta.8: com reserva, desiste na 2ª falha temporária (503/429) em vez de esperar as 6 tentativas,
    /// e deixa o modelo sobrecarregado de lado por 5 minutos (os próximos criativos já começam pela reserva).
    /// Último recurso: a IA principal da análise (mais leve, costuma ter folga).
    private func makePlan(_ jpeg: Data, prompt: String, config: ProviderConfig, rule: FallbackRule,
                          ctx: RequestContext) async throws -> CreativePlan {
        let chain = config.chain(.planning).filter { APIKeyStore.hasKey($0.provider) }
        var order = rule.enabled ? chain : Array(chain.prefix(1))
        if order.count > 1, let until = plannerCooldown[order[0]], until > Date() {
            order.swapAt(0, 1)
            ctx.log(.info, "\(order[1].label) estava sobrecarregado há pouco; planejando com \(order[0].label).")
        }
        if let basic = config.chain(.analysis).first(where: { APIKeyStore.hasKey($0.provider) }),
           !order.contains(basic), rule.enabled || order.isEmpty {
            order.append(basic)
        }
        var lastError: Error = AIError("Nenhuma IA com chave configurada para o planejamento.", kind: .auth)
        for (i, choice) in order.enumerated() {
            if i > 0 {
                ctx.log(.warning, "refazendo o planejamento com \(choice.label).", details: lastError.aiDetails ?? lastError.localizedDescription)
            }
            var attemptCtx = ctx
            if i < order.count - 1 { attemptCtx.maxAttempts = min(ctx.maxAttempts, Self.plannerQuickAttempts) }
            do {
                let planner = try ProviderFactory.make(choice, config: config)
                let raw = try await RequestContext.$current.withValue(attemptCtx) { try await planner.analyze(jpeg, prompt: prompt) }
                if let plan = CreativePlanner.parse(raw, model: choice.model) { return plan }
                lastError = AIError("O planejamento do \(choice.label) veio fora do formato esperado.", details: String(raw.prefix(600)))
            } catch {
                if error is CancellationError || Task.isCancelled { throw error }
                lastError = error
                if error.aiKind == .temporary || error.aiKind == .rateLimit {
                    plannerCooldown[choice] = Date().addingTimeInterval(Self.plannerCooldownSeconds)
                } else if error.aiKind == .model || error.aiKind == .badRequest {
                    ctx.log(.warning, "o modelo \(choice.label) não foi aceito. Confira em Configurações → Modelos de IA.",
                            details: error.aiDetails)
                }
            }
        }
        throw lastError
    }

    private static func joinNotes(_ a: String?, _ b: String?) -> String? {
        let parts = [a, b].compactMap { $0?.trimmed }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private func process(jobID: UUID, itemID: UUID, config: ProviderConfig, rule: FallbackRule, attempts: Int) async {
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
                let ctx = context(job, first, step: "Planejamento", category: .analise, attempts: attempts,
                                  timeout: HTTP.plannerTimeout, onStatus: nil)
                let started = Date()
                do {
                    let src = folder.appendingPathComponent(first.originalFile)
                    guard let upload = await Task.detached(operation: { ImageTools.uploadJPEG(src) }).value else {
                        throw AIError("Não foi possível ler a imagem original.")
                    }
                    let prompt = CreativePlanner.prompt(removeItems: removeItems, extra: extra, instructions: job.instructions)
                    let plan = try await makePlan(upload, prompt: prompt, config: config, rule: rule, ctx: ctx)
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
                let chain = config.chain(.clean, prefer: item.cleanProviderOverride ?? job.cleanProvider)
                let (result, usedModel) = try await withFallback(chain, config: config, rule: rule, ctx: ctx,
                                                                 imageOp: true, explicit: item.cleanProviderOverride != nil) {
                    (provider: AIProvider) async throws -> Data in
                    let data = try await provider.editImage(upload, prompt: prompt, aspectRatio: aspect)
                    return try Self.validImage(data)
                }
                let rel = "limpos/\(Self.short(itemID))-\(Self.short(UUID())).png"
                Paths.ensure(folder.appendingPathComponent("limpos", isDirectory: true))
                try ImageTools.saveGenerated(result, to: folder.appendingPathComponent(rel))
                try Self.verifySaved(folder.appendingPathComponent(rel))
                let used = usedModel.provider
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
                ctx.log(.success, "concluída com \(usedModel.label) em \(Self.elapsed(started)).")
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
                let (raw, _) = try await withFallback(config.chain(.analysis, prefer: job.analysisProvider), config: config,
                                                      rule: rule, ctx: ctx, quickSwitch: true) {
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

        // 3. VARIAÇÕES — 1.0.0-beta.19: saem juntas, até o limite da fila de imagem da IA
        // (o Modo rápido com segurança ajusta esse limite). Antes saíam uma de cada vez por criativo.
        guard let ready = store.job(jobID)?.items.first(where: { $0.id == itemID }) else { return }
        let reference = await Task.detached(operation: { ImageTools.uploadJPEG(cleanedURL) }).value
        guard let reference else {
            AppLog.error(.variacao, "Não foi possível ler a imagem limpa para gerar as variações.", jobID: jobID, jobName: job.name, item: name)
            return
        }
        let setup = VariationSetup(job: job, item: ready, folder: folder, reference: reference,
                                   aspect: Self.aspect(job.sizeMode, width: ready.pixelWidth, height: ready.pixelHeight),
                                   rules: plan?.variationRules ?? "", forbidden: forbidden, extra: extra,
                                   direction: direction, textChanges: textChanges,
                                   config: config, rule: rule, attempts: attempts)
        let pendingVars = ready.variations.filter { $0.status == .pending || $0.status == .running }
        let gate = ProviderGate.image(job.variationProvider)
        let analysisChain = config.chain(.analysis, prefer: job.analysisProvider)

        await BoundedParallel.run(
            pendingVars,
            limit: { await gate.currentLimit() },
            work: { [weak self] v in await self?.generateVariation(v, setup) },
            followUp: { [weak self] check in
                // 4. CHECAGEM DO TEXTO — roda junto com as próximas variações, sem ocupar vaga de imagem.
                // O criativo só termina quando todas as checagens terminam.
                await self?.checkText(jobID: jobID, itemID: itemID, varID: check.varID, index: check.index, file: check.file,
                                      transcript: ready.transcript, removeItems: removeItems, forbidden: forbidden,
                                      ocrLeftovers: check.leftovers, verify: job.verifyText,
                                      analysisChain: analysisChain, config: config, rule: rule, ctx: check.ctx)
            })
    }

    /// Tudo que as variações de um criativo têm em comum.
    struct VariationSetup {
        let job: Job
        let item: JobItem
        let folder: URL
        let reference: Data
        let aspect: String
        let rules: String
        let forbidden: [String]
        let extra: String
        let direction: String
        let textChanges: String
        let config: ProviderConfig
        let rule: FallbackRule
        let attempts: Int
    }

    /// Variação pronta, esperando a checagem do texto.
    struct PendingCheck: Sendable {
        let varID: UUID
        let index: Int
        let file: URL
        let leftovers: [String]
        let ctx: RequestContext
    }

    /// Gera uma variação (com a refação automática por termo proibido). Devolve a checagem a fazer,
    /// ou nil se falhou ou foi pausada.
    private func generateVariation(_ v: Variation, _ s: VariationSetup) async -> PendingCheck? {
        let job = s.job
        let jobID = job.id
        let itemID = s.item.id
        let varID = v.id
        if Task.isCancelled { return nil }
        store.updateVariation(jobID, itemID, varID) { $0.status = .running; $0.attempts += 1; $0.retryNote = nil; $0.retryAt = nil }
        let started = Date()
        let ctx = context(job, s.item, step: "Variação v\(v.index) (\(v.axisName))", category: .variacao, attempts: s.attempts) { [weak self] note, until in
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
            let chain = s.config.chain(.variation, prefer: v.providerOverride ?? job.variationProvider)
            var autoNote: String?
            var redosUsed = v.autoRedos ?? 0
            var ocrLeftovers: [String] = []
            var out: URL = s.folder
            var used = chain.first?.provider ?? job.variationProvider
            var usedLabel = chain.first?.label ?? used.label
            let reference = s.reference
            let aspect = s.aspect

            while true {
                let prompt = Prompts.variation(axis: axis, transcript: s.item.transcript, extra: s.extra, direction: s.direction,
                                               textChanges: s.textChanges, forbidden: s.forbidden, rules: s.rules,
                                               redoNote: Self.joinNotes(v.redoNote, autoNote))
                let (result, usedModel) = try await withFallback(chain, config: s.config, rule: s.rule, ctx: ctx,
                                                                 imageOp: true, explicit: v.providerOverride != nil) {
                    (provider: AIProvider) async throws -> Data in
                    let data = try await provider.editImage(reference, prompt: prompt, aspectRatio: aspect)
                    return try Self.validImage(data)
                }
                let provider = usedModel.provider
                used = provider
                usedLabel = usedModel.label
                let rel = "variacoes/\(Self.short(itemID))-v\(v.index)-\(Self.short(UUID())).png"
                Paths.ensure(s.folder.appendingPathComponent("variacoes", isDirectory: true))
                out = s.folder.appendingPathComponent(rel)
                try ImageTools.saveGenerated(result, to: out)
                try Self.verifySaved(out)
                store.update(jobID) { $0.costUSD += self.settings.imagePrice(for: provider) }
                store.updateVariation(jobID, itemID, varID) { $0.file = rel }

                // leitura do próprio Mac: termo proibido → refaz sozinho uma vez
                let target = out
                let ocr = await Task.detached(operation: { LocalOCR.text(at: target) }).value ?? ""
                ocrLeftovers = ForbiddenTerms.found(in: ocr, terms: s.forbidden)
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
            ctx.log(.success, "gerada com \(usedLabel) em \(Self.elapsed(started)).")
            return PendingCheck(varID: varID, index: v.index, file: out, leftovers: ocrLeftovers, ctx: ctx)
        } catch is CancellationError {
            store.updateVariation(jobID, itemID, varID) { $0.status = .pending; $0.retryNote = nil; $0.retryAt = nil }
            return nil
        } catch {
            if Task.isCancelled {
                store.updateVariation(jobID, itemID, varID) { $0.status = .pending; $0.retryNote = nil; $0.retryAt = nil }
                return nil
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
            return nil
        }
    }

    /// 4. CHECAGEM DO TEXTO de uma variação pronta: confere o texto travado e se apareceu marca.
    /// É auxiliar: falha aqui não derruba a variação. 1.0.0-beta.9: roda em paralelo com a próxima variação.
    private func checkText(jobID: UUID, itemID: UUID, varID: UUID, index: Int, file: URL,
                           transcript: String?, removeItems: [String], forbidden: [String], ocrLeftovers: [String],
                           verify: Bool, analysisChain: [ModelChoice],
                           config: ProviderConfig, rule: FallbackRule, ctx: RequestContext) async {
        var checkCtx = ctx
        checkCtx.step = "Checagem de texto v\(index)"
        checkCtx.category = .analise
        checkCtx.timeout = HTTP.analysisTimeout
        checkCtx.onStatus = nil

        var warnings: [String] = []
        if !ocrLeftovers.isEmpty { warnings.append("Termo proibido: " + ocrLeftovers.joined(separator: ", ")) }
        if verify, (transcript?.isEmpty == false || !forbidden.isEmpty),
           let jpeg = await Task.detached(operation: { ImageTools.uploadJPEG(file) }).value {
            do {
                let prompt = Prompts.textCheck(expected: transcript ?? "(no text)", removeItems: removeItems, forbidden: forbidden)
                let (raw, _) = try await withFallback(analysisChain, config: config, rule: rule, ctx: checkCtx, quickSwitch: true) {
                    try await $0.analyze(jpeg, prompt: prompt)
                }
                store.update(jobID) { $0.costUSD += self.settings.priceAnalysis }
                let obj = JSONExtract.object(from: raw) ?? [:]
                let match = (obj["match"] as? Bool) ?? true
                let diff = (obj["differences"] as? String) ?? ""
                let brand = (obj["brand_found"] as? [String]) ?? []
                if !match && transcript?.isEmpty == false { warnings.append("Texto diferente: " + (diff.isEmpty ? "verifique" : diff)) }
                if !brand.isEmpty { warnings.append("Marca apareceu: " + brand.joined(separator: ", ")) }
            } catch {
                if error is CancellationError || Task.isCancelled { return }
                checkCtx.log(.warning, "checagem não concluída (a variação foi mantida). \(error.localizedDescription)",
                             details: error.aiDetails)
            }
        }
        if Task.isCancelled { return }
        let joined = warnings.isEmpty ? nil : warnings.joined(separator: " · ")
        store.updateVariation(jobID, itemID, varID) { $0.textWarning = joined }
        if let joined { checkCtx.log(.warning, joined) }
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
