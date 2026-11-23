import Foundation

// 1.0.0-beta.23: efeitos de textura que rodam sobre os pixels já desenhados do Otimizador em Lote (Stories 9:16):
// serrilhado das bordas e linhas diagonais. Arquivo puro (só Foundation), para os testes automáticos rodarem sem o app.
//
// O buffer é RGBX de 8 bits, de cima para baixo (4 bytes por pixel), o mesmo que o `rasterize` do motor entrega.
// Tudo é inteiro e determinístico: a mesma semente dá o mesmo resultado, no preview e no arquivo final.
//
// Por que na CPU e não no Core Image:
// - o serrilhado precisa de reamostragem "nearest" exata e de um deslocamento por linha e coluna, que o Core Image
//   não faz sem um kernel próprio (Metal) — e as linhas precisam de pixel exato, sem filtro;
// - uma imagem 1080×1920 tem 2 milhões de pixels: cada passada é uma volta simples por um buffer, dezenas de ms.
enum StoryTextureEffects {

    // MARK: - Linhas diagonais

    /// Estado de um pixel numa camada de linhas: fora das faixas, faixa escura ou faixa de realce claro.
    static let bandNone = 0, bandDark = 1, bandLight = 2

    /// Cada linha é um par de faixas coladas dentro do período `spacing`: `thickness` px escuros e, logo depois,
    /// `highlight` px de realce claro (efeito de relevo / gravura); o resto do período fica intacto.
    /// Tudo em pixels inteiros: nada de reamostragem nem suavização, então as bordas das faixas saem firmes.
    static func band(k: Int, thickness: Int, highlight: Int) -> Int {
        k < thickness ? bandDark : (k < thickness + highlight ? bandLight : bandNone)
    }

    /// Estado do pixel (x, y) — com y de cima para baixo — numa camada. `slash == false`: `\` (x − y constante, desce para a
    /// direita); `slash == true`: `/` (x + y constante). Uma é o espelho exato da outra, com a mesma força.
    static func bandState(x: Int, y: Int, spacing: Int, thickness: Int, highlight: Int, slash: Bool, phase: Int) -> Int {
        let s = max(spacing, 2)
        let k = (((slash ? x + y : x - y) + phase) % s + s) % s
        return band(k: k, thickness: thickness, highlight: highlight)
    }

    /// Duas tabelas de 256 entradas: o valor de um canal depois de uma faixa escura e de uma faixa de realce passarem por cima.
    ///
    /// Tinta preta (faixa escura) e branca (realce); b = valor do canal de 0 a 1:
    /// - hard-light: escura = b·0 = 0 · realce = screen com branco = 1 (os dois extremos, então aparece em qualquer cor);
    /// - overlay: escura = 0 nas sombras e 2·b − 1 nas luzes · realce = 2·b nas sombras e 1 nas luzes.
    /// A opacidade mistura o original com esse resultado; o realce usa `lineHighlightRatio` da opacidade da faixa escura.
    /// No X, cada camada usa `lineCrossBalance` da opacidade.
    static func lineLUTs(blend: StoryLineBlend, opacity: Double, cross: Bool = false) -> (dark: [UInt8], light: [UInt8]) {
        let base = min(max(opacity.isFinite ? opacity : 0, 0), 1) * (cross ? StoryTexture.lineCrossBalance : 1)
        let aDark = base, aLight = base * StoryTexture.lineHighlightRatio
        var dark = [UInt8](repeating: 0, count: 256), light = [UInt8](repeating: 0, count: 256)
        for v in 0..<256 {
            let b = Double(v) / 255
            let darkTarget: Double, lightTarget: Double
            switch blend {
            case .hardLight:
                darkTarget = 0
                lightTarget = 1
            case .overlay:
                darkTarget = b < 0.5 ? 0 : 2 * b - 1
                lightTarget = b < 0.5 ? 2 * b : 1
            }
            func out(_ target: Double, _ a: Double) -> UInt8 { UInt8(min(max(((b + (target - b) * a) * 255).rounded(), 0), 255)) }
            dark[v] = out(darkTarget, aDark)
            light[v] = out(lightTarget, aLight)
        }
        return (dark, light)
    }

    /// Desenha as linhas diagonais. Só os pixels das faixas mudam; o resto fica intacto.
    /// No X, as duas diagonais entram em sequência (cada uma com a própria fase e `lineCrossBalance` da opacidade).
    static func applyLines(_ px: inout [UInt8], width W: Int, height H: Int, params p: StoryParams) {
        guard p.lineOpacity > 0, W > 0, H > 0, px.count >= W * H * 4 else { return }
        let s = min(max(p.lineSpacing, 4), 64)
        let t = min(max(p.lineThickness, 1), s - 2)
        let h = StoryTexture.lineHighlightWidth(spacing: s, thickness: t)
        let useBack = p.lineDirection != .slash
        let useFwd = p.lineDirection != .backslash
        let cross = useBack && useFwd
        let luts = lineLUTs(blend: p.lineBlend, opacity: p.lineOpacity, cross: cross)
        let phaseBack = p.linePhase
        // no X a segunda diagonal tem fase própria; sozinha, a `/` usa a mesma fase da `\`
        let phaseFwd = cross ? p.linePhase2 : p.linePhase
        px.withUnsafeMutableBufferPointer { buf in
            luts.dark.withUnsafeBufferPointer { ld in
                luts.light.withUnsafeBufferPointer { ll in
                    for y in 0..<H {
                        // contadores que andam 1 por pixel (evita uma divisão por pixel)
                        var kb = (((phaseBack - y) % s) + s) % s
                        var kf = (((phaseFwd + y) % s) + s) % s
                        var o = y * W * 4
                        for _ in 0..<W {
                            if useBack {
                                if kb < t {
                                    buf[o] = ld[Int(buf[o])]; buf[o + 1] = ld[Int(buf[o + 1])]; buf[o + 2] = ld[Int(buf[o + 2])]
                                } else if kb < t + h {
                                    buf[o] = ll[Int(buf[o])]; buf[o + 1] = ll[Int(buf[o + 1])]; buf[o + 2] = ll[Int(buf[o + 2])]
                                }
                            }
                            if useFwd {
                                if kf < t {
                                    buf[o] = ld[Int(buf[o])]; buf[o + 1] = ld[Int(buf[o + 1])]; buf[o + 2] = ld[Int(buf[o + 2])]
                                } else if kf < t + h {
                                    buf[o] = ll[Int(buf[o])]; buf[o + 1] = ll[Int(buf[o + 1])]; buf[o + 2] = ll[Int(buf[o + 2])]
                                }
                            }
                            kb += 1
                            if kb == s { kb = 0 }
                            kf += 1
                            if kf == s { kf = 0 }
                            o += 4
                        }
                    }
                }
            }
        }
    }

    // MARK: - Serrilhado das bordas

    /// Força da borda (diferença de luminância, 0–255) a partir da qual o serrilhado começa e onde chega ao máximo.
    /// Ruído, granulação e degradês ficam abaixo disso; texto, botões e contornos fortes ficam acima.
    static let edgeLow = 30
    static let edgeHigh = 90

    private static func mix(_ v: UInt64) -> UInt64 {
        var z = v &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Máscara de bordas (0–255): Sobel na luminância, depois uma dilatação de 2px para cobrir a vizinhança da borda.
    /// Exposta para os testes.
    static func edgeMask(_ px: [UInt8], width W: Int, height H: Int) -> [UInt8] {
        let n = W * H
        guard W >= 3, H >= 3, px.count >= n * 4 else { return [UInt8](repeating: 0, count: max(n, 0)) }
        var lum = [UInt8](repeating: 0, count: n)
        px.withUnsafeBufferPointer { p in
            lum.withUnsafeMutableBufferPointer { l in
                for i in 0..<n {
                    let o = i * 4
                    l[i] = UInt8(truncatingIfNeeded: (77 * Int(p[o]) + 150 * Int(p[o + 1]) + 29 * Int(p[o + 2])) >> 8)
                }
            }
        }
        var edge = [UInt8](repeating: 0, count: n)
        lum.withUnsafeBufferPointer { l in
            edge.withUnsafeMutableBufferPointer { e in
                for y in 1..<(H - 1) {
                    let r0 = (y - 1) * W, r1 = y * W, r2 = (y + 1) * W
                    for x in 1..<(W - 1) {
                        let tl = Int(l[r0 + x - 1]), tc = Int(l[r0 + x]), tr = Int(l[r0 + x + 1])
                        let ml = Int(l[r1 + x - 1]), mr = Int(l[r1 + x + 1])
                        let bl = Int(l[r2 + x - 1]), bc = Int(l[r2 + x]), br = Int(l[r2 + x + 1])
                        let gx = (tr + 2 * mr + br) - (tl + 2 * ml + bl)
                        let gy = (bl + 2 * bc + br) - (tl + 2 * tc + tr)
                        // um degrau de altura D dá |gx| = 4D, então /4 devolve a altura do degrau
                        e[r1 + x] = UInt8(min(255, (abs(gx) + abs(gy)) / 4))
                    }
                }
            }
        }
        let radius = 2
        var wide = [UInt8](repeating: 0, count: n)
        edge.withUnsafeBufferPointer { e in
            wide.withUnsafeMutableBufferPointer { w in
                for y in 0..<H {
                    let row = y * W
                    for x in 0..<W {
                        var m: UInt8 = 0
                        let lo = max(0, x - radius), hi = min(W - 1, x + radius)
                        for k in lo...hi { m = max(m, e[row + k]) }
                        w[row + x] = m
                    }
                }
            }
        }
        var mask = [UInt8](repeating: 0, count: n)
        wide.withUnsafeBufferPointer { w in
            mask.withUnsafeMutableBufferPointer { m in
                for y in 0..<H {
                    let lo = max(0, y - radius), hi = min(H - 1, y + radius)
                    for x in 0..<W {
                        var v: UInt8 = 0
                        for k in lo...hi { v = max(v, w[k * W + x]) }
                        m[y * W + x] = v
                    }
                }
            }
        }
        return mask
    }

    /// Serrilhado: quebra a suavidade (anti-aliasing) só onde há borda forte. Fora das bordas, nada muda.
    ///
    /// Em cada pixel da zona de borda, o valor vem de outro pixel da própria imagem:
    /// 1. reamostragem *nearest* por degraus: a grade é reduzida a `f` (de 100% a 50%, conforme o nível) e ampliada de volta
    ///    sem suavizar, o que cria os degraus "de escada" nos contornos;
    /// 2. jitter por linha e por coluna: cada linha da imagem anda de −J a +J px na horizontal e cada coluna de −J a +J px na
    ///    vertical (J de 0 a 3 conforme o nível), o que rasga as bordas como num sinal ruim.
    /// A mistura com o original segue a força da borda (suave perto do limiar, total nas bordas fortes).
    static func applyEdgeJitter(_ px: inout [UInt8], width W: Int, height H: Int, level: Double, seed: UInt64) {
        guard level > 0, level.isFinite, W >= 8, H >= 8, px.count >= W * H * 4 else { return }
        let L = min(level, 1)
        let mask = edgeMask(px, width: W, height: H)

        var weight = [Int](repeating: 0, count: 256)
        for v in 0..<256 {
            weight[v] = min(256, max(0, (v - edgeLow) * 256 / (edgeHigh - edgeLow)))
        }

        let f = 1 - 0.5 * L
        var mapX = [Int](repeating: 0, count: W)
        var mapY = [Int](repeating: 0, count: H)
        for x in 0..<W { mapX[x] = min(W - 1, Int((Double(Int(Double(x) * f)) / f).rounded())) }
        for y in 0..<H { mapY[y] = min(H - 1, Int((Double(Int(Double(y) * f)) / f).rounded())) }

        let J = Int((L * 3).rounded())
        var rowOff = [Int](repeating: 0, count: H)
        var colOff = [Int](repeating: 0, count: W)
        if J > 0 {
            let span = UInt64(2 * J + 1)
            for y in 0..<H { rowOff[y] = Int(mix(seed ^ (UInt64(y) &* 0xD6E8_FEB8_6659_FD93)) % span) - J }
            for x in 0..<W { colOff[x] = Int(mix(~seed ^ (UInt64(x) &* 0xA24B_AED4_963E_E407)) % span) - J }
        }

        var out = px
        px.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                mask.withUnsafeBufferPointer { m in
                    for y in 0..<H {
                        let ro = rowOff[y], sy0 = mapY[y]
                        for x in 0..<W {
                            let w = weight[Int(m[y * W + x])]
                            if w == 0 { continue }
                            let sx = min(max(mapX[x] + ro, 0), W - 1)
                            let sy = min(max(sy0 + colOff[x], 0), H - 1)
                            let so = (sy * W + sx) * 4
                            let d = (y * W + x) * 4
                            for c in 0..<3 {
                                dst[d + c] = UInt8((Int(src[d + c]) * (256 - w) + Int(src[so + c]) * w) >> 8)
                            }
                        }
                    }
                }
            }
        }
        px = out
    }
}
