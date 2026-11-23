using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Serialization;

namespace IMPCriativos.Core.Models;

/// <summary>Um eixo de variação: a "direção" que diferencia uma variação das outras.</summary>
public sealed class VariationAxis : IEquatable<VariationAxis>
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = "";
    public string Instruction { get; set; } = "";

    public VariationAxis() { }

    public VariationAxis(string name, string instruction, Guid? id = null)
    {
        Name = name;
        Instruction = instruction;
        if (id is Guid g) Id = g;
    }

    public VariationAxis Copy() => new(Name, Instruction, Id);

    public bool Equals(VariationAxis? o) => o != null && o.Id == Id && o.Name == Name && o.Instruction == Instruction;
    public override bool Equals(object? obj) => Equals(obj as VariationAxis);
    public override int GetHashCode() => HashCode.Combine(Id, Name, Instruction);
}

/// <summary>
/// Perfil de um cliente (operador de cassino ou bet): o que remover, como variar e instruções extras.
/// Fica salvo só no computador do usuário, nunca no repositório.
/// </summary>
public sealed class ClientProfile
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = "";
    public List<string> RemoveItems { get; set; } = new();
    public List<VariationAxis> Axes { get; set; } = new();
    public int DefaultVariations { get; set; }
    public string ExtraInstructions { get; set; } = "";
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    /// <summary>1.0.0-beta.6: instruções de lote salvas para reaproveitar.</summary>
    public List<string>? SavedInstructions { get; set; }
    /// <summary>1.0.0-beta.18: rodízio dos eixos entre os criativos do lote (null = ligado).</summary>
    public bool? AxisRotation { get; set; }

    /// <summary>Ligado: o 1º criativo usa os eixos 1–N, o 2º os seguintes… Desligado: todo criativo usa os N primeiros.</summary>
    [JsonIgnore]
    public bool RotatesAxes
    {
        get => AxisRotation ?? true;
        set => AxisRotation = value;
    }

    public static readonly string[] DefaultRemoveItems =
    {
        "Logotipo da empresa",
        "Nome da empresa (escrito em qualquer lugar da imagem)",
        "@ de Instagram ou outras redes sociais",
        "Site / endereço de internet",
        "Telefone ou WhatsApp",
        "CNPJ",
        "Marca d'água ou selo da empresa",
    };

    // Os eixos padrão (50, de cassino e bet) ficam em DefaultAxes.cs, gerado junto com docs/EIXOS-DE-VARIACAO.md.
    public static List<VariationAxis> DefaultAxes => AxisCatalog.BuiltIn.Select(a => a.Axis).ToList();

    /// <summary>
    /// Eixos padrão da beta.1 à beta.13. Guardados só para reconhecer perfis que nunca mexeram neles
    /// e trocá-los sozinhos pelos 50 eixos de cassino e bet.
    /// </summary>
    public static readonly (string Name, string Instruction)[] LegacyDefaultAxes =
    {
        ("Fundo e paleta", "Replace the background and the color palette with a fresh, vibrant combination. Keep high contrast and perfect legibility."),
        ("Composição", "Rearrange the composition: change the position and scale of the main subject (the prize/product) and of the text block."),
        ("Iluminação e clima", "Change the lighting and mood (for example: night scene with neon lights, golden sunset, or a clean studio look)."),
        ("Ângulo do prêmio", "Show the main subject from a different angle or perspective, without changing any of its real characteristics."),
        ("Estilo gráfico", "Apply a different ad graphic style (for example: 3D elements, geometric shapes, glow effects), keeping it professional and premium."),
        ("Cenário", "Place the main subject in a different setting or environment that is coherent with the theme of the ad."),
    };

    /// <summary>true quando o perfil ainda usa exatamente os eixos padrão antigos (sem nenhuma edição).</summary>
    [JsonIgnore]
    public bool UsesLegacyDefaultAxes
    {
        get
        {
            if (Axes.Count != LegacyDefaultAxes.Length) return false;
            var legacy = LegacyDefaultAxes.Select(a => $"{a.Name}|{a.Instruction}").ToHashSet();
            return Axes.Select(a => $"{a.Name}|{a.Instruction}").ToHashSet().SetEquals(legacy);
        }
    }

    /// <summary>Impressões digitais de listas padrão antigas (beta.14: os 50 eixos anteriores ao filtro de cassino online).</summary>
    public static readonly HashSet<string> OutdatedDefaultFingerprints = new()
    {
        "54cb5c1cb24a953ae611a70240bf65538ad1f2c91d830fc558642fcb1bb12f7b",
    };

    /// <summary>
    /// Impressão digital da lista de eixos, sem depender da ordem: SHA-256 de cada "nome|instrução",
    /// hashes ordenados, unidos por quebra de linha e passados de novo no SHA-256.
    /// </summary>
    public static string Fingerprint(IEnumerable<VariationAxis> axes)
    {
        static string Hex(string s) => Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(s)));
        var parts = axes.Select(a => Hex($"{a.Name}|{a.Instruction}")).OrderBy(x => x, StringComparer.Ordinal);
        return Hex(string.Join("\n", parts));
    }

    /// <summary>true quando o perfil usa uma lista padrão antiga sem edição (6 eixos até a beta.13 ou 50 da beta.14).</summary>
    [JsonIgnore]
    public bool UsesOutdatedDefaultAxes => UsesLegacyDefaultAxes || OutdatedDefaultFingerprints.Contains(Fingerprint(Axes));

    public static ClientProfile NewProfile(string name = "Novo cliente") => new()
    {
        Name = name,
        RemoveItems = DefaultRemoveItems.ToList(),
        Axes = DefaultAxes,
        DefaultVariations = 4,
        ExtraInstructions = "",
    };

    /// <summary>Nomes do perfil de exemplo, que precisam ser trocados pelos reais.</summary>
    public static readonly string[] PlaceholderTerms = { "Minha Bet", "@minhabet", "Minha Empresa Prêmios", "@minhaempresa" };

    /// <summary>1.0.0-beta.8: o perfil ainda tem os nomes de exemplo (instruções ou itens de remoção).</summary>
    [JsonIgnore]
    public bool HasPlaceholderTerms
    {
        get
        {
            var text = string.Join("\n", RemoveItems.Append(ExtraInstructions)).ToLowerInvariant();
            return PlaceholderTerms.Any(t => text.Contains(t.ToLowerInvariant()));
        }
    }

    public const string ExampleInstructions = "Troque pelos nomes reais da casa de apostas: ex. remover o nome \"Minha Bet\", o @minhabet e o site minhabet.bet.br.";
    /// <summary>Texto do perfil de exemplo até a beta.13 (trocado sozinho pelo novo).</summary>
    public const string LegacyExampleInstructions = "Troque pelos nomes reais: ex. remover o nome \"Minha Empresa Prêmios\" e o @minhaempresa.";

    public static ClientProfile Example
    {
        get
        {
            var p = NewProfile("Exemplo");
            p.ExtraInstructions = ExampleInstructions;
            return p;
        }
    }

    public ClientProfile Clone() =>
        System.Text.Json.JsonSerializer.Deserialize<ClientProfile>(
            System.Text.Json.JsonSerializer.Serialize(this, Util.Json.Compact), Util.Json.Compact)!;
}
