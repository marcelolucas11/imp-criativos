using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using IMPCriativos.Core.Models;

namespace IMPCriativos.Core.Storage;

/// <summary>
/// Guarda as chaves de API num arquivo só deste usuário: <c>%LOCALAPPDATA%\IMP Criativos\chaves.json</c>.
/// No Windows o conteúdo é cifrado pelo DPAPI do próprio Windows (<c>ProtectedData</c>, escopo CurrentUser):
/// só a sua conta, neste computador, consegue ler. As chaves nunca saem do computador, a não ser para o Google ou a OpenAI.
///
/// Formato: <c>{"dpapi": "&lt;base64&gt;"}</c>, onde o base64 é o JSON <c>{"gemini": "...", "openai": "..."}</c> cifrado.
/// Fora do Windows (testes no Linux) grava o JSON sem cifra, como o Mac.
/// </summary>
public static class ApiKeyStore
{
    private static readonly object Lock = new();
    private static Dictionary<string, string>? _cache;
    private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("IMP Criativos · chaves de API");

    private static string FileUrl => Paths.KeysFile;

    /// <summary>Esquece o que está na memória (testes; troca de pasta de dados).</summary>
    public static void ResetCache()
    {
        lock (Lock) _cache = null;
    }

    public static void Save(string value, ProviderKind provider)
    {
        var trimmed = value.Trim();
        lock (Lock)
        {
            var keys = LoadAllLocked();
            if (trimmed.Length == 0) keys.Remove(provider.Raw()); else keys[provider.Raw()] = trimmed;
            WriteLocked(keys);
        }
    }

    public static string? Load(ProviderKind provider)
    {
        lock (Lock)
        {
            return LoadAllLocked().TryGetValue(provider.Raw(), out var s) && !string.IsNullOrEmpty(s) ? s : null;
        }
    }

    public static void Delete(ProviderKind provider)
    {
        lock (Lock)
        {
            var keys = LoadAllLocked();
            if (!keys.Remove(provider.Raw())) return;
            try { WriteLocked(keys); } catch { }
        }
    }

    public static bool HasKey(ProviderKind provider) => Load(provider) != null;

    private static Dictionary<string, string> LoadAllLocked()
    {
        if (_cache != null) return _cache;
        var keys = new Dictionary<string, string>();
        try
        {
            if (File.Exists(FileUrl))
            {
                var node = JsonNode.Parse(File.ReadAllText(FileUrl)) as JsonObject;
                if (node?["dpapi"] is JsonValue v && v.TryGetValue<string>(out var b64))
                {
                    var plain = Unprotect(Convert.FromBase64String(b64));
                    keys = JsonSerializer.Deserialize<Dictionary<string, string>>(plain) ?? new();
                }
                else if (node != null)
                {
                    foreach (var (k, val) in node)
                        if (val is JsonValue sv && sv.TryGetValue<string>(out var s)) keys[k] = s;
                }
            }
        }
        catch
        {
            // arquivo de outra conta ou estragado: começa vazio (basta colar as chaves de novo em Configurações)
            keys = new Dictionary<string, string>();
        }
        _cache = keys;
        return keys;
    }

    private static void WriteLocked(Dictionary<string, string> keys)
    {
        try
        {
            var json = JsonSerializer.SerializeToUtf8Bytes(keys);
            string text;
            if (OperatingSystem.IsWindows())
                text = new JsonObject { ["dpapi"] = Convert.ToBase64String(Protect(json)) }.ToJsonString();
            else
                text = Encoding.UTF8.GetString(json);
            Util.AtomicFile.WriteAllText(FileUrl, text);
            if (!OperatingSystem.IsWindows())
            {
                try { File.SetUnixFileMode(FileUrl, UnixFileMode.UserRead | UnixFileMode.UserWrite); } catch { }
            }
            _cache = keys;
        }
        catch (Exception e)
        {
            throw new IOException($"Não foi possível salvar a chave ({e.Message}).", e);
        }
    }

    private static byte[] Protect(byte[] data)
    {
        if (!OperatingSystem.IsWindows()) return data;
        return ProtectedData.Protect(data, Entropy, DataProtectionScope.CurrentUser);
    }

    private static byte[] Unprotect(byte[] data)
    {
        if (!OperatingSystem.IsWindows()) return data;
        return ProtectedData.Unprotect(data, Entropy, DataProtectionScope.CurrentUser);
    }
}
