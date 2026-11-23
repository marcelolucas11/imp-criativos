import XCTest
import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers

/// Otimizador em Lote (1.0.0-beta.21): roda o motor de verdade (Core Image + libjpeg-turbo) em imagens
/// fabricadas e confere o resultado pixel a pixel. Também grava amostras em /tmp/imp-story-samples
/// (o GitHub Actions guarda essa pasta para conferência visual).
final class StoryOptimizerImageTests: XCTestCase {
    static let samples = URL(fileURLWithPath: "/tmp/imp-story-samples", isDirectory: true)
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("story-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: Self.samples, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    // MARK: - Imagens fabricadas

    private func makeImage(_ width: Int, _ height: Int, _ draw: (CGContext) -> Void) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: StoryOptimizer.srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        draw(ctx)
        return ctx.makeImage()!
    }

    private func flat(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ width: Int = 1080, _ height: Int = 1920) -> CGImage {
        makeImage(width, height) { ctx in
            ctx.setFillColor(CGColor(srgbRed: r, green: g, blue: b, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// Criativo de mentira: degradê, formas e barras brancas no lugar do texto.
    private func colorful(_ width: Int = 1600, _ height: Int = 1200) -> CGImage {
        makeImage(width, height) { ctx in
            let colors = [CGColor(srgbRed: 0.45, green: 0.05, blue: 0.6, alpha: 1), CGColor(srgbRed: 0.05, green: 0.1, blue: 0.35, alpha: 1)] as CFArray
            let gradient = CGGradient(colorsSpace: StoryOptimizer.srgb, colors: colors, locations: [0, 1])!
            ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
            ctx.setFillColor(CGColor(srgbRed: 1, green: 0.8, blue: 0.1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: width / 2 - 260, y: height / 2 - 260, width: 520, height: 520))
            ctx.setFillColor(CGColor(srgbRed: 0.9, green: 0.15, blue: 0.2, alpha: 1))
            ctx.fill(CGRect(x: 80, y: 80, width: 300, height: 120))
            ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            for i in 0..<4 {
                ctx.fill(CGRect(x: 120, y: height - 160 - i * 70, width: width - 240 - i * 180, height: 36))
            }
        }
    }

    private func write(_ image: CGImage, _ name: String, type: UTType = .png, properties: [CFString: Any]? = nil) -> URL {
        let url = tmp.appendingPathComponent(name)
        let dst = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dst, image, properties as CFDictionary?)
        XCTAssertTrue(CGImageDestinationFinalize(dst))
        return url
    }

    /// RGBX 8 bits, de cima para baixo.
    private func pixels(_ ci: CIImage) throws -> [UInt8] {
        try StoryOptimizer.rasterize(ci).pixels
    }

    private func decode(_ url: URL) -> (image: CGImage, pixels: [UInt8])? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        var buf = [UInt8](repeating: 0, count: img.width * img.height * 4)
        buf.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: img.width * 4,
                                space: StoryOptimizer.srgb, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        }
        return (img, buf)
    }

    private func pixel(_ px: [UInt8], x: Int, y: Int, width: Int = 1080) -> (r: Int, g: Int, b: Int) {
        let i = (y * width + x) * 4
        return (Int(px[i]), Int(px[i + 1]), Int(px[i + 2]))
    }

    private func channelStats(_ px: [UInt8], channel: Int) -> (mean: Double, sd: Double, minV: Int, maxV: Int) {
        var sum = 0.0, sq = 0.0, lo = 255, hi = 0, n = 0.0
        var i = channel
        while i < px.count {
            let v = Int(px[i])
            sum += Double(v); sq += Double(v * v); lo = min(lo, v); hi = max(hi, v); n += 1
            i += 4
        }
        let mean = sum / n
        return (mean, (sq / n - mean * mean).squareRoot(), lo, hi)
    }

    private var coverOptions: StoryOptions {
        var o = StoryOptions()
        o.fit = .cover
        return o
    }

    private func compose(_ img: CGImage, _ options: StoryOptions, _ params: StoryParams) -> CIImage {
        StoryOptimizer.compose(img, options: options, params: params, background: StoryOptimizer.backgroundColor(for: img, options: options))
    }

    // MARK: - Geometria e enquadramento

    func testNeutralParamsKeepAFlatImage() throws {
        let px = try pixels(compose(flat(0.5, 0.5, 0.5), coverOptions, StoryParams()))
        XCTAssertEqual(px.count, 1080 * 1920 * 4)
        let s = channelStats(px, channel: 1)
        XCTAssertLessThanOrEqual(s.maxV - s.minV, 1, "sem variações, a imagem lisa continua lisa")
    }

    func testRotationAndCropLeaveNoEmptyCorners() throws {
        let green = flat(0.1, 0.8, 0.2)
        for shift in [-1.0, 1.0] {
            var p = StoryParams()
            p.rotationDegrees = 0.8 * shift
            p.cropFraction = 0.015
            p.cropShiftX = shift
            p.cropShiftY = -shift
            let px = try pixels(compose(green, coverOptions, p))
            for (x, y) in [(0, 0), (1079, 0), (0, 1919), (1079, 1919)] {
                let c = pixel(px, x: x, y: y)
                XCTAssertGreaterThan(c.g, 180, "canto (\(x),\(y)) vazio com rotação \(p.rotationDegrees)")
                XCTAssertLessThan(c.r, 60)
            }
        }
    }

    func testMirrorSwapsSides() throws {
        let img = makeImage(1080, 1920) { ctx in
            ctx.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 540, height: 1920))
            ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)); ctx.fill(CGRect(x: 540, y: 0, width: 540, height: 1920))
        }
        var p = StoryParams()
        let plain = try pixels(compose(img, coverOptions, p))
        XCTAssertGreaterThan(pixel(plain, x: 100, y: 960).r, 200)
        p.mirror = true
        let mirrored = try pixels(compose(img, coverOptions, p))
        let c = pixel(mirrored, x: 100, y: 960)
        XCTAssertGreaterThan(c.b, 200, "espelhado: o azul passa para a esquerda")
        XCTAssertLessThan(c.r, 40)
    }

    func testBlurFitFillsTopAndBottomWithTheImage() throws {
        var o = StoryOptions()
        o.fit = .blurFit
        let wide = flat(0.9, 0.5, 0.1, 1600, 900)
        let px = try pixels(compose(wide, o, StoryParams()))
        let top = pixel(px, x: 540, y: 100), bottom = pixel(px, x: 540, y: 1820), mid = pixel(px, x: 540, y: 960)
        for c in [top, bottom] {
            XCTAssertGreaterThan(c.r, 150, "o fundo é a própria imagem desfocada, não preto")
            XCTAssertLessThan(c.b, 80, "nem branco")
        }
        XCTAssertEqual(Double(mid.r), 230, accuracy: 3)
    }

    func testSolidUsesDominantColor() throws {
        var o = StoryOptions()
        o.fit = .solid
        o.solidColor = .dominant
        let img = makeImage(1600, 900) { ctx in
            ctx.setFillColor(CGColor(srgbRed: 220 / 255, green: 30 / 255, blue: 30 / 255, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 1600, height: 900))
            ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)); ctx.fill(CGRect(x: 600, y: 300, width: 300, height: 300))
        }
        let dominant = try pixels(compose(img, o, StoryParams()))
        let c = pixel(dominant, x: 10, y: 10)
        XCTAssertEqual(Double(c.r), 220, accuracy: 6)
        XCTAssertEqual(Double(c.g), 30, accuracy: 6)
        o.solidColor = .black
        let black = try pixels(compose(img, o, StoryParams()))
        XCTAssertLessThan(pixel(black, x: 10, y: 10).r, 3)
    }

    // MARK: - Cor, ruído, canal, granulação

    func testBrightnessShiftMatchesPercent() throws {
        let base = channelStats(try pixels(compose(flat(0.5, 0.5, 0.5), coverOptions, StoryParams())), channel: 0).mean
        var p = StoryParams()
        p.brightness = 0.02
        let s = channelStats(try pixels(compose(flat(0.5, 0.5, 0.5), coverOptions, p)), channel: 0)
        XCTAssertEqual(s.mean, base + 5.1, accuracy: 1.6, "+2% de brilho ≈ +5 níveis")
    }

    /// O ruído fica dentro de ±N níveis, com média no lugar (não clareia nem escurece a imagem).
    func testNoiseStaysWithinAmplitude() throws {
        let base = channelStats(try pixels(compose(flat(0.5, 0.5, 0.5), coverOptions, StoryParams())), channel: 0).mean
        var p = StoryParams()
        p.noiseAmplitude = 3
        p.noiseOffsetX = 777
        p.noiseOffsetY = 1234
        let px = try pixels(compose(flat(0.5, 0.5, 0.5), coverOptions, p))
        for channel in 0..<3 {
            let s = channelStats(px, channel: channel)
            print("ruído ±3 canal \(channel): média \(s.mean) desvio \(s.sd) min \(s.minV) max \(s.maxV)")
            XCTAssertEqual(s.mean, base, accuracy: 0.8)
            XCTAssertGreaterThan(s.sd, 1.2, "o ruído existe")
            XCTAssertLessThan(s.sd, 2.3)
            XCTAssertGreaterThanOrEqual(Double(s.minV), base - 4.5)
            XCTAssertLessThanOrEqual(Double(s.maxV), base + 4.5)
        }
    }

    func testChromaticShiftMovesOneChannelByOnePixel() throws {
        let img = makeImage(1080, 1920) { ctx in
            ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 1080, height: 1920))
            ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)); ctx.fill(CGRect(x: 540, y: 0, width: 540, height: 1920))
        }
        var p = StoryParams()
        p.chromaticChannel = .red
        p.chromaticDX = 1
        let px = try pixels(compose(img, coverOptions, p))
        func edge(_ channel: Int) -> Int? {
            (0..<1079).first { x in px[(960 * 1080 + x) * 4 + channel] > 127 }
        }
        let g = try XCTUnwrap(edge(1)), r = try XCTUnwrap(edge(0)), b = try XCTUnwrap(edge(2))
        XCTAssertEqual(g, b, "verde e azul não andam")
        XCTAssertEqual(abs(r - g), 1, "vermelho anda exatamente 1px")
    }

    func testFilmGrainIsSubtle() throws {
        let base = channelStats(try pixels(compose(flat(0.5, 0.5, 0.5), coverOptions, StoryParams())), channel: 1).mean
        var p = StoryParams()
        p.grainOpacity = 0.03
        p.grainOffsetX = 50
        let s = channelStats(try pixels(compose(flat(0.5, 0.5, 0.5), coverOptions, p)), channel: 1)
        print("granulação 3%: média \(s.mean) desvio \(s.sd) min \(s.minV) max \(s.maxV)")
        XCTAssertEqual(s.mean, base, accuracy: 1.5)
        XCTAssertGreaterThan(s.maxV - s.minV, 0, "a granulação existe")
        XCTAssertLessThanOrEqual(s.maxV - s.minV, 10)
    }

    // MARK: - Arquivo final

    /// Ponteiro simples pelos marcadores do JPEG (até o início dos dados da imagem).
    private struct JPEGInfo {
        var progressive = false
        var sampling: UInt8?
        var exif = false
        var xmp = false
        var icc = false
        var comment = false
    }

    private func jpegInfo(_ data: Data) -> JPEGInfo {
        let b = [UInt8](data)
        var info = JPEGInfo()
        var i = 2
        while i + 4 < b.count, b[i] == 0xFF {
            let m = b[i + 1]
            let len = Int(b[i + 2]) << 8 | Int(b[i + 3])
            let seg = Array(b[(i + 4)..<min(i + 2 + len, b.count)])
            switch m {
            case 0xE1:
                if seg.starts(with: Array("Exif".utf8)) { info.exif = true }
                if String(decoding: seg, as: UTF8.self).contains("ns.adobe.com/xap") { info.xmp = true }
            case 0xE2:
                if seg.starts(with: Array("ICC_PROFILE".utf8)) { info.icc = true }
            case 0xFE:
                info.comment = true
            case 0xC0, 0xC1, 0xC2:
                info.progressive = m == 0xC2
                info.sampling = b[i + 11]
            case 0xDA:
                return info
            default:
                break
            }
            i += 2 + len
        }
        return info
    }

    func testOutputIsCleanStoryJPEG() throws {
        // entrada com EXIF, GPS, TIFF e orientação 6 (deitada)
        let source = write(colorful(1200, 1600), "entrada.jpg", type: .jpeg, properties: [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "SecretCam", kCGImagePropertyTIFFSoftware: "SpyWare 9"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "comentario secreto"],
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 29.95, kCGImagePropertyGPSLatitudeRef: "S"],
        ])
        let raw = try Data(contentsOf: source)
        XCTAssertNotNil(raw.range(of: Data("SecretCam".utf8)), "a entrada tem metadados (conferência do teste)")

        var o = StoryOptions()
        o.intensity = .moderate
        for (seed, name) in [(UInt64(11), "a"), (UInt64(12), "b"), (UInt64(13), "c"), (UInt64(14), "d")] {
            let p = StoryParams.sample(o, seed: seed)
            let out = tmp.appendingPathComponent("story_\(name).jpg")
            try StoryOptimizer.process(source: source, options: o, params: p, to: out)
            let data = try Data(contentsOf: out)
            let info = jpegInfo(data)
            XCTAssertNil(data.range(of: Data("SecretCam".utf8)))
            XCTAssertNil(data.range(of: Data("SpyWare".utf8)))
            XCTAssertNil(data.range(of: Data("secreto".utf8)))
            XCTAssertFalse(info.exif, "sem EXIF")
            XCTAssertFalse(info.xmp, "sem XMP")
            XCTAssertFalse(info.comment, "sem comentário")
            XCTAssertTrue(info.icc, "com perfil sRGB")
            XCTAssertEqual(info.progressive, p.progressive)
            XCTAssertEqual(info.sampling, p.chroma444 ? 0x11 : 0x22, "subamostragem do sorteio")
            let decoded = try XCTUnwrap(decode(out))
            XCTAssertEqual(decoded.image.width, 1080)
            XCTAssertEqual(decoded.image.height, 1920)
            let props = CGImageSourceCopyPropertiesAtIndex(CGImageSourceCreateWithURL(out as CFURL, nil)!, 0, nil) as? [CFString: Any]
            XCTAssertNil(props?[kCGImagePropertyGPSDictionary])
            XCTAssertNil(props?[kCGImagePropertyTIFFDictionary])
        }
    }

    func testSameSeedGivesIdenticalFileAndDifferentSeedsDiffer() throws {
        let source = write(colorful(), "fonte.png")
        var o = StoryOptions()
        o.intensity = .moderate
        let p1 = StoryParams.sample(o, seed: 5), p2 = StoryParams.sample(o, seed: 6)
        let a = tmp.appendingPathComponent("a.jpg"), b = tmp.appendingPathComponent("b.jpg"), c = tmp.appendingPathComponent("c.jpg")
        try StoryOptimizer.process(source: source, options: o, params: p1, to: a)
        try StoryOptimizer.process(source: source, options: o, params: p1, to: b)
        try StoryOptimizer.process(source: source, options: o, params: p2, to: c)
        XCTAssertEqual(try Data(contentsOf: a), try Data(contentsOf: b), "preview = arquivo final")
        XCTAssertNotEqual(try Data(contentsOf: a), try Data(contentsOf: c))
    }

    func testPNGOutputHasNoMetadata() throws {
        let source = write(colorful(), "fonte.png")
        var o = StoryOptions()
        o.format = .png
        let out = tmp.appendingPathComponent("story.png")
        try StoryOptimizer.process(source: source, options: o, params: StoryParams.sample(o, seed: 3), to: out)
        let decoded = try XCTUnwrap(decode(out))
        XCTAssertEqual(decoded.image.width, 1080)
        XCTAssertEqual(decoded.image.height, 1920)
        // confere os blocos do arquivo (o leitor da Apple inventa um {Exif} com as dimensões, então lemos os bytes)
        let bytes = [UInt8](try Data(contentsOf: out))
        var types: [String] = []
        var i = 8
        while i + 12 <= bytes.count {
            let length = Int(bytes[i]) << 24 | Int(bytes[i + 1]) << 16 | Int(bytes[i + 2]) << 8 | Int(bytes[i + 3])
            types.append(String(decoding: bytes[(i + 4)..<(i + 8)], as: UTF8.self))
            i += 12 + length
        }
        print("PNG blocos: \(types)")
        XCTAssertEqual(types.first, "IHDR")
        XCTAssertEqual(types.last, "IEND")
        XCTAssertTrue(Set(types).isSubset(of: StoryOptimizer.keptPNGChunks), "só blocos de imagem e cor: \(types)")
        XCTAssertFalse(types.contains("eXIf"))
    }

    func testCleanPNGDropsTextAndExifChunks() {
        func chunk(_ type: String, _ payload: [UInt8]) -> [UInt8] {
            let n = payload.count
            return [UInt8(n >> 24 & 255), UInt8(n >> 16 & 255), UInt8(n >> 8 & 255), UInt8(n & 255)] + Array(type.utf8) + payload + [0, 0, 0, 0]
        }
        let sig: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        let dirty = sig + chunk("IHDR", Array(repeating: 1, count: 13)) + chunk("eXIf", Array("SecretCam".utf8))
            + chunk("tEXt", Array("Software Spy".utf8)) + chunk("IDAT", [9, 9, 9]) + chunk("IEND", [])
        let clean = [UInt8](StoryOptimizer.cleanPNG(Data(dirty)))
        XCTAssertEqual(clean, sig + chunk("IHDR", Array(repeating: 1, count: 13)) + chunk("IDAT", [9, 9, 9]) + chunk("IEND", []))
    }

    /// Amostras para conferir a olho (guardadas pelo GitHub Actions) e tempo por imagem.
    func testWriteSamplesAndMeasureSpeed() throws {
        let source = write(colorful(4000, 3000), "fonte-grande.png")
        try? FileManager.default.copyItem(at: source, to: Self.samples.appendingPathComponent("0-entrada-4000x3000.png"))
        var timings: [Double] = []
        for (i, fit) in StoryFit.allCases.enumerated() {
            for intensity in [StoryIntensity.light, .moderate] {
                var o = StoryOptions()
                o.fit = fit
                o.intensity = intensity
                o.solidColor = .dominant
                let out = Self.samples.appendingPathComponent("\(i + 1)-\(fit.rawValue)-\(intensity.rawValue).jpg")
                let t0 = Date()
                try StoryOptimizer.process(source: source, options: o, params: StoryParams.sample(o, seed: UInt64(100 + i)), to: out)
                timings.append(Date().timeIntervalSince(t0))
            }
        }
        // ampliação 4x de um pedaço, para ver ruído e granulação
        var o = StoryOptions()
        o.intensity = .moderate
        o.fit = .cover
        let params = StoryParams.sample(o, seed: 100)
        let cg = try XCTUnwrap(StoryOptimizer.loadSource(source))
        let crop = StoryOptimizer.compose(cg, options: o, params: params, background: .black)
            .cropped(to: CGRect(x: 400, y: 900, width: 270, height: 480))
            .transformed(by: CGAffineTransform(translationX: -400, y: -900))
            .samplingNearest()
            .transformed(by: CGAffineTransform(scaleX: 4, y: 4))
        let zoomed = try XCTUnwrap(StoryOptimizer.context.createCGImage(crop, from: CGRect(x: 0, y: 0, width: 1080, height: 1920)))
        _ = write(zoomed, "zoom.png")
        try? FileManager.default.copyItem(at: tmp.appendingPathComponent("zoom.png"), to: Self.samples.appendingPathComponent("9-zoom-4x-moderado.png"))
        // folha de contato (3×2) em base64 no log, para conferir sem baixar o artefato
        let outputs = StoryFit.allCases.enumerated().flatMap { i, fit in
            [StoryIntensity.light, .moderate].map { Self.samples.appendingPathComponent("\(i + 1)-\(fit.rawValue)-\($0.rawValue).jpg") }
        }
        let tileW = 360, tileH = 640
        let sheet = makeImage(tileW * 2, tileH * 3) { ctx in
            ctx.interpolationQuality = .high
            for (n, url) in outputs.enumerated() {
                guard let img = decode(url)?.image else { continue }
                let col = n % 2, row = 2 - n / 2
                ctx.draw(img, in: CGRect(x: col * tileW, y: row * tileH, width: tileW, height: tileH))
            }
        }
        for (name, img) in [("folha", sheet), ("zoom", zoomed)] {
            let url = write(img, "\(name).jpg", type: .jpeg, properties: [kCGImageDestinationLossyCompressionQuality: name == "zoom" ? 0.95 : 0.85])
            let b64 = try Data(contentsOf: url).base64EncodedString()
            var i = b64.startIndex
            while i < b64.endIndex {
                let j = b64.index(i, offsetBy: 2000, limitedBy: b64.endIndex) ?? b64.endIndex
                print("SAMPLEB64 \(name) \(b64[i..<j])")
                i = j
            }
        }
        let avg = timings.reduce(0, +) / Double(timings.count)
        print("Otimizador: \(String(format: "%.3f", avg)) s por imagem (entrada 4000×3000, \(timings.count) amostras)")
        XCTAssertLessThan(avg, 5, "uma imagem não pode levar mais que alguns segundos")
    }
}
