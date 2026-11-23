// 1.0.0-beta.27: gera windows/tests/IMPCriativos.Tests/fixtures/paridade-mac.json a partir do código Swift do Mac.
// O teste ParidadeMacTests da versão Windows gera os mesmos textos e sorteios em C# e compara um por um.
// Rodado pelo CI do Mac (ci.yml): compila todo o Sources/IMPCriativos (menos o @main) junto com este arquivo.
// Uso: scripts/paridade/gerar.sh   (precisa de macOS e da libjpeg-turbo compilada)
import Foundation

var out: [String: String] = [:]

func put(_ key: String, _ value: String) { out[key] = value }
func d(_ v: Double) -> String { "\(v)" }

for keep in [false, true] {
    UserDefaults.standard.set(keep, forKey: Niche.keepNoticesKey)
    let k = keep ? "manter" : "remover"
    put("niche.noticesRule.\(k)", Niche.noticesRule)
    let plan = CreativePlan(forbiddenTerms: ["AVIATOR", "@marca"], originalText: "AVIATOR\nGANHE GIROS",
                            finalText: "GANHE GIROS", cleanInstruction: "Erase the AVIATOR logo at the top.",
                            variationRules: "Keep the red plane.", doubts: "", model: "m", needsCleaning: true)
    put("prompts.cleanFromPlan.\(k)", Prompts.cleanFromPlan(plan, extra: "  tirar o selo ", redoNote: "ficou borrado"))
    put("prompts.cleanFromPlan.vazio.\(k)", Prompts.cleanFromPlan(CreativePlan(forbiddenTerms: [], originalText: "", finalText: "",
        cleanInstruction: "x", variationRules: "", doubts: "", model: nil, needsCleaning: nil), extra: "", redoNote: nil))
    put("prompts.clean.\(k)", Prompts.clean(removeItems: ["Logotipo da empresa", "CNPJ"], extra: "sem o selo",
                                            textChanges: "Trocar \"R$ 10\" por \"R$ 5\"", forbidden: ["MARCA"], redoNote: "refazer"))
    put("prompts.clean.min.\(k)", Prompts.clean(removeItems: ["Logo"], extra: "", redoNote: nil))
    put("prompts.analysis.\(k)", Prompts.analysis(removeItems: ["Logo"], textChanges: "", forbidden: ["X1"]))
    put("prompts.analysis.changes.\(k)", Prompts.analysis(removeItems: ["Logo", "Site"], textChanges: "Incluir \"Nome\"", forbidden: []))
    let axis = VariationAxis(name: "Neon", instruction: "Complete redesign with neon.")
    put("prompts.variation.\(k)", Prompts.variation(axis: axis, transcript: "  GANHE GIROS\nSÓ HOJE ", extra: "extra", direction: "mais escuro",
                                                    textChanges: "", forbidden: ["AVIATOR"], rules: "Keep the plane.", redoNote: "a b"))
    put("prompts.variation.changes.\(k)", Prompts.variation(axis: axis, transcript: nil, extra: "", textChanges: "Incluir \"Y\"", redoNote: nil))
    put("prompts.variation.semtexto.\(k)", Prompts.variation(axis: axis, transcript: "", extra: "", redoNote: nil))
    put("prompts.textCheck.\(k)", Prompts.textCheck(expected: "GANHE GIROS", removeItems: ["Logo"], forbidden: ["AVIATOR"]))
    put("prompts.neutral.\(k)", Prompts.neutral("PROMPT"))
    let ins = BatchInstructions(raw: " tirar aviator ", removeItems: ["Palavra \"Aviator\""], textChanges: "Trocar A por B", direction: "noite")
    put("planner.prompt.\(k)", CreativePlanner.prompt(removeItems: ["Logo", "@x"], extra: " fixo ", instructions: ins))
    put("planner.prompt.vazio.\(k)", CreativePlanner.prompt(removeItems: [], extra: "", instructions: nil))
}
UserDefaults.standard.removeObject(forKey: Niche.keepNoticesKey)
put("niche.promptContext", Niche.promptContext)
put("niche.mainSubject", Niche.mainSubject)
put("niche.characterRules", Niche.characterRules)
put("niche.coherenceRules", Niche.coherenceRules)
put("instructions.prompt", InstructionInterpreter.prompt(for: "tirar o nome Aviator\ne deixar à noite"))
put("forbidden.fallback", ForbiddenTerms.fallback(from: ["Nome da empresa (escrito em qualquer lugar da imagem)", "Palavra \"Aviator\"",
    "nome Fortune Tiger", "Logotipo da empresa", "Blaze, Stake e KTO", "o @minhabet"]).joined(separator: "|"))
put("forbidden.found", ForbiddenTerms.found(in: "Jogue AVI ATOR agora! fera", terms: ["Aviator", "Ferramenta", "fera"]).joined(separator: "|"))
put("forbidden.strip", ForbiddenTerms.strip(["AVIATOR"], from: "GOSTA DE AVIATOR ?\nAVIATOR\nJOGUE  JÁ"))
put("forbidden.normalize", ForbiddenTerms.normalize("Ação — ＡＢＣ @Marca.com!"))

// sorteio do Otimizador em Lote
var cases: [(String, StoryOptions)] = []
for i in StoryIntensity.allCases {
    var o = StoryOptions(); o.intensity = i
    cases.append(("int-\(i.rawValue)", o))
}
for preset in StoryTexturePreset.allCases {
    for style in StoryLineStyle.allCases {
        var o = StoryOptions(); o.intensity = .normal
        o.selectTexturePreset(preset); o.setLinesEnabled(true); o.lineStyle = style
        o.lineDirection = style == .ink ? .cross : .random
        cases.append(("tex-\(preset.rawValue)-\(style.rawValue)", o))
    }
}
var png = StoryOptions(); png.format = .png; png.intensity = .aggressive; png.mirror = true
cases.append(("png-agressivo", png))
for (name, o) in cases {
    for seed: UInt64 in [1, 42, 123_456_789, 18_446_744_073_709_551_557] {
        for v in [1, 3] {
            let p = StoryParams.sample(o, seed: StoryVersions.seed(seed, version: v))
            let fields: [String] = [
                d(p.cropFraction), d(p.cropShiftX), d(p.cropShiftY), d(p.rotationDegrees), d(p.brightness), d(p.contrast),
                d(p.saturation), d(p.noiseAmplitude), d(p.noiseOffsetX), d(p.noiseOffsetY), p.chromaticChannel?.rawValue ?? "nil",
                "\(p.chromaticDX)", "\(p.chromaticDY)", d(p.grainOpacity), "\(p.grainSoftLight)", d(p.grainOffsetX), d(p.grainOffsetY),
                d(p.sharpenIntensity), d(p.softenRadius), "\(p.mirror)", p.perspective.map(d).joined(separator: ","), d(p.perspectiveMax),
                d(p.temperatureKelvin), d(p.diagonalAmplitude), "\(p.diagonalPeriod)", "\(p.diagonalAnti)", "\(p.diagonalPhase)",
                d(p.vignette), d(p.lineOpacity), "\(p.lineSpacing)", "\(p.lineThickness)", p.lineDirection.rawValue, p.lineBlend.rawValue,
                "\(p.linePhase)", "\(p.linePhase2)", p.lineStyle.rawValue, d(p.lineAngle), d(p.lineIrregularity), "\(p.lineSeed)",
                d(p.jitterLevel), "\(p.jitterSeed)", "\(p.aberrationDX)", "\(p.aberrationDY)", d(p.bloomLevel), d(p.blurAngle),
                "\(p.quality)", "\(p.progressive)", "\(p.chroma444)", p.code,
            ]
            put("params.\(name).\(seed).v\(v)", fields.joined(separator: ";"))
            put("summary.\(name).\(seed).v\(v)", p.summary)
        }
    }
}

let data = try! JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "paridade-mac.json"
try! data.write(to: URL(fileURLWithPath: path))
print("paridade: \(out.count) itens em \(path)")
