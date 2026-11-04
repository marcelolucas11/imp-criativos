# Histórico de versões

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
