# Histórico de versões

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
