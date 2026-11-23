using System.Globalization;
using System.Text;

namespace IMPCriativos.Core.Storage;

/// <summary>
/// Pastas do app. No Windows: <c>%LOCALAPPDATA%\IMP Criativos</c>, com as mesmas subpastas do Mac
/// (<c>clients</c>, <c>jobs\&lt;id&gt;</c>, <c>logs</c>, <c>updates</c>, <c>eixos-personalizados.json</c>).
/// A variável de ambiente <c>IMP_CRIATIVOS_DATA</c> troca a pasta (testes e teste de fumaça).
/// </summary>
public static class Paths
{
    private static string? _override;

    /// <summary>Troca a pasta de dados (usado pelos testes e pelo --smoke-test).</summary>
    public static void OverrideRoot(string? path) => _override = path;

    public static string AppSupport
    {
        get
        {
            var root = _override ?? Environment.GetEnvironmentVariable("IMP_CRIATIVOS_DATA");
            if (string.IsNullOrWhiteSpace(root))
            {
                var baseDir = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
                if (string.IsNullOrEmpty(baseDir))
                    baseDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".local", "share");
                root = Path.Combine(baseDir, "IMP Criativos");
            }
            Directory.CreateDirectory(root);
            return root;
        }
    }

    public static string Clients => Ensure(Path.Combine(AppSupport, "clients"));
    public static string Jobs => Ensure(Path.Combine(AppSupport, "jobs"));
    public static string Updates => Ensure(Path.Combine(AppSupport, "updates"));
    public static string Logs => Ensure(Path.Combine(AppSupport, "logs"));

    /// <summary>1.0.0-beta.18: biblioteca de eixos personalizados do usuário (vale para todos os clientes).</summary>
    public static string CustomAxes => Path.Combine(AppSupport, "eixos-personalizados.json");

    /// <summary>Preferências (no Mac ficam no UserDefaults).</summary>
    public static string PreferencesFile => Path.Combine(AppSupport, "preferencias.json");

    public static string KeysFile => Path.Combine(AppSupport, "chaves.json");

    public static string JobFolder(Guid id) => Ensure(Path.Combine(Jobs, id.ToString("D").ToUpperInvariant()));

    public static string Ensure(string path)
    {
        try { Directory.CreateDirectory(path); } catch { }
        return path;
    }

    public static readonly HashSet<string> ImageExtensions = new(StringComparer.OrdinalIgnoreCase)
        { "jpg", "jpeg", "png", "webp", "heic", "heif" };

    public static string Ext(string path) => Path.GetExtension(path).TrimStart('.').ToLowerInvariant();

    public static List<string> ListImages(string folder)
    {
        try
        {
            return Directory.EnumerateFiles(folder)
                .Where(f => !Path.GetFileName(f).StartsWith('.'))
                .Where(f => (File.GetAttributes(f) & FileAttributes.Hidden) == 0)
                .Where(f => ImageExtensions.Contains(Ext(f)))
                .OrderBy(f => Path.GetFileName(f), NaturalComparer.Instance)
                .ToList();
        }
        catch { return new List<string>(); }
    }

    /// <summary>Tira acentos (como o <c>folding(.diacriticInsensitive)</c> do Swift).</summary>
    public static string FoldDiacritics(string s)
    {
        var norm = s.Normalize(NormalizationForm.FormD);
        var sb = new StringBuilder(norm.Length);
        foreach (var ch in norm)
            if (CharUnicodeInfo.GetUnicodeCategory(ch) != UnicodeCategory.NonSpacingMark) sb.Append(ch);
        return sb.ToString().Normalize(NormalizationForm.FormC);
    }

    /// <summary>Deixa um texto seguro para usar em nome de arquivo.</summary>
    public static string Slug(string s)
    {
        var folded = FoldDiacritics(s).ToLowerInvariant();
        var sb = new StringBuilder();
        foreach (var ch in folded)
            sb.Append(char.IsLetterOrDigit(ch) || ch == '-' || ch == '_' ? ch : '-');
        var o = sb.ToString();
        while (o.Contains("--")) o = o.Replace("--", "-");
        return o.Trim('-').ToLowerInvariant();
    }
}

/// <summary>Ordem "natural" de nomes (arquivo2 antes de arquivo10), como o <c>localizedStandardCompare</c>.</summary>
public sealed class NaturalComparer : IComparer<string>
{
    public static readonly NaturalComparer Instance = new();

    public int Compare(string? a, string? b)
    {
        a ??= ""; b ??= "";
        int i = 0, j = 0;
        while (i < a.Length && j < b.Length)
        {
            if (char.IsDigit(a[i]) && char.IsDigit(b[j]))
            {
                int si = i, sj = j;
                while (i < a.Length && char.IsDigit(a[i])) i++;
                while (j < b.Length && char.IsDigit(b[j])) j++;
                var na = a[si..i].TrimStart('0');
                var nb = b[sj..j].TrimStart('0');
                if (na.Length != nb.Length) return na.Length.CompareTo(nb.Length);
                var c = string.CompareOrdinal(na, nb);
                if (c != 0) return c;
            }
            else
            {
                var c = string.Compare(a[i].ToString(), b[j].ToString(), CultureInfo.GetCultureInfo("pt-BR"),
                    CompareOptions.IgnoreCase | CompareOptions.IgnoreNonSpace);
                if (c != 0) return c;
                i++; j++;
            }
        }
        return (a.Length - i).CompareTo(b.Length - j);
    }
}
