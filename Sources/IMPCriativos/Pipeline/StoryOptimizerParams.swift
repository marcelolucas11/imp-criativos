import Foundation

// 1.0.0-beta.21: Otimizador em Lote (Stories 9:16) — opções, presets e sorteio dos parâmetros de cada imagem.
//
// Arquivo puro (só Foundation) para rodar nos testes automáticos sem o app. A parte de imagem
// (Core Image + libjpeg-turbo) fica em StoryOptimizer.swift.
//
// Cada imagem recebe uma semente quando entra no lote. Os parâmetros saem dessa semente, então o
// preview mostra exatamente o arquivo que vai sair, e "Novo sorteio" só troca a semente.

// MARK: - Gerador com semente

/// SplitMix64: mesma semente → mesma sequência de números.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - Opções da tela

enum StoryFit: String, CaseIterable, Identifiable, Codable {
    case cover
    case blurFit
    case solid

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cover: return "Preencher"
        case .blurFit: return "Fundo desfocado"
        case .solid: return "Cor sólida"
        }
    }

    var hint: String {
        switch self {
        case .cover: return "Preenche todo o 1080×1920 e corta o que sobrar pelo centro (pode cortar texto nas bordas)."
        case .blurFit: return "Mantém a imagem inteira no centro e preenche em cima e embaixo com uma cópia ampliada e desfocada dela."
        case .solid: return "Mantém a imagem inteira no centro sobre uma cor de fundo."
        }
    }
}

enum StorySolidColor: String, CaseIterable, Identifiable, Codable {
    case black
    case dominant
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .black: return "Preto"
        case .dominant: return "Cor dominante"
        case .custom: return "Escolher cor"
        }
    }
}

enum StoryIntensity: String, CaseIterable, Identifiable, Codable {
    case light
    case moderate
    /// 1.0.0-beta.22: níveis maiores.
    case normal
    case aggressive
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: return "Leve"
        case .moderate: return "Moderado"
        case .normal: return "Normal"
        case .aggressive: return "Agressivo"
        case .custom: return "Personalizado"
        }
    }

    var hint: String {
        switch self {
        case .light: return "Imperceptível."
        case .moderate: return "Quase imperceptível (os intervalos do pedido original)."
        case .normal: return "Percebe-se de perto, comparando lado a lado. Liga riscos diagonais, perspectiva, temperatura e vinheta."
        case .aggressive: return "Diferença visível (cor, enquadramento e textura), mas o olho reconhece que é a mesma peça. Confira no preview."
        case .custom: return "Uma chave e um limite por etapa."
        }
    }
}

enum StoryOutputFormat: String, CaseIterable, Identifiable, Codable {
    case jpg
    case png

    var id: String { rawValue }
    var label: String { self == .jpg ? "JPEG" : "PNG" }
    var fileExtension: String { rawValue }
}

enum StoryNaming: String, CaseIterable, Identifiable, Codable {
    case sequential
    case sequentialCode

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sequential: return "Sequencial (story_001)"
        case .sequentialCode: return "Sequencial + código (story_001_a8f3k)"
        }
    }
}

struct RGBColor: Codable, Equatable {
    var r: Double
    var g: Double
    var b: Double

    static let black = RGBColor(r: 0, g: 0, b: 0)
}

/// Quais etapas sutis rodam e até onde vão. O sorteio de cada imagem fica dentro desses limites.
struct StoryAdjustments: Codable, Equatable {
    /// Micro-recorte (por borda) e micro-rotação.
    var geometry = true
    var cropMinPercent = 0.5
    var cropMaxPercent = 1.5
    var rotationMaxDegrees = 0.8
    /// 1.0.0-beta.22: micro-perspectiva — cada canto anda até X% do lado.
    var perspective = false
    var perspectiveMaxPercent = 0.6
    /// Brilho, contraste e saturação.
    var photometric = true
    var brightnessMaxPercent = 2.0
    var contrastMaxPercent = 2.0
    var saturationMaxPercent = 3.0
    /// 1.0.0-beta.22: temperatura de cor (mais quente ou mais fria), em kelvin.
    var temperature = false
    var temperatureMaxKelvin = 250.0
    /// Micro-ruído nos canais RGB (níveis de 0–255).
    var noise = true
    var noiseMinAmplitude = 2.0
    var noiseMaxAmplitude = 4.0
    /// Deslocamento de 1px (ou até 2px) no canal vermelho ou azul.
    var chromaticShift = true
    var chromaticMaxPixels = 1
    /// Granulação de filme (overlay ou soft-light).
    var filmGrain = true
    var grainMinOpacityPercent = 1.0
    var grainMaxOpacityPercent = 3.0
    /// 1.0.0-beta.22: riscos diagonais pixel a pixel — uma linha escurece, a seguinte clareia, a outra mantém o tom.
    var diagonal = false
    var diagonalMinAmplitude = 2.0
    var diagonalMaxAmplitude = 5.0
    /// 1.0.0-beta.22: vinheta — bordas mais escuras ou mais claras (% da escala nos cantos).
    var vignette = false
    var vignetteMaxPercent = 5.0
    /// Unsharp Mask leve ou suavização mínima, sorteado.
    var detail = true
    /// Baseline ou progressivo e subamostragem 4:2:0 ou 4:4:4, sorteados (só JPEG).
    var jpegVariation = true

    // Limites dos sliders do Personalizado (vão até o Agressivo)
    static let cropRange: ClosedRange<Double> = 0.5...5
    static let rotationRange: ClosedRange<Double> = 0...3
    static let perspectiveRange: ClosedRange<Double> = 0...2
    static let brightnessRange: ClosedRange<Double> = 0...8
    static let contrastRange: ClosedRange<Double> = 0...8
    static let saturationRange: ClosedRange<Double> = 0...12
    static let temperatureRange: ClosedRange<Double> = 0...800
    static let noiseRange: ClosedRange<Double> = 2...8
    static let chromaticRange: ClosedRange<Int> = 1...2
    static let grainRange: ClosedRange<Double> = 1...8
    static let diagonalRange: ClosedRange<Double> = 1...12
    static let vignetteRange: ClosedRange<Double> = 0...15
    static let qualityRange: ClosedRange<Int> = 88...93

    /// Leve (imperceptível): intervalos curtos, sem deslocamento de canal nem granulação.
    static let light: StoryAdjustments = {
        var a = StoryAdjustments()
        a.cropMaxPercent = 0.8
        a.rotationMaxDegrees = 0.3
        a.brightnessMaxPercent = 1
        a.contrastMaxPercent = 1
        a.saturationMaxPercent = 1.5
        a.noiseMaxAmplitude = 2.5
        a.chromaticShift = false
        a.filmGrain = false
        a.grainMaxOpacityPercent = 1.5
        return a
    }()

    /// Moderado: os intervalos do pedido original (beta.21), com todas as etapas de lá ligadas.
    static let moderate = StoryAdjustments()

    /// Normal (beta.22): o dobro do Moderado e as etapas novas ligadas.
    static let normal: StoryAdjustments = {
        var a = StoryAdjustments()
        a.cropMinPercent = 1
        a.cropMaxPercent = 3
        a.rotationMaxDegrees = 1.5
        a.perspective = true
        a.perspectiveMaxPercent = 0.6
        a.brightnessMaxPercent = 4
        a.contrastMaxPercent = 4
        a.saturationMaxPercent = 6
        a.temperature = true
        a.temperatureMaxKelvin = 300
        a.noiseMinAmplitude = 3
        a.noiseMaxAmplitude = 6
        a.grainMinOpacityPercent = 2
        a.grainMaxOpacityPercent = 5
        a.diagonal = true
        a.diagonalMinAmplitude = 2
        a.diagonalMaxAmplitude = 5
        a.vignette = true
        a.vignetteMaxPercent = 5
        return a
    }()

    /// Agressivo (beta.22): variação visível, mesma peça reconhecível.
    static let aggressive: StoryAdjustments = {
        var a = StoryAdjustments()
        a.cropMinPercent = 2
        a.cropMaxPercent = 5
        a.rotationMaxDegrees = 2
        a.perspective = true
        a.perspectiveMaxPercent = 1.5
        a.brightnessMaxPercent = 7
        a.contrastMaxPercent = 7
        a.saturationMaxPercent = 10
        a.temperature = true
        a.temperatureMaxKelvin = 650
        a.noiseMinAmplitude = 5
        a.noiseMaxAmplitude = 8
        a.chromaticMaxPixels = 2
        a.grainMinOpacityPercent = 4
        a.grainMaxOpacityPercent = 8
        a.diagonal = true
        a.diagonalMinAmplitude = 5
        a.diagonalMaxAmplitude = 10
        a.vignette = true
        a.vignetteMaxPercent = 12
        return a
    }()

    /// Mantém cada valor dentro dos limites (protege contra configuração salva estragada) e mínimo ≤ máximo.
    func clamped() -> StoryAdjustments {
        func c(_ v: Double, _ r: ClosedRange<Double>) -> Double { v.isFinite ? min(max(v, r.lowerBound), r.upperBound) : r.lowerBound }
        var a = self
        a.cropMaxPercent = c(cropMaxPercent, Self.cropRange)
        a.cropMinPercent = min(c(cropMinPercent, Self.cropRange), a.cropMaxPercent)
        a.rotationMaxDegrees = c(rotationMaxDegrees, Self.rotationRange)
        a.perspectiveMaxPercent = c(perspectiveMaxPercent, Self.perspectiveRange)
        a.brightnessMaxPercent = c(brightnessMaxPercent, Self.brightnessRange)
        a.contrastMaxPercent = c(contrastMaxPercent, Self.contrastRange)
        a.saturationMaxPercent = c(saturationMaxPercent, Self.saturationRange)
        a.temperatureMaxKelvin = c(temperatureMaxKelvin, Self.temperatureRange)
        a.noiseMaxAmplitude = c(noiseMaxAmplitude, Self.noiseRange)
        a.noiseMinAmplitude = min(c(noiseMinAmplitude, Self.noiseRange), a.noiseMaxAmplitude)
        a.chromaticMaxPixels = min(max(chromaticMaxPixels, Self.chromaticRange.lowerBound), Self.chromaticRange.upperBound)
        a.grainMaxOpacityPercent = c(grainMaxOpacityPercent, Self.grainRange)
        a.grainMinOpacityPercent = min(c(grainMinOpacityPercent, Self.grainRange), a.grainMaxOpacityPercent)
        a.diagonalMaxAmplitude = c(diagonalMaxAmplitude, Self.diagonalRange)
        a.diagonalMinAmplitude = min(c(diagonalMinAmplitude, Self.diagonalRange), a.diagonalMaxAmplitude)
        a.vignetteMaxPercent = c(vignetteMaxPercent, Self.vignetteRange)
        return a
    }
}

extension StoryAdjustments {
    // Leitura tolerante: ajustes salvos por versões anteriores (sem os campos novos) continuam valendo.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T { (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback }
        geometry = v(.geometry, geometry)
        cropMinPercent = v(.cropMinPercent, cropMinPercent)
        cropMaxPercent = v(.cropMaxPercent, cropMaxPercent)
        rotationMaxDegrees = v(.rotationMaxDegrees, rotationMaxDegrees)
        perspective = v(.perspective, perspective)
        perspectiveMaxPercent = v(.perspectiveMaxPercent, perspectiveMaxPercent)
        photometric = v(.photometric, photometric)
        brightnessMaxPercent = v(.brightnessMaxPercent, brightnessMaxPercent)
        contrastMaxPercent = v(.contrastMaxPercent, contrastMaxPercent)
        saturationMaxPercent = v(.saturationMaxPercent, saturationMaxPercent)
        temperature = v(.temperature, temperature)
        temperatureMaxKelvin = v(.temperatureMaxKelvin, temperatureMaxKelvin)
        noise = v(.noise, noise)
        noiseMinAmplitude = v(.noiseMinAmplitude, noiseMinAmplitude)
        noiseMaxAmplitude = v(.noiseMaxAmplitude, noiseMaxAmplitude)
        chromaticShift = v(.chromaticShift, chromaticShift)
        chromaticMaxPixels = v(.chromaticMaxPixels, chromaticMaxPixels)
        filmGrain = v(.filmGrain, filmGrain)
        grainMinOpacityPercent = v(.grainMinOpacityPercent, grainMinOpacityPercent)
        grainMaxOpacityPercent = v(.grainMaxOpacityPercent, grainMaxOpacityPercent)
        diagonal = v(.diagonal, diagonal)
        diagonalMinAmplitude = v(.diagonalMinAmplitude, diagonalMinAmplitude)
        diagonalMaxAmplitude = v(.diagonalMaxAmplitude, diagonalMaxAmplitude)
        vignette = v(.vignette, vignette)
        vignetteMaxPercent = v(.vignetteMaxPercent, vignetteMaxPercent)
        detail = v(.detail, detail)
        jpegVariation = v(.jpegVariation, jpegVariation)
    }
}

// MARK: - Texturas, linhas e bordas (beta.23)

/// Direção das linhas diagonais. `random` sorteia \, / ou X por imagem.
enum StoryLineDirection: String, CaseIterable, Identifiable, Codable {
    case backslash
    case slash
    case cross
    case random

    var id: String { rawValue }

    var label: String {
        switch self {
        case .backslash: return "Diagonal esquerda (\\)"
        case .slash: return "Diagonal direita (/)"
        case .cross: return "Cruzada (X)"
        case .random: return "Aleatória por imagem"
        }
    }

    /// Rótulo curto dos botões de direção.
    var shortLabel: String {
        switch self {
        case .backslash: return "Esquerda \\"
        case .slash: return "Direita /"
        case .cross: return "Cruzada X"
        case .random: return "Aleatória"
        }
    }
}

/// 1.0.0-beta.25: estilo das linhas.
/// - `tone`: mantém a cor. Só clareia e escurece o próprio pixel (multiplica R, G e B pelo mesmo fator), de leve, com borda suave,
///   ângulo livre e linhas irregulares (riscos de comprimento e força diferentes, com falhas), como chuva ou filme riscado.
/// - `ink`: gravura em preto e branco (beta.24): faixa escura com realce claro, pixel exato a 45°, hard-light ou overlay.
enum StoryLineStyle: String, CaseIterable, Identifiable, Codable {
    case tone
    case ink

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tone: return "Tom (mantém a cor)"
        case .ink: return "Gravura (preto e branco)"
        }
    }

    var hint: String {
        switch self {
        case .tone:
            return "Clareia e escurece o próprio pixel sem trocar a cor: o verde continua verde, o amarelo continua amarelo. Borda suave, riscos irregulares e quase nada sobre áreas muito claras (texto branco fica limpo)."
        case .ink:
            return "Faixa escura (preto) com um realce claro (branco) colado. Bem marcado e digital: aparece até sobre texto branco e fundo preto."
        }
    }
}

/// Modo de mistura das linhas com a imagem (beta.24: só os de alto impacto; Multiply e Soft-light saíram).
/// As linhas são faixas de contraste duplo: uma faixa escura (tinta preta) e, colada nela, uma faixa fina de realce claro (tinta branca).
enum StoryLineBlend: String, CaseIterable, Identifiable, Codable {
    /// Hard-light com tinta preta e branca: multiplica nas faixas escuras e faz screen nas de realce. Aparece em qualquer cor.
    case hardLight
    /// Overlay: o contraste da própria imagem decide (mais forte nas luzes para a faixa escura e nas sombras para o realce).
    case overlay

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hardLight: return "Hard-light"
        case .overlay: return "Overlay"
        }
    }
}

enum StoryTexturePreset: String, CaseIterable, Identifiable, Codable {
    case off
    case subtle
    case balanced
    case intense
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: return "Desligado"
        case .subtle: return "Sutil"
        case .balanced: return "Equilibrado"
        case .intense: return "Intenso"
        case .custom: return "Personalizado"
        }
    }

    var hint: String {
        switch self {
        case .off: return "Sem linhas, serrilhado, aberração nem bloom."
        case .subtle: return "Linhas leves, micro-aberração e serrilhado mínimo. O texto continua limpo."
        case .balanced: return "Linhas bem visíveis, serrilhado moderado e deslocamento RGB médio."
        case .intense: return "Linhas fortes, serrilhado alto, aberração cromática e bloom fortes. Confira o texto no zoom antes de processar o lote."
        case .custom: return "Sliders das linhas (do estilo escolhido acima) e uma chave e um slider (0 a 100%) para cada efeito."
        }
    }
}

/// Efeitos de textura e estilização das bordas. Cada um liga e desliga sozinho; os sliders vão de 0 a 100%.
/// O nível é o máximo: cada imagem sorteia entre 70% e 100% dele (a direção "aleatória" das linhas também é sorteada).
struct StoryTexture: Codable, Equatable {
    /// Linhas diagonais por cima da imagem (pixel exato, sem reamostragem).
    var lines = false
    var lineDirection: StoryLineDirection = .random
    /// Intensidade (0–100%), com curva própria (ver `lineAlpha`): 10–25% visível e sutil, 50% bem marcado, 80–100% forte.
    var lineOpacityPercent = 50.0
    /// Em pixels da saída 1080×1920, medidos na horizontal. Espaçamento = período das linhas; espessura = faixa escura.
    var lineSpacing = 10.0
    var lineThickness = 2.0
    var lineBlend: StoryLineBlend = .hardLight
    /// 1.0.0-beta.25: estilo, ângulo (só no Tom; a Gravura fica em 45° pixel exato) e irregularidade (só no Tom).
    var lineStyle: StoryLineStyle = .tone
    var lineAngle = 55.0
    var lineIrregularity = 60.0
    /// Serrilhado: quebra o anti-aliasing só nas bordas de alto contraste (texto, botões).
    var jitter = false
    var jitterPercent = 40.0
    /// Aberração cromática: R e B andam em sentidos opostos (1px a 6px conforme o nível).
    var aberration = false
    var aberrationPercent = 40.0
    /// Ofuscação: bloom nas luzes + micro-desfoque direcional (do levemente estilizado ao quase ilegível).
    var bloom = false
    var bloomPercent = 30.0

    static let percentRange: ClosedRange<Double> = 0...100
    static let spacingRange: ClosedRange<Double> = 4...18
    static let thicknessRange: ClosedRange<Double> = 2...8
    static let aberrationMaxPixels = 6
    /// Teto da opacidade da faixa escura (a leitura do texto não some mesmo com o slider em 100%).
    static let lineOpacityCap = 0.85
    /// A faixa de realce claro tem 60% da opacidade da escura.
    static let lineHighlightRatio = 0.6
    /// No modo Cruzada (X) cada camada usa 65% da opacidade, para a malha não escurecer nem estourar a imagem.
    static let lineCrossBalance = 0.65
    /// Tom: ângulo das linhas em graus a partir da horizontal (45° = diagonal exata; mais alto = mais em pé).
    static let angleRange: ClosedRange<Double> = 30...75
    /// Tom: variação máxima do brilho no centro da linha com o slider em 100% (±35%). A cor nunca muda.
    static let toneAmplitudeCap = 0.35
    /// Tom: comprimento médio de cada trecho de risco (px) — a força muda de um trecho para o outro, e alguns somem.
    static let toneSegmentLength = 36.0

    /// Curva do slider no Tom (0 a 1) → variação de brilho no centro da linha:
    /// 10% ≈ 5% · 25% ≈ 11% · 50% ≈ 20% · 80% ≈ 30% · 100% = 35%.
    static func toneAmplitude(level: Double) -> Double {
        let l = min(max(level.isFinite ? level : 0, 0), 1)
        return toneAmplitudeCap * pow(l, 0.8)
    }

    /// Curva do slider (0 a 1) → opacidade da faixa escura: 10% ≈ 0,17 · 25% ≈ 0,32 · 50% ≈ 0,52 · 80% ≈ 0,73 · 100% = 0,85.
    static func lineAlpha(level: Double) -> Double {
        let l = min(max(level.isFinite ? level : 0, 0), 1)
        return lineOpacityCap * pow(l, 0.7)
    }

    /// Largura da faixa de realce: um terço da escura (mínimo 1px), sempre sobrando pelo menos 1px de intervalo.
    static func lineHighlightWidth(spacing: Int, thickness: Int) -> Int {
        max(1, min(Int((Double(thickness) / 3).rounded()), spacing - thickness - 1))
    }

    static let none = StoryTexture()

    var isActive: Bool {
        (lines && lineOpacityPercent > 0) || (jitter && jitterPercent > 0)
            || (aberration && aberrationPercent > 0) || (bloom && bloomPercent > 0)
    }

    /// Sutil: linhas leves + micro-aberração + serrilhado mínimo.
    static let subtle: StoryTexture = {
        var t = StoryTexture()
        t.lines = true
        t.lineDirection = .random
        t.lineStyle = .tone
        t.lineOpacityPercent = 30
        t.lineSpacing = 10
        t.lineThickness = 2
        t.lineAngle = 55
        t.lineIrregularity = 60
        t.lineBlend = .hardLight
        t.jitter = true
        t.jitterPercent = 15
        t.aberration = true
        t.aberrationPercent = 15
        return t
    }()

    /// Equilibrado: linhas visíveis + serrilhado moderado + deslocamento RGB médio.
    static let balanced: StoryTexture = {
        var t = StoryTexture()
        t.lines = true
        t.lineDirection = .random
        t.lineStyle = .tone
        t.lineOpacityPercent = 60
        t.lineSpacing = 9
        t.lineThickness = 3
        t.lineAngle = 55
        t.lineIrregularity = 50
        t.lineBlend = .hardLight
        t.jitter = true
        t.jitterPercent = 45
        t.aberration = true
        t.aberrationPercent = 45
        return t
    }()

    /// Intenso: linhas marcadas + serrilhado alto + aberração e bloom fortes.
    static let intense: StoryTexture = {
        var t = StoryTexture()
        t.lines = true
        t.lineDirection = .cross
        t.lineStyle = .ink
        t.lineOpacityPercent = 85
        t.lineSpacing = 8
        t.lineThickness = 4
        t.lineBlend = .hardLight
        t.jitter = true
        t.jitterPercent = 80
        t.aberration = true
        t.aberrationPercent = 80
        t.bloom = true
        t.bloomPercent = 70
        return t
    }()

    /// Mantém tudo dentro dos limites e a espessura menor que o espaçamento (senão não sobra intervalo entre as linhas).
    func clamped() -> StoryTexture {
        func c(_ v: Double, _ r: ClosedRange<Double>) -> Double { v.isFinite ? min(max(v, r.lowerBound), r.upperBound) : r.lowerBound }
        var t = self
        t.lineOpacityPercent = c(lineOpacityPercent, Self.percentRange)
        t.lineSpacing = c(lineSpacing, Self.spacingRange).rounded()
        // pelo menos 2px de folga: sobra espaço para a faixa de realce e para um intervalo
        t.lineThickness = max(Self.thicknessRange.lowerBound, min(c(lineThickness, Self.thicknessRange).rounded(), t.lineSpacing - 2))
        t.lineAngle = c(lineAngle, Self.angleRange).rounded()
        t.lineIrregularity = c(lineIrregularity, Self.percentRange)
        t.jitterPercent = c(jitterPercent, Self.percentRange)
        t.aberrationPercent = c(aberrationPercent, Self.percentRange)
        t.bloomPercent = c(bloomPercent, Self.percentRange)
        return t
    }

    /// Leitura tolerante: chave nova ou ausente nunca derruba o que já estava salvo.
    init() {}

    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T { (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback }
        lines = v(.lines, lines)
        lineDirection = v(.lineDirection, lineDirection)
        lineOpacityPercent = v(.lineOpacityPercent, lineOpacityPercent)
        lineSpacing = v(.lineSpacing, lineSpacing)
        lineThickness = v(.lineThickness, lineThickness)
        lineBlend = v(.lineBlend, lineBlend)
        // opções salvas antes da beta.25 não têm estilo: eram todas gravura
        lineStyle = v(.lineStyle, StoryLineStyle.ink)
        lineAngle = v(.lineAngle, lineAngle)
        lineIrregularity = v(.lineIrregularity, lineIrregularity)
        jitter = v(.jitter, jitter)
        jitterPercent = v(.jitterPercent, jitterPercent)
        aberration = v(.aberration, aberration)
        aberrationPercent = v(.aberrationPercent, aberrationPercent)
        bloom = v(.bloom, bloom)
        bloomPercent = v(.bloomPercent, bloomPercent)
    }
}

/// 1.0.0-beta.26: medidas das linhas de um estilo. Cada estilo (Tom e Gravura) tem os próprios níveis Sutil, Equilibrado e
/// Intenso e o próprio Personalizado; ligar as linhas, o estilo e a direção ficam fora do nível, escolhidos antes.
struct StoryLineSettings: Codable, Equatable {
    /// Intensidade (0–100%). No Tom vira variação de brilho (`toneAmplitude`); na Gravura, opacidade da faixa escura (`lineAlpha`).
    var opacityPercent = 50.0
    var spacing = 10.0
    var thickness = 2.0
    /// Só no Tom.
    var angle = 55.0
    var irregularity = 60.0
    /// Só na Gravura.
    var blend: StoryLineBlend = .hardLight

    init() {}

    init(opacityPercent: Double, spacing: Double, thickness: Double, angle: Double = 55, irregularity: Double = 0, blend: StoryLineBlend = .hardLight) {
        self.opacityPercent = opacityPercent
        self.spacing = spacing
        self.thickness = thickness
        self.angle = angle
        self.irregularity = irregularity
        self.blend = blend
    }

    /// As medidas de linha guardadas num `StoryTexture` (usado para migrar opções salvas antes da beta.26).
    init(texture t: StoryTexture) {
        self.init(opacityPercent: t.lineOpacityPercent, spacing: t.lineSpacing, thickness: t.lineThickness,
                  angle: t.lineAngle, irregularity: t.lineIrregularity, blend: t.lineBlend)
    }

    func apply(to t: inout StoryTexture) {
        t.lineOpacityPercent = opacityPercent
        t.lineSpacing = spacing
        t.lineThickness = thickness
        t.lineAngle = angle
        t.lineIrregularity = irregularity
        t.lineBlend = blend
    }

    /// Níveis de cada estilo. Desligado e Personalizado não têm nível próprio (devolvem o Equilibrado).
    static func preset(_ level: StoryTexturePreset, style: StoryLineStyle) -> StoryLineSettings {
        switch (style, level) {
        case (.tone, .subtle): return StoryLineSettings(opacityPercent: 30, spacing: 10, thickness: 2, angle: 55, irregularity: 60)
        case (.tone, .intense): return StoryLineSettings(opacityPercent: 90, spacing: 8, thickness: 3, angle: 55, irregularity: 40)
        case (.tone, _): return StoryLineSettings(opacityPercent: 60, spacing: 9, thickness: 3, angle: 55, irregularity: 50)
        case (.ink, .subtle): return StoryLineSettings(opacityPercent: 20, spacing: 12, thickness: 2, blend: .hardLight)
        case (.ink, .intense): return StoryLineSettings(opacityPercent: 85, spacing: 8, thickness: 4, blend: .hardLight)
        case (.ink, _): return StoryLineSettings(opacityPercent: 50, spacing: 8, thickness: 3, blend: .hardLight)
        }
    }

    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T { (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback }
        opacityPercent = v(.opacityPercent, opacityPercent)
        spacing = v(.spacing, spacing)
        thickness = v(.thickness, thickness)
        angle = v(.angle, angle)
        irregularity = v(.irregularity, irregularity)
        blend = v(.blend, blend)
    }
}

/// Tudo o que a tela do Otimizador escolhe. Fica salvo entre aberturas do app.
struct StoryOptions: Codable, Equatable {
    var fit: StoryFit = .blurFit
    var solidColor: StorySolidColor = .black
    var customColor: RGBColor = .black
    var intensity: StoryIntensity = .light
    /// Valores do modo Personalizado (começa igual ao Moderado).
    var custom: StoryAdjustments = .moderate
    /// Espelhar na horizontal — desligado de fábrica (só para imagens sem texto).
    var mirror = false
    var format: StoryOutputFormat = .jpg
    var naming: StoryNaming = .sequentialCode
    var prefix = "story"
    /// 1.0.0-beta.22: quantas versões diferentes sair de cada imagem (1 a 10).
    var versionsPerImage = 1
    /// 1.0.0-beta.23: texturas, linhas e bordas (desligado de fábrica: quem já usa o app não vê mudança).
    var texturePreset: StoryTexturePreset = .off
    /// Valores do modo Personalizado das texturas (começa na cópia do preset que estava em uso).
    /// beta.26: daqui só valem serrilhado, aberração e ofuscação; as linhas vêm dos campos abaixo.
    var customTexture: StoryTexture = .balanced
    /// 1.0.0-beta.26: as linhas são escolhidas antes do nível: liga/desliga, estilo e direção valem para qualquer nível.
    var linesEnabled = false
    var lineStyle: StoryLineStyle = .tone
    var lineDirection: StoryLineDirection = .random
    /// Personalizado das linhas, um para cada estilo (trocar o estilo não mistura as medidas de um com o outro).
    var customToneLines = StoryLineSettings.preset(.balanced, style: .tone)
    var customInkLines = StoryLineSettings.preset(.balanced, style: .ink)

    static let versionsRange: ClosedRange<Int> = 1...10

    init() {}

    var versions: Int { min(max(versionsPerImage, Self.versionsRange.lowerBound), Self.versionsRange.upperBound) }

    /// Etapas e limites em vigor, conforme a intensidade escolhida.
    var adjustments: StoryAdjustments {
        switch intensity {
        case .light: return .light
        case .moderate: return .moderate
        case .normal: return .normal
        case .aggressive: return .aggressive
        case .custom: return custom.clamped()
        }
    }

    /// Serrilhado, aberração e ofuscação do nível escolhido (sem as linhas).
    static func baseTexture(_ preset: StoryTexturePreset) -> StoryTexture {
        switch preset {
        case .off: return .none
        case .subtle: return .subtle
        case .balanced: return .balanced
        case .intense: return .intense
        case .custom: return .balanced
        }
    }

    /// Medidas das linhas em vigor: o nível do estilo escolhido, ou o Personalizado desse estilo.
    var lineSettings: StoryLineSettings {
        texturePreset == .custom ? customLines : StoryLineSettings.preset(texturePreset, style: lineStyle)
    }

    /// Personalizado das linhas do estilo escolhido (é o que os sliders editam).
    var customLines: StoryLineSettings {
        get { lineStyle == .tone ? customToneLines : customInkLines }
        set {
            if lineStyle == .tone { customToneLines = newValue } else { customInkLines = newValue }
        }
    }

    /// Efeitos de textura em vigor: o nível escolhido mais as linhas (ligadas, estilo e direção escolhidos antes do nível).
    var texture: StoryTexture {
        if texturePreset == .off { return .none }
        var t = texturePreset == .custom ? customTexture : Self.baseTexture(texturePreset)
        t.lines = linesEnabled
        t.lineStyle = lineStyle
        t.lineDirection = lineDirection
        lineSettings.apply(to: &t)
        return t.clamped()
    }

    /// Troca o nível das texturas. Ao entrar no Personalizado, os sliders (das linhas dos dois estilos e dos outros efeitos)
    /// partem do nível que estava valendo (se estava desligado, do Equilibrado) em vez de pular para valores soltos.
    mutating func selectTexturePreset(_ preset: StoryTexturePreset) {
        if preset == .custom, texturePreset != .custom {
            let from: StoryTexturePreset = texturePreset == .off ? .balanced : texturePreset
            customTexture = Self.baseTexture(from)
            customToneLines = StoryLineSettings.preset(from, style: .tone)
            customInkLines = StoryLineSettings.preset(from, style: .ink)
        }
        texturePreset = preset
    }

    /// Liga ou desliga as linhas. Ligar com o nível em Desligado já escolhe o Equilibrado (senão não apareceria nada).
    mutating func setLinesEnabled(_ on: Bool) {
        linesEnabled = on
        if on, texturePreset == .off { texturePreset = .balanced }
    }

    // Leitura tolerante: campos novos em versões futuras não apagam o que já estava salvo.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = StoryOptions()
        fit = (try? c.decodeIfPresent(StoryFit.self, forKey: .fit)) ?? d.fit
        solidColor = (try? c.decodeIfPresent(StorySolidColor.self, forKey: .solidColor)) ?? d.solidColor
        customColor = (try? c.decodeIfPresent(RGBColor.self, forKey: .customColor)) ?? d.customColor
        intensity = (try? c.decodeIfPresent(StoryIntensity.self, forKey: .intensity)) ?? d.intensity
        custom = (try? c.decodeIfPresent(StoryAdjustments.self, forKey: .custom)) ?? d.custom
        mirror = (try? c.decodeIfPresent(Bool.self, forKey: .mirror)) ?? d.mirror
        format = (try? c.decodeIfPresent(StoryOutputFormat.self, forKey: .format)) ?? d.format
        naming = (try? c.decodeIfPresent(StoryNaming.self, forKey: .naming)) ?? d.naming
        prefix = (try? c.decodeIfPresent(String.self, forKey: .prefix)) ?? d.prefix
        versionsPerImage = (try? c.decodeIfPresent(Int.self, forKey: .versionsPerImage)) ?? d.versionsPerImage
        texturePreset = (try? c.decodeIfPresent(StoryTexturePreset.self, forKey: .texturePreset)) ?? d.texturePreset
        customTexture = (try? c.decodeIfPresent(StoryTexture.self, forKey: .customTexture)) ?? d.customTexture
        customToneLines = (try? c.decodeIfPresent(StoryLineSettings.self, forKey: .customToneLines)) ?? d.customToneLines
        customInkLines = (try? c.decodeIfPresent(StoryLineSettings.self, forKey: .customInkLines)) ?? d.customInkLines
        if let on = try? c.decodeIfPresent(Bool.self, forKey: .linesEnabled) {
            linesEnabled = on
            lineStyle = (try? c.decodeIfPresent(StoryLineStyle.self, forKey: .lineStyle)) ?? d.lineStyle
            lineDirection = (try? c.decodeIfPresent(StoryLineDirection.self, forKey: .lineDirection)) ?? d.lineDirection
        } else {
            // salvo antes da beta.26: as linhas moravam dentro do nível
            switch texturePreset {
            case .off:
                break
            case .custom:
                linesEnabled = customTexture.lines
                lineStyle = customTexture.lineStyle
                lineDirection = customTexture.lineDirection
                customLines = StoryLineSettings(texture: customTexture)
            case .intense:
                linesEnabled = true
                lineStyle = .ink
                lineDirection = .cross
            case .subtle, .balanced:
                linesEnabled = true
                lineStyle = .tone
                lineDirection = .random
            }
        }
    }
}

// MARK: - Parâmetros sorteados de uma imagem

enum ChromaticChannel: String, Equatable {
    case red
    case blue
}

struct StoryParams: Equatable {
    /// Recorte por borda (0.01 = 1%). 0 = sem recorte.
    var cropFraction: Double = 0
    /// -1…1: para que lado a janela do recorte escorrega (0 = centro).
    var cropShiftX: Double = 0
    var cropShiftY: Double = 0
    var rotationDegrees: Double = 0
    /// Soma no canal (escala 0–1): -0.02…0.02.
    var brightness: Double = 0
    /// Fator 1 + contraste: -0.02…0.02.
    var contrast: Double = 0
    /// Fator 1 + saturação: -0.03…0.03.
    var saturation: Double = 0
    /// Amplitude do ruído em níveis de 0–255 (0 = sem ruído).
    var noiseAmplitude: Double = 0
    var noiseOffsetX: Double = 0
    var noiseOffsetY: Double = 0
    /// Canal deslocado em 1px (nil = sem deslocamento).
    var chromaticChannel: ChromaticChannel?
    var chromaticDX: Int = 0
    var chromaticDY: Int = 0
    /// Opacidade da granulação (0.01 = 1%; 0 = sem granulação).
    var grainOpacity: Double = 0
    var grainSoftLight = false
    var grainOffsetX: Double = 0
    var grainOffsetY: Double = 0
    /// Unsharp Mask (0 = não aplica).
    var sharpenIntensity: Double = 0
    /// Suavização em px (0 = não aplica).
    var softenRadius: Double = 0
    var mirror = false
    /// 1.0.0-beta.22: micro-perspectiva — deslocamento de cada canto, em fração do lado (−máx…máx).
    /// Ordem: inferior esquerdo, inferior direito, superior direito, superior esquerdo (x, y de cada).
    var perspective: [Double] = []
    var perspectiveMax: Double = 0
    /// 1.0.0-beta.22: temperatura de cor em kelvin (+ mais quente, − mais fria).
    var temperatureKelvin: Double = 0
    /// 1.0.0-beta.22: riscos diagonais — amplitude em níveis 0–255 (0 = desligado), período 3 ou 4,
    /// direção (\ ou /) e fase. Período 3: escurece, clareia, mantém. Período 4: escurece, mantém, clareia, mantém.
    var diagonalAmplitude: Double = 0
    var diagonalPeriod = 3
    var diagonalAnti = false
    var diagonalPhase = 0
    /// 1.0.0-beta.22: vinheta — fração da escala somada nos cantos (− escurece, + clareia).
    var vignette: Double = 0
    /// 1.0.0-beta.23: linhas diagonais (opacidade 0–1 já com o teto aplicado; 0 = desligado). A direção nunca é `random` aqui:
    /// o sorteio já escolheu \, / ou X para esta imagem.
    /// beta.24: opacidade da faixa ESCURA (já pela curva do slider); a de realce claro usa `lineHighlightRatio` dela.
    var lineOpacity: Double = 0
    var lineSpacing = 8
    var lineThickness = 3
    var lineDirection: StoryLineDirection = .backslash
    var lineBlend: StoryLineBlend = .hardLight
    /// Deslocamento aleatório das linhas nesta imagem (0 a espaçamento − 1). No X, a segunda diagonal tem a própria fase.
    var linePhase = 0
    var linePhase2 = 0
    /// 1.0.0-beta.25: no Tom, `lineOpacity` é a variação de brilho no centro da linha (0,35 = ±35%), `lineAngle` em graus,
    /// `lineIrregularity` de 0 a 1 e `lineSeed` sorteia o desenho dos riscos desta imagem. Padrão gravura, como antes.
    var lineStyle: StoryLineStyle = .ink
    var lineAngle = 45.0
    var lineIrregularity = 0.0
    var lineSeed: UInt64 = 0
    /// 1.0.0-beta.23: serrilhado das bordas (nível 0–1; 0 = desligado) e semente do jitter de linhas/colunas.
    var jitterLevel: Double = 0
    var jitterSeed: UInt64 = 0
    /// 1.0.0-beta.23: aberração cromática — R anda (+dx, +dy) e B anda (−dx, −dy). 0 = desligado.
    var aberrationDX = 0
    var aberrationDY = 0
    /// 1.0.0-beta.23: ofuscação (bloom + micro-desfoque direcional), nível 0–1, e ângulo do desfoque em radianos.
    var bloomLevel: Double = 0
    var blurAngle: Double = 0
    var quality = 90
    var progressive = false
    var chroma444 = false
    /// Código aleatório do nome do arquivo (ex.: a8f3k).
    var code = "00000"

    static let codeAlphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")

    /// Sorteia os parâmetros de uma imagem.
    ///
    /// Todos os números são sempre sorteados na mesma ordem e só depois zerados conforme as etapas
    /// desligadas — assim, ligar ou desligar uma etapa não muda o sorteio das outras.
    static func sample(_ options: StoryOptions, seed: UInt64) -> StoryParams {
        let a = options.adjustments
        var rng = SeededRandom(seed: seed)
        func unit() -> Double { Double.random(in: 0..<1, using: &rng) }
        func sym(_ maxValue: Double) -> Double { (unit() * 2 - 1) * maxValue }

        // ordem fixa dos sorteios — não reordenar (mudaria o resultado de sementes já mostradas no preview)
        let cropU = unit(), shiftX = sym(1), shiftY = sym(1), rot = sym(a.rotationMaxDegrees)
        let bri = sym(a.brightnessMaxPercent / 100), con = sym(a.contrastMaxPercent / 100), sat = sym(a.saturationMaxPercent / 100)
        let noiseU = unit(), nX = unit() * 4096, nY = unit() * 4096
        let chanRed = unit() < 0.5, dir = Int(unit() * 4) % 4
        let grainU = unit(), grainSoft = unit() < 0.5, gX = unit() * 4096, gY = unit() * 4096
        let sharpenWins = unit() < 0.5, sharpenU = unit()
        let q = StoryAdjustments.qualityRange.lowerBound + Int(unit() * Double(StoryAdjustments.qualityRange.count)) % StoryAdjustments.qualityRange.count
        let prog = unit() < 0.5, c444 = unit() < 0.5
        var code = ""
        for _ in 0..<5 { code.append(codeAlphabet[Int(unit() * Double(codeAlphabet.count)) % codeAlphabet.count]) }
        // 1.0.0-beta.22: sorteios novos sempre no fim (sementes antigas continuam dando os mesmos valores acima)
        var corners: [Double] = []
        for _ in 0..<8 { corners.append(sym(1)) }
        let temp = sym(a.temperatureMaxKelvin)
        let chromaTwo = unit() < 0.5
        let diagU = unit(), diagFour = unit() < 0.5, diagAnti = unit() < 0.5, diagPhaseU = unit()
        let vig = sym(a.vignetteMaxPercent / 100)
        // 1.0.0-beta.23: texturas — sorteios novos no fim da sequência (a semente de antes continua dando os mesmos valores acima)
        let t = options.texture
        let lineDirU = unit(), linePhaseU = unit()
        let lineLevelU = unit(), jitterLevelU = unit(), aberrationLevelU = unit(), bloomLevelU = unit()
        let aberrationAngleU = unit(), blurAngleU = unit()
        let jitterSeed = rng.next()
        // 1.0.0-beta.25: sorteios do Tom, também no fim
        let lineAngleU = unit()
        let lineSeed = rng.next()
        /// 70% a 100% do nível escolhido.
        func level(_ percent: Double, _ u: Double) -> Double { percent / 100 * (0.7 + 0.3 * u) }

        var p = StoryParams()
        p.code = code
        p.mirror = options.mirror
        p.quality = q

        if a.geometry {
            let lo = min(a.cropMinPercent, a.cropMaxPercent)
            p.cropFraction = (lo + cropU * (a.cropMaxPercent - lo)) / 100
            p.cropShiftX = shiftX
            p.cropShiftY = shiftY
            p.rotationDegrees = rot
        }
        if a.photometric {
            p.brightness = bri
            p.contrast = con
            p.saturation = sat
        }
        if a.noise {
            let lo = min(a.noiseMinAmplitude, a.noiseMaxAmplitude)
            p.noiseAmplitude = lo + noiseU * (a.noiseMaxAmplitude - lo)
            p.noiseOffsetX = nX
            p.noiseOffsetY = nY
        }
        if a.chromaticShift {
            p.chromaticChannel = chanRed ? .red : .blue
            let moves = [(1, 0), (-1, 0), (0, 1), (0, -1)]
            let size = a.chromaticMaxPixels >= 2 && chromaTwo ? 2 : 1
            p.chromaticDX = moves[dir].0 * size
            p.chromaticDY = moves[dir].1 * size
        }
        if a.filmGrain {
            let lo = min(a.grainMinOpacityPercent, a.grainMaxOpacityPercent)
            p.grainOpacity = (lo + grainU * (a.grainMaxOpacityPercent - lo)) / 100
            p.grainSoftLight = grainSoft
            p.grainOffsetX = gX
            p.grainOffsetY = gY
        }
        if a.detail {
            if sharpenWins { p.sharpenIntensity = 0.2 + sharpenU * 0.2 } else { p.softenRadius = 0.2 }
        }
        if a.perspective, a.perspectiveMaxPercent > 0 {
            p.perspectiveMax = a.perspectiveMaxPercent / 100
            p.perspective = corners.map { $0 * p.perspectiveMax }
        }
        if a.temperature { p.temperatureKelvin = temp }
        if a.diagonal {
            let lo = min(a.diagonalMinAmplitude, a.diagonalMaxAmplitude)
            p.diagonalAmplitude = lo + diagU * (a.diagonalMaxAmplitude - lo)
            p.diagonalPeriod = diagFour ? 4 : 3
            p.diagonalAnti = diagAnti
            p.diagonalPhase = Int(diagPhaseU * Double(p.diagonalPeriod)) % p.diagonalPeriod
        }
        if a.vignette { p.vignette = vig }
        if t.lines, t.lineOpacityPercent > 0 {
            // linhas variam pouco entre imagens (90% a 100% do nível): têm que aparecer em todas
            let lineLevel = t.lineOpacityPercent / 100 * (0.9 + 0.1 * lineLevelU)
            p.lineStyle = t.lineStyle
            switch t.lineStyle {
            case .ink:
                p.lineOpacity = StoryTexture.lineAlpha(level: lineLevel)
            case .tone:
                p.lineOpacity = StoryTexture.toneAmplitude(level: lineLevel)
                // ±3° por imagem em volta do ângulo escolhido
                p.lineAngle = min(max(t.lineAngle + (lineAngleU * 2 - 1) * 3, StoryTexture.angleRange.lowerBound), StoryTexture.angleRange.upperBound)
                p.lineIrregularity = min(max(t.lineIrregularity / 100, 0), 1)
                p.lineSeed = lineSeed
            }
            p.lineSpacing = max(4, Int(t.lineSpacing))
            p.lineThickness = max(2, min(Int(t.lineThickness), p.lineSpacing - 2))
            p.lineBlend = t.lineBlend
            switch t.lineDirection {
            case .backslash, .slash, .cross: p.lineDirection = t.lineDirection
            case .random:
                let choices: [StoryLineDirection] = [.backslash, .slash, .cross]
                p.lineDirection = choices[min(2, Int(lineDirU * 3))]
            }
            p.linePhase = min(p.lineSpacing - 1, Int(linePhaseU * Double(p.lineSpacing)))
            p.linePhase2 = Int((jitterSeed >> 11) % UInt64(p.lineSpacing))
        }
        if t.jitter, t.jitterPercent > 0 {
            p.jitterLevel = level(t.jitterPercent, jitterLevelU)
            p.jitterSeed = jitterSeed
        }
        if t.aberration, t.aberrationPercent > 0 {
            let l = level(t.aberrationPercent, aberrationLevelU)
            let px = max(1, Int((1 + Double(StoryTexture.aberrationMaxPixels - 1) * l).rounded()))
            let angle = aberrationAngleU * Double.pi
            var dx = Int((Double(px) * cos(angle)).rounded()), dy = Int((Double(px) * sin(angle)).rounded())
            if dx == 0 && dy == 0 { dx = px }
            p.aberrationDX = dx
            p.aberrationDY = dy
        }
        if t.bloom, t.bloomPercent > 0 {
            p.bloomLevel = level(t.bloomPercent, bloomLevelU)
            p.blurAngle = blurAngleU * Double.pi
        }
        if a.jpegVariation, options.format == .jpg {
            p.progressive = prog
            p.chroma444 = c444
        }
        return p
    }

    /// Há alguma etapa que roda sobre os pixels já desenhados (serrilhado e linhas)?
    var needsRasterPass: Bool { jitterLevel > 0 || lineOpacity > 0 }

    /// Algum efeito de textura (linhas, serrilhado, aberração ou ofuscação) está ligado nesta imagem?
    var hasTexture: Bool {
        needsRasterPass || aberrationDX != 0 || aberrationDY != 0 || bloomLevel > 0
    }

    /// Cópia sem nenhum efeito de textura (para comparar "com" e "sem" no modal de inspeção).
    var withoutTexture: StoryParams {
        var p = self
        p.lineOpacity = 0
        p.jitterLevel = 0
        p.aberrationDX = 0
        p.aberrationDY = 0
        p.bloomLevel = 0
        return p
    }

    /// Ampliação mínima para que uma rotação de `degrees` não deixe cantos vazios num quadro `width`×`height`.
    static func rotationZoom(width: Double, height: Double, degrees: Double) -> Double {
        let t = abs(degrees) * .pi / 180
        guard t > 0, width > 0, height > 0 else { return 1 }
        let c = cos(t), s = sin(t)
        return max((width * c + height * s) / width, (width * s + height * c) / height)
    }

    /// Valor (−1, 0 ou +1) do risco diagonal no pixel (x, y): −1 escurece, +1 clareia, 0 mantém o tom.
    /// Período 3: −1, +1, 0. Período 4: −1, 0, +1, 0. A média é zero, então o tom geral não muda.
    static func diagonalSign(x: Int, y: Int, period: Int, anti: Bool, phase: Int) -> Int {
        let p = period == 4 ? 4 : 3
        let pattern = p == 4 ? [-1, 0, 1, 0] : [-1, 1, 0]
        let k = ((anti ? x - y : x + y) + phase) % p
        return pattern[(k + p) % p]
    }

    /// Resumo curto para o status do arquivo e o Histórico.
    var summary: String {
        var parts: [String] = []
        if cropFraction > 0 { parts.append(String(format: "recorte %.2f%%", cropFraction * 100)) }
        if rotationDegrees != 0 { parts.append(String(format: "rot %+.2f°", rotationDegrees)) }
        if brightness != 0 || contrast != 0 || saturation != 0 {
            parts.append(String(format: "br %+.1f%% ct %+.1f%% sat %+.1f%%", brightness * 100, contrast * 100, saturation * 100))
        }
        if noiseAmplitude > 0 { parts.append(String(format: "ruído ±%.1f", noiseAmplitude)) }
        if let ch = chromaticChannel { parts.append("canal \(ch == .red ? "R" : "B") \(chromaticDX),\(chromaticDY)px") }
        if grainOpacity > 0 { parts.append(String(format: "grão %.1f%% ", grainOpacity * 100) + (grainSoftLight ? "soft-light" : "overlay")) }
        if sharpenIntensity > 0 { parts.append(String(format: "nitidez %.2f", sharpenIntensity)) }
        if softenRadius > 0 { parts.append(String(format: "suaviza %.1fpx", softenRadius)) }
        if perspectiveMax > 0 { parts.append(String(format: "perspectiva ±%.1f%%", perspectiveMax * 100)) }
        if temperatureKelvin != 0 { parts.append(String(format: "temperatura %+.0fK", temperatureKelvin)) }
        if diagonalAmplitude > 0 {
            parts.append("riscos " + (diagonalAnti ? "/" : "\\") + String(format: " ±%.1f (período %d)", diagonalAmplitude, diagonalPeriod))
        }
        if vignette != 0 { parts.append(String(format: "vinheta %+.1f%%", vignette * 100)) }
        if lineOpacity > 0 {
            let dir: String
            switch lineDirection {
            case .backslash: dir = "\\"
            case .slash: dir = "/"
            default: dir = "X"
            }
            switch lineStyle {
            case .ink:
                parts.append("linhas \(dir) \(lineSpacing)px/\(lineThickness)px \(lineBlend.label.lowercased()) " + String(format: "%.0f%%", lineOpacity * 100))
            case .tone:
                parts.append("linhas no tom \(dir) " + String(format: "%.0f° %dpx/%dpx ±%.0f%%", lineAngle, lineSpacing, lineThickness, lineOpacity * 100))
            }
        }
        if jitterLevel > 0 { parts.append(String(format: "serrilhado %.0f%%", jitterLevel * 100)) }
        if aberrationDX != 0 || aberrationDY != 0 { parts.append("aberração RGB \(aberrationDX),\(aberrationDY)px") }
        if bloomLevel > 0 { parts.append(String(format: "ofuscação %.0f%%", bloomLevel * 100)) }
        if mirror { parts.append("espelhado") }
        parts.append("q\(quality)\(progressive ? " progressivo" : "")\(chroma444 ? " 4:4:4" : " 4:2:0")")
        return parts.joined(separator: " · ")
    }
}

// MARK: - Nomes dos arquivos

enum StoryNames {
    /// Prefixo seguro para nome de arquivo (sem acento, espaço ou símbolo). Vazio vira "story".
    static func cleanPrefix(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR")).lowercased()
        var out = ""
        for ch in folded.unicodeScalars {
            let ok = ("a"..."z").contains(ch) || ("0"..."9").contains(ch) || ch == "_" || ch == "-"
            out.unicodeScalars.append(ok ? ch : "_")
        }
        while out.contains("__") { out = out.replacingOccurrences(of: "__", with: "_") }
        out = out.trimmingCharacters(in: CharacterSet(charactersIn: "_-"))
        return out.isEmpty ? "story" : String(out.prefix(40))
    }

    /// story_001_a8f3k.jpg (ou story_001.jpg). O número tem pelo menos 3 dígitos.
    /// Com várias versões por imagem: story_001_v2_a8f3k.jpg.
    static func fileName(index: Int, total: Int, prefix: String, code: String, naming: StoryNaming, ext: String,
                         version: Int? = nil) -> String {
        let width = max(3, String(max(total, 1)).count)
        var number = String(max(index, 0))
        while number.count < width { number = "0" + number }
        let base = "\(cleanPrefix(prefix))_\(number)" + (version.map { "_v\($0)" } ?? "")
        return naming == .sequentialCode ? "\(base)_\(code).\(ext)" : "\(base).\(ext)"
    }
}

// MARK: - Versões

enum StoryVersions {
    /// Semente da versão `v` (1 = a própria semente da imagem, que é a do preview).
    static func seed(_ base: UInt64, version v: Int) -> UInt64 {
        guard v > 1 else { return base }
        var rng = SeededRandom(seed: base ^ (UInt64(v) &* 0xD6E8_FEB8_6659_FD93))
        return rng.next()
    }
}

// MARK: - Cor dominante

enum DominantColor {
    /// Cor mais frequente de uma miniatura RGBA8 (pré-multiplicada ou não): agrupa em caixas de 4 bits
    /// por canal e devolve a média da caixa mais cheia. Ignora pixels quase transparentes.
    static func compute(rgba: [UInt8]) -> RGBColor? {
        var counts = [Int](repeating: 0, count: 4096)
        var sumR = [Int](repeating: 0, count: 4096)
        var sumG = [Int](repeating: 0, count: 4096)
        var sumB = [Int](repeating: 0, count: 4096)
        var i = 0
        while i + 3 < rgba.count {
            let a = Int(rgba[i + 3])
            if a >= 128 {
                // desfaz a pré-multiplicação (sem efeito quando a = 255)
                let r = min(255, Int(rgba[i]) * 255 / a)
                let g = min(255, Int(rgba[i + 1]) * 255 / a)
                let b = min(255, Int(rgba[i + 2]) * 255 / a)
                let bin = (r >> 4) << 8 | (g >> 4) << 4 | (b >> 4)
                counts[bin] += 1
                sumR[bin] += r
                sumG[bin] += g
                sumB[bin] += b
            }
            i += 4
        }
        guard let best = counts.indices.max(by: { counts[$0] < counts[$1] }), counts[best] > 0 else { return nil }
        let n = Double(counts[best])
        return RGBColor(r: Double(sumR[best]) / n / 255, g: Double(sumG[best]) / n / 255, b: Double(sumB[best]) / n / 255)
    }
}
