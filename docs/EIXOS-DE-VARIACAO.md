# Eixos de variação — cassino e bet (50 eixos padrão)

> O IMP Criativos é feito **somente para criativos de cassino online e apostas esportivas (bet)**. Cassino é sempre online (jogos de celular, personagens e símbolos 3D), nunca cassino físico. Estes são os eixos padrão desde a **1.0.0-beta.15** (filtro de cassino online). Fonte única: `scripts/eixos_variacao.py`, que gera este arquivo e `Models/DefaultAxes.swift`.

## Como funcionam

- **Eixo = direção de arte completa de uma variação**: layout, fundo, estilo, luz e tratamento do texto. Todos começam com *Complete redesign*: a referência entra como briefing de conteúdo, não como molde.
- **Rodízio entre criativos**: com 4 variações, o 1º criativo usa os eixos 1–4, o 2º usa 5–8, e assim por diante; no fim da lista, recomeça. A lista alterna famílias, então cada criativo recebe 4 direções bem diferentes.
- **Coerência garantida pelo app, não pelo eixo**: o prompt-base de toda variação (`Prompts.variation` + `Niche`) exige o mesmo jogo ou esporte, a mesma oferta, o texto exato, os avisos 18+ e de jogo responsável, e proíbe adicionar palavras, números, odds, multiplicadores, valores, bônus, dinheiro, pessoas, logos, selos ou promessa de ganho. Se um eixo não combinar com o tema (ex.: cenário de cassino num criativo de bet esportiva), a IA adapta ao tema da referência.
- **Cenários adaptativos**: os eixos de cenário têm as duas versões ("para cassino online… / para bet esportiva…"). Nenhum leva para cassino físico (salão, máquinas, mesas de feltro, Las Vegas): o script recusa esses termos.
- **Personagens 3D** (mascotes dos jogos online): o prompt-base (`Niche.characterRules`) mantém o mesmo personagem em todas as variações — mesmo desenho, cores, roupa, acessórios e acabamento 3D —, mudando só pose, expressão e ângulo quando o eixo pede. Nunca adiciona outro personagem nem deixa o personagem mais infantil. A família *Personagem e jogo* foi feita para esses criativos.
- **Avisos obrigatórios** (Portaria SPA/MF 1.964/2026, desde 17/07/2026): a advertência "Ministério da Fazenda adverte: …" fica horizontal, legível e com pelo menos 10% da área; o 18+ e o "Jogue com responsabilidade" também ficam. Por isso nenhum eixo pede para encolher o texto.
- **Sem nomes de jogos ou casas de aposta** e sem palavras de promessa nas instruções (validado por script).
- **Risco de texto**: chance de a IA errar a grafia ao reestilizar as letras. Baixo = texto em blocos limpos; Alto = letras 3D, quadrinhos, placa de título de jogo. Os de risco alto saem mais diferentes, mas geram mais aviso de texto e refação.
- **Personalizar**: em Clientes → Eixos de variação dá para editar, reordenar, apagar ou escrever eixos. O botão "Usar os 50 eixos padrão" traz esta lista de volta.

| Família | Eixos |
|---|---|
| Layout | 10 |
| Estilo gráfico | 11 |
| Cenário (cassino online ou bet) | 9 |
| Luz e cor | 8 |
| Tipografia e oferta | 5 |
| Ângulo e energia | 4 |
| Personagem e jogo | 3 |

Risco de texto: Baixo 31 · Médio 16 · Alto 3

## Lista (na ordem de uso)

| # | Nome | Família | O que muda | Risco de texto |
|---|---|---|---|---|
| 1 | 3D premium | Estilo gráfico | Formas 3D brilhantes flutuando | Baixo |
| 2 | Destaque em close | Layout | Close gigante do assunto + faixa de texto | Baixo |
| 3 | Arena à noite | Cenário (cassino online ou bet) | Estádio vazio (bet) ou o mundo do jogo à noite (cassino) | Médio |
| 4 | Clima oposto | Luz e cor | Inverte o clima: quente↔frio, escuro↔claro | Baixo |
| 5 | Neon noturno | Estilo gráfico | Fundo escuro com tubos e linhas de neon | Médio |
| 6 | Diagonal dividida | Layout | Tela cortada na diagonal em 2 cores | Médio |
| 7 | Palco de revelação | Cenário (cassino online ou bet) | Palco vazio, holofotes e fumaça | Baixo |
| 8 | Monocromático + destaque | Luz e cor | Uma cor em vários tons + 1 destaque | Baixo |
| 9 | Preto e dourado | Estilo gráfico | Luxo: preto, mármore e filetes dourados | Baixo |
| 10 | Faixa central | Layout | Faixa larga no meio com o título | Baixo |
| 11 | Fumaça e partículas | Cenário (cassino online ou bet) | Fumaça colorida e partículas de luz | Baixo |
| 12 | Duotone | Luz e cor | Fundo e grafismos em duas cores fortes | Baixo |
| 13 | Minimalista premium | Estilo gráfico | Muito espaço vazio, 1 cor de destaque | Baixo |
| 14 | Pôster tipográfico | Layout | Título enorme vira o protagonista | Médio |
| 15 | Estúdio infinito | Cenário (cassino online ou bet) | Foto de estúdio em fundo infinito colorido | Baixo |
| 16 | Luz dramática | Luz e cor | Fundo quase preto, luz de recorte | Baixo |
| 17 | Vidro fosco | Estilo gráfico | Painéis de vidro translúcido | Baixo |
| 18 | Cartão flutuante | Layout | Tudo dentro de um card sobre fundo novo | Baixo |
| 19 | Campo gráfico | Cenário (cassino online ou bet) | Campo/quadra estilizado ou padrão do próprio jogo | Baixo |
| 20 | Etiquetas por linha | Tipografia e oferta | Cada linha numa etiqueta/fita colorida | Médio |
| 21 | Colagem recortada | Estilo gráfico | Recorte com borda de adesivo e papel rasgado | Médio |
| 22 | Tela em destaque | Layout | Tela do jogo/app em 3D, inclinada | Médio |
| 23 | Universo do próprio jogo | Cenário (cassino online ou bet) | Expande cores, símbolos e texturas da referência | Baixo |
| 24 | Claro e arejado | Luz e cor | Tudo claro, branco e pastel | Baixo |
| 25 | Arcade retrô | Estilo gráfico | Pixel art, scanlines e cores de fliperama | Médio |
| 26 | Editorial assimétrico | Layout | Assunto à direita, texto e respiro à esquerda | Médio |
| 27 | Título 3D | Tipografia e oferta | Título em letras 3D extrudadas | Alto |
| 28 | Ação e velocidade | Ângulo e energia | Rastros de velocidade, diagonal forte | Médio |
| 29 | Gradiente líquido | Estilo gráfico | Fundo de gradiente fluido e orgânico | Baixo |
| 30 | Halo circular | Layout | Círculo/anel de luz emoldurando o assunto | Baixo |
| 31 | Ambiente de app premium | Cenário (cassino online ou bet) | Visual brilhante de app de jogo premium | Baixo |
| 32 | Luz em duas cores | Luz e cor | Luz colorida de cada lado | Baixo |
| 33 | Pop art | Estilo gráfico | Retícula, contorno preto e cores primárias | Alto |
| 34 | Título de impacto | Tipografia e oferta | Caixa-alta condensada, contorno e sombra | Médio |
| 35 | Momento congelado | Ângulo e energia | Câmera lenta com partículas suspensas | Baixo |
| 36 | Personagem em nova pose | Personagem e jogo | Mesmo personagem 3D em pose e ângulo novos | Baixo |
| 37 | Leitura em Z | Layout | Texto e assunto em zigue-zague dinâmico | Médio |
| 38 | Holográfico | Estilo gráfico | Fundo iridescente com brilho arco-íris | Baixo |
| 39 | Superfície do jogo | Cenário (cassino online ou bet) | Assunto sobre plataforma feita do próprio jogo | Baixo |
| 40 | Ultra vibrante | Luz e cor | Cores elétricas e saturadas | Baixo |
| 41 | Oferta como herói | Tipografia e oferta | A linha da oferta vira o centro da peça | Médio |
| 42 | Ângulo monumental | Ângulo e energia | Câmera baixa grande-angular, assunto gigante | Baixo |
| 43 | Saindo da tela do celular | Personagem e jogo | Personagem/símbolos saindo da tela do celular | Médio |
| 44 | Simetria central | Layout | Composição espelhada e centralizada | Baixo |
| 45 | Cinematográfico | Estilo gráfico | Cor de cinema, névoa, assunto como herói | Médio |
| 46 | Cenário temático do jogo | Cenário (cassino online ou bet) | Mundo 3D que o tema do jogo sugere | Baixo |
| 47 | Brilho âmbar | Luz e cor | Luz quente âmbar e champanhe com bokeh | Baixo |
| 48 | Placa de título de jogo | Tipografia e oferta | Título numa placa 3D estilo jogo online | Alto |
| 49 | Painéis múltiplos | Ângulo e energia | Tela dividida em painéis com recortes do assunto | Médio |
| 50 | Símbolos do jogo em 3D | Personagem e jogo | Símbolos do próprio jogo flutuando em 3D | Baixo |

## Instruções (copiar e colar)

**1. 3D premium** · Estilo gráfico · risco de texto: Baixo

```
Complete redesign in a premium 3D render style: glossy 3D geometric shapes (spheres, rings, pills) floating around the main subject, studio lighting with soft reflections, smooth gradient backdrop in a new palette. Text clean, bold and flat for perfect legibility.
```

**2. Destaque em close** · Layout · risco de texto: Baixo

```
Complete redesign, not a retouch: a dramatic close-up of the main subject fills about two-thirds of the canvas, boldly cropped at one edge. All the text grouped in one compact, high-contrast block at the top, on a solid color band. New background and palette.
```

**3. Arena à noite** · Cenário (cassino online ou bet) · risco de texto: Médio

```
Complete redesign with a night arena atmosphere: for sports betting, an empty stadium under bright floodlights; for an online casino game, the game's own world at night, glowing in its own colors. The main subject in front, sharp; cinematic contrast; text over the darker sky area.
```

**4. Clima oposto** · Luz e cor · risco de texto: Baixo

```
Complete redesign using the opposite mood of the reference: if it is warm, make it cool; if dark, make it bright; if very colorful, make it restrained. New background, new accent colors, matching new lighting on the main subject and a rearranged layout.
```

**5. Neon noturno** · Estilo gráfico · risco de texto: Médio

```
Complete redesign with a night neon aesthetic: dark background, glowing neon tubes and light lines framing the main subject, colored rim light (magenta, cyan or purple) on it, light haze. Text in bright, sharp letters with a subtle glow, fully legible.
```

**6. Diagonal dividida** · Layout · risco de texto: Médio

```
Complete redesign: split the canvas with a strong diagonal into two contrasting color fields. The main subject large on one side, slightly breaking over the diagonal line; the text block on the other side, left-aligned. Clean modern shapes, crisp light.
```

**7. Palco de revelação** · Cenário (cassino online ou bet) · risco de texto: Baixo

```
Complete redesign as a big reveal on stage: the main subject in the center of an empty stage under strong spotlights, with light beams and a little haze, dark venue around it. Exciting event atmosphere. Text above and below the subject.
```

**8. Monocromático + destaque** · Luz e cor · risco de texto: Baixo

```
Complete redesign with a monochrome palette (one hue in many tones) for the background and graphic elements, and a single strong contrasting accent color on the most important text line. The main subject keeps its real colors. New layout.
```

**9. Preto e dourado** · Estilo gráfico · risco de texto: Baixo

```
Complete redesign in a black-and-gold luxury style: deep black or dark marble background, fine gold lines and metallic accents, warm elegant light on the main subject. Text in refined gold or white letters. Sophisticated and minimal.
```

**10. Faixa central** · Layout · risco de texto: Baixo

```
Complete redesign: a bold full-width horizontal band crosses the middle of the canvas and carries the headline; the main subject sits above the band, partly overlapping it, and the rest of the text sits below. Punchy solid background in a new color.
```

**11. Fumaça e partículas** · Cenário (cassino online ou bet) · risco de texto: Baixo

```
Complete redesign with an abstract atmospheric setting: the main subject surrounded by swirling colored smoke, floating light particles and soft sparks on a dark background, as if materializing. Text crisp and bright, where the background is calm.
```

**12. Duotone** · Luz e cor · risco de texto: Baixo

```
Complete redesign with a bold duotone treatment on the background and graphic elements (two strong colors only, such as blue and pink or green and purple), while the main subject keeps its real colors and stands out. Graphic, poster-like.
```

**13. Minimalista premium** · Estilo gráfico · risco de texto: Baixo

```
Complete redesign in a minimalist premium-tech style: lots of empty space in a light or deep single tone, the main subject centered with a soft natural shadow, one accent color. Text perfectly aligned with elegant spacing. Calm and high-end.
```

**14. Pôster tipográfico** · Layout · risco de texto: Médio

```
Complete redesign as a typographic poster: the headline (the most prominent text line) set in very large heavy letters across the top 40% of the canvas, every letter fully visible. The main subject below, smaller and centered, with the rest of the text beneath it. Minimal background, one strong accent color.
```

**15. Estúdio infinito** · Cenário (cassino online ou bet) · risco de texto: Baixo

```
Complete redesign as a professional studio shot: the main subject in a seamless infinite studio (cyclorama) in a bold new color, perfect softbox lighting, crisp reflections and a soft floor shadow. Text arranged cleanly in the empty space.
```

**16. Luz dramática** · Luz e cor · risco de texto: Baixo

```
Complete redesign with dramatic low-key lighting: almost black background, a strong rim light outlining the main subject, one beam of light, deep shadows and high contrast. Text in bright, sharp letters. Intense and premium.
```

**17. Vidro fosco** · Estilo gráfico · risco de texto: Baixo

```
Complete redesign in a glassmorphism style: colorful blurred gradient background with soft blobs of light, the text on frosted translucent glass panels with thin bright borders, the main subject in front in sharp focus. Modern and techy.
```

**18. Cartão flutuante** · Layout · risco de texto: Baixo

```
Complete redesign: the main subject and all the text inside a large rounded card floating in the center with a soft shadow, over a contrasting gradient or textured background that fills the canvas. Modern, app-like look.
```

**19. Campo gráfico** · Cenário (cassino online ou bet) · risco de texto: Baixo

```
Complete redesign with a graphic field: for sports betting, a stylized top-down pitch or court with glowing lines; for a casino game, a subtle repeating pattern built from the shapes and colors of the reference's own game. The main subject large on top.
```

**20. Etiquetas por linha** · Tipografia e oferta · risco de texto: Médio

```
Complete redesign where each line of text sits on its own colored sticker or ribbon shape, stacked and slightly tilted in alternating directions, with the main subject large next to them. New background and palette.
```

**21. Colagem recortada** · Estilo gráfico · risco de texto: Médio

```
Complete redesign as a cut-out collage: the main subject cut out with a thick white sticker outline, over layered torn-paper shapes and textured paper in bold colors, slightly tilted for energy. Text on paper strips or tape pieces, clearly legible.
```

**22. Tela em destaque** · Layout · risco de texto: Médio

```
Complete redesign around the screen: if the reference shows a phone or a game screen, make that screen the hero, large and tilted in 3D perspective with a soft glow around it; if it does not, present the main subject inside a large glowing rounded frame. Text in a clean block above.
```

**23. Universo do próprio jogo** · Cenário (cassino online ou bet) · risco de texto: Baixo

```
Complete redesign that expands the reference's own visual world: take the colors, symbols, characters or textures already present in the reference and build an immersive full-canvas scene around the main subject, bigger, deeper and more layered, without bringing in elements from other games or sports.
```

**24. Claro e arejado** · Luz e cor · risco de texto: Baixo

```
Complete redesign with high-key lighting: very bright, airy and clean, white and soft pastel tones, minimal shadows, fresh feel. The main subject sharp and colorful against the light background. Text in strong dark colors for contrast.
```

**25. Arcade retrô** · Estilo gráfico · risco de texto: Médio

```
Complete redesign in a retro arcade style: pixel-art borders and shapes, subtle scanlines and glowing screen colors around the main subject, which keeps its own look (photo or polished 3D render), on a dark background. Text in bold blocky letters, perfectly spelled and fully legible.
```

**26. Editorial assimétrico** · Layout · risco de texto: Médio

```
Complete redesign with an editorial, asymmetric layout: the main subject off-center on the right, generous empty space on the left holding the text, left-aligned with a strong size hierarchy. Sophisticated background with one thin accent line.
```

**27. Título 3D** · Tipografia e oferta · risco de texto: Alto

```
Complete redesign with the headline in big 3D extruded letters (thick depth, glossy material, strong light) and the rest of the text in clean flat letters. The main subject below or beside the headline. Simple background so the 3D type stands out. Spelling must stay perfect.
```

**28. Ação e velocidade** · Ângulo e energia · risco de texto: Médio

```
Complete redesign with dynamic action: speed streaks, motion blur and an energy burst behind the main subject, as if it is bursting toward the viewer, with a strong diagonal composition. Text in bold italic letters along the diagonal, fully legible.
```

**29. Gradiente líquido** · Estilo gráfico · risco de texto: Baixo

```
Complete redesign with a fluid gradient style: smooth liquid color mesh and organic blobs flowing behind the main subject, vibrant but harmonious palette, soft glow where the colors meet. Text clean, in white or dark, for maximum contrast.
```

**30. Halo circular** · Layout · risco de texto: Baixo

```
Complete redesign: a large glowing circle or ring behind the main subject frames it in the center like a halo; the text arranged above and below the circle. Bold two-tone background, clean geometric look.
```

**31. Ambiente de app premium** · Cenário (cassino online ou bet) · risco de texto: Baixo

```
Complete redesign in the glossy look of a premium mobile gaming app: deep gradient background (purple, navy or emerald with gold accents), glowing light streaks and soft colored bokeh, the main subject in front, sharp and lit like a hero. For sports betting, add subtle glowing pitch lines.
```

**32. Luz em duas cores** · Luz e cor · risco de texto: Baixo

```
Complete redesign with dual-color gel lighting: the main subject lit from one side with a saturated color and from the other with a contrasting color, on a dark seamless background with glossy highlights. Bold music-video look. Text clean and white.
```

**33. Pop art** · Estilo gráfico · risco de texto: Alto

```
Complete redesign in a pop-art style: halftone dot textures, bold black outlines, flat saturated primary colors, empty comic-style burst shapes behind the main subject with no words inside them. Text in heavy comic-style letters, perfectly spelled.
```

**34. Título de impacto** · Tipografia e oferta · risco de texto: Médio

```
Complete redesign with high-impact typography: the headline in heavy condensed capitals with a thick contrasting outline and a hard drop shadow, slightly tilted; the main subject large beside it without covering any letter. Bold, punchy background.
```

**35. Momento congelado** · Ângulo e energia · risco de texto: Baixo

```
Complete redesign as a frozen high-speed moment: the main subject captured mid-motion with light trails, sparks and small fragments suspended in the air around it, ultra-sharp detail on a dark background. Text in a clean block at the top.
```

**36. Personagem em nova pose** · Personagem e jogo · risco de texto: Baixo

```
Complete redesign around the character: if the reference has a 3D character or mascot, show the very same character (identical design, colors, outfit, accessories and render style) in a new dynamic pose and camera angle, larger and closer, over a new background; if it has none, show the main subject from a bold new angle.
```

**37. Leitura em Z** · Layout · risco de texto: Médio

```
Complete redesign with a Z-shaped reading path: the first part of the text at the top-left, the main subject large in the center-right, the remaining text at the bottom-left. Energetic background with motion lines or soft speed blur.
```

**38. Holográfico** · Estilo gráfico · risco de texto: Baixo

```
Complete redesign with an iridescent holographic style: holographic foil background with a rainbow sheen, soft pastel reflections on the main subject, clean futuristic shapes. Text in crisp white or dark letters on a solid panel for legibility.
```

**39. Superfície do jogo** · Cenário (cassino online ou bet) · risco de texto: Baixo

```
Complete redesign where the main subject stands on a glossy 3D platform built from its own game: for an online casino game, its reels, grid, wheel or board turned into a shiny surface in perspective; for sports betting, a stylized pitch or court. Clean background, strong depth.
```

**40. Ultra vibrante** · Luz e cor · risco de texto: Baixo

```
Complete redesign with an ultra-vibrant, saturated palette: electric colors, strong gradients and glossy highlights, a background full of color but organized, the main subject popping with a bright outline glow. Text with strong contrast.
```

**41. Oferta como herói** · Tipografia e oferta · risco de texto: Médio

```
Complete redesign where the offer line that is already in the text (the bonus, the odds or the main benefit, exactly as written) becomes the visual hero: set large inside a bold shape such as a ticket, ribbon or glowing pill at the center, with the main subject around it. Every number exactly as given.
```

**42. Ângulo monumental** · Ângulo e energia · risco de texto: Baixo

```
Complete redesign with a dramatic low-angle, wide-lens view that makes the main subject look monumental, strong perspective lines leading to it and a deep sky or ceiling behind it. Text in a tight block at the top.
```

**43. Saindo da tela do celular** · Personagem e jogo · risco de texto: Médio

```
Complete redesign with the main subject (the 3D character, the game symbols or the athlete) bursting out of a modern smartphone screen in 3D, breaking the frame toward the viewer, the phone tilted in perspective and its screen showing only the game's own visuals with no readable text. Text in a clean block above.
```

**44. Simetria central** · Layout · risco de texto: Baixo

```
Complete redesign with a perfectly symmetrical vertical composition: the main subject centered in the middle third, mirrored light shapes on both sides, the text centered above and below in a strict hierarchy. Elegant and balanced.
```

**45. Cinematográfico** · Estilo gráfico · risco de texto: Médio

```
Complete redesign with a cinematic look: moody teal-and-orange color grading, dramatic contrast and light fog, the main subject lit like the hero of a film poster. Text in a tall, elegant condensed typeface, with no credits block and no extra text.
```

**46. Cenário temático do jogo** · Cenário (cassino online ou bet) · risco de texto: Baixo

```
Complete redesign set in the world that the reference's own theme suggests (for example an oriental temple for an oriental-themed game, open sky for a flight game, a sweets landscape for a candy-themed game), built only from the theme already visible in the reference and rendered as a detailed 3D environment around the main subject. For sports betting, the sport's own arena.
```

**47. Brilho âmbar** · Luz e cor · risco de texto: Baixo

```
Complete redesign bathed in warm amber and champagne light: glowing golden bokeh in the background, soft warm highlights on the main subject, deep soft shadows, a luxurious evening mood. Text in clean light letters over a darker area.
```

**48. Placa de título de jogo** · Tipografia e oferta · risco de texto: Alto

```
Complete redesign with the headline on a 3D title plaque in the style of an online game title: beveled, glossy, with metallic or gem trim and a soft glow, showing only the given text, fully legible. For sports betting, a sleek broadcast-style graphic bar. The main subject below the plaque.
```

**49. Painéis múltiplos** · Ângulo e energia · risco de texto: Médio

```
Complete redesign as a split screen: the canvas divided into two or three vertical panels, each showing a different crop of the same main subject (wide view, detail, glow), with all the text on one solid band across the panels.
```

**50. Símbolos do jogo em 3D** · Personagem e jogo · risco de texto: Baixo

```
Complete redesign with the reference's own game elements (only symbols, gems, cards, balls or icons already in the reference) floating around the main subject as glossy 3D objects at different depths, with depth of field and a soft glow. Deep-colored background, text in a clean block.
```

## Kits para quem prefere sempre os mesmos 4 eixos

Deixe na lista do cliente só estes 4 (o rodízio fica igual para todos os criativos).

| Kit | Eixos |
|---|---|
| **Bem diferentes** | 2. Destaque em close · 5. Neon noturno · 24. Claro e arejado · 21. Colagem recortada |
| **Premium** | 9. Preto e dourado · 26. Editorial assimétrico · 31. Ambiente de app premium · 8. Monocromático + destaque |
| **Seguro para o texto** | 18. Cartão flutuante · 1. 3D premium · 4. Clima oposto · 7. Palco de revelação |
| **Cassino online (personagem 3D)** | 36. Personagem em nova pose · 50. Símbolos do jogo em 3D · 46. Cenário temático do jogo · 43. Saindo da tela do celular |
| **Bet esportiva** | 3. Arena à noite · 19. Campo gráfico · 28. Ação e velocidade · 42. Ângulo monumental |
