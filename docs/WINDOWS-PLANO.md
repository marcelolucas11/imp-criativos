# Versão Windows — mapa da migração

Este arquivo é o mapa da versão Windows do IMP Criativos (a partir da `1.0.0-beta.27`).
Se uma sessão de trabalho acabar no meio, a próxima continua daqui: a tabela diz onde cada parte do Mac
mora no Windows e a checklist diz o que já está pronto.

**Regra de ouro:** o app do Mac não muda. Nada em `Sources/IMPCriativos/` nem em `Tests/` é editado para o Windows.
Toda mudança de função, prompt, texto ou tela vale para as duas versões no mesmo PR (ver `CLAUDE.md`).

## Estrutura

```
windows/
  IMPCriativos.Windows.sln
  src/IMPCriativos.Core/      net10.0 — sem nada de Windows: modelos, prompts, provedores, pipeline,
                               otimizador (SkiaSharp + libjpeg-turbo), atualizador, logs
  src/IMPCriativos.App/       net10.0-windows10.0.19041.0 — WPF: telas, bandeja, OCR (Windows.Media.Ocr),
                               HEIC (WIC), notificações, iniciar com o Windows, --smoke-test
  tests/IMPCriativos.Tests/   xUnit — roda no Linux e no Windows
  tests/IMPCriativos.Tests/fixtures/  .impcliente e job.json de exemplo, paridade-mac.json (gerado pelo Swift)
  build/publish.ps1, smoke.ps1        publicação, instalador e teste de fumaça
  installer/IMPCriativos.iss  Inno Setup 6
```

## Paridade com o Mac verificada pelo CI

| O que | Como |
|---|---|
| Prompts (todos os textos enviados às IAs) | O job do Mac (`ci.yml`) compila `scripts/paridade/main.swift` junto com o código Swift e gera `windows/tests/IMPCriativos.Tests/fixtures/paridade-mac.json` (o log imprime o arquivo em `PARIDADE-B64:`). O teste `ParidadeMacTests` gera os mesmos prompts em C# e compara caractere por caractere. |
| Sorteio do Otimizador (`StoryParams.sample`) | Mesmo arquivo: parâmetros sorteados pelo Swift para várias sementes e opções; o C# precisa dar os mesmos valores. |
| Eixos padrão | `scripts/eixos_variacao.py` gera `DefaultAxes.swift` **e** `DefaultAxes.cs`; o CI roda o script e falha se `git diff --exit-code` mostrar diferença. |
| Arquivos (`.impcliente`, `job.json`) | `tests/fixtures/*.json` no formato do `Codable` do Swift; teste de ida e volta. |

## Tabela Swift → C#

| Swift (`Sources/IMPCriativos/`) | C# (`windows/src/`) | Observação |
|---|---|---|
| `Models/Niche.swift` | `Core/Models/Niche.cs` | textos idênticos; `KeepNotices` lê `Preferences` |
| `Models/Job.swift` | `Core/Models/Job.cs` | mesmos nomes de campo JSON |
| `Models/ClientProfile.swift` | `Core/Models/ClientProfile.cs` | `Fingerprint` com SHA-256 igual |
| `Models/AppSettings.swift` | `Core/Models/AppSettings.cs` | UserDefaults → `preferencias.json` |
| `Models/AIModels.swift` | `Core/Models/AIModels.cs` | lista de modelos idêntica; `ModelCatalog` |
| `Models/BatchInstructions.swift` | `Core/Models/BatchInstructions.cs` | prompt idêntico |
| `Models/DefaultAxes.swift` (gerado) | `Core/Models/DefaultAxes.cs` (gerado) | pelo mesmo script |
| `Storage/Paths.swift` | `Core/Storage/Paths.cs` | `%LOCALAPPDATA%\IMP Criativos` |
| `Storage/APIKeyStore.swift` | `Core/Storage/ApiKeyStore.cs` | `chaves.json` cifrado com DPAPI (CurrentUser) |
| `Storage/ActivityLog.swift` | `Core/Storage/ActivityLog.cs` | `logs\AAAA-MM.jsonl`, 6 meses |
| `Storage/ClientStore.swift` | `Core/Storage/ClientStore.cs` | importar/exportar `.impcliente` |
| `Storage/CustomAxisStore.swift` | `Core/Storage/CustomAxisStore.cs` | |
| `Storage/JobStore.swift` | `Core/Storage/JobStore.cs` | |
| `Providers/AIProvider.swift` | `Core/Providers/AIProvider.cs` | |
| `Providers/HTTP.swift` | `Core/Providers/Http.cs` | `RequestContext` com `AsyncLocal` |
| `Providers/GeminiProvider.swift` | `Core/Providers/GeminiProvider.cs` | |
| `Providers/OpenAIProvider.swift` | `Core/Providers/OpenAIProvider.cs` | |
| `Providers/ProviderGate.swift` | `Core/Providers/ProviderGate.cs` | `SpeedMonitor` com evento |
| `Pipeline/SpeedPolicy.swift` | `Core/Pipeline/SpeedPolicy.cs` | mesma lógica |
| `Pipeline/BoundedParallel.swift` | `Core/Pipeline/BoundedParallel.cs` | `SemaphoreSlim`/tarefas |
| `Pipeline/Prompts.swift` | `Core/Pipeline/Prompts.cs` | textos idênticos |
| `Pipeline/CreativePlanner.swift` | `Core/Pipeline/CreativePlanner.cs` | `LocalOCR` → `ILocalTextReader` |
| `Pipeline/ImageTools.swift` | `Core/Imaging/ImageTools.cs` | SkiaSharp; HEIC por `IImageDecoderExtension` (WIC no App) |
| `Pipeline/Exporter.swift` | `Core/Pipeline/Exporter.cs` | mesmos nomes de arquivo |
| `Pipeline/JobRunner.swift` | `Core/Pipeline/JobRunner.cs` | |
| `Pipeline/StoryOptimizerParams.swift` | `Core/Story/StoryOptimizerParams.cs` | SplitMix64 e ordem dos sorteios idênticos |
| `Pipeline/StoryTextureEffects.swift` | `Core/Story/StoryTextureEffects.cs` | C# puro sobre RGBX |
| `Pipeline/StoryOptimizer.swift` | `Core/Story/StoryOptimizer.cs` | Core Image → SkiaSharp; JPEG pela libjpeg-turbo (P/Invoke) |
| `Pipeline/StoryBatch.swift` | `Core/Story/StoryBatch.cs` | ZIP com `System.IO.Compression` |
| `Updater/Updater.swift` | `Core/Updater/Updater.cs` (namespace `Updates`) | instalador `.exe` + `.exe.sha256`, ignora `mac` e `windows` |
| `System/SystemServices.swift` | `App/Services/WindowsServices.cs` | OCR, WIC, Run do HKCU, toast, seletores, instância única |
| `App/*.swift` | `App/Program.cs`, `App/App.cs`, `App/AppModel.cs` | instância única (Mutex + pipe), bandeja, `--background`, `--smoke-test` |
| `Views/Components.swift` | `App/UI/UI.cs` + `App/UI/Theme.cs` | cores do tema escuro, componentes (telas montadas em código, sem XAML) |
| `Views/ContentView.swift` | `App/MainWindow.cs` | menu lateral, atalhos Ctrl |
| `Views/HomeView.swift` | `App/Views/HomeView.cs` | |
| `Views/NewJobView.swift` | `App/Views/NewJobView.cs` | inclui Limpar logo |
| `Views/JobDetailView.swift` | `App/Views/JobDetailView.cs` | revisão, Ver grande com comparar |
| `Views/ClientsView.swift` + `AxisPickers.swift` | `App/Views/ClientsView.cs` (com Catálogo e Meus eixos) | |
| `Views/StoryOptimizerView.swift` | `App/Views/StoryOptimizerView.cs` | |
| `Views/StoryInspectorView.swift` | `App/Views/StoryInspectorWindow.cs` | zoom sem suavização (NearestNeighbor, pixel real da tela) |
| `Views/LogsView.swift` | `App/Views/LogsView.cs` | |
| `Views/SettingsView.swift` + `ModelMenu.swift` | `App/Views/SettingsView.cs` + `App/UI/ModelMenu.cs` | |
| `Views/MenuBarView.swift` | `App/Services/TrayIcon.cs` | `NotifyIcon` |

## Diferenças inevitáveis entre Mac e Windows

- **OCR local**: o Mac usa o Vision; o Windows usa `Windows.Media.Ocr`, que depende do idioma instalado
  (Português primeiro; se não houver, qualquer idioma instalado). Sem OCR, a conferência local é pulada
  com aviso no Histórico e a checagem por IA continua.
- **HEIC**: depende das Extensões de Imagem HEIF da Microsoft Store.
- **Otimizador**: os arquivos não são idênticos bit a bit aos do Mac (Core Image e Skia arredondam diferente),
  mas os limites, a ordem das etapas e os parâmetros sorteados são os mesmos. No Windows, a mesma semente
  gera exatamente o mesmo arquivo.
- **Sinais de risco do computador** (calor, pouca energia): o Windows só confere o disco livre e a economia de bateria.
- **Notificações**: toast do Windows com o AppUserModelID do atalho do Menu Iniciar; se falhar, balão da bandeja.
- **Amostras do Otimizador com texto real** (`testLineLevelsAndDirectionsSamples`, `testToneLineSamples`): só no Mac, porque desenham texto com o CoreText; o resto dos testes de textura e imagem foi portado (97 testes no Windows e no Linux).
- **Atualização**: o Windows baixa o instalador (`.exe`) e roda em modo silencioso; o Mac troca o `.app`.

## Checklist de paridade

Legenda: [x] pronto · [~] parcial · [ ] falta

### Fase 1 — leitura e plano
- [x] Leitura de `Sources/`, `docs/`, `scripts/`, `.github/`
- [x] Este arquivo

### Fase 2 — solução e Core básico
- [x] Solução com 3 projetos
- [x] Modelos com JSON compatível com o `Codable` (UUID maiúsculo, data ISO 8601 sem fração, enums por nome)
- [x] `OutputSizeMode` no formato do Swift (`{"fixed":{"width":…,"height":…}}` / `{"original":{}}`)
- [x] Teste de ida e volta com `.impcliente` e `job.json` de exemplo
- [x] `Paths`, `Preferences` (`preferencias.json`)
- [x] Chaves com DPAPI
- [x] Histórico (logs por mês, 6 meses)
- [x] Eixos gerados em C# pelo script + checagem no CI
- [x] CI: `windows-latest` e `ubuntu-latest`

### Fase 3 — IA e pipeline
- [x] `Http` (tentativas, espera crescente, Retry-After, prazo por tentativa)
- [x] `ProviderGate`, `SpeedPolicy`, `SpeedMonitor`
- [x] `BoundedParallel`
- [x] Gemini (Interactions API, variantes, filtros desligados, tentativa neutra)
- [x] OpenAI (images/edits multipart, chat/completions)
- [x] `Prompts`, `CreativePlanner`, `ForbiddenTerms`, `InstructionInterpreter`
- [x] `JobRunner` (planejamento, limpeza, análise, refação 1x, variações, checagem, reserva, disjuntor, vigia, retomada)
- [x] `Exporter` + `CostEstimator`
- [x] Testes de `SpeedPolicy` e `BoundedParallel` portados
- [x] Paridade dos prompts com o Mac (fixture)

### Fase 4 — Otimizador em Lote
- [x] `StoryOptimizerParams` (SplitMix64, sorteio, presets, migrações da beta.26, nomes, versões, cor dominante)
- [x] Paridade do sorteio com o Mac (fixture)
- [x] `StoryTextureEffects` (linhas Tom e Gravura, serrilhado)
- [x] Motor Skia (enquadramentos, recorte/rotação, perspectiva, cor, temperatura, nitidez, canal, grão, riscos, vinheta, aberração, bloom, ruído)
- [x] JPEG pela libjpeg-turbo (qualidade, subamostragem, progressivo, ICC sRGB) e PNG limpo
- [x] `StoryBatch` (fila 4 por vez, cancelar, pasta `stories_data_hora`, ZIP)
- [x] Testes de `StoryOptimizerParamsTests`, `StoryTextureTests` e `StoryOptimizerImageTests` portados

### Fase 5 — App WPF
- [x] Tema escuro e menu lateral
- [x] Início
- [x] Novo lote (Normal / Teste de eixos, IA por etapa, tamanho, estimativa, confirmação > 60, instruções com conferência)
- [x] Limpar logo
- [x] Lotes e revisão (aprovar, refazer com observação, descartar, aprovar pendentes, ver grande, comparar)
- [x] Baixar aprovados
- [x] Clientes (O que remover, eixos, Rodízio, Catálogo, Meus eixos, importar/exportar)
- [x] Otimizador em Lote
- [x] Inspecionar Antes / Depois
- [x] Histórico
- [x] Configurações (chaves, modelos, avisos, velocidade, segundo plano, iniciar com o Windows, atualizações)
- [x] Bandeja com o menu da barra de menus, instância única
- [x] Notificações (toast, balão de reserva)
- [x] OCR local e HEIC
- [x] Atualizador
- [x] `--smoke-test` com capturas

### Fase 6 — instalador e publicação
- [x] Inno Setup
- [x] `release.yml` (job `windows`, tag fixa `windows`, sem `.zip`)
- [x] Botão Baixar para Windows, README, docs, `CLAUDE.md`, CHANGELOG

### Fase 7 — verificação
- [x] CI verde (Mac, Windows, Linux)
- [x] Capturas conferidas (prévias no log do teste de fumaça)
- [x] Release `v1.0.0-beta.27` com um único `.zip` (o do Mac); links fixos `mac` e `windows` respondendo
