# Histórico de versões

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
