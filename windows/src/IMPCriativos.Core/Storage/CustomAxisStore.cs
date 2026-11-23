using IMPCriativos.Core.Models;
using IMPCriativos.Core.Util;

namespace IMPCriativos.Core.Storage;

/// <summary>
/// Eixo criado pelo usuário, guardado na biblioteca "Meus eixos" (vale para todos os clientes).
/// O <see cref="Id"/> é o mesmo do <see cref="VariationAxis"/> que entra na lista do cliente, para saber o que está marcado.
/// </summary>
public sealed class CustomAxis
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = "";
    public string Instruction { get; set; } = "";
    /// <summary>"O que muda", em poucas palavras (opcional).</summary>
    public string Note { get; set; } = "";
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    [System.Text.Json.Serialization.JsonIgnore]
    public VariationAxis Axis => new(Name, Instruction, Id);
}

/// <summary>Biblioteca de eixos personalizados (1.0.0-beta.18), em <c>eixos-personalizados.json</c>.</summary>
public sealed class CustomAxisStore
{
    private sealed class FileContent
    {
        public List<CustomAxis> Axes { get; set; } = new();
        /// <summary>Eixos apagados da biblioteca: não voltam sozinhos quando um cliente que ainda os usa é salvo.</summary>
        public List<string> Dismissed { get; set; } = new();
    }

    private readonly object _lock = new();
    private List<CustomAxis> _axes = new();
    private HashSet<string> _dismissed = new();
    private const string PlaceholderInstruction = "Describe how this variation should differ.";

    public event Action? Changed;

    public CustomAxisStore() { Load(); }

    public List<CustomAxis> Axes
    {
        get { lock (_lock) return _axes.ToList(); }
    }

    public bool FileExists => File.Exists(Paths.CustomAxes);

    public void Load()
    {
        var content = Json.TryReadFile<FileContent>(Paths.CustomAxes);
        if (content == null) return;
        lock (_lock)
        {
            _axes = content.Axes;
            _dismissed = content.Dismissed.ToHashSet();
        }
    }

    private void Persist()
    {
        FileContent content;
        lock (_lock)
            content = new FileContent { Axes = _axes.ToList(), Dismissed = _dismissed.OrderBy(x => x, StringComparer.Ordinal).ToList() };
        try { Json.WriteFile(Paths.CustomAxes, content); } catch { }
        Changed?.Invoke();
    }

    /// <summary>
    /// Na primeira vez, traz para a biblioteca os eixos personalizados que já estão nos clientes
    /// (tudo o que não é do catálogo do app nem da lista padrão antiga).
    /// </summary>
    public void SeedIfNeeded(IEnumerable<ClientProfile> clients)
    {
        if (FileExists) return;
        foreach (var p in clients) Absorb(p.Axes, save: false);
        Persist();
        int n;
        lock (_lock) n = _axes.Count;
        if (n > 0) AppLog.Info(LogCategory.Clientes, $"{n} eixos personalizados dos clientes foram para \"Meus eixos\".");
    }

    /// <summary>Guarda na biblioteca os eixos personalizados de uma lista (chamado ao salvar um cliente).</summary>
    public void Absorb(IEnumerable<VariationAxis> list, bool save = true)
    {
        var changed = false;
        lock (_lock)
        {
            foreach (var axis in list.Where(IsCustom))
            {
                var name = axis.Name.Trim();
                var instruction = axis.Instruction.Trim();
                if (instruction.Length == 0 || instruction == PlaceholderInstruction || _dismissed.Contains(Key(axis))
                    || _axes.Any(a => a.Id == axis.Id || a.Instruction == instruction)) continue;
                _axes.Add(new CustomAxis { Id = axis.Id, Name = name.Length == 0 ? "Sem nome" : name, Instruction = instruction });
                changed = true;
            }
        }
        if (changed && save) Persist();
    }

    /// <summary>Eixo que não é do catálogo do app.</summary>
    public static bool IsCustom(VariationAxis axis) => AxisCatalog.Entry(axis) == null;

    public CustomAxis Add(string name = "Novo eixo", string instruction = "", string note = "")
    {
        var axis = new CustomAxis { Name = name, Instruction = instruction, Note = note };
        lock (_lock) _axes.Add(axis);
        Persist();
        return axis;
    }

    public void Update(CustomAxis axis)
    {
        lock (_lock)
        {
            var i = _axes.FindIndex(a => a.Id == axis.Id);
            if (i < 0) return;
            _axes[i] = axis;
        }
        Persist();
    }

    public void Delete(CustomAxis axis)
    {
        lock (_lock)
        {
            _axes.RemoveAll(a => a.Id == axis.Id);
            _dismissed.Add(Key(axis.Axis));
        }
        Persist();
    }

    private static string Key(VariationAxis axis) => axis.Instruction.Trim();
}
