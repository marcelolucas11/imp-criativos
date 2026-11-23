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
        if p.lineStyle == .tone {
            applyToneLines(&px, width: W, height: H, params: p)
            return
        }
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

    // MARK: - Linhas no tom (beta.25)

    /// Número de 0 a 1 tirado de (a, b, semente): sempre o mesmo para os mesmos valores.
    @inline(__always)
    static func hash01(_ a: Int, _ b: Int, _ seed: UInt64) -> Double {
        let ka: UInt64 = UInt64(bitPattern: Int64(a)) &* 0x9E37_79B9_7F4A_7C15
        let kb: UInt64 = UInt64(bitPattern: Int64(b)) &* 0xC2B2_AE3D_27D4_EB4F
        var h: UInt64 = seed &+ ka &+ kb
        h ^= h >> 30
        h = h &* 0xBF58_476D_1CE4_E5B9
        h ^= h >> 27
        h = h &* 0x94D0_49BB_1331_11EB
        h ^= h >> 31
        return Double(h >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    @inline(__always)
    static func smoothstep(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
        let t = min(max((x - e0) / (e1 - e0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Força do risco num trecho de uma linha (0 = falha). Sem irregularidade, sempre 1.
    /// Com irregularidade `r` (0 a 1): até 30% dos trechos somem e a força dos outros varia entre 1 − 0,7·r e 1.
    @inline(__always)
    static func segmentStrength(line: Int, segment: Int, irregularity r: Double, seed: UInt64) -> Double {
        guard r > 0 else { return 1 }
        if hash01(line, segment, seed) < 0.3 * r { return 0 }
        return 1 - r * 0.7 * hash01(line, segment, seed ^ 0x5DEE_CE66)
    }

    /// Perfil de uma linha no Tom: quanto o brilho muda a `d` px do centro (−1 = escurece tudo o que a força permite,
    /// +0,5 = clareia metade disso). Miolo escuro de `thickness` px com 1 px de borda suave e, colado de um lado,
    /// um brilho fraco de ~2 px. Nada de degrau duro: é isso que tira a cara de "padrão digital".
    @inline(__always)
    static func toneProfile(distance d: Double, thickness t: Double) -> Double {
        let half = t / 2
        let dark = 1 - smoothstep(half - 0.5, half + 0.5, abs(d))
        let glow = max(0, 1 - abs(d - (half + 1)) / 1.2)
        return -dark + 0.5 * glow
    }

    /// Quanto da linha entra num pixel com luminância `luma` (0 a 1): as áreas muito claras (texto branco, luzes) quase não recebem.
    @inline(__always)
    static func toneProtection(luma: Double) -> Double { 1 - smoothstep(0.72, 0.97, luma) }

    /// Multiplica R, G e B pelo mesmo fator (a cor fica a mesma, só o brilho muda). Para clarear, o fator para antes
    /// de o canal mais forte estourar — senão a proporção entre os canais, e com ela a cor, mudaria.
    @inline(__always)
    static func toneScale(r: UInt8, g: UInt8, b: UInt8, factor: Double) -> (UInt8, UInt8, UInt8) {
        var f: Double = max(factor, 0)
        if f > 1 {
            let m: Double = Double(max(r, max(g, b)))
            if m > 0 { f = min(f, 255 / m) }
        }
        let k: Double = f
        func c(_ v: UInt8) -> UInt8 {
            let x: Double = (Double(v) * k).rounded()
            return UInt8(min(max(x, 0), 255))
        }
        return (c(r), c(g), c(b))
    }

    /// Linhas no tom da imagem. Cada camada é uma família de linhas paralelas com ângulo `lineAngle` (graus a partir da horizontal),
    /// espaçadas `lineSpacing` px (distância de uma linha à outra) e com miolo de `lineThickness` px. Com irregularidade, cada linha
    /// anda um pouco para o lado e é feita de trechos de ~36 px com força diferente (alguns somem), como chuva ou filme riscado.
    /// `lineOpacity` é a variação máxima de brilho no centro da linha. No X as duas camadas entram em sequência.
    static func applyToneLines(_ px: inout [UInt8], width W: Int, height H: Int, params p: StoryParams) {
        guard p.lineOpacity > 0, W > 0, H > 0, px.count >= W * H * 4 else { return }
        let spacingPx: Int = min(max(p.lineSpacing, 4), 64)
        let s: Double = Double(spacingPx)
        let t: Double = Double(min(max(p.lineThickness, 1), spacingPx - 2))
        let irr: Double = p.lineIrregularity.isFinite ? p.lineIrregularity : 0
        let r: Double = min(max(irr, 0), 1)
        let angle: Double = p.lineAngle.isFinite ? p.lineAngle : 45
        let theta: Double = min(max(angle, 10), 80) * Double.pi / 180
        let sn: Double = Foundation.sin(theta)
        let cs: Double = Foundation.cos(theta)
        let useBack: Bool = p.lineDirection != .slash
        let useFwd: Bool = p.lineDirection != .backslash
        let cross: Bool = useBack && useFwd
        let balance: Double = cross ? StoryTexture.lineCrossBalance : 1
        let amp: Double = min(max(p.lineOpacity, 0), 0.6) * balance
        // quanto cada linha pode andar para o lado sem encostar na vizinha
        let room: Double = max(0, (s - t - 2) / 2)
        let maxShift: Double = r * room
        let reach: Double = t / 2 + 2.3
        let phaseFwd: Double = Double(cross ? p.linePhase2 : p.linePhase)
        let seedFwd: UInt64 = cross ? (p.lineSeed ^ 0x9E37_79B9_7F4A_7C15) : p.lineSeed
        let geo = ToneGeometry(spacing: s, thickness: t, irregularity: r, sin: sn, cos: cs, amplitude: amp, maxShift: maxShift, reach: reach)
        px.withUnsafeMutableBufferPointer { (buf: inout UnsafeMutableBufferPointer<UInt8>) -> Void in
            if useBack { toneLayer(buf, width: W, height: H, geo: geo, slash: false, phase: Double(p.linePhase), seed: p.lineSeed) }
            if useFwd { toneLayer(buf, width: W, height: H, geo: geo, slash: true, phase: phaseFwd, seed: seedFwd) }
        }
    }

    /// Medidas de uma passada de linhas no tom (as mesmas para as duas diagonais do X).
    struct ToneGeometry {
        let spacing: Double
        let thickness: Double
        let irregularity: Double
        let sin: Double
        let cos: Double
        let amplitude: Double
        let maxShift: Double
        let reach: Double
    }

    /// Uma família de linhas paralelas no tom.
    /// n: posição perpendicular às linhas (px) · u: posição ao longo da linha (px), com y de cima para baixo.
    /// `\`: n = x·sen − y·cos, u = x·cos + y·sen  ·  `/`: n = x·sen + y·cos, u = x·cos − y·sen.
    static func toneLayer(_ buf: UnsafeMutableBufferPointer<UInt8>, width W: Int, height H: Int, geo g: ToneGeometry,
                          slash: Bool, phase: Double, seed: UInt64) {
        let s: Double = g.spacing
        let ny: Double = slash ? g.cos : -g.cos
        let uy: Double = slash ? -g.sin : g.sin
        let segLen: Double = StoryTexture.toneSegmentLength
        for y in 0..<H {
            var n: Double = Double(y) * ny + phase
            var u: Double = Double(y) * uy
            var o: Int = y * W * 4
            for _ in 0..<W {
                let q: Double = n / s
                let line: Int = Int(q.rounded(.down))
                var shift: Double = 0
                if g.maxShift > 0 {
                    let h: Double = hash01(line, -7, seed)
                    shift = (h * 2 - 1) * g.maxShift
                }
                let frac: Double = q - Double(line)
                let d: Double = frac * s - s / 2 - shift
                if abs(d) <= g.reach {
                    let profile: Double = toneProfile(distance: d, thickness: g.thickness)
                    let strength: Double = toneStrength(line: line, along: u, segmentLength: segLen, irregularity: g.irregularity, seed: seed)
                    if profile != 0 && strength > 0 {
                        let R: UInt8 = buf[o], G: UInt8 = buf[o + 1], B: UInt8 = buf[o + 2]
                        let lr: Double = 0.299 * Double(R)
                        let lg: Double = 0.587 * Double(G)
                        let lb: Double = 0.114 * Double(B)
                        let luma: Double = (lr + lg + lb) / 255
                        let k: Double = g.amplitude * profile * strength * toneProtection(luma: luma)
                        if k != 0 {
                            let out = toneScale(r: R, g: G, b: B, factor: 1 + k)
                            buf[o] = out.0
                            buf[o + 1] = out.1
                            buf[o + 2] = out.2
                        }
                    }
                }
                n += g.sin
                u += g.cos
                o += 4
            }
        }
    }

    /// Força do risco num ponto da linha: os trechos têm força própria e a passagem de um para o outro é suave.
    @inline(__always)
    static func toneStrength(line: Int, along u: Double, segmentLength: Double, irregularity r: Double, seed: UInt64) -> Double {
        guard r > 0 else { return 1 }
        let offset: Double = hash01(line, -3, seed) * 8
        let a: Double = u / segmentLength + offset
        let j: Int = Int(a.rounded(.down))
        let f: Double = smoothstep(0, 1, a - Double(j))
        let s0: Double = segmentStrength(line: line, segment: j, irregularity: r, seed: seed)
        let s1: Double = segmentStrength(line: line, segment: j + 1, irregularity: r, seed: seed)
        return s0 + (s1 - s0) * f
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
