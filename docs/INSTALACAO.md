# Instalação e primeiro uso

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

Cole, clique em **Salvar** e depois em **Testar**. A chave fica no Keychain do Mac.

Se depois de uma atualização o macOS perguntar se o IMP Criativos pode acessar o Keychain, clique em **Permitir Sempre**.

## 3. Criar um cliente

Em **Clientes**:

- **O que remover:** seja específico — nome exato da empresa, @ do Instagram, descrição da logo.
- **Eixos de variação:** cada variação usa um eixo (v1 = 1º eixo, v2 = 2º…). Os padrões já funcionam.
- **Instruções extras:** regras que valem sempre (ex.: "não mudar a cor do carro").
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
| "modelo não encontrado" | O provedor trocou o nome do modelo: atualize em Configurações → Modelos de IA |
| Atualização pede para mover o app | Mova o app para Aplicativos e abra de lá |
| Texto saiu errado numa variação | Use ↻ com a observação "manter o texto exatamente igual" ou troque a IA das variações para GPT |
