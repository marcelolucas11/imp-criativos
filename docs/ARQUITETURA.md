# Arquitetura — IMP Criativos

## Visão geral

App nativo para macOS 14+ (Apple Silicon), em Swift/SwiftUI, sem dependências externas.
Feito **somente para criativos de cassino online e apostas esportivas (bet)** — ver [Nicho](#nicho-cassino-e-bet).
O projeto Xcode é gerado pelo [XcodeGen](https://github.com/yonaskolb/XcodeGen) a partir do `project.yml`.

```
Pasta de criativos
   ↓
[0] PLANEJAMENTO ── IA mais forte lê o pedido + o criativo: termos proibidos, texto final exato,
                    instrução de limpeza específica e regras das variações
   ↓
[1] LIMPEZA ─────── IA de imagem segue o plano
   ↓
[2] ANÁLISE ─────── IA de visão + leitura do próprio Mac (Vision) conferem os termos proibidos;
                    se sobrar algum, refaz a limpeza sozinha 1x. Texto travado = texto final do plano
   ↓
[3] VARIAÇÕES ───── N variações com o texto final travado, um eixo de cassino/bet por variação (em rodízio
                    entre os criativos); leitura do Mac confere cada uma e refaz sozinha 1x se aparecer termo proibido
   ↓
[4] CHECAGEM ────── IA confere se o texto saiu igual e se a marca não voltou
   ↓
[5] REVISÃO ─────── aprovar / refazer (com observação) / descartar
   ↓
[6] EXPORTAÇÃO ──── tamanho original ou fixo, JPG/PNG, nomenclatura cliente_criativo_vN
```

## Nicho: cassino e bet

O app atende um único nicho: anúncios de **cassino online** e **apostas esportivas (bet)** de operadores autorizados no Brasil
(Lei 14.790/2023). Cassino é sempre online (jogos de celular: slots, crash, mines, roleta e cartas ao vivo, com personagens e
símbolos 3D); o contexto proíbe transformar o anúncio em cena de cassino físico. Isso está centralizado em `Models/Niche.swift`,
usado por todos os prompts:

| Texto em `Niche` | Onde entra | Para quê |
|---|---|---|
| `promptContext` | Planejamento, interpretação, limpeza, variações, análise, checagem | Toda IA sabe que é criativo de cassino/bet |
| `mainSubject` | Variações | "Assunto principal" = personagem/mascote 3D, jogo (tela, rolos, símbolos, gemas, grade, roleta, cartas, objeto voador), celular com o app, pessoa, atleta, bola, ou a própria oferta |
| `characterRules` | Variações (e uma linha na limpeza; o planejamento descreve o personagem em `variation_rules`) | Mesmo personagem 3D em todas as variações (desenho, cores, roupa, acessórios, acabamento 3D); só pose/expressão/ângulo mudam; nunca outro personagem nem visual mais infantil (Portaria Interministerial nº 73/2026) |
| `noticesRule` | Limpeza, planejamento, variações, tentativa neutra | Segue a chave **Configurações → Avisos do criativo** (`AppSettings.keepWarningNotices`, UserDefaults `keepWarningNotices`, **desligada de fábrica**). Desligada: remove 18+, "Jogue com responsabilidade" e advertências (fora do texto final, sem recriar). Ligada: mantém os que já estão no criativo; se o aviso tiver a marca, sai só a marca |
| `coherenceRules` | Variações | Mesmo jogo/esporte e oferta; proibido adicionar palavras, números, odds, multiplicadores, valores, bônus, dinheiro, pessoas, logos, selos ou promessa de ganho |

`Prompts.neutral` (nova tentativa em bloqueio) descreve o anúncio como de operador de cassino e apostas licenciado no Brasil, só para adultos.

### Eixos de variação

- 50 eixos padrão em `Models/DefaultAxes.swift`, **gerado** por `scripts/eixos_variacao.py` junto com `docs/EIXOS-DE-VARIACAO.md` (para mudar, edite o script e rode `python3 scripts/eixos_variacao.py .`).
  Cada eixo é uma direção de arte completa que começa com *Complete redesign*; os de cenário se adaptam ao tema
  ("para cassino… / para bet esportiva…"). A ordem alterna famílias (layout, estilo, cenário, luz, tipografia, ângulo).
- `Prompts.variation` trata a referência (o limpo) como **briefing de conteúdo, não molde**, e pede peça nova; se o eixo não
  combinar com o tema da referência, a IA adapta o eixo ao tema.
- **Rodízio** (`JobStore.createJob`): a variação `i` do criativo `n` usa `axes[(n × variações + i) % axes.count]`.
  Com a lista do mesmo tamanho do número de variações, o comportamento é o antigo (todos os criativos usam os mesmos eixos).
- **Migração** (`ClientStore.migrateLegacyDefaults`): perfis com uma lista padrão antiga sem edição (os 6 eixos até a beta.13, ou os 50 da beta.14, reconhecidos por impressão digital SHA-256 em `ClientProfile.outdatedDefaultFingerprints`) passam para a lista atual.
  Perfis personalizados ficam como estão; o botão "Usar os 50 eixos padrão" troca quando o usuário quiser.

## Pastas do código

| Pasta | Responsabilidade |
|---|---|
| `App/` | Ciclo de vida, Dock ↔ barra de menus, confirmação ao sair, modelo central (`AppModel`) |
| `Models/` | `Niche` (cassino e bet), `Job`, `JobItem`, `Variation`, `ClientProfile`, `DefaultAxes` (gerado), `AppSettings` |
| `Storage/` | Chaves de API (`chaves.json`), perfis de clientes (JSON), lotes (JSON + imagens), caminhos |
| `Providers/` | Interface `AIProvider` e implementações Gemini (Interactions API) e OpenAI |
| `Pipeline/` | `JobRunner` (fila e etapas), `Prompts`, `ImageTools`, `Exporter`, `CostEstimator` |
| `System/` | Itens de Início (`SMAppService`), notificações, seletores de pasta |
| `Updater/` | Busca nas GitHub Releases, SHA-256, verificação de assinatura, substituição do app |
| `Views/` | Telas SwiftUI |

## Dados

| Dado | Local | No GitHub? |
|---|---|---|
| Chaves de API | `~/Library/Application Support/IMP Criativos/chaves.json` (permissão 600, só o usuário lê) | Nunca |
| Preferências | UserDefaults | Nunca |
| Perfis de clientes | `~/Library/Application Support/IMP Criativos/clients/*.json` | Nunca |
| Lotes | `…/jobs/<id>/job.json` + `originais/`, `limpos/`, `variacoes/` | Nunca |
| Exportados | Pasta escolhida pelo usuário | Nunca |
| Histórico (logs) | `…/logs/AAAA-MM.jsonl` (um arquivo por mês, guarda 6 meses) | Nunca |

Cada passo do lote é salvo no `job.json` assim que termina. Se o app fechar no meio, o lote é retomado ao abrir;
etapas interrompidas voltam para "pendente".

## Provedores de IA

| Etapa | Gemini | OpenAI |
|---|---|---|
| Limpeza e variações | `gemini-nano-banana-2.1` via `POST /v1beta/interactions` | `gpt-image-2` via `POST /v1/images/edits` |
| Análise e checagens | `gemini-3.5-flash-lite` via Interactions | `gpt-5-mini` via `POST /v1/chat/completions` |

Desde a beta.11, cada etapa (limpeza, variações, análise/checagem, planejamento) tem **IA principal** e **reserva**, cada
uma escolhida como plataforma › modelo em Configurações → Modelos de IA (`AppSettings.stageAI`, tipos em
`Models/AIModels.swift`). Desde a beta.12 o menu mostra uma lista fixa com todos os modelos compatíveis de cada
plataforma (`BuiltInModels`, agrupados em mais fortes / rápidos / atuais / anteriores), com ou sem chave, e não aceita
mais nome digitado. Modelos que a chave enxerga na API (`GET /v1beta/models` no Gemini, `GET /v1/models` na OpenAI,
filtrados por tipo em `ModelCatalog`) e que ainda não estão na lista fixa aparecem no fim, em "Novos". A IA escolhida no Novo lote vira a principal da etapa; "Refazer com…" põe a plataforma escolhida na frente
(`ProviderConfig.chain`). O tamanho de saída é sempre um formato vertical do Meta Ads
(1080×1350 em 4:5 ou 1080×1920 em 9:16), e a IA já gera nessa proporção: no Gemini, `aspect_ratio` 4:5 ou 9:16 com
`image_size` fixo em 2K e saída `image/jpeg` (o modelo não aceita PNG; o app converte para PNG ao salvar; se o modelo
recusar algum campo, repete sem eles); na OpenAI, `size` 1024x1536 (retrato, com
nova tentativa em `auto` se recusado). A exportação ajusta para o tamanho final (preenchendo e cortando o excesso pelo centro).

### Erros, tentativas e troca de IA

- **Classificação** (`AIErrorKind` em `HTTP.swift`): temporário (408/5xx), limite (429), conexão, bloqueio de conteúdo,
  chave, modelo inexistente (404), pedido recusado (400) e outros. Só os três primeiros são repetidos.
- **Tentativas** (`HTTP.send`): padrão 6, com espera ~2s, 5s, 10s, 20s, 40s (±30% aleatório, máx. 90s) e respeito ao
  `Retry-After`. Configurável em Configurações → Erros e tentativas.
- **Fila por IA** (`ProviderGate`): limita pedidos simultâneos de imagem por provedor somando todos os lotes (padrão 2;
  análise 4). Quando a IA responde 429/5xx, a fila daquela IA pausa por alguns segundos para os outros pedidos não
  insistirem juntos.
- **Troca automática** (`JobRunner.withFallback`): se a IA principal da etapa falhar (qualquer erro; bloqueio só se a
  opção estiver ligada) e a reserva escolhida tiver chave, a etapa é refeita nela (beta.11; antes era sempre "a outra"
  plataforma e só em erro temporário). O item guarda `providerUsed` e a tela mostra "feito com …".
- **Filtro de conteúdo** (beta.5): o Gemini recebe `safety_settings` com `off` em todas as categorias ajustáveis
  (`harassment`, `hate_speech`, `sexually_explicit`, `dangerous_content`, `jailbreak`); a OpenAI recebe
  `moderation=low`. Se o modelo recusar esses campos (400), repete sem eles. Quando a resposta vem bloqueada, o próprio
  provedor tenta uma vez de novo com `Prompts.neutral` (contexto de anúncio já publicado de empresa licenciada, só edição
  gráfica) antes de o erro chegar à troca automática de IA. As proteções fixas dos provedores não são ajustáveis.
  Desde a beta.8 o Gemini **não** faz a tentativa neutra quando o bloqueio é do filtro de saída de imagem
  (`image_safety`): a imagem já foi gerada e barrada, e nos testes a nova tentativa nunca passou.
- **Disjuntor por lote** (beta.8, `JobRunner.registerBlock`): depois de 2 imagens bloqueadas pela mesma IA num lote, as
  próximas limpezas e variações daquele lote vão direto para a outra IA (se houver chave e a troca em bloqueio estiver
  ligada). Escolha manual ("refazer com…") não passa pelo disjuntor. A contagem zera quando o lote é retomado.
- **Planejamento em sobrecarga** (beta.8, `JobRunner.makePlan`): com reserva disponível, o modelo de planejamento tem
  só 2 tentativas antes de trocar; depois de um 503/429 ele fica 5 minutos de lado (os próximos criativos começam pela
  reserva). Se as duas falharem, o último recurso é a IA principal da análise.
- **Limpeza pulada** (beta.8): o plano traz `needs_cleaning`. Quando é `false`, o original (com rotação aplicada) vira o
  "limpo" sem chamar a IA de imagem. A análise confere esse limpo; se achar marca ou termo proibido, o item ganha
  `forceClean` e a limpeza roda normalmente. "Refazer" na limpeza também força.
- **Tempo máximo por tentativa** (beta.9, `HTTP.withDeadline`): cada tentativa do `HTTP.send` tem prazo próprio,
  vindo de `RequestContext.timeout` (análise/checagem 90s, planejamento 240s, imagem 300s; sem contexto, imagem 300s e
  texto 240s). Passou do prazo, o pedido é cancelado e vira erro `.timeout` ("Tempo esgotado"), que é temporário. A espera
  pela vaga na fila da IA (`ProviderGate`) não conta no prazo. Pedido de texto acima de 45s é registrado no Histórico.
- **Análise e checagem em travamento** (beta.9, `withFallback(quickSwitch:)`): com a outra IA disponível e a troca
  automática ligada, a IA principal tem só 2 tentativas; na falha temporária, o modelo fica 5 minutos de lado
  (`analysisCooldown`) e as próximas análises/checagens começam pela outra, que tem até 3 tentativas.
- **Checagem em paralelo** (beta.9, `JobRunner.checkText`): as variações de um criativo rodam dentro de um
  `withTaskGroup`; a checagem de cada variação entra como tarefa do grupo e corre junto com a próxima variação. O
  criativo só termina quando o grupo termina, e cancelar o lote cancela as checagens em andamento.
- **Contexto da chamada** (`RequestContext`, task-local): leva lote, criativo e etapa até o `HTTP.send`, que avisa a tela
  ("Gemini ocupado (503) · tentativa 3/6", com contagem regressiva) e registra no histórico.

### Histórico

`ActivityLog` grava cada movimentação (lote criado/iniciado/pausado/concluído, etapas, tentativas, trocas de IA, revisão,
exportação, clientes, chaves, atualizações) em JSON Lines. A tela **Histórico** filtra por tipo, categoria, lote, período e
texto, e copia o registro ou um diagnóstico (versão, macOS, configuração sem chaves e registros) para colar numa conversa
de suporte.

## Segundo plano

- `Continuar em segundo plano` ligado: fechar a janela troca a política do app para `.accessory` (sai do Dock) e o
  `MenuBarExtra` mantém o ícone na barra de menus. Reabrir a janela volta para `.regular` (ícone e bolinha no Dock).
- Desligado: fechar a última janela encerra o app (com confirmação se houver lote rodando).
- `Abrir ao ligar o Mac`: `SMAppService.mainApp`.

## Atualização

1. `GET api.github.com/repos/marcelolucas11/imp-criativos/releases` (público, sem token).
2. Escolhe a maior versão SemVer acima da instalada (betas opcionais).
3. Baixa `IMP-Criativos-<v>.zip` e confere com `IMP-Criativos-<v>.zip.sha256`.
4. Descompacta com `ditto` e valida com `codesign --verify --deep --strict`.
   Se o app instalado tiver assinatura com certificado (não ad-hoc), exige o mesmo *designated requirement*.
5. Um script espera o app fechar, troca o bundle, remove a quarentena e reabre.

### Assinatura

A v1 beta é assinada *ad-hoc* (sem conta de desenvolvedor Apple). Consequências:
- Na primeira abertura é preciso "clique direito → Abrir".
- Por isso as chaves **não** ficam no Keychain (desde a 1.0.0-beta.10): com assinatura ad-hoc, cada versão tem outra
  identidade e o macOS pedia a senha das chaves de novo, às vezes sem parar.

Próximo passo planejado: certificado autoassinado da agência guardado como segredo do GitHub, para manter a mesma
identidade entre versões (com verificação de origem no atualizador).

## Publicação

- `ci.yml`: compila a cada push em `main`/`dev` e mostra erros como anotações.
- `release.yml`: quando o arquivo `VERSION` muda na `main`, compila em Release, empacota `.dmg`, `.zip` e `.sha256`,
  cria a tag `v<VERSION>` e publica a Release (pré-lançamento quando a versão tem `-beta`).

## Fora da v1

Vídeos · espanhol · Macs Intel · envio direto para a Meta · texto aplicado por código com templates · qualquer nicho que não seja cassino ou bet.
