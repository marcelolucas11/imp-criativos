import Foundation
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UniformTypeIdentifiers
import CTurboJPEG

/// 1.0.0-beta.21: motor do Otimizador em Lote (Stories 9:16). 100% local: Core Image (placa de vídeo do Mac)
/// para enquadrar e ajustar, e libjpeg-turbo para gravar o JPEG. Nenhuma chamada de rede, nenhuma IA.
///
/// Ordem por imagem:
///   leitura (orientação EXIF aplicada, maior lado até 4096 px) → espelho (opcional) → enquadramento 9:16
///   → micro-recorte/rotação → brilho/contraste/saturação → nitidez ou suavização → deslocamento de canal
///   → granulação → micro-ruído → pixels novos em sRGB → JPEG (libjpeg-turbo) ou PNG (ImageIO), sem metadados.
///
/// Os metadados somem porque a imagem é redesenhada do zero num buffer novo: EXIF, IPTC, XMP, GPS, comentários
/// e perfis de cor antigos não passam para o arquivo. Só entra um perfil sRGB limpo, para as cores não mudarem.
enum StoryOptimizer {
    static let width = 1080
    static let height = 1920
    /// Limite de leitura: fotos enormes são lidas já reduzidas (economiza memória com 4 imagens ao mesmo tempo).
    static let maxSourcePixel = 4096

    static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
    static var canvas: CGRect { CGRect(x: 0, y: 0, width: width, height: height) }

    /// Contexto único (seguro para várias threads). Trabalha em sRGB "com gama", para que o ruído de
    /// ±N níveis e os ±% de brilho/contraste correspondam aos 0–255 do arquivo final.
    static let context = CIContext(options: [
        .workingColorSpace: srgb,
        .outputColorSpace: srgb,
        .cacheIntermediates: false,
    ])

    enum Failure: LocalizedError {
        case unreadable
        case render
        case encode(String)

        var errorDescription: String? {
            switch self {
            case .unreadable: return "Não consegui abrir a imagem (arquivo corrompido ou formato não suportado)."
            case .render: return "Falha ao desenhar a imagem final."
            case let .encode(msg): return "Falha ao gravar o arquivo: \(msg)"
            }
        }
    }

    // MARK: - Entrada

    static func loadSource(_ url: URL) -> CGImage? {
        ImageTools.loadCGImage(url, maxPixel: maxSourcePixel)
    }

    /// Cor de fundo do modo "Cor sólida" (e da transparência de PNGs).
    static func backgroundColor(for source: CGImage, options: StoryOptions) -> RGBColor {
        guard options.fit == .solid else { return RGBColor(r: 1, g: 1, b: 1) }
        switch options.solidColor {
        case .black: return .black
        case .custom: return options.customColor
        case .dominant: return dominantColor(of: source) ?? .black
        }
    }

    static func dominantColor(of source: CGImage) -> RGBColor? {
        let side = 64
        var buf = [UInt8](repeating: 0, count: side * side * 4)
        let ok = buf.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(source, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return ok ? DominantColor.compute(rgba: buf) : nil
    }

    // MARK: - Composição

    /// Monta a imagem final 1080×1920 (ainda sem gravar). Usada no lote e no preview.
    static func compose(_ source: CGImage, options: StoryOptions, params: StoryParams, background: RGBColor) -> CIImage {
        let W = CGFloat(width), H = CGFloat(height)
        let frame = canvas
        let bg = ciColor(background)

        var img = CIImage(cgImage: source)
        img = img.transformed(by: CGAffineTransform(translationX: -img.extent.minX, y: -img.extent.minY))
        if params.mirror {
            // x → largura − x
            img = img.transformed(by: CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -img.extent.width, y: 0))
        }
        // transparência fica sobre o fundo escolhido (cor sólida) ou branco
        img = img.composited(over: CIImage(color: bg).cropped(to: img.extent))

        // 1) Enquadramento 9:16
        let sw = max(img.extent.width, 1), sh = max(img.extent.height, 1)
        let coverScale = max(W / sw, H / sh)
        let fitScale = min(W / sw, H / sh)
        var out: CIImage
        switch options.fit {
        case .cover:
            out = centered(lanczos(img, coverScale), in: frame).cropped(to: frame)
        case .blurFit:
            let fg = centered(lanczos(img, fitScale), in: frame)
            // cópia ampliada (um pouco além do necessário, para esconder as bordas do desfoque), desfocada e levemente escurecida
            let back = centered(lanczos(img, coverScale * 1.08), in: frame)
                .clampedToExtent()
                .applyingGaussianBlur(sigma: 36)
                .applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: -0.06])
                .cropped(to: frame)
            out = fg.composited(over: back).cropped(to: frame)
        case .solid:
            let fg = centered(lanczos(img, fitScale), in: frame)
            out = fg.composited(over: CIImage(color: bg).cropped(to: frame)).cropped(to: frame)
        }

        // 2) Micro-recorte e micro-rotação, voltando a exatos 1080×1920 (Lanczos)
        if params.cropFraction > 0 || params.rotationDegrees != 0 {
            let zoomCrop = 1 / (1 - 2 * min(params.cropFraction, 0.1))
            let zoomRot = StoryParams.rotationZoom(width: Double(W), height: Double(H), degrees: params.rotationDegrees)
            let big = centered(lanczos(out, CGFloat(zoomCrop * zoomRot)), in: frame)
            let theta = CGFloat(params.rotationDegrees * .pi / 180)
            let rotate = CGAffineTransform(translationX: W / 2, y: H / 2).rotated(by: theta).translatedBy(x: -W / 2, y: -H / 2)
            // a sobra do recorte deixa a janela escorregar para um lado (90% da folga, por segurança nas bordas)
            let dx = CGFloat(params.cropShiftX * (zoomCrop - 1) / 2 * 0.9) * W
            let dy = CGFloat(params.cropShiftY * (zoomCrop - 1) / 2 * 0.9) * H
            out = big.clampedToExtent()
                .transformed(by: rotate.concatenating(CGAffineTransform(translationX: dx, y: dy)))
                .cropped(to: frame)
        }

        // 3) Brilho, contraste e saturação
        if params.brightness != 0 || params.contrast != 0 || params.saturation != 0 {
            let f = CIFilter.colorControls()
            f.inputImage = out
            f.brightness = Float(params.brightness)
            f.contrast = Float(1 + params.contrast)
            f.saturation = Float(1 + params.saturation)
            out = (f.outputImage ?? out).cropped(to: frame)
        }

        // 4) Micro-nitidez (Unsharp Mask) ou suavização mínima
        if params.sharpenIntensity > 0 {
            let f = CIFilter.unsharpMask()
            f.inputImage = out.clampedToExtent()
            f.radius = 1.2
            f.intensity = Float(params.sharpenIntensity)
            out = (f.outputImage ?? out).cropped(to: frame)
        } else if params.softenRadius > 0 {
            out = out.clampedToExtent().applyingGaussianBlur(sigma: params.softenRadius).cropped(to: frame)
        }

        // 5) Deslocamento de canal: R ou B andam 1px (sem reamostrar — deslocamento inteiro)
        if let channel = params.chromaticChannel {
            let base = out.clampedToExtent()
            let r = only(base, red: 1, green: 0, blue: 0)
            let g = only(base, red: 0, green: 1, blue: 0)
            let b = only(base, red: 0, green: 0, blue: 1)
            let shift = CGAffineTransform(translationX: CGFloat(params.chromaticDX), y: CGFloat(params.chromaticDY))
            let rr = channel == .red ? r.transformed(by: shift) : r
            let bb = channel == .blue ? b.transformed(by: shift) : b
            // cada imagem tem só um canal; o máximo por canal junta as três de volta
            out = rr.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: g])
                .applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: bb])
                .cropped(to: frame)
        }

        // 6) Granulação de filme (monocromática, overlay ou soft-light, 1–3%).
        //    O gerador de ruído é opaco à força (alfa 1) antes de mexer na cor, para os valores ficarem em 0–1.
        if params.grainOpacity > 0, let noise = CIFilter.randomGenerator().outputImage {
            let grain = noise
                .transformed(by: CGAffineTransform(translationX: -CGFloat(params.grainOffsetX), y: -CGFloat(params.grainOffsetY)))
                .cropped(to: frame.insetBy(dx: -4, dy: -4))
                .settingAlphaOne(in: frame.insetBy(dx: -4, dy: -4))
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                    "inputBVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                    "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                ])
                .applyingGaussianBlur(sigma: 0.6)
                .cropped(to: frame)
            let blended = grain.applyingFilter(params.grainSoftLight ? "CISoftLightBlendMode" : "CIOverlayBlendMode",
                                               parameters: [kCIInputBackgroundImageKey: out])
            let mix = CIFilter.dissolveTransition()
            mix.inputImage = out
            mix.targetImage = blended
            mix.time = Float(params.grainOpacity)
            out = (mix.outputImage ?? out).cropped(to: frame)
        }

        // 7) Micro-ruído uniforme de ±N níveis por canal (quebra faixas de cor na compressão do Instagram)
        if params.noiseAmplitude > 0, let noise = CIFilter.randomGenerator().outputImage {
            // linear light: resultado = base + 2·camada − 1 → camada = 0,5 + (u − 0,5)·k dá base ± k
            let k = CGFloat(params.noiseAmplitude / 255)
            let bias = 0.5 - 0.5 * k
            let layer = noise
                .transformed(by: CGAffineTransform(translationX: -CGFloat(params.noiseOffsetX), y: -CGFloat(params.noiseOffsetY)))
                .cropped(to: frame)
                .settingAlphaOne(in: frame)
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: k, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: k, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: k, w: 0),
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                    "inputBiasVector": CIVector(x: bias, y: bias, z: bias, w: 1),
                ])
                .cropped(to: frame)
            out = layer.applyingFilter("CILinearLightBlendMode", parameters: [kCIInputBackgroundImageKey: out]).cropped(to: frame)
        }

        return out.cropped(to: frame)
    }

    // MARK: - Saída

    struct Raster {
        let pixels: [UInt8]
        let pitch: Int
        let image: CGImage
    }

    /// Desenha num buffer novo RGBX 8 bits sRGB (de cima para baixo). Nada do arquivo original passa daqui.
    static func rasterize(_ image: CIImage) throws -> Raster {
        guard let cg = context.createCGImage(image, from: canvas, format: .RGBA8, colorSpace: srgb) else { throw Failure.render }
        let pitch = width * 4
        var buf = [UInt8](repeating: 0, count: pitch * height)
        let made: CGImage? = buf.withUnsafeMutableBytes { raw -> CGImage? in
            guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: pitch,
                                      space: srgb, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
            ctx.interpolationQuality = .none
            ctx.draw(cg, in: canvas)
            return ctx.makeImage()
        }
        guard let made else { throw Failure.render }
        return Raster(pixels: buf, pitch: pitch, image: made)
    }

    private static func tj<T: BinaryInteger>(_ v: T) -> Int32 { Int32(truncatingIfNeeded: v) }

    /// JPEG pela libjpeg-turbo: qualidade, baseline/progressivo e subamostragem 4:2:0/4:4:4 do sorteio,
    /// com perfil sRGB e nenhum outro metadado (sem EXIF, XMP, IPTC nem comentário).
    static func encodeJPEG(_ raster: Raster, params: StoryParams) throws -> Data {
        // tj3Init é uma macro em C (o Swift não enxerga); ela chama tj3InitVersion com a versão do cabeçalho
        guard let handle = tj3InitVersion(tj(TJINIT_COMPRESS.rawValue), tj(TURBOJPEG_VERSION_NUMBER)) else { throw Failure.encode("libjpeg-turbo não iniciou") }
        defer { tj3Destroy(handle) }
        func check(_ code: Int32) throws {
            if code != 0 { throw Failure.encode(String(cString: tj3GetErrorStr(handle))) }
        }
        try check(tj3Set(handle, tj(TJPARAM_QUALITY.rawValue), tj(params.quality)))
        try check(tj3Set(handle, tj(TJPARAM_SUBSAMP.rawValue), tj(params.chroma444 ? TJSAMP_444.rawValue : TJSAMP_420.rawValue)))
        try check(tj3Set(handle, tj(TJPARAM_PROGRESSIVE.rawValue), params.progressive ? 1 : 0))
        try check(tj3Set(handle, tj(TJPARAM_OPTIMIZE.rawValue), 1))
        if let iccData = srgb.copyICCData() as Data? {
            var icc = [UInt8](iccData)
            let count = icc.count
            try icc.withUnsafeMutableBufferPointer { p in try check(tj3SetICCProfile(handle, p.baseAddress, count)) }
        }
        var jpeg: UnsafeMutablePointer<UInt8>? = nil
        var size: Int = 0
        try raster.pixels.withUnsafeBufferPointer { p in
            try check(tj3Compress8(handle, p.baseAddress, tj(width), tj(raster.pitch), tj(height), tj(TJPF_RGBX.rawValue), &jpeg, &size))
        }
        guard let jpeg, size > 0 else { throw Failure.encode("JPEG vazio") }
        defer { tj3Free(jpeg) }
        return Data(bytes: jpeg, count: size)
    }

    /// PNG pelo ImageIO, sem metadados (só o perfil sRGB da imagem).
    static func encodePNG(_ raster: Raster) throws -> Data {
        let data = NSMutableData()
        guard let dst = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw Failure.encode("PNG não iniciou")
        }
        CGImageDestinationAddImage(dst, raster.image, nil)
        guard CGImageDestinationFinalize(dst) else { throw Failure.encode("PNG não finalizou") }
        return data as Data
    }

    /// Processa uma imagem do lote e grava em `output`. Devolve o tamanho do arquivo em bytes.
    @discardableResult
    static func process(source url: URL, options: StoryOptions, params: StoryParams, to output: URL) throws -> Int {
        try autoreleasepool {
            guard let cg = loadSource(url) else { throw Failure.unreadable }
            let composed = compose(cg, options: options, params: params, background: backgroundColor(for: cg, options: options))
            let raster = try rasterize(composed)
            let data = try (options.format == .jpg ? encodeJPEG(raster, params: params) : encodePNG(raster))
            try data.write(to: output, options: .atomic)
            return data.count
        }
    }

    /// Imagem do preview (mesma composição do arquivo final).
    static func preview(_ source: CGImage, options: StoryOptions, params: StoryParams) -> CGImage? {
        let composed = compose(source, options: options, params: params, background: backgroundColor(for: source, options: options))
        return context.createCGImage(composed, from: canvas, format: .RGBA8, colorSpace: srgb)
    }

    // MARK: - Utilidades

    private static func ciColor(_ c: RGBColor) -> CIColor {
        CIColor(red: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), alpha: 1, colorSpace: srgb)
            ?? CIColor(red: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b))
    }

    /// Redimensiona com Lanczos (alta qualidade).
    private static func lanczos(_ img: CIImage, _ scale: CGFloat) -> CIImage {
        guard abs(scale - 1) > 0.0001 else { return img }
        let f = CIFilter.lanczosScaleTransform()
        f.inputImage = img
        f.scale = Float(scale)
        f.aspectRatio = 1
        return f.outputImage ?? img.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }

    /// Centraliza no quadro com deslocamento inteiro (não borra os pixels).
    private static func centered(_ img: CIImage, in rect: CGRect) -> CIImage {
        let dx = (rect.midX - img.extent.midX).rounded()
        let dy = (rect.midY - img.extent.midY).rounded()
        return img.transformed(by: CGAffineTransform(translationX: dx, y: dy))
    }

    /// Mantém só um canal de cor (alfa 1).
    private static func only(_ img: CIImage, red: CGFloat, green: CGFloat, blue: CGFloat) -> CIImage {
        img.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: red, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: green, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: blue, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0),
        ])
    }
}
