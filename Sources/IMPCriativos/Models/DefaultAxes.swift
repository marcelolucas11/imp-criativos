import Foundation

// ARQUIVO GERADO por scripts/eixos_variacao.py — não edite à mão (docs/EIXOS-DE-VARIACAO.md é gerado junto).
// 1.0.0-beta.15: 50 eixos de variação para criativos de CASSINO ONLINE e BET (apostas esportivas), sem cassino físico.
// Ordem alternando famílias: com o rodízio, cada criativo recebe eixos seguidos de famílias diferentes.
// As regras de coerência (mesmo jogo/esporte, texto exato, sem promessa nova, avisos 18+) ficam no
// prompt-base (`Prompts.variation` + `Niche`), então valem também para eixos que o usuário escrever.
extension ClientProfile {
    static let defaultAxes: [VariationAxis] = [
        // 1. Estilo gráfico · risco de texto: Baixo
        VariationAxis(name: "3D premium",
                      instruction: "Complete redesign in a premium 3D render style: glossy 3D geometric shapes (spheres, rings, pills) floating around the main subject, studio lighting with soft reflections, smooth gradient backdrop in a new palette. Text clean, bold and flat for perfect legibility."),
        // 2. Layout · risco de texto: Baixo
        VariationAxis(name: "Destaque em close",
                      instruction: "Complete redesign, not a retouch: a dramatic close-up of the main subject fills about two-thirds of the canvas, boldly cropped at one edge. All the text grouped in one compact, high-contrast block at the top, on a solid color band. New background and palette."),
        // 3. Cenário (cassino online ou bet) · risco de texto: Médio
        VariationAxis(name: "Arena à noite",
                      instruction: "Complete redesign with a night arena atmosphere: for sports betting, an empty stadium under bright floodlights; for an online casino game, the game's own world at night, glowing in its own colors. The main subject in front, sharp; cinematic contrast; text over the darker sky area."),
        // 4. Luz e cor · risco de texto: Baixo
        VariationAxis(name: "Clima oposto",
                      instruction: "Complete redesign using the opposite mood of the reference: if it is warm, make it cool; if dark, make it bright; if very colorful, make it restrained. New background, new accent colors, matching new lighting on the main subject and a rearranged layout."),
        // 5. Estilo gráfico · risco de texto: Médio
        VariationAxis(name: "Neon noturno",
                      instruction: "Complete redesign with a night neon aesthetic: dark background, glowing neon tubes and light lines framing the main subject, colored rim light (magenta, cyan or purple) on it, light haze. Text in bright, sharp letters with a subtle glow, fully legible."),
        // 6. Layout · risco de texto: Médio
        VariationAxis(name: "Diagonal dividida",
                      instruction: "Complete redesign: split the canvas with a strong diagonal into two contrasting color fields. The main subject large on one side, slightly breaking over the diagonal line; the text block on the other side, left-aligned. Clean modern shapes, crisp light."),
        // 7. Cenário (cassino online ou bet) · risco de texto: Baixo
        VariationAxis(name: "Palco de revelação",
                      instruction: "Complete redesign as a big reveal on stage: the main subject in the center of an empty stage under strong spotlights, with light beams and a little haze, dark venue around it. Exciting event atmosphere. Text above and below the subject."),
        // 8. Luz e cor · risco de texto: Baixo
        VariationAxis(name: "Monocromático + destaque",
                      instruction: "Complete redesign with a monochrome palette (one hue in many tones) for the background and graphic elements, and a single strong contrasting accent color on the most important text line. The main subject keeps its real colors. New layout."),
        // 9. Estilo gráfico · risco de texto: Baixo
        VariationAxis(name: "Preto e dourado",
                      instruction: "Complete redesign in a black-and-gold luxury style: deep black or dark marble background, fine gold lines and metallic accents, warm elegant light on the main subject. Text in refined gold or white letters. Sophisticated and minimal."),
        // 10. Layout · risco de texto: Baixo
        VariationAxis(name: "Faixa central",
                      instruction: "Complete redesign: a bold full-width horizontal band crosses the middle of the canvas and carries the headline; the main subject sits above the band, partly overlapping it, and the rest of the text sits below. Punchy solid background in a new color."),
        // 11. Cenário (cassino online ou bet) · risco de texto: Baixo
        VariationAxis(name: "Fumaça e partículas",
                      instruction: "Complete redesign with an abstract atmospheric setting: the main subject surrounded by swirling colored smoke, floating light particles and soft sparks on a dark background, as if materializing. Text crisp and bright, where the background is calm."),
        // 12. Luz e cor · risco de texto: Baixo
        VariationAxis(name: "Duotone",
                      instruction: "Complete redesign with a bold duotone treatment on the background and graphic elements (two strong colors only, such as blue and pink or green and purple), while the main subject keeps its real colors and stands out. Graphic, poster-like."),
        // 13. Estilo gráfico · risco de texto: Baixo
        VariationAxis(name: "Minimalista premium",
                      instruction: "Complete redesign in a minimalist premium-tech style: lots of empty space in a light or deep single tone, the main subject centered with a soft natural shadow, one accent color. Text perfectly aligned with elegant spacing. Calm and high-end."),
        // 14. Layout · risco de texto: Médio
        VariationAxis(name: "Pôster tipográfico",
                      instruction: "Complete redesign as a typographic poster: the headline (the most prominent text line) set in very large heavy letters across the top 40% of the canvas, every letter fully visible. The main subject below, smaller and centered, with the rest of the text beneath it. Minimal background, one strong accent color."),
        // 15. Cenário (cassino online ou bet) · risco de texto: Baixo
        VariationAxis(name: "Estúdio infinito",
                      instruction: "Complete redesign as a professional studio shot: the main subject in a seamless infinite studio (cyclorama) in a bold new color, perfect softbox lighting, crisp reflections and a soft floor shadow. Text arranged cleanly in the empty space."),
        // 16. Luz e cor · risco de texto: Baixo
        VariationAxis(name: "Luz dramática",
                      instruction: "Complete redesign with dramatic low-key lighting: almost black background, a strong rim light outlining the main subject, one beam of light, deep shadows and high contrast. Text in bright, sharp letters. Intense and premium."),
        // 17. Estilo gráfico · risco de texto: Baixo
        VariationAxis(name: "Vidro fosco",
                      instruction: "Complete redesign in a glassmorphism style: colorful blurred gradient background with soft blobs of light, the text on frosted translucent glass panels with thin bright borders, the main subject in front in sharp focus. Modern and techy."),
        // 18. Layout · risco de texto: Baixo
        VariationAxis(name: "Cartão flutuante",
                      instruction: "Complete redesign: the main subject and all the text inside a large rounded card floating in the center with a soft shadow, over a contrasting gradient or textured background that fills the canvas. Modern, app-like look."),
        // 19. Cenário (cassino online ou bet) · risco de texto: Baixo
        VariationAxis(name: "Campo gráfico",
                      instruction: "Complete redesign with a graphic field: for sports betting, a stylized top-down pitch or court with glowing lines; for a casino game, a subtle repeating pattern built from the shapes and colors of the reference's own game. The main subject large on top."),
        // 20. Tipografia e oferta · risco de texto: Médio
        VariationAxis(name: "Etiquetas por linha",
                      instruction: "Complete redesign where each line of text sits on its own colored sticker or ribbon shape, stacked and slightly tilted in alternating directions, with the main subject large next to them. New background and palette."),
        // 21. Estilo gráfico · risco de texto: Médio
        VariationAxis(name: "Colagem recortada",
                      instruction: "Complete redesign as a cut-out collage: the main subject cut out with a thick white sticker outline, over layered torn-paper shapes and textured paper in bold colors, slightly tilted for energy. Text on paper strips or tape pieces, clearly legible."),
        // 22. Layout · risco de texto: Médio
        VariationAxis(name: "Tela em destaque",
                      instruction: "Complete redesign around the screen: if the reference shows a phone or a game screen, make that screen the hero, large and tilted in 3D perspective with a soft glow around it; if it does not, present the main subject inside a large glowing rounded frame. Text in a clean block above."),
        // 23. Cenário (cassino online ou bet) · risco de texto: Baixo
        VariationAxis(name: "Universo do próprio jogo",
                      instruction: "Complete redesign that expands the reference's own visual world: take the colors, symbols, characters or textures already present in the reference and build an immersive full-canvas scene around the main subject, bigger, deeper and more layered, without bringing in elements from other games or sports."),
        // 24. Luz e cor · risco de texto: Baixo
        VariationAxis(name: "Claro e arejado",
                      instruction: "Complete redesign with high-key lighting: very bright, airy and clean, white and soft pastel tones, minimal shadows, fresh feel. The main subject sharp and colorful against the light background. Text in strong dark colors for contrast."),
        // 25. Estilo gráfico · risco de texto: Médio
        VariationAxis(name: "Arcade retrô",
                      instruction: "Complete redesign in a retro arcade style: pixel-art borders and shapes, subtle scanlines and glowing screen colors around the main subject, which keeps its own look (photo or polished 3D render), on a dark background. Text in bold blocky letters, perfectly spelled and fully legible."),
        // 26. Layout · risco de texto: Médio
        VariationAxis(name: "Editorial assimétrico",
                      instruction: "Complete redesign with an editorial, asymmetric layout: the main subject off-center on the right, generous empty space on the left holding the text, left-aligned with a strong size hierarchy. Sophisticated background with one thin accent line."),
        // 27. Tipografia e oferta · risco de texto: Alto
        VariationAxis(name: "Título 3D",
                      instruction: "Complete redesign with the headline in big 3D extruded letters (thick depth, glossy material, strong light) and the rest of the text in clean flat letters. The main subject below or beside the headline. Simple background so the 3D type stands out. Spelling must stay perfect."),
        // 28. Ângulo e energia · risco de texto: Médio
        VariationAxis(name: "Ação e velocidade",
                      instruction: "Complete redesign with dynamic action: speed streaks, motion blur and an energy burst behind the main subject, as if it is bursting toward the viewer, with a strong diagonal composition. Text in bold italic letters along the diagonal, fully legible."),
        // 29. Estilo gráfico · risco de texto: Baixo
        VariationAxis(name: "Gradiente líquido",
                      instruction: "Complete redesign with a fluid gradient style: smooth liquid color mesh and organic blobs flowing behind the main subject, vibrant but harmonious palette, soft glow where the colors meet. Text clean, in white or dark, for maximum contrast."),
        // 30. Layout · risco de texto: Baixo
        VariationAxis(name: "Halo circular",
                      instruction: "Complete redesign: a large glowing circle or ring behind the main subject frames it in the center like a halo; the text arranged above and below the circle. Bold two-tone background, clean geometric look."),
        // 31. Cenário (cassino online ou bet) · risco de texto: Baixo
        VariationAxis(name: "Ambiente de app premium",
                      instruction: "Complete redesign in the glossy look of a premium mobile gaming app: deep gradient background (purple, navy or emerald with gold accents), glowing light streaks and soft colored bokeh, the main subject in front, sharp and lit like a hero. For sports betting, add subtle glowing pitch lines."),
        // 32. Luz e cor · risco de texto: Baixo
        VariationAxis(name: "Luz em duas cores",
                      instruction: "Complete redesign with dual-color gel lighting: the main subject lit from one side with a saturated color and from the other with a contrasting color, on a dark seamless background with glossy highlights. Bold music-video look. Text clean and white."),
        // 33. Estilo gráfico · risco de texto: Alto
        VariationAxis(name: "Pop art",
                      instruction: "Complete redesign in a pop-art style: halftone dot textures, bold black outlines, flat saturated primary colors, empty comic-style burst shapes behind the main subject with no words inside them. Text in heavy comic-style letters, perfectly spelled."),
        // 34. Tipografia e oferta · risco de texto: Médio
        VariationAxis(name: "Título de impacto",
                      instruction: "Complete redesign with high-impact typography: the headline in heavy condensed capitals with a thick contrasting outline and a hard drop shadow, slightly tilted; the main subject large beside it without covering any letter. Bold, punchy background."),
        // 35. Ângulo e energia · risco de texto: Baixo
        VariationAxis(name: "Momento congelado",
                      instruction: "Complete redesign as a frozen high-speed moment: the main subject captured mid-motion with light trails, sparks and small fragments suspended in the air around it, ultra-sharp detail on a dark background. Text in a clean block at the top."),
        // 36. Personagem e jogo · risco de texto: Baixo
        VariationAxis(name: "Personagem em nova pose",
                      instruction: "Complete redesign around the character: if the reference has a 3D character or mascot, show the very same character (identical design, colors, outfit, accessories and render style) in a new dynamic pose and camera angle, larger and closer, over a new background; if it has none, show the main subject from a bold new angle."),
        // 37. Layout · risco de texto: Médio
        VariationAxis(name: "Leitura em Z",
                      instruction: "Complete redesign with a Z-shaped reading path: the first part of the text at the top-left, the main subject large in the center-right, the remaining text at the bottom-left. Energetic background with motion lines or soft speed blur."),
        // 38. Estilo gráfico · risco de texto: Baixo
        VariationAxis(name: "Holográfico",
                      instruction: "Complete redesign with an iridescent holographic style: holographic foil background with a rainbow sheen, soft pastel reflections on the main subject, clean futuristic shapes. Text in crisp white or dark letters on a solid panel for legibility."),
        // 39. Cenário (cassino online ou bet) · risco de texto: Baixo
        VariationAxis(name: "Superfície do jogo",
                      instruction: "Complete redesign where the main subject stands on a glossy 3D platform built from its own game: for an online casino game, its reels, grid, wheel or board turned into a shiny surface in perspective; for sports betting, a stylized pitch or court. Clean background, strong depth."),
        // 40. Luz e cor · risco de texto: Baixo
        VariationAxis(name: "Ultra vibrante",
                      instruction: "Complete redesign with an ultra-vibrant, saturated palette: electric colors, strong gradients and glossy highlights, a background full of color but organized, the main subject popping with a bright outline glow. Text with strong contrast."),
        // 41. Tipografia e oferta · risco de texto: Médio
        VariationAxis(name: "Oferta como herói",
                      instruction: "Complete redesign where the offer line that is already in the text (the bonus, the odds or the main benefit, exactly as written) becomes the visual hero: set large inside a bold shape such as a ticket, ribbon or glowing pill at the center, with the main subject around it. Every number exactly as given."),
        // 42. Ângulo e energia · risco de texto: Baixo
        VariationAxis(name: "Ângulo monumental",
                      instruction: "Complete redesign with a dramatic low-angle, wide-lens view that makes the main subject look monumental, strong perspective lines leading to it and a deep sky or ceiling behind it. Text in a tight block at the top."),
        // 43. Personagem e jogo · risco de texto: Médio
        VariationAxis(name: "Saindo da tela do celular",
                      instruction: "Complete redesign with the main subject (the 3D character, the game symbols or the athlete) bursting out of a modern smartphone screen in 3D, breaking the frame toward the viewer, the phone tilted in perspective and its screen showing only the game's own visuals with no readable text. Text in a clean block above."),
        // 44. Layout · risco de texto: Baixo
        VariationAxis(name: "Simetria central",
                      instruction: "Complete redesign with a perfectly symmetrical vertical composition: the main subject centered in the middle third, mirrored light shapes on both sides, the text centered above and below in a strict hierarchy. Elegant and balanced."),
        // 45. Estilo gráfico · risco de texto: Médio
        VariationAxis(name: "Cinematográfico",
                      instruction: "Complete redesign with a cinematic look: moody teal-and-orange color grading, dramatic contrast and light fog, the main subject lit like the hero of a film poster. Text in a tall, elegant condensed typeface, with no credits block and no extra text."),
        // 46. Cenário (cassino online ou bet) · risco de texto: Baixo
        VariationAxis(name: "Cenário temático do jogo",
                      instruction: "Complete redesign set in the world that the reference's own theme suggests (for example an oriental temple for an oriental-themed game, open sky for a flight game, a sweets landscape for a candy-themed game), built only from the theme already visible in the reference and rendered as a detailed 3D environment around the main subject. For sports betting, the sport's own arena."),
        // 47. Luz e cor · risco de texto: Baixo
        VariationAxis(name: "Brilho âmbar",
                      instruction: "Complete redesign bathed in warm amber and champagne light: glowing golden bokeh in the background, soft warm highlights on the main subject, deep soft shadows, a luxurious evening mood. Text in clean light letters over a darker area."),
        // 48. Tipografia e oferta · risco de texto: Alto
        VariationAxis(name: "Placa de título de jogo",
                      instruction: "Complete redesign with the headline on a 3D title plaque in the style of an online game title: beveled, glossy, with metallic or gem trim and a soft glow, showing only the given text, fully legible. For sports betting, a sleek broadcast-style graphic bar. The main subject below the plaque."),
        // 49. Ângulo e energia · risco de texto: Médio
        VariationAxis(name: "Painéis múltiplos",
                      instruction: "Complete redesign as a split screen: the canvas divided into two or three vertical panels, each showing a different crop of the same main subject (wide view, detail, glow), with all the text on one solid band across the panels."),
        // 50. Personagem e jogo · risco de texto: Baixo
        VariationAxis(name: "Símbolos do jogo em 3D",
                      instruction: "Complete redesign with the reference's own game elements (only symbols, gems, cards, balls or icons already in the reference) floating around the main subject as glossy 3D objects at different depths, with depth of field and a soft glow. Deep-colored background, text in a clean block."),
    ]
}
