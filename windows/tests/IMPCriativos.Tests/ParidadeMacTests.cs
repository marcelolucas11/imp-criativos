using System.Globalization;
using System.Text.Json;
using IMPCriativos.Core.Models;
using IMPCriativos.Core.Pipeline;
using IMPCriativos.Core.Storage;
using IMPCriativos.Core.Story;
using Xunit;
using Xunit.Abstractions;

namespace IMPCriativos.Tests;

/// <summary>
/// Paridade com o Mac: <c>fixtures/paridade-mac.json</c> é gerado pelo próprio código Swift (scripts/paridade, no CI do Mac).
/// Aqui o C# gera os mesmos prompts, textos e sorteios e precisa dar exatamente o mesmo resultado.
/// </summary>
[Collection("Preferencias")]
public class ParidadeMacTests
{
    private readonly ITestOutputHelper _out;
    public ParidadeMacTests(ITestOutputHelper output) { _out = output; }

    private static string D(double v) => v.ToString("R", CultureInfo.InvariantCulture);

    /// <summary>Os mesmos casos de scripts/paridade/main.swift.</summary>
    public static Dictionary<string, string> Generate()
    {
        var o = new Dictionary<string, string>();
        var prefs = new Preferences(null);
        Preferences.Reset(prefs);
        try
        {
            foreach (var keep in new[] { false, true })
            {
                prefs.Set(Niche.KeepNoticesKey, keep);
                var k = keep ? "manter" : "remover";
                o[$"niche.noticesRule.{k}"] = Niche.NoticesRule;
                var plan = new CreativePlan
                {
                    ForbiddenTerms = new() { "AVIATOR", "@marca" }, OriginalText = "AVIATOR\nGANHE GIROS", FinalText = "GANHE GIROS",
                    CleanInstruction = "Erase the AVIATOR logo at the top.", VariationRules = "Keep the red plane.", Doubts = "", Model = "m",
                    NeedsCleaning = true,
                };
                o[$"prompts.cleanFromPlan.{k}"] = Prompts.CleanFromPlan(plan, "  tirar o selo ", "ficou borrado");
                o[$"prompts.cleanFromPlan.vazio.{k}"] = Prompts.CleanFromPlan(new CreativePlan { CleanInstruction = "x" }, "", null);
                o[$"prompts.clean.{k}"] = Prompts.Clean(new[] { "Logotipo da empresa", "CNPJ" }, "sem o selo", "Trocar \"R$ 10\" por \"R$ 5\"",
                    new[] { "MARCA" }, "refazer");
                o[$"prompts.clean.min.{k}"] = Prompts.Clean(new[] { "Logo" }, "", redoNote: null);
                o[$"prompts.analysis.{k}"] = Prompts.Analysis(new[] { "Logo" }, "", new[] { "X1" });
                o[$"prompts.analysis.changes.{k}"] = Prompts.Analysis(new[] { "Logo", "Site" }, "Incluir \"Nome\"", Array.Empty<string>());
                var axis = new VariationAxis("Neon", "Complete redesign with neon.");
                o[$"prompts.variation.{k}"] = Prompts.Variation(axis, "  GANHE GIROS\nSÓ HOJE ", "extra", "mais escuro", "",
                    new[] { "AVIATOR" }, "Keep the plane.", "a b");
                o[$"prompts.variation.changes.{k}"] = Prompts.Variation(axis, null, "", textChanges: "Incluir \"Y\"", redoNote: null);
                o[$"prompts.variation.semtexto.{k}"] = Prompts.Variation(axis, "", "", redoNote: null);
                o[$"prompts.textCheck.{k}"] = Prompts.TextCheck("GANHE GIROS", new[] { "Logo" }, new[] { "AVIATOR" });
                o[$"prompts.neutral.{k}"] = Prompts.Neutral("PROMPT");
                var ins = new BatchInstructions
                {
                    Raw = " tirar aviator ", RemoveItems = new() { "Palavra \"Aviator\"" }, TextChanges = "Trocar A por B", Direction = "noite",
                };
                o[$"planner.prompt.{k}"] = CreativePlanner.Prompt(new[] { "Logo", "@x" }, " fixo ", ins);
                o[$"planner.prompt.vazio.{k}"] = CreativePlanner.Prompt(Array.Empty<string>(), "", null);
            }
        }
        finally
        {
            Preferences.Reset();
        }
        o["niche.promptContext"] = Niche.PromptContext;
        o["niche.mainSubject"] = Niche.MainSubject;
        o["niche.characterRules"] = Niche.CharacterRules;
        o["niche.coherenceRules"] = Niche.CoherenceRules;
        o["instructions.prompt"] = InstructionInterpreter.Prompt("tirar o nome Aviator\ne deixar à noite");
        o["forbidden.fallback"] = string.Join("|", ForbiddenTerms.Fallback(new[]
        {
            "Nome da empresa (escrito em qualquer lugar da imagem)", "Palavra \"Aviator\"", "nome Fortune Tiger",
            "Logotipo da empresa", "Blaze, Stake e KTO", "o @minhabet",
        }));
        o["forbidden.found"] = string.Join("|", ForbiddenTerms.Found("Jogue AVI ATOR agora! fera", new[] { "Aviator", "Ferramenta", "fera" }));
        o["forbidden.strip"] = ForbiddenTerms.Strip(new[] { "AVIATOR" }, "GOSTA DE AVIATOR ?\nAVIATOR\nJOGUE  JÁ");
        o["forbidden.normalize"] = ForbiddenTerms.Normalize("Ação — ＡＢＣ @Marca.com!");

        var cases = new List<(string, StoryOptions)>();
        foreach (var i in StoryLabels.Intensities)
            cases.Add(($"int-{Raw(i)}", new StoryOptions { Intensity = i }));
        foreach (var preset in StoryLabels.Presets)
        foreach (var style in StoryLabels.Styles)
        {
            var opt = new StoryOptions { Intensity = StoryIntensity.Normal };
            opt.SelectTexturePreset(preset);
            opt.SetLinesEnabled(true);
            opt.LineStyle = style;
            opt.LineDirection = style == StoryLineStyle.Ink ? StoryLineDirection.Cross : StoryLineDirection.Random;
            cases.Add(($"tex-{Raw(preset)}-{Raw(style)}", opt));
        }
        cases.Add(("png-agressivo", new StoryOptions { Format = StoryOutputFormat.Png, Intensity = StoryIntensity.Aggressive, Mirror = true }));
        foreach (var (name, opt) in cases)
        foreach (var seed in new ulong[] { 1, 42, 123_456_789, 18_446_744_073_709_551_557 })
        foreach (var v in new[] { 1, 3 })
        {
            var p = StoryParams.Sample(opt, StoryVersions.Seed(seed, v));
            var f = new[]
            {
                D(p.CropFraction), D(p.CropShiftX), D(p.CropShiftY), D(p.RotationDegrees), D(p.Brightness), D(p.Contrast),
                D(p.Saturation), D(p.NoiseAmplitude), D(p.NoiseOffsetX), D(p.NoiseOffsetY), p.ChromaticChannel is ChromaticChannel c ? Raw(c) : "nil",
                $"{p.ChromaticDX}", $"{p.ChromaticDY}", D(p.GrainOpacity), B(p.GrainSoftLight), D(p.GrainOffsetX), D(p.GrainOffsetY),
                D(p.SharpenIntensity), D(p.SoftenRadius), B(p.Mirror), string.Join(",", p.Perspective.Select(D)), D(p.PerspectiveMax),
                D(p.TemperatureKelvin), D(p.DiagonalAmplitude), $"{p.DiagonalPeriod}", B(p.DiagonalAnti), $"{p.DiagonalPhase}",
                D(p.Vignette), D(p.LineOpacity), $"{p.LineSpacing}", $"{p.LineThickness}", Raw(p.LineDirection), Raw(p.LineBlend),
                $"{p.LinePhase}", $"{p.LinePhase2}", Raw(p.LineStyle), D(p.LineAngle), D(p.LineIrregularity), $"{p.LineSeed}",
                D(p.JitterLevel), $"{p.JitterSeed}", $"{p.AberrationDX}", $"{p.AberrationDY}", D(p.BloomLevel), D(p.BlurAngle),
                $"{p.Quality}", B(p.Progressive), B(p.Chroma444), p.Code,
            };
            o[$"params.{name}.{seed}.v{v}"] = string.Join(";", f);
            o[$"summary.{name}.{seed}.v{v}"] = p.Summary;
        }
        return o;
    }

    private static string B(bool b) => b ? "true" : "false";
    private static string Raw<T>(T v) where T : struct, Enum => Core.Util.TolerantEnumConverterFactory.RawValue(v);

    /// <summary>Compara um campo do sorteio: números pelo valor (o Swift imprime "0.0", o C# "0").</summary>
    private static bool SameField(string a, string b)
    {
        if (a == b) return true;
        var pa = a.Split(',');
        var pb = b.Split(',');
        if (pa.Length != pb.Length) return false;
        for (var i = 0; i < pa.Length; i++)
        {
            if (pa[i] == pb[i]) continue;
            if (!double.TryParse(pa[i], NumberStyles.Float, CultureInfo.InvariantCulture, out var x) ||
                !double.TryParse(pb[i], NumberStyles.Float, CultureInfo.InvariantCulture, out var y) || x != y) return false;
        }
        return true;
    }

    [Fact]
    public void MatchesMacOutput()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "fixtures", "paridade-mac.json");
        if (!File.Exists(path))
        {
            _out.WriteLine("paridade-mac.json ainda não foi gerado pelo CI do Mac — teste pulado.");
            return;
        }
        var mac = JsonSerializer.Deserialize<Dictionary<string, string>>(File.ReadAllText(path))!;
        var win = Generate();
        var problems = new List<string>();
        foreach (var (key, expected) in mac)
        {
            if (!win.TryGetValue(key, out var actual)) { problems.Add($"{key}: falta no Windows"); continue; }
            if (key.StartsWith("params."))
            {
                var ea = expected.Split(';');
                var aa = actual.Split(';');
                if (ea.Length != aa.Length || ea.Where((e, i) => !SameField(e, aa[i])).Any())
                    problems.Add($"{key}:\n  Mac:     {expected}\n  Windows: {actual}");
            }
            else if (expected != actual)
            {
                var i = 0;
                while (i < Math.Min(expected.Length, actual.Length) && expected[i] == actual[i]) i++;
                problems.Add($"{key}: difere na posição {i}\n  Mac:     …{Excerpt(expected, i)}\n  Windows: …{Excerpt(actual, i)}");
            }
        }
        foreach (var key in win.Keys.Where(k => !mac.ContainsKey(k))) problems.Add($"{key}: falta no Mac");
        Assert.True(problems.Count == 0, string.Join("\n\n", problems.Take(30)));
    }

    private static string Excerpt(string s, int i) =>
        s.Substring(Math.Max(0, i - 30), Math.Min(80, s.Length - Math.Max(0, i - 30))).Replace("\n", "⏎");

    /// <summary>Grava o que o Windows gera (artefato do CI, para comparar à mão).</summary>
    [Fact]
    public void WritesWindowsOutput()
    {
        var dir = Environment.GetEnvironmentVariable("IMP_PARIDADE_OUT");
        if (string.IsNullOrEmpty(dir)) return;
        Directory.CreateDirectory(dir);
        File.WriteAllText(Path.Combine(dir, "paridade-windows.json"),
            JsonSerializer.Serialize(new SortedDictionary<string, string>(Generate()), new JsonSerializerOptions { WriteIndented = true }));
    }
}

[CollectionDefinition("Preferencias", DisableParallelization = true)]
public class PreferenciasCollection { }
