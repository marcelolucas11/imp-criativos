# Regras do repositório IMP Criativos

O app existe em **duas versões**: Mac (Swift, `Sources/` e `Tests/`) e Windows (C# .NET 10 + WPF, `windows/`).

- **Toda mudança de função, prompt, texto ou tela vale para as duas versões no mesmo PR.** Não deixe uma versão para depois.
- **Prompts e textos** ficam idênticos nos dois lados. O CI do Mac gera `windows/tests/IMPCriativos.Tests/fixtures/paridade-mac.json` a partir do código Swift (`scripts/paridade/`) e o `ParidadeMacTests` compara com o C#. Mudou um prompt ou o sorteio do Otimizador? Atualize os dois lados e o fixture (o log do job do Mac imprime o arquivo em `PARIDADE-B64:`).
- **Eixos de variação** só mudam pelo `scripts/eixos_variacao.py`, que gera `DefaultAxes.swift`, `DefaultAxes.cs` e `docs/EIXOS-DE-VARIACAO.md`. O CI falha se o gerado não estiver em dia.
- **Formatos de arquivo** (`.impcliente`, `job.json`, preferências) seguem os nomes do `Codable` do Swift. Campo novo: os dois lados, com leitura tolerante.
- **`docs/WINDOWS-PLANO.md`** precisa continuar atualizado (tabela Swift → C# e checklist).
- **Releases:** a Release `vX.Y.Z` tem **um único `.zip`**, o do Mac (o atualizador do Mac pega o primeiro `.zip`). O Windows sobe só `IMP-Criativos-Setup-X.Y.Z-windows-x64.exe` e `.exe.sha256`. As tags fixas `mac` e `windows` não são versões e os dois atualizadores as ignoram.
- **Privacidade:** nenhum dado de cliente, chave de API ou imagem real no repositório.
- Textos do app só em **português do Brasil**. No Windows, ⌘ vira Ctrl.
- Publicar versão: seção no `CHANGELOG.md` + número no `VERSION`, na `main`.
