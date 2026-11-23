namespace IMPCriativos.Core.Story;

/// <summary>
/// 1.0.0-beta.23: efeitos de textura que rodam sobre os pixels já desenhados do Otimizador em Lote (Stories 9:16):
/// serrilhado das bordas e linhas diagonais. C# puro, mesmo algoritmo de <c>Pipeline/StoryTextureEffects.swift</c>.
///
/// O buffer é RGBX de 8 bits, de cima para baixo (4 bytes por pixel). Tudo é inteiro e determinístico:
/// a mesma semente dá o mesmo resultado, no preview e no arquivo final.
/// </summary>
public static class StoryTextureEffects
{
    // MARK: - Linhas diagonais

    public const int BandNone = 0, BandDark = 1, BandLight = 2;

    /// <summary>Cada linha é um par de faixas coladas dentro do período: <c>thickness</c> px escuros e, logo depois, <c>highlight</c> px claros.</summary>
    public static int Band(int k, int thickness, int highlight) =>
        k < thickness ? BandDark : (k < thickness + highlight ? BandLight : BandNone);

    /// <summary>Estado do pixel (x, y) — y de cima para baixo — numa camada. slash false: <c>\</c>; true: <c>/</c>.</summary>
    public static int BandState(int x, int y, int spacing, int thickness, int highlight, bool slash, int phase)
    {
        var s = Math.Max(spacing, 2);
        var k = (((slash ? x + y : x - y) + phase) % s + s) % s;
        return Band(k, thickness, highlight);
    }

    /// <summary>Duas tabelas de 256 entradas: o valor de um canal depois de uma faixa escura e de uma faixa de realce passarem por cima.</summary>
    public static (byte[] Dark, byte[] Light) LineLUTs(StoryLineBlend blend, double opacity, bool cross = false)
    {
        var @base = Math.Min(Math.Max(double.IsFinite(opacity) ? opacity : 0, 0), 1) * (cross ? StoryTexture.LineCrossBalance : 1);
        double aDark = @base, aLight = @base * StoryTexture.LineHighlightRatio;
        var dark = new byte[256];
        var light = new byte[256];
        for (var v = 0; v < 256; v++)
        {
            var b = v / 255.0;
            double darkTarget, lightTarget;
            if (blend == StoryLineBlend.HardLight)
            {
                darkTarget = 0;
                lightTarget = 1;
            }
            else
            {
                darkTarget = b < 0.5 ? 0 : 2 * b - 1;
                lightTarget = b < 0.5 ? 2 * b : 1;
            }
            byte Out(double target, double a) => (byte)Math.Min(Math.Max(R.Round((b + (target - b) * a) * 255), 0), 255);
            dark[v] = Out(darkTarget, aDark);
            light[v] = Out(lightTarget, aLight);
        }
        return (dark, light);
    }

    /// <summary>Desenha as linhas diagonais. Só os pixels das faixas mudam; o resto fica intacto.</summary>
    public static void ApplyLines(byte[] px, int W, int H, StoryParams p)
    {
        if (!(p.LineOpacity > 0) || W <= 0 || H <= 0 || px.Length < W * H * 4) return;
        if (p.LineStyle == StoryLineStyle.Tone)
        {
            ApplyToneLines(px, W, H, p);
            return;
        }
        var s = Math.Min(Math.Max(p.LineSpacing, 4), 64);
        var t = Math.Min(Math.Max(p.LineThickness, 1), s - 2);
        var h = StoryTexture.LineHighlightWidth(s, t);
        var useBack = p.LineDirection != StoryLineDirection.Slash;
        var useFwd = p.LineDirection != StoryLineDirection.Backslash;
        var cross = useBack && useFwd;
        var (ld, ll) = LineLUTs(p.LineBlend, p.LineOpacity, cross);
        var phaseBack = p.LinePhase;
        // no X a segunda diagonal tem fase própria; sozinha, a `/` usa a mesma fase da `\`
        var phaseFwd = cross ? p.LinePhase2 : p.LinePhase;
        for (var y = 0; y < H; y++)
        {
            var kb = (((phaseBack - y) % s) + s) % s;
            var kf = (((phaseFwd + y) % s) + s) % s;
            var o = y * W * 4;
            for (var x = 0; x < W; x++)
            {
                if (useBack)
                {
                    if (kb < t) { px[o] = ld[px[o]]; px[o + 1] = ld[px[o + 1]]; px[o + 2] = ld[px[o + 2]]; }
                    else if (kb < t + h) { px[o] = ll[px[o]]; px[o + 1] = ll[px[o + 1]]; px[o + 2] = ll[px[o + 2]]; }
                }
                if (useFwd)
                {
                    if (kf < t) { px[o] = ld[px[o]]; px[o + 1] = ld[px[o + 1]]; px[o + 2] = ld[px[o + 2]]; }
                    else if (kf < t + h) { px[o] = ll[px[o]]; px[o + 1] = ll[px[o + 1]]; px[o + 2] = ll[px[o + 2]]; }
                }
                kb++; if (kb == s) kb = 0;
                kf++; if (kf == s) kf = 0;
                o += 4;
            }
        }
    }

    // MARK: - Linhas no tom (beta.25)

    /// <summary>Número de 0 a 1 tirado de (a, b, semente): sempre o mesmo para os mesmos valores.</summary>
    public static double Hash01(int a, int b, ulong seed)
    {
        unchecked
        {
            var ka = (ulong)(long)a * 0x9E3779B97F4A7C15UL;
            var kb = (ulong)(long)b * 0xC2B2AE3D27D4EB4FUL;
            var h = seed + ka + kb;
            h ^= h >> 30;
            h *= 0xBF58476D1CE4E5B9UL;
            h ^= h >> 27;
            h *= 0x94D049BB133111EBUL;
            h ^= h >> 31;
            return (h >> 11) * (1.0 / 9_007_199_254_740_992.0);
        }
    }

    public static double Smoothstep(double e0, double e1, double x)
    {
        var t = Math.Min(Math.Max((x - e0) / (e1 - e0), 0), 1);
        return t * t * (3 - 2 * t);
    }

    /// <summary>Força do risco num trecho de uma linha (0 = falha). Sem irregularidade, sempre 1.</summary>
    public static double SegmentStrength(int line, int segment, double r, ulong seed)
    {
        if (!(r > 0)) return 1;
        if (Hash01(line, segment, seed) < 0.3 * r) return 0;
        return 1 - r * 0.7 * Hash01(line, segment, seed ^ 0x5DEECE66UL);
    }

    /// <summary>Perfil de uma linha no Tom: quanto o brilho muda a <paramref name="d"/> px do centro.</summary>
    public static double ToneProfile(double d, double t)
    {
        var half = t / 2;
        var dark = 1 - Smoothstep(half - 0.5, half + 0.5, Math.Abs(d));
        var glow = Math.Max(0, 1 - Math.Abs(d - (half + 1)) / 1.2);
        return -dark + 0.5 * glow;
    }

    /// <summary>Quanto da linha entra num pixel com luminância <paramref name="luma"/> (0 a 1).</summary>
    public static double ToneProtection(double luma) => 1 - Smoothstep(0.72, 0.97, luma);

    /// <summary>Multiplica R, G e B pelo mesmo fator (a cor fica a mesma, só o brilho muda).</summary>
    public static (byte R, byte G, byte B) ToneScale(byte r, byte g, byte b, double factor)
    {
        var f = Math.Max(factor, 0);
        if (f > 1)
        {
            double m = Math.Max(r, Math.Max(g, b));
            if (m > 0) f = Math.Min(f, 255 / m);
        }
        byte C(byte v) => (byte)Math.Min(Math.Max(R.Round(v * f), 0), 255);
        return (C(r), C(g), C(b));
    }

    public sealed record ToneGeometry(double Spacing, double Thickness, double Irregularity, double Sin, double Cos, double Amplitude,
        double MaxShift, double Reach);

    /// <summary>Linhas no tom da imagem (ângulo livre, borda suave, riscos irregulares).</summary>
    public static void ApplyToneLines(byte[] px, int W, int H, StoryParams p)
    {
        if (!(p.LineOpacity > 0) || W <= 0 || H <= 0 || px.Length < W * H * 4) return;
        var spacingPx = Math.Min(Math.Max(p.LineSpacing, 4), 64);
        double s = spacingPx;
        double t = Math.Min(Math.Max(p.LineThickness, 1), spacingPx - 2);
        var irr = double.IsFinite(p.LineIrregularity) ? p.LineIrregularity : 0;
        var r = Math.Min(Math.Max(irr, 0), 1);
        var angle = double.IsFinite(p.LineAngle) ? p.LineAngle : 45;
        var theta = Math.Min(Math.Max(angle, 10), 80) * Math.PI / 180;
        var sn = Math.Sin(theta);
        var cs = Math.Cos(theta);
        var useBack = p.LineDirection != StoryLineDirection.Slash;
        var useFwd = p.LineDirection != StoryLineDirection.Backslash;
        var cross = useBack && useFwd;
        var balance = cross ? StoryTexture.LineCrossBalance : 1;
        var amp = Math.Min(Math.Max(p.LineOpacity, 0), 0.6) * balance;
        // quanto cada linha pode andar para o lado sem encostar na vizinha
        var room = Math.Max(0, (s - t - 2) / 2);
        var maxShift = r * room;
        var reach = t / 2 + 2.3;
        double phaseFwd = cross ? p.LinePhase2 : p.LinePhase;
        var seedFwd = cross ? (p.LineSeed ^ 0x9E3779B97F4A7C15UL) : p.LineSeed;
        var geo = new ToneGeometry(s, t, r, sn, cs, amp, maxShift, reach);
        if (useBack) ToneLayer(px, W, H, geo, false, p.LinePhase, p.LineSeed);
        if (useFwd) ToneLayer(px, W, H, geo, true, phaseFwd, seedFwd);
    }

    /// <summary>
    /// Uma família de linhas paralelas no tom. n: posição perpendicular às linhas · u: posição ao longo da linha.
    /// <c>\</c>: n = x·sen − y·cos, u = x·cos + y·sen · <c>/</c>: n = x·sen + y·cos, u = x·cos − y·sen.
    /// </summary>
    public static void ToneLayer(byte[] buf, int W, int H, ToneGeometry g, bool slash, double phase, ulong seed)
    {
        var s = g.Spacing;
        var ny = slash ? g.Cos : -g.Cos;
        var uy = slash ? -g.Sin : g.Sin;
        const double segLen = StoryTexture.ToneSegmentLength;
        for (var y = 0; y < H; y++)
        {
            var n = y * ny + phase;
            var u = y * uy;
            var o = y * W * 4;
            for (var x = 0; x < W; x++)
            {
                var q = n / s;
                var line = (int)Math.Floor(q);
                double shift = 0;
                if (g.MaxShift > 0)
                {
                    var hh = Hash01(line, -7, seed);
                    shift = (hh * 2 - 1) * g.MaxShift;
                }
                var frac = q - line;
                var d = frac * s - s / 2 - shift;
                if (Math.Abs(d) <= g.Reach)
                {
                    var profile = ToneProfile(d, g.Thickness);
                    var strength = ToneStrength(line, u, segLen, g.Irregularity, seed);
                    if (profile != 0 && strength > 0)
                    {
                        byte R0 = buf[o], G0 = buf[o + 1], B0 = buf[o + 2];
                        var lr = 0.299 * R0;
                        var lg = 0.587 * G0;
                        var lb = 0.114 * B0;
                        var luma = (lr + lg + lb) / 255;
                        var k = g.Amplitude * profile * strength * ToneProtection(luma);
                        if (k != 0)
                        {
                            var oc = ToneScale(R0, G0, B0, 1 + k);
                            buf[o] = oc.R;
                            buf[o + 1] = oc.G;
                            buf[o + 2] = oc.B;
                        }
                    }
                }
                n += g.Sin;
                u += g.Cos;
                o += 4;
            }
        }
    }

    /// <summary>Força do risco num ponto da linha: os trechos têm força própria e a passagem de um para o outro é suave.</summary>
    public static double ToneStrength(int line, double u, double segmentLength, double r, ulong seed)
    {
        if (!(r > 0)) return 1;
        var offset = Hash01(line, -3, seed) * 8;
        var a = u / segmentLength + offset;
        var j = (int)Math.Floor(a);
        var f = Smoothstep(0, 1, a - j);
        var s0 = SegmentStrength(line, j, r, seed);
        var s1 = SegmentStrength(line, j + 1, r, seed);
        return s0 + (s1 - s0) * f;
    }

    // MARK: - Serrilhado das bordas

    /// <summary>Força da borda (diferença de luminância, 0–255) a partir da qual o serrilhado começa e onde chega ao máximo.</summary>
    public const int EdgeLow = 30;
    public const int EdgeHigh = 90;

    private static ulong Mix(ulong v)
    {
        unchecked
        {
            var z = v + 0x9E3779B97F4A7C15UL;
            z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9UL;
            z = (z ^ (z >> 27)) * 0x94D049BB133111EBUL;
            return z ^ (z >> 31);
        }
    }

    /// <summary>Máscara de bordas (0–255): Sobel na luminância, depois uma dilatação de 2px.</summary>
    public static byte[] EdgeMask(byte[] px, int W, int H)
    {
        var n = W * H;
        if (W < 3 || H < 3 || px.Length < n * 4) return new byte[Math.Max(n, 0)];
        var lum = new byte[n];
        for (var i = 0; i < n; i++)
        {
            var o = i * 4;
            lum[i] = unchecked((byte)((77 * px[o] + 150 * px[o + 1] + 29 * px[o + 2]) >> 8));
        }
        var edge = new byte[n];
        for (var y = 1; y < H - 1; y++)
        {
            int r0 = (y - 1) * W, r1 = y * W, r2 = (y + 1) * W;
            for (var x = 1; x < W - 1; x++)
            {
                int tl = lum[r0 + x - 1], tc = lum[r0 + x], tr = lum[r0 + x + 1];
                int ml = lum[r1 + x - 1], mr = lum[r1 + x + 1];
                int bl = lum[r2 + x - 1], bc = lum[r2 + x], br = lum[r2 + x + 1];
                var gx = (tr + 2 * mr + br) - (tl + 2 * ml + bl);
                var gy = (bl + 2 * bc + br) - (tl + 2 * tc + tr);
                // um degrau de altura D dá |gx| = 4D, então /4 devolve a altura do degrau
                edge[r1 + x] = (byte)Math.Min(255, (Math.Abs(gx) + Math.Abs(gy)) / 4);
            }
        }
        const int radius = 2;
        var wide = new byte[n];
        for (var y = 0; y < H; y++)
        {
            var row = y * W;
            for (var x = 0; x < W; x++)
            {
                byte m = 0;
                int lo = Math.Max(0, x - radius), hi = Math.Min(W - 1, x + radius);
                for (var k = lo; k <= hi; k++) if (edge[row + k] > m) m = edge[row + k];
                wide[row + x] = m;
            }
        }
        var mask = new byte[n];
        for (var y = 0; y < H; y++)
        {
            int lo = Math.Max(0, y - radius), hi = Math.Min(H - 1, y + radius);
            for (var x = 0; x < W; x++)
            {
                byte v = 0;
                for (var k = lo; k <= hi; k++) if (wide[k * W + x] > v) v = wide[k * W + x];
                mask[y * W + x] = v;
            }
        }
        return mask;
    }

    /// <summary>Serrilhado: quebra a suavidade (anti-aliasing) só onde há borda forte. Fora das bordas, nada muda.</summary>
    public static void ApplyEdgeJitter(byte[] px, int W, int H, double level, ulong seed)
    {
        if (!(level > 0) || !double.IsFinite(level) || W < 8 || H < 8 || px.Length < W * H * 4) return;
        var L = Math.Min(level, 1);
        var mask = EdgeMask(px, W, H);

        var weight = new int[256];
        for (var v = 0; v < 256; v++)
            weight[v] = Math.Min(256, Math.Max(0, (v - EdgeLow) * 256 / (EdgeHigh - EdgeLow)));

        var f = 1 - 0.5 * L;
        var mapX = new int[W];
        var mapY = new int[H];
        for (var x = 0; x < W; x++) mapX[x] = Math.Min(W - 1, (int)R.Round((int)(x * f) / f));
        for (var y = 0; y < H; y++) mapY[y] = Math.Min(H - 1, (int)R.Round((int)(y * f) / f));

        var J = (int)R.Round(L * 3);
        var rowOff = new int[H];
        var colOff = new int[W];
        if (J > 0)
        {
            var span = (ulong)(2 * J + 1);
            unchecked
            {
                for (var y = 0; y < H; y++) rowOff[y] = (int)(Mix(seed ^ ((ulong)y * 0xD6E8FEB86659FD93UL)) % span) - J;
                for (var x = 0; x < W; x++) colOff[x] = (int)(Mix(~seed ^ ((ulong)x * 0xA24BAED4963EE407UL)) % span) - J;
            }
        }

        var src = (byte[])px.Clone();
        for (var y = 0; y < H; y++)
        {
            int ro = rowOff[y], sy0 = mapY[y];
            for (var x = 0; x < W; x++)
            {
                var w = weight[mask[y * W + x]];
                if (w == 0) continue;
                var sx = Math.Min(Math.Max(mapX[x] + ro, 0), W - 1);
                var sy = Math.Min(Math.Max(sy0 + colOff[x], 0), H - 1);
                var so = (sy * W + sx) * 4;
                var d = (y * W + x) * 4;
                for (var c = 0; c < 3; c++)
                    px[d + c] = (byte)((src[d + c] * (256 - w) + src[so + c] * w) >> 8);
            }
        }
    }
}
