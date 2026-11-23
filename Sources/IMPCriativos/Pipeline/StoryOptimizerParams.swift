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
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: return "Leve (imperceptível)"
        case .moderate: return "Moderado"
        case .custom: return "Personalizado"
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
    var cropMaxPercent = 1.5
    var rotationMaxDegrees = 0.8
    /// Brilho, contraste e saturação.
    var photometric = true
    var brightnessMaxPercent = 2.0
    var contrastMaxPercent = 2.0
    var saturationMaxPercent = 3.0
    /// Micro-ruído nos canais RGB (níveis de 0–255).
    var noise = true
    var noiseMaxAmplitude = 4.0
    /// Deslocamento de 1px no canal vermelho ou azul.
    var chromaticShift = true
    /// Granulação de filme (overlay ou soft-light).
    var filmGrain = true
    var grainMaxOpacityPercent = 3.0
    /// Unsharp Mask leve ou suavização mínima, sorteado.
    var detail = true
    /// Baseline ou progressivo e subamostragem 4:2:0 ou 4:4:4, sorteados (só JPEG).
    var jpegVariation = true

    // Limites do pedido (os sliders do Personalizado andam dentro deles)
    static let cropRange: ClosedRange<Double> = 0.5...1.5
    static let rotationRange: ClosedRange<Double> = 0...0.8
    static let brightnessRange: ClosedRange<Double> = 0...2
    static let contrastRange: ClosedRange<Double> = 0...2
    static let saturationRange: ClosedRange<Double> = 0...3
    static let noiseRange: ClosedRange<Double> = 2...4
    static let grainRange: ClosedRange<Double> = 1...3
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

    /// Moderado: os intervalos completos do pedido, com todas as etapas ligadas.
    static let moderate = StoryAdjustments()

    /// Mantém cada valor dentro do limite do pedido (protege contra configuração salva estragada).
    func clamped() -> StoryAdjustments {
        func c(_ v: Double, _ r: ClosedRange<Double>) -> Double { v.isFinite ? min(max(v, r.lowerBound), r.upperBound) : r.lowerBound }
        var a = self
        a.cropMaxPercent = c(cropMaxPercent, Self.cropRange)
        a.rotationMaxDegrees = c(rotationMaxDegrees, Self.rotationRange)
        a.brightnessMaxPercent = c(brightnessMaxPercent, Self.brightnessRange)
        a.contrastMaxPercent = c(contrastMaxPercent, Self.contrastRange)
        a.saturationMaxPercent = c(saturationMaxPercent, Self.saturationRange)
        a.noiseMaxAmplitude = c(noiseMaxAmplitude, Self.noiseRange)
        a.grainMaxOpacityPercent = c(grainMaxOpacityPercent, Self.grainRange)
        return a
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

    init() {}

    /// Etapas e limites em vigor, conforme a intensidade escolhida.
    var adjustments: StoryAdjustments {
        switch intensity {
        case .light: return .light
        case .moderate: return .moderate
        case .custom: return custom.clamped()
        }
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

        var p = StoryParams()
        p.code = code
        p.mirror = options.mirror
        p.quality = q

        if a.geometry {
            let lo = min(StoryAdjustments.cropRange.lowerBound, a.cropMaxPercent)
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
            let lo = StoryAdjustments.noiseRange.lowerBound
            p.noiseAmplitude = lo + noiseU * (a.noiseMaxAmplitude - lo)
            p.noiseOffsetX = nX
            p.noiseOffsetY = nY
        }
        if a.chromaticShift {
            p.chromaticChannel = chanRed ? .red : .blue
            let moves = [(1, 0), (-1, 0), (0, 1), (0, -1)]
            p.chromaticDX = moves[dir].0
            p.chromaticDY = moves[dir].1
        }
        if a.filmGrain {
            let lo = StoryAdjustments.grainRange.lowerBound
            p.grainOpacity = (lo + grainU * (a.grainMaxOpacityPercent - lo)) / 100
            p.grainSoftLight = grainSoft
            p.grainOffsetX = gX
            p.grainOffsetY = gY
        }
        if a.detail {
            if sharpenWins { p.sharpenIntensity = 0.2 + sharpenU * 0.2 } else { p.softenRadius = 0.2 }
        }
        if a.jpegVariation, options.format == .jpg {
            p.progressive = prog
            p.chroma444 = c444
        }
        return p
    }

    /// Ampliação mínima para que uma rotação de `degrees` não deixe cantos vazios num quadro `width`×`height`.
    static func rotationZoom(width: Double, height: Double, degrees: Double) -> Double {
        let t = abs(degrees) * .pi / 180
        guard t > 0, width > 0, height > 0 else { return 1 }
        let c = cos(t), s = sin(t)
        return max((width * c + height * s) / width, (width * s + height * c) / height)
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
    static func fileName(index: Int, total: Int, prefix: String, code: String, naming: StoryNaming, ext: String) -> String {
        let width = max(3, String(max(total, 1)).count)
        var number = String(max(index, 0))
        while number.count < width { number = "0" + number }
        let base = "\(cleanPrefix(prefix))_\(number)"
        return naming == .sequentialCode ? "\(base)_\(code).\(ext)" : "\(base).\(ext)"
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
