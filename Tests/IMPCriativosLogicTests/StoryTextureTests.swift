import XCTest
import CoreGraphics
import CoreText
import CoreImage
import ImageIO
import UniformTypeIdentifiers

/// Texturas, linhas e bordas (1.0.0-beta.23): sorteio e opções (puros), efeitos nos pixels (CPU) e o motor de verdade
/// (aberração e bloom no Core Image). Também grava amostras em /tmp/imp-story-samples para conferência visual.
final class StoryTextureTests: XCTestCase {
    static let samples = URL(fileURLWithPath: "/tmp/imp-story-samples", isDirectory: true)
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("texture-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: Self.samples, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    // MARK: - Ajudantes

    private func buffer(_ width: Int, _ height: Int, _ value: UInt8 = 128) -> [UInt8] {
        [UInt8](repeating: value, count: width * height * 4)
    }

    private func setPixel(_ px: inout [UInt8], _ x: Int, _ y: Int, width: Int, _ v: UInt8) {
        let o = (y * width + x) * 4
        px[o] = v; px[o + 1] = v; px[o + 2] = v
    }

    private func gray(_ px: [UInt8], _ x: Int, _ y: Int, width: Int) -> Int { Int(px[(y * width + x) * 4 + 1]) }

    /// Opções com as linhas ligadas (Tom, direção aleatória) e o nível de texturas ainda em Desligado.
    private var textureOptions: StoryOptions {
        var o = StoryOptions()
        o.fit = .cover
        o.linesEnabled = true
        return o
    }

    private func linesParams(_ direction: StoryLineDirection, blend: StoryLineBlend = .hardLight) -> StoryParams {
        var p = StoryParams()
        p.lineOpacity = 0.85
        p.lineSpacing = 8
        p.lineThickness = 4
        p.lineDirection = direction
        p.lineBlend = blend
        p.linePhase = 3
        p.linePhase2 = 5
        return p
    }

    // MARK: - Opções e sorteio

    func testTexturesAreOffByDefaultAndDoNotChangeOlderValues() {
        let off = textureOptions
        var on = off
        on.texturePreset = .intense
        XCTAssertEqual(off.texturePreset, .off)
        XCTAssertFalse(off.texture.isActive)
        for seed in [1, 2, 3, 99, 12345, 987_654_321] as [UInt64] {
            let a = StoryParams.sample(off, seed: seed), b = StoryParams.sample(on, seed: seed)
            XCTAssertFalse(a.hasTexture, "desligado de fábrica")
            XCTAssertTrue(b.hasTexture)
            XCTAssertEqual(a.code, b.code, "ligar texturas não muda o sorteio das outras etapas")
            XCTAssertEqual(a.cropFraction, b.cropFraction)
            XCTAssertEqual(a.rotationDegrees, b.rotationDegrees)
            XCTAssertEqual(a.noiseAmplitude, b.noiseAmplitude)
            XCTAssertEqual(a.quality, b.quality)
            XCTAssertEqual(a.diagonalAmplitude, b.diagonalAmplitude)
            XCTAssertEqual(a.vignette, b.vignette)
            XCTAssertEqual(a.grainOpacity, b.grainOpacity)
            XCTAssertEqual(b.withoutTexture.hasTexture, false)
        }
    }

    func testPresetsActivateTheEffectsTheyPromise() {
        for seed in 1...40 {
            var o = textureOptions
            o.texturePreset = .subtle
            let s = StoryParams.sample(o, seed: UInt64(seed))
            XCTAssertGreaterThan(s.lineOpacity, 0)
            XCTAssertEqual(s.lineStyle, .tone, "Sutil usa linhas no tom (mantêm a cor)")
            XCTAssertLessThanOrEqual(s.lineOpacity, StoryTexture.toneAmplitude(level: 0.3) + 1e-9, "linhas leves")
            XCTAssertEqual(s.lineSpacing, 10)
            XCTAssertEqual(s.lineThickness, 2)
            XCTAssertEqual(s.lineAngle, 55, accuracy: 3.0001)
            XCTAssertEqual(s.lineIrregularity, 0.6, accuracy: 1e-9)
            XCTAssertGreaterThan(s.jitterLevel, 0)
            XCTAssertLessThanOrEqual(s.jitterLevel, 0.15 + 1e-9, "serrilhado mínimo")
            XCTAssertTrue(s.aberrationDX != 0 || s.aberrationDY != 0)
            XCTAssertLessThanOrEqual(max(abs(s.aberrationDX), abs(s.aberrationDY)), 2, "micro-aberração")
            XCTAssertEqual(s.bloomLevel, 0)

            o.texturePreset = .balanced
            let b = StoryParams.sample(o, seed: UInt64(seed))
            XCTAssertEqual(b.lineStyle, .tone)
            XCTAssertGreaterThanOrEqual(b.lineOpacity, StoryTexture.toneAmplitude(level: 0.54) - 1e-9, "60%: visível")
            XCTAssertLessThanOrEqual(b.lineOpacity, StoryTexture.toneAmplitude(level: 0.6) + 1e-9)
            XCTAssertEqual(b.lineSpacing, 9)
            XCTAssertEqual(b.lineThickness, 3)
            XCTAssertGreaterThanOrEqual(b.jitterLevel, 0.45 * 0.7 - 1e-9)
            XCTAssertLessThanOrEqual(b.jitterLevel, 0.45 + 1e-9)
            XCTAssertEqual(b.bloomLevel, 0)
            XCTAssertGreaterThanOrEqual(max(abs(b.aberrationDX), abs(b.aberrationDY)), 1)

            o.texturePreset = .intense
            o.lineStyle = .ink
            o.lineDirection = .cross
            let i = StoryParams.sample(o, seed: UInt64(seed))
            XCTAssertEqual(i.lineDirection, .cross)
            XCTAssertEqual(i.lineStyle, .ink)
            XCTAssertEqual(i.lineThickness, 4)
            XCTAssertEqual(i.lineSpacing, 8)
            XCTAssertGreaterThanOrEqual(i.bloomLevel, 0.7 * 0.7 - 1e-9)
            XCTAssertLessThanOrEqual(i.bloomLevel, 0.7 + 1e-9)
            XCTAssertGreaterThanOrEqual(i.jitterLevel, 0.8 * 0.7 - 1e-9)
            XCTAssertLessThanOrEqual(i.lineOpacity, StoryTexture.lineAlpha(level: 0.85) + 1e-9)
            XCTAssertGreaterThan(i.lineOpacity, b.lineOpacity, "Intenso marca mais que Equilibrado")
            XCTAssertLessThan(StoryTexture.lineOpacityCap, 1, "a leitura do texto não some, mesmo com o slider em 100%")
        }
    }

    func testRandomLineDirectionCoversAllThreeAndFixedOnesStayFixed() {
        var o = textureOptions
        o.texturePreset = .subtle
        var seen = Set<StoryLineDirection>()
        for seed in 1...80 { seen.insert(StoryParams.sample(o, seed: UInt64(seed)).lineDirection) }
        XCTAssertEqual(seen, [.backslash, .slash, .cross], "a direção aleatória sorteia \\, / e X")
        XCTAssertFalse(seen.contains(.random), "o sorteio nunca deixa 'aleatória' chegar ao motor")

        o.texturePreset = .custom
        o.customTexture = .balanced
        for direction in [StoryLineDirection.backslash, .slash, .cross] {
            o.lineDirection = direction
            for seed in 1...20 { XCTAssertEqual(StoryParams.sample(o, seed: UInt64(seed)).lineDirection, direction) }
        }
    }

    func testAberrationStaysBetweenOneAndSixPixels() {
        var o = textureOptions
        o.texturePreset = .custom
        o.customTexture = StoryTexture()
        o.customTexture.aberration = true
        o.customTexture.aberrationPercent = 100
        var biggest = 0
        for seed in 1...200 {
            let p = StoryParams.sample(o, seed: UInt64(seed))
            let m = max(abs(p.aberrationDX), abs(p.aberrationDY))
            XCTAssertGreaterThanOrEqual(m, 1, "sempre desloca pelo menos 1px")
            XCTAssertLessThanOrEqual(m, StoryTexture.aberrationMaxPixels)
            biggest = max(biggest, m)
        }
        XCTAssertGreaterThanOrEqual(biggest, 5, "no nível máximo chega perto dos 6px")
        o.customTexture.aberrationPercent = 1
        for seed in 1...50 {
            let p = StoryParams.sample(o, seed: UInt64(seed))
            XCTAssertLessThanOrEqual(max(abs(p.aberrationDX), abs(p.aberrationDY)), 1, "no nível mínimo só 1px")
        }
    }

    func testEachEffectTurnsOffByItself() {
        var o = textureOptions
        o.texturePreset = .custom
        o.customTexture = .intense
        o.linesEnabled = false
        var p = StoryParams.sample(o, seed: 5)
        XCTAssertEqual(p.lineOpacity, 0)
        XCTAssertGreaterThan(p.jitterLevel, 0)
        o.customTexture.jitter = false
        p = StoryParams.sample(o, seed: 5)
        XCTAssertEqual(p.jitterLevel, 0)
        XCTAssertTrue(p.aberrationDX != 0 || p.aberrationDY != 0)
        o.customTexture.aberration = false
        o.customTexture.bloom = false
        p = StoryParams.sample(o, seed: 5)
        XCTAssertFalse(p.hasTexture)
        XCTAssertFalse(o.texture.isActive)
        o.customTexture = .intense
        o.linesEnabled = true
        o.customToneLines.opacityPercent = 0
        XCTAssertEqual(StoryParams.sample(o, seed: 5).lineOpacity, 0, "slider em 0% = efeito desligado")
    }

    func testCustomTextureIsClampedAndThicknessStaysBelowSpacing() {
        var t = StoryTexture()
        t.lineSpacing = 2
        t.lineThickness = 1
        t.lineOpacityPercent = 250
        t.jitterPercent = -10
        t.aberrationPercent = .nan
        let c = t.clamped()
        XCTAssertEqual(c.lineSpacing, 4, "espaçamento mínimo de 4px na saída 1080×1920")
        XCTAssertEqual(c.lineThickness, 2, "espessura mínima de 2px")
        XCTAssertEqual(c.lineOpacityPercent, 100)
        XCTAssertEqual(c.jitterPercent, 0)
        XCTAssertEqual(c.aberrationPercent, 0)
        t.lineSpacing = 18
        t.lineThickness = 8
        XCTAssertEqual(t.clamped().lineThickness, 8, "espessura máxima de 8px")
        t.lineSpacing = 99
        XCTAssertEqual(t.clamped().lineSpacing, 18, "espaçamento máximo de 18px")
        t.lineSpacing = 8
        XCTAssertEqual(t.clamped().lineThickness, 6, "sempre sobram 2px: espessura ≤ espaçamento − 2")
        XCTAssertEqual(StoryTexture().lineSpacing, 10)
        XCTAssertEqual(StoryTexture().lineThickness, 2)
        XCTAssertEqual(StoryTexture().lineStyle, .tone, "linha nova começa no tom")
        t.lineAngle = 5
        t.lineIrregularity = 300
        XCTAssertEqual(t.clamped().lineAngle, 30, "ângulo de 30° a 75°")
        XCTAssertEqual(t.clamped().lineIrregularity, 100)
        t.lineAngle = 120
        XCTAssertEqual(t.clamped().lineAngle, 75)
        var o = textureOptions
        o.texturePreset = .custom
        o.customToneLines = StoryLineSettings(texture: t)
        let p = StoryParams.sample(o, seed: 3)
        XCTAssertLessThanOrEqual(p.lineThickness, p.lineSpacing - 2)
        XCTAssertGreaterThanOrEqual(p.lineThickness, 2)
    }

    func testChoosingCustomStartsFromThePresetInUse() {
        var o = StoryOptions()
        o.texturePreset = .intense
        o.selectTexturePreset(.custom)
        XCTAssertEqual(o.texturePreset, .custom)
        XCTAssertEqual(o.customTexture, .intense, "os sliders partem do preset que estava valendo")
        o.customTexture.jitterPercent = 10
        o.selectTexturePreset(.subtle)
        o.selectTexturePreset(.custom)
        XCTAssertEqual(o.customTexture, .subtle)

        var fresh = StoryOptions()
        fresh.selectTexturePreset(.custom)
        XCTAssertEqual(fresh.customTexture, .balanced, "vindo do Desligado, parte do Equilibrado")
        XCTAssertEqual(fresh.customToneLines, StoryLineSettings.preset(.balanced, style: .tone))
        XCTAssertEqual(fresh.customInkLines, StoryLineSettings.preset(.balanced, style: .ink))
        fresh.customTexture.bloomPercent = 55
        fresh.selectTexturePreset(.custom)
        XCTAssertEqual(fresh.customTexture.bloomPercent, 55, "escolher Personalizado de novo não apaga o que já estava")
    }

    // MARK: - Linhas escolhidas antes do nível (beta.26)

    func testLinesAreChosenBeforeTheLevelAndEachStyleHasItsOwnLevels() {
        XCTAssertFalse(StoryOptions().linesEnabled, "linhas desligadas de fábrica")
        var o = textureOptions
        for level in [StoryTexturePreset.subtle, .balanced, .intense] {
            o.texturePreset = level
            for style in StoryLineStyle.allCases {
                o.lineStyle = style
                o.lineDirection = .slash
                let t = o.texture
                let expected = StoryLineSettings.preset(level, style: style)
                XCTAssertTrue(t.lines)
                XCTAssertEqual(t.lineStyle, style, "\(level) \(style)")
                XCTAssertEqual(t.lineDirection, .slash, "a direção escolhida vale em qualquer nível")
                XCTAssertEqual(t.lineOpacityPercent, expected.opacityPercent, "\(level) \(style)")
                XCTAssertEqual(t.lineSpacing, expected.spacing)
                XCTAssertEqual(t.lineThickness, expected.thickness)
                XCTAssertEqual(t.jitterPercent, StoryOptions.baseTexture(level).jitterPercent, "serrilhado segue o nível")
                let p = StoryParams.sample(o, seed: 11)
                XCTAssertEqual(p.lineStyle, style)
                XCTAssertEqual(p.lineDirection, .slash)
            }
        }
        // cada estilo tem níveis próprios e crescentes
        for style in StoryLineStyle.allCases {
            let s = StoryLineSettings.preset(.subtle, style: style), b = StoryLineSettings.preset(.balanced, style: style), i = StoryLineSettings.preset(.intense, style: style)
            XCTAssertLessThan(s.opacityPercent, b.opacityPercent)
            XCTAssertLessThan(b.opacityPercent, i.opacityPercent)
        }
        XCTAssertNotEqual(StoryLineSettings.preset(.balanced, style: .tone), StoryLineSettings.preset(.balanced, style: .ink))

        // linhas desligadas: o nível continua valendo para os outros efeitos
        o.linesEnabled = false
        o.texturePreset = .intense
        XCTAssertFalse(o.texture.lines)
        XCTAssertEqual(StoryParams.sample(o, seed: 3).lineOpacity, 0)
        XCTAssertGreaterThan(StoryParams.sample(o, seed: 3).jitterLevel, 0)

        // ligar as linhas com o nível desligado já escolhe o Equilibrado
        var fresh = StoryOptions()
        fresh.setLinesEnabled(true)
        XCTAssertEqual(fresh.texturePreset, .balanced)
        fresh.texturePreset = .subtle
        fresh.setLinesEnabled(false)
        fresh.setLinesEnabled(true)
        XCTAssertEqual(fresh.texturePreset, .subtle, "com um nível escolhido, ligar as linhas não troca o nível")
    }

    func testCustomLinesAreKeptSeparatelyForEachStyle() {
        var o = textureOptions
        o.texturePreset = .subtle
        o.selectTexturePreset(.custom)
        XCTAssertEqual(o.customToneLines, StoryLineSettings.preset(.subtle, style: .tone), "o Personalizado parte do nível em uso, nos dois estilos")
        XCTAssertEqual(o.customInkLines, StoryLineSettings.preset(.subtle, style: .ink))
        o.lineStyle = .tone
        o.customLines.opacityPercent = 77
        o.customLines.angle = 65
        o.lineStyle = .ink
        XCTAssertEqual(o.customLines, StoryLineSettings.preset(.subtle, style: .ink), "mexer no Tom não muda a Gravura")
        o.customLines.blend = .overlay
        XCTAssertEqual(o.texture.lineBlend, .overlay)
        o.lineStyle = .tone
        XCTAssertEqual(o.texture.lineOpacityPercent, 77)
        XCTAssertEqual(o.texture.lineAngle, 65)
        XCTAssertEqual(o.customInkLines.blend, .overlay)
    }

    func testOptionsSavedBeforeBeta26MoveTheirLinesOut() throws {
        let custom = #"{"texturePreset":"custom","customTexture":{"lines":true,"lineStyle":"tone","lineDirection":"slash","lineOpacityPercent":42,"lineSpacing":11,"lineThickness":3,"lineAngle":62,"lineIrregularity":20}}"#.data(using: .utf8)!
        let c = try JSONDecoder().decode(StoryOptions.self, from: custom)
        XCTAssertTrue(c.linesEnabled)
        XCTAssertEqual(c.lineStyle, .tone)
        XCTAssertEqual(c.lineDirection, .slash)
        XCTAssertEqual(c.customToneLines.opacityPercent, 42)
        XCTAssertEqual(c.customToneLines.angle, 62)
        XCTAssertEqual(c.texture.lineSpacing, 11)
        let intense = #"{"texturePreset":"intense"}"#.data(using: .utf8)!
        let i = try JSONDecoder().decode(StoryOptions.self, from: intense)
        XCTAssertTrue(i.linesEnabled)
        XCTAssertEqual(i.lineStyle, .ink, "o Intenso era gravura em X")
        XCTAssertEqual(i.lineDirection, .cross)
        let customOff = #"{"texturePreset":"custom","customTexture":{"lines":false}}"#.data(using: .utf8)!
        XCTAssertFalse(try JSONDecoder().decode(StoryOptions.self, from: customOff).linesEnabled)
        var n = StoryOptions()
        n.linesEnabled = true
        n.lineStyle = .ink
        n.lineDirection = .backslash
        n.customInkLines.blend = .overlay
        XCTAssertEqual(try JSONDecoder().decode(StoryOptions.self, from: JSONEncoder().encode(n)), n)
    }

    func testOldSavedOptionsStillDecodeWithTexturesOff() throws {
        let old = #"{"fit":"cover","intensity":"normal","format":"png","versionsPerImage":3}"#.data(using: .utf8)!
        let o = try JSONDecoder().decode(StoryOptions.self, from: old)
        XCTAssertEqual(o.texturePreset, .off)
        XCTAssertEqual(o.intensity, .normal)
        XCTAssertEqual(o.versions, 3)
        XCTAssertEqual(o.customTexture, .balanced)

        var n = StoryOptions()
        n.texturePreset = .custom
        n.customTexture = .intense
        n.customTexture.lineDirection = .slash
        n.customTexture.lineBlend = .overlay
        let back = try JSONDecoder().decode(StoryOptions.self, from: JSONEncoder().encode(n))
        XCTAssertEqual(back, n)

        let partial = #"{"texturePreset":"balanced","customTexture":{"lines":true,"lineSpacing":9}}"#.data(using: .utf8)!
        let p = try JSONDecoder().decode(StoryOptions.self, from: partial)
        XCTAssertEqual(p.texturePreset, .balanced)
        XCTAssertEqual(p.customTexture.lineSpacing, 9)
        XCTAssertEqual(p.customTexture.lineStyle, .ink, "opções salvas antes da beta.25 continuam em gravura")
        XCTAssertTrue(p.linesEnabled, "salvo antes da beta.26 com um nível ligado: as linhas continuam ligadas")
        XCTAssertEqual(p.lineStyle, .tone)
        XCTAssertFalse(o.linesEnabled, "salvo com texturas desligadas: linhas desligadas")
        n.customTexture.lineStyle = .tone
        n.customTexture.lineAngle = 62
        n.customTexture.lineIrregularity = 35
        XCTAssertEqual(try JSONDecoder().decode(StoryOptions.self, from: JSONEncoder().encode(n)), n)
        let oldBlend = #"{"customTexture":{"lines":true,"lineBlend":"softLight"}}"#.data(using: .utf8)!
        let q = try JSONDecoder().decode(StoryOptions.self, from: oldBlend)
        XCTAssertEqual(q.customTexture.lineBlend, .hardLight, "modo removido (Soft-light) volta para Hard-light")
        XCTAssertTrue(q.customTexture.lines)
        XCTAssertEqual(p.customTexture.jitterPercent, StoryTexture().jitterPercent, "campo ausente fica no padrão")
    }

    func testSummaryMentionsTheActiveTextures() {
        var o = textureOptions
        o.texturePreset = .intense
        let s = StoryParams.sample(o, seed: 8).summary
        XCTAssertTrue(s.contains("linhas"), s)
        XCTAssertTrue(s.contains("serrilhado"), s)
        XCTAssertTrue(s.contains("aberração"), s)
        XCTAssertTrue(s.contains("ofuscação"), s)
        XCTAssertFalse(StoryParams.sample(textureOptions, seed: 8).summary.contains("serrilhado"))
    }

    // MARK: - Linhas (CPU)

    func testLinesMatchTheirGeometryInEveryDirection() {
        let W = 96, H = 80
        for direction in [StoryLineDirection.backslash, .slash, .cross] {
            var px = buffer(W, H, 200)
            let p = linesParams(direction)
            StoryTextureEffects.applyLines(&px, width: W, height: H, params: p)
            let cross = direction == .cross
            let luts = StoryTextureEffects.lineLUTs(blend: p.lineBlend, opacity: p.lineOpacity, cross: cross)
            let h = StoryTexture.lineHighlightWidth(spacing: 8, thickness: 4)
            XCTAssertEqual(h, 1, "realce fino: um terço da faixa escura")
            var dark = 0, light = 0
            for y in 0..<H {
                for x in 0..<W {
                    var expected = 200
                    if direction != .slash {
                        switch StoryTextureEffects.bandState(x: x, y: y, spacing: 8, thickness: 4, highlight: h, slash: false, phase: 3) {
                        case StoryTextureEffects.bandDark: expected = Int(luts.dark[expected])
                        case StoryTextureEffects.bandLight: expected = Int(luts.light[expected])
                        default: break
                        }
                    }
                    if direction != .backslash {
                        switch StoryTextureEffects.bandState(x: x, y: y, spacing: 8, thickness: 4, highlight: h, slash: true, phase: cross ? 5 : 3) {
                        case StoryTextureEffects.bandDark: expected = Int(luts.dark[expected])
                        case StoryTextureEffects.bandLight: expected = Int(luts.light[expected])
                        default: break
                        }
                    }
                    let got = gray(px, x, y, width: W)
                    XCTAssertEqual(got, expected, "(\(x),\(y)) \(direction)")
                    if got < 200 { dark += 1 } else if got > 200 { light += 1 }
                }
            }
            if !cross {
                XCTAssertEqual(Double(dark) / Double(W * H), 0.5, accuracy: 0.01, "faixa escura = 4 de cada 8 px")
                XCTAssertEqual(Double(light) / Double(W * H), 0.125, accuracy: 0.01, "realce = 1 de cada 8 px")
            }
            XCTAssertGreaterThan(light, 0, "tem faixa de realce claro")
            XCTAssertGreaterThan(dark, 0)
        }
    }

    func testBackslashAndSlashHaveExactlyTheSameStrength() {
        let W = 96, H = 80
        var back = buffer(W, H, 150), fwd = buffer(W, H, 150)
        StoryTextureEffects.applyLines(&back, width: W, height: H, params: linesParams(.backslash))
        StoryTextureEffects.applyLines(&fwd, width: W, height: H, params: linesParams(.slash))
        func histogram(_ px: [UInt8]) -> [Int: Int] {
            var h: [Int: Int] = [:]
            for i in 0..<(W * H) { h[Int(px[i * 4 + 1]), default: 0] += 1 }
            return h
        }
        XCTAssertEqual(histogram(back), histogram(fwd), "mesma quantidade de pixels em cada tom: \\ e / pesam igual")
        // espelhar na horizontal troca uma pela outra (a fase muda, a força não)
        var mirrored = [UInt8](repeating: 0, count: back.count)
        for y in 0..<H { for x in 0..<W {
            let a = (y * W + x) * 4, b = (y * W + (W - 1 - x)) * 4
            for c in 0..<4 { mirrored[b + c] = back[a + c] }
        } }
        XCTAssertEqual(histogram(mirrored), histogram(fwd))
    }

    func testLinesAreClearlyVisibleOnDarkMidAndLightColours() {
        let luts = StoryTextureEffects.lineLUTs(blend: .hardLight, opacity: StoryTexture.lineAlpha(level: 0.5))
        for v in 0..<256 {
            let delta = max(abs(Int(luts.dark[v]) - v), abs(Int(luts.light[v]) - v))
            XCTAssertGreaterThanOrEqual(delta, 30, "em \(v) pelo menos uma das faixas se destaca (a escura nas luzes, o realce nas sombras)")
        }
        // preto puro: só o realce aparece; branco puro: só a faixa escura aparece
        XCTAssertEqual(Int(luts.dark[0]), 0)
        XCTAssertGreaterThan(Int(luts.light[0]), 60)
        XCTAssertEqual(Int(luts.light[255]), 255)
        XCTAssertLessThan(Int(luts.dark[255]), 150)
    }

    func testCrossKeepsTheOverallBrightnessCloseToASingleDirection() {
        let W = 96, H = 80
        func mean(_ px: [UInt8]) -> Double {
            var sum = 0
            for i in 0..<(W * H) { sum += Int(px[i * 4 + 1]) }
            return Double(sum) / Double(W * H)
        }
        var params = linesParams(.backslash)
        params.lineOpacity = StoryTexture.lineAlpha(level: 0.5)
        var single = buffer(W, H, 128), cross = buffer(W, H, 128)
        StoryTextureEffects.applyLines(&single, width: W, height: H, params: params)
        params.lineDirection = .cross
        StoryTextureEffects.applyLines(&cross, width: W, height: H, params: params)
        let ms = mean(single), mc = mean(cross)
        print("brilho médio de 128: uma direção \(ms) · X \(mc)")
        XCTAssertGreaterThan(ms, 85); XCTAssertLessThan(ms, 128)
        XCTAssertGreaterThan(mc, 85); XCTAssertLessThan(mc, 128)
        XCTAssertLessThan(abs(mc - ms), 12, "o X não escurece nem estoura mais que uma direção")
        XCTAssertNotEqual(single, cross)
    }

    func testLineCurveMatchesTheRequestedFeel() {
        XCTAssertEqual(StoryTexture.lineAlpha(level: 0), 0)
        XCTAssertEqual(StoryTexture.lineAlpha(level: 1), StoryTexture.lineOpacityCap, accuracy: 1e-9)
        var last = -1.0
        for i in 0...100 {
            let a = StoryTexture.lineAlpha(level: Double(i) / 100)
            XCTAssertGreaterThanOrEqual(a, last, "a curva só sobe")
            XCTAssertLessThanOrEqual(a, StoryTexture.lineOpacityCap + 1e-9)
            last = a
        }
        XCTAssertGreaterThan(StoryTexture.lineAlpha(level: 0.10), 0.12, "10% já é visível")
        XCTAssertLessThan(StoryTexture.lineAlpha(level: 0.25), 0.40, "25% ainda é sutil")
        XCTAssertEqual(StoryTexture.lineAlpha(level: 0.5), 0.52, accuracy: 0.05, "50%: bem marcado")
        XCTAssertGreaterThan(StoryTexture.lineAlpha(level: 0.8), 0.68, "80% a 100%: forte")
        XCTAssertLessThan(StoryTexture.lineAlpha(level: 1), 0.9, "mas o texto continua legível")
    }

    func testLinePhaseChangesFromImageToImage() {
        var o = textureOptions
        o.texturePreset = .balanced
        var phases = Set<Int>()
        for seed in 1...60 { phases.insert(StoryParams.sample(o, seed: UInt64(seed)).linePhase) }
        XCTAssertGreaterThanOrEqual(phases.count, 5, "a fase muda de imagem para imagem: \(phases.sorted())")
        XCTAssertTrue(phases.allSatisfy { (0..<9).contains($0) })
        o.texturePreset = .intense
        var phases2 = Set<Int>()
        for seed in 1...60 {
            let p = StoryParams.sample(o, seed: UInt64(seed))
            XCTAssertLessThan(p.linePhase2, p.lineSpacing)
            phases2.insert(p.linePhase2)
        }
        XCTAssertGreaterThanOrEqual(phases2.count, 5, "no X a segunda diagonal também muda")
    }

    // MARK: - Linhas no tom (beta.25)

    private func toneParams(_ direction: StoryLineDirection, amplitude: Double = 0.3, angle: Double = 55, irregularity: Double = 0) -> StoryParams {
        var p = StoryParams()
        p.lineStyle = .tone
        p.lineOpacity = amplitude
        p.lineSpacing = 10
        p.lineThickness = 3
        p.lineDirection = direction
        p.lineAngle = angle
        p.lineIrregularity = irregularity
        p.linePhase = 2
        p.linePhase2 = 7
        p.lineSeed = 42
        return p
    }

    private func coloured(_ W: Int, _ H: Int, _ r: UInt8, _ g: UInt8, _ b: UInt8) -> [UInt8] {
        var px = [UInt8](repeating: 255, count: W * H * 4)
        for i in 0..<(W * H) { px[i * 4] = r; px[i * 4 + 1] = g; px[i * 4 + 2] = b }
        return px
    }

    private func hsv(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> (h: Double, s: Double, v: Double) {
        let R = Double(r) / 255, G = Double(g) / 255, B = Double(b) / 255
        let mx = max(R, G, B), mn = min(R, G, B), d = mx - mn
        var h = 0.0
        if d > 0 {
            if mx == R { h = ((G - B) / d).truncatingRemainder(dividingBy: 6) } else if mx == G { h = (B - R) / d + 2 } else { h = (R - G) / d + 4 }
            h *= 60
            if h < 0 { h += 360 }
        }
        return (h, mx > 0 ? d / mx : 0, mx)
    }

    func testToneLinesKeepTheColourAndOnlyChangeBrightness() {
        let W = 120, H = 90
        for (r, g, b) in [(30, 110, 100), (200, 140, 40), (90, 20, 150), (40, 40, 40)] as [(UInt8, UInt8, UInt8)] {
            for direction in [StoryLineDirection.backslash, .slash, .cross] {
                var px = coloured(W, H, r, g, b)
                StoryTextureEffects.applyLines(&px, width: W, height: H, params: toneParams(direction, amplitude: 0.35, irregularity: 0.6))
                let orig = hsv(r, g, b)
                var darker = 0, lighter = 0, minV = 1.0
                for i in 0..<(W * H) {
                    let o = i * 4
                    let c = hsv(px[o], px[o + 1], px[o + 2])
                    if c.v < orig.v - 0.01 { darker += 1 }
                    if c.v > orig.v + 0.01 { lighter += 1 }
                    minV = min(minV, c.v)
                    // a cor não muda: mesmo matiz e mesma saturação (tirando o arredondamento em 8 bits)
                    if orig.s > 0.2 && c.v > 0.08 {
                        let dh = abs(c.h - orig.h)
                        XCTAssertLessThan(min(dh, 360 - dh), 4, "matiz em (\(r),\(g),\(b)) \(direction)")
                        XCTAssertEqual(c.s, orig.s, accuracy: 0.05, "saturação em (\(r),\(g),\(b)) \(direction)")
                    }
                }
                XCTAssertGreaterThan(darker, W * H / 20, "tem linha escura (\(r),\(g),\(b)) \(direction)")
                XCTAssertGreaterThan(lighter, 0, "tem brilho claro colado (\(r),\(g),\(b)) \(direction)")
                // uma direção: no máximo −35%; no X, onde as duas linhas se cruzam, (1 − 0,35·0,65)² ≈ −40%
                XCTAssertGreaterThan(minV, orig.v * (direction == .cross ? 1 - 0.42 : 1 - 0.36), "nunca vira preto")
            }
        }
    }

    func testToneLinesLeaveVeryBrightAreasAlmostUntouched() {
        let W = 120, H = 90
        var white = coloured(W, H, 255, 255, 255)
        StoryTextureEffects.applyLines(&white, width: W, height: H, params: toneParams(.cross, amplitude: 0.35))
        XCTAssertTrue(white.enumerated().allSatisfy { $0.offset % 4 == 3 || $0.element >= 253 }, "texto branco fica limpo")
        var mid = coloured(W, H, 120, 120, 120)
        StoryTextureEffects.applyLines(&mid, width: W, height: H, params: toneParams(.cross, amplitude: 0.35))
        XCTAssertLessThan(mid.enumerated().filter { $0.offset % 4 == 1 }.map { Int($0.element) }.min()!, 100, "no meio-tom a linha aparece")
    }

    func testToneLinesFollowTheChosenAngleAndDirection() {
        let W = 160, H = 160
        func pattern(_ direction: StoryLineDirection, _ angle: Double) -> [Int] {
            var px = coloured(W, H, 140, 140, 140)
            StoryTextureEffects.applyLines(&px, width: W, height: H, params: toneParams(direction, amplitude: 0.35, angle: angle))
            return (0..<(W * H)).map { Int(px[$0 * 4 + 1]) }
        }
        // diferença média entre um pixel e o que está `dist` px adiante numa direção: ao longo da linha ≈ 0, atravessando ≠ 0
        func meanDiff(_ v: [Int], dx: Double, dy: Double) -> Double {
            var sum = 0, n = 0
            for y in 20..<(H - 20) { for x in 20..<(W - 20) {
                let x2 = x + Int(dx.rounded()), y2 = y + Int(dy.rounded())
                sum += abs(v[y * W + x] - v[y2 * W + x2]); n += 1
            } }
            return Double(sum) / Double(n)
        }
        for angle in [45.0, 55.0, 70.0] {
            let t = angle * Double.pi / 180, d = 12.0
            let back = pattern(.backslash, angle), fwd = pattern(.slash, angle)
            let alongBack = meanDiff(back, dx: d * cos(t), dy: d * sin(t))
            let acrossBack = meanDiff(back, dx: d * cos(t), dy: -d * sin(t))
            XCTAssertLessThan(alongBack * 2.5, acrossBack, "\\ a \(angle)°: desce para a direita")
            let alongFwd = meanDiff(fwd, dx: d * cos(t), dy: -d * sin(t))
            let acrossFwd = meanDiff(fwd, dx: d * cos(t), dy: d * sin(t))
            XCTAssertLessThan(alongFwd * 2.5, acrossFwd, "/ a \(angle)°: sobe para a direita")
            let mb = Double(back.reduce(0, +)) / Double(back.count), mf = Double(fwd.reduce(0, +)) / Double(fwd.count)
            XCTAssertEqual(mb, mf, accuracy: 3, "\\ e / com a mesma força a \(angle)°")
        }
    }

    func testToneIrregularityBreaksTheLinesAndSeedChangesTheDrawing() {
        let W = 200, H = 200
        func render(_ irregularity: Double, seed: UInt64 = 42) -> [UInt8] {
            var px = coloured(W, H, 120, 120, 120)
            var p = toneParams(.backslash, amplitude: 0.35, irregularity: irregularity)
            p.lineSeed = seed
            StoryTextureEffects.applyLines(&px, width: W, height: H, params: p)
            return px
        }
        func darkCount(_ px: [UInt8]) -> Int { (0..<(W * H)).filter { px[$0 * 4 + 1] < 100 }.count }
        let regular = render(0), irregular = render(1)
        XCTAssertLessThan(Double(darkCount(irregular)), Double(darkCount(regular)) * 0.85, "com irregularidade há falhas e trechos fracos")
        XCTAssertGreaterThan(darkCount(irregular), darkCount(regular) / 5, "mas as linhas continuam lá")
        XCTAssertEqual(render(1), render(1), "mesma semente, mesmo desenho")
        XCTAssertNotEqual(render(1, seed: 1), render(1, seed: 2), "outra imagem, outro desenho")
        XCTAssertEqual(render(0, seed: 1), render(0, seed: 2), "sem irregularidade a semente não importa")
    }

    func testToneCrossStaysBalanced() {
        let W = 120, H = 120
        func mean(_ d: StoryLineDirection) -> Double {
            var px = coloured(W, H, 128, 128, 128)
            StoryTextureEffects.applyLines(&px, width: W, height: H, params: toneParams(d, amplitude: 0.35))
            return Double((0..<(W * H)).map { Int(px[$0 * 4 + 1]) }.reduce(0, +)) / Double(W * H)
        }
        let single = mean(.backslash), cross = mean(.cross)
        print("tom: brilho médio de 128 → uma direção \(single) · X \(cross)")
        XCTAssertLessThan(single, 128)
        XCTAssertGreaterThan(single, 100)
        XCTAssertLessThan(abs(cross - single), 8, "o X não escurece muito mais que uma direção")
    }

    func testToneSamplingKeepsTheOlderDrawsAndVariesTheAngle() {
        var o = textureOptions
        o.texturePreset = .custom
        o.customTexture = .balanced
        var inkOnly = o
        inkOnly.lineStyle = .ink
        // mesmo espaçamento nos dois estilos (a fase é sorteada dentro do espaçamento)
        inkOnly.customInkLines.spacing = o.customToneLines.spacing
        o.lineStyle = .tone
        var angles = Set<Int>()
        for seed in 1...40 as ClosedRange<UInt64> {
            let tone = StoryParams.sample(o, seed: seed), ink = StoryParams.sample(inkOnly, seed: seed)
            XCTAssertEqual(tone.code, ink.code, "o estilo das linhas não muda o resto do sorteio")
            XCTAssertEqual(tone.lineDirection, ink.lineDirection)
            XCTAssertEqual(tone.linePhase, ink.linePhase)
            XCTAssertEqual(tone.jitterSeed, ink.jitterSeed)
            XCTAssertEqual(ink.lineAngle, 45, "gravura fica em 45°")
            XCTAssertGreaterThanOrEqual(tone.lineAngle, 52 - 1e-9)
            XCTAssertLessThanOrEqual(tone.lineAngle, 58 + 1e-9)
            XCTAssertNotEqual(tone.lineSeed, 0)
            angles.insert(Int(tone.lineAngle * 10))
            XCTAssertTrue(tone.summary.contains("linhas no tom"), tone.summary)
        }
        XCTAssertGreaterThan(angles.count, 10, "o ângulo varia um pouco por imagem")
        XCTAssertEqual(StoryTexture.toneAmplitude(level: 0), 0)
        XCTAssertEqual(StoryTexture.toneAmplitude(level: 1), StoryTexture.toneAmplitudeCap, accuracy: 1e-9)
        XCTAssertEqual(StoryTexture.toneAmplitude(level: 0.5), 0.20, accuracy: 0.01)
    }

    func testBackslashRunsTopLeftToBottomRightAndSlashTheOtherWay() {
        let W = 96, H = 80
        var back = buffer(W, H, 200), fwd = buffer(W, H, 200)
        StoryTextureEffects.applyLines(&back, width: W, height: H, params: linesParams(.backslash))
        StoryTextureEffects.applyLines(&fwd, width: W, height: H, params: linesParams(.slash))
        for y in 1..<(H - 1) {
            for x in 1..<(W - 1) {
                // \ : o vizinho para baixo e para a direita é igual; / : o vizinho para cima e para a direita é igual
                XCTAssertEqual(gray(back, x, y, width: W), gray(back, x + 1 < W ? x + 1 : x, min(y + 1, H - 1), width: W), "\\ em (\(x),\(y))")
                XCTAssertEqual(gray(fwd, x, y, width: W), gray(fwd, min(x + 1, W - 1), y - 1, width: W), "/ em (\(x),\(y))")
            }
        }
        XCTAssertNotEqual(back, fwd)
    }

    func testLineBlendModesAndOpacity() {
        let off = StoryTextureEffects.lineLUTs(blend: .hardLight, opacity: 0)
        XCTAssertEqual(off.dark, (0..<256).map { UInt8($0) }, "opacidade 0 não muda nada")
        XCTAssertEqual(off.light, (0..<256).map { UInt8($0) })
        let full = StoryTextureEffects.lineLUTs(blend: .hardLight, opacity: 1)
        XCTAssertEqual(Int(full.dark[200]), 0, "hard-light: faixa escura = tinta preta")
        XCTAssertEqual(Double(full.light[100]), 193, accuracy: 1, "realce = 60% da opacidade, tinta branca")
        let half = StoryTextureEffects.lineLUTs(blend: .hardLight, opacity: 0.5)
        XCTAssertEqual(Double(half.dark[200]), 100, accuracy: 1)
        let overlay = StoryTextureEffects.lineLUTs(blend: .overlay, opacity: 1)
        XCTAssertEqual(Double(overlay.dark[200]), 145, accuracy: 1, "overlay, luzes: 2·b − 1")
        XCTAssertEqual(Int(overlay.dark[100]), 0, "overlay, sombras: 2·b·0")
        XCTAssertEqual(Double(overlay.light[100]), 160, accuracy: 1, "overlay, sombras do realce: 2·b")
        XCTAssertEqual(Double(overlay.light[200]), 233, accuracy: 1, "overlay, luzes do realce: 1")
        let cross = StoryTextureEffects.lineLUTs(blend: .hardLight, opacity: 1, cross: true)
        XCTAssertEqual(Double(cross.dark[200]), 200 * (1 - StoryTexture.lineCrossBalance), accuracy: 1, "no X cada camada usa só parte da opacidade")
        for blend in StoryLineBlend.allCases {
            let l = StoryTextureEffects.lineLUTs(blend: blend, opacity: 0.6)
            for v in 1..<256 {
                XCTAssertGreaterThanOrEqual(l.dark[v], l.dark[v - 1], "\(blend) escura é crescente")
                XCTAssertGreaterThanOrEqual(l.light[v], l.light[v - 1], "\(blend) realce é crescente")
            }
            for v in 0..<256 {
                XCTAssertLessThanOrEqual(Int(l.dark[v]), v, "\(blend): a faixa escura só escurece")
                XCTAssertGreaterThanOrEqual(Int(l.light[v]), v, "\(blend): o realce só clareia")
            }
        }
    }

    func testLinesOnlyChangeLinePixelsAndLeaveTheRestIntact() {
        let W = 64, H = 64
        var px = buffer(W, H, 90)
        for i in 0..<(W * H) { px[i * 4 + 3] = 7 }
        var p = linesParams(.cross, blend: .overlay)
        p.lineOpacity = 0
        let same = px
        StoryTextureEffects.applyLines(&px, width: W, height: H, params: p)
        XCTAssertEqual(px, same, "opacidade 0 = nada muda")
        p.lineOpacity = 0.5
        StoryTextureEffects.applyLines(&px, width: W, height: H, params: p)
        for i in 0..<(W * H) { XCTAssertEqual(px[i * 4 + 3], 7, "o byte X do RGBX nunca é tocado") }
    }

    // MARK: - Serrilhado (CPU)

    /// Ruído determinístico de ±amp em volta de `base`.
    private func noisy(_ W: Int, _ H: Int, base: Int, amp: Int) -> [UInt8] {
        var px = buffer(W, H)
        var state: UInt64 = 88_172_645_463_325_252
        for i in 0..<(W * H) {
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            let v = base + Int(state % UInt64(2 * amp + 1)) - amp
            px[i * 4] = UInt8(v); px[i * 4 + 1] = UInt8(v); px[i * 4 + 2] = UInt8(v)
        }
        return px
    }

    func testEdgeJitterLeavesFlatAndNoisyAreasAlone() {
        let W = 200, H = 120
        var flat = buffer(W, H, 120)
        let flatBefore = flat
        StoryTextureEffects.applyEdgeJitter(&flat, width: W, height: H, level: 1, seed: 11)
        XCTAssertEqual(flat, flatBefore, "área lisa não muda")

        var grain = noisy(W, H, base: 120, amp: 6)
        let grainBefore = grain
        StoryTextureEffects.applyEdgeJitter(&grain, width: W, height: H, level: 1, seed: 11)
        XCTAssertEqual(grain, grainBefore, "granulação e ruído não são bordas")

        var soft = buffer(W, H)
        for y in 0..<H { for x in 0..<W { setPixel(&soft, x, y, width: W, UInt8(40 + x)) } }
        let softBefore = soft
        StoryTextureEffects.applyEdgeJitter(&soft, width: W, height: H, level: 1, seed: 11)
        XCTAssertEqual(soft, softBefore, "degradê suave não é borda")
    }

    func testEdgeJitterOnlyTouchesTheNeighbourhoodOfStrongEdgesAndBreaksThem() {
        let W = 200, H = 120
        var px = buffer(W, H)
        for y in 0..<H { for x in 0..<W { setPixel(&px, x, y, width: W, x < 100 ? 20 : 235) } }
        let before = px
        StoryTextureEffects.applyEdgeJitter(&px, width: W, height: H, level: 1, seed: 7)
        var changedColumns = Set<Int>()
        for y in 0..<H {
            for x in 0..<W where gray(px, x, y, width: W) != gray(before, x, y, width: W) { changedColumns.insert(x) }
        }
        XCTAssertFalse(changedColumns.isEmpty, "a borda foi serrilhada")
        XCTAssertGreaterThanOrEqual(changedColumns.min() ?? 0, 95, "longe da borda nada muda")
        XCTAssertLessThanOrEqual(changedColumns.max() ?? 0, 104)
        // a posição da transição varia de uma linha para outra (borda rasgada, não reta)
        var positions = Set<Int>()
        for y in 0..<H { if let x = (0..<W).first(where: { gray(px, $0, y, width: W) > 127 }) { positions.insert(x) } }
        XCTAssertGreaterThanOrEqual(positions.count, 3, "a borda deixou de ser reta: \(positions.sorted())")
        // fora da zona da borda, as duas cores continuam exatamente as mesmas
        XCTAssertEqual(gray(px, 10, 50, width: W), 20)
        XCTAssertEqual(gray(px, 190, 50, width: W), 235)
    }

    func testEdgeJitterAlsoBreaksHorizontalEdges() {
        let W = 200, H = 120
        var px = buffer(W, H)
        for y in 0..<H { for x in 0..<W { setPixel(&px, x, y, width: W, y < 60 ? 15 : 240) } }
        StoryTextureEffects.applyEdgeJitter(&px, width: W, height: H, level: 1, seed: 21)
        var positions = Set<Int>()
        for x in 0..<W { if let y = (0..<H).first(where: { gray(px, x, $0, width: W) > 127 }) { positions.insert(y) } }
        XCTAssertGreaterThanOrEqual(positions.count, 3, "borda horizontal rasgada: \(positions.sorted())")
    }

    func testEdgeJitterLevelControlsStrengthAndIsDeterministic() {
        let W = 200, H = 120
        var base = buffer(W, H)
        for y in 0..<H { for x in 0..<W { setPixel(&base, x, y, width: W, (x / 20 + y / 20) % 2 == 0 ? 30 : 225) } }
        func changed(_ level: Double, _ seed: UInt64) -> (px: [UInt8], count: Int) {
            var p = base
            StoryTextureEffects.applyEdgeJitter(&p, width: W, height: H, level: level, seed: seed)
            var n = 0
            for i in 0..<(W * H) where p[i * 4 + 1] != base[i * 4 + 1] { n += 1 }
            return (p, n)
        }
        XCTAssertEqual(changed(0, 1).count, 0, "nível 0 não faz nada")
        let low = changed(0.15, 4), mid = changed(0.5, 4), high = changed(1, 4)
        XCTAssertGreaterThan(high.count, low.count, "nível alto mexe mais que o baixo (\(low.count) → \(mid.count) → \(high.count))")
        XCTAssertEqual(changed(0.5, 4).px, mid.px, "mesma semente, mesmo resultado")
        XCTAssertNotEqual(changed(0.5, 5).px, mid.px, "outra semente, outro serrilhado")
    }

    func testEdgeMaskFindsTextLikeBarsOnly() {
        let W = 200, H = 120
        var px = buffer(W, H, 60)
        for y in 40..<60 { for x in 30..<170 { setPixel(&px, x, y, width: W, 250) } }
        let mask = StoryTextureEffects.edgeMask(px, width: W, height: H)
        XCTAssertEqual(mask[10 * W + 10], 0, "fundo liso fora da barra")
        XCTAssertEqual(mask[50 * W + 100], 0, "miolo liso da barra")
        XCTAssertGreaterThan(Int(mask[40 * W + 100]), StoryTextureEffects.edgeHigh, "a borda da barra é forte")
        XCTAssertGreaterThan(Int(mask[38 * W + 100]), StoryTextureEffects.edgeLow, "e a vizinhança dela também entra")
    }

    // MARK: - Motor (Core Image + CPU)

    private func makeImage(_ width: Int, _ height: Int, _ draw: (CGContext) -> Void) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: StoryOptimizer.srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        draw(ctx)
        return ctx.makeImage()!
    }

    private func halfBlackHalfWhite() -> CGImage {
        makeImage(1080, 1920) { ctx in
            ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 1080, height: 1920))
            ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)); ctx.fill(CGRect(x: 540, y: 0, width: 540, height: 1920))
        }
    }

    private func compose(_ img: CGImage, _ params: StoryParams) -> CIImage {
        let o = textureOptions
        return StoryOptimizer.compose(img, options: o, params: params, background: StoryOptimizer.backgroundColor(for: img, options: o))
    }

    func testAberrationMovesRedAndBlueInOppositeDirections() throws {
        var p = StoryParams()
        p.aberrationDX = 3
        p.aberrationDY = 0
        let px = try StoryOptimizer.rasterize(compose(halfBlackHalfWhite(), p)).pixels
        func edge(_ channel: Int) -> Int? { (0..<1079).first { x in px[(960 * 1080 + x) * 4 + channel] > 127 } }
        let r = try XCTUnwrap(edge(0)), g = try XCTUnwrap(edge(1)), b = try XCTUnwrap(edge(2))
        print("aberração 3px: R \(r) G \(g) B \(b)")
        XCTAssertEqual(r - g, 3, "vermelho anda 3px para um lado")
        XCTAssertEqual(g - b, 3, "azul anda 3px para o lado oposto")
        XCTAssertEqual(abs(g - 540), 0, "verde fica onde estava")
    }

    func testBloomGlowsAroundBrightAreasAndKeepsTheFarBackgroundDark() throws {
        var p = StoryParams()
        p.bloomLevel = 1
        p.blurAngle = 0
        let px = try StoryOptimizer.rasterize(compose(halfBlackHalfWhite(), p)).pixels
        let near = gray(px, 536, 960, width: 1080), far = gray(px, 100, 960, width: 1080), inside = gray(px, 900, 960, width: 1080)
        print("ofuscação 100%: perto \(near) longe \(far) dentro \(inside)")
        XCTAssertGreaterThan(near, 8, "o brilho vaza para o lado escuro, perto da borda")
        XCTAssertLessThan(far, 3, "longe da borda o fundo continua escuro")
        XCTAssertGreaterThan(inside, 235, "o miolo da área clara continua claro")
        var low = StoryParams()
        low.bloomLevel = 0.1
        let soft = try StoryOptimizer.rasterize(compose(halfBlackHalfWhite(), low)).pixels
        XCTAssertLessThan(gray(soft, 536, 960, width: 1080), near, "nível baixo borra menos que o alto")
    }

    func testRasterPassRunsAfterDrawingAndNeutralParamsSkipIt() throws {
        let flatImage = makeImage(1080, 1920) { ctx in
            ctx.setFillColor(CGColor(srgbRed: 0.6, green: 0.6, blue: 0.6, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 1080, height: 1920))
        }
        let neutral = try StoryOptimizer.rasterize(compose(flatImage, StoryParams()))
        XCTAssertEqual(try StoryOptimizer.applyTexture(neutral, params: StoryParams()).pixels, neutral.pixels, "sem textura, nada muda")

        let p = linesParams(.backslash)
        let lined = try StoryOptimizer.applyTexture(neutral, params: p)
        XCTAssertEqual(lined.image.width, 1080)
        XCTAssertEqual(lined.image.height, 1920)
        var checked = 0
        for (x, y) in [(10, 10), (11, 10), (12, 10), (13, 10), (14, 10), (15, 10), (500, 900), (501, 900), (502, 900), (503, 900)] {
            let on = StoryTextureEffects.bandState(x: x, y: y, spacing: 8, thickness: 4, highlight: 1, slash: false, phase: 3) != StoryTextureEffects.bandNone
            let changed = gray(lined.pixels, x, y, width: 1080) != gray(neutral.pixels, x, y, width: 1080)
            XCTAssertEqual(changed, on, "(\(x),\(y))")
            checked += 1
        }
        XCTAssertEqual(checked, 10)
    }

    // MARK: - Arquivo final e amostras

    /// Criativo de mentira com "texto" (barras brancas e um botão), para ver o serrilhado nas bordas de alto contraste.
    private func creative() -> CGImage {
        makeImage(1600, 1200) { ctx in
            let colors = [CGColor(srgbRed: 0.45, green: 0.05, blue: 0.6, alpha: 1), CGColor(srgbRed: 0.05, green: 0.1, blue: 0.35, alpha: 1)] as CFArray
            let gradient = CGGradient(colorsSpace: StoryOptimizer.srgb, colors: colors, locations: [0, 1])!
            ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 1600, y: 1200), options: [])
            ctx.setFillColor(CGColor(srgbRed: 1, green: 0.8, blue: 0.1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: 540, y: 340, width: 520, height: 520))
            ctx.setFillColor(CGColor(srgbRed: 0.9, green: 0.15, blue: 0.2, alpha: 1))
            ctx.fill(CGRect(x: 80, y: 80, width: 300, height: 120))
            ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            for i in 0..<4 { ctx.fill(CGRect(x: 120, y: 1040 - i * 70, width: 1360 - i * 180, height: 36)) }
        }
    }

    private func decode(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    private func write(_ image: CGImage, _ name: String, type: UTType = .png, quality: Double? = nil) -> URL {
        let url = tmp.appendingPathComponent(name)
        let dst = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dst, image, quality.map { [kCGImageDestinationLossyCompressionQuality: $0] as CFDictionary })
        XCTAssertTrue(CGImageDestinationFinalize(dst))
        return url
    }

    private func printBase64(_ name: String, _ url: URL) throws {
        let b64 = try Data(contentsOf: url).base64EncodedString()
        var i = b64.startIndex
        while i < b64.endIndex {
            let j = b64.index(i, offsetBy: 2000, limitedBy: b64.endIndex) ?? b64.endIndex
            print("SAMPLEB64 \(name) \(b64[i..<j])")
            i = j
        }
    }

    /// Cada preset, no arquivo final: JPEG válido de 1080×1920, sem metadados, e com tempo razoável.
    func testPresetsWriteValidFilesAndSamples() throws {
        let sourceImage = creative()
        let source = write(sourceImage, "criativo.png")
        var tiles: [CGImage] = []
        var zooms: [CGImage] = []
        var timings: [Double] = []
        for preset in [StoryTexturePreset.off, .subtle, .balanced, .intense] {
            var o = StoryOptions()
            o.fit = .blurFit
            o.intensity = .light
            o.texturePreset = preset
            let params = StoryParams.sample(o, seed: 2026)
            XCTAssertEqual(params.hasTexture, preset != .off)
            let out = Self.samples.appendingPathComponent("texturas-\(preset.rawValue).jpg")
            let t0 = Date()
            let bytes = try StoryOptimizer.process(source: source, options: o, params: params, to: out)
            timings.append(Date().timeIntervalSince(t0))
            print("textura \(preset.rawValue): \(bytes) bytes · \(params.summary)")
            XCTAssertGreaterThan(bytes, 20_000)
            let image = try XCTUnwrap(decode(out))
            XCTAssertEqual(image.width, 1080)
            XCTAssertEqual(image.height, 1920)
            tiles.append(image)
            if let crop = image.cropping(to: CGRect(x: 70, y: 600, width: 180, height: 110)) { zooms.append(crop) }
        }
        let sheet = makeImage(1080, 480) { ctx in
            ctx.interpolationQuality = .high
            for (n, img) in tiles.enumerated() { ctx.draw(img, in: CGRect(x: n * 270, y: 0, width: 270, height: 480)) }
        }
        let zoomSheet = makeImage(1080, 660) { ctx in
            ctx.interpolationQuality = .none
            for (n, img) in zooms.enumerated() {
                let col = n % 2, row = 1 - n / 2
                ctx.draw(img, in: CGRect(x: col * 540, y: row * 330, width: 540, height: 330))
            }
        }
        for (name, img) in [("texturas-folha", sheet), ("texturas-zoom-3x", zoomSheet)] {
            let url = write(img, "\(name).jpg", type: .jpeg, quality: name == "texturas-zoom-3x" ? 0.95 : 0.85)
            try? FileManager.default.copyItem(at: url, to: Self.samples.appendingPathComponent("\(name).jpg"))
            try printBase64(name, url)
        }
        // Os testes rodam em Debug (-Onone, com checagem de limites em cada acesso ao array), onde as passadas de pixel custam
        // dezenas de vezes mais do que no app. O tempo de verdade é medido no passo "Velocidade das texturas (Release)" do CI,
        // que falha se o serrilhado ou as linhas passarem do limite. Aqui sobra só uma rede larga contra travamento.
        let off = try XCTUnwrap(timings.first)
        let textured = Array(timings.dropFirst())
        let avg = textured.reduce(0, +) / Double(textured.count)
        print("Otimizador: sem textura \(String(format: "%.3f", off)) s · com textura \(String(format: "%.3f", avg)) s por imagem (1080×1920, build de teste)")
        print("Otimizador: tempos por preset \(timings.map { String(format: "%.2f", $0) })")
        XCTAssertLessThan(avg, 60, "as texturas não podem travar o lote")
    }

    /// Amostras só das linhas: 5 níveis do slider × 3 direções, em 1:1, e uma folha ampliada para conferir pixel a pixel.
    func testLineLevelsAndDirectionsSamples() throws {
        // criativo 1080×1920 com título e subtítulo de verdade (texto branco sobre fundo escuro, e um bloco claro) para ver a legibilidade
        let artwork = makeImage(1080, 1920) { ctx in
            let colors = [CGColor(srgbRed: 0.45, green: 0.05, blue: 0.6, alpha: 1), CGColor(srgbRed: 0.05, green: 0.1, blue: 0.35, alpha: 1)] as CFArray
            let gradient = CGGradient(colorsSpace: StoryOptimizer.srgb, colors: colors, locations: [0, 1])!
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 1920), end: CGPoint(x: 1080, y: 0), options: [])
            func text(_ string: String, size: CGFloat, baselineFromTop: CGFloat, x: CGFloat, color: CGColor) {
                let font = CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
                let attrs: [NSAttributedString.Key: Any] = [.font: font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): color]
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attrs))
                ctx.textPosition = CGPoint(x: x, y: 1920 - baselineFromTop)
                CTLineDraw(line, ctx)
            }
            let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
            text("SORTEIO", size: 130, baselineFromTop: 270, x: 50, color: white)
            text("R$ 50.000 NO PIX", size: 64, baselineFromTop: 360, x: 50, color: CGColor(srgbRed: 1, green: 0.85, blue: 0.2, alpha: 1))
            ctx.setFillColor(white)
            ctx.fill(CGRect(x: 50, y: 1920 - 760, width: 980, height: 250))
            text("GARANTA SEU NÚMERO", size: 70, baselineFromTop: 660, x: 80, color: CGColor(srgbRed: 0.1, green: 0.05, blue: 0.3, alpha: 1))
        }
        let base = try StoryOptimizer.rasterize(compose(artwork, StoryParams()))
        let levels: [Double] = [0.10, 0.25, 0.50, 0.80, 1.0]
        let directions: [StoryLineDirection] = [.backslash, .slash, .cross]
        let tile = CGSize(width: 270, height: 200)
        let crop = CGRect(x: 45, y: 170, width: tile.width, height: tile.height) // título branco, subtítulo amarelo e fundo escuro
        func lined(_ direction: StoryLineDirection, _ level: Double) throws -> CGImage {
            var p = StoryParams()
            p.lineOpacity = StoryTexture.lineAlpha(level: level)
            p.lineSpacing = 8
            p.lineThickness = 3
            p.lineDirection = direction
            p.lineBlend = .hardLight
            p.linePhase = 2
            p.linePhase2 = 6
            XCTAssertTrue(p.needsRasterPass)
            return try XCTUnwrap(StoryOptimizer.applyTexture(base, params: p).image.cropping(to: crop))
        }
        var tiles: [[CGImage]] = []
        for d in directions { tiles.append(try levels.map { try lined(d, $0) }) }
        let sheet = makeImage(Int(tile.width) * levels.count, Int(tile.height) * directions.count) { ctx in
            ctx.interpolationQuality = .none
            for (r, row) in tiles.enumerated() {
                for (c, img) in row.enumerated() {
                    ctx.draw(img, in: CGRect(x: CGFloat(c) * tile.width, y: CGFloat(directions.count - 1 - r) * tile.height, width: tile.width, height: tile.height))
                }
            }
        }
        let zoomPicks: [(StoryLineDirection, Double)] = [(.backslash, 0.5), (.slash, 0.5), (.cross, 0.5), (.cross, 1.0)]
        let zoomCrop = CGRect(x: 15, y: 10, width: 90, height: 60)
        let zoomImages = try zoomPicks.map { try XCTUnwrap(lined($0.0, $0.1).cropping(to: zoomCrop)) }
        let zoom = makeImage(1080, 720) { ctx in
            ctx.interpolationQuality = .none
            for (n, img) in zoomImages.enumerated() {
                let col = n % 2, row = 1 - n / 2
                ctx.draw(img, in: CGRect(x: col * 540, y: row * 360, width: 540, height: 360))
            }
        }
        // o bloco claro com texto escuro: aqui a faixa escura é que aparece, e o texto não pode se perder
        let lightCrop = CGRect(x: 60, y: 570, width: 270, height: 130)
        func linedLight(_ direction: StoryLineDirection, _ level: Double) throws -> CGImage {
            var p = StoryParams()
            p.lineOpacity = StoryTexture.lineAlpha(level: level)
            p.lineSpacing = 8; p.lineThickness = 3; p.lineDirection = direction; p.lineBlend = .hardLight
            p.linePhase = 2; p.linePhase2 = 6
            return try XCTUnwrap(StoryOptimizer.applyTexture(base, params: p).image.cropping(to: lightCrop))
        }
        let lightRow = try levels.map { try linedLight(.cross, $0) }
        let lightSheet = makeImage(Int(lightCrop.width) * levels.count, Int(lightCrop.height)) { ctx in
            ctx.interpolationQuality = .none
            for (c, img) in lightRow.enumerated() { ctx.draw(img, in: CGRect(x: CGFloat(c) * lightCrop.width, y: 0, width: lightCrop.width, height: lightCrop.height)) }
        }
        for (name, img) in [("linhas-niveis", sheet), ("linhas-zoom-6x", zoom), ("linhas-bloco-claro", lightSheet)] {
            let url = write(img, "\(name).jpg", type: .jpeg, quality: 0.95)
            try? FileManager.default.copyItem(at: url, to: Self.samples.appendingPathComponent("\(name).jpg"))
            try printBase64(name, url)
        }
        // o nível 100% é bem mais forte que o 10%, e o X não passa dos extremos
        let low = try lined(.backslash, 0.10), high = try lined(.backslash, 1.0)
        func contrast(_ img: CGImage) -> Double {
            var data = [UInt8](repeating: 0, count: img.width * img.height * 4)
            data.withUnsafeMutableBytes { raw in
                if let ctx = CGContext(data: raw.baseAddress, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: img.width * 4,
                                       space: StoryOptimizer.srgb, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) {
                    ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
                }
            }
            var sum = 0.0
            for y in 0..<img.height { for x in 1..<img.width {
                sum += abs(Double(data[(y * img.width + x) * 4 + 1]) - Double(data[(y * img.width + x - 1) * 4 + 1]))
            } }
            return sum / Double(img.width * img.height)
        }
        print("contraste local: 10% \(contrast(low)) · 100% \(contrast(high))")
        XCTAssertGreaterThan(contrast(high), contrast(low) * 2, "100% é bem mais marcado que 10%")
    }

    /// Amostras das linhas no tom num criativo parecido com o print de referência (fundo verde-petróleo escuro, manchas
    /// laranja e brilho verde embaixo) e com título branco: 3 direções × 25/50/100%, um zoom 4× e Gravura × Tom lado a lado.
    func testToneLineSamples() throws {
        let artwork = makeImage(1080, 1920) { ctx in
            let colors = [CGColor(srgbRed: 0.04, green: 0.16, blue: 0.15, alpha: 1), CGColor(srgbRed: 0.05, green: 0.24, blue: 0.2, alpha: 1)] as CFArray
            let gradient = CGGradient(colorsSpace: StoryOptimizer.srgb, colors: colors, locations: [0, 1])!
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 1920), end: CGPoint(x: 1080, y: 0), options: [])
            ctx.setFillColor(CGColor(srgbRed: 0.95, green: 0.62, blue: 0.18, alpha: 1))
            for (x, y, r) in [(120, 1560, 70), (210, 1500, 55), (300, 1450, 40), (620, 1480, 35), (180, 1380, 45)] as [(CGFloat, CGFloat, CGFloat)] {
                ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
            }
            ctx.setFillColor(CGColor(srgbRed: 0.2, green: 0.75, blue: 0.25, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: 100, y: 1180, width: 700, height: 160))
            let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 120, nil)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)]
            ctx.textPosition = CGPoint(x: 60, y: 1920 - 820)
            CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: "SORTEIO", attributes: attrs)), ctx)
        }
        let base = try StoryOptimizer.rasterize(compose(artwork, StoryParams()))
        let crop = CGRect(x: 20, y: 280, width: 360, height: 560) // manchas laranja, brilho verde, fundo escuro e o começo do título
        func lined(_ direction: StoryLineDirection, _ level: Double, style: StoryLineStyle = .tone) throws -> CGImage {
            var p = StoryParams()
            p.lineStyle = style
            p.lineOpacity = style == .tone ? StoryTexture.toneAmplitude(level: level) : StoryTexture.lineAlpha(level: level)
            p.lineSpacing = style == .tone ? 10 : 8
            p.lineThickness = style == .tone ? 2 : 3
            p.lineDirection = direction
            p.lineAngle = style == .tone ? 55 : 45
            p.lineIrregularity = style == .tone ? 0.6 : 0
            p.lineSeed = 99
            p.linePhase = 3
            p.linePhase2 = 6
            return try XCTUnwrap(StoryOptimizer.applyTexture(base, params: p).image.cropping(to: crop))
        }
        let levels: [Double] = [0.25, 0.5, 1.0]
        let directions: [StoryLineDirection] = [.backslash, .slash, .cross]
        var cells: [CGImage] = []
        for d in directions { for l in levels { cells.append(try lined(d, l)) } }
        let w = Int(crop.width), h = Int(crop.height)
        let sheet = makeImage(w * levels.count, h * directions.count) { ctx in
            ctx.interpolationQuality = .none
            for (i, img) in cells.enumerated() {
                let c = i % levels.count, r = i / levels.count
                ctx.draw(img, in: CGRect(x: c * w, y: (directions.count - 1 - r) * h, width: w, height: h))
            }
        }
        let zoomCrop = CGRect(x: 0, y: 0, width: 270, height: 180)
        let zoomSrc = try XCTUnwrap(lined(.backslash, 0.5).cropping(to: zoomCrop))
        let zoom = makeImage(1080, 720) { ctx in
            ctx.interpolationQuality = .none
            ctx.draw(zoomSrc, in: CGRect(x: 0, y: 0, width: 1080, height: 720))
        }
        let original = try XCTUnwrap(lined(.backslash, 0).cropping(to: CGRect(x: 0, y: 0, width: w, height: h)))
        let ink = try lined(.backslash, 0.5, style: .ink), tone = try lined(.backslash, 0.5)
        let compare = makeImage(w * 3, h) { ctx in
            ctx.interpolationQuality = .none
            for (i, img) in [original, ink, tone].enumerated() { ctx.draw(img, in: CGRect(x: i * w, y: 0, width: w, height: h)) }
        }
        for (name, img) in [("tom-niveis", sheet), ("tom-zoom-4x", zoom), ("original-gravura-tom", compare)] {
            let url = write(img, "\(name).jpg", type: .jpeg, quality: 0.95)
            try? FileManager.default.copyItem(at: url, to: Self.samples.appendingPathComponent("\(name).jpg"))
            try printBase64(name, url)
        }
    }

    func testTextureFileIsReproducibleFromTheSameSeed() throws {
        let source = write(creative(), "repro.png")
        var o = StoryOptions()
        o.fit = .cover
        o.format = .png
        o.texturePreset = .balanced
        let params = StoryParams.sample(o, seed: 31)
        let a = tmp.appendingPathComponent("a.png"), b = tmp.appendingPathComponent("b.png")
        try StoryOptimizer.process(source: source, options: o, params: params, to: a)
        try StoryOptimizer.process(source: source, options: o, params: params, to: b)
        XCTAssertEqual(try Data(contentsOf: a), try Data(contentsOf: b), "o preview e o arquivo final saem iguais com a mesma semente")
        let other = StoryParams.sample(o, seed: 32)
        let c = tmp.appendingPathComponent("c.png")
        try StoryOptimizer.process(source: source, options: o, params: other, to: c)
        XCTAssertNotEqual(try Data(contentsOf: a), try Data(contentsOf: c))
    }
}
