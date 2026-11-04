<p align="center">
  <img src="Resources/AppIcon-1024.png" width="128" alt="IMP Criativos">
</p>

<h1 align="center">IMP Criativos</h1>

<p align="center">App para Mac que remove a marca de criativos e gera variações em lote com IA (Gemini ou GPT).</p>

---

## O que faz

1. **Lê uma pasta** de criativos (JPG, PNG, WEBP, HEIC).
2. **Limpa** cada criativo: remove logo, nome da empresa, @, site, telefone, CNPJ — a lista é editável por cliente.
3. **Confere** a limpeza e transcreve o texto do criativo.
4. **Gera N variações** de cada um, cada uma num eixo diferente (fundo, composição, iluminação, ângulo…), mantendo o texto exato.
5. **Confere o texto** de cada variação e marca divergências.
6. **Fila de revisão**: aprovar, refazer (com observação) ou descartar.
7. **Baixa os aprovados** no tamanho original de cada criativo ou num tamanho fixo (1080×1080, 1080×1350, 1080×1920 ou personalizado).

Exemplo: 50 criativos × 4 variações = **50 limpos + 200 variações**.

## Instalar

1. Baixe o `.dmg` da [última versão](../../releases).
2. Arraste o **IMP Criativos** para **Aplicativos**.
3. Na primeira vez: **clique direito no app → Abrir → Abrir**.
   (Ou Ajustes do Sistema → Privacidade e Segurança → "Abrir Mesmo Assim".)
4. Em **Configurações → Chaves de API**, cole sua chave do Gemini e/ou da OpenAI.

Requisitos: macOS 14 (Sonoma) ou superior, Mac com Apple Silicon (M1 em diante).

Guia completo: [docs/INSTALACAO.md](docs/INSTALACAO.md)

## Atualizar

Dentro do app: **Configurações → Atualizações → Buscar atualização → Instalar e reiniciar**.
O app baixa a versão nova daqui do GitHub, confere a integridade e se substitui.

## Privacidade

- **Chaves de API**: Keychain do seu Mac. Nunca saem dele (exceto para o próprio Google/OpenAI).
- **Perfis de clientes, lotes e imagens**: `~/Library/Application Support/IMP Criativos/` e as pastas que você escolher.
- **Este repositório** contém só código e prompts genéricos. Nenhum dado de cliente.

## Para desenvolvedores

Arquitetura: [docs/ARQUITETURA.md](docs/ARQUITETURA.md) · Histórico: [CHANGELOG.md](CHANGELOG.md)

```bash
brew install xcodegen
xcodegen generate
open IMPCriativos.xcodeproj
```

Publicar versão: atualize o `CHANGELOG.md`, crie a tag `vX.Y.Z` (ou `vX.Y.Z-beta.N`) e envie. O GitHub Actions compila e publica a Release.

© 2026 Impera Services
