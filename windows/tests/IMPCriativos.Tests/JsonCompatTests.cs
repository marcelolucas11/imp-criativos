using System.Text.Json.Nodes;
using IMPCriativos.Core.Models;
using IMPCriativos.Core.Providers;
using IMPCriativos.Core.Util;
using Xunit;

namespace IMPCriativos.Tests;

/// <summary>Arquivos iguais aos do Mac: um .impcliente ou job.json gravado pelo Codable do Swift abre aqui e volta igual.</summary>
public class JsonCompatTests
{
    private static string Fixture(string name) => File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "fixtures", name));

    /// <summary>Compara dois JSON ignorando ordem de campos e espaços.</summary>
    private static void AssertSameJson(string expected, string actual)
    {
        var a = JsonNode.Parse(expected)!;
        var b = JsonNode.Parse(actual)!;
        Assert.True(JsonNode.DeepEquals(a, b), $"esperado:\n{a}\n\nobtido:\n{b}");
    }

    [Fact]
    public void ClientFromMacRoundTrips()
    {
        var text = Fixture("cliente-mac.impcliente");
        var p = Json.Deserialize<ClientProfile>(text)!;
        Assert.Equal("Cliente Ação", p.Name);
        Assert.Equal(Guid.Parse("0F4E8B1C-2D3A-4B5C-8D9E-112233445566"), p.Id);
        Assert.False(p.RotatesAxes);
        Assert.Equal(new DateTime(2026, 11, 20, 14, 3, 9, DateTimeKind.Utc), p.CreatedAt);
        Assert.Equal(2, p.Axes.Count);
        Assert.Equal("3D premium", p.Axes[0].Name);
        AssertSameJson(text, Json.Serialize(p));
    }

    [Fact]
    public void JobFromMacRoundTrips()
    {
        var text = Fixture("job-mac.json");
        var j = Json.Deserialize<Job>(text)!;
        Assert.Equal(JobState.Review, j.State);
        Assert.Equal(ProviderKind.Openai, j.CleanProvider);
        Assert.False(j.SizeMode.IsOriginal);
        Assert.Equal(1920, j.SizeMode.Height);
        Assert.Equal(AIErrorKind.RateLimit, j.Items[0].CleanErrorKind);
        Assert.Equal("GANHE GIROS\nSÓ HOJE", j.Items[0].Transcript);
        Assert.Equal(27, j.Items[0].Variations[0].AxisNumber);
        Assert.True(j.IsAxisTest);
        Assert.Equal(0.164, j.CostUSD);
        AssertSameJson(text, Json.Serialize(j));
    }

    [Fact]
    public void OriginalSizeModeUsesSwiftShape()
    {
        var s = Json.Serialize(OutputSizeMode.Original, indented: false);
        Assert.Equal("""{"original":{}}""", s);
        Assert.True(Json.Deserialize<OutputSizeMode>(s)!.IsOriginal);
    }

    [Fact]
    public void MissingFieldsUseDefaults()
    {
        var p = Json.Deserialize<ClientProfile>("""{"name":"X","id":"0F4E8B1C-2D3A-4B5C-8D9E-112233445566"}""")!;
        Assert.Equal("X", p.Name);
        Assert.True(p.RotatesAxes);
        Assert.Empty(p.Axes);
        var v = Json.Deserialize<Variation>("""{"index":3,"status":"algo-novo"}""")!;
        Assert.Equal(3, v.Index);
        Assert.Equal(StepStatus.Pending, v.Status);
    }

    [Fact]
    public void GuidsAndDatesUseSwiftFormat()
    {
        var p = ClientProfile.NewProfile("A");
        p.CreatedAt = new DateTime(2026, 1, 2, 3, 4, 5, 678, DateTimeKind.Utc);
        var node = JsonNode.Parse(Json.Serialize(p))!;
        Assert.Equal("2026-01-02T03:04:05Z", (string?)node["createdAt"]);
        var id = (string?)node["id"];
        Assert.Equal(id, id!.ToUpperInvariant());
    }

    [Fact]
    public void DefaultAxesFingerprintMatchesCatalog()
    {
        // a lista padrão atual nunca pode ser confundida com uma lista antiga
        Assert.False(ClientProfile.NewProfile().UsesOutdatedDefaultAxes);
        Assert.Equal(50, AxisCatalog.BuiltIn.Length);
        Assert.Equal(Enumerable.Range(1, 50), AxisCatalog.BuiltIn.Select(a => a.Number));
    }
}
