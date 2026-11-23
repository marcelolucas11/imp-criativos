import XCTest

/// Otimizador em Lote (1.0.0-beta.21): sorteio dos parâmetros, presets, nomes e cor dominante.
final class StoryOptimizerParamsTests: XCTestCase {
    private func options(_ intensity: StoryIntensity, format: StoryOutputFormat = .jpg) -> StoryOptions {
        var o = StoryOptions()
        o.intensity = intensity
        o.format = format
        return o
    }

    func testSameSeedGivesSameParams() {
        let o = options(.moderate)
        XCTAssertEqual(StoryParams.sample(o, seed: 42), StoryParams.sample(o, seed: 42))
    }

    func testDifferentSeedsGiveDifferentParams() {
        let o = options(.moderate)
        var codes = Set<String>()
        for seed: UInt64 in 0..<500 {
            codes.insert(StoryParams.sample(o, seed: seed).code)
        }
        XCTAssertGreaterThan(codes.count, 495, "códigos dos arquivos praticamente nunca repetem")
    }

    /// Todos os valores ficam dentro dos intervalos do pedido, em todas as intensidades.
    func testModerateStaysWithinRequestedRanges() {
        let o = options(.moderate)
        for seed: UInt64 in 0..<2000 {
            let p = StoryParams.sample(o, seed: seed &* 2_654_435_761)
            XCTAssertTrue((0.005...0.015).contains(p.cropFraction), "recorte \(p.cropFraction)")
            XCTAssertLessThanOrEqual(abs(p.rotationDegrees), 0.8)
            XCTAssertLessThanOrEqual(abs(p.brightness), 0.02)
            XCTAssertLessThanOrEqual(abs(p.contrast), 0.02)
            XCTAssertLessThanOrEqual(abs(p.saturation), 0.03)
            XCTAssertTrue((2...4).contains(p.noiseAmplitude), "ruído \(p.noiseAmplitude)")
            XCTAssertTrue((0.01...0.03).contains(p.grainOpacity), "grão \(p.grainOpacity)")
            XCTAssertNotNil(p.chromaticChannel)
            XCTAssertEqual(abs(p.chromaticDX) + abs(p.chromaticDY), 1, "desloca exatamente 1px")
            XCTAssertTrue((88...93).contains(p.quality))
            XCTAssertTrue(p.sharpenIntensity == 0 ? p.softenRadius == 0.2 : (0.2...0.4).contains(p.sharpenIntensity) && p.softenRadius == 0)
            XCTAssertTrue((-1...1).contains(p.cropShiftX) && (-1...1).contains(p.cropShiftY))
            XCTAssertEqual(p.code.count, 5)
            XCTAssertFalse(p.mirror, "espelhar vem desligado de fábrica")
        }
    }

    func testLightIsSubtlerAndSkipsChannelShiftAndGrain() {
        let o = options(.light)
        for seed: UInt64 in 0..<1000 {
            let p = StoryParams.sample(o, seed: seed)
            XCTAssertLessThanOrEqual(p.cropFraction, 0.008 + 1e-12)
            XCTAssertLessThanOrEqual(abs(p.rotationDegrees), 0.3)
            XCTAssertLessThanOrEqual(abs(p.brightness), 0.01)
            XCTAssertLessThanOrEqual(p.noiseAmplitude, 2.5)
            XCTAssertNil(p.chromaticChannel)
            XCTAssertEqual(p.grainOpacity, 0)
        }
    }

    func testAllQualitiesAndBothJPEGModesAppear() {
        let o = options(.moderate)
        var qualities = Set<Int>(), progressive = Set<Bool>(), chroma = Set<Bool>()
        for seed: UInt64 in 0..<500 {
            let p = StoryParams.sample(o, seed: seed)
            qualities.insert(p.quality); progressive.insert(p.progressive); chroma.insert(p.chroma444)
        }
        XCTAssertEqual(qualities, Set(88...93))
        XCTAssertEqual(progressive, [true, false])
        XCTAssertEqual(chroma, [true, false])
    }

    func testPNGNeverVariesJPEGEncoding() {
        let o = options(.moderate, format: .png)
        for seed: UInt64 in 0..<200 {
            let p = StoryParams.sample(o, seed: seed)
            XCTAssertFalse(p.progressive)
            XCTAssertFalse(p.chroma444)
        }
    }

    /// Desligar uma etapa zera só ela; as outras mantêm o mesmo sorteio (o preview não "pula").
    func testTurningOffOneStepKeepsTheOthers() {
        var o = options(.custom)
        let before = StoryParams.sample(o, seed: 7)
        o.custom.noise = false
        o.custom.chromaticShift = false
        let after = StoryParams.sample(o, seed: 7)
        XCTAssertEqual(after.noiseAmplitude, 0)
        XCTAssertNil(after.chromaticChannel)
        XCTAssertEqual(after.cropFraction, before.cropFraction)
        XCTAssertEqual(after.rotationDegrees, before.rotationDegrees)
        XCTAssertEqual(after.brightness, before.brightness)
        XCTAssertEqual(after.grainOpacity, before.grainOpacity)
        XCTAssertEqual(after.quality, before.quality)
        XCTAssertEqual(after.code, before.code)
    }

    func testEverythingOffIsNeutralExceptEncoding() {
        var o = options(.custom)
        o.custom.geometry = false
        o.custom.photometric = false
        o.custom.noise = false
        o.custom.chromaticShift = false
        o.custom.filmGrain = false
        o.custom.detail = false
        o.custom.jpegVariation = false
        let p = StoryParams.sample(o, seed: 99)
        XCTAssertEqual(p.cropFraction, 0)
        XCTAssertEqual(p.rotationDegrees, 0)
        XCTAssertEqual(p.brightness, 0)
        XCTAssertEqual(p.noiseAmplitude, 0)
        XCTAssertEqual(p.grainOpacity, 0)
        XCTAssertEqual(p.sharpenIntensity, 0)
        XCTAssertEqual(p.softenRadius, 0)
        XCTAssertFalse(p.progressive)
        XCTAssertTrue((88...93).contains(p.quality), "a qualidade continua sorteada (re-encoding limpo)")
    }

    func testMirrorOnlyWhenEnabled() {
        var o = options(.light)
        XCTAssertFalse(StoryParams.sample(o, seed: 1).mirror)
        o.mirror = true
        XCTAssertTrue(StoryParams.sample(o, seed: 1).mirror)
    }

    func testCustomValuesAreClampedToRequestedLimits() {
        var o = options(.custom)
        o.custom.cropMaxPercent = 9
        o.custom.rotationMaxDegrees = 5
        o.custom.noiseMaxAmplitude = 50
        o.custom.grainMaxOpacityPercent = .nan
        let a = o.adjustments
        XCTAssertEqual(a.cropMaxPercent, 1.5)
        XCTAssertEqual(a.rotationMaxDegrees, 0.8)
        XCTAssertEqual(a.noiseMaxAmplitude, 4)
        XCTAssertEqual(a.grainMaxOpacityPercent, 1)
    }

    func testRotationZoomCoversCorners() {
        XCTAssertEqual(StoryParams.rotationZoom(width: 1080, height: 1920, degrees: 0), 1)
        let z = StoryParams.rotationZoom(width: 1080, height: 1920, degrees: 0.8)
        XCTAssertGreaterThan(z, 1.02)
        XCTAssertLessThan(z, 1.03)
        XCTAssertEqual(z, StoryParams.rotationZoom(width: 1080, height: 1920, degrees: -0.8), accuracy: 1e-12)
    }

    func testFileNames() {
        XCTAssertEqual(StoryNames.fileName(index: 1, total: 100, prefix: "story", code: "a8f3k", naming: .sequentialCode, ext: "jpg"), "story_001_a8f3k.jpg")
        XCTAssertEqual(StoryNames.fileName(index: 42, total: 7, prefix: "story", code: "x", naming: .sequential, ext: "png"), "story_042.png")
        XCTAssertEqual(StoryNames.fileName(index: 7, total: 1000, prefix: "Promoção Março!", code: "abcde", naming: .sequential, ext: "jpg"), "promocao_marco_0007.jpg")
        XCTAssertEqual(StoryNames.cleanPrefix("   "), "story")
    }

    func testDecodingOldOrPartialSettingsKeepsDefaults() throws {
        let json = #"{"fit":"solid","prefix":"cliente"}"#.data(using: .utf8)!
        let o = try JSONDecoder().decode(StoryOptions.self, from: json)
        XCTAssertEqual(o.fit, .solid)
        XCTAssertEqual(o.prefix, "cliente")
        XCTAssertEqual(o.intensity, .light)
        XCTAssertFalse(o.mirror)
    }

    func testDominantColorPicksMostFrequent() {
        var px: [UInt8] = []
        for _ in 0..<70 { px += [220, 30, 30, 255] }   // vermelho
        for _ in 0..<30 { px += [20, 20, 200, 255] }   // azul
        for _ in 0..<50 { px += [0, 255, 0, 10] }      // verde quase transparente: ignorado
        let c = try? XCTUnwrap(DominantColor.compute(rgba: px))
        XCTAssertEqual(c?.r ?? 0, 220.0 / 255, accuracy: 0.01)
        XCTAssertEqual(c?.b ?? 1, 30.0 / 255, accuracy: 0.01)
        XCTAssertNil(DominantColor.compute(rgba: [0, 0, 0, 0]))
    }
}
