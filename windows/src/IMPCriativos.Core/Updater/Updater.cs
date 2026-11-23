using System.Diagnostics;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;
using IMPCriativos.Core.Pipeline;
using IMPCriativos.Core.Providers;
using IMPCriativos.Core.Storage;

namespace IMPCriativos.Core.Updates;

/// <summary>Versão no formato 1.2.3 ou 1.2.3-beta.4 (mesma regra do <c>SemVer</c> do Mac).</summary>
public sealed class SemVer : IComparable<SemVer>
{
    public int Major { get; }
    public int Minor { get; }
    public int Patch { get; }
    public string[] Pre { get; }

    private SemVer(int major, int minor, int patch, string[] pre)
    {
        Major = major; Minor = minor; Patch = patch; Pre = pre;
    }

    /// <summary>null quando não é número de versão (ex.: as tags fixas "mac" e "windows").</summary>
    public static SemVer? Parse(string? raw)
    {
        if (raw == null) return null;
        var s = raw.Trim();
        if (s.StartsWith('v') || s.StartsWith('V')) s = s[1..];
        var parts = s.Split('-', 2);
        var nums = parts[0].Split('.', StringSplitOptions.RemoveEmptyEntries)
            .Select(x => int.TryParse(x, System.Globalization.NumberStyles.None, null, out var n) ? (int?)n : null)
            .Where(n => n != null).Select(n => n!.Value).ToList();
        if (nums.Count < 1) return null;
        var pre = parts.Length > 1 ? parts[1].Split('.', StringSplitOptions.RemoveEmptyEntries) : Array.Empty<string>();
        return new SemVer(nums[0], nums.Count > 1 ? nums[1] : 0, nums.Count > 2 ? nums[2] : 0, pre);
    }

    public override string ToString() => $"{Major}.{Minor}.{Patch}" + (Pre.Length == 0 ? "" : "-" + string.Join(".", Pre));

    public int CompareTo(SemVer? b)
    {
        if (b == null) return 1;
        if (Major != b.Major) return Major.CompareTo(b.Major);
        if (Minor != b.Minor) return Minor.CompareTo(b.Minor);
        if (Patch != b.Patch) return Patch.CompareTo(b.Patch);
        if ((Pre.Length == 0) != (b.Pre.Length == 0)) return Pre.Length == 0 ? 1 : -1; // beta < final
        foreach (var (x, y) in Pre.Zip(b.Pre))
        {
            if (x == y) continue;
            if (int.TryParse(x, out var xi) && int.TryParse(y, out var yi)) return xi.CompareTo(yi);
            return string.CompareOrdinal(x, y) < 0 ? -1 : 1;
        }
        return Pre.Length.CompareTo(b.Pre.Length);
    }

    public static bool operator >(SemVer a, SemVer b) => a.CompareTo(b) > 0;
    public static bool operator <(SemVer a, SemVer b) => a.CompareTo(b) < 0;
}

public sealed record ReleaseInfo(string Version, string Tag, string Notes, string InstallerUrl, string? ChecksumUrl, string? PageUrl, bool Prerelease);

public static class AppInfo
{
    public static string Version
    {
        get
        {
            var v = Assembly.GetEntryAssembly()?.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion
                    ?? typeof(AppInfo).Assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion
                    ?? "0.0.0";
            var plus = v.IndexOf('+');
            return plus >= 0 ? v[..plus] : v;
        }
    }

    public const string UpdateRepo = "marcelolucas11/imp-criativos";

    /// <summary>Nome do instalador de uma versão nas Releases (o atualizador só considera Releases que o têm).</summary>
    public static string InstallerName(string version) => $"IMP-Criativos-Setup-{version}-windows-x64.exe";
}

/// <summary>
/// Busca versões novas nas Releases do GitHub, confere a integridade (SHA-256) e roda o instalador em modo silencioso.
/// Mesma lógica do <c>Updater.swift</c>: compara SemVer com beta, respeita "incluir betas", ignora rascunhos
/// e as tags fixas "mac" e "windows" (não são número de versão).
/// </summary>
public sealed class Updater
{
    public enum StateKind { Idle, Checking, UpToDate, Available, Downloading, Installing, Failed }

    public StateKind State { get; private set; } = StateKind.Idle;
    public ReleaseInfo? AvailableRelease { get; private set; }
    public string? Error { get; private set; }
    public DateTime? LastChecked { get; private set; }

    public event Action? Changed;

    /// <summary>Fecha o app depois de abrir o instalador (o App liga; o instalador reabre o app no fim).</summary>
    public Action? QuitForUpdate { get; set; }

    private void Set(StateKind s, string? error = null)
    {
        State = s;
        Error = error;
        Changed?.Invoke();
    }

    /// <summary>Escolhe a melhor Release (exposto para os testes).</summary>
    public static ReleaseInfo? PickBest(JsonArray list, string currentVersion, bool includeBeta)
    {
        var current = SemVer.Parse(currentVersion) ?? SemVer.Parse("0.0.0")!;
        (SemVer V, ReleaseInfo Info)? best = null;
        foreach (var r in list.OfType<JsonObject>())
        {
            if (JsonExtract.Bool(r, "draft") == true) continue;
            var pre = JsonExtract.Bool(r, "prerelease") ?? false;
            if (pre && !includeBeta) continue;
            var tag = JsonExtract.OptStr(r, "tag_name");
            // as tags fixas "mac" e "windows" não são número de versão: SemVer.Parse dá null e a Release é ignorada
            if (tag == null || SemVer.Parse(tag) is not SemVer v || !(v > current)) continue;
            var assets = (r["assets"] as JsonArray ?? new JsonArray()).OfType<JsonObject>().ToList();
            string? Asset(string name) => assets.FirstOrDefault(a => JsonExtract.OptStr(a, "name") == name) is JsonObject a
                ? JsonExtract.OptStr(a, "browser_download_url") : null;
            var exeName = AppInfo.InstallerName(v.ToString());
            if (Asset(exeName) is not string exe) continue;
            var info = new ReleaseInfo(v.ToString(), tag, JsonExtract.Str(r, "body"), exe, Asset(exeName + ".sha256"),
                JsonExtract.OptStr(r, "html_url"), pre);
            if (best == null || v > best.Value.V) best = (v, info);
        }
        return best?.Info;
    }

    public async Task Check(bool includeBeta, bool silent = false)
    {
        if (!silent) Set(StateKind.Checking);
        try
        {
            var req = new HttpRequestMessage(HttpMethod.Get, $"https://api.github.com/repos/{AppInfo.UpdateRepo}/releases?per_page=20");
            req.Headers.TryAddWithoutValidation("Accept", "application/vnd.github+json");
            req.Headers.TryAddWithoutValidation("User-Agent", $"IMP-Criativos-Windows/{AppInfo.Version}");
            var data = await Http.Send(req, "GitHub · releases", attempts: 2);
            if (Http.Json(data) is not JsonArray list) throw new AIError("Resposta inesperada do GitHub.");
            var best = PickBest(list, AppInfo.Version, includeBeta);
            LastChecked = DateTime.UtcNow;
            if (best != null)
            {
                AvailableRelease = best;
                Set(StateKind.Available);
                AppLog.Info(LogCategory.Atualizacao, $"Versão {best.Version} disponível (instalada: {AppInfo.Version}).");
                if (silent) Notifier.Post("Atualização disponível", $"IMP Criativos {best.Version} está pronto para instalar.");
            }
            else if (!silent)
            {
                Set(StateKind.UpToDate);
            }
        }
        catch (Exception e)
        {
            if (!silent) Set(StateKind.Failed, $"Não foi possível buscar atualizações: {e.Message}");
            AppLog.Warning(LogCategory.Atualizacao, $"Não foi possível buscar atualizações: {e.Message}", details: e.AiDetails());
        }
    }

    public async Task Install(ReleaseInfo release)
    {
        Set(StateKind.Downloading);
        AppLog.Info(LogCategory.Atualizacao, $"Baixando a versão {release.Version}…");
        try
        {
            var work = Path.Combine(Paths.Updates, release.Version);
            try { if (Directory.Exists(work)) Directory.Delete(work, true); } catch { }
            Directory.CreateDirectory(work);

            // 1. baixa o instalador
            var exe = Path.Combine(work, AppInfo.InstallerName(release.Version));
            using (var resp = await Http.Client.GetAsync(release.InstallerUrl, HttpCompletionOption.ResponseHeadersRead))
            {
                if (!resp.IsSuccessStatusCode) throw new AIError("Falha ao baixar a atualização.");
                await using var fs = File.Create(exe);
                await resp.Content.CopyToAsync(fs);
            }

            // 2. confere a integridade (SHA-256 publicado junto na Release). Sem ele, cancela.
            if (release.ChecksumUrl == null)
                throw new AIError("A versão publicada não tem o arquivo de conferência (.sha256). Atualização cancelada.");
            var sumData = await Http.Send(new HttpRequestMessage(HttpMethod.Get, release.ChecksumUrl), "GitHub · checksum", attempts: 2);
            var expected = Encoding.UTF8.GetString(sumData).Split(new[] { ' ', '\n', '\r', '\t' }, StringSplitOptions.RemoveEmptyEntries)
                .FirstOrDefault()?.ToLowerInvariant() ?? "";
            string actual;
            await using (var fs = File.OpenRead(exe)) actual = Convert.ToHexStringLower(await SHA256.HashDataAsync(fs));
            if (expected.Length == 0 || expected != actual)
                throw new AIError("O arquivo baixado não confere com a versão publicada. Atualização cancelada.");

            Set(StateKind.Installing);

            // 3. roda o instalador em modo silencioso; ele fecha este app, instala e reabre no fim
            Process.Start(new ProcessStartInfo
            {
                FileName = exe,
                Arguments = "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /CLOSEAPPLICATIONS",
                UseShellExecute = true,
            });
            AppLog.Success(LogCategory.Atualizacao, $"Versão {release.Version} baixada; instalando e reiniciando o app.");
            QuitForUpdate?.Invoke();
        }
        catch (Exception e)
        {
            Set(StateKind.Failed, e.Message);
            AppLog.Error(LogCategory.Atualizacao, $"Falha ao instalar a versão {release.Version}: {e.Message}", details: e.AiDetails());
        }
    }
}
