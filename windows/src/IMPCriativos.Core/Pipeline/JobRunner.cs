using System.Collections.Concurrent;
using System.Globalization;
using IMPCriativos.Core.Imaging;
using IMPCriativos.Core.Models;
using IMPCriativos.Core.Providers;
using IMPCriativos.Core.Storage;

namespace IMPCriativos.Core.Pipeline;

/// <summary>Notificações do sistema (o App liga o toast do Windows).</summary>
public static class Notifier
{
    public static Action<string, string>? Handler { get; set; }

    public static void Post(string title, string body)
    {
        try { Handler?.Invoke(title, body); } catch { }
    }
}

/// <summary>
/// Executa os lotes: planejamento → limpeza → análise → variações → checagem de texto.
/// Cada passo é salvo em disco; pausar, fechar o app ou desligar o computador não perde trabalho.
/// Mesma lógica de <c>Pipeline/JobRunner.swift</c>.
/// </summary>
public sealed class JobRunner
{
    private readonly JobStore _store;
    private readonly AppSettings _settings;
    private readonly object _lock = new();
    private readonly Dictionary<Guid, (Task Task, CancellationTokenSource Cts)> _tasks = new();
    private readonly HashSet<Guid> _running = new();
    /// <summary>1.0.0-beta.8: imagens bloqueadas pelo filtro de conteúdo, por lote e por IA (disjuntor).</summary>
    private readonly ConcurrentDictionary<Guid, ConcurrentDictionary<ModelChoice, int>> _imageBlocks = new();
    /// <summary>1.0.0-beta.8: até quando o modelo de planejamento de cada IA fica "em pausa" depois de um 503/429.</summary>
    private readonly ConcurrentDictionary<ModelChoice, DateTime> _plannerCooldown = new();
    /// <summary>1.0.0-beta.9: até quando o modelo de análise de cada IA fica de lado depois de travar.</summary>
    private readonly ConcurrentDictionary<ModelChoice, DateTime> _analysisCooldown = new();
    /// <summary>1.0.0-beta.19: vigia de travamento. Último avanço de cada lote (etapas concluídas e quando).</summary>
    private readonly ConcurrentDictionary<Guid, (int Steps, DateTime At)> _progressMark = new();

    /// <summary>Depois de quantos bloqueios de imagem no mesmo lote a IA deixa de ser tentada nas próximas imagens dele.</summary>
    public const int ImageBlockLimit = 2;
    /// <summary>Tentativas do modelo de planejamento quando há outra IA de reserva (em vez das 6 do lote).</summary>
    public const int PlannerQuickAttempts = 2;
    /// <summary>Quanto tempo o modelo de planejamento sobrecarregado fica de lado.</summary>
    public static readonly TimeSpan PlannerCooldownTime = TimeSpan.FromMinutes(5);
    /// <summary>Tentativas da análise/checagem na IA principal quando há outra de reserva.</summary>
    public const int AnalysisQuickAttempts = 2;
    /// <summary>Tentativas da análise/checagem na IA de reserva (a checagem é auxiliar; não vale esperar muito).</summary>
    public const int AnalysisBackupAttempts = 3;
    /// <summary>Quanto tempo o modelo de análise que travou fica de lado.</summary>
    public static readonly TimeSpan AnalysisCooldownTime = TimeSpan.FromMinutes(5);
    /// <summary>Lote sem nenhuma etapa concluída por este tempo = sinal de travamento.</summary>
    public static readonly TimeSpan StallTime = TimeSpan.FromMinutes(12);
    /// <summary>De quanto em quanto tempo o vigia confere o lote e o computador.</summary>
    public static readonly TimeSpan WatchInterval = TimeSpan.FromSeconds(30);
    /// <summary>Quantas vezes o app refaz sozinho quando aparece termo proibido (limpeza e cada variação).</summary>
    public const int AutoRedoLimit = 1;

    /// <summary>Lotes rodando mudaram.</summary>
    public event Action? RunningChanged;

    public JobRunner(JobStore store, AppSettings settings)
    {
        _store = store;
        _settings = settings;
    }

    public HashSet<Guid> Running
    {
        get { lock (_lock) return new HashSet<Guid>(_running); }
    }

    public bool HasActiveWork
    {
        get { lock (_lock) return _running.Count > 0; }
    }

    public bool IsRunning(Guid id)
    {
        lock (_lock) return _running.Contains(id);
    }

    /// <summary>Regras de troca automática de IA, lidas das Configurações quando o lote começa.</summary>
    public sealed record FallbackRule(bool Enabled, bool OnBlocked)
    {
        /// <summary>
        /// 1.0.0-beta.11: com uma reserva escolhida por etapa, qualquer erro troca para ela
        /// (modelo inexistente, chave, pedido recusado…); bloqueio de conteúdo só se a opção estiver ligada.
        /// </summary>
        public bool Applies(Exception error)
        {
            if (!Enabled) return false;
            return error.AiKind() == AIErrorKind.Blocked ? OnBlocked : true;
        }
    }

    // MARK: controle

    public void Start(Guid jobID)
    {
        lock (_lock)
        {
            if (_tasks.ContainsKey(jobID)) return;
        }
        var job = _store.Get(jobID);
        if (job == null || job.State == JobState.Cancelled) return;
        var wasStarted = job.FinishedSteps > 0;
        _store.Update(jobID, j => { j.State = JobState.Running; j.LastError = null; });
        var line1 = (job.IsCleanOnly
                        ? $"{job.Items.Count} criativos · só limpeza (sem variações)"
                        : $"{job.Items.Count} criativos · {job.VariationsPerItem} variações cada")
                    + (job.IsAxisTest ? " (teste de eixos: todos os eixos do cliente)" : "")
                    + (job.SkipsCleaning ? " · limpeza desligada (imagens já limpas)" : "")
                    + $" · saída {job.SizeMode.Label} {job.Format.Label()}";
        AppLog.Info(LogCategory.Lote, wasStarted ? "Lote retomado." : "Lote iniciado.",
            details: $"{line1}\nIA do lote — {ProviderSummary(job)}\n{_settings.Summary}",
            jobID: jobID, jobName: job.Name);
        var cts = new CancellationTokenSource();
        lock (_lock)
        {
            if (_tasks.ContainsKey(jobID)) return;
            _running.Add(jobID);
            var task = Task.Run(async () =>
            {
                try { await Run(jobID, cts.Token); }
                catch (OperationCanceledException) { }
                catch (Exception e)
                {
                    AppLog.Error(LogCategory.Lote, $"Erro inesperado no lote: {e.Message}", details: e.ToString(), jobID: jobID, jobName: job.Name);
                }
                finally
                {
                    lock (_lock)
                    {
                        _tasks.Remove(jobID);
                        _running.Remove(jobID);
                    }
                    RunningChanged?.Invoke();
                }
            });
            _tasks[jobID] = (task, cts);
        }
        RunningChanged?.Invoke();
    }

    private void CancelTask(Guid id)
    {
        lock (_lock)
            if (_tasks.TryGetValue(id, out var t)) t.Cts.Cancel();
    }

    public void Pause(Guid jobID)
    {
        CancelTask(jobID);
        _store.Update(jobID, j => j.State = JobState.Paused);
        if (_store.Get(jobID) is Job job) AppLog.Info(LogCategory.Lote, "Lote pausado.", jobID: jobID, jobName: job.Name);
    }

    public void Cancel(Guid jobID)
    {
        CancelTask(jobID);
        _store.Update(jobID, j => j.State = JobState.Cancelled);
        if (_store.Get(jobID) is Job job) AppLog.Warning(LogCategory.Lote, "Lote cancelado.", jobID: jobID, jobName: job.Name);
    }

    public void PauseAll()
    {
        foreach (var id in Running) Pause(id);
    }

    /// <summary>Espera os lotes pararem (ao sair do app), até o tempo dado.</summary>
    public async Task WaitIdle(TimeSpan max)
    {
        Task[] all;
        lock (_lock) all = _tasks.Values.Select(t => t.Task).ToArray();
        if (all.Length == 0) return;
        await Task.WhenAny(Task.WhenAll(all), Task.Delay(max));
    }

    /// <summary>Ao abrir o app: retoma lotes que estavam rodando quando ele foi fechado.</summary>
    public void ResumeInterrupted()
    {
        foreach (var job in _store.Jobs.Where(j => j.State is JobState.Running or JobState.Queued))
        {
            AppLog.Info(LogCategory.Sistema, "Retomando lote interrompido quando o app fechou.", jobID: job.Id, jobName: job.Name);
            Start(job.Id);
        }
    }

    public void RedoClean(Guid jobID, Guid itemID, string? note, ProviderKind? provider = null)
    {
        _store.UpdateItem(jobID, itemID, item =>
        {
            item.CleanStatus = StepStatus.Pending;
            item.CleanError = null;
            item.CleanErrorKind = null;
            item.CleanErrorDetails = null;
            item.CleanWarning = null;
            item.CleanReview = ReviewStatus.Pending;
            item.CleanRedoNote = note;
            item.CleanProviderOverride = provider ?? item.CleanProviderOverride;
            item.AnalysisDone = false;
            item.AutoCleanRedos = 0;
            item.CleanSkipped = false;
            item.ForceClean = true;
        });
        if (_store.Get(jobID) is Job job && job.Items.FirstOrDefault(i => i.Id == itemID) is JobItem it)
        {
            var msg = "Limpeza enviada para refazer";
            if (provider is ProviderKind p) msg += $" com {p.Label()}";
            AppLog.Info(LogCategory.Revisao, msg + ".", details: note != null ? $"Observação: {note}" : null,
                jobID: jobID, jobName: job.Name, item: it.SourceName);
        }
        Start(jobID);
    }

    public void RedoVariation(Guid jobID, Guid itemID, Guid varID, string? note, ProviderKind? provider = null)
    {
        _store.UpdateVariation(jobID, itemID, varID, v =>
        {
            v.Status = StepStatus.Pending;
            v.Error = null;
            v.ErrorKind = null;
            v.ErrorDetails = null;
            v.TextWarning = null;
            v.Review = ReviewStatus.Pending;
            v.RedoNote = note;
            v.ProviderOverride = provider ?? v.ProviderOverride;
            v.AutoRedos = 0;
        });
        if (_store.Get(jobID) is Job job && job.Items.FirstOrDefault(i => i.Id == itemID) is JobItem it &&
            it.Variations.FirstOrDefault(x => x.Id == varID) is Variation v)
        {
            var msg = $"Variação v{v.Index} enviada para refazer";
            if (provider is ProviderKind p) msg += $" com {p.Label()}";
            AppLog.Info(LogCategory.Revisao, msg + ".", details: note != null ? $"Observação: {note}" : null,
                jobID: jobID, jobName: job.Name, item: it.SourceName);
        }
        Start(jobID);
    }

    /// <summary>Volta para a fila tudo que falhou. Com <paramref name="provider"/>, força essa IA nas etapas refeitas.</summary>
    public void RetryFailed(Guid jobID, ProviderKind? provider = null)
    {
        var count = 0;
        _store.Update(jobID, job =>
        {
            foreach (var item in job.Items)
            {
                if (item.CleanStatus == StepStatus.Failed)
                {
                    item.CleanStatus = StepStatus.Pending;
                    item.CleanError = null;
                    item.CleanErrorKind = null;
                    item.CleanErrorDetails = null;
                    if (provider != null) item.CleanProviderOverride = provider;
                    count++;
                }
                foreach (var v in item.Variations.Where(v => v.Status == StepStatus.Failed))
                {
                    v.Status = StepStatus.Pending;
                    v.Error = null;
                    v.ErrorKind = null;
                    v.ErrorDetails = null;
                    if (provider != null) v.ProviderOverride = provider;
                    count++;
                }
            }
        });
        if (count == 0 || _store.Get(jobID) is not Job j) return;
        AppLog.Info(LogCategory.Lote, $"{count} etapa(s) com falha voltaram para a fila" + (provider is ProviderKind p ? $" usando {p.Label()}" : "") + ".",
            jobID: jobID, jobName: j.Name);
        Start(jobID);
    }

    /// <summary>"Tentar falhas de novo" em todos os lotes de uma vez.</summary>
    public void RetryAllFailed()
    {
        foreach (var job in _store.Jobs.Where(j => j.FailureCount > 0 && j.State != JobState.Cancelled))
            RetryFailed(job.Id);
    }

    // MARK: execução

    private static bool NeedsWork(JobItem item)
    {
        if (item.CleanStatus is StepStatus.Pending or StepStatus.Running) return true;
        if (item.CleanStatus != StepStatus.Done) return false;
        return !item.AnalysisDone || item.Variations.Any(v => v.Status is StepStatus.Pending or StepStatus.Running);
    }

    private async Task Run(Guid jobID, CancellationToken ct)
    {
        var job = _store.Get(jobID);
        if (job == null) return;
        var config = new ProviderConfig(_settings);
        ProviderGate.Configure(_settings.MaxImageRequests, _settings.FastImageCeiling, _settings.FastMode);
        ProviderGate.SetMacHoldAll(SpeedMonitor.MacRisk());
        SpeedMonitor.Shared.Refresh();

        // as plataformas escolhidas no lote são obrigatórias; a reserva de cada etapa só entra se tiver chave
        // 1.0.0-beta.20: só limpeza não usa a IA das variações; limpeza desligada não usa a IA da limpeza
        var missing = RequiredProviders(job).Where(p => !ApiKeyStore.HasKey(p)).Cast<ProviderKind?>().FirstOrDefault();
        if (missing is ProviderKind m)
        {
            var msg = $"Chave do {m.Label()} não configurada. Vá em Configurações → Chaves de API.";
            _store.Update(jobID, j => { j.State = JobState.Paused; j.LastError = msg; });
            AppLog.Error(LogCategory.Lote, $"Lote pausado: {msg}", jobID: jobID, jobName: job.Name);
            return;
        }

        // passos interrompidos no meio voltam para "pendente"
        _store.Update(jobID, j =>
        {
            foreach (var item in j.Items)
            {
                item.CleanRetryNote = null;
                item.CleanRetryAt = null;
                if (item.CleanStatus == StepStatus.Running) item.CleanStatus = StepStatus.Pending;
                foreach (var v in item.Variations)
                {
                    v.RetryNote = null;
                    v.RetryAt = null;
                    if (v.Status == StepStatus.Running) v.Status = StepStatus.Pending;
                }
            }
        });

        _imageBlocks[jobID] = new ConcurrentDictionary<ModelChoice, int>();
        _progressMark[jobID] = (_store.Get(jobID)?.FinishedSteps ?? 0, DateTime.UtcNow);
        // 1.0.0-beta.19: vigia do lote — computador sob pressão ou lote parado devolvem a velocidade original
        using var watchCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        var watchdog = Task.Run(async () =>
        {
            try
            {
                while (!watchCts.IsCancellationRequested)
                {
                    await Task.Delay(WatchInterval, watchCts.Token);
                    Watch(jobID);
                }
            }
            catch (OperationCanceledException) { }
        });
        try
        {
            var workers = Math.Max(1, _settings.MaxConcurrent);
            var rule = new FallbackRule(_settings.FallbackEnabled, _settings.FallbackOnBlocked);
            var attempts = Math.Max(1, _settings.RetryAttempts);

            // repete enquanto aparecer trabalho novo (ex.: "refazer" clicado durante o lote)
            while (!ct.IsCancellationRequested)
            {
                // integridade: o que está "pronto" sem a imagem no disco volta para a fila antes de cada rodada
                var repaired = _store.RepairMissingFiles(jobID);
                if (repaired > 0 && _store.Get(jobID) is Job rj)
                    AppLog.Warning(LogCategory.Lote, $"Integridade: {repaired} imagem(ns) prontas não estavam no disco e voltaram para a fila.",
                        jobID: jobID, jobName: rj.Name);
                var current = _store.Get(jobID);
                if (current == null) return;
                var pending = current.Items.Where(NeedsWork).Select(i => i.Id).ToList();
                if (pending.Count == 0) break;
                var queue = new ConcurrentQueue<Guid>(pending);
                var tasks = Enumerable.Range(0, Math.Min(workers, pending.Count)).Select(_ => Task.Run(async () =>
                {
                    while (!ct.IsCancellationRequested && queue.TryDequeue(out var id))
                    {
                        try { await Process(jobID, id, config, rule, attempts, ct); }
                        catch (OperationCanceledException) { }
                        catch (Exception e)
                        {
                            AppLog.Error(LogCategory.Lote, $"Erro inesperado: {e.Message}", details: e.ToString(), jobID: jobID, jobName: current.Name);
                        }
                    }
                })).ToArray();
                await Task.WhenAll(tasks);
            }
        }
        finally
        {
            watchCts.Cancel();
            try { await watchdog; } catch { }
            _progressMark.TryRemove(jobID, out _);
        }

        if (ct.IsCancellationRequested) return;
        var finished = _store.Get(jobID);
        if (finished == null || finished.State != JobState.Running) return;
        _store.Update(jobID, j => j.State = JobState.Review);
        var failed = finished.FailureCount;
        var summary = $"{finished.Items.Count} criativos · {finished.FailureCount} etapa(s) com falha · {finished.WarningCount} com alerta · gasto estimado {finished.CostUSD.Usd()}";
        if (failed > 0)
            AppLog.Warning(LogCategory.Lote, "Lote terminou com falhas. Use \"Tentar falhas de novo\".", details: summary, jobID: jobID, jobName: finished.Name);
        else
            AppLog.Success(LogCategory.Lote, "Lote concluído, pronto para revisão.", details: summary, jobID: jobID, jobName: finished.Name);
        if (_settings.NotifyOnFinish)
            Notifier.Post("Lote pronto para revisão",
                $"{finished.Name}: {finished.Items.Count} criativos processados" + (failed > 0 ? $", {failed} etapa(s) com falha." : "."));
    }

    /// <summary>
    /// 1.0.0-beta.19: vigia do lote, a cada 30 s enquanto ele roda.
    /// - Computador com pouco disco ou em economia de bateria → filas de imagem na velocidade original.
    /// - Nenhuma etapa concluída em 12 minutos → trata como travamento: velocidade original e modo seguro.
    /// Não cancela nada; só segura os próximos pedidos.
    /// </summary>
    private void Watch(Guid jobID)
    {
        ProviderGate.SetMacHoldAll(SpeedMonitor.MacRisk());
        var job = _store.Get(jobID);
        if (job == null || job.State != JobState.Running) return;
        var steps = job.FinishedSteps;
        var now = DateTime.UtcNow;
        if (!_progressMark.TryGetValue(jobID, out var mark) || mark.Steps != steps)
        {
            _progressMark[jobID] = (steps, now);
            return;
        }
        if (now - mark.At < StallTime) return;
        _progressMark[jobID] = (steps, now);
        var minutes = (int)StallTime.TotalMinutes;
        AppLog.Warning(LogCategory.Lote, $"Segurança: o lote está há {minutes} minutos sem concluir nenhuma etapa. A velocidade voltou para a original.",
            details: "Os pedidos em andamento continuam (cada um tem tempo limite). Se nada mudar, pause e retome o lote ou veja os erros em Histórico.",
            jobID: jobID, jobName: job.Name);
        ProviderGate.ReportStall($"lote sem avanço há {minutes} minutos");
    }

    /// <summary>
    /// 1.0.0-beta.19 — integridade: a resposta da IA precisa ser uma imagem que o computador consegue abrir.
    /// Se não for, conta como falha temporária (a etapa é refeita com a reserva, se houver).
    /// </summary>
    public static byte[] ValidImage(byte[] data)
    {
        if (!ImageTools.IsValidImage(data))
            throw new AIError("A IA devolveu um arquivo que não é uma imagem válida.", AIErrorKind.Temporary,
                details: $"{data.Length} bytes recebidos");
        return data;
    }

    /// <summary>1.0.0-beta.19 — integridade: a imagem gravada precisa existir e abrir.</summary>
    public static void VerifySaved(string path)
    {
        if (ImageTools.PixelSize(path) == null)
            throw new AIError("A imagem não foi gravada corretamente no disco.", AIErrorKind.Other, details: path);
    }

    /// <summary>
    /// Chama a IA principal da etapa; se falhar (e a troca automática estiver ligada) e a reserva tiver chave, refaz com ela.
    /// - imageOp: pedido de imagem (limpeza/variação). Conta bloqueios do filtro de conteúdo por lote; depois de
    ///   <see cref="ImageBlockLimit"/> bloqueios do mesmo modelo, as próximas imagens do lote vão direto para a reserva.
    /// - explicit: o usuário escolheu esta IA para esta etapa ("refazer com…"); o disjuntor não interfere.
    /// - quickSwitch: análise/checagem (1.0.0-beta.9). Com reserva, desiste na 2ª falha temporária
    ///   e deixa o modelo que travou de lado por 5 minutos.
    /// </summary>
    private async Task<(T Value, ModelChoice Used)> WithFallback<T>(List<ModelChoice> chain, ProviderConfig config, FallbackRule rule,
        RequestContext ctx, Func<IAIProvider, Task<T>> op, CancellationToken ct, bool imageOp = false, bool @explicit = false,
        bool quickSwitch = false)
    {
        if (chain.Count == 0) throw new AIError("Nenhuma IA configurada para esta etapa.");
        var primary = chain[0];
        var reserve = chain.Skip(1).FirstOrDefault(c => ApiKeyStore.HasKey(c.Provider));
        ModelChoice? Other(ModelChoice c) => reserve == null ? null : c == primary ? reserve : primary;
        var blockedRule = rule.Applies(new AIError("", AIErrorKind.Blocked));
        var first = primary;
        if (imageOp && !@explicit && blockedRule && reserve != null && BlockCount(ctx.JobID, primary) >= ImageBlockLimit)
        {
            first = reserve;
            ctx.OnStatus?.Invoke($"Indo direto para {reserve.Provider.Label()}…", null);
        }
        var canQuickSwitch = quickSwitch && rule.Enabled && reserve != null;
        if (canQuickSwitch && _analysisCooldown.TryGetValue(primary, out var until) && until > DateTime.UtcNow)
            first = reserve!;
        var firstCtx = ctx;
        if (first != primary) firstCtx = firstCtx with { Step = ctx.Step + $" ({first.Label})" };
        if (canQuickSwitch) firstCtx = firstCtx with { MaxAttempts = Math.Min(ctx.MaxAttempts, AnalysisQuickAttempts) };
        try
        {
            var main = ProviderFactory.Make(first, config);
            var value = await RequestContext.With(firstCtx, () => op(main));
            return (value, first);
        }
        catch (Exception error) when (error is not OperationCanceledException && !ct.IsCancellationRequested)
        {
            if (imageOp && error.AiKind() == AIErrorKind.Blocked) RegisterBlock(first, Other(first), ctx, blockedRule);
            var alt = Other(first);
            if (!rule.Applies(error) || alt == null) throw;
            IAIProvider backup;
            try { backup = ProviderFactory.Make(alt, config); } catch { throw error; }
            var cooldownNote = "";
            if (canQuickSwitch && error.AiKind().IsTemporary())
            {
                var wasCooling = _analysisCooldown.TryGetValue(first, out var u) && u > DateTime.UtcNow;
                _analysisCooldown[first] = DateTime.UtcNow + AnalysisCooldownTime;
                if (!wasCooling && first == primary)
                    cooldownNote = $" Nos próximos {(int)AnalysisCooldownTime.TotalMinutes} minutos, as análises e checagens vão direto para {alt.Label}.";
            }
            ctx.Log(LogLevel.Warning, $"{first.Label} falhou ({error.AiKind().Title()}). Refazendo automaticamente com a reserva {alt.Label}.{cooldownNote}",
                error.AiDetails() ?? error.Message);
            ctx.OnStatus?.Invoke($"Trocando para {alt.Provider.Label()}…", null);
            var altCtx = ctx with { Step = ctx.Step + $" ({alt.Label})" };
            if (canQuickSwitch) altCtx = altCtx with { MaxAttempts = Math.Min(ctx.MaxAttempts, AnalysisBackupAttempts) };
            var value = await RequestContext.With(altCtx, () => op(backup));
            return (value, alt);
        }
    }

    private int BlockCount(Guid? jobID, ModelChoice choice)
    {
        if (jobID is not Guid id || !_imageBlocks.TryGetValue(id, out var d)) return 0;
        return d.TryGetValue(choice, out var n) ? n : 0;
    }

    /// <summary>Conta um bloqueio de imagem; ao atingir o limite, avisa uma vez no Histórico.</summary>
    private void RegisterBlock(ModelChoice choice, ModelChoice? reserve, RequestContext ctx, bool canSwitch)
    {
        if (ctx.JobID is not Guid jobID) return;
        var d = _imageBlocks.GetOrAdd(jobID, _ => new ConcurrentDictionary<ModelChoice, int>());
        var n = d.AddOrUpdate(choice, 1, (_, v) => v + 1);
        if (n != ImageBlockLimit || !canSwitch || reserve == null) return;
        AppLog.Warning(LogCategory.Lote, $"{choice.Label} bloqueou {n} imagens neste lote. As próximas imagens deste lote vão direto para {reserve.Label}.",
            details: $"Vale até o lote terminar ou ser pausado. \"Refazer com {choice.Provider.Label()}\" continua disponível em cada imagem.",
            jobID: jobID, jobName: ctx.JobName);
    }

    /// <summary>1.0.0-beta.9: o tempo máximo de cada tentativa sai da etapa (análise 90s, imagem 5 min; o planejamento passa 4 min).</summary>
    private static RequestContext Context(Job job, JobItem item, string step, LogCategory category, int attempts, double? timeout = null,
        Action<string?, DateTime?>? onStatus = null) => new()
    {
        JobID = job.Id,
        JobName = job.Name,
        Item = item.SourceName,
        Step = step,
        Category = category,
        MaxAttempts = attempts,
        Timeout = timeout ?? (category == LogCategory.Analise ? Http.AnalysisTimeout : Http.ImageTimeout),
        OnStatus = onStatus,
    };

    /// <summary>
    /// Faz o plano com a IA de planejamento escolhida; se falhar (e a troca automática estiver ligada), tenta a reserva.
    /// 1.0.0-beta.8: com reserva, desiste na 2ª falha temporária (503/429) em vez de esperar as 6 tentativas,
    /// e deixa o modelo sobrecarregado de lado por 5 minutos. Último recurso: a IA principal da análise.
    /// </summary>
    private async Task<CreativePlan> MakePlan(byte[] jpeg, string prompt, ProviderConfig config, FallbackRule rule, RequestContext ctx,
        CancellationToken ct)
    {
        var chain = config.Chain(AIStage.Planning).Where(c => ApiKeyStore.HasKey(c.Provider)).ToList();
        var order = rule.Enabled ? chain : chain.Take(1).ToList();
        if (order.Count > 1 && _plannerCooldown.TryGetValue(order[0], out var until) && until > DateTime.UtcNow)
        {
            (order[0], order[1]) = (order[1], order[0]);
            ctx.Log(LogLevel.Info, $"{order[1].Label} estava sobrecarregado há pouco; planejando com {order[0].Label}.");
        }
        var basic = config.Chain(AIStage.Analysis).FirstOrDefault(c => ApiKeyStore.HasKey(c.Provider));
        if (basic != null && !order.Contains(basic) && (rule.Enabled || order.Count == 0)) order.Add(basic);
        Exception lastError = new AIError("Nenhuma IA com chave configurada para o planejamento.", AIErrorKind.Auth);
        for (var i = 0; i < order.Count; i++)
        {
            var choice = order[i];
            if (i > 0) ctx.Log(LogLevel.Warning, $"refazendo o planejamento com {choice.Label}.", lastError.AiDetails() ?? lastError.Message);
            var attemptCtx = ctx;
            if (i < order.Count - 1) attemptCtx = ctx with { MaxAttempts = Math.Min(ctx.MaxAttempts, PlannerQuickAttempts) };
            try
            {
                var planner = ProviderFactory.Make(choice, config);
                var raw = await RequestContext.With(attemptCtx, () => planner.Analyze(jpeg, prompt, ct));
                if (CreativePlanner.Parse(raw, choice.Model) is CreativePlan plan) return plan;
                lastError = new AIError($"O planejamento do {choice.Label} veio fora do formato esperado.", details: raw[..Math.Min(600, raw.Length)]);
            }
            catch (OperationCanceledException) { throw; }
            catch (Exception error)
            {
                if (ct.IsCancellationRequested) throw new OperationCanceledException(ct);
                lastError = error;
                if (error.AiKind() is AIErrorKind.Temporary or AIErrorKind.RateLimit)
                    _plannerCooldown[choice] = DateTime.UtcNow + PlannerCooldownTime;
                else if (error.AiKind() is AIErrorKind.Model or AIErrorKind.BadRequest)
                    ctx.Log(LogLevel.Warning, $"o modelo {choice.Label} não foi aceito. Confira em Configurações → Modelos de IA.", error.AiDetails());
            }
        }
        throw lastError;
    }

    private static string? JoinNotes(string? a, string? b)
    {
        var parts = new[] { a, b }.Where(x => x != null).Select(x => x!.Trimmed()).Where(x => x.Length > 0).ToList();
        return parts.Count == 0 ? null : string.Join(" ", parts);
    }

    private string Abs(Guid jobID, string rel) => _store.FilePath(jobID, rel)!;

    private async Task Process(Guid jobID, Guid itemID, ProviderConfig config, FallbackRule rule, int attempts, CancellationToken ct)
    {
        var job = _store.Get(jobID);
        var first = job?.Items.FirstOrDefault(i => i.Id == itemID);
        if (job == null || first == null) return;
        var folder = _store.Folder(jobID);
        var removeItems = job.EffectiveRemoveItems;
        var extra = job.Client.ExtraInstructions;
        var textChanges = job.Instructions?.TextChanges ?? "";
        var direction = job.Instructions?.Direction ?? "";
        var name = first.SourceName;

        // 0. PLANEJAMENTO: a IA mais forte lê o pedido e o criativo e escreve as instruções exatas
        if (first.PlanDone != true && first.CleanStatus != StepStatus.Done)
        {
            if (_settings.PlanningEnabled)
            {
                _store.UpdateItem(jobID, itemID, i => { i.CleanStatus = StepStatus.Running; i.CleanRetryNote = "Planejando o criativo…"; i.CleanRetryAt = null; });
                var ctx = Context(job, first, "Planejamento", LogCategory.Analise, attempts, Http.PlannerTimeout);
                var started = DateTime.UtcNow;
                try
                {
                    var src = Abs(jobID, first.OriginalFile);
                    var upload = await Task.Run(() => ImageTools.UploadJpeg(src)) ?? throw new AIError("Não foi possível ler a imagem original.");
                    var prompt = CreativePlanner.Prompt(removeItems, extra, job.Instructions);
                    var plan = await MakePlan(upload, prompt, config, rule, ctx, ct);
                    _store.Update(jobID, j => j.CostUSD += _settings.PricePlanning);
                    _store.UpdateItem(jobID, itemID, i => { i.Plan = plan; i.PlanDone = true; i.CleanRetryNote = null; });
                    ctx.Log(LogLevel.Info, $"plano pronto em {Elapsed(started)} · termos proibidos: " +
                                           (plan.ForbiddenTerms.Count == 0 ? "nenhum" : string.Join(", ", plan.ForbiddenTerms)),
                        CreativePlanner.Summary(plan));
                }
                catch (Exception error)
                {
                    if (error is OperationCanceledException || ct.IsCancellationRequested)
                    {
                        _store.UpdateItem(jobID, itemID, i => { i.CleanStatus = StepStatus.Pending; i.CleanRetryNote = null; });
                        return;
                    }
                    _store.UpdateItem(jobID, itemID, i => { i.PlanDone = true; i.Plan = null; i.CleanRetryNote = null; });
                    ctx.Log(LogLevel.Warning, $"não foi possível planejar (o criativo segue com as instruções diretas). {error.Message}", error.AiDetails());
                }
            }
            else
            {
                _store.UpdateItem(jobID, itemID, i => i.PlanDone = true);
            }
        }

        var item = _store.Get(jobID)?.Items.FirstOrDefault(i => i.Id == itemID);
        if (item == null) return;
        var plan0 = item.Plan;
        // termos do plano + palavras citadas nos itens de remoção (rede de segurança se o plano esquecer algum)
        var forbidden = ForbiddenTerms.Dedup((plan0?.ForbiddenTerms ?? new List<string>()).Concat(ForbiddenTerms.Fallback(removeItems)));

        // 1a. NADA A REMOVER (1.0.0-beta.8): o plano disse que a imagem já está limpa → usa o original, sem custo.
        var cleanDone = item.CleanStatus == StepStatus.Done;

        // 1b. LIMPEZA DESLIGADA NO LOTE (1.0.0-beta.20): a imagem enviada já vem limpa → vai direto para as variações.
        if (!cleanDone && job.SkipsCleaning && item.ForceClean != true)
        {
            var src = Abs(jobID, item.OriginalFile);
            var rel = $"limpos/{Short(itemID)}-enviado-{Short(Guid.NewGuid())}.png";
            Paths.Ensure(Path.Combine(folder, "limpos"));
            var dst = Abs(jobID, rel);
            var ok = await Task.Run(() => ImageTools.CopyAsPng(src, dst));
            if (!ok)
            {
                _store.UpdateItem(jobID, itemID, i =>
                {
                    i.CleanStatus = StepStatus.Failed;
                    i.CleanError = ImageTools.IsHeic(src) && ImageTools.Extension?.UnsupportedMessage(src) is string hm
                        ? hm : "Não foi possível ler a imagem enviada.";
                    i.CleanErrorKind = AIErrorKind.Other;
                    i.CleanRetryNote = null;
                });
                AppLog.Error(LogCategory.Limpeza, "Não foi possível ler a imagem enviada.", jobID: jobID, jobName: job.Name, item: name);
                return;
            }
            _store.UpdateItem(jobID, itemID, i =>
            {
                i.CleanedFile = rel;
                i.CleanStatus = StepStatus.Done;
                i.CleanSkipped = true;
                i.CleanProviderUsed = null;
                i.CleanRetryNote = null;
                i.CleanRetryAt = null;
                i.AnalysisDone = false;
            });
            AppLog.Info(LogCategory.Limpeza, "Limpeza desligada no lote: usando a imagem enviada (sem custo).", jobID: jobID, jobName: job.Name, item: name);
            cleanDone = true;
        }

        if (!cleanDone && plan0?.SkipsCleaning == true && item.ForceClean != true && (item.CleanRedoNote ?? "").Trimmed().Length == 0)
        {
            var src = Abs(jobID, item.OriginalFile);
            var rel = $"limpos/{Short(itemID)}-original-{Short(Guid.NewGuid())}.png";
            Paths.Ensure(Path.Combine(folder, "limpos"));
            var dst = Abs(jobID, rel);
            if (await Task.Run(() => ImageTools.CopyAsPng(src, dst)))
            {
                _store.UpdateItem(jobID, itemID, i =>
                {
                    i.CleanedFile = rel;
                    i.CleanStatus = StepStatus.Done;
                    i.CleanSkipped = true;
                    i.CleanProviderUsed = null;
                    i.CleanRetryNote = null;
                    i.CleanRetryAt = null;
                    i.AnalysisDone = false;
                });
                AppLog.Success(LogCategory.Limpeza, "Limpeza: nada a remover segundo o plano; usando o original (sem custo).",
                    jobID: jobID, jobName: job.Name, item: name);
                cleanDone = true;
            }
        }

        // 1. LIMPEZA
        if (!cleanDone)
        {
            _store.UpdateItem(jobID, itemID, i => { i.CleanStatus = StepStatus.Running; i.CleanRetryNote = null; i.CleanRetryAt = null; });
            var started = DateTime.UtcNow;
            var ctx = Context(job, item, "Limpeza", LogCategory.Limpeza, attempts, onStatus: (note, until) =>
                _store.UpdateItem(jobID, itemID, i =>
                {
                    if (i.CleanStatus != StepStatus.Running) return;
                    i.CleanRetryNote = note;
                    i.CleanRetryAt = until;
                }));
            try
            {
                var src = Abs(jobID, item.OriginalFile);
                var upload = await Task.Run(() => ImageTools.UploadJpeg(src))
                             ?? throw new AIError(ImageTools.IsHeic(src) && ImageTools.Extension?.UnsupportedMessage(src) is string hm
                                 ? hm : "Não foi possível ler a imagem original.");
                var aspect = Aspect(job.SizeMode, item.PixelWidth, item.PixelHeight);
                string prompt;
                if (plan0 != null)
                {
                    var p = plan0.Copy();
                    p.ForbiddenTerms = forbidden;
                    prompt = Prompts.CleanFromPlan(p, extra, item.CleanRedoNote);
                }
                else
                {
                    prompt = Prompts.Clean(removeItems, extra, textChanges, forbidden, item.CleanRedoNote);
                }
                var chain = config.Chain(AIStage.Clean, item.CleanProviderOverride ?? job.CleanProvider);
                var (result, usedModel) = await WithFallback(chain, config, rule, ctx,
                    async provider => ValidImage(await provider.EditImage(upload, prompt, aspect, ct)), ct,
                    imageOp: true, @explicit: item.CleanProviderOverride != null);
                var rel = $"limpos/{Short(itemID)}-{Short(Guid.NewGuid())}.png";
                Paths.Ensure(Path.Combine(folder, "limpos"));
                ImageTools.SaveGenerated(result, Abs(jobID, rel));
                VerifySaved(Abs(jobID, rel));
                var used = usedModel.Provider;
                _store.Update(jobID, j => j.CostUSD += _settings.ImagePrice(used));
                _store.UpdateItem(jobID, itemID, i =>
                {
                    i.CleanedFile = rel;
                    i.CleanStatus = StepStatus.Done;
                    i.CleanRetryNote = null;
                    i.CleanRetryAt = null;
                    i.CleanProviderUsed = used;
                    i.CleanSkipped = false;
                    i.AnalysisDone = false;
                });
                ctx.Log(LogLevel.Success, $"concluída com {usedModel.Label} em {Elapsed(started)}.");
            }
            catch (Exception error)
            {
                if (error is OperationCanceledException || ct.IsCancellationRequested)
                {
                    _store.UpdateItem(jobID, itemID, i => { i.CleanStatus = StepStatus.Pending; i.CleanRetryNote = null; i.CleanRetryAt = null; });
                    return;
                }
                _store.UpdateItem(jobID, itemID, i =>
                {
                    i.CleanStatus = StepStatus.Failed;
                    i.CleanError = error.Message;
                    i.CleanErrorKind = error.AiKind();
                    i.CleanErrorDetails = error.AiDetails();
                    i.CleanRetryNote = null;
                    i.CleanRetryAt = null;
                });
                ctx.Log(LogLevel.Error, $"falhou — {error.AiKind().Title()}. {error.Message}",
                    string.Join("\n", new[] { error.AiDetails(), $"Sugestão: {error.AiKind().Hint()}" }.Where(x => x != null)));
                return;
            }
        }

        // 2. ANÁLISE: checa sobras (IA + leitura do próprio computador) e define o texto travado das variações
        var cleaned = _store.Get(jobID)?.Items.FirstOrDefault(i => i.Id == itemID);
        if (cleaned?.CleanedFile is not string cleanedRel) return;
        var cleanedPath = Abs(jobID, cleanedRel);
        if (!cleaned.AnalysisDone)
        {
            var ctx = Context(job, cleaned, "Análise", LogCategory.Analise, attempts);
            var ocr = await Task.Run(() => LocalOCR.Text(cleanedPath)) ?? "";
            var aiText = "";
            var aiWarnings = new List<string>();
            string? aiFinalText = null;
            var changesMissing = false;
            string? analysisFailed = null;
            // com plano, o texto final já está decidido; a análise só confere e transcreve
            var changesForAI = plan0 == null ? textChanges : "";
            try
            {
                var jpeg = await Task.Run(() => ImageTools.UploadJpeg(cleanedPath)) ?? throw new AIError("Não foi possível ler a imagem limpa.");
                var prompt = Prompts.Analysis(removeItems, changesForAI, forbidden);
                var (raw, _) = await WithFallback(config.Chain(AIStage.Analysis, job.AnalysisProvider), config, rule, ctx,
                    p => p.Analyze(jpeg, prompt, ct), ct, quickSwitch: true);
                _store.Update(jobID, j => j.CostUSD += _settings.PriceAnalysis);
                var obj = JsonExtract.Object(raw) ?? new System.Text.Json.Nodes.JsonObject();
                var isClean = JsonExtract.Bool(obj, "clean") ?? true;
                var found = JsonExtract.Strings(obj, "found") ?? new List<string>();
                aiText = JsonExtract.Str(obj, "text");
                aiFinalText = JsonExtract.OptStr(obj, "final_text")?.Trimmed().NilIfEmpty();
                changesMissing = changesForAI.Trimmed().Length > 0 && JsonExtract.Bool(obj, "changes_applied") == false;
                if (!isClean) aiWarnings.Add("Possível sobra de marca: " + (found.Count == 0 ? "verifique" : string.Join(", ", found)));
            }
            catch (Exception error)
            {
                if (error is OperationCanceledException || ct.IsCancellationRequested) return;
                analysisFailed = error.Message;
                ctx.Log(LogLevel.Warning, $"a IA não conseguiu conferir a limpeza (segue com a leitura do computador). {error.Message}", error.AiDetails());
            }

            // Conferência por código: termo proibido lido pela IA ou pelo OCR do computador → refaz sozinho uma vez
            var leftovers = ForbiddenTerms.Found(aiText + "\n" + ocr, forbidden);

            // 1.0.0-beta.20: limpeza desligada pelo usuário → não limpa sozinho; só avisa na revisão
            var userSkipped = job.SkipsCleaning && cleaned.ForceClean != true;

            // 1.0.0-beta.8: a limpeza foi pulada, mas a checagem achou marca → faz a limpeza de verdade
            if (!userSkipped && cleaned.CleanSkipped == true && (leftovers.Count > 0 || aiWarnings.Count > 0))
            {
                var found = (leftovers.Count == 0 ? new List<string>() : new List<string> { "termos: " + string.Join(", ", leftovers) }).Concat(aiWarnings);
                _store.UpdateItem(jobID, itemID, i =>
                {
                    i.CleanSkipped = false;
                    i.ForceClean = true;
                    i.CleanStatus = StepStatus.Pending;
                    i.AnalysisDone = false;
                });
                ctx.Log(LogLevel.Warning, "o plano dizia que não havia nada a remover, mas a checagem encontrou marca. Fazendo a limpeza.",
                    string.Join("\n", found));
                return;
            }
            if (!userSkipped && leftovers.Count > 0 && (cleaned.AutoCleanRedos ?? 0) < AutoRedoLimit)
            {
                var note = $"Ainda aparece: {string.Join(", ", leftovers)}. Apague esses termos de TODA a imagem, inclusive do título, das telas e das miniaturas, reescrevendo a frase só o necessário.";
                _store.UpdateItem(jobID, itemID, i =>
                {
                    i.AutoCleanRedos = (i.AutoCleanRedos ?? 0) + 1;
                    i.CleanRedoNote = JoinNotes(i.CleanRedoNote, note);
                    i.CleanStatus = StepStatus.Pending;
                    i.AnalysisDone = false;
                });
                ctx.Log(LogLevel.Warning, $"termo proibido ainda aparece no limpo ({string.Join(", ", leftovers)}). Refazendo a limpeza automaticamente.",
                    $"Leitura da IA:\n{aiText}\n\nLeitura do computador:\n{ocr}");
                return;
            }

            // texto travado das variações: o final do plano; sem plano, o que a análise viu (com as alterações pedidas)
            string expected;
            if (plan0?.FinalText is { Length: > 0 } fin)
            {
                expected = fin;
            }
            else
            {
                var seen = aiText.Trimmed().Length == 0 ? ocr : aiText;
                expected = textChanges.Trimmed().Length == 0 ? seen : (aiFinalText ?? seen);
            }
            if (ForbiddenTerms.Found(expected, forbidden).Count > 0) expected = ForbiddenTerms.Strip(forbidden, expected);

            var warnings = new List<string>(aiWarnings);
            if (userSkipped && leftovers.Count > 0)
                warnings.Add($"Marca na imagem enviada: {string.Join(", ", leftovers)} (limpeza desligada; as variações foram instruídas a não escrever. Use Refazer na limpeza para limpar esta imagem)");
            else if (leftovers.Count > 0)
                warnings.Add($"Termo proibido no limpo mesmo após refazer: {string.Join(", ", leftovers)} (as variações foram instruídas a não escrever)");
            if (changesMissing) warnings.Add($"Alteração de texto não aplicada no limpo (as variações vão aplicar): {textChanges.Trimmed()}");
            if (analysisFailed != null && leftovers.Count == 0) warnings.Add($"Não foi possível conferir a limpeza com a IA: {analysisFailed}");
            var warning = warnings.Count == 0 ? null : string.Join(" · ", warnings);
            var seenText = aiText.Trimmed().Length == 0 ? null : aiText;
            var finalExpected = expected;
            _store.UpdateItem(jobID, itemID, i =>
            {
                i.Transcript = finalExpected.Trimmed().Length == 0 ? null : finalExpected;
                i.SeenText = seenText == finalExpected ? null : seenText;
                i.CleanWarning = warning;
                i.AnalysisDone = true;
            });
            if (warning != null) ctx.Log(LogLevel.Warning, warning);
        }

        // 3. VARIAÇÕES — 1.0.0-beta.19: saem juntas, até o limite da fila de imagem da IA
        var ready = _store.Get(jobID)?.Items.FirstOrDefault(i => i.Id == itemID);
        if (ready == null) return;
        // 1.0.0-beta.20: módulo "Limpar logo" — o criativo termina na limpeza conferida
        if (ready.Variations.Count == 0) return;
        var reference = await Task.Run(() => ImageTools.UploadJpeg(cleanedPath));
        if (reference == null)
        {
            AppLog.Error(LogCategory.Variacao, "Não foi possível ler a imagem limpa para gerar as variações.", jobID: jobID, jobName: job.Name, item: name);
            return;
        }
        var setup = new VariationSetup(job, ready, folder, reference, Aspect(job.SizeMode, ready.PixelWidth, ready.PixelHeight),
            plan0?.VariationRules ?? "", forbidden, extra, direction, textChanges, config, rule, attempts);
        var pendingVars = ready.Variations.Where(v => v.Status is StepStatus.Pending or StepStatus.Running).ToList();
        var gate = ProviderGate.Image(job.VariationProvider);
        var analysisChain = config.Chain(AIStage.Analysis, job.AnalysisProvider);

        await BoundedParallel.Run(pendingVars,
            () => Task.FromResult(gate.CurrentLimit()),
            v => GenerateVariation(v, setup, ct),
            // 4. CHECAGEM DO TEXTO — roda junto com as próximas variações, sem ocupar vaga de imagem.
            check => CheckText(jobID, itemID, check.VarID, check.Index, check.File, ready.Transcript, removeItems, forbidden,
                check.Leftovers, job.VerifyText, analysisChain, config, rule, check.Ctx, ct),
            ct);
    }

    /// <summary>Tudo que as variações de um criativo têm em comum.</summary>
    private sealed record VariationSetup(Job Job, JobItem Item, string Folder, byte[] Reference, string Aspect, string Rules,
        List<string> Forbidden, string Extra, string Direction, string TextChanges, ProviderConfig Config, FallbackRule Rule, int Attempts);

    /// <summary>Variação pronta, esperando a checagem do texto.</summary>
    private sealed record PendingCheck(Guid VarID, int Index, string File, List<string> Leftovers, RequestContext Ctx);

    /// <summary>Gera uma variação (com a refação automática por termo proibido). Devolve a checagem a fazer, ou null.</summary>
    private async Task<PendingCheck?> GenerateVariation(Variation v, VariationSetup s, CancellationToken ct)
    {
        var job = s.Job;
        var jobID = job.Id;
        var itemID = s.Item.Id;
        var varID = v.Id;
        if (ct.IsCancellationRequested) return null;
        _store.UpdateVariation(jobID, itemID, varID, x => { x.Status = StepStatus.Running; x.Attempts += 1; x.RetryNote = null; x.RetryAt = null; });
        var started = DateTime.UtcNow;
        var ctx = Context(job, s.Item, $"Variação v{v.Index} ({v.AxisName})", LogCategory.Variacao, s.Attempts, onStatus: (note, until) =>
            _store.UpdateVariation(jobID, itemID, varID, x =>
            {
                if (x.Status != StepStatus.Running) return;
                x.RetryNote = note;
                x.RetryAt = until;
            }));
        try
        {
            var axis = new VariationAxis(v.AxisName, v.AxisInstruction);
            var chain = s.Config.Chain(AIStage.Variation, v.ProviderOverride ?? job.VariationProvider);
            string? autoNote = null;
            var redosUsed = v.AutoRedos ?? 0;
            var ocrLeftovers = new List<string>();
            var o = s.Folder;
            var used = chain.FirstOrDefault()?.Provider ?? job.VariationProvider;
            var usedLabel = chain.FirstOrDefault()?.Label ?? used.Label();

            while (true)
            {
                var prompt = Prompts.Variation(axis, s.Item.Transcript, s.Extra, s.Direction, s.TextChanges, s.Forbidden, s.Rules,
                    JoinNotes(v.RedoNote, autoNote));
                var (result, usedModel) = await WithFallback(chain, s.Config, s.Rule, ctx,
                    async provider => ValidImage(await provider.EditImage(s.Reference, prompt, s.Aspect, ct)), ct,
                    imageOp: true, @explicit: v.ProviderOverride != null);
                var provider = usedModel.Provider;
                used = provider;
                usedLabel = usedModel.Label;
                var rel = $"variacoes/{Short(itemID)}-v{v.Index}-{Short(Guid.NewGuid())}.png";
                Paths.Ensure(Path.Combine(s.Folder, "variacoes"));
                o = Abs(jobID, rel);
                ImageTools.SaveGenerated(result, o);
                VerifySaved(o);
                _store.Update(jobID, j => j.CostUSD += _settings.ImagePrice(provider));
                _store.UpdateVariation(jobID, itemID, varID, x => x.File = rel);

                // leitura do próprio computador: termo proibido → refaz sozinho uma vez
                var target = o;
                var ocr = await Task.Run(() => LocalOCR.Text(target)) ?? "";
                ocrLeftovers = ForbiddenTerms.Found(ocr, s.Forbidden);
                if (ocrLeftovers.Count == 0 || redosUsed >= AutoRedoLimit || ct.IsCancellationRequested) break;
                redosUsed += 1;
                var redos = redosUsed;
                _store.UpdateVariation(jobID, itemID, varID, x => x.AutoRedos = redos);
                autoNote = $"Apareceu: {string.Join(", ", ocrLeftovers)}. Não escreva esses termos em nenhum lugar da imagem.";
                ctx.Log(LogLevel.Warning, $"termo proibido apareceu ({string.Join(", ", ocrLeftovers)}). Refazendo automaticamente.",
                    $"Leitura do computador:\n{ocr}");
                ctx.OnStatus?.Invoke("Refazendo: termo proibido apareceu…", null);
            }

            var usedFinal = used;
            _store.UpdateVariation(jobID, itemID, varID, x =>
            {
                x.Status = StepStatus.Done;
                x.Error = null;
                x.ErrorKind = null;
                x.ErrorDetails = null;
                x.RetryNote = null;
                x.RetryAt = null;
                x.ProviderUsed = usedFinal;
            });
            ctx.Log(LogLevel.Success, $"gerada com {usedLabel} em {Elapsed(started)}.");
            return new PendingCheck(varID, v.Index, o, ocrLeftovers, ctx);
        }
        catch (Exception error)
        {
            if (error is OperationCanceledException || ct.IsCancellationRequested)
            {
                _store.UpdateVariation(jobID, itemID, varID, x => { x.Status = StepStatus.Pending; x.RetryNote = null; x.RetryAt = null; });
                return null;
            }
            _store.UpdateVariation(jobID, itemID, varID, x =>
            {
                x.Status = StepStatus.Failed;
                x.Error = error.Message;
                x.ErrorKind = error.AiKind();
                x.ErrorDetails = error.AiDetails();
                x.RetryNote = null;
                x.RetryAt = null;
            });
            ctx.Log(LogLevel.Error, $"falhou — {error.AiKind().Title()}. {error.Message}",
                string.Join("\n", new[] { error.AiDetails(), $"Sugestão: {error.AiKind().Hint()}" }.Where(x => x != null)));
            return null;
        }
    }

    /// <summary>
    /// 4. CHECAGEM DO TEXTO de uma variação pronta: confere o texto travado e se apareceu marca.
    /// É auxiliar: falha aqui não derruba a variação.
    /// </summary>
    private async Task CheckText(Guid jobID, Guid itemID, Guid varID, int index, string file, string? transcript, List<string> removeItems,
        List<string> forbidden, List<string> ocrLeftovers, bool verify, List<ModelChoice> analysisChain, ProviderConfig config,
        FallbackRule rule, RequestContext ctx, CancellationToken ct)
    {
        var checkCtx = ctx with
        {
            Step = $"Checagem de texto v{index}",
            Category = LogCategory.Analise,
            Timeout = Http.AnalysisTimeout,
            OnStatus = null,
        };
        var warnings = new List<string>();
        if (ocrLeftovers.Count > 0) warnings.Add("Termo proibido: " + string.Join(", ", ocrLeftovers));
        if (verify && (!string.IsNullOrEmpty(transcript) || forbidden.Count > 0))
        {
            var jpeg = await Task.Run(() => ImageTools.UploadJpeg(file));
            if (jpeg != null)
            {
                try
                {
                    var prompt = Prompts.TextCheck(transcript ?? "(no text)", removeItems, forbidden);
                    var (raw, _) = await WithFallback(analysisChain, config, rule, checkCtx, p => p.Analyze(jpeg, prompt, ct), ct, quickSwitch: true);
                    _store.Update(jobID, j => j.CostUSD += _settings.PriceAnalysis);
                    var obj = JsonExtract.Object(raw) ?? new System.Text.Json.Nodes.JsonObject();
                    var match = JsonExtract.Bool(obj, "match") ?? true;
                    var diff = JsonExtract.Str(obj, "differences");
                    var brand = JsonExtract.Strings(obj, "brand_found") ?? new List<string>();
                    if (!match && !string.IsNullOrEmpty(transcript)) warnings.Add("Texto diferente: " + (diff.Length == 0 ? "verifique" : diff));
                    if (brand.Count > 0) warnings.Add("Marca apareceu: " + string.Join(", ", brand));
                }
                catch (Exception error)
                {
                    if (error is OperationCanceledException || ct.IsCancellationRequested) return;
                    checkCtx.Log(LogLevel.Warning, $"checagem não concluída (a variação foi mantida). {error.Message}", error.AiDetails());
                }
            }
        }
        if (ct.IsCancellationRequested) return;
        var joined = warnings.Count == 0 ? null : string.Join(" · ", warnings);
        _store.UpdateVariation(jobID, itemID, varID, x => x.TextWarning = joined);
        if (joined != null) checkCtx.Log(LogLevel.Warning, joined);
    }

    public static string Short(Guid id) => id.ToString("D")[..8].ToLowerInvariant();

    public static string Elapsed(DateTime since)
    {
        var s = (DateTime.UtcNow - since).TotalSeconds;
        return s < 60
            ? $"{Math.Round(s, MidpointRounding.ToEven).ToString("0", CultureInfo.InvariantCulture)}s"
            : $"{(int)s / 60}min {(int)s % 60:00}s";
    }

    /// <summary>1.0.0-beta.20: IAs que o lote realmente usa (a chave delas é obrigatória).</summary>
    public static List<ProviderKind> RequiredProviders(Job job)
    {
        if (job.IsCleanOnly) return new() { job.CleanProvider, job.AnalysisProvider };
        if (job.SkipsCleaning) return new() { job.VariationProvider, job.AnalysisProvider };
        return new() { job.CleanProvider, job.VariationProvider, job.AnalysisProvider };
    }

    public static string ProviderSummary(Job job)
    {
        if (job.IsCleanOnly) return $"limpeza: {job.CleanProvider.Label()} · análise: {job.AnalysisProvider.Label()}";
        if (job.SkipsCleaning) return $"variações: {job.VariationProvider.Label()} · análise: {job.AnalysisProvider.Label()}";
        return $"limpeza: {job.CleanProvider.Label()} · variações: {job.VariationProvider.Label()} · análise: {job.AnalysisProvider.Label()}";
    }

    /// <summary>
    /// Proporção pedida à IA: a do tamanho de saída (4:5 ou 9:16), para a imagem já nascer vertical.
    /// Lotes em "manter original" (antigos e o módulo Limpar logo) seguem a proporção de cada criativo.
    /// </summary>
    public static string Aspect(OutputSizeMode mode, int width, int height) =>
        mode.IsOriginal ? ImageTools.NearestAspectRatio(width, height) : ImageTools.NearestAspectRatio(mode.Width, mode.Height);
}
