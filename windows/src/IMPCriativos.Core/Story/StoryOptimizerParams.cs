using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using IMPCriativos.Core.Util;

namespace IMPCriativos.Core.Story;

// 1.0.0-beta.21: Otimizador em Lote (Stories 9:16) — opções, presets e sorteio dos parâmetros de cada imagem.
// Cópia fiel de Pipeline/StoryOptimizerParams.swift: o SplitMix64 e a ORDEM dos sorteios são os mesmos,
// então a mesma semente dá os mesmos parâmetros no Mac e no Windows (conferido pelo teste de paridade).

/// <summary>SplitMix64: mesma semente → mesma sequência de números.</summary>
public struct SeededRandom
{
    private ulong _state;

    public SeededRandom(ulong seed) { _state = seed; }

    public ulong Next()
    {
        unchecked
        {
            _state += 0x9E3779B97F4A7C15UL;
            var z = _state;
            z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9UL;
            z = (z ^ (z >> 27)) * 0x94D049BB133111EBUL;
            return z ^ (z >> 31);
        }
    }

    /// <summary>
    /// Igual ao <c>Double.random(in: 0..&lt;1, using:)</c> do Swift: 53 bits do gerador × 2⁻⁵³
    /// (<c>next() &amp; (1 &lt;&lt; 53 − 1)</c> vezes <c>ulpOfOne / 2</c>).
    /// </summary>
    public double NextUnit() => (Next() & ((1UL << 53) - 1)) * (1.0 / 9007199254740992.0);
}

internal static class R
{
    /// <summary>Arredondamento do Swift (<c>.rounded()</c>): metade para longe do zero.</summary>
    public static double Round(double v) => Math.Round(v, MidpointRounding.AwayFromZero);
    public static double Clamp(double v, double lo, double hi) => double.IsFinite(v) ? Math.Min(Math.Max(v, lo), hi) : lo;
}

// MARK: - Opções da tela

public enum StoryFit { Cover, BlurFit, Solid }

public enum StorySolidColor { Black, Dominant, Custom }

public enum StoryIntensity { Light, Moderate, Normal, Aggressive, Custom }

public enum StoryOutputFormat { Jpg, Png }

public enum StoryNaming { Sequential, SequentialCode }

/// <summary>Direção das linhas diagonais. <c>Random</c> sorteia \, / ou X por imagem.</summary>
public enum StoryLineDirection { Backslash, Slash, Cross, Random }

/// <summary>1.0.0-beta.25: estilo das linhas — Tom (mantém a cor) ou Gravura (preto e branco).</summary>
public enum StoryLineStyle { Tone, Ink }

/// <summary>Modo de mistura das linhas da Gravura.</summary>
public enum StoryLineBlend { HardLight, Overlay }

public enum StoryTexturePreset { Off, Subtle, Balanced, Intense, Custom }

public static class StoryLabels
{
    public static readonly StoryFit[] Fits = { StoryFit.Cover, StoryFit.BlurFit, StoryFit.Solid };
    public static readonly StorySolidColor[] SolidColors = { StorySolidColor.Black, StorySolidColor.Dominant, StorySolidColor.Custom };
    public static readonly StoryIntensity[] Intensities = { StoryIntensity.Light, StoryIntensity.Moderate, StoryIntensity.Normal, StoryIntensity.Aggressive, StoryIntensity.Custom };
    public static readonly StoryOutputFormat[] Formats = { StoryOutputFormat.Jpg, StoryOutputFormat.Png };
    public static readonly StoryNaming[] Namings = { StoryNaming.Sequential, StoryNaming.SequentialCode };
    public static readonly StoryLineDirection[] Directions = { StoryLineDirection.Backslash, StoryLineDirection.Slash, StoryLineDirection.Cross, StoryLineDirection.Random };
    public static readonly StoryLineStyle[] Styles = { StoryLineStyle.Tone, StoryLineStyle.Ink };
    public static readonly StoryLineBlend[] Blends = { StoryLineBlend.HardLight, StoryLineBlend.Overlay };
    public static readonly StoryTexturePreset[] Presets = { StoryTexturePreset.Off, StoryTexturePreset.Subtle, StoryTexturePreset.Balanced, StoryTexturePreset.Intense, StoryTexturePreset.Custom };

    public static string Label(this StoryFit f) => f switch
    {
        StoryFit.Cover => "Preencher",
        StoryFit.BlurFit => "Fundo desfocado",
        _ => "Cor sólida",
    };

    public static string Hint(this StoryFit f) => f switch
    {
        StoryFit.Cover => "Preenche todo o 1080×1920 e corta o que sobrar pelo centro (pode cortar texto nas bordas).",
        StoryFit.BlurFit => "Mantém a imagem inteira no centro e preenche em cima e embaixo com uma cópia ampliada e desfocada dela.",
        _ => "Mantém a imagem inteira no centro sobre uma cor de fundo.",
    };

    public static string Label(this StorySolidColor c) => c switch
    {
        StorySolidColor.Black => "Preto",
        StorySolidColor.Dominant => "Cor dominante",
        _ => "Escolher cor",
    };

    public static string Label(this StoryIntensity i) => i switch
    {
        StoryIntensity.Light => "Leve",
        StoryIntensity.Moderate => "Moderado",
        StoryIntensity.Normal => "Normal",
        StoryIntensity.Aggressive => "Agressivo",
        _ => "Personalizado",
    };

    public static string Hint(this StoryIntensity i) => i switch
    {
        StoryIntensity.Light => "Imperceptível.",
        StoryIntensity.Moderate => "Quase imperceptível (os intervalos do pedido original).",
        StoryIntensity.Normal => "Percebe-se de perto, comparando lado a lado. Liga riscos diagonais, perspectiva, temperatura e vinheta.",
        StoryIntensity.Aggressive => "Diferença visível (cor, enquadramento e textura), mas o olho reconhece que é a mesma peça. Confira no preview.",
        _ => "Uma chave e um limite por etapa.",
    };

    public static string Label(this StoryOutputFormat f) => f == StoryOutputFormat.Jpg ? "JPEG" : "PNG";
    public static string FileExtension(this StoryOutputFormat f) => f == StoryOutputFormat.Jpg ? "jpg" : "png";

    public static string Label(this StoryNaming n) =>
        n == StoryNaming.Sequential ? "Sequencial (story_001)" : "Sequencial + código (story_001_a8f3k)";

    public static string Label(this StoryLineDirection d) => d switch
    {
        StoryLineDirection.Backslash => "Diagonal esquerda (\\)",
        StoryLineDirection.Slash => "Diagonal direita (/)",
        StoryLineDirection.Cross => "Cruzada (X)",
        _ => "Aleatória por imagem",
    };

    /// <summary>Rótulo curto dos botões de direção.</summary>
    public static string ShortLabel(this StoryLineDirection d) => d switch
    {
        StoryLineDirection.Backslash => "Esquerda \\",
        StoryLineDirection.Slash => "Direita /",
        StoryLineDirection.Cross => "Cruzada X",
        _ => "Aleatória",
    };

    public static string Label(this StoryLineStyle s) => s == StoryLineStyle.Tone ? "Tom (mantém a cor)" : "Gravura (preto e branco)";

    public static string Hint(this StoryLineStyle s) => s == StoryLineStyle.Tone
        ? "Clareia e escurece o próprio pixel sem trocar a cor: o verde continua verde, o amarelo continua amarelo. Borda suave, riscos irregulares e quase nada sobre áreas muito claras (texto branco fica limpo)."
        : "Faixa escura (preto) com um realce claro (branco) colado. Bem marcado e digital: aparece até sobre texto branco e fundo preto.";

    public static string Label(this StoryLineBlend b) => b == StoryLineBlend.HardLight ? "Hard-light" : "Overlay";

    public static string Label(this StoryTexturePreset p) => p switch
    {
        StoryTexturePreset.Off => "Desligado",
        StoryTexturePreset.Subtle => "Sutil",
        StoryTexturePreset.Balanced => "Equilibrado",
        StoryTexturePreset.Intense => "Intenso",
        _ => "Personalizado",
    };

    public static string Hint(this StoryTexturePreset p) => p switch
    {
        StoryTexturePreset.Off => "Sem linhas, serrilhado, aberração nem bloom.",
        StoryTexturePreset.Subtle => "Linhas leves, micro-aberração e serrilhado mínimo. O texto continua limpo.",
        StoryTexturePreset.Balanced => "Linhas bem visíveis, serrilhado moderado e deslocamento RGB médio.",
        StoryTexturePreset.Intense => "Linhas fortes, serrilhado alto, aberração cromática e bloom fortes. Confira o texto no zoom antes de processar o lote.",
        _ => "Sliders das linhas (do estilo escolhido acima) e uma chave e um slider (0 a 100%) para cada efeito.",
    };
}

public sealed record RGBColor(double R, double G, double B)
{
    public static readonly RGBColor Black = new(0, 0, 0);
}

/// <summary>Quais etapas sutis rodam e até onde vão. O sorteio de cada imagem fica dentro desses limites.</summary>
public sealed record StoryAdjustments
{
    /// <summary>Micro-recorte (por borda) e micro-rotação.</summary>
    public bool Geometry { get; set; } = true;
    public double CropMinPercent { get; set; } = 0.5;
    public double CropMaxPercent { get; set; } = 1.5;
    public double RotationMaxDegrees { get; set; } = 0.8;
    /// <summary>1.0.0-beta.22: micro-perspectiva — cada canto anda até X% do lado.</summary>
    public bool Perspective { get; set; }
    public double PerspectiveMaxPercent { get; set; } = 0.6;
    /// <summary>Brilho, contraste e saturação.</summary>
    public bool Photometric { get; set; } = true;
    public double BrightnessMaxPercent { get; set; } = 2.0;
    public double ContrastMaxPercent { get; set; } = 2.0;
    public double SaturationMaxPercent { get; set; } = 3.0;
    /// <summary>1.0.0-beta.22: temperatura de cor (mais quente ou mais fria), em kelvin.</summary>
    public bool Temperature { get; set; }
    public double TemperatureMaxKelvin { get; set; } = 250.0;
    /// <summary>Micro-ruído nos canais RGB (níveis de 0–255).</summary>
    public bool Noise { get; set; } = true;
    public double NoiseMinAmplitude { get; set; } = 2.0;
    public double NoiseMaxAmplitude { get; set; } = 4.0;
    /// <summary>Deslocamento de 1px (ou até 2px) no canal vermelho ou azul.</summary>
    public bool ChromaticShift { get; set; } = true;
    public int ChromaticMaxPixels { get; set; } = 1;
    /// <summary>Granulação de filme (overlay ou soft-light).</summary>
    public bool FilmGrain { get; set; } = true;
    public double GrainMinOpacityPercent { get; set; } = 1.0;
    public double GrainMaxOpacityPercent { get; set; } = 3.0;
    /// <summary>1.0.0-beta.22: riscos diagonais pixel a pixel.</summary>
    public bool Diagonal { get; set; }
    public double DiagonalMinAmplitude { get; set; } = 2.0;
    public double DiagonalMaxAmplitude { get; set; } = 5.0;
    /// <summary>1.0.0-beta.22: vinheta — bordas mais escuras ou mais claras (% da escala nos cantos).</summary>
    public bool Vignette { get; set; }
    public double VignetteMaxPercent { get; set; } = 5.0;
    /// <summary>Unsharp Mask leve ou suavização mínima, sorteado.</summary>
    public bool Detail { get; set; } = true;
    /// <summary>Baseline ou progressivo e subamostragem 4:2:0 ou 4:4:4, sorteados (só JPEG).</summary>
    public bool JpegVariation { get; set; } = true;

    // Limites dos sliders do Personalizado (vão até o Agressivo)
    public static readonly (double Lo, double Hi) CropRange = (0.5, 5);
    public static readonly (double Lo, double Hi) RotationRange = (0, 3);
    public static readonly (double Lo, double Hi) PerspectiveRange = (0, 2);
    public static readonly (double Lo, double Hi) BrightnessRange = (0, 8);
    public static readonly (double Lo, double Hi) ContrastRange = (0, 8);
    public static readonly (double Lo, double Hi) SaturationRange = (0, 12);
    public static readonly (double Lo, double Hi) TemperatureRange = (0, 800);
    public static readonly (double Lo, double Hi) NoiseRange = (2, 8);
    public static readonly (int Lo, int Hi) ChromaticRange = (1, 2);
    public static readonly (double Lo, double Hi) GrainRange = (1, 8);
    public static readonly (double Lo, double Hi) DiagonalRange = (1, 12);
    public static readonly (double Lo, double Hi) VignetteRange = (0, 15);
    public static readonly (int Lo, int Hi) QualityRange = (88, 93);

    /// <summary>Leve (imperceptível): intervalos curtos, sem deslocamento de canal nem granulação.</summary>
    public static StoryAdjustments Light => new()
    {
        CropMaxPercent = 0.8, RotationMaxDegrees = 0.3, BrightnessMaxPercent = 1, ContrastMaxPercent = 1,
        SaturationMaxPercent = 1.5, NoiseMaxAmplitude = 2.5, ChromaticShift = false, FilmGrain = false, GrainMaxOpacityPercent = 1.5,
    };

    /// <summary>Moderado: os intervalos do pedido original (beta.21), com todas as etapas de lá ligadas.</summary>
    public static StoryAdjustments Moderate => new();

    /// <summary>Normal (beta.22): o dobro do Moderado e as etapas novas ligadas.</summary>
    public static StoryAdjustments Normal => new()
    {
        CropMinPercent = 1, CropMaxPercent = 3, RotationMaxDegrees = 1.5, Perspective = true, PerspectiveMaxPercent = 0.6,
        BrightnessMaxPercent = 4, ContrastMaxPercent = 4, SaturationMaxPercent = 6, Temperature = true, TemperatureMaxKelvin = 300,
        NoiseMinAmplitude = 3, NoiseMaxAmplitude = 6, GrainMinOpacityPercent = 2, GrainMaxOpacityPercent = 5,
        Diagonal = true, DiagonalMinAmplitude = 2, DiagonalMaxAmplitude = 5, Vignette = true, VignetteMaxPercent = 5,
    };

    /// <summary>Agressivo (beta.22): variação visível, mesma peça reconhecível.</summary>
    public static StoryAdjustments Aggressive => new()
    {
        CropMinPercent = 2, CropMaxPercent = 5, RotationMaxDegrees = 2, Perspective = true, PerspectiveMaxPercent = 1.5,
        BrightnessMaxPercent = 7, ContrastMaxPercent = 7, SaturationMaxPercent = 10, Temperature = true, TemperatureMaxKelvin = 650,
        NoiseMinAmplitude = 5, NoiseMaxAmplitude = 8, ChromaticMaxPixels = 2, GrainMinOpacityPercent = 4, GrainMaxOpacityPercent = 8,
        Diagonal = true, DiagonalMinAmplitude = 5, DiagonalMaxAmplitude = 10, Vignette = true, VignetteMaxPercent = 12,
    };

    /// <summary>Mantém cada valor dentro dos limites (protege contra configuração salva estragada) e mínimo ≤ máximo.</summary>
    public StoryAdjustments Clamped()
    {
        static double C(double v, (double Lo, double Hi) r) => R.Clamp(v, r.Lo, r.Hi);
        var a = this with { };
        a.CropMaxPercent = C(CropMaxPercent, CropRange);
        a.CropMinPercent = Math.Min(C(CropMinPercent, CropRange), a.CropMaxPercent);
        a.RotationMaxDegrees = C(RotationMaxDegrees, RotationRange);
        a.PerspectiveMaxPercent = C(PerspectiveMaxPercent, PerspectiveRange);
        a.BrightnessMaxPercent = C(BrightnessMaxPercent, BrightnessRange);
        a.ContrastMaxPercent = C(ContrastMaxPercent, ContrastRange);
        a.SaturationMaxPercent = C(SaturationMaxPercent, SaturationRange);
        a.TemperatureMaxKelvin = C(TemperatureMaxKelvin, TemperatureRange);
        a.NoiseMaxAmplitude = C(NoiseMaxAmplitude, NoiseRange);
        a.NoiseMinAmplitude = Math.Min(C(NoiseMinAmplitude, NoiseRange), a.NoiseMaxAmplitude);
        a.ChromaticMaxPixels = Math.Min(Math.Max(ChromaticMaxPixels, ChromaticRange.Lo), ChromaticRange.Hi);
        a.GrainMaxOpacityPercent = C(GrainMaxOpacityPercent, GrainRange);
        a.GrainMinOpacityPercent = Math.Min(C(GrainMinOpacityPercent, GrainRange), a.GrainMaxOpacityPercent);
        a.DiagonalMaxAmplitude = C(DiagonalMaxAmplitude, DiagonalRange);
        a.DiagonalMinAmplitude = Math.Min(C(DiagonalMinAmplitude, DiagonalRange), a.DiagonalMaxAmplitude);
        a.VignetteMaxPercent = C(VignetteMaxPercent, VignetteRange);
        return a;
    }
}

/// <summary>
/// Efeitos de textura e estilização das bordas. Cada um liga e desliga sozinho; os sliders vão de 0 a 100%.
/// O nível é o máximo: cada imagem sorteia entre 70% e 100% dele (a direção "aleatória" das linhas também é sorteada).
/// </summary>
[JsonConverter(typeof(StoryTextureConverter))]
public sealed record StoryTexture
{
    /// <summary>Linhas diagonais por cima da imagem (pixel exato, sem reamostragem).</summary>
    public bool Lines { get; set; }
    public StoryLineDirection LineDirection { get; set; } = StoryLineDirection.Random;
    /// <summary>Intensidade (0–100%), com curva própria (ver <see cref="LineAlpha"/>).</summary>
    public double LineOpacityPercent { get; set; } = 50.0;
    /// <summary>Em pixels da saída 1080×1920, medidos na horizontal.</summary>
    public double LineSpacing { get; set; } = 10.0;
    public double LineThickness { get; set; } = 2.0;
    public StoryLineBlend LineBlend { get; set; } = StoryLineBlend.HardLight;
    /// <summary>1.0.0-beta.25: estilo, ângulo (só no Tom) e irregularidade (só no Tom).</summary>
    public StoryLineStyle LineStyle { get; set; } = StoryLineStyle.Tone;
    public double LineAngle { get; set; } = 55.0;
    public double LineIrregularity { get; set; } = 60.0;
    /// <summary>Serrilhado: quebra o anti-aliasing só nas bordas de alto contraste (texto, botões).</summary>
    public bool Jitter { get; set; }
    public double JitterPercent { get; set; } = 40.0;
    /// <summary>Aberração cromática: R e B andam em sentidos opostos (1px a 6px conforme o nível).</summary>
    public bool Aberration { get; set; }
    public double AberrationPercent { get; set; } = 40.0;
    /// <summary>Ofuscação: bloom nas luzes + micro-desfoque direcional.</summary>
    public bool Bloom { get; set; }
    public double BloomPercent { get; set; } = 30.0;

    public static readonly (double Lo, double Hi) PercentRange = (0, 100);
    public static readonly (double Lo, double Hi) SpacingRange = (4, 18);
    public static readonly (double Lo, double Hi) ThicknessRange = (2, 8);
    public const int AberrationMaxPixels = 6;
    /// <summary>Teto da opacidade da faixa escura (a leitura do texto não some mesmo com o slider em 100%).</summary>
    public const double LineOpacityCap = 0.85;
    /// <summary>A faixa de realce claro tem 60% da opacidade da escura.</summary>
    public const double LineHighlightRatio = 0.6;
    /// <summary>No modo Cruzada (X) cada camada usa 65% da opacidade.</summary>
    public const double LineCrossBalance = 0.65;
    /// <summary>Tom: ângulo das linhas em graus a partir da horizontal.</summary>
    public static readonly (double Lo, double Hi) AngleRange = (30, 75);
    /// <summary>Tom: variação máxima do brilho no centro da linha com o slider em 100% (±35%).</summary>
    public const double ToneAmplitudeCap = 0.35;
    /// <summary>Tom: comprimento médio de cada trecho de risco (px).</summary>
    public const double ToneSegmentLength = 36.0;

    /// <summary>Curva do slider no Tom (0 a 1) → variação de brilho no centro da linha.</summary>
    public static double ToneAmplitude(double level)
    {
        var l = Math.Min(Math.Max(double.IsFinite(level) ? level : 0, 0), 1);
        return ToneAmplitudeCap * Math.Pow(l, 0.8);
    }

    /// <summary>Curva do slider (0 a 1) → opacidade da faixa escura.</summary>
    public static double LineAlpha(double level)
    {
        var l = Math.Min(Math.Max(double.IsFinite(level) ? level : 0, 0), 1);
        return LineOpacityCap * Math.Pow(l, 0.7);
    }

    /// <summary>Largura da faixa de realce: um terço da escura (mínimo 1px), sempre sobrando pelo menos 1px de intervalo.</summary>
    public static int LineHighlightWidth(int spacing, int thickness) =>
        Math.Max(1, Math.Min((int)R.Round(thickness / 3.0), spacing - thickness - 1));

    public static StoryTexture None => new();

    [JsonIgnore]
    public bool IsActive => (Lines && LineOpacityPercent > 0) || (Jitter && JitterPercent > 0)
                            || (Aberration && AberrationPercent > 0) || (Bloom && BloomPercent > 0);

    /// <summary>Sutil: linhas leves + micro-aberração + serrilhado mínimo.</summary>
    public static StoryTexture Subtle => new()
    {
        Lines = true, LineDirection = StoryLineDirection.Random, LineStyle = StoryLineStyle.Tone, LineOpacityPercent = 30,
        LineSpacing = 10, LineThickness = 2, LineAngle = 55, LineIrregularity = 60, LineBlend = StoryLineBlend.HardLight,
        Jitter = true, JitterPercent = 15, Aberration = true, AberrationPercent = 15,
    };

    /// <summary>Equilibrado: linhas visíveis + serrilhado moderado + deslocamento RGB médio.</summary>
    public static StoryTexture Balanced => new()
    {
        Lines = true, LineDirection = StoryLineDirection.Random, LineStyle = StoryLineStyle.Tone, LineOpacityPercent = 60,
        LineSpacing = 9, LineThickness = 3, LineAngle = 55, LineIrregularity = 50, LineBlend = StoryLineBlend.HardLight,
        Jitter = true, JitterPercent = 45, Aberration = true, AberrationPercent = 45,
    };

    /// <summary>Intenso: linhas marcadas + serrilhado alto + aberração e bloom fortes.</summary>
    public static StoryTexture Intense => new()
    {
        Lines = true, LineDirection = StoryLineDirection.Cross, LineStyle = StoryLineStyle.Ink, LineOpacityPercent = 85,
        LineSpacing = 8, LineThickness = 4, LineBlend = StoryLineBlend.HardLight, Jitter = true, JitterPercent = 80,
        Aberration = true, AberrationPercent = 80, Bloom = true, BloomPercent = 70,
    };

    /// <summary>Mantém tudo dentro dos limites e a espessura menor que o espaçamento.</summary>
    public StoryTexture Clamped()
    {
        static double C(double v, (double Lo, double Hi) r) => R.Clamp(v, r.Lo, r.Hi);
        var t = this with { };
        t.LineOpacityPercent = C(LineOpacityPercent, PercentRange);
        t.LineSpacing = R.Round(C(LineSpacing, SpacingRange));
        // pelo menos 2px de folga: sobra espaço para a faixa de realce e para um intervalo
        t.LineThickness = Math.Max(ThicknessRange.Lo, Math.Min(R.Round(C(LineThickness, ThicknessRange)), t.LineSpacing - 2));
        t.LineAngle = R.Round(C(LineAngle, AngleRange));
        t.LineIrregularity = C(LineIrregularity, PercentRange);
        t.JitterPercent = C(JitterPercent, PercentRange);
        t.AberrationPercent = C(AberrationPercent, PercentRange);
        t.BloomPercent = C(BloomPercent, PercentRange);
        return t;
    }
}

/// <summary>Leitura tolerante da textura: opções salvas antes da beta.25 não têm estilo (eram todas Gravura).</summary>
public sealed class StoryTextureConverter : JsonConverter<StoryTexture>
{
    public override StoryTexture? Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        using var doc = JsonDocument.ParseValue(ref reader);
        var e = doc.RootElement;
        var t = new StoryTexture();
        if (e.ValueKind != JsonValueKind.Object) return t;
        t.Lines = StoryJson.Get(e, "lines", t.Lines, options);
        t.LineDirection = StoryJson.Get(e, "lineDirection", t.LineDirection, options);
        t.LineOpacityPercent = StoryJson.Get(e, "lineOpacityPercent", t.LineOpacityPercent, options);
        t.LineSpacing = StoryJson.Get(e, "lineSpacing", t.LineSpacing, options);
        t.LineThickness = StoryJson.Get(e, "lineThickness", t.LineThickness, options);
        t.LineBlend = StoryJson.Get(e, "lineBlend", t.LineBlend, options);
        t.LineStyle = StoryJson.Get(e, "lineStyle", StoryLineStyle.Ink, options);
        t.LineAngle = StoryJson.Get(e, "lineAngle", t.LineAngle, options);
        t.LineIrregularity = StoryJson.Get(e, "lineIrregularity", t.LineIrregularity, options);
        t.Jitter = StoryJson.Get(e, "jitter", t.Jitter, options);
        t.JitterPercent = StoryJson.Get(e, "jitterPercent", t.JitterPercent, options);
        t.Aberration = StoryJson.Get(e, "aberration", t.Aberration, options);
        t.AberrationPercent = StoryJson.Get(e, "aberrationPercent", t.AberrationPercent, options);
        t.Bloom = StoryJson.Get(e, "bloom", t.Bloom, options);
        t.BloomPercent = StoryJson.Get(e, "bloomPercent", t.BloomPercent, options);
        return t;
    }

    public override void Write(Utf8JsonWriter writer, StoryTexture value, JsonSerializerOptions options)
    {
        writer.WriteStartObject();
        writer.WriteBoolean("lines", value.Lines);
        writer.WriteString("lineDirection", TolerantEnumConverterFactory.RawValue(value.LineDirection));
        writer.WriteNumber("lineOpacityPercent", value.LineOpacityPercent);
        writer.WriteNumber("lineSpacing", value.LineSpacing);
        writer.WriteNumber("lineThickness", value.LineThickness);
        writer.WriteString("lineBlend", TolerantEnumConverterFactory.RawValue(value.LineBlend));
        writer.WriteString("lineStyle", TolerantEnumConverterFactory.RawValue(value.LineStyle));
        writer.WriteNumber("lineAngle", value.LineAngle);
        writer.WriteNumber("lineIrregularity", value.LineIrregularity);
        writer.WriteBoolean("jitter", value.Jitter);
        writer.WriteNumber("jitterPercent", value.JitterPercent);
        writer.WriteBoolean("aberration", value.Aberration);
        writer.WriteNumber("aberrationPercent", value.AberrationPercent);
        writer.WriteBoolean("bloom", value.Bloom);
        writer.WriteNumber("bloomPercent", value.BloomPercent);
        writer.WriteEndObject();
    }
}

internal static class StoryJson
{
    /// <summary>Campo ausente ou com tipo errado → valor padrão (como o <c>(try? decodeIfPresent) ?? padrão</c> do Swift).</summary>
    public static T Get<T>(JsonElement e, string key, T fallback, JsonSerializerOptions options)
    {
        if (!e.TryGetProperty(key, out var v) || v.ValueKind == JsonValueKind.Null) return fallback;
        try
        {
            if (typeof(T).IsEnum)
            {
                if (v.ValueKind != JsonValueKind.String) return fallback;
                var raw = v.GetString();
                var names = Enum.GetNames(typeof(T));
                foreach (var n in names)
                    if (JsonNamingPolicy.CamelCase.ConvertName(n) == raw) return (T)Enum.Parse(typeof(T), n);
                return fallback;
            }
            if (typeof(T) == typeof(bool)) return v.ValueKind is JsonValueKind.True or JsonValueKind.False ? (T)(object)v.GetBoolean() : fallback;
            if (typeof(T) == typeof(double)) return v.ValueKind == JsonValueKind.Number ? (T)(object)v.GetDouble() : fallback;
            if (typeof(T) == typeof(int)) return v.ValueKind == JsonValueKind.Number && v.TryGetInt32(out var i) ? (T)(object)i : fallback;
            if (typeof(T) == typeof(string)) return v.ValueKind == JsonValueKind.String ? (T)(object)v.GetString()! : fallback;
            return v.Deserialize<T>(options) ?? fallback;
        }
        catch { return fallback; }
    }
}

/// <summary>
/// 1.0.0-beta.26: medidas das linhas de um estilo. Cada estilo (Tom e Gravura) tem os próprios níveis Sutil, Equilibrado e
/// Intenso e o próprio Personalizado; ligar as linhas, o estilo e a direção ficam fora do nível, escolhidos antes.
/// </summary>
public sealed record StoryLineSettings
{
    /// <summary>Intensidade (0–100%).</summary>
    public double OpacityPercent { get; set; } = 50.0;
    public double Spacing { get; set; } = 10.0;
    public double Thickness { get; set; } = 2.0;
    /// <summary>Só no Tom.</summary>
    public double Angle { get; set; } = 55.0;
    public double Irregularity { get; set; } = 60.0;
    /// <summary>Só na Gravura.</summary>
    public StoryLineBlend Blend { get; set; } = StoryLineBlend.HardLight;

    public StoryLineSettings() { }

    public StoryLineSettings(double opacityPercent, double spacing, double thickness, double angle = 55, double irregularity = 0,
        StoryLineBlend blend = StoryLineBlend.HardLight)
    {
        OpacityPercent = opacityPercent;
        Spacing = spacing;
        Thickness = thickness;
        Angle = angle;
        Irregularity = irregularity;
        Blend = blend;
    }

    /// <summary>As medidas de linha guardadas num <see cref="StoryTexture"/> (usado para migrar opções salvas antes da beta.26).</summary>
    public static StoryLineSettings FromTexture(StoryTexture t) =>
        new(t.LineOpacityPercent, t.LineSpacing, t.LineThickness, t.LineAngle, t.LineIrregularity, t.LineBlend);

    public void ApplyTo(StoryTexture t)
    {
        t.LineOpacityPercent = OpacityPercent;
        t.LineSpacing = Spacing;
        t.LineThickness = Thickness;
        t.LineAngle = Angle;
        t.LineIrregularity = Irregularity;
        t.LineBlend = Blend;
    }

    /// <summary>Níveis de cada estilo. Desligado e Personalizado não têm nível próprio (devolvem o Equilibrado).</summary>
    public static StoryLineSettings Preset(StoryTexturePreset level, StoryLineStyle style) => (style, level) switch
    {
        (StoryLineStyle.Tone, StoryTexturePreset.Subtle) => new(30, 10, 2, 55, 60),
        (StoryLineStyle.Tone, StoryTexturePreset.Intense) => new(90, 8, 3, 55, 40),
        (StoryLineStyle.Tone, _) => new(60, 9, 3, 55, 50),
        (StoryLineStyle.Ink, StoryTexturePreset.Subtle) => new(20, 12, 2, blend: StoryLineBlend.HardLight),
        (StoryLineStyle.Ink, StoryTexturePreset.Intense) => new(85, 8, 4, blend: StoryLineBlend.HardLight),
        _ => new(50, 8, 3, blend: StoryLineBlend.HardLight),
    };
}

/// <summary>Tudo o que a tela do Otimizador escolhe. Fica salvo entre aberturas do app.</summary>
[JsonConverter(typeof(StoryOptionsConverter))]
public sealed class StoryOptions
{
    public StoryFit Fit { get; set; } = StoryFit.BlurFit;
    public StorySolidColor SolidColor { get; set; } = StorySolidColor.Black;
    public RGBColor CustomColor { get; set; } = RGBColor.Black;
    public StoryIntensity Intensity { get; set; } = StoryIntensity.Light;
    /// <summary>Valores do modo Personalizado (começa igual ao Moderado).</summary>
    public StoryAdjustments Custom { get; set; } = StoryAdjustments.Moderate;
    /// <summary>Espelhar na horizontal — desligado de fábrica (só para imagens sem texto).</summary>
    public bool Mirror { get; set; }
    public StoryOutputFormat Format { get; set; } = StoryOutputFormat.Jpg;
    public StoryNaming Naming { get; set; } = StoryNaming.SequentialCode;
    public string Prefix { get; set; } = "story";
    /// <summary>1.0.0-beta.22: quantas versões diferentes sair de cada imagem (1 a 10).</summary>
    public int VersionsPerImage { get; set; } = 1;
    /// <summary>1.0.0-beta.23: texturas, linhas e bordas (desligado de fábrica).</summary>
    public StoryTexturePreset TexturePreset { get; set; } = StoryTexturePreset.Off;
    /// <summary>Valores do modo Personalizado das texturas. beta.26: daqui só valem serrilhado, aberração e ofuscação.</summary>
    public StoryTexture CustomTexture { get; set; } = StoryTexture.Balanced;
    /// <summary>1.0.0-beta.26: as linhas são escolhidas antes do nível.</summary>
    public bool LinesEnabled { get; set; }
    public StoryLineStyle LineStyle { get; set; } = StoryLineStyle.Tone;
    public StoryLineDirection LineDirection { get; set; } = StoryLineDirection.Random;
    /// <summary>Personalizado das linhas, um para cada estilo.</summary>
    public StoryLineSettings CustomToneLines { get; set; } = StoryLineSettings.Preset(StoryTexturePreset.Balanced, StoryLineStyle.Tone);
    public StoryLineSettings CustomInkLines { get; set; } = StoryLineSettings.Preset(StoryTexturePreset.Balanced, StoryLineStyle.Ink);

    public const int VersionsMin = 1;
    public const int VersionsMax = 10;

    [JsonIgnore] public int Versions => Math.Min(Math.Max(VersionsPerImage, VersionsMin), VersionsMax);

    /// <summary>Etapas e limites em vigor, conforme a intensidade escolhida.</summary>
    [JsonIgnore]
    public StoryAdjustments Adjustments => Intensity switch
    {
        StoryIntensity.Light => StoryAdjustments.Light,
        StoryIntensity.Moderate => StoryAdjustments.Moderate,
        StoryIntensity.Normal => StoryAdjustments.Normal,
        StoryIntensity.Aggressive => StoryAdjustments.Aggressive,
        _ => Custom.Clamped(),
    };

    /// <summary>Serrilhado, aberração e ofuscação do nível escolhido (sem as linhas).</summary>
    public static StoryTexture BaseTexture(StoryTexturePreset preset) => preset switch
    {
        StoryTexturePreset.Off => StoryTexture.None,
        StoryTexturePreset.Subtle => StoryTexture.Subtle,
        StoryTexturePreset.Intense => StoryTexture.Intense,
        _ => StoryTexture.Balanced,
    };

    /// <summary>Medidas das linhas em vigor: o nível do estilo escolhido, ou o Personalizado desse estilo.</summary>
    [JsonIgnore]
    public StoryLineSettings LineSettings =>
        TexturePreset == StoryTexturePreset.Custom ? CustomLines : StoryLineSettings.Preset(TexturePreset, LineStyle);

    /// <summary>Personalizado das linhas do estilo escolhido (é o que os sliders editam).</summary>
    [JsonIgnore]
    public StoryLineSettings CustomLines
    {
        get => LineStyle == StoryLineStyle.Tone ? CustomToneLines : CustomInkLines;
        set
        {
            if (LineStyle == StoryLineStyle.Tone) CustomToneLines = value; else CustomInkLines = value;
        }
    }

    /// <summary>Efeitos de textura em vigor: o nível escolhido mais as linhas (ligadas, estilo e direção escolhidos antes do nível).</summary>
    [JsonIgnore]
    public StoryTexture Texture
    {
        get
        {
            if (TexturePreset == StoryTexturePreset.Off) return StoryTexture.None;
            var t = (TexturePreset == StoryTexturePreset.Custom ? CustomTexture : BaseTexture(TexturePreset)) with { };
            t.Lines = LinesEnabled;
            t.LineStyle = LineStyle;
            t.LineDirection = LineDirection;
            LineSettings.ApplyTo(t);
            return t.Clamped();
        }
    }

    /// <summary>
    /// Troca o nível das texturas. Ao entrar no Personalizado, os sliders partem do nível que estava valendo
    /// (se estava desligado, do Equilibrado) em vez de pular para valores soltos.
    /// </summary>
    public void SelectTexturePreset(StoryTexturePreset preset)
    {
        if (preset == StoryTexturePreset.Custom && TexturePreset != StoryTexturePreset.Custom)
        {
            var from = TexturePreset == StoryTexturePreset.Off ? StoryTexturePreset.Balanced : TexturePreset;
            CustomTexture = BaseTexture(from);
            CustomToneLines = StoryLineSettings.Preset(from, StoryLineStyle.Tone);
            CustomInkLines = StoryLineSettings.Preset(from, StoryLineStyle.Ink);
        }
        TexturePreset = preset;
    }

    /// <summary>Liga ou desliga as linhas. Ligar com o nível em Desligado já escolhe o Equilibrado.</summary>
    public void SetLinesEnabled(bool on)
    {
        LinesEnabled = on;
        if (on && TexturePreset == StoryTexturePreset.Off) TexturePreset = StoryTexturePreset.Balanced;
    }

    public StoryOptions Clone() => JsonSerializer.Deserialize<StoryOptions>(JsonSerializer.Serialize(this, Json.Compact), Json.Compact)!;

    public string Key => JsonSerializer.Serialize(this, Json.Compact);

    public override bool Equals(object? obj) => obj is StoryOptions o && o.Key == Key;
    public override int GetHashCode() => Key.GetHashCode();
}

/// <summary>Leitura tolerante das opções, com as migrações da beta.26 (linhas que moravam dentro do nível).</summary>
public sealed class StoryOptionsConverter : JsonConverter<StoryOptions>
{
    public override StoryOptions Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        using var doc = JsonDocument.ParseValue(ref reader);
        var c = doc.RootElement;
        var d = new StoryOptions();
        var o = new StoryOptions();
        if (c.ValueKind != JsonValueKind.Object) return o;
        o.Fit = StoryJson.Get(c, "fit", d.Fit, options);
        o.SolidColor = StoryJson.Get(c, "solidColor", d.SolidColor, options);
        o.CustomColor = StoryJson.Get(c, "customColor", d.CustomColor, options);
        o.Intensity = StoryJson.Get(c, "intensity", d.Intensity, options);
        o.Custom = StoryJson.Get(c, "custom", d.Custom, options);
        o.Mirror = StoryJson.Get(c, "mirror", d.Mirror, options);
        o.Format = StoryJson.Get(c, "format", d.Format, options);
        o.Naming = StoryJson.Get(c, "naming", d.Naming, options);
        o.Prefix = StoryJson.Get(c, "prefix", d.Prefix, options);
        o.VersionsPerImage = StoryJson.Get(c, "versionsPerImage", d.VersionsPerImage, options);
        o.TexturePreset = StoryJson.Get(c, "texturePreset", d.TexturePreset, options);
        o.CustomTexture = StoryJson.Get(c, "customTexture", d.CustomTexture, options);
        o.CustomToneLines = StoryJson.Get(c, "customToneLines", d.CustomToneLines, options);
        o.CustomInkLines = StoryJson.Get(c, "customInkLines", d.CustomInkLines, options);
        if (c.TryGetProperty("linesEnabled", out var le) && le.ValueKind is JsonValueKind.True or JsonValueKind.False)
        {
            o.LinesEnabled = le.GetBoolean();
            o.LineStyle = StoryJson.Get(c, "lineStyle", d.LineStyle, options);
            o.LineDirection = StoryJson.Get(c, "lineDirection", d.LineDirection, options);
        }
        else
        {
            // salvo antes da beta.26: as linhas moravam dentro do nível
            switch (o.TexturePreset)
            {
                case StoryTexturePreset.Off:
                    break;
                case StoryTexturePreset.Custom:
                    o.LinesEnabled = o.CustomTexture.Lines;
                    o.LineStyle = o.CustomTexture.LineStyle;
                    o.LineDirection = o.CustomTexture.LineDirection;
                    o.CustomLines = StoryLineSettings.FromTexture(o.CustomTexture);
                    break;
                case StoryTexturePreset.Intense:
                    o.LinesEnabled = true;
                    o.LineStyle = StoryLineStyle.Ink;
                    o.LineDirection = StoryLineDirection.Cross;
                    break;
                default:
                    o.LinesEnabled = true;
                    o.LineStyle = StoryLineStyle.Tone;
                    o.LineDirection = StoryLineDirection.Random;
                    break;
            }
        }
        return o;
    }

    public override void Write(Utf8JsonWriter writer, StoryOptions v, JsonSerializerOptions options)
    {
        writer.WriteStartObject();
        writer.WriteString("fit", TolerantEnumConverterFactory.RawValue(v.Fit));
        writer.WriteString("solidColor", TolerantEnumConverterFactory.RawValue(v.SolidColor));
        writer.WritePropertyName("customColor");
        JsonSerializer.Serialize(writer, v.CustomColor, options);
        writer.WriteString("intensity", TolerantEnumConverterFactory.RawValue(v.Intensity));
        writer.WritePropertyName("custom");
        JsonSerializer.Serialize(writer, v.Custom, options);
        writer.WriteBoolean("mirror", v.Mirror);
        writer.WriteString("format", TolerantEnumConverterFactory.RawValue(v.Format));
        writer.WriteString("naming", TolerantEnumConverterFactory.RawValue(v.Naming));
        writer.WriteString("prefix", v.Prefix);
        writer.WriteNumber("versionsPerImage", v.VersionsPerImage);
        writer.WriteString("texturePreset", TolerantEnumConverterFactory.RawValue(v.TexturePreset));
        writer.WritePropertyName("customTexture");
        JsonSerializer.Serialize(writer, v.CustomTexture, options);
        writer.WriteBoolean("linesEnabled", v.LinesEnabled);
        writer.WriteString("lineStyle", TolerantEnumConverterFactory.RawValue(v.LineStyle));
        writer.WriteString("lineDirection", TolerantEnumConverterFactory.RawValue(v.LineDirection));
        writer.WritePropertyName("customToneLines");
        JsonSerializer.Serialize(writer, v.CustomToneLines, options);
        writer.WritePropertyName("customInkLines");
        JsonSerializer.Serialize(writer, v.CustomInkLines, options);
        writer.WriteEndObject();
    }
}

// MARK: - Parâmetros sorteados de uma imagem

public enum ChromaticChannel { Red, Blue }

public sealed record StoryParams
{
    /// <summary>Recorte por borda (0.01 = 1%). 0 = sem recorte.</summary>
    public double CropFraction { get; set; }
    /// <summary>-1…1: para que lado a janela do recorte escorrega (0 = centro).</summary>
    public double CropShiftX { get; set; }
    public double CropShiftY { get; set; }
    public double RotationDegrees { get; set; }
    /// <summary>Soma no canal (escala 0–1).</summary>
    public double Brightness { get; set; }
    /// <summary>Fator 1 + contraste.</summary>
    public double Contrast { get; set; }
    /// <summary>Fator 1 + saturação.</summary>
    public double Saturation { get; set; }
    /// <summary>Amplitude do ruído em níveis de 0–255 (0 = sem ruído).</summary>
    public double NoiseAmplitude { get; set; }
    public double NoiseOffsetX { get; set; }
    public double NoiseOffsetY { get; set; }
    /// <summary>Canal deslocado (null = sem deslocamento).</summary>
    public ChromaticChannel? ChromaticChannel { get; set; }
    public int ChromaticDX { get; set; }
    public int ChromaticDY { get; set; }
    /// <summary>Opacidade da granulação (0.01 = 1%; 0 = sem granulação).</summary>
    public double GrainOpacity { get; set; }
    public bool GrainSoftLight { get; set; }
    public double GrainOffsetX { get; set; }
    public double GrainOffsetY { get; set; }
    /// <summary>Unsharp Mask (0 = não aplica).</summary>
    public double SharpenIntensity { get; set; }
    /// <summary>Suavização em px (0 = não aplica).</summary>
    public double SoftenRadius { get; set; }
    public bool Mirror { get; set; }
    /// <summary>
    /// 1.0.0-beta.22: micro-perspectiva — deslocamento de cada canto, em fração do lado (−máx…máx).
    /// Ordem (do Core Image, y para cima): inferior esquerdo, inferior direito, superior direito, superior esquerdo (x, y de cada).
    /// </summary>
    public double[] Perspective { get; set; } = Array.Empty<double>();
    public double PerspectiveMax { get; set; }
    /// <summary>1.0.0-beta.22: temperatura de cor em kelvin (+ mais quente, − mais fria).</summary>
    public double TemperatureKelvin { get; set; }
    /// <summary>1.0.0-beta.22: riscos diagonais — amplitude (0–255), período 3 ou 4, direção e fase.</summary>
    public double DiagonalAmplitude { get; set; }
    public int DiagonalPeriod { get; set; } = 3;
    public bool DiagonalAnti { get; set; }
    public int DiagonalPhase { get; set; }
    /// <summary>1.0.0-beta.22: vinheta — fração da escala somada nos cantos (− escurece, + clareia).</summary>
    public double Vignette { get; set; }
    /// <summary>1.0.0-beta.23: linhas diagonais (0 = desligado). A direção nunca é Random aqui.</summary>
    public double LineOpacity { get; set; }
    public int LineSpacing { get; set; } = 8;
    public int LineThickness { get; set; } = 3;
    public StoryLineDirection LineDirection { get; set; } = StoryLineDirection.Backslash;
    public StoryLineBlend LineBlend { get; set; } = StoryLineBlend.HardLight;
    public int LinePhase { get; set; }
    public int LinePhase2 { get; set; }
    /// <summary>1.0.0-beta.25: estilo, ângulo, irregularidade e semente do Tom. Padrão gravura, como antes.</summary>
    public StoryLineStyle LineStyle { get; set; } = StoryLineStyle.Ink;
    public double LineAngle { get; set; } = 45.0;
    public double LineIrregularity { get; set; }
    public ulong LineSeed { get; set; }
    /// <summary>1.0.0-beta.23: serrilhado das bordas (nível 0–1) e semente.</summary>
    public double JitterLevel { get; set; }
    public ulong JitterSeed { get; set; }
    /// <summary>1.0.0-beta.23: aberração cromática — R anda (+dx, +dy) e B anda (−dx, −dy).</summary>
    public int AberrationDX { get; set; }
    public int AberrationDY { get; set; }
    /// <summary>1.0.0-beta.23: ofuscação (bloom + micro-desfoque direcional), nível 0–1, e ângulo em radianos.</summary>
    public double BloomLevel { get; set; }
    public double BlurAngle { get; set; }
    public int Quality { get; set; } = 90;
    public bool Progressive { get; set; }
    public bool Chroma444 { get; set; }
    /// <summary>Código aleatório do nome do arquivo (ex.: a8f3k).</summary>
    public string Code { get; set; } = "00000";

    public static readonly char[] CodeAlphabet = "abcdefghijklmnopqrstuvwxyz0123456789".ToCharArray();

    public bool Equals(StoryParams? o)
    {
        if (o is null) return false;
        return CropFraction == o.CropFraction && CropShiftX == o.CropShiftX && CropShiftY == o.CropShiftY &&
               RotationDegrees == o.RotationDegrees && Brightness == o.Brightness && Contrast == o.Contrast &&
               Saturation == o.Saturation && NoiseAmplitude == o.NoiseAmplitude && NoiseOffsetX == o.NoiseOffsetX &&
               NoiseOffsetY == o.NoiseOffsetY && ChromaticChannel == o.ChromaticChannel && ChromaticDX == o.ChromaticDX &&
               ChromaticDY == o.ChromaticDY && GrainOpacity == o.GrainOpacity && GrainSoftLight == o.GrainSoftLight &&
               GrainOffsetX == o.GrainOffsetX && GrainOffsetY == o.GrainOffsetY && SharpenIntensity == o.SharpenIntensity &&
               SoftenRadius == o.SoftenRadius && Mirror == o.Mirror && Perspective.SequenceEqual(o.Perspective) &&
               PerspectiveMax == o.PerspectiveMax && TemperatureKelvin == o.TemperatureKelvin &&
               DiagonalAmplitude == o.DiagonalAmplitude && DiagonalPeriod == o.DiagonalPeriod && DiagonalAnti == o.DiagonalAnti &&
               DiagonalPhase == o.DiagonalPhase && Vignette == o.Vignette && LineOpacity == o.LineOpacity &&
               LineSpacing == o.LineSpacing && LineThickness == o.LineThickness && LineDirection == o.LineDirection &&
               LineBlend == o.LineBlend && LinePhase == o.LinePhase && LinePhase2 == o.LinePhase2 && LineStyle == o.LineStyle &&
               LineAngle == o.LineAngle && LineIrregularity == o.LineIrregularity && LineSeed == o.LineSeed &&
               JitterLevel == o.JitterLevel && JitterSeed == o.JitterSeed && AberrationDX == o.AberrationDX &&
               AberrationDY == o.AberrationDY && BloomLevel == o.BloomLevel && BlurAngle == o.BlurAngle &&
               Quality == o.Quality && Progressive == o.Progressive && Chroma444 == o.Chroma444 && Code == o.Code;
    }

    public override int GetHashCode() => HashCode.Combine(Code, Quality, CropFraction, RotationDegrees, JitterSeed, LineSeed);

    /// <summary>
    /// Sorteia os parâmetros de uma imagem.
    ///
    /// Todos os números são sempre sorteados na mesma ordem e só depois zerados conforme as etapas
    /// desligadas — assim, ligar ou desligar uma etapa não muda o sorteio das outras.
    /// </summary>
    public static StoryParams Sample(StoryOptions options, ulong seed)
    {
        var a = options.Adjustments;
        var rng = new SeededRandom(seed);
        double Unit() => rng.NextUnit();
        double Sym(double maxValue) => (Unit() * 2 - 1) * maxValue;

        // ordem fixa dos sorteios — não reordenar (mudaria o resultado de sementes já mostradas no preview)
        var cropU = Unit(); var shiftX = Sym(1); var shiftY = Sym(1); var rot = Sym(a.RotationMaxDegrees);
        var bri = Sym(a.BrightnessMaxPercent / 100); var con = Sym(a.ContrastMaxPercent / 100); var sat = Sym(a.SaturationMaxPercent / 100);
        var noiseU = Unit(); var nX = Unit() * 4096; var nY = Unit() * 4096;
        var chanRed = Unit() < 0.5; var dir = (int)(Unit() * 4) % 4;
        var grainU = Unit(); var grainSoft = Unit() < 0.5; var gX = Unit() * 4096; var gY = Unit() * 4096;
        var sharpenWins = Unit() < 0.5; var sharpenU = Unit();
        var qCount = StoryAdjustments.QualityRange.Hi - StoryAdjustments.QualityRange.Lo + 1;
        var q = StoryAdjustments.QualityRange.Lo + (int)(Unit() * qCount) % qCount;
        var prog = Unit() < 0.5; var c444 = Unit() < 0.5;
        var code = new StringBuilder();
        for (var i = 0; i < 5; i++) code.Append(CodeAlphabet[(int)(Unit() * CodeAlphabet.Length) % CodeAlphabet.Length]);
        // 1.0.0-beta.22: sorteios novos sempre no fim (sementes antigas continuam dando os mesmos valores acima)
        var corners = new double[8];
        for (var i = 0; i < 8; i++) corners[i] = Sym(1);
        var temp = Sym(a.TemperatureMaxKelvin);
        var chromaTwo = Unit() < 0.5;
        var diagU = Unit(); var diagFour = Unit() < 0.5; var diagAnti = Unit() < 0.5; var diagPhaseU = Unit();
        var vig = Sym(a.VignetteMaxPercent / 100);
        // 1.0.0-beta.23: texturas — sorteios novos no fim da sequência
        var t = options.Texture;
        var lineDirU = Unit(); var linePhaseU = Unit();
        var lineLevelU = Unit(); var jitterLevelU = Unit(); var aberrationLevelU = Unit(); var bloomLevelU = Unit();
        var aberrationAngleU = Unit(); var blurAngleU = Unit();
        var jitterSeed = rng.Next();
        // 1.0.0-beta.25: sorteios do Tom, também no fim
        var lineAngleU = Unit();
        var lineSeed = rng.Next();
        // 70% a 100% do nível escolhido.
        static double Level(double percent, double u) => percent / 100 * (0.7 + 0.3 * u);

        var p = new StoryParams { Code = code.ToString(), Mirror = options.Mirror, Quality = q };

        if (a.Geometry)
        {
            var lo = Math.Min(a.CropMinPercent, a.CropMaxPercent);
            p.CropFraction = (lo + cropU * (a.CropMaxPercent - lo)) / 100;
            p.CropShiftX = shiftX;
            p.CropShiftY = shiftY;
            p.RotationDegrees = rot;
        }
        if (a.Photometric)
        {
            p.Brightness = bri;
            p.Contrast = con;
            p.Saturation = sat;
        }
        if (a.Noise)
        {
            var lo = Math.Min(a.NoiseMinAmplitude, a.NoiseMaxAmplitude);
            p.NoiseAmplitude = lo + noiseU * (a.NoiseMaxAmplitude - lo);
            p.NoiseOffsetX = nX;
            p.NoiseOffsetY = nY;
        }
        if (a.ChromaticShift)
        {
            p.ChromaticChannel = chanRed ? Story.ChromaticChannel.Red : Story.ChromaticChannel.Blue;
            (int, int)[] moves = { (1, 0), (-1, 0), (0, 1), (0, -1) };
            var size = a.ChromaticMaxPixels >= 2 && chromaTwo ? 2 : 1;
            p.ChromaticDX = moves[dir].Item1 * size;
            p.ChromaticDY = moves[dir].Item2 * size;
        }
        if (a.FilmGrain)
        {
            var lo = Math.Min(a.GrainMinOpacityPercent, a.GrainMaxOpacityPercent);
            p.GrainOpacity = (lo + grainU * (a.GrainMaxOpacityPercent - lo)) / 100;
            p.GrainSoftLight = grainSoft;
            p.GrainOffsetX = gX;
            p.GrainOffsetY = gY;
        }
        if (a.Detail)
        {
            if (sharpenWins) p.SharpenIntensity = 0.2 + sharpenU * 0.2; else p.SoftenRadius = 0.2;
        }
        if (a.Perspective && a.PerspectiveMaxPercent > 0)
        {
            p.PerspectiveMax = a.PerspectiveMaxPercent / 100;
            p.Perspective = corners.Select(c => c * p.PerspectiveMax).ToArray();
        }
        if (a.Temperature) p.TemperatureKelvin = temp;
        if (a.Diagonal)
        {
            var lo = Math.Min(a.DiagonalMinAmplitude, a.DiagonalMaxAmplitude);
            p.DiagonalAmplitude = lo + diagU * (a.DiagonalMaxAmplitude - lo);
            p.DiagonalPeriod = diagFour ? 4 : 3;
            p.DiagonalAnti = diagAnti;
            p.DiagonalPhase = (int)(diagPhaseU * p.DiagonalPeriod) % p.DiagonalPeriod;
        }
        if (a.Vignette) p.Vignette = vig;
        if (t.Lines && t.LineOpacityPercent > 0)
        {
            // linhas variam pouco entre imagens (90% a 100% do nível): têm que aparecer em todas
            var lineLevel = t.LineOpacityPercent / 100 * (0.9 + 0.1 * lineLevelU);
            p.LineStyle = t.LineStyle;
            switch (t.LineStyle)
            {
                case StoryLineStyle.Ink:
                    p.LineOpacity = StoryTexture.LineAlpha(lineLevel);
                    break;
                case StoryLineStyle.Tone:
                    p.LineOpacity = StoryTexture.ToneAmplitude(lineLevel);
                    // ±3° por imagem em volta do ângulo escolhido
                    p.LineAngle = Math.Min(Math.Max(t.LineAngle + (lineAngleU * 2 - 1) * 3, StoryTexture.AngleRange.Lo), StoryTexture.AngleRange.Hi);
                    p.LineIrregularity = Math.Min(Math.Max(t.LineIrregularity / 100, 0), 1);
                    p.LineSeed = lineSeed;
                    break;
            }
            p.LineSpacing = Math.Max(4, (int)t.LineSpacing);
            p.LineThickness = Math.Max(2, Math.Min((int)t.LineThickness, p.LineSpacing - 2));
            p.LineBlend = t.LineBlend;
            switch (t.LineDirection)
            {
                case StoryLineDirection.Backslash:
                case StoryLineDirection.Slash:
                case StoryLineDirection.Cross:
                    p.LineDirection = t.LineDirection;
                    break;
                default:
                    StoryLineDirection[] choices = { StoryLineDirection.Backslash, StoryLineDirection.Slash, StoryLineDirection.Cross };
                    p.LineDirection = choices[Math.Min(2, (int)(lineDirU * 3))];
                    break;
            }
            p.LinePhase = Math.Min(p.LineSpacing - 1, (int)(linePhaseU * p.LineSpacing));
            p.LinePhase2 = (int)((jitterSeed >> 11) % (ulong)p.LineSpacing);
        }
        if (t.Jitter && t.JitterPercent > 0)
        {
            p.JitterLevel = Level(t.JitterPercent, jitterLevelU);
            p.JitterSeed = jitterSeed;
        }
        if (t.Aberration && t.AberrationPercent > 0)
        {
            var l = Level(t.AberrationPercent, aberrationLevelU);
            var px = Math.Max(1, (int)R.Round(1 + (StoryTexture.AberrationMaxPixels - 1) * l));
            var angle = aberrationAngleU * Math.PI;
            var dx = (int)R.Round(px * Math.Cos(angle));
            var dy = (int)R.Round(px * Math.Sin(angle));
            if (dx == 0 && dy == 0) dx = px;
            p.AberrationDX = dx;
            p.AberrationDY = dy;
        }
        if (t.Bloom && t.BloomPercent > 0)
        {
            p.BloomLevel = Level(t.BloomPercent, bloomLevelU);
            p.BlurAngle = blurAngleU * Math.PI;
        }
        if (a.JpegVariation && options.Format == StoryOutputFormat.Jpg)
        {
            p.Progressive = prog;
            p.Chroma444 = c444;
        }
        return p;
    }

    /// <summary>Há alguma etapa que roda sobre os pixels já desenhados (serrilhado e linhas)?</summary>
    public bool NeedsRasterPass => JitterLevel > 0 || LineOpacity > 0;

    /// <summary>Algum efeito de textura (linhas, serrilhado, aberração ou ofuscação) está ligado nesta imagem?</summary>
    public bool HasTexture => NeedsRasterPass || AberrationDX != 0 || AberrationDY != 0 || BloomLevel > 0;

    /// <summary>Cópia sem nenhum efeito de textura (para comparar "com" e "sem" no modal de inspeção).</summary>
    public StoryParams WithoutTexture => this with { LineOpacity = 0, JitterLevel = 0, AberrationDX = 0, AberrationDY = 0, BloomLevel = 0 };

    /// <summary>Ampliação mínima para que uma rotação de <paramref name="degrees"/> não deixe cantos vazios.</summary>
    public static double RotationZoom(double width, double height, double degrees)
    {
        var t = Math.Abs(degrees) * Math.PI / 180;
        if (!(t > 0) || width <= 0 || height <= 0) return 1;
        double c = Math.Cos(t), s = Math.Sin(t);
        return Math.Max((width * c + height * s) / width, (width * s + height * c) / height);
    }

    /// <summary>
    /// Valor (−1, 0 ou +1) do risco diagonal no pixel (x, y): −1 escurece, +1 clareia, 0 mantém o tom.
    /// Período 3: −1, +1, 0. Período 4: −1, 0, +1, 0. A média é zero, então o tom geral não muda.
    /// </summary>
    public static int DiagonalSign(int x, int y, int period, bool anti, int phase)
    {
        var p = period == 4 ? 4 : 3;
        int[] pattern = p == 4 ? new[] { -1, 0, 1, 0 } : new[] { -1, 1, 0 };
        var k = ((anti ? x - y : x + y) + phase) % p;
        return pattern[(k + p) % p];
    }

    private static string F(double v, string fmt) => v.ToString(fmt, CultureInfo.InvariantCulture);
    private static string Signed(double v, string fmt) => (v >= 0 ? "+" : "") + F(v, fmt);

    /// <summary>Resumo curto para o status do arquivo e o Histórico.</summary>
    public string Summary
    {
        get
        {
            var parts = new List<string>();
            if (CropFraction > 0) parts.Add($"recorte {F(CropFraction * 100, "0.00")}%");
            if (RotationDegrees != 0) parts.Add($"rot {Signed(RotationDegrees, "0.00")}°");
            if (Brightness != 0 || Contrast != 0 || Saturation != 0)
                parts.Add($"br {Signed(Brightness * 100, "0.0")}% ct {Signed(Contrast * 100, "0.0")}% sat {Signed(Saturation * 100, "0.0")}%");
            if (NoiseAmplitude > 0) parts.Add($"ruído ±{F(NoiseAmplitude, "0.0")}");
            if (ChromaticChannel is ChromaticChannel ch) parts.Add($"canal {(ch == Story.ChromaticChannel.Red ? "R" : "B")} {ChromaticDX},{ChromaticDY}px");
            if (GrainOpacity > 0) parts.Add($"grão {F(GrainOpacity * 100, "0.0")}% " + (GrainSoftLight ? "soft-light" : "overlay"));
            if (SharpenIntensity > 0) parts.Add($"nitidez {F(SharpenIntensity, "0.00")}");
            if (SoftenRadius > 0) parts.Add($"suaviza {F(SoftenRadius, "0.0")}px");
            if (PerspectiveMax > 0) parts.Add($"perspectiva ±{F(PerspectiveMax * 100, "0.0")}%");
            if (TemperatureKelvin != 0) parts.Add($"temperatura {Signed(TemperatureKelvin, "0")}K");
            if (DiagonalAmplitude > 0)
                parts.Add("riscos " + (DiagonalAnti ? "/" : "\\") + $" ±{F(DiagonalAmplitude, "0.0")} (período {DiagonalPeriod})");
            if (Vignette != 0) parts.Add($"vinheta {Signed(Vignette * 100, "0.0")}%");
            if (LineOpacity > 0)
            {
                var d = LineDirection switch
                {
                    StoryLineDirection.Backslash => "\\",
                    StoryLineDirection.Slash => "/",
                    _ => "X",
                };
                parts.Add(LineStyle == StoryLineStyle.Ink
                    ? $"linhas {d} {LineSpacing}px/{LineThickness}px {LineBlend.Label().ToLowerInvariant()} {F(LineOpacity * 100, "0")}%"
                    : $"linhas no tom {d} {F(LineAngle, "0")}° {LineSpacing}px/{LineThickness}px ±{F(LineOpacity * 100, "0")}%");
            }
            if (JitterLevel > 0) parts.Add($"serrilhado {F(JitterLevel * 100, "0")}%");
            if (AberrationDX != 0 || AberrationDY != 0) parts.Add($"aberração RGB {AberrationDX},{AberrationDY}px");
            if (BloomLevel > 0) parts.Add($"ofuscação {F(BloomLevel * 100, "0")}%");
            if (Mirror) parts.Add("espelhado");
            parts.Add($"q{Quality}{(Progressive ? " progressivo" : "")}{(Chroma444 ? " 4:4:4" : " 4:2:0")}");
            return string.Join(" · ", parts);
        }
    }
}

// MARK: - Nomes dos arquivos

public static class StoryNames
{
    /// <summary>Prefixo seguro para nome de arquivo (sem acento, espaço ou símbolo). Vazio vira "story".</summary>
    public static string CleanPrefix(string s)
    {
        var folded = Storage.Paths.FoldDiacritics(s).ToLowerInvariant();
        var sb = new StringBuilder();
        foreach (var ch in folded)
        {
            var ok = (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') || ch == '_' || ch == '-';
            sb.Append(ok ? ch : '_');
        }
        var o = sb.ToString();
        while (o.Contains("__")) o = o.Replace("__", "_");
        o = o.Trim('_', '-');
        return o.Length == 0 ? "story" : o[..Math.Min(40, o.Length)];
    }

    /// <summary>story_001_a8f3k.jpg (ou story_001.jpg). Com várias versões por imagem: story_001_v2_a8f3k.jpg.</summary>
    public static string FileName(int index, int total, string prefix, string code, StoryNaming naming, string ext, int? version = null)
    {
        var width = Math.Max(3, Math.Max(total, 1).ToString(CultureInfo.InvariantCulture).Length);
        var number = Math.Max(index, 0).ToString(CultureInfo.InvariantCulture).PadLeft(width, '0');
        var @base = $"{CleanPrefix(prefix)}_{number}" + (version is int v ? $"_v{v}" : "");
        return naming == StoryNaming.SequentialCode ? $"{@base}_{code}.{ext}" : $"{@base}.{ext}";
    }
}

// MARK: - Versões

public static class StoryVersions
{
    /// <summary>Semente da versão <paramref name="v"/> (1 = a própria semente da imagem, que é a do preview).</summary>
    public static ulong Seed(ulong @base, int v)
    {
        if (v <= 1) return @base;
        var rng = new SeededRandom(@base ^ unchecked((ulong)v * 0xD6E8FEB86659FD93UL));
        return rng.Next();
    }
}

// MARK: - Cor dominante

public static class DominantColor
{
    /// <summary>
    /// Cor mais frequente de uma miniatura RGBA8 (pré-multiplicada ou não): agrupa em caixas de 4 bits
    /// por canal e devolve a média da caixa mais cheia. Ignora pixels quase transparentes.
    /// </summary>
    public static RGBColor? Compute(byte[] rgba)
    {
        var counts = new int[4096];
        var sumR = new int[4096];
        var sumG = new int[4096];
        var sumB = new int[4096];
        for (var i = 0; i + 3 < rgba.Length; i += 4)
        {
            int a = rgba[i + 3];
            if (a < 128) continue;
            // desfaz a pré-multiplicação (sem efeito quando a = 255)
            var r = Math.Min(255, rgba[i] * 255 / a);
            var g = Math.Min(255, rgba[i + 1] * 255 / a);
            var b = Math.Min(255, rgba[i + 2] * 255 / a);
            var bin = ((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4);
            counts[bin]++;
            sumR[bin] += r;
            sumG[bin] += g;
            sumB[bin] += b;
        }
        var best = 0;
        for (var k = 1; k < 4096; k++)
            if (counts[k] >= counts[best] && counts[k] > counts[best]) best = k;
        if (counts[best] == 0) return null;
        double n = counts[best];
        return new RGBColor(sumR[best] / n / 255, sumG[best] / n / 255, sumB[best] / n / 255);
    }
}
