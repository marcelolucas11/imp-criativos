import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import AppKit

/// Operações de imagem com ImageIO/CoreGraphics (sem dependências externas).
enum ImageTools {
    static func pixelSize(of url: URL) -> CGSize? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        // fotos com rotação EXIF 5–8 têm largura/altura trocadas na exibição
        if let o = props[kCGImagePropertyOrientation] as? Int, (5...8).contains(o) {
            return CGSize(width: h, height: w)
        }
        return CGSize(width: w, height: h)
    }

    /// Carrega já com a orientação EXIF aplicada, limitando o maior lado.
    static func loadCGImage(_ url: URL, maxPixel: Int? = nil) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let size = pixelSize(of: url) ?? .zero
        let longest = Int(max(size.width, size.height))
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(maxPixel ?? longest, max(longest, 1)),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    static func cgImage(from data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 8192,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    static func encode(_ image: CGImage, as type: UTType, quality: Double = 0.92) -> Data? {
        let data = NSMutableData()
        guard let dst = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
        let props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(dst, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dst) else { return nil }
        return data as Data
    }

    /// Versão para enviar à IA: JPEG, maior lado até 2048 px.
    static func uploadJPEG(_ url: URL) -> Data? {
        guard let img = loadCGImage(url, maxPixel: 2048) else { return nil }
        return encode(flattened(img), as: .jpeg, quality: 0.9)
    }

    /// Remove transparência (fundo branco) — JPEG não tem canal alfa.
    static func flattened(_ img: CGImage) -> CGImage {
        guard img.alphaInfo != .none, img.alphaInfo != .noneSkipLast, img.alphaInfo != .noneSkipFirst else { return img }
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return img }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: img.width, height: img.height))
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        return ctx.makeImage() ?? img
    }

    /// Redimensiona preenchendo o quadro (corta o excesso pelo centro).
    static func aspectFill(_ img: CGImage, to target: CGSize) -> CGImage? {
        let tw = Int(target.width), th = Int(target.height)
        guard tw > 0, th > 0 else { return nil }
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: tw, height: th, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        let sw = CGFloat(img.width), sh = CGFloat(img.height)
        let scale = max(CGFloat(tw) / sw, CGFloat(th) / sh)
        let dw = sw * scale, dh = sh * scale
        let rect = CGRect(x: (CGFloat(tw) - dw) / 2, y: (CGFloat(th) - dh) / 2, width: dw, height: dh)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: tw, height: th))
        ctx.draw(img, in: rect)
        return ctx.makeImage()
    }

    /// Proporção suportada pelo Gemini mais próxima da imagem original.
    static func nearestAspectRatio(width: Int, height: Int) -> String {
        let options: [(String, Double)] = [
            ("1:1", 1), ("4:5", 0.8), ("5:4", 1.25), ("3:4", 0.75), ("4:3", 4.0 / 3),
            ("2:3", 2.0 / 3), ("3:2", 1.5), ("9:16", 9.0 / 16), ("16:9", 16.0 / 9), ("21:9", 21.0 / 9),
        ]
        let r = Double(width) / Double(max(height, 1))
        return options.min { abs(log($0.1 / r)) < abs(log($1.1 / r)) }!.0
    }

    /// Salva a resposta da IA como PNG na pasta do lote.
    static func saveGenerated(_ data: Data, to url: URL) throws {
        if let img = cgImage(from: data), let png = encode(img, as: .png) {
            try png.write(to: url, options: .atomic)
        } else {
            try data.write(to: url, options: .atomic)
        }
    }

    /// 1.0.0-beta.8: copia o original como PNG (com a rotação EXIF aplicada) para servir de "limpo"
    /// quando não há nada a remover. Devolve false se não conseguir ler ou gravar.
    static func copyAsPNG(_ src: URL, to dst: URL) -> Bool {
        guard let img = loadCGImage(src), let png = encode(img, as: .png) else { return false }
        return (try? png.write(to: dst, options: .atomic)) != nil
    }

    // MARK: miniaturas para as telas

    private static let cache = NSCache<NSString, NSImage>()

    static func thumbnail(_ url: URL, maxPixel: Int = 480) -> NSImage? {
        let key = "\(url.path)#\(maxPixel)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let cg = loadCGImage(url, maxPixel: maxPixel) else { return nil }
        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache.setObject(img, forKey: key)
        return img
    }

    static func invalidateThumbnails() { cache.removeAllObjects() }
}
