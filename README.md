<p align="center">
  <img src="Resources/AppIcon-1024.png" width="128" alt="IMP Criativos">
</p>

<h1 align="center">IMP Criativos</h1>

<p align="center">App para Mac que remove a marca de criativos de <b>cassino online e bet (apostas esportivas)</b> e gera variações em lote com IA (Gemini ou GPT).</p>

<p align="center">
  <a href="https://github.com/marcelolucas11/imp-criativos/releases/download/mac/IMP-Criativos.dmg">
    <img src="Resources/botao-baixar-mac.svg" width="340" alt="Baixar para Mac — IMP Criativos, versão mais nova">
  </a>
</p>

---

## Para quem é

O IMP Criativos é feito **somente para criativos de cassino online e apostas esportivas (bet)** de operadores autorizados no Brasil.
Todos os prompts das IAs partem desse contexto (`Sources/IMPCriativos/Models/Niche.swift`): o mesmo jogo ou esporte é mantido,
nenhuma odd, multiplicador, valor, bônus ou promessa de ganho é inventado, e os avisos **18+** e de **jogo responsável** são preservados.
Não é um app de uso geral nem para rifas ou sorteios.

## O que faz

1. **Lê uma pasta** de criativos (JPG, PNG, WEBP, HEIC).
2. **Limpa** cada criativo: remove logo, nome da empresa, @, site, telefone, CNPJ — a lista é editável por cliente.
3. **Confere** a limpeza e transcreve o texto do criativo.
4. **Gera N variações** de cada um, cada uma num **eixo de variação** diferente, mantendo o texto exato. O app já vem com **50 eixos de cassino e bet** ([lista](docs/EIXOS-DE-VARIACAO.md)), usados em rodízio pelos criativos do lote: cada variação sai com cara de peça nova, sem fugir do jogo ou esporte do original.
   - **Instruções por lote (opcional):** no Novo lote, escreva em texto livre o que quer (ex.: "tirar todo nome Aviator, adicionar o nome Y, ângulos bem variados"). O app separa em *remover*, *alterar texto* e *direção das variações*, mostra para você conferir e aplica cada parte na etapa certa.
5. **Confere o texto** de cada variação e marca divergências.
6. **Fila de revisão**: aprovar, refazer (com observação) ou descartar.
7. **Baixa os aprovados** nos tamanhos verticais padrão do Meta Ads: 1080×1350 (feed 4:5) ou 1080×1920 (stories e reels 9:16).

Exemplo: 50 criativos × 4 variações = **50 limpos + 200 variações**.

## Instalar

1. Clique em **Baixar para Mac** acima (ou baixe o `.dmg` de qualquer versão em [Releases](../../releases)).
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

- **Chaves de API**: arquivo `chaves.json` do app, legível só pela sua conta do Mac. Nunca saem dele (exceto para o próprio Google/OpenAI).
- **Perfis de clientes, lotes e imagens**: `~/Library/Application Support/IMP Criativos/` e as pastas que você escolher.
- **Este repositório** contém só código e prompts genéricos. Nenhum dado de cliente.

## Para desenvolvedores

Arquitetura: [docs/ARQUITETURA.md](docs/ARQUITETURA.md) · Histórico: [CHANGELOG.md](CHANGELOG.md)

```bash
brew install xcodegen
xcodegen generate
open IMPCriativos.xcodeproj
```

Publicar versão: escreva a seção no `CHANGELOG.md`, troque o número no arquivo `VERSION` (ex.: `1.0.0-beta.2`) e envie para a `main`. O GitHub Actions compila, cria a tag e publica a Release.

© 2026 Impera Services
