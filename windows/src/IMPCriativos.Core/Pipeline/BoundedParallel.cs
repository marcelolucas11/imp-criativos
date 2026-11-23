namespace IMPCriativos.Core.Pipeline;

/// <summary>
/// 1.0.0-beta.19: roda vários trabalhos ao mesmo tempo, com um limite que pode mudar no meio.
///
/// Usado nas variações de um criativo (saem juntas até o limite da fila da IA, que o Modo rápido com segurança ajusta)
/// e no Otimizador em Lote. Garantias, conferidas nos testes automáticos:
/// - cada item roda exatamente uma vez, e nunca mais que <c>limit()</c> ao mesmo tempo (o limite é relido a cada vaga);
/// - o acompanhamento (<c>followUp</c>, ex.: a checagem do texto) roda sem ocupar vaga de imagem;
/// - cancelado (Pausar, fechar o app), não começa nada novo e espera os que estão rodando terminarem.
/// </summary>
public static class BoundedParallel
{
    public static async Task Run<TItem, TFollow>(
        IReadOnlyList<TItem> items,
        Func<Task<int>> limit,
        Func<TItem, Task<TFollow?>> work,
        Func<TFollow, Task> followUp,
        CancellationToken ct = default) where TFollow : class
    {
        if (items.Count == 0) return;
        var queue = new Queue<TItem>(items);
        var workers = new List<Task<TFollow?>>();
        var follows = new List<Task>();
        while (true)
        {
            if (!ct.IsCancellationRequested && queue.Count > 0)
            {
                var cap = Math.Max(1, await limit());
                while (workers.Count < cap && queue.Count > 0)
                {
                    var item = queue.Dequeue();
                    workers.Add(Task.Run(() => work(item)));
                }
            }
            var all = workers.Cast<Task>().Concat(follows).ToList();
            if (all.Count == 0) break;
            var done = await Task.WhenAny(all);
            if (done is Task<TFollow?> w && workers.Remove(w))
            {
                TFollow? follow = null;
                try { follow = await w; } catch { }
                if (follow != null && !ct.IsCancellationRequested)
                {
                    var f = follow;
                    follows.Add(Task.Run(() => followUp(f)));
                }
            }
            else
            {
                follows.Remove(done);
                try { await done; } catch { }
            }
        }
    }

    /// <summary>Atalho com limite fixo.</summary>
    public static Task Run<TItem, TFollow>(IReadOnlyList<TItem> items, int limit, Func<TItem, Task<TFollow?>> work,
        Func<TFollow, Task> followUp, CancellationToken ct = default) where TFollow : class =>
        Run(items, () => Task.FromResult(limit), work, followUp, ct);
}
