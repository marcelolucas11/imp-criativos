using System.Globalization;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;

namespace IMPCriativos.Core.Util;

/// <summary>
/// JSON no mesmo formato que o <c>Codable</c> do Swift grava no Mac:
/// nomes de campo em camelCase (iguais às propriedades Swift), UUID em maiúsculas, datas ISO 8601 sem fração
/// ("2026-11-23T20:07:13Z"), enums pelo nome e campos opcionais vazios omitidos.
/// A leitura é tolerante: campo ausente fica com o valor padrão; campo a mais é ignorado.
/// </summary>
public static class Json
{
    public static readonly JsonSerializerOptions Options = Create(indented: true);
    public static readonly JsonSerializerOptions Compact = Create(indented: false);

    public static JsonSerializerOptions Create(bool indented)
    {
        var o = new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
            DictionaryKeyPolicy = null,
            DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
            WriteIndented = indented,
            PropertyNameCaseInsensitive = false,
            NumberHandling = JsonNumberHandling.AllowNamedFloatingPointLiterals,
            Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
            ReadCommentHandling = JsonCommentHandling.Skip,
            AllowTrailingCommas = true,
            UnmappedMemberHandling = JsonUnmappedMemberHandling.Skip,
        };
        o.Converters.Add(new SwiftDateConverter());
        o.Converters.Add(new SwiftNullableDateConverter());
        o.Converters.Add(new SwiftGuidConverter());
        o.Converters.Add(new SwiftNullableGuidConverter());
        o.Converters.Add(new TolerantEnumConverterFactory());
        return o;
    }

    public static string Serialize<T>(T value, bool indented = true) =>
        JsonSerializer.Serialize(value, indented ? Options : Compact);

    public static T? Deserialize<T>(string text) => JsonSerializer.Deserialize<T>(text, Options);

    public static T? TryDeserialize<T>(string text)
    {
        try { return JsonSerializer.Deserialize<T>(text, Options); }
        catch { return default; }
    }

    public static T? TryReadFile<T>(string path)
    {
        try { return File.Exists(path) ? JsonSerializer.Deserialize<T>(File.ReadAllText(path), Options) : default; }
        catch { return default; }
    }

    /// <summary>Grava de forma atômica (arquivo temporário + troca), como o <c>.atomic</c> do Swift.</summary>
    public static void WriteFile<T>(string path, T value, bool indented = true) =>
        AtomicFile.WriteAllText(path, Serialize(value, indented));

    /// <summary>Lê JSON livre (respostas das IAs, da API do GitHub).</summary>
    public static JsonNode? Parse(string text)
    {
        try { return JsonNode.Parse(text); } catch { return null; }
    }
}

/// <summary>Data ISO 8601 em UTC, sem fração de segundo (formato do <c>.iso8601</c> do JSONEncoder).</summary>
public sealed class SwiftDateConverter : JsonConverter<DateTime>
{
    public static string Format(DateTime d) =>
        d.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture);

    public static DateTime Parse(string s) =>
        DateTime.Parse(s, CultureInfo.InvariantCulture, DateTimeStyles.AdjustToUniversal | DateTimeStyles.AssumeUniversal);

    public override DateTime Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        if (reader.TokenType == JsonTokenType.String)
        {
            var s = reader.GetString() ?? "";
            return Parse(s);
        }
        if (reader.TokenType == JsonTokenType.Number)
        {
            // datas gravadas com a estratégia padrão do Swift: segundos desde 01/01/2001
            var secs = reader.GetDouble();
            return new DateTime(2001, 1, 1, 0, 0, 0, DateTimeKind.Utc).AddSeconds(secs);
        }
        throw new JsonException("Data inválida");
    }

    public override void Write(Utf8JsonWriter writer, DateTime value, JsonSerializerOptions options) =>
        writer.WriteStringValue(Format(value));
}

public sealed class SwiftNullableDateConverter : JsonConverter<DateTime?>
{
    private static readonly SwiftDateConverter Inner = new();

    public override DateTime? Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        if (reader.TokenType == JsonTokenType.Null) return null;
        try { return Inner.Read(ref reader, typeof(DateTime), options); }
        catch { return null; }
    }

    public override void Write(Utf8JsonWriter writer, DateTime? value, JsonSerializerOptions options)
    {
        if (value is null) writer.WriteNullValue();
        else Inner.Write(writer, value.Value, options);
    }
}

/// <summary>UUID em maiúsculas, como o <c>UUID.uuidString</c> do Swift.</summary>
public sealed class SwiftGuidConverter : JsonConverter<Guid>
{
    public override Guid Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        var s = reader.GetString();
        return Guid.TryParse(s, out var g) ? g : Guid.NewGuid();
    }

    public override void Write(Utf8JsonWriter writer, Guid value, JsonSerializerOptions options) =>
        writer.WriteStringValue(value.ToString("D").ToUpperInvariant());
}

public sealed class SwiftNullableGuidConverter : JsonConverter<Guid?>
{
    public override Guid? Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        if (reader.TokenType == JsonTokenType.Null) return null;
        var s = reader.GetString();
        return Guid.TryParse(s, out var g) ? g : null;
    }

    public override void Write(Utf8JsonWriter writer, Guid? value, JsonSerializerOptions options)
    {
        if (value is null) writer.WriteNullValue();
        else writer.WriteStringValue(value.Value.ToString("D").ToUpperInvariant());
    }
}

/// <summary>
/// Enums pelo nome em camelCase (o mesmo <c>rawValue</c> do Swift: "rateLimit", "blurFit"…),
/// ou pelo nome indicado em <see cref="JsonStringEnumMemberNameAttribute"/>.
/// Valor desconhecido (de uma versão mais nova) vira o padrão do enum em vez de derrubar a leitura.
/// </summary>
public sealed class TolerantEnumConverterFactory : JsonConverterFactory
{
    public override bool CanConvert(Type typeToConvert) =>
        typeToConvert.IsEnum || (Nullable.GetUnderlyingType(typeToConvert)?.IsEnum ?? false);

    public override JsonConverter CreateConverter(Type typeToConvert, JsonSerializerOptions options)
    {
        var under = Nullable.GetUnderlyingType(typeToConvert);
        if (under != null)
            return (JsonConverter)Activator.CreateInstance(typeof(NullableEnumConverter<>).MakeGenericType(under))!;
        return (JsonConverter)Activator.CreateInstance(typeof(EnumConverter<>).MakeGenericType(typeToConvert))!;
    }

    internal static class Names<T> where T : struct, Enum
    {
        public static readonly Dictionary<T, string> ToName = new();
        public static readonly Dictionary<string, T> FromName = new(StringComparer.Ordinal);

        static Names()
        {
            foreach (var f in typeof(T).GetFields(System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Static))
            {
                var value = (T)f.GetValue(null)!;
                var attr = (JsonStringEnumMemberNameAttribute?)Attribute.GetCustomAttribute(f, typeof(JsonStringEnumMemberNameAttribute));
                var name = attr?.Name ?? JsonNamingPolicy.CamelCase.ConvertName(f.Name);
                ToName[value] = name;
                FromName[name] = value;
            }
        }
    }

    public static string RawValue<T>(T value) where T : struct, Enum =>
        Names<T>.ToName.TryGetValue(value, out var n) ? n : value.ToString();

    public static bool TryParse<T>(string? raw, out T value) where T : struct, Enum
    {
        if (raw != null && Names<T>.FromName.TryGetValue(raw, out value)) return true;
        value = default;
        return false;
    }

    private sealed class EnumConverter<T> : JsonConverter<T> where T : struct, Enum
    {
        public override T Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
        {
            if (reader.TokenType == JsonTokenType.String && TryParse<T>(reader.GetString(), out var v)) return v;
            if (reader.TokenType == JsonTokenType.Number && reader.TryGetInt32(out var i)) return (T)Enum.ToObject(typeof(T), i);
            return default;
        }

        public override void Write(Utf8JsonWriter writer, T value, JsonSerializerOptions options) =>
            writer.WriteStringValue(RawValue(value));

        public override T ReadAsPropertyName(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options) =>
            TryParse<T>(reader.GetString(), out var v) ? v : default;

        public override void WriteAsPropertyName(Utf8JsonWriter writer, T value, JsonSerializerOptions options) =>
            writer.WritePropertyName(RawValue(value));
    }

    private sealed class NullableEnumConverter<T> : JsonConverter<T?> where T : struct, Enum
    {
        public override T? Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
        {
            if (reader.TokenType == JsonTokenType.Null) return null;
            if (reader.TokenType == JsonTokenType.String && TryParse<T>(reader.GetString(), out var v)) return v;
            return null;
        }

        public override void Write(Utf8JsonWriter writer, T? value, JsonSerializerOptions options)
        {
            if (value is null) writer.WriteNullValue();
            else writer.WriteStringValue(RawValue(value.Value));
        }
    }
}

public static class AtomicFile
{
    public static void WriteAllText(string path, string text) => WriteAllBytes(path, System.Text.Encoding.UTF8.GetBytes(text));

    public static void WriteAllBytes(string path, byte[] data)
    {
        var dir = Path.GetDirectoryName(path);
        if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
        var tmp = path + "." + Guid.NewGuid().ToString("N")[..8] + ".tmp";
        File.WriteAllBytes(tmp, data);
        try
        {
            File.Move(tmp, path, overwrite: true);
        }
        catch
        {
            try { File.Delete(tmp); } catch { }
            throw;
        }
    }
}
