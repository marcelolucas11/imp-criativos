# Arquitetura — IMP Criativos

## Visão geral

App nativo para macOS 14+ (Apple Silicon), em Swift/SwiftUI, sem dependências externas.
O projeto Xcode é gerado pelo [XcodeGen](https://github.com/yonaskolb/XcodeGen) a partir do `project.yml`.

```
Pasta de criativos
   ↓
[1] LIMPEZA ─────── IA escolhida (Gemini ou GPT) remove tudo da lista do cliente
   ↓
[2] ANÁLISE ─────── IA de visão confere sobras de marca e transcreve o texto
   ↓
[3] VARIAÇÕES ───── N variações, uma por eixo do cliente, mantendo o texto exato
   ↓
[4] CHECAGEM ────── confere se o texto saiu igual e se a marca não voltou
   ↓
[5] REVISÃO ─────── aprovar / refazer (com observação) / descartar
   ↓
[6] EXPORTAÇÃO ──── tamanho original ou fixo, JPG/PNG, nomenclatura cliente_criativo_vN
```

## Pastas do código

| Pasta | Responsabilidade |
|---|---|
| `App/` | Ciclo de vida, Dock ↔ barra de menus, confirmação ao sair, modelo central (`AppModel`) |
| `Models/` | `Job`, `JobItem`, `Variation`, `ClientProfile`, `AppSettings` |
| `Storage/` | Keychain, perfis de clientes (JSON), lotes (JSON + imagens), caminhos |
| `Providers/` | Interface `AIProvider` e implementações Gemini (Interactions API) e OpenAI |
| `Pipeline/` | `JobRunner` (fila e etapas), `Prompts`, `ImageTools`, `Exporter`, `CostEstimator` |
| `System/` | Itens de Início (`SMAppService`), notificações, seletores de pasta |
| `Updater/` | Busca nas GitHub Releases, SHA-256, verificação de assinatura, substituição do app |
| `Views/` | Telas SwiftUI |

## Dados

| Dado | Local | No GitHub? |
|---|---|---|
| Chaves de API | Keychain (`com.imperaservices.impcriativos`) | Nunca |
| Preferências | UserDefaults | Nunca |
| Perfis de clientes | `~/Library/Application Support/IMP Criativos/clients/*.json` | Nunca |
| Lotes | `…/jobs/<id>/job.json` + `originais/`, `limpos/`, `variacoes/` | Nunca |
| Exportados | Pasta escolhida pelo usuário | Nunca |
| Histórico (logs) | `…/logs/AAAA-MM.jsonl` (um arquivo por mês, guarda 6 meses) | Nunca |

Cada passo do lote é salvo no `job.json` assim que termina. Se o app fechar no meio, o lote é retomado ao abrir;
etapas interrompidas voltam para "pendente".

## Provedores de IA

| Etapa | Gemini (padrão) | OpenAI |
|---|---|---|
| Limpeza e variações | `gemini-nano-banana-2.1` via `POST /v1beta/interactions` | `gpt-image-2` via `POST /v1/images/edits` |
| Análise e checagens | `gemini-3.5-flash-lite` via Interactions | `gpt-5-mini` via `POST /v1/chat/completions` |

Os nomes dos modelos são editáveis nas Configurações. O tamanho de saída é sempre um formato vertical do Meta Ads
(1080×1350 em 4:5 ou 1080×1920 em 9:16), e a IA já gera nessa proporção: no Gemini, `aspect_ratio` 4:5 ou 9:16 com
`image_size` fixo em 2K (se o modelo recusar esses campos, repete sem eles); na OpenAI, `size` 1024x1536 (retrato, com
nova tentativa em `auto` se recusado). A exportação ajusta para o tamanho final (preenchendo e cortando o excesso pelo centro).

### Erros, tentativas e troca de IA

- **Classificação** (`AIErrorKind` em `HTTP.swift`): temporário (408/5xx), limite (429), conexão, bloqueio de conteúdo,
  chave, modelo inexistente (404), pedido recusado (400) e outros. Só os três primeiros são repetidos.
- **Tentativas** (`HTTP.send`): padrão 6, com espera ~2s, 5s, 10s, 20s, 40s (±30% aleatório, máx. 90s) e respeito ao
  `Retry-After`. Configurável em Configurações → Erros e tentativas.
- **Fila por IA** (`ProviderGate`): limita pedidos simultâneos de imagem por provedor somando todos os lotes (padrão 2;
  análise 4). Quando a IA responde 429/5xx, a fila daquela IA pausa por alguns segundos para os outros pedidos não
  insistirem juntos.
- **Troca automática** (`JobRunner.withFallback`): se a IA do lote falhar por erro temporário (ou bloqueio, se ligado) e a
  outra tiver chave, a etapa é refeita nela. O item guarda `providerUsed` e a tela mostra "feito com …".
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
- Depois de cada atualização o macOS pode pedir para liberar o Keychain de novo ("Permitir Sempre").

Próximo passo planejado: certificado autoassinado da agência guardado como segredo do GitHub, para manter a mesma
identidade entre versões (sem novo pedido de Keychain e com verificação de origem no atualizador).

## Publicação

- `ci.yml`: compila a cada push em `main`/`dev` e mostra erros como anotações.
- `release.yml`: quando o arquivo `VERSION` muda na `main`, compila em Release, empacota `.dmg`, `.zip` e `.sha256`,
  cria a tag `v<VERSION>` e publica a Release (pré-lançamento quando a versão tem `-beta`).

## Fora da v1

Vídeos · espanhol · Macs Intel · envio direto para a Meta · texto aplicado por código com templates.
