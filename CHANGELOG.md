# Histórico de versões

## [1.0.0-beta.26] — 2026-11-23

**Otimizador em Lote: as linhas são escolhidas antes do nível**

A ordem da tela agora segue o fluxo de trabalho: enquadramento → variações sutis → **linhas diagonais** → **intensidade das texturas** → saída.

- **Nova seção "Linhas diagonais"**, antes do nível. Tem a chave sim/não, o **estilo** (Tom ou Gravura) e a **direção** (botões Esquerda \\, Direita /, Cruzada X, Aleatória). Essas escolhas valem em qualquer nível, inclusive no Personalizado.
- **"Intensidade das texturas"** (antes "Texturas, linhas e bordas"): o nível Sutil, Equilibrado, Intenso ou Personalizado define a força e as medidas das linhas **do estilo escolhido**, e também o serrilhado, a aberração e a ofuscação.
  - Tom: Sutil 30% · 10/2 px · 55° · irregularidade 60% — Equilibrado 60% · 9/3 px · 50% — Intenso 90% · 8/3 px · 40%.
  - Gravura: Sutil 20% · 12/2 px — Equilibrado 50% · 8/3 px — Intenso 85% · 8/4 px (hard-light).
  - O Intenso não força mais o X: vale a direção escolhida.
- **Personalizado separado por estilo:** os sliders das linhas do Tom e da Gravura ficam guardados separadamente, então trocar o estilo não mistura as medidas.
- Ligar as linhas com o nível em Desligado já escolhe o Equilibrado. Com as linhas desligadas, o nível continua valendo para os outros efeitos.
- **Opções salvas antes desta versão:** quem usava um nível continua com linhas ligadas (Sutil e Equilibrado no Tom; Intenso em Gravura X). O Personalizado leva as linhas, o estilo e a direção que já tinha.
- **Testes novos:** níveis próprios de cada estilo, direção e estilo valendo em todos os níveis, Personalizado separado por estilo, ligar as linhas sem nível e leitura das opções antigas.

## [1.0.0-beta.25] — 2026-11-23

**Otimizador em Lote: linhas no tom (mantêm a cor)**

As linhas da beta.24 eram tinta preta e branca por cima da imagem. O novo estilo **Tom (mantém a cor)** imita o print de referência: só clareia e escurece o próprio pixel, sem trocar a cor. A gravura preto e branco continua disponível.

- **Tom (mantém a cor):** R, G e B são multiplicados pelo mesmo fator, então o verde continua verde e o amarelo continua amarelo. Ao clarear, o fator para antes de o canal mais forte estourar, para a cor não mudar.
  - Variação de brilho no centro da linha: 10% ≈ ±5%, 50% ≈ ±20%, 100% = ±35%. Nunca vira preto.
  - Borda suave (1 px), miolo escuro com um brilho fraco colado de um lado.
  - **Ângulo livre** de 30° a 75° (padrão 55°, mais em pé que a diagonal), com ±3° sorteados por imagem.
  - **Irregularidade** (0–100%): cada linha sai um pouco do lugar e é feita de trechos de ~36 px com força diferente, alguns com falha, como chuva ou filme riscado. O desenho muda de imagem para imagem.
  - Áreas muito claras (texto branco, luzes) quase não recebem linha.
- **Gravura (preto e branco):** a linha da beta.24, sem mudanças.
- **Tela:**
  - escolha do **estilo** (Tom ou Gravura) no Personalizado;
  - **botões grandes de direção** com o desenho de cada uma (Esquerda \\, Direita /, Cruzada X, Aleatória);
  - sliders de **Ângulo** e **Irregularidade** no Tom;
  - explicação de **Hard-light** e **Overlay** embaixo da Mistura (só na Gravura).
- **Presets:** Sutil (Tom, 30%, 10 px/2 px, 55°, irregularidade 60%) e Equilibrado (Tom, 60%, 9 px/3 px, 55°, 50%) passam a usar o Tom. Intenso continua em Gravura X.
- Opções personalizadas salvas antes desta versão continuam em Gravura. Os sorteios novos ficam no fim da sequência, então o resto do sorteio de cada semente não muda.
- **Testes novos:** cor (matiz e saturação) preservada em fundos verde, laranja, roxo e cinza; nada muda no branco; ângulo e direção conferidos a 45°, 55° e 70°; `\\` e `/` com a mesma força; irregularidade cria falhas e a semente muda o desenho; X equilibrado; sorteio do ângulo. O CI gera amostras num criativo parecido com o print (3 direções × 25/50/100%, zoom 4× e original × Gravura × Tom) e mede o Tom em Release.

## [1.0.0-beta.24] — 2026-11-23

**Otimizador em Lote: linhas diagonais bem marcadas**

Na beta.23 as linhas diagonais quase não apareciam em 1080×1920 (1px de espessura, mistura suave). Esta versão muda só o efeito de **Linhas Diagonais**. Serrilhado, aberração cromática, bloom e a janela "Inspecionar Antes / Depois" ficam como estavam.

- **Geometria em pixels reais da saída 1080×1920:** espessura de **2 a 8px** (padrão 3px) e espaçamento de **4 a 18px** (padrão 8px). A espessura nunca passa de espaçamento − 2, então sempre sobra respiro entre as linhas. As bordas das faixas são firmes: o desenho é feito pixel a pixel, sem reamostragem nem suavização.
- **Padrão de gravura em alto contraste:** cada linha vira uma **faixa escura** (preto) com uma **faixa fina de realce claro** (branco, com 60% da opacidade da escura) colada ao lado. Isso dá o efeito de relevo e faz a linha aparecer tanto em fundo claro quanto em fundo escuro.
- **Mistura de alto impacto:** saem Multiply e Soft-light, que eram fracas. Ficam **Hard-light** (padrão) e **Overlay**. As configurações antigas com os modos removidos voltam sozinhas para Hard-light.
- **Curva do slider "Intensidade":** 10% a 25% fica visível e discreto; 50% fica bem marcado sobre imagem e texto; 80% a 100% fica forte e dramático, com teto de 85% de opacidade para as letras continuarem legíveis.
- **`\` e `/` com a mesma força:** uma é o espelho exato da outra. No **X**, as duas camadas entram em sequência com opacidade equilibrada (65% cada), sem estourar o brilho nem escurecer demais.
- **Fase aleatória por imagem:** o ponto onde o padrão começa é sorteado para cada imagem (e, no X, para cada diagonal), então as linhas nunca caem nos mesmos pixels em duas imagens.
- **Presets:** Sutil (20%, 12px/2px), Equilibrado (50%, 8px/3px) e Intenso (85%, X, 8px/4px).
- Os sorteios novos ficam no fim da sequência, então o resto do sorteio de cada semente não muda.
- **Testes novos:** geometria e estado de cada pixel (faixa escura, realce ou intacto) nas três direções; `\` e `/` com histograma idêntico; faixa legível em fundo escuro, médio e claro; X sem alterar o brilho médio além do limite; curva do slider; fase variando entre imagens; leitura de opções salvas com o modo antigo. O CI também gera uma folha de amostras com 5 níveis × 3 direções e uma folha ampliada.

## [1.0.0-beta.23] — 2026-11-23

**Otimizador em Lote: texturas, linhas e bordas, e janela "Inspecionar Antes / Depois"**

- **Nova seção "Texturas, linhas e bordas"** com os presets **Desligado**, **Sutil**, **Equilibrado**, **Intenso** e **Personalizado**. Ela vale junto com a Intensidade (por exemplo, nível Normal + textura Equilibrada). Vem **desligada de fábrica**, então nada muda para quem já usa o app: a mesma imagem com a mesma semente sai igual à da beta.22.
  - **Sutil:** linhas leves, micro-aberração (1 a 2px) e serrilhado mínimo.
  - **Equilibrado:** linhas diagonais visíveis, serrilhado moderado e deslocamento RGB médio.
  - **Intenso:** linhas marcadas (cruzadas), serrilhado alto, aberração cromática e bloom fortes.
  - No **Personalizado**, cada efeito tem a própria chave e um slider de 0 a 100%. Ao escolher Personalizado, os sliders partem do preset que estava em uso.
- **Linhas diagonais:** direção `\`, `/`, X (cruzada) ou **aleatória por imagem**; opacidade de 0 a 100%; espaçamento de 2 a 12px; espessura de 1 a 3px (sempre menor que o espaçamento); mistura **Overlay**, **Multiply** ou **Soft-light**. São linhas escuras desenhadas pixel a pixel, sem reamostrar. A opacidade tem teto de 85%, para o texto continuar legível mesmo com o slider no máximo. São diferentes dos "riscos diagonais" das intensidades Normal e Agressivo (±2 a ±10 níveis, média zero), que continuam como estavam.
- **Serrilhado de bordas:** só nas bordas de alto contraste (texto, botões, contornos). O app acha as bordas com Sobel na luminância, alarga a máscara em 2px e, só ali, quebra o anti-aliasing com reamostragem *nearest* por degraus (a grade vai a 100%–50%) e jitter por linha e por coluna (de ±0 a ±3px). Ruído, granulação e degradês suaves não entram na máscara, então o resto da foto não muda.
- **Aberração cromática RGB:** o canal vermelho anda para um lado e o azul para o oposto, de 1px a 6px conforme o nível, com o verde parado (halo colorido em volta de letras e objetos). A direção é sorteada por imagem.
- **Ofuscação (bloom + micro-desfoque):** micro-desfoque direcional curto com bloom nas luzes. No nível baixo as letras só ficam levemente estilizadas; no alto ficam perto do limite da leitura.
- Cada imagem sorteia entre **70% e 100%** do nível escolhido, para as versões não saírem idênticas. Os sorteios novos ficam no fim da sequência.
- **Botão "Inspecionar Antes / Depois"** (lupa), logo acima do preview. Abre uma janela grande com a imagem em 1080×1920, os mesmos pixels do arquivo final:
  - **Cortina:** barra vertical arrastável, com o Antes à esquerda e o Depois à direita.
  - **Lado a lado:** duas colunas que se movem juntas.
  - **Zoom** Ajustar, 100%, 200% e 400% com arrastar e rolar para mover. 100% é um pixel da imagem para cada pixel real da tela e, com zoom, sem suavização, para ver o serrilhado de verdade.
  - **Re-randomizar Preview:** sorteia outros valores para a imagem (a nova semente também vale no lote).
  - O **Antes** pode ser o **original enquadrado** (sem nenhuma variação) ou **sem as texturas** (tudo igual ao arquivo final, menos as texturas), com a mesma geometria para comparar pixel a pixel.
- O resumo do Histórico e o do preview passam a listar as texturas usadas.
- **Desempenho:** linhas e serrilhado são passadas inteiras sobre o buffer de 1080×1920 (medido em Release: cerca de 30 ms o serrilhado e 4 ms as linhas, por imagem); aberração e bloom rodam no Core Image, na placa de vídeo. Tudo continua 100% no Mac, sem rede e sem IA.
- **Testes automáticos novos:**
  - texturas desligadas não mudam o sorteio das outras etapas, e as opções salvas antes continuam lendo;
  - cada preset liga o que promete; a direção aleatória sorteia as três; a aberração fica entre 1 e 6px;
  - as linhas batem com a geometria de cada direção, em todos os pixels; \ e / correm cada uma para o seu lado;
  - o serrilhado deixa quieta a área lisa, a granulação e o degradê, rasga só a vizinhança de bordas fortes (verticais e horizontais) e é reproduzível;
  - vermelho e azul andam em sentidos opostos pelo número certo de pixels; o bloom vaza só perto de áreas claras;
  - arquivos finais de cada preset saem válidos em 1080×1920.

## [1.0.0-beta.22] — 2026-11-23

**Otimizador em Lote: níveis Normal e Agressivo, riscos diagonais e versões por imagem**

- **Novos níveis de intensidade**, agora em cinco: Leve, Moderado, **Normal**, **Agressivo** e Personalizado. Embaixo do seletor aparece o que cada nível faz, e o Agressivo vem com aviso.
  - **Normal:** recorte de 1% a 3%, rotação até ±1,5°, brilho e contraste ±4%, saturação ±6%, ruído ±3 a ±6 e granulação de 2% a 5%, com as etapas novas ligadas.
  - **Agressivo:** recorte de 2% a 5%, rotação até ±2°, brilho e contraste ±7%, saturação ±10%, ruído ±5 a ±8, deslocamento de canal de até 2px e granulação de 4% a 8%. A diferença fica visível, mas a peça continua reconhecível.
- **Riscos diagonais pixel a pixel:** uma linha escurece, a seguinte clareia e a outra mantém o tom original. Às vezes o padrão é de 4 linhas, com escurece, mantém, clareia, mantém. A direção (\ ou /), o espaçamento e a intensidade são sorteados por imagem. A média do padrão é zero, então o tom geral da imagem não muda. Vai de ±2 a ±5 níveis no Normal e de ±5 a ±10 no Agressivo.
- **Micro-perspectiva:** cada canto da imagem anda um pouco, até ±0,6% no Normal e ±1,5% no Agressivo, sem deixar borda vazia.
- **Temperatura de cor:** a imagem fica um pouco mais quente ou mais fria, até ±300K no Normal e ±650K no Agressivo.
- **Vinheta:** os cantos ficam um pouco mais escuros ou mais claros e o centro não muda, até ±5% no Normal e ±12% no Agressivo.
- **Versões por imagem (1 a 10):** cada imagem pode gerar várias versões, cada uma com um sorteio diferente (`story_001_v1_…`, `story_001_v2_…`). O preview tem um seletor para ver cada versão, e o progresso conta os arquivos.
- O **Personalizado** ganhou chave e limite para cada etapa nova, e os limites dos sliders agora vão até o Agressivo. Os ajustes salvos nas versões anteriores continuam valendo.
- Os níveis Leve e Moderado não mudaram. A mesma imagem com a mesma semente sai igual à da beta.21.
- **Testes automáticos novos:**
  - os riscos ficam só em base −N, base e base +N, constantes ao longo da diagonal e sem mudar a média;
  - o sinal + da temperatura deixa a imagem mais quente;
  - a vinheta muda os cantos e não o centro;
  - com tudo do Agressivo no extremo, não sobra canto vazio;
  - cada nível respeita os próprios limites;
  - as versões têm sementes e nomes diferentes.

## [1.0.0-beta.21] — 2026-11-23

**Nova aba: Otimizador em Lote (Stories 9:16) — 100% no Mac, sem IA**

- **Nova aba "Otimizador em Lote (Stories 9:16)"** no menu lateral (também no Início, na barra de menus e em ⇧⌘O). Não usa internet, chave de API nem IA, e não tem custo.
- **Até 100 imagens por vez:** arraste arquivos ou uma pasta (JPG, PNG, WebP, HEIC) ou use "Adicionar…". Contador 0/100, miniaturas com status, remover uma a uma ou limpar tudo.
- **Enquadramento 9:16 em 1080×1920 exatos:** *Preencher* (corta o excesso pelo centro), *Fundo desfocado* (imagem inteira no centro, com uma cópia ampliada e desfocada dela em cima e embaixo; padrão de fábrica, para não cortar texto) ou *Cor sólida* (preto, cor dominante da imagem ou uma cor escolhida).
- **Metadados apagados:** cada imagem é redesenhada do zero. EXIF, IPTC, XMP, GPS, comentários de software e perfis de cor antigos não passam para o arquivo, que sai só com um perfil sRGB limpo (para as cores não mudarem).
- **Variações sutis sorteadas por imagem**, em três níveis: *Leve (imperceptível)*, *Moderado* (os intervalos completos) ou *Personalizado* (uma chave e um limite por etapa):
  - micro-recorte de 0,5% a 1,5% nas bordas e micro-rotação até ±0,8°, voltando a 1080×1920 com Lanczos;
  - brilho e contraste ±2%, saturação ±3%;
  - micro-ruído de ±2 a ±4 níveis nos canais (evita faixas de cor na compressão do Instagram);
  - deslocamento de 1px no canal vermelho ou azul;
  - granulação de filme de 1% a 3% (overlay ou soft-light);
  - Unsharp Mask leve (0,2 a 0,4) ou suavização de 0,2px;
  - espelhar na horizontal (desligado de fábrica, só para imagens sem texto).
- **Gravação:** JPEG pela **libjpeg-turbo**, com qualidade sorteada entre 88 e 93 e, quando ligado, baseline ou progressivo e subamostragem 4:2:0 ou 4:4:4 sorteados. Também dá para gravar em PNG, sem perda. Nomes `story_001_a8f3k.jpg` ou só sequenciais, com prefixo editável.
- **Antes / Depois em tempo real** da imagem selecionada. O "Depois" é exatamente o arquivo que vai sair, e "Novo sorteio" troca os valores daquela imagem.
- **Fila com 4 imagens por vez**, barra "X de Y imagens processadas", status por arquivo e **Cancelar**. Dá para trocar de aba enquanto roda. Os arquivos vão para uma pasta `stories_data_hora` dentro da pasta escolhida, com **Abrir pasta** e **Baixar Tudo (.ZIP)**. O resumo de cada execução fica no Histórico.
- Cerca de 0,4 s por imagem de 4000×3000 no Mac de testes do GitHub.
- **Testes automáticos** do sorteio (limites, presets, sementes, nomes) e do motor com imagens fabricadas: ruído dentro de ±N, canal deslocado exatamente 1px, cantos sem vazio depois da rotação, EXIF/GPS/XMP removidos, JPEG com o modo e a subamostragem sorteados, PNG sem blocos extras e mesma semente = mesmo arquivo.

## [1.0.0-beta.20] — 2026-11-11

**Módulo "Limpar logo" e opção de desligar a limpeza no lote**

- **Novo módulo "Limpar logo"** no menu lateral (também no Início, na barra de menus e em ⇧⌘L). É só limpeza: escolha o cliente e a pasta com os anúncios (ex.: baixados da Biblioteca de Anúncios) e o app remove o logo e o nome da empresa, sem criar variações. Usa a mesma limpeza do lote normal: planejamento, lista do cliente + o que você pedir nas instruções, checagem pela IA e pela leitura do Mac e refação automática se sobrar marca.
- Na saída do módulo, o tamanho vem em **"Manter o tamanho original"** (dá para escolher feed 4:5 ou stories 9:16). Os arquivos saem como `cliente_criativo_limpo.jpg`. A estimativa mostra só o custo e o tempo da limpeza, e o lote pede só as chaves da IA da limpeza e da checagem.
- **Nova chave "Limpar logo e nome antes das variações"** no Novo lote (ligada de fábrica, vale para Normal e Teste de eixos). **Desligada**, as imagens da pasta são tratadas como já limpas e vão direto para as variações, **sem custo de limpeza** (a IA da limpeza some da tela e da estimativa). A checagem ainda lê cada imagem: se achar marca, **só avisa** na revisão, não limpa sozinha. Se quiser limpar uma imagem específica, use "Refazer" no quadro dela.
- Na revisão, o quadro da imagem mostra "Limpo" no módulo Limpar logo e "Enviado · v0" quando a limpeza estava desligada; o cabeçalho e o Histórico dizem qual modo o lote usou.

## [1.0.0-beta.19] — 2026-11-08

**Teste de eixos e modo rápido com segurança automática**

- **Novo modo "Teste de eixos"** no Novo lote (ao lado de "Normal"). Cada imagem passa por **todos os eixos marcados no cliente**, na ordem da lista, sem rodízio e com uma limpeza só. Com uma imagem e os 50 eixos do catálogo, saem 50 variações, uma por eixo. Na revisão, cada variação mostra o número e o nome do eixo ("27. Título 3D"); na exportação, o nome do arquivo também leva o eixo (`cliente_criativo_v27_e27-titulo-3d.jpg`).
- **Estimativa de tempo** no Novo lote, além do custo, e **confirmação antes de lotes grandes** (mais de 60 variações).
- **Variações em paralelo.** Antes, as variações de um mesmo criativo saíam uma de cada vez. Agora saem juntas, até o limite da fila de imagem da IA. Num teste com uma imagem só, isso sozinho já usa as 2 vagas em vez de 1.
- **Modo rápido com segurança automática** (Configurações → Velocidade, ligado de fábrica, teto de 4). O app começa na velocidade original (2 pedidos de imagem por IA), mede o tempo de cada imagem e sobe um pedido por vez enquanto a IA responde bem. **Volta na hora para a velocidade original** quando algo indica risco: IA ocupada (503), limite de uso (429), tempo esgotado, falha de conexão, IA ficando lenta demais com mais pedidos, Mac quente, modo de pouca energia, menos de 2 GB livres no disco ou lote 12 minutos sem concluir nada. Depois de um problema, só tenta subir de novo em 10 minutos (30 se o problema se repetir). Cada subida e descida fica no Histórico, e o topo do lote mostra a velocidade e o risco.
- **A qualidade não depende da velocidade.** O modo rápido só muda quantos pedidos vão juntos: modelo, qualidade, prompts, checagem de texto, leitura do Mac e refações continuam iguais.
- **Integridade das imagens.** Resposta da IA que o Mac não consegue abrir como imagem não é salva (conta como falha temporária e a reserva entra). Depois de gravar, o arquivo é conferido. E antes de cada rodada do lote, qualquer etapa "pronta" cuja imagem sumiu do disco volta sozinha para a fila.
- **Testes automáticos** no GitHub Actions para as regras de velocidade e para as variações em paralelo (com uma IA de mentira que demora e falha): cada variação roda uma vez só, o limite é respeitado mesmo mudando no meio, e pausar não deixa nada rodando.

## [1.0.0-beta.18] — 2026-11-07

**Escolha de eixos por catálogo e chave de rodízio**

- **Chave "Rodízio"** ao lado do título "Eixos de variação" (por cliente, ligada de fábrica). Ligada: cada criativo do lote usa os próximos eixos da lista. Desligada: todo criativo usa os primeiros eixos da lista, na ordem.
- **Botão "Catálogo do app"**: abre uma janela com os 50 eixos que vêm com o programa, catalogados por número, nome, família, o que muda e risco de texto, com busca e filtros por família e risco. "Ver mais" mostra o prompt de cada eixo. Marcar a bolinha coloca o eixo na lista do cliente; desmarcar tira. Botões para marcar ou desmarcar todos os visíveis.
- **Botão "Meus eixos"**: biblioteca dos eixos que você criou, válida para todos os clientes, com a mesma bolinha. "Ver mais" abre a edição do nome, do "o que muda" e do prompt; dá para criar e apagar eixos. Na primeira vez, ela recebe os eixos personalizados que já estavam nos seus clientes; depois, todo eixo novo que você escrever na lista de um cliente entra nela ao Salvar.
- Na lista do cliente, cada eixo mostra se é do catálogo (com o número) ou "Meu eixo", e o título mostra quantos eixos estão na lista.
- As janelas mexem só na lista do cliente aberta; nada é gravado até clicar em Salvar.

## [1.0.0-beta.17] — 2026-11-07

- **Nova chave "Manter avisos 18+ e de jogo responsável"** em Configurações → Avisos do criativo. **Vem desligada de fábrica**: o app remove o 18+, o "Jogue com responsabilidade" e advertências (como "Ministério da Fazenda adverte…") na limpeza, tira esses avisos do texto final e as variações não os recriam. **Ligada**: o app mantém os avisos que já estão no criativo (se o aviso tiver o nome da casa, sai só o nome). Vale para os próximos lotes e para o que for refeito; o estado aparece no registro de cada lote em Histórico.

## [1.0.0-beta.16] — 2026-11-07

- **Removida a regra da advertência "Ministério da Fazenda adverte".** O app não exige mais esse aviso nem tamanho mínimo de 10% da área. Continua só mantendo o 18+ e o "Jogue com responsabilidade" que já estão no criativo (a menos que você peça para tirar).

## [1.0.0-beta.15] — 2026-11-07

**Filtro de cassino online: personagens 3D, sem cassino físico e avisos de 2026**

- **Cassino é sempre online.** O contexto enviado às IAs agora diz que o jogo é de celular ou computador e proíbe transformar o anúncio em cena de cassino físico (salão, fileiras de máquinas, mesas num ambiente, ruas e letreiros estilo Las Vegas).
- **Personagens 3D tratados como assunto principal.** O mascote ou personagem 3D do jogo continua o mesmo em todas as variações: mesmo desenho, cores, roupa, acessórios e acabamento 3D, inclusive quando o fundo vira pop art, pixel art ou colagem. Só a pose, a expressão e o ângulo podem mudar, quando o eixo pede. O app nunca adiciona outro personagem nem deixa o personagem mais infantil. O planejamento passa a descrever o personagem para as variações não o trocarem.
- **Avisos obrigatórios de 2026.** Além do 18+ e do "Jogue com responsabilidade", a limpeza, o planejamento e as variações mantêm a advertência "Ministério da Fazenda adverte: …" na horizontal, legível e com pelo menos 10% da área do anúncio (Portaria SPA/MF 1.964/2026, em vigor desde 17/07/2026).
- **Eixos revisados (continuam 50).** Saíram os que levavam para cassino físico ou fugiam do nicho online: Salão premium, Mesa de feltro ou gramado, Lounge VIP, Vista de cima, Letreiro luminoso, Cidade à noite e Retrô anos 80. Entraram Ambiente de app premium, Superfície do jogo, Cenário temático do jogo, Placa de título de jogo e a nova família **Personagem e jogo**: Personagem em nova pose, Saindo da tela do celular e Símbolos do jogo em 3D. Arena à noite e Arcade retrô foram ajustados. O script que gera os eixos agora recusa termos de cassino físico.
- Clientes que estavam com os 50 eixos da beta.14 sem edição passam sozinhos para a lista nova.

## [1.0.0-beta.14] — 2026-11-07

**App exclusivo de cassino e bet, com 50 eixos de variação novos**

- **O app agora é declarado e configurado só para criativos de cassino online e apostas esportivas (bet).** O nicho fica num lugar só do código (`Niche.swift`) e entra em todos os pedidos às IAs: planejamento, leitura das instruções do lote, limpeza, variações, análise, checagem e a nova tentativa em bloqueio. Saíram as referências a prêmio físico e produto, que vinham do começo do projeto.
- **50 eixos de variação de cassino e bet no lugar dos 6 antigos.** Cada eixo é uma direção de arte completa (layout, fundo, estilo, luz e tratamento do texto), para cada variação sair com cara de peça nova feita pelo mesmo designer. São 6 famílias: layout, estilo gráfico, cenário, luz e cor, tipografia e oferta, ângulo e energia. Os eixos de cenário têm versão para cassino e para bet esportiva (ex.: mesa de feltro ou gramado; salão de cassino ou lounge de estádio). Lista completa em `docs/EIXOS-DE-VARIACAO.md`.
- **Todos os eixos passam a ser usados (rodízio).** Antes, todo criativo usava só os primeiros eixos da lista (com 4 variações, só os 4 primeiros). Agora o 1º criativo usa os eixos 1 a 4, o 2º usa 5 a 8, e assim por diante; no fim da lista, recomeça. A lista padrão alterna as famílias, então as 4 variações de cada criativo saem de famílias diferentes. Quem quiser sempre os mesmos eixos deixa na lista só a quantidade de variações.
- **Variações mais diferentes do original.** O pedido de variação agora diz para tratar o criativo limpo como briefing (assunto, texto, tema e oferta), não como molde de layout, e montar uma peça nova.
- **Regras de coerência para todas as variações**, inclusive com eixos escritos por você: mesmo jogo ou esporte, mesma oferta, texto exato, e nada de palavras, números, odds, multiplicadores, valores, bônus, dinheiro, pessoas, logos, selos ou promessa de ganho que não estejam no original. Se um eixo não combinar com o tema (ex.: cenário de cassino num criativo de bet esportiva), a IA adapta o eixo ao tema do criativo.
- **Avisos obrigatórios preservados.** A limpeza, o planejamento e as variações mantêm o "18+" e o "Jogue com responsabilidade". Se o aviso tiver o nome da casa, sai só o nome.
- **Clientes antigos:** quem ainda usava os 6 eixos padrão sem mudança passa sozinho para os 50. Quem personalizou os eixos continua com os seus; o botão **Usar os 50 eixos padrão (cassino e bet)** troca quando quiser (só vale depois de Salvar).
- Exemplos e textos da tela de Clientes, do Novo lote, do Início e de Configurações → Sobre falam de casa de apostas ("Minha Bet", @minhabet, minhabet.bet.br). A barra lateral mostra "Cassino e bet" ao lado da versão.

## [1.0.0-beta.13] — 2026-11-06

**Ordem dos eixos de variação**

- **Botões de subir e descer** em cada eixo de variação (Clientes → Eixos de variação). A ordem define qual eixo cada variação usa: a v1 usa o 1º, a v2 o 2º, e assim por diante.
- Cada eixo mostra a posição (1º, 2º, 3º…) ao lado do nome. As setas ficam apagadas no primeiro e no último.
- A nova ordem vale ao salvar o cliente e é usada nos próximos lotes.

## [1.0.0-beta.12] — 2026-11-06

**Todos os modelos já prontos no menu**

- **Fim do "Digitar outro modelo…".** Cada plataforma agora mostra a lista completa de modelos que funcionam no app, mesmo sem a chave salva, cada um com uma nota curta (ex.: "mais fiel na edição", "o mais barato").
- **Imagem (limpeza e variações):** Gemini — Nano Banana 2.1, Nano Banana Pro, Nano Banana 2, Nano Banana 2 Lite e o original; OpenAI — Images 2.6 e 2.5 (Sunburst e Flare), gpt-image-2 e os anteriores.
- **Texto (planejamento, análise e checagem):** separados em "Mais fortes" (Gemini 4 Argon, 3.1 Pro, 3.8 Flash; GPT-6 Astra, 6.1 Sol, 6 Sol) e "Rápidos e baratos" (Flash, Flash-Lite; GPT-6.1 Terra, 6 Luna, minis), mais as versões anteriores.
- Lançamentos que a sua chave enxergar e que ainda não estão na lista aparecem no fim do menu, em "Novos, vistos pela sua chave".
- Os modelos padrão de cada etapa não mudaram.

## [1.0.0-beta.11] — 2026-11-06

**Escolha de plataforma e modelo por etapa, com IA reserva**

- **Configurações → Modelos de IA virou menu.** No lugar das caixas de texto, cada etapa (Limpeza, Variações, Análise e checagem, Planejamento) tem um botão que abre **plataforma › modelo**: escolha Google (Gemini) ou OpenAI (GPT) e, dentro dela, a versão.
- **Nova caixa "Reserva se der erro" em cada etapa.** Você escolhe qual plataforma e modelo assume quando a principal falha (pode ser a outra plataforma ou outro modelo da mesma), ou "Nenhuma". A troca agora vale para qualquer erro da principal (sobrecarga, modelo não encontrado, chave, pedido recusado); o bloqueio de conteúdo continua dependendo da opção em Erros e tentativas.
- **Lista de modelos atualizada pela sua chave.** O app pergunta ao Google e à OpenAI quais modelos a sua chave enxerga (botão "Atualizar lista de modelos", e sozinho uma vez por dia ou ao salvar uma chave). Modelo que ainda não aparece: "Digitar outro modelo…".
- **Novo lote usa o mesmo menu** para a IA da limpeza, das variações e das checagens; a escolha vira a principal da etapa.
- **O planejamento tem IA própria** (antes seguia a IA das checagens do lote). A interpretação das instruções do lote usa a IA do planejamento e, se falhar, a da análise.
- **Migração automática:** as escolhas e os nomes de modelo que você já tinha viram a principal de cada etapa, com a outra plataforma como reserva.

## [1.0.0-beta.10] — 2026-11-06

**Fim do pedido de senha do Keychain**

- **Corrigido: o macOS pedia a senha das chaves sem parar** ("IMP Criativos deseja acessar a chave…"), mesmo com a senha certa. O app é assinado sem conta de desenvolvedor Apple, então cada versão nova tem outra identidade e a liberação anterior não valia; e como as telas conferem a chave a todo momento, o pedido voltava em seguida.
- **As chaves saíram do Keychain.** Agora ficam em `~/Library/Application Support/IMP Criativos/chaves.json`, com permissão só para a sua conta do Mac. Continuam sem ir para o GitHub nem para lugar nenhum além do Google/OpenAI.
- **Migração automática e silenciosa:** na primeira abertura, o app tenta trazer as chaves antigas do Keychain sem mostrar nenhum pedido. Se o macOS não deixar, é só colar as chaves de novo em **Configurações → Chaves de API** (uma vez).

## [1.0.0-beta.9] — 2026-11-05

**Nada de lote parado esperando uma IA que não responde (correções a partir do diagnóstico do "teste white v2")**

- **Corrigido: uma checagem de texto podia segurar o criativo por até 1 hora.** Cada tentativa esperava até 10 minutos pela resposta, e a troca automática de IA só entrava depois das 6 tentativas. No "teste white v2", a checagem da v2 do hambúrguer ficou ~31 minutos parada. Agora cada tentativa tem um tempo máximo pela etapa: **análise e checagem 90s, planejamento 4 min, imagens 5 min**.
- **A análise e a checagem trocam de IA rápido.** Com a outra chave configurada, elas desistem na 2ª falha temporária (tempo esgotado, 503 ou 429) e passam para a outra IA. O modelo que travou fica 5 minutos de lado, e as próximas análises e checagens já vão direto para a outra. Na IA de reserva, a checagem tenta no máximo 3 vezes.
- **A checagem não segura mais as próximas variações.** A checagem da v2 roda junto com a geração da v3, e o criativo só fica pronto quando todas as checagens terminam.
- **Novo erro "Tempo esgotado"**, separado de "Falha de conexão": quando a IA não responde dentro do tempo máximo.
- **Histórico mais claro:** análise, checagem ou planejamento que passa de 45s ganha uma linha com o tempo que levou.

## [1.0.0-beta.8] — 2026-11-05

**Lotes mais rápidos e previsíveis (correções a partir do diagnóstico do "teste white")**

- **Corrigido: todo pedido de imagem ao Gemini falhava na primeira tentativa.** O app pedia a saída em PNG e o modelo só devolve JPEG. Agora o pedido vai completo, e a imagem do Gemini volta em 9:16 (ou 4:5) e 2K, em vez de sair sem proporção.
- **Limpeza pulada quando não há nada para remover.** O planejamento passa a dizer se a imagem precisa de limpeza. Se não precisar, o original segue direto para as variações, sem custo e sem risco de bloqueio. A checagem continua conferindo; se encontrar marca, a limpeza é feita normalmente. O criativo mostra "Nada a remover · usando o original", e "Refazer" limpa mesmo assim.
- **Fim da tentativa neutra no bloqueio de imagem do Gemini.** Quando o filtro de imagem do Google barra o resultado (`image_safety`), o app passa direto para o GPT em vez de repetir no Gemini (nos testes, a repetição nunca funcionou e custava até 2 minutos).
- **Disjuntor por lote:** depois de 2 imagens bloqueadas pela mesma IA num lote, as próximas imagens daquele lote vão direto para a outra. O Histórico avisa quando isso acontece.
- **Limpeza no GPT por padrão.** Quem usava o Gemini na limpeza passa para o GPT uma vez (se tiver a chave da OpenAI). Dá para escolher o Gemini de novo no Novo lote.
- **Planejamento troca de IA mais cedo em sobrecarga.** Com 2 erros 503/429 seguidos, o plano vai para a outra IA (antes eram 6 tentativas, mais de 3 minutos). O modelo sobrecarregado fica 5 minutos de lado, e os próximos criativos já começam pela outra IA. Sem a outra chave, o app usa o modelo de análise.
- **Aviso no Novo lote** quando o cliente ainda tem os nomes de exemplo ("Minha Empresa Prêmios", @minhaempresa).

## [1.0.0-beta.7] — 2026-11-04

**O app segue o seu pedido à risca**

- **Nova etapa de planejamento antes da limpeza.** Uma IA de raciocínio mais forte (Gemini `gemini-4-argon` ou OpenAI `gpt-6-sol`, conforme a IA de análise do lote) olha cada criativo junto com o perfil do cliente e as instruções do lote, e escreve para as outras etapas:
  - a lista de **termos proibidos** daquele criativo (palavras, nomes, @, sites), escritos como aparecem na imagem;
  - o **texto final exato** que o criativo deve ter, reescrevendo a frase só o necessário quando uma palavra sai (ex.: "GOSTA DE AVIATOR?" → "GOSTA DE JOGAR?");
  - uma **instrução de limpeza específica** para aquela imagem (o que apagar, onde, e qual linha troca por qual);
  - as **regras das variações**.
- **Corrigido:** as variações copiavam palavras que deviam sumir. Antes, o texto travado das variações vinha do que *sobrou* no limpo; se a limpeza deixasse "AVIATOR", as variações eram obrigadas a escrever "AVIATOR". Agora o texto travado é o texto final do plano, e o código remove qualquer termo proibido dele.
- **Conferência pelo próprio Mac (sem custo):** a leitura de texto do macOS confere o limpo e cada variação. Se aparecer termo proibido, o app **refaz sozinho uma vez** com a observação do que apareceu. Se mesmo assim sobrar, o criativo chega com aviso amarelo "Termo proibido".
- Os termos proibidos entram em todas as instruções (limpeza, variações e checagens), inclusive em telas de celular, miniaturas e logos.
- A interpretação das instruções do lote também passou a usar o modelo de planejamento.
- O plano de cada criativo aparece no ícone de prancheta ao lado do nome e fica no Histórico.
- **Configurações → Modelos de IA:** liga/desliga o planejamento e troca os modelos. Se o modelo não for aceito, o app usa o de análise e avisa no Histórico. Custo estimado: cerca de US$ 0,02 por criativo (editável na tabela de preços).

## [1.0.0-beta.6] — 2026-11-04

**Instruções por lote**

- **Nova caixa "Instruções para este lote" no Novo lote.** Escreva em texto livre, por exemplo: *tirar todo nome Aviator, tirar o nome X, adicionar o nome Y, criar ângulos bem diferentes e variados*.
- **O app interpreta o pedido em três partes** e mostra para você conferir e editar antes de iniciar:
  - **Remover também:** entra na limpeza e nas checagens de sobra de marca deste lote.
  - **Alterar o texto:** a limpeza já aplica a mudança, e o texto esperado das variações passa a ser o texto alterado. A checagem de texto confere se o nome novo saiu certo.
  - **Direção das variações:** somada ao eixo de cada variação.
- A interpretação usa a IA das checagens (uma chamada de texto, custo desprezível). Se ela falhar, tenta a outra IA; se as duas falharem, o texto vai inteiro para "Direção" e você ajusta.
- **Instruções salvas por cliente:** botão "Salvar no cliente" e menu "Instruções salvas" para reaproveitar em outros lotes.
- As instruções aparecem no topo do lote e ficam registradas no Histórico.
- Se a limpeza não aplicar a alteração de texto, o criativo ganha um aviso, e as variações aplicam mesmo assim.
- **Botão "Baixar para Mac" no README** com link fixo que sempre baixa a versão mais nova.

## [1.0.0-beta.5] — 2026-11-04

**Menos bloqueios em criativos de cassino e apostas**

- **Gemini com filtros ajustáveis desligados:** todas as categorias de segurança que o Google deixa configurar (assédio, ódio, conteúdo sexual, conteúdo perigoso e jailbreak) vão como "off" em cada pedido de imagem e de análise.
- **OpenAI com moderação "low":** o nível menos restritivo que a OpenAI permite para gerar e editar imagens.
- **Nova tentativa automática com instrução neutra:** se a IA bloquear, o app tenta mais uma vez explicando que é só uma edição gráfica de um anúncio já publicado de empresa licenciada, sem promessas novas. Só depois disso troca para a outra IA (se a opção estiver ligada em Configurações → Erros e tentativas).
- Se algum modelo não aceitar esses ajustes, o app repete o pedido sem eles, em vez de falhar.
- Corrigido: um erro 400 de "campo não aceito" que citava "safety" ou "moderation" era confundido com bloqueio de conteúdo.

## [1.0.0-beta.4] — 2026-11-04

**Erros de IA ocupada (HTTP 503) não derrubam mais o lote**

- **Tentativas automáticas mais pacientes:** em erro temporário (503, 429, 5xx, falha de conexão) o app tenta de novo até 6 vezes, com esperas crescentes de ~2s, 5s, 10s, 20s e 40s, um pouco aleatórias para os pedidos não voltarem todos juntos. Respeita o tempo de espera pedido pelo servidor.
- **Fila por IA:** no máximo 2 pedidos de imagem ao mesmo tempo para cada IA, somando todos os lotes. Quando a IA responde "ocupado", os outros pedidos para ela esperam alguns segundos em vez de insistir juntos.
- **Troca automática de IA:** se o Gemini continuar ocupado depois das tentativas, a imagem é refeita no GPT (e vice-versa), quando as duas chaves estão salvas. Opcional também para imagens bloqueadas pelo filtro de conteúdo. A imagem mostra "feito com GPT (OpenAI)".
- **Erro temporário × definitivo na tela:** enquanto espera, a etapa mostra em amarelo "Gemini ocupado (503) · tentativa 3/6" com contagem regressiva. Falha temporária aparece em amarelo; erros reais (chave inválida, modelo inexistente, bloqueio) em vermelho, com a sugestão do que fazer ao passar o mouse.
- **Tentar falhas de novo:** o botão no topo do lote mostra quantas falhas existem e funciona mesmo com o lote rodando. Em Ações: "Refazer falhas com Gemini/GPT". Embaixo de cada etapa que falhou: "Refazer com …" usando a outra IA. Na barra de menus: tentar as falhas de todos os lotes.
- Configurações → **Erros e tentativas**: pedidos simultâneos por IA, nº de tentativas e as duas opções de troca automática.

**Novo: Histórico**

- Nova tela **Histórico** na barra lateral com tudo o que acontece: lotes criados, iniciados, pausados e concluídos; cada limpeza e variação (com a IA usada e o tempo); tentativas e trocas de IA; aprovações, descartes e "refazer" com a observação; exportações; perfis de clientes; chaves salvas e testadas (nunca a chave em si); atualizações.
- Filtros por tipo (tudo / erros e alertas / só erros), categoria, lote, período e busca por texto.
- Detalhes técnicos de cada erro (modelo, código HTTP, resposta da IA) e a sugestão de solução.
- **Copiar este registro**, **Copiar com contexto** e **Copiar diagnóstico** (versão, macOS, configuração sem chaves e registros filtrados), prontos para colar na conversa com o Claude.
- Selo com o número de erros novos na barra lateral; "Ver histórico deste lote" no menu Ações; clique com o botão direito num erro para copiá-lo.
- Os registros ficam só neste Mac (`Application Support/IMP Criativos/logs`), guardados por 6 meses. Exportar em .txt e apagar pelo menu Mais.

## [1.0.0-beta.3] — 2026-11-04

- Tamanhos de saída agora são só os verticais padrão do Meta Ads: **Feed 4:5 — 1080×1350** e **Stories e Reels 9:16 — 1080×1920** (saíram quadrado, personalizado e manter original).
- A IA já gera a imagem nessa proporção vertical, em vez de gerar no formato do original e cortar depois.
- Configurações: "Gemini — resolução" (1K/2K/4K) virou **Formato do criativo**, o formato padrão dos novos lotes. A resolução de geração fica fixa em 2K, que cobre os dois tamanhos com folga.

## [1.0.0-beta.2] — 2026-11-04

- Corrigido: o campo para colar a chave de API não aparecia nas Configurações (sobrava só o texto de dica).
- Novo: botão **Colar** e botão de olho para conferir a chave colada antes de salvar; Enter também salva.
- Corrigido: campos de texto em Clientes (itens a remover, eixos, instruções) e no tamanho personalizado agora aparecem com borda e largura certa.

## [1.0.0-beta.1] — 2026-11-04

Primeira versão de testes.

- Lotes: escolher pasta de criativos, cliente, nº de variações (1–10), IA por etapa (Gemini ou GPT), tamanho e formato de saída.
- Limpeza da marca com lista editável por cliente.
- Checagem automática de sobras de marca e transcrição do texto.
- Variações por eixos configuráveis, mantendo o texto exato do criativo.
- Checagem de texto em cada variação.
- Revisão: aprovar, refazer com observação, descartar; aprovação em massa.
- Exportação dos aprovados com nomenclatura `cliente_criativo_v0..vN`, tamanho original ou fixo, JPG ou PNG.
- Estimativa de custo antes do lote e contador de gasto por lote e por mês.
- Perfis de clientes com exportar/importar (`.impcliente`).
- Segundo plano com ícone na barra de menus, abrir ao ligar o Mac, notificações.
- Fila persistente: retoma o lote de onde parou.
- Chaves de API no Keychain.
- Atualização pelo botão dentro do app (GitHub Releases + conferência SHA-256 e assinatura).
