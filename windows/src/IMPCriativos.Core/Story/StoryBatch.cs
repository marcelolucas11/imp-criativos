using System.Globalization;
using System.IO.Compression;
using System.Security.Cryptography;
using IMPCriativos.Core.Pipeline;
using IMPCriativos.Core.Storage;
using SkiaSharp;

namespace IMPCriativos.Core.Story;

/// <summary>
/// 1.0.0-beta.21: estado do Otimizador em Lote (Stories 9:16) — lista de imagens, opções, fila e preview.
/// Fica num objeto único do app (não na tela), então o lote continua rodando se você trocar de aba.
/// Não usa IA, não tem revisão e não gera custo. Só um resumo vai para o Histórico.
/// </summary>
public sealed class StoryBatch
{
    public static StoryBatch Shared { get; } = new();

    public const int MaxItems = 100;
    /// <summary>Imagens processadas ao mesmo tempo (não trava a tela nem estoura a memória).</summary>
    public const int Concurrency = 4;
    public static readonly HashSet<string> Accepted = new(StringComparer.OrdinalIgnoreCase) { "jpg", "jpeg", "png", "webp", "heic", "heif" };

    private const string OptionsKey = "storyOptimizer.options";
    private const string FolderKey = "storyOptimizer.outputFolder";

    public enum StatusKind { Pending, Processing, Done, Failed, Cancelled }

    public sealed record Status(StatusKind Kind, string? Message = null)
    {
        public static readonly Status Pending = new(StatusKind.Pending);
        public static readonly Status Processing = new(StatusKind.Processing);
        public static readonly Status Done = new(StatusKind.Done);
        public static readonly Status Cancelled = new(StatusKind.Cancelled);
        public static Status Failed(string msg) => new(StatusKind.Failed, msg);

        public string Label => Kind switch
        {
            StatusKind.Pending => "Aguardando",
            StatusKind.Processing => "Processando",
            StatusKind.Done => "Pronto",
            StatusKind.Failed => $"Erro: {Message}",
            _ => "Cancelado",
        };

        public bool IsFinished => Kind is StatusKind.Done or StatusKind.Failed;
    }

    public sealed class Item
    {
        public Guid Id { get; } = Guid.NewGuid();
        public string Path { get; init; } = "";
        public ulong Seed { get; set; }
        public Status Status { get; set; } = Status.Pending;
        public string? Output { get; set; }
        public int? Bytes { get; set; }
        public string? Summary { get; set; }
        /// <summary>1.0.0-beta.22: versões desta imagem já gravadas.</summary>
        public int DoneVersions { get; set; }
        public string FileName => System.IO.Path.GetFileName(Path);
    }

    private readonly object _lock = new();
    private readonly List<Item> _items = new();
    private StoryOptions _options;
    private Guid? _selectedID;
    private int _previewVersion = 1;
    private bool _inspecting;
    private CancellationTokenSource? _runCts;
    private CancellationTokenSource? _previewCts;
    private (string Path, SKBitmap Image)? _previewSource;

    /// <summary>Algo mudou (lista, progresso, aviso, preview). Pode chegar de qualquer thread.</summary>
    public event Action? Changed;

    private void Notify() => Changed?.Invoke();

    private StoryBatch()
    {
        _options = Preferences.Shared.GetObject<StoryOptions>(OptionsKey) ?? new StoryOptions();
        var saved = Preferences.Shared.GetString(FolderKey);
        OutputFolder = saved != null && Directory.Exists(saved)
            ? saved
            : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");
    }

    public List<Item> Items
    {
        get { lock (_lock) return _items.ToList(); }
    }

    public StoryOptions Options
    {
        get { lock (_lock) return _options.Clone(); }
        set
        {
            lock (_lock)
            {
                if (value.Equals(_options)) return;
                _options = value.Clone();
                if (_previewVersion > _options.Versions) _previewVersion = _options.Versions;
            }
            Preferences.Shared.SetObject(OptionsKey, value);
            RefreshPreview();
            Notify();
        }
    }

    /// <summary>Muda as opções no lugar (atalho para a tela).</summary>
    public void Edit(Action<StoryOptions> change)
    {
        var o = Options;
        change(o);
        Options = o;
    }

    public string? OutputFolder { get; private set; }

    public void SetOutputFolder(string path)
    {
        OutputFolder = path;
        Preferences.Shared.Set(FolderKey, path);
        Notify();
    }

    public bool Running { get; private set; }
    public bool Cancelling { get; private set; }
    public string? LastRunFolder { get; private set; }
    public bool Zipping { get; private set; }
    /// <summary>1.0.0-beta.22: arquivos do lote (imagens × versões) e quantos já terminaram.</summary>
    public int TotalOutputs { get; private set; }
    public int ProcessedOutputs { get; private set; }
    public int WrittenOutputs { get; private set; }
    public string? Notice { get; set; }

    public Guid? SelectedID
    {
        get => _selectedID;
        set
        {
            if (_selectedID == value) return;
            _selectedID = value;
            RefreshPreview();
            Notify();
        }
    }

    /// <summary>Versão mostrada no preview (1…versões por imagem).</summary>
    public int PreviewVersion
    {
        get => _previewVersion;
        set
        {
            if (_previewVersion == value) return;
            _previewVersion = value;
            RefreshPreview();
            Notify();
        }
    }

    // preview (RGBX 1080×1920 ou a própria imagem de origem)
    public SKBitmap? PreviewBefore { get; private set; }
    public byte[]? PreviewAfter { get; private set; }
    public string PreviewSummary { get; private set; } = "";
    public bool PreviewLoading { get; private set; }
    public byte[]? InspectOriginal { get; private set; }
    public byte[]? InspectPlain { get; private set; }

    /// <summary>1.0.0-beta.23: modal de inspeção Antes / Depois aberto (desenha as referências em 1080×1920).</summary>
    public bool Inspecting
    {
        get => _inspecting;
        set
        {
            if (_inspecting == value) return;
            _inspecting = value;
            if (value) RefreshPreview();
            else { InspectOriginal = null; InspectPlain = null; }
            Notify();
        }
    }

    public Item? Selected
    {
        get { lock (_lock) return _items.FirstOrDefault(i => i.Id == _selectedID); }
    }

    public int DoneCount { get { lock (_lock) return _items.Count(i => i.Status.Kind == StatusKind.Done); } }
    public int FailedCount { get { lock (_lock) return _items.Count(i => i.Status.Kind == StatusKind.Failed); } }
    public int FinishedCount { get { lock (_lock) return _items.Count(i => i.Status.IsFinished); } }

    private static ulong NewSeed()
    {
        Span<byte> b = stackalloc byte[8];
        ulong v;
        do { RandomNumberGenerator.Fill(b); v = BitConverter.ToUInt64(b); } while (v == 0);
        return v;
    }

    // MARK: - Lista

    /// <summary>Adiciona arquivos (ou pastas, que são abertas) até o limite de 100.</summary>
    public void Add(IEnumerable<string> paths)
    {
        if (Running) return;
        var candidates = new List<string>();
        var unsupported = 0;
        foreach (var p in paths)
        {
            if (Directory.Exists(p)) candidates.AddRange(Paths.ListImages(p));
            else if (Accepted.Contains(Paths.Ext(p))) candidates.Add(p);
            else unsupported++;
        }
        int added = 0, duplicated = 0, overLimit = 0;
        lock (_lock)
        {
            var known = _items.Select(i => Path.GetFullPath(i.Path).ToLowerInvariant()).ToHashSet();
            foreach (var p in candidates)
            {
                var key = Path.GetFullPath(p).ToLowerInvariant();
                if (known.Contains(key)) { duplicated++; continue; }
                if (_items.Count >= MaxItems) { overLimit++; continue; }
                _items.Add(new Item { Path = p, Seed = NewSeed() });
                known.Add(key);
                added++;
            }
        }
        var parts = new List<string>();
        if (overLimit > 0) parts.Add($"Limite de {MaxItems} imagens por lote: {overLimit} ficaram de fora.");
        if (duplicated > 0) parts.Add($"{duplicated} já estavam na lista.");
        if (unsupported > 0) parts.Add($"{unsupported} arquivo(s) ignorado(s) — aceita JPG, PNG, WebP e HEIC.");
        Notice = parts.Count == 0 ? null : string.Join(" ", parts);
        if (added > 0) ResetResults();
        if (_selectedID == null || Selected == null)
        {
            lock (_lock) _selectedID = _items.FirstOrDefault()?.Id;
            RefreshPreview();
        }
        Notify();
    }

    public void Remove(Guid id)
    {
        if (Running) return;
        lock (_lock) _items.RemoveAll(i => i.Id == id);
        if (_selectedID == id)
        {
            lock (_lock) _selectedID = _items.FirstOrDefault()?.Id;
            RefreshPreview();
        }
        Notify();
    }

    public void Clear()
    {
        if (Running) return;
        lock (_lock) _items.Clear();
        _selectedID = null;
        LastRunFolder = null;
        Notice = null;
        _previewSource = null;
        PreviewBefore = null;
        PreviewAfter = null;
        PreviewSummary = "";
        Notify();
    }

    /// <summary>Troca a semente de uma imagem (outro sorteio dentro dos mesmos limites).</summary>
    public void Reroll(Guid id)
    {
        if (Running) return;
        lock (_lock)
        {
            var it = _items.FirstOrDefault(i => i.Id == id);
            if (it == null) return;
            it.Seed = NewSeed();
        }
        RefreshPreview();
        Notify();
    }

    private void ResetResults()
    {
        lock (_lock)
        {
            foreach (var i in _items.Where(i => i.Status.Kind != StatusKind.Pending))
            {
                i.Status = Status.Pending;
                i.Output = null;
                i.Bytes = null;
                i.Summary = null;
                i.DoneVersions = 0;
            }
        }
        ProcessedOutputs = 0;
        WrittenOutputs = 0;
        TotalOutputs = 0;
    }

    // MARK: - Fila

    /// <summary>Começa o lote. Devolve a tarefa (o teste de fumaça espera por ela).</summary>
    public Task Start()
    {
        if (Running || Items.Count == 0) return Task.CompletedTask;
        if (OutputFolder is not string @base) { Notice = "Escolha a pasta de saída."; Notify(); return Task.CompletedTask; }
        var stamp = DateTime.Now.ToString("yyyy-MM-dd_HHmmss", CultureInfo.InvariantCulture);
        var dest = Path.Combine(@base, $"stories_{stamp}");
        try { Directory.CreateDirectory(dest); }
        catch (Exception e)
        {
            Notice = $"Não consegui criar a pasta de saída: {e.Message}";
            Notify();
            return Task.CompletedTask;
        }

        ResetResults();
        Notice = null;
        LastRunFolder = dest;
        Running = true;
        Cancelling = false;

        var opts = Options;
        var items = Items;
        var total = items.Count;
        var versions = opts.Versions;
        var jobs = new List<(Guid Id, string Path, StoryParams Params, string Name)>();
        // 1.0.0-beta.22: cada imagem sai em N versões, cada uma com o seu sorteio (a versão 1 é a do preview)
        for (var index = 0; index < items.Count; index++)
        {
            for (var v = 1; v <= versions; v++)
            {
                var p = StoryParams.Sample(opts, StoryVersions.Seed(items[index].Seed, v));
                var name = StoryNames.FileName(index + 1, total, opts.Prefix, p.Code, opts.Naming, opts.Format.FileExtension(),
                    versions > 1 ? v : null);
                jobs.Add((items[index].Id, items[index].Path, p, name));
            }
        }
        TotalOutputs = jobs.Count;
        var started = DateTime.UtcNow;
        AppLog.Info(LogCategory.Exportacao, $"Otimizador em Lote: {total} imagem(ns) × {versions} versão(ões) → {Path.GetFileName(dest)}",
            details: $"Enquadramento: {opts.Fit.Label()} · Intensidade: {opts.Intensity.Label()} · Linhas: " +
                     (opts.LinesEnabled ? $"{opts.LineStyle.Label()}, {opts.LineDirection.Label().ToLower(new CultureInfo("pt-BR"))}" : "não") +
                     $" · Texturas: {opts.TexturePreset.Label()} · Formato: {opts.Format.Label()}{(opts.Mirror ? " · espelhado" : "")}");
        Notify();

        var cts = new CancellationTokenSource();
        _runCts = cts;
        var ct = cts.Token;
        return Task.Run(async () =>
        {
            await BoundedParallel.Run(jobs, Concurrency, async job =>
            {
                if (ct.IsCancellationRequested) return (object?)null;
                Update(job.Id, null, i => { if (i.Status.Kind == StatusKind.Pending) i.Status = Status.Processing; });
                var output = Path.Combine(dest, job.Name);
                try
                {
                    var bytes = await Task.Run(() => StoryOptimizer.Process(job.Path, opts, job.Params, output));
                    Update(job.Id, true, i =>
                    {
                        i.DoneVersions++;
                        if (i.Output == null)
                        {
                            i.Output = output;
                            i.Bytes = bytes;
                            i.Summary = job.Params.Summary;
                        }
                        if (i.DoneVersions >= versions && i.Status.Kind == StatusKind.Processing) i.Status = Status.Done;
                    });
                }
                catch (Exception e)
                {
                    var msg = e is StoryOptimizer.Failure ? e.Message
                        : Imaging.ImageTools.IsHeic(job.Path) && Imaging.ImageTools.Extension?.UnsupportedMessage(job.Path) is string hm ? hm
                        : e.Message;
                    Update(job.Id, false, i => i.Status = Status.Failed(msg));
                }
                return null;
            }, (object _) => Task.CompletedTask, ct);
            FinishRun(started);
        });
    }

    public void Cancel()
    {
        if (!Running) return;
        Cancelling = true;
        _runCts?.Cancel();
        Notify();
    }

    private void Update(Guid id, bool? written, Action<Item> change)
    {
        lock (_lock)
        {
            if (written is bool w)
            {
                ProcessedOutputs++;
                if (w) WrittenOutputs++;
            }
            var it = _items.FirstOrDefault(i => i.Id == id);
            if (it != null) change(it);
        }
        Notify();
    }

    /// <summary>Avisa no fim do lote (o App mostra a notificação se a janela não estiver em foco).</summary>
    public static Func<bool>? AppIsActive { get; set; }

    private void FinishRun(DateTime started)
    {
        lock (_lock)
            foreach (var i in _items.Where(i => !i.Status.IsFinished)) i.Status = Status.Cancelled;
        var wasCancelled = Cancelling;
        Running = false;
        Cancelling = false;
        _runCts = null;
        var seconds = (int)Math.Round((DateTime.UtcNow - started).TotalSeconds, MidpointRounding.AwayFromZero);
        int done = DoneCount, failed = FailedCount, count = Items.Count;
        var text = TotalOutputs > count
            ? $"{WrittenOutputs} de {TotalOutputs} arquivos ({done} de {count} imagens completas) em {seconds}s"
            : $"{done} de {count} imagens prontas em {seconds}s";
        if (failed > 0) text += $" · {failed} com erro";
        if (wasCancelled) text += " · lote cancelado";
        Notice = text + ".";
        var failures = Items.Where(i => i.Status.Kind == StatusKind.Failed).Select(i => $"{i.FileName}: {i.Status.Message}").ToList();
        if (failed > 0 || wasCancelled)
            AppLog.Warning(LogCategory.Exportacao, $"Otimizador em Lote: {text}", details: failures.Count == 0 ? null : string.Join("\n", failures));
        else
            AppLog.Success(LogCategory.Exportacao, $"Otimizador em Lote: {text}", details: LastRunFolder);
        if (!(AppIsActive?.Invoke() ?? true)) Notifier.Post("Otimizador em Lote", text);
        Notify();
    }

    // MARK: - ZIP

    /// <summary>Compacta a pasta do último lote (Baixar Tudo .ZIP). Devolve null se deu certo, ou o erro.</summary>
    public async Task<string?> MakeZip(string target)
    {
        if (Running || Zipping || LastRunFolder is not string folder) return "Nada para compactar.";
        Zipping = true;
        Notify();
        var failure = await Task.Run(() =>
        {
            try
            {
                if (File.Exists(target)) File.Delete(target);
                ZipFile.CreateFromDirectory(folder, target, CompressionLevel.Optimal, includeBaseDirectory: true);
                return null;
            }
            catch (Exception e) { return e.Message; }
        });
        Zipping = false;
        if (failure != null)
        {
            Notice = $"Não consegui criar o ZIP: {failure}";
            AppLog.Error(LogCategory.Exportacao, "Otimizador em Lote: falha ao criar o ZIP", details: failure);
        }
        else
        {
            Notice = $"ZIP salvo: {Path.GetFileName(target)}";
        }
        Notify();
        return failure;
    }

    // MARK: - Preview

    /// <summary>Redesenha o antes/depois da imagem selecionada com as opções atuais (mesma semente do arquivo final).</summary>
    public void RefreshPreview()
    {
        _previewCts?.Cancel();
        var item = Selected;
        if (item == null)
        {
            PreviewBefore = null;
            PreviewAfter = null;
            PreviewSummary = "";
            PreviewLoading = false;
            InspectOriginal = null;
            InspectPlain = null;
            Notify();
            return;
        }
        var opts = Options;
        var inspect = _inspecting;
        var seed = StoryVersions.Seed(item.Seed, Math.Min(_previewVersion, opts.Versions));
        var path = item.Path;
        var cached = _previewSource?.Path == path ? _previewSource?.Image : null;
        PreviewLoading = true;
        var cts = new CancellationTokenSource();
        _previewCts = cts;
        Notify();
        _ = Task.Run(async () =>
        {
            // espera um instante: arrastar um slider não redesenha a cada pixel
            try { await Task.Delay(120, cts.Token); } catch { return; }
            var p = StoryParams.Sample(opts, seed);
            SKBitmap? source = cached;
            byte[]? after = null, original = null, plain = null;
            try
            {
                source ??= StoryOptimizer.LoadSource(path);
                if (source != null && !cts.IsCancellationRequested)
                {
                    after = StoryOptimizer.Preview(source, opts, p);
                    if (inspect)
                    {
                        // sem nenhuma variação (nem espelho): só o enquadramento 9:16 escolhido
                        original = StoryOptimizer.Preview(source, opts, new StoryParams());
                        // tudo igual ao arquivo final, menos as texturas — mesma geometria
                        plain = p.HasTexture ? StoryOptimizer.Preview(source, opts, p.WithoutTexture) : after;
                    }
                }
            }
            catch { }
            if (cts.IsCancellationRequested) return;
            if (source != null && !ReferenceEquals(source, cached))
            {
                        _previewSource = (path, source);
            }
            PreviewBefore = source;
            PreviewAfter = after;
            InspectOriginal = inspect ? original : null;
            InspectPlain = inspect ? plain : null;
            PreviewSummary = source == null ? "Não consegui abrir esta imagem." : p.Summary;
            PreviewLoading = false;
            Notify();
        });
    }
}
