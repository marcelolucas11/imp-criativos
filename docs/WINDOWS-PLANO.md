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
  tests/fixtures/             arquivos de exemplo (.impcliente, job.json) e paridade com o Mac
  installer/IMPCriativos.iss  Inno Setup 6
```

## Paridade com o Mac verificada pelo CI

| O que | Como |
|---|---|
| Prompts (todos os textos enviados às IAs) | O job do Mac (`ci.yml`) compila `scripts/paridade/main.swift` junto com o código Swift e gera `windows/tests/fixtures/paridade-mac.json`. O teste `ParidadeMacTests` gera os mesmos prompts em C# e compara caractere por caractere. |
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
| `Storage/APIKeyStore.swift` | `Core/Storage/ApiKeyStore.cs` + `App/Services/DpapiProtector.cs` | `chaves.json` cifrado com DPAPI (CurrentUser) |
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
| `Updater/Updater.swift` | `Core/Updater/Updater.cs` | instalador `.exe` + `.exe.sha256` |
| `System/SystemServices.swift` | `App/Services/*.cs` | Run do HKCU, toast, seletores |
| `App/*.swift` | `App/App.xaml(.cs)`, `App/AppModel.cs` | instância única (Mutex), bandeja |
| `Views/Components.swift` | `App/Themes/Brand.xaml` | cores do tema escuro |
| `Views/ContentView.swift` | `App/MainWindow.xaml` | menu lateral |
| `Views/HomeView.swift` | `App/Views/HomeView.xaml` | |
| `Views/NewJobView.swift` | `App/Views/NewJobView.xaml` | inclui Limpar logo |
| `Views/JobDetailView.swift` | `App/Views/JobDetailView.xaml` | revisão |
| `Views/ClientsView.swift` + `AxisPickers.swift` | `App/Views/ClientsView.xaml` + `AxisPickerWindow.xaml` | |
| `Views/StoryOptimizerView.swift` | `App/Views/StoryOptimizerView.xaml` | |
| `Views/StoryInspectorView.swift` | `App/Views/StoryInspectorWindow.xaml` | zoom sem suavização |
| `Views/LogsView.swift` | `App/Views/LogsView.xaml` | |
| `Views/SettingsView.swift` + `ModelMenu.swift` | `App/Views/SettingsView.xaml` | |
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
- **Atualização**: o Windows baixa o instalador (`.exe`) e roda em modo silencioso; o Mac troca o `.app`.

## Checklist de paridade

Legenda: [x] pronto · [~] parcial · [ ] falta

### Fase 1 — leitura e plano
- [x] Leitura de `Sources/`, `docs/`, `scripts/`, `.github/`
- [x] Este arquivo

### Fase 2 — solução e Core básico
- [ ] Solução com 3 projetos
- [ ] Modelos com JSON compatível com o `Codable` (UUID maiúsculo, data ISO 8601 sem fração, enums por nome)
- [ ] `OutputSizeMode` no formato do Swift (`{"fixed":{"width":…,"height":…}}` / `{"original":{}}`)
- [ ] Teste de ida e volta com `.impcliente` e `job.json` de exemplo
- [ ] `Paths`, `Preferences` (`preferencias.json`)
- [ ] Chaves com DPAPI
- [ ] Histórico (logs por mês, 6 meses)
- [ ] Eixos gerados em C# pelo script + checagem no CI
- [ ] CI: `windows-latest` e `ubuntu-latest`

### Fase 3 — IA e pipeline
- [ ] `Http` (tentativas, espera crescente, Retry-After, prazo por tentativa)
- [ ] `ProviderGate`, `SpeedPolicy`, `SpeedMonitor`
- [ ] `BoundedParallel`
- [ ] Gemini (Interactions API, variantes, filtros desligados, tentativa neutra)
- [ ] OpenAI (images/edits multipart, chat/completions)
- [ ] `Prompts`, `CreativePlanner`, `ForbiddenTerms`, `InstructionInterpreter`
- [ ] `JobRunner` (planejamento, limpeza, análise, refação 1x, variações, checagem, reserva, disjuntor, vigia, retomada)
- [ ] `Exporter` + `CostEstimator`
- [ ] Testes de `SpeedPolicy` e `BoundedParallel` portados
- [ ] Paridade dos prompts com o Mac (fixture)

### Fase 4 — Otimizador em Lote
- [ ] `StoryOptimizerParams` (SplitMix64, sorteio, presets, migrações da beta.26, nomes, versões, cor dominante)
- [ ] Paridade do sorteio com o Mac (fixture)
- [ ] `StoryTextureEffects` (linhas Tom e Gravura, serrilhado)
- [ ] Motor Skia (enquadramentos, recorte/rotação, perspectiva, cor, temperatura, nitidez, canal, grão, riscos, vinheta, aberração, bloom, ruído)
- [ ] JPEG pela libjpeg-turbo (qualidade, subamostragem, progressivo, ICC sRGB) e PNG limpo
- [ ] `StoryBatch` (fila 4 por vez, cancelar, pasta `stories_data_hora`, ZIP)
- [ ] Testes de `StoryOptimizerParamsTests`, `StoryTextureTests` e `StoryOptimizerImageTests` portados

### Fase 5 — App WPF
- [ ] Tema escuro e menu lateral
- [ ] Início
- [ ] Novo lote (Normal / Teste de eixos, IA por etapa, tamanho, estimativa, confirmação > 60, instruções com conferência)
- [ ] Limpar logo
- [ ] Lotes e revisão (aprovar, refazer com observação, descartar, aprovar pendentes, ver grande, comparar)
- [ ] Baixar aprovados
- [ ] Clientes (O que remover, eixos, Rodízio, Catálogo, Meus eixos, importar/exportar)
- [ ] Otimizador em Lote
- [ ] Inspecionar Antes / Depois
- [ ] Histórico
- [ ] Configurações (chaves, modelos, avisos, velocidade, segundo plano, iniciar com o Windows, atualizações)
- [ ] Bandeja com o menu da barra de menus, instância única
- [ ] Notificações (toast, balão de reserva)
- [ ] OCR local e HEIC
- [ ] Atualizador
- [ ] `--smoke-test` com capturas

### Fase 6 — instalador e publicação
- [ ] Inno Setup
- [ ] `release.yml` (job `windows`, tag fixa `windows`, sem `.zip`)
- [ ] Botão Baixar para Windows, README, docs, `CLAUDE.md`, CHANGELOG

### Fase 7 — verificação
- [ ] CI verde (Mac, Windows, Linux)
- [ ] Capturas conferidas
- [ ] Release `v1.0.0-beta.27` com um único `.zip`
