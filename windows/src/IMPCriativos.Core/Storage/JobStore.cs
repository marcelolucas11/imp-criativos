using IMPCriativos.Core.Imaging;
using IMPCriativos.Core.Models;
using IMPCriativos.Core.Util;

namespace IMPCriativos.Core.Storage;

/// <summary>
/// Lotes de processamento. Cada lote tem sua pasta em <c>IMP Criativos\jobs\&lt;id&gt;</c>
/// com o <c>job.json</c> e todas as imagens intermediárias — por isso o app retoma de onde parou.
/// Seguro para várias threads: <see cref="Get(Guid)"/> devolve uma cópia; mudanças passam por <see cref="Update"/>.
/// </summary>
public sealed class JobStore
{
    private readonly object _lock = new();
    private List<Job> _jobs = new();

    /// <summary>Algum lote mudou (id do lote; Guid.Empty = lista inteira). Pode chegar de qualquer thread.</summary>
    public event Action<Guid>? Changed;

    public JobStore() { Load(); }

    /// <summary>Cópias de todos os lotes, mais novos primeiro.</summary>
    public List<Job> Jobs
    {
        get { lock (_lock) return _jobs.Select(j => j.Clone()).ToList(); }
    }

    public void Load()
    {
        var list = new List<Job>();
        try
        {
            foreach (var dir in Directory.EnumerateDirectories(Paths.Jobs))
            {
                var j = Json.TryReadFile<Job>(Path.Combine(dir, "job.json"));
                if (j != null) list.Add(j);
            }
        }
        catch { }
        lock (_lock) _jobs = list.OrderByDescending(j => j.CreatedAt).ToList();
        Changed?.Invoke(Guid.Empty);
    }

    public Job? Get(Guid id)
    {
        lock (_lock) return _jobs.FirstOrDefault(j => j.Id == id)?.Clone();
    }

    public string Folder(Guid id) => Paths.JobFolder(id);

    public string? FilePath(Guid job, string? name) => name == null ? null : Path.Combine(Folder(job), name.Replace('/', Path.DirectorySeparatorChar));

    public void Save(Job job)
    {
        var copy = job.Clone();
        lock (_lock)
        {
            var i = _jobs.FindIndex(j => j.Id == copy.Id);
            if (i >= 0) _jobs[i] = copy; else _jobs.Insert(0, copy);
            Persist(copy);
        }
        Changed?.Invoke(copy.Id);
    }

    private void Persist(Job job)
    {
        try { Json.WriteFile(Path.Combine(Folder(job.Id), "job.json"), job); } catch { }
    }

    /// <summary>Altera um lote e salva em disco (o job.json é gravado a cada passo).</summary>
    public void Update(Guid id, Action<Job> change)
    {
        lock (_lock)
        {
            var job = _jobs.FirstOrDefault(j => j.Id == id);
            if (job == null) return;
            change(job);
            Persist(job);
        }
        Changed?.Invoke(id);
    }

    public void UpdateItem(Guid jobID, Guid itemID, Action<JobItem> change) =>
        Update(jobID, job =>
        {
            var item = job.Items.FirstOrDefault(i => i.Id == itemID);
            if (item != null) change(item);
        });

    public void UpdateVariation(Guid jobID, Guid itemID, Guid varID, Action<Variation> change) =>
        UpdateItem(jobID, itemID, item =>
        {
            var v = item.Variations.FirstOrDefault(x => x.Id == varID);
            if (v != null) change(v);
        });

    public void Delete(Guid id)
    {
        try { Directory.Delete(Folder(id), recursive: true); } catch { }
        lock (_lock) _jobs.RemoveAll(j => j.Id == id);
        Changed?.Invoke(Guid.Empty);
    }

    /// <summary>Cria um lote: copia os originais para a pasta do lote e prepara as variações.</summary>
    public Job CreateJob(string name, ClientProfile client, string inputFolder, IReadOnlyList<string> files, int variations,
        ProviderKind cleanProvider, ProviderKind variationProvider, ProviderKind analysisProvider, OutputSizeMode sizeMode,
        OutputFormat format, bool verifyText, BatchInstructions? instructions = null, bool axisTest = false,
        bool cleanOnly = false, bool skipCleaning = false)
    {
        var id = Guid.NewGuid();
        var folder = Folder(id);
        var originals = Paths.Ensure(Path.Combine(folder, "originais"));
        var axes = client.Axes.Count == 0 ? ClientProfile.DefaultAxes : client.Axes;
        var rotate = client.RotatesAxes;
        // 1.0.0-beta.19: no teste de eixos, cada criativo passa por todos os eixos da lista, na ordem
        // 1.0.0-beta.20: no módulo "Limpar logo" não há variações
        var perItem = cleanOnly ? 0 : (axisTest ? axes.Count : Math.Max(1, variations));

        var items = new List<JobItem>();
        for (var n = 0; n < files.Count; n++)
        {
            var src = files[n];
            var ext = Paths.Ext(src);
            var fileName = $"{n + 1:000}.{ext}";
            var rel = $"originais/{fileName}";
            var dst = Path.Combine(originals, fileName);
            File.Copy(src, dst, overwrite: true);
            var size = ImageTools.PixelSize(dst) ?? (1080, 1080);
            // Rodízio (beta.14; chave por cliente desde a beta.18): com 4 variações, o 1º criativo usa os eixos 1–4,
            // o 2º os eixos 5–8… e no fim da lista recomeça. Desligado: todo criativo usa os N primeiros da lista.
            var vars = new List<Variation>();
            for (var i = 0; i < perItem; i++)
            {
                var axis = axisTest ? axes[i] : axes[(rotate ? n * perItem + i : i) % axes.Count];
                vars.Add(new Variation
                {
                    Index = i + 1,
                    AxisName = axis.Name,
                    AxisInstruction = axis.Instruction,
                    AxisNumber = AxisCatalog.Entry(axis)?.Number,
                });
            }
            items.Add(new JobItem
            {
                SourceName = Path.GetFileName(src),
                OriginalFile = rel,
                PixelWidth = size.Item1,
                PixelHeight = size.Item2,
                Variations = vars,
            });
        }

        var job = new Job
        {
            Id = id,
            Name = name,
            Client = client.Clone(),
            InputFolder = inputFolder,
            CleanProvider = cleanProvider,
            VariationProvider = variationProvider,
            AnalysisProvider = analysisProvider,
            VariationsPerItem = perItem,
            SizeMode = sizeMode,
            Format = format,
            VerifyText = verifyText,
            Items = items,
            Instructions = instructions == null || instructions.IsEmpty ? null : instructions,
            AxisTest = axisTest && !cleanOnly ? true : null,
            CleanOnly = cleanOnly ? true : null,
            SkipCleaning = skipCleaning && !cleanOnly ? true : null,
        };
        Save(job);
        return job;
    }

    /// <summary>
    /// 1.0.0-beta.19 — integridade: etapa marcada como pronta cuja imagem sumiu do disco volta para a fila.
    /// Roda antes de cada rodada do lote, então nada termina "pronto" sem o arquivo existir. Devolve quantas etapas voltaram.
    /// </summary>
    public int RepairMissingFiles(Guid id)
    {
        var job = Get(id);
        if (job == null) return 0;
        bool Exists(string? rel) => rel != null && File.Exists(FilePath(id, rel)!);
        var broken = 0;
        foreach (var item in job.Items)
        {
            if (item.CleanStatus == StepStatus.Done && !Exists(item.CleanedFile)) broken++;
            broken += item.Variations.Count(v => v.Status == StepStatus.Done && !Exists(v.File));
        }
        if (broken == 0) return 0;
        Update(id, j =>
        {
            foreach (var item in j.Items)
            {
                if (item.CleanStatus == StepStatus.Done && !Exists(item.CleanedFile))
                {
                    item.CleanStatus = StepStatus.Pending;
                    item.CleanedFile = null;
                    item.AnalysisDone = false;
                    item.CleanReview = ReviewStatus.Pending;
                }
                foreach (var v in item.Variations.Where(v => v.Status == StepStatus.Done && !Exists(v.File)))
                {
                    v.Status = StepStatus.Pending;
                    v.File = null;
                    v.Review = ReviewStatus.Pending;
                }
            }
        });
        return broken;
    }

    /// <summary>Gasto (estimado) no mês corrente, somando todos os lotes.</summary>
    public double MonthCost
    {
        get
        {
            var now = DateTime.Now;
            lock (_lock)
                return _jobs.Where(j => j.CreatedAt.ToLocalTime().Year == now.Year && j.CreatedAt.ToLocalTime().Month == now.Month)
                    .Sum(j => j.CostUSD);
        }
    }
}
