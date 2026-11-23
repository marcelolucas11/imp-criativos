using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using IMPCriativos.Core.Util;

namespace IMPCriativos.Core.Storage;

public enum LogLevel { Info, Success, Warning, Error }

public static class LogLevelExt
{
    public static readonly LogLevel[] All = { LogLevel.Info, LogLevel.Success, LogLevel.Warning, LogLevel.Error };

    public static string Label(this LogLevel l) => l switch
    {
        LogLevel.Info => "Info",
        LogLevel.Success => "Sucesso",
        LogLevel.Warning => "Alerta",
        _ => "Erro",
    };
}

public enum LogCategory { Lote, Limpeza, Analise, Variacao, Revisao, Exportacao, Ia, Clientes, Configuracoes, Atualizacao, Sistema }

public static class LogCategoryExt
{
    public static readonly LogCategory[] All =
    {
        LogCategory.Lote, LogCategory.Limpeza, LogCategory.Analise, LogCategory.Variacao, LogCategory.Revisao,
        LogCategory.Exportacao, LogCategory.Ia, LogCategory.Clientes, LogCategory.Configuracoes, LogCategory.Atualizacao,
        LogCategory.Sistema,
    };

    public static string Label(this LogCategory c) => c switch
    {
        LogCategory.Lote => "Lote",
        LogCategory.Limpeza => "Limpeza",
        LogCategory.Analise => "Análise",
        LogCategory.Variacao => "Variação",
        LogCategory.Revisao => "Revisão",
        LogCategory.Exportacao => "Exportação",
        LogCategory.Ia => "IA / conexão",
        LogCategory.Clientes => "Clientes",
        LogCategory.Configuracoes => "Configurações",
        LogCategory.Atualizacao => "Atualização",
        _ => "Sistema",
    };
}

public sealed class LogEntry
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public DateTime Date { get; set; } = DateTime.UtcNow;
    public LogLevel Level { get; set; }
    public LogCategory Category { get; set; }
    public string Message { get; set; } = "";
    public string? Details { get; set; }
    [JsonPropertyName("jobID")] public Guid? JobID { get; set; }
    public string? JobName { get; set; }
    public string? Item { get; set; }

    /// <summary>Linha de texto pronta para copiar e colar numa conversa de suporte.</summary>
    [JsonIgnore]
    public string PlainText
    {
        get
        {
            var s = new StringBuilder($"[{Stamp(Date)}] {Level.Label().ToUpper(new CultureInfo("pt-BR"))} · {Category.Label()}");
            if (JobName != null) s.Append($" · lote \"{JobName}\"");
            if (Item != null) s.Append($" · {Item}");
            s.Append($"\n  {Message}");
            if (!string.IsNullOrEmpty(Details)) s.Append("\n  " + Details.Replace("\n", "\n  "));
            return s.ToString();
        }
    }

    public static string Stamp(DateTime d) =>
        d.ToLocalTime().ToString("dd/MM/yyyy HH:mm:ss", CultureInfo.InvariantCulture);
}

/// <summary>
/// Histórico de movimentações, edições e erros.
/// Um arquivo JSON Lines por mês em <c>IMP Criativos\logs</c> (guarda 6 meses). Pode ser chamado de qualquer thread.
/// </summary>
public sealed class ActivityLog
{
    private static ActivityLog? _shared;
    private static readonly object SharedLock = new();

    public static ActivityLog Shared
    {
        get { lock (SharedLock) return _shared ??= new ActivityLog(); }
    }

    /// <summary>Recria o histórico (testes; troca de pasta de dados).</summary>
    public static void Reset()
    {
        lock (SharedLock) _shared = null;
    }

    private readonly object _lock = new();
    private readonly object _writeLock = new();
    private readonly List<LogEntry> _entries;
    private const int MaxInMemory = 15_000;
    private const int RetentionMonths = 6;

    public DateTime LastSeen { get; private set; }

    /// <summary>Uma entrada nova (já na lista). Pode chegar de qualquer thread.</summary>
    public event Action<LogEntry>? Added;
    public event Action? Cleared;

    public static string Folder => Paths.Logs;

    private ActivityLog()
    {
        LastSeen = Preferences.Shared.GetDate("logLastSeen") ?? DateTime.UtcNow;
        _entries = LoadFromDisk();
    }

    /// <summary>Mais recentes primeiro (cópia).</summary>
    public List<LogEntry> Entries
    {
        get { lock (_lock) return new List<LogEntry>(_entries); }
    }

    /// <summary>Erros desde a última vez que a tela Histórico foi aberta (para o selo no menu lateral).</summary>
    public int UnseenErrors
    {
        get
        {
            lock (_lock)
            {
                var n = 0;
                foreach (var e in _entries)
                {
                    if (e.Date <= LastSeen) break;
                    if (e.Level == LogLevel.Error) n++;
                }
                return n;
            }
        }
    }

    public void MarkSeen()
    {
        LastSeen = DateTime.UtcNow;
        Preferences.Shared.Set("logLastSeen", LastSeen);
    }

    public void Add(LogLevel level, LogCategory category, string message, string? details = null,
        Guid? jobID = null, string? jobName = null, string? item = null)
    {
        var entry = new LogEntry
        {
            Level = level, Category = category, Message = message, Details = details,
            JobID = jobID, JobName = jobName, Item = item,
        };
        lock (_lock)
        {
            _entries.Insert(0, entry);
            if (_entries.Count > MaxInMemory) _entries.RemoveRange(MaxInMemory, _entries.Count - MaxInMemory);
        }
        Write(entry);
        Added?.Invoke(entry);
    }

    public void Clear()
    {
        lock (_writeLock)
        {
            try
            {
                foreach (var f in Directory.EnumerateFiles(Folder)) try { File.Delete(f); } catch { }
            }
            catch { }
        }
        lock (_lock) _entries.Clear();
        MarkSeen();
        Cleared?.Invoke();
    }

    private static string FileFor(DateTime d) =>
        Path.Combine(Folder, d.ToLocalTime().ToString("yyyy-MM", CultureInfo.InvariantCulture) + ".jsonl");

    private void Write(LogEntry entry)
    {
        try
        {
            var line = JsonSerializer.Serialize(entry, Json.Compact) + "\n";
            lock (_writeLock) File.AppendAllText(FileFor(entry.Date), line, new UTF8Encoding(false));
        }
        catch { }
    }

    private static List<LogEntry> LoadFromDisk()
    {
        var files = new List<string>();
        try
        {
            files = Directory.EnumerateFiles(Folder, "*.jsonl")
                .OrderByDescending(f => Path.GetFileName(f), StringComparer.Ordinal).ToList();
        }
        catch { }
        // apaga meses além da retenção
        foreach (var old in files.Skip(RetentionMonths)) try { File.Delete(old); } catch { }

        var o = new List<LogEntry>();
        foreach (var file in files.Take(RetentionMonths))
        {
            string[] lines;
            try { lines = File.ReadAllLines(file); } catch { continue; }
            var month = new List<LogEntry>();
            foreach (var line in lines)
            {
                if (string.IsNullOrWhiteSpace(line)) continue;
                var e = Json.TryDeserialize<LogEntry>(line);
                if (e != null) month.Add(e);
            }
            month.Reverse();
            o.AddRange(month);
            if (o.Count >= MaxInMemory) break;
        }
        return o.Take(MaxInMemory).ToList();
    }
}

/// <summary>Atalhos para registrar no histórico.</summary>
public static class AppLog
{
    public static void Info(LogCategory c, string m, string? details = null, Guid? jobID = null, string? jobName = null, string? item = null) =>
        ActivityLog.Shared.Add(LogLevel.Info, c, m, details, jobID, jobName, item);

    public static void Success(LogCategory c, string m, string? details = null, Guid? jobID = null, string? jobName = null, string? item = null) =>
        ActivityLog.Shared.Add(LogLevel.Success, c, m, details, jobID, jobName, item);

    public static void Warning(LogCategory c, string m, string? details = null, Guid? jobID = null, string? jobName = null, string? item = null) =>
        ActivityLog.Shared.Add(LogLevel.Warning, c, m, details, jobID, jobName, item);

    public static void Error(LogCategory c, string m, string? details = null, Guid? jobID = null, string? jobName = null, string? item = null) =>
        ActivityLog.Shared.Add(LogLevel.Error, c, m, details, jobID, jobName, item);
}
