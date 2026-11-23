using System.Globalization;
using IMPCriativos.Core.Models;
using IMPCriativos.Core.Util;

namespace IMPCriativos.Core.Storage;

/// <summary>Perfis de clientes, um arquivo JSON por cliente em <c>IMP Criativos\clients</c>.</summary>
public sealed class ClientStore
{
    private readonly object _lock = new();
    private List<ClientProfile> _clients = new();

    public event Action? Changed;

    private static readonly StringComparer NameOrder = StringComparer.Create(new CultureInfo("pt-BR"), CompareOptions.IgnoreCase);

    public ClientStore()
    {
        Load();
        if (Clients.Count == 0) Save(ClientProfile.Example);
        MigrateLegacyDefaults();
    }

    /// <summary>Cópias dos perfis, em ordem alfabética.</summary>
    public List<ClientProfile> Clients
    {
        get { lock (_lock) return _clients.Select(c => c.Clone()).ToList(); }
    }

    /// <summary>
    /// 1.0.0-beta.14/15 (app só de cassino online e bet): perfis que ainda têm uma lista padrão antiga sem nenhuma
    /// edição passam a usar os eixos padrão atuais; o texto do perfil de exemplo antigo é atualizado.
    /// </summary>
    public void MigrateLegacyDefaults()
    {
        foreach (var profile in Clients)
        {
            var changed = false;
            if (profile.UsesOutdatedDefaultAxes)
            {
                profile.Axes = ClientProfile.DefaultAxes;
                changed = true;
            }
            if (profile.ExtraInstructions == ClientProfile.LegacyExampleInstructions)
            {
                profile.ExtraInstructions = ClientProfile.ExampleInstructions;
                changed = true;
            }
            if (changed)
            {
                Save(profile);
                AppLog.Info(LogCategory.Clientes,
                    $"Cliente \"{profile.Name}\" passou a usar os {ClientProfile.DefaultAxes.Count} eixos padrão de cassino e bet.");
            }
        }
    }

    public void Load()
    {
        var list = new List<ClientProfile>();
        try
        {
            foreach (var f in Directory.EnumerateFiles(Paths.Clients, "*.json"))
            {
                var p = Json.TryReadFile<ClientProfile>(f);
                if (p != null) list.Add(p);
            }
        }
        catch { }
        lock (_lock) _clients = list.OrderBy(c => c.Name, NameOrder).ToList();
        Changed?.Invoke();
    }

    public void Save(ClientProfile profile)
    {
        var copy = profile.Clone();
        try { Json.WriteFile(Path.Combine(Paths.Clients, $"{copy.Id.ToString("D").ToUpperInvariant()}.json"), copy); } catch { }
        lock (_lock)
        {
            var i = _clients.FindIndex(c => c.Id == copy.Id);
            if (i >= 0) _clients[i] = copy; else _clients.Add(copy);
            _clients = _clients.OrderBy(c => c.Name, NameOrder).ToList();
        }
        Changed?.Invoke();
    }

    public void Delete(ClientProfile profile)
    {
        try { File.Delete(Path.Combine(Paths.Clients, $"{profile.Id.ToString("D").ToUpperInvariant()}.json")); } catch { }
        lock (_lock) _clients.RemoveAll(c => c.Id == profile.Id);
        Changed?.Invoke();
    }

    public ClientProfile? Client(Guid? id)
    {
        if (id is not Guid g) return null;
        lock (_lock) return _clients.FirstOrDefault(c => c.Id == g)?.Clone();
    }

    // MARK: exportar / importar (.impcliente) — para trocar perfis entre sócios (Mac ↔ Windows)

    public void Export(ClientProfile profile, string path) => Json.WriteFile(path, profile);

    public ClientProfile ImportProfile(string path)
    {
        var p = Json.Deserialize<ClientProfile>(File.ReadAllText(path)) ?? throw new InvalidDataException("Arquivo de cliente inválido.");
        bool exists;
        lock (_lock) exists = _clients.Any(c => c.Id == p.Id);
        if (exists)
        {
            p.Id = Guid.NewGuid();
            p.Name += " (importado)";
        }
        Save(p);
        return p;
    }
}
