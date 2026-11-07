#!/usr/bin/env python3
"""Fonte única dos 50 eixos de variação de cassino e bet do IMP Criativos (1.0.0-beta.14).

Gera:
  - Sources/IMPCriativos/Models/DefaultAxes.swift  (ClientProfile.defaultAxes)
  - docs/EIXOS-DE-VARIACAO.md                      (biblioteca para consulta)
e valida as regras do nicho antes de escrever qualquer arquivo.

Uso (na raiz do repositório): python3 scripts/eixos_variacao.py .
Para mudar os eixos padrão, edite a lista AXES abaixo e rode de novo.
"""
import re, sys
from collections import Counter

FAM = {
    "A": "Layout",
    "B": "Estilo gráfico",
    "C": "Cenário (cassino ou bet)",
    "D": "Luz e cor",
    "E": "Tipografia e oferta",
    "F": "Ângulo e energia",
}

# (família, nome, o que muda, risco de texto, serve para, instrução)
# "serve para": Ambos = cassino e bet esportiva (os eixos de cenário se adaptam ao tema da referência).
AXES = [
    # ---------------- A — Layout ----------------
    ("A", "Destaque em close", "Close gigante do assunto + faixa de texto", "Baixo", "Ambos",
     "Complete redesign, not a retouch: a dramatic close-up of the main subject fills about two-thirds of the canvas, boldly cropped at one edge. All the text grouped in one compact, high-contrast block at the top, on a solid color band. New background and palette."),
    ("A", "Diagonal dividida", "Tela cortada na diagonal em 2 cores", "Médio", "Ambos",
     "Complete redesign: split the canvas with a strong diagonal into two contrasting color fields. The main subject large on one side, slightly breaking over the diagonal line; the text block on the other side, left-aligned. Clean modern shapes, crisp light."),
    ("A", "Faixa central", "Faixa larga no meio com o título", "Baixo", "Ambos",
     "Complete redesign: a bold full-width horizontal band crosses the middle of the canvas and carries the headline; the main subject sits above the band, partly overlapping it, and the rest of the text sits below. Punchy solid background in a new color."),
    ("A", "Pôster tipográfico", "Título enorme vira o protagonista", "Médio", "Ambos",
     "Complete redesign as a typographic poster: the headline (the most prominent text line) set in very large heavy letters across the top 40% of the canvas, every letter fully visible. The main subject below, smaller and centered, with the rest of the text beneath it. Minimal background, one strong accent color."),
    ("A", "Cartão flutuante", "Tudo dentro de um card sobre fundo novo", "Baixo", "Ambos",
     "Complete redesign: the main subject and all the text inside a large rounded card floating in the center with a soft shadow, over a contrasting gradient or textured background that fills the canvas. Modern, app-like look."),
    ("A", "Tela em destaque", "Tela do jogo/app em 3D, inclinada", "Médio", "Ambos",
     "Complete redesign around the screen: if the reference shows a phone or a game screen, make that screen the hero, large and tilted in 3D perspective with a soft glow around it; if it does not, present the main subject inside a large glowing rounded frame. Text in a clean block above."),
    ("A", "Editorial assimétrico", "Assunto à direita, texto e respiro à esquerda", "Médio", "Ambos",
     "Complete redesign with an editorial, asymmetric layout: the main subject off-center on the right, generous empty space on the left holding the text, left-aligned with a strong size hierarchy. Sophisticated background with one thin accent line."),
    ("A", "Halo circular", "Círculo/anel de luz emoldurando o assunto", "Baixo", "Ambos",
     "Complete redesign: a large glowing circle or ring behind the main subject frames it in the center like a halo; the text arranged above and below the circle. Bold two-tone background, clean geometric look."),
    ("A", "Leitura em Z", "Texto e assunto em zigue-zague dinâmico", "Médio", "Ambos",
     "Complete redesign with a Z-shaped reading path: the first part of the text at the top-left, the main subject large in the center-right, the remaining text at the bottom-left. Energetic background with motion lines or soft speed blur."),
    ("A", "Simetria central", "Composição espelhada e centralizada", "Baixo", "Ambos",
     "Complete redesign with a perfectly symmetrical vertical composition: the main subject centered in the middle third, mirrored light shapes on both sides, the text centered above and below in a strict hierarchy. Elegant and balanced."),
    # ---------------- B — Estilo gráfico ----------------
    ("B", "3D premium", "Formas 3D brilhantes flutuando", "Baixo", "Ambos",
     "Complete redesign in a premium 3D render style: glossy 3D geometric shapes (spheres, rings, pills) floating around the main subject, studio lighting with soft reflections, smooth gradient backdrop in a new palette. Text clean, bold and flat for perfect legibility."),
    ("B", "Neon noturno", "Fundo escuro com tubos e linhas de neon", "Médio", "Ambos",
     "Complete redesign with a night neon aesthetic: dark background, glowing neon tubes and light lines framing the main subject, colored rim light (magenta, cyan or purple) on it, light haze. Text in bright, sharp letters with a subtle glow, fully legible."),
    ("B", "Preto e dourado", "Luxo: preto, mármore e filetes dourados", "Baixo", "Ambos",
     "Complete redesign in a black-and-gold luxury style: deep black or dark marble background, fine gold lines and metallic accents, warm elegant light on the main subject. Text in refined gold or white letters. Sophisticated and minimal."),
    ("B", "Minimalista premium", "Muito espaço vazio, 1 cor de destaque", "Baixo", "Ambos",
     "Complete redesign in a minimalist premium-tech style: lots of empty space in a light or deep single tone, the main subject centered with a soft natural shadow, one accent color. Text perfectly aligned with elegant spacing. Calm and high-end."),
    ("B", "Vidro fosco", "Painéis de vidro translúcido", "Baixo", "Ambos",
     "Complete redesign in a glassmorphism style: colorful blurred gradient background with soft blobs of light, the text on frosted translucent glass panels with thin bright borders, the main subject in front in sharp focus. Modern and techy."),
    ("B", "Colagem recortada", "Recorte com borda de adesivo e papel rasgado", "Médio", "Ambos",
     "Complete redesign as a cut-out collage: the main subject cut out with a thick white sticker outline, over layered torn-paper shapes and textured paper in bold colors, slightly tilted for energy. Text on paper strips or tape pieces, clearly legible."),
    ("B", "Arcade retrô", "Pixel art, scanlines e cores de fliperama", "Médio", "Ambos",
     "Complete redesign in a retro arcade style: pixel-art borders and shapes, subtle scanlines and glowing screen colors around the main subject, which stays realistic, on a dark background. Text in bold blocky letters, perfectly spelled and fully legible."),
    ("B", "Gradiente líquido", "Fundo de gradiente fluido e orgânico", "Baixo", "Ambos",
     "Complete redesign with a fluid gradient style: smooth liquid color mesh and organic blobs flowing behind the main subject, vibrant but harmonious palette, soft glow where the colors meet. Text clean, in white or dark, for maximum contrast."),
    ("B", "Retrô anos 80", "Pôr do sol synthwave com grade neon", "Médio", "Ambos",
     "Complete redesign in a retro 80s synthwave style: purple-to-orange sunset sky, glowing grid floor in perspective, chrome highlights, the main subject placed on the horizon. Text in bold retro letters with a subtle chrome or glow effect, fully legible."),
    ("B", "Pop art", "Retícula, contorno preto e cores primárias", "Alto", "Ambos",
     "Complete redesign in a pop-art style: halftone dot textures, bold black outlines, flat saturated primary colors, empty comic-style burst shapes behind the main subject with no words inside them. Text in heavy comic-style letters, perfectly spelled."),
    ("B", "Holográfico", "Fundo iridescente com brilho arco-íris", "Baixo", "Ambos",
     "Complete redesign with an iridescent holographic style: holographic foil background with a rainbow sheen, soft pastel reflections on the main subject, clean futuristic shapes. Text in crisp white or dark letters on a solid panel for legibility."),
    ("B", "Cinematográfico", "Cor de cinema, névoa, assunto como herói", "Médio", "Ambos",
     "Complete redesign with a cinematic look: moody teal-and-orange color grading, dramatic contrast and light fog, the main subject lit like the hero of a film poster. Text in a tall, elegant condensed typeface, with no credits block and no extra text."),
    # ---------------- C — Cenário (adaptativo) ----------------
    ("C", "Salão premium", "Salão de cassino elegante ou área VIP de estádio", "Baixo", "Ambos",
     "Complete redesign set in a premium venue that matches the reference: for a casino game, an elegant casino floor with blurred warm lights and gold details; for sports betting, a modern stadium lounge with glowing screens in the background showing no readable text. The main subject in front, sharp."),
    ("C", "Mesa de feltro ou gramado", "Assunto sobre feltro (cassino) ou gramado (bet)", "Baixo", "Ambos",
     "Complete redesign on a surface that matches the theme: for a casino game, a deep green or burgundy felt table under a warm overhead lamp; for sports betting, close-up stadium turf or court with painted lines. The main subject placed on it, seen from above at an angle."),
    ("C", "Arena à noite", "Estádio vazio sob refletores ou skyline noturno", "Médio", "Ambos",
     "Complete redesign with a night arena atmosphere: for sports betting, an empty stadium under bright floodlights; for a casino game, a glamorous night skyline full of colorful lights. The main subject in front, sharp; cinematic contrast; text over the darker sky area."),
    ("C", "Palco de revelação", "Palco vazio, holofotes e fumaça", "Baixo", "Ambos",
     "Complete redesign as a big reveal on stage: the main subject in the center of an empty stage under strong spotlights, with light beams and a little haze, dark venue around it. Exciting event atmosphere. Text above and below the subject."),
    ("C", "Cidade à noite", "Cidade noturna com bokeh e reflexos", "Médio", "Ambos",
     "Complete redesign with an urban night setting: the main subject in front of a city at night with colorful bokeh lights and a wet reflective street or rooftop, cinematic contrast. Text in clean bright letters over the darker sky."),
    ("C", "Fumaça e partículas", "Fumaça colorida e partículas de luz", "Baixo", "Ambos",
     "Complete redesign with an abstract atmospheric setting: the main subject surrounded by swirling colored smoke, floating light particles and soft sparks on a dark background, as if materializing. Text crisp and bright, where the background is calm."),
    ("C", "Estúdio infinito", "Foto de estúdio em fundo infinito colorido", "Baixo", "Ambos",
     "Complete redesign as a professional studio shot: the main subject in a seamless infinite studio (cyclorama) in a bold new color, perfect softbox lighting, crisp reflections and a soft floor shadow. Text arranged cleanly in the empty space."),
    ("C", "Lounge VIP", "Ambiente VIP escuro com couro e dourado", "Baixo", "Ambos",
     "Complete redesign in an exclusive VIP lounge with dark leather, gold trims, warm indirect lights and shallow depth of field, the main subject presented as the star of the room: for a casino game, a private gaming room; for sports betting, a members lounge with team-neutral colors."),
    ("C", "Campo gráfico", "Campo/quadra estilizado ou padrão do próprio jogo", "Baixo", "Ambos",
     "Complete redesign with a graphic field: for sports betting, a stylized top-down pitch or court with glowing lines; for a casino game, a subtle repeating pattern built from the shapes and colors of the reference's own game. The main subject large on top."),
    ("C", "Universo do próprio jogo", "Expande cores, símbolos e texturas da referência", "Baixo", "Ambos",
     "Complete redesign that expands the reference's own visual world: take the colors, symbols, characters or textures already present in the reference and build an immersive full-canvas scene around the main subject, bigger, deeper and more layered, without bringing in elements from other games or sports."),
    # ---------------- D — Luz e cor ----------------
    ("D", "Clima oposto", "Inverte o clima: quente↔frio, escuro↔claro", "Baixo", "Ambos",
     "Complete redesign using the opposite mood of the reference: if it is warm, make it cool; if dark, make it bright; if very colorful, make it restrained. New background, new accent colors, matching new lighting on the main subject and a rearranged layout."),
    ("D", "Monocromático + destaque", "Uma cor em vários tons + 1 destaque", "Baixo", "Ambos",
     "Complete redesign with a monochrome palette (one hue in many tones) for the background and graphic elements, and a single strong contrasting accent color on the most important text line. The main subject keeps its real colors. New layout."),
    ("D", "Duotone", "Fundo e grafismos em duas cores fortes", "Baixo", "Ambos",
     "Complete redesign with a bold duotone treatment on the background and graphic elements (two strong colors only, such as blue and pink or green and purple), while the main subject keeps its real colors and stands out. Graphic, poster-like."),
    ("D", "Luz dramática", "Fundo quase preto, luz de recorte", "Baixo", "Ambos",
     "Complete redesign with dramatic low-key lighting: almost black background, a strong rim light outlining the main subject, one beam of light, deep shadows and high contrast. Text in bright, sharp letters. Intense and premium."),
    ("D", "Claro e arejado", "Tudo claro, branco e pastel", "Baixo", "Ambos",
     "Complete redesign with high-key lighting: very bright, airy and clean, white and soft pastel tones, minimal shadows, fresh feel. The main subject sharp and colorful against the light background. Text in strong dark colors for contrast."),
    ("D", "Luz em duas cores", "Luz colorida de cada lado", "Baixo", "Ambos",
     "Complete redesign with dual-color gel lighting: the main subject lit from one side with a saturated color and from the other with a contrasting color, on a dark seamless background with glossy highlights. Bold music-video look. Text clean and white."),
    ("D", "Ultra vibrante", "Cores elétricas e saturadas", "Baixo", "Ambos",
     "Complete redesign with an ultra-vibrant, saturated palette: electric colors, strong gradients and glossy highlights, a background full of color but organized, the main subject popping with a bright outline glow. Text with strong contrast."),
    ("D", "Brilho âmbar", "Luz quente âmbar e champanhe com bokeh", "Baixo", "Ambos",
     "Complete redesign bathed in warm amber and champagne light: glowing golden bokeh in the background, soft warm highlights on the main subject, deep soft shadows, a luxurious evening mood. Text in clean light letters over a darker area."),
    # ---------------- E — Tipografia e oferta ----------------
    ("E", "Etiquetas por linha", "Cada linha numa etiqueta/fita colorida", "Médio", "Ambos",
     "Complete redesign where each line of text sits on its own colored sticker or ribbon shape, stacked and slightly tilted in alternating directions, with the main subject large next to them. New background and palette."),
    ("E", "Título 3D", "Título em letras 3D extrudadas", "Alto", "Ambos",
     "Complete redesign with the headline in big 3D extruded letters (thick depth, glossy material, strong light) and the rest of the text in clean flat letters. The main subject below or beside the headline. Simple background so the 3D type stands out. Spelling must stay perfect."),
    ("E", "Título de impacto", "Caixa-alta condensada, contorno e sombra", "Médio", "Ambos",
     "Complete redesign with high-impact typography: the headline in heavy condensed capitals with a thick contrasting outline and a hard drop shadow, slightly tilted; the main subject large beside it without covering any letter. Bold, punchy background."),
    ("E", "Oferta como herói", "A linha da oferta vira o centro da peça", "Médio", "Ambos",
     "Complete redesign where the offer line that is already in the text (the bonus, the odds or the main benefit, exactly as written) becomes the visual hero: set large inside a bold shape such as a ticket, ribbon or glowing pill at the center, with the main subject around it. Every number exactly as given."),
    ("E", "Letreiro luminoso", "Título em letreiro de lâmpadas ou painel de LED", "Alto", "Ambos",
     "Complete redesign with the headline on an illuminated sign: for a casino game, a vintage marquee with small light bulbs around its border; for sports betting, a clean stadium LED panel. Letters clean and fully legible, showing only the given text. The main subject below the sign."),
    # ---------------- F — Ângulo e energia ----------------
    ("F", "Ação e velocidade", "Rastros de velocidade, diagonal forte", "Médio", "Ambos",
     "Complete redesign with dynamic action: speed streaks, motion blur and an energy burst behind the main subject, as if it is bursting toward the viewer, with a strong diagonal composition. Text in bold italic letters along the diagonal, fully legible."),
    ("F", "Momento congelado", "Câmera lenta com partículas suspensas", "Baixo", "Ambos",
     "Complete redesign as a frozen high-speed moment: the main subject captured mid-motion with light trails, sparks and small fragments suspended in the air around it, ultra-sharp detail on a dark background. Text in a clean block at the top."),
    ("F", "Vista de cima", "Flat lay: tudo visto de cima", "Baixo", "Ambos",
     "Complete redesign as a top-down flat lay: the main subject seen from directly above on a textured surface that matches the theme (felt for a casino game, turf or court for sports betting), with elements already in the reference arranged neatly around it. Text on a solid band."),
    ("F", "Ângulo monumental", "Câmera baixa grande-angular, assunto gigante", "Baixo", "Ambos",
     "Complete redesign with a dramatic low-angle, wide-lens view that makes the main subject look monumental, strong perspective lines leading to it and a deep sky or ceiling behind it. Text in a tight block at the top."),
    ("F", "Painéis múltiplos", "Tela dividida em painéis com recortes do assunto", "Médio", "Ambos",
     "Complete redesign as a split screen: the canvas divided into two or three vertical panels, each showing a different crop of the same main subject (wide view, detail, glow), with all the text on one solid band across the panels."),
]

GAME_NAMES = r"aviator|fortune|tiger|tigrinho|mines|spaceman|plinko|crash|blaze|bet365|betano|pixbet|sportingbet|stake|esportes da sorte|superbet|kto|betnacional|f12|estrela ?bet"
PROMISE = r"jackpot|\bwin\b|\bwins\b|winner|winning|money|cash|\bcoins?\b|prize|payout|\brich\b|guarantee|free|easy|profit|income"
CHILD = r"cartoon|toy|kid|child|school"


def interleave(axes):
    """Ordena os eixos alternando as famílias para que cada bloco de 4 eixos seguidos — usado num
    mesmo criativo pelo rodízio — tenha direções bem diferentes. Guloso: escolhe sempre a família com
    mais eixos restantes que não apareceu nos 3 últimos (mantendo a ordem interna de cada família)."""
    buckets = {f: [a for a in axes if a[0] == f] for f in FAM}
    order = []
    while any(buckets.values()):
        recent = [a[0] for a in order[-3:]]
        candidates = [f for f in FAM if buckets[f] and f not in recent]
        if not candidates:
            candidates = [f for f in FAM if buckets[f] and (not order or f != order[-1][0])] or [f for f in FAM if buckets[f]]
        f = max(candidates, key=lambda f: (len(buckets[f]), -list(FAM).index(f)))
        order.append(buckets[f].pop(0))
    return order


def validate(axes):
    errors = []
    if len(axes) != 50:
        errors.append(f"esperado 50 eixos, há {len(axes)}")
    names = [a[1] for a in axes]
    if len(set(names)) != len(names):
        errors.append("nomes repetidos: " + str([n for n, c in Counter(names).items() if c > 1]))
    insts = [a[5] for a in axes]
    if len(set(insts)) != len(insts):
        errors.append("instruções repetidas")
    for fam, name, muda, risco, serve, inst in axes:
        tag = f"[{name}]"
        if fam not in FAM: errors.append(f"{tag} família inválida")
        if risco not in ("Baixo", "Médio", "Alto"): errors.append(f"{tag} risco inválido")
        if serve not in ("Ambos",): errors.append(f"{tag} 'serve para' inválido")
        if not inst.startswith("Complete redesign"): errors.append(f"{tag} não começa com 'Complete redesign'")
        if "main subject" not in inst: errors.append(f"{tag} não fala do assunto principal")
        for label, pat in (("nome de jogo/marca", GAME_NAMES), ("promessa/dinheiro", PROMISE), ("público infantil", CHILD)):
            m = re.search(pat, inst, re.I)
            if m: errors.append(f"{tag} {label}: '{m.group(0)}'")
        if '"' in inst or "\\" in inst: errors.append(f"{tag} aspas/barra na instrução")
        words = len(inst.split())
        if not 25 <= words <= 75: errors.append(f"{tag} {words} palavras (fora de 25–75)")
    # eixos de cenário precisam se adaptar a cassino E bet esportiva, ou usar só o que já está na referência
    for fam, name, *_rest in axes:
        inst = _rest[-1]
        if fam == "C" and not (("casino" in inst and "sports betting" in inst) or "reference" in inst or "empty stage" in inst
                               or "city at night" in inst or "smoke" in inst or "studio" in inst):
            errors.append(f"[{name}] cenário não adaptativo")
    return errors


def swift_string(s):
    return s.replace("\\", "\\\\").replace('"', '\\"')


def gen_swift(axes):
    lines = [
        "import Foundation",
        "",
        "// ARQUIVO GERADO por scripts/eixos_variacao.py — não edite à mão (docs/EIXOS-DE-VARIACAO.md é gerado junto).",
        "// 1.0.0-beta.14: 50 eixos de variação feitos para criativos de CASSINO e BET (apostas esportivas).",
        "// Ordem alternando famílias: com o rodízio, cada criativo recebe eixos seguidos de famílias diferentes.",
        "// As regras de coerência (mesmo jogo/esporte, texto exato, sem promessa nova, avisos 18+) ficam no",
        "// prompt-base (`Prompts.variation` + `Niche`), então valem também para eixos que o usuário escrever.",
        "extension ClientProfile {",
        "    static let defaultAxes: [VariationAxis] = [",
    ]
    for i, (fam, name, muda, risco, serve, inst) in enumerate(axes, 1):
        lines.append(f"        // {i}. {FAM[fam]} · risco de texto: {risco}")
        lines.append(f'        VariationAxis(name: "{swift_string(name)}",')
        lines.append(f'                      instruction: "{swift_string(inst)}"),')
    lines += ["    ]", "}", ""]
    return "\n".join(lines)


def gen_md(axes):
    out = []
    w = out.append
    w("# Eixos de variação — cassino e bet (50 eixos padrão)")
    w("")
    w("> O IMP Criativos é feito **somente para criativos de cassino online e apostas esportivas (bet)**. "
      "Estes são os eixos padrão desde a **1.0.0-beta.14**. Fonte única: `scripts/eixos_variacao.py`, que gera este arquivo e `Models/DefaultAxes.swift`.")
    w("")
    w("## Como funcionam")
    w("")
    w("- **Eixo = direção de arte completa de uma variação**: layout, fundo, estilo, luz e tratamento do texto. "
      "Todos começam com *Complete redesign*: a referência entra como briefing de conteúdo, não como molde.")
    w("- **Rodízio entre criativos**: com 4 variações, o 1º criativo usa os eixos 1–4, o 2º usa 5–8, e assim por diante; "
      "no fim da lista, recomeça. A lista alterna famílias, então cada criativo recebe 4 direções bem diferentes.")
    w("- **Coerência garantida pelo app, não pelo eixo**: o prompt-base de toda variação (`Prompts.variation` + `Niche`) exige "
      "o mesmo jogo ou esporte, a mesma oferta, o texto exato, os avisos 18+ e de jogo responsável, e proíbe adicionar palavras, "
      "números, odds, multiplicadores, valores, bônus, dinheiro, pessoas, logos, selos ou promessa de ganho. "
      "Se um eixo não combinar com o tema (ex.: cenário de cassino num criativo de bet esportiva), a IA adapta ao tema da referência.")
    w("- **Cenários adaptativos**: os eixos de cenário têm as duas versões (\"para cassino… / para bet esportiva…\").")
    w("- **Sem nomes de jogos ou casas de aposta** e sem palavras de promessa nas instruções (validado por script).")
    w("- **Risco de texto**: chance de a IA errar a grafia ao reestilizar as letras. Baixo = texto em blocos limpos; "
      "Alto = letras 3D, quadrinhos, letreiro. Os de risco alto saem mais diferentes, mas geram mais aviso de texto e refação.")
    w("- **Personalizar**: em Clientes → Eixos de variação dá para editar, reordenar, apagar ou escrever eixos. "
      "O botão \"Usar os 50 eixos padrão\" traz esta lista de volta.")
    w("")
    fam_count = Counter(FAM[a[0]] for a in axes)
    risk_count = Counter(a[3] for a in axes)
    w("| Família | Eixos |")
    w("|---|---|")
    for f in FAM.values():
        w(f"| {f} | {fam_count.get(f, 0)} |")
    w("")
    w(f"Risco de texto: Baixo {risk_count.get('Baixo',0)} · Médio {risk_count.get('Médio',0)} · Alto {risk_count.get('Alto',0)}")
    w("")
    w("## Lista (na ordem de uso)")
    w("")
    w("| # | Nome | Família | O que muda | Risco de texto |")
    w("|---|---|---|---|---|")
    for i, (fam, name, muda, risco, serve, inst) in enumerate(axes, 1):
        w(f"| {i} | {name} | {FAM[fam]} | {muda} | {risco} |")
    w("")
    w("## Instruções (copiar e colar)")
    for i, (fam, name, muda, risco, serve, inst) in enumerate(axes, 1):
        w("")
        w(f"**{i}. {name}** · {FAM[fam]} · risco de texto: {risco}")
        w("")
        w("```")
        w(inst)
        w("```")
    w("")
    w("## Kits para quem prefere sempre os mesmos 4 eixos")
    w("")
    w("Deixe na lista do cliente só estes 4 (o rodízio fica igual para todos os criativos).")
    w("")
    idx = {a[1]: i for i, a in enumerate(axes, 1)}
    kits = [
        ("Bem diferentes", ["Destaque em close", "Neon noturno", "Claro e arejado", "Colagem recortada"]),
        ("Premium", ["Preto e dourado", "Editorial assimétrico", "Lounge VIP", "Monocromático + destaque"]),
        ("Seguro para o texto", ["Cartão flutuante", "3D premium", "Clima oposto", "Palco de revelação"]),
        ("Cassino", ["Mesa de feltro ou gramado", "Universo do próprio jogo", "Letreiro luminoso", "Brilho âmbar"]),
        ("Bet esportiva", ["Arena à noite", "Campo gráfico", "Ação e velocidade", "Ângulo monumental"]),
    ]
    w("| Kit | Eixos |")
    w("|---|---|")
    for k, members in kits:
        for m in members:
            assert m in idx, m
        w(f"| **{k}** | " + " · ".join(f"{idx[m]}. {m}" for m in members) + " |")
    w("")
    return "\n".join(out)


if __name__ == "__main__":
    root = sys.argv[1]
    errs = validate(AXES)
    if errs:
        print("ERROS:\n" + "\n".join(errs)); sys.exit(1)
    ordered = interleave(AXES)
    assert len(ordered) == 50 and set(a[1] for a in ordered) == set(a[1] for a in AXES)
    # cada bloco de 4 seguidos (como o rodízio usa) deve ter pelo menos 3 famílias diferentes
    worst = min(len({ordered[(s + k) % 50][0] for k in range(4)}) for s in range(50))
    print(f"famílias distintas no pior bloco de 4 seguidos: {worst}")
    if worst < 3:
        print("ERRO: ordem com blocos pouco variados"); sys.exit(1)
    open(f"{root}/Sources/IMPCriativos/Models/DefaultAxes.swift", "w", encoding="utf-8").write(gen_swift(ordered))
    open(f"{root}/docs/EIXOS-DE-VARIACAO.md", "w", encoding="utf-8").write(gen_md(ordered))
    words = [len(a[5].split()) for a in AXES]
    print(f"OK: {len(AXES)} eixos · {dict(Counter(FAM[a[0]] for a in AXES))}")
    print(f"risco: {dict(Counter(a[3] for a in AXES))} · palavras: {min(words)}–{max(words)}")
