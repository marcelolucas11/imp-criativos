# Instalação e primeiro uso

> O IMP Criativos é feito **somente para criativos de cassino online e apostas esportivas (bet)**. Cassino é sempre online (jogos de celular, personagens 3D), nunca cassino físico.

## 1. Instalar

1. Baixe a versão mais nova pelo link fixo [IMP-Criativos.dmg](https://github.com/marcelolucas11/imp-criativos/releases/download/mac/IMP-Criativos.dmg) (o mesmo do botão **Baixar para Mac** no README). Versões anteriores ficam em [Releases](https://github.com/marcelolucas11/imp-criativos/releases).
2. Abra o `.dmg` e arraste **IMP Criativos** para a pasta **Aplicativos** (ou para outra pasta, como um SSD externo).
3. **Primeira abertura:** como o app não é distribuído pela App Store, o macOS mostra um aviso.
   - Clique com o botão direito no app → **Abrir** → **Abrir**; ou
   - tente abrir normalmente, depois vá em **Ajustes do Sistema → Privacidade e Segurança** e clique em **Abrir Mesmo Assim**.

   Isso só é necessário na primeira vez.

> Não rode o app de dentro do `.dmg`: o botão de atualizar precisa que ele esteja numa pasta normal.

## 2. Chaves de API

Em **Configurações → Chaves de API**:

| Provedor | Onde criar a chave |
|---|---|
| Gemini | [aistudio.google.com](https://aistudio.google.com) → Get API key |
| OpenAI | [platform.openai.com](https://platform.openai.com) → API keys |

Cole, clique em **Salvar** e depois em **Testar**. A chave fica salva só neste Mac, num arquivo que apenas a sua conta lê. O app não pede senha do Keychain.

## 3. Criar um cliente

Em **Clientes**:

- **O que remover:** seja específico — nome exato da casa de apostas, @ do Instagram, site (ex.: `minhabet.bet.br`), descrição da logo. Nomes de jogos que não podem aparecer vão entre aspas (ex.: `"Aviator"`): o app reescreve a frase de forma natural. Os avisos **18+**, **"Jogue com responsabilidade"** e advertências seguem a opção em **Configurações → Avisos do criativo**: desligada (padrão) o app remove; ligada, mantém.
- **Eixos de variação:** o cliente novo já vem com os [50 eixos de cassino e bet](EIXOS-DE-VARIACAO.md). Use **Catálogo do app** para marcar/desmarcar eixos do app (com família, o que muda, risco de texto e o prompt em "Ver mais") e **Meus eixos** para os que você criou. Com a chave **Rodízio** ligada (padrão), os eixos rodam entre os criativos do lote (com 4 variações: 1º criativo usa os eixos 1–4, o 2º usa 5–8…); desligada, todo criativo usa os primeiros da lista. Pedido de texto (tirar ou trocar palavras) não é eixo: vai em "O que remover" ou nas instruções do lote.
- **Instruções extras:** regras que valem sempre (ex.: "nunca mudar as odds nem o valor do bônus").
- **Exportar:** gera um arquivo `.impcliente` para enviar a outra pessoa, que importa com o botão de importar.

## 4. Rodar um lote

1. **Novo lote** → escolha o cliente e a pasta dos criativos.
2. Defina o número de variações, a IA de cada etapa e o tamanho de saída.
3. Confira a **estimativa de custo** e clique em **Iniciar lote**.

Pode fechar a janela: com "Continuar em segundo plano" ligado, o app vai para a barra de menus e avisa quando terminar.

## 5. Revisar e baixar

- Clique em qualquer imagem para ver grande e comparar com a referência.
- ✓ aprova · ↻ refaz (dá para escrever o que corrigir) · ✕ descarta.
- **Ações → Aprovar pendentes sem alerta** agiliza lotes grandes.
- **Baixar aprovados** salva tudo numa pasta `cliente/lote_data/` com nomes `cliente_criativo_v0.jpg`, `_v1`…

## Problemas comuns

| Sintoma | O que fazer |
|---|---|
| "Chave não configurada" | Configurações → Chaves de API |
| Muitas falhas com HTTP 429 | Limite da sua conta na API: reduza "Criativos processados ao mesmo tempo" |
| "modelo não encontrado" | O provedor trocou o nome do modelo: em Configurações → Modelos de IA, clique em "Atualizar lista de modelos" e escolha outro (ou defina uma reserva) |
| Atualização pede para mover o app | Mova o app para Aplicativos e abra de lá |
| Texto saiu errado numa variação | Use ↻ com a observação "manter o texto exatamente igual" ou troque a IA das variações para GPT |
