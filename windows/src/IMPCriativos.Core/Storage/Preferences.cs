using System.Text.Json;
using System.Text.Json.Nodes;
using IMPCriativos.Core.Util;

namespace IMPCriativos.Core.Storage;

/// <summary>
/// Preferências do app em <c>%LOCALAPPDATA%\IMP Criativos\preferencias.json</c> — o equivalente do UserDefaults do Mac,
/// com as mesmas chaves e os mesmos valores de fábrica (<see cref="Register"/>). Seguro para várias threads.
/// Leitura tolerante: arquivo ausente ou estragado volta aos valores de fábrica sem derrubar o app.
/// </summary>
public sealed class Preferences
{
    private static Preferences? _shared;
    private static readonly object SharedLock = new();

    public static Preferences Shared
    {
        get
        {
            lock (SharedLock) return _shared ??= new Preferences(Paths.PreferencesFile);
        }
    }

    /// <summary>Troca a instância (testes).</summary>
    public static void Reset(Preferences? p = null)
    {
        lock (SharedLock) _shared = p;
    }

    private readonly string? _file;
    private readonly object _lock = new();
    private readonly JsonObject _values;
    private readonly Dictionary<string, JsonNode?> _defaults = new();

    public event Action<string>? Changed;

    /// <summary>Preferências guardadas em <paramref name="file"/>; null = só na memória.</summary>
    public Preferences(string? file)
    {
        _file = file;
        JsonObject? loaded = null;
        if (file != null && File.Exists(file))
        {
            try { loaded = JsonNode.Parse(File.ReadAllText(file)) as JsonObject; } catch { }
        }
        _values = loaded ?? new JsonObject();
    }

    /// <summary>Valores de fábrica (como o <c>register(defaults:)</c>): só valem enquanto a chave não foi gravada.</summary>
    public void Register(IDictionary<string, object?> defaults)
    {
        lock (_lock)
        {
            foreach (var (k, v) in defaults) _defaults[k] = ToNode(v);
        }
    }

    public bool Contains(string key)
    {
        lock (_lock) return _values.ContainsKey(key);
    }

    private JsonNode? Raw(string key)
    {
        lock (_lock)
        {
            if (_values.TryGetPropertyValue(key, out var v)) return v?.DeepClone();
            return _defaults.TryGetValue(key, out var d) ? d?.DeepClone() : null;
        }
    }

    public bool GetBool(string key)
    {
        var n = Raw(key);
        try
        {
            if (n is JsonValue v)
            {
                if (v.TryGetValue<bool>(out var b)) return b;
                if (v.TryGetValue<double>(out var d)) return d != 0;
                if (v.TryGetValue<string>(out var s)) return s is "true" or "1" or "YES";
            }
        }
        catch { }
        return false;
    }

    public int GetInt(string key)
    {
        var n = Raw(key);
        try
        {
            if (n is JsonValue v)
            {
                if (v.TryGetValue<int>(out var i)) return i;
                if (v.TryGetValue<double>(out var d)) return (int)d;
                if (v.TryGetValue<bool>(out var b)) return b ? 1 : 0;
                if (v.TryGetValue<string>(out var s) && int.TryParse(s, out var p)) return p;
            }
        }
        catch { }
        return 0;
    }

    public double GetDouble(string key)
    {
        var n = Raw(key);
        try
        {
            if (n is JsonValue v)
            {
                if (v.TryGetValue<double>(out var d)) return d;
                if (v.TryGetValue<string>(out var s) && double.TryParse(s, System.Globalization.NumberStyles.Float,
                        System.Globalization.CultureInfo.InvariantCulture, out var p)) return p;
            }
        }
        catch { }
        return 0;
    }

    public string? GetString(string key)
    {
        var n = Raw(key);
        try { return n is JsonValue v && v.TryGetValue<string>(out var s) ? s : null; }
        catch { return null; }
    }

    public DateTime? GetDate(string key)
    {
        var s = GetString(key);
        if (s == null) return null;
        try { return SwiftDateConverter.Parse(s); } catch { return null; }
    }

    /// <summary>Objeto guardado como JSON (equivalente de gravar <c>Data</c> do JSONEncoder no UserDefaults).</summary>
    public T? GetObject<T>(string key)
    {
        var n = Raw(key);
        if (n == null) return default;
        try { return n.Deserialize<T>(Json.Options); } catch { return default; }
    }

    public void Set(string key, object? value)
    {
        lock (_lock)
        {
            if (value == null) _values.Remove(key);
            else _values[key] = ToNode(value);
            Save();
        }
        Changed?.Invoke(key);
    }

    public void SetObject<T>(string key, T value)
    {
        lock (_lock)
        {
            _values[key] = JsonSerializer.SerializeToNode(value, Json.Options);
            Save();
        }
        Changed?.Invoke(key);
    }

    public void Remove(string key) => Set(key, null);

    private static JsonNode? ToNode(object? v) => v switch
    {
        null => null,
        JsonNode n => n.DeepClone(),
        DateTime d => JsonValue.Create(SwiftDateConverter.Format(d)),
        _ => JsonSerializer.SerializeToNode(v, v.GetType(), Json.Options),
    };

    private void Save()
    {
        if (_file == null) return;
        try { AtomicFile.WriteAllText(_file, _values.ToJsonString(Json.Options)); } catch { }
    }
}
