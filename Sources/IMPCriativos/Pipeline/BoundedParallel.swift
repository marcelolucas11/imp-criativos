import Foundation

/// Resultado interno de cada tarefa do `BoundedParallel`.
/// Os resultados só circulam dentro do grupo de tarefas do `run` (sem estado compartilhado).
enum BoundedParallelOutcome<Follow>: @unchecked Sendable {
    case worked(Follow?)
    case followed
}

/// 1.0.0-beta.19: roda vários trabalhos ao mesmo tempo, com um limite que pode mudar no meio.
///
/// Usado nas variações de um criativo: antes elas saíam uma de cada vez; agora saem juntas até o limite
/// da fila da IA (que o Modo rápido com segurança ajusta). Garantias, conferidas nos testes automáticos:
/// - cada item roda exatamente uma vez, e nunca mais que `limit()` ao mesmo tempo (o limite é relido a cada vaga);
/// - o acompanhamento (`followUp`, ex.: a checagem do texto) roda sem ocupar vaga de imagem;
/// - cancelado (Pausar, fechar o app), não começa nada novo e espera os que estão rodando terminarem.
///
/// Arquivo puro (só Foundation) para rodar nos testes automáticos sem o app.
enum BoundedParallel {
    static func run<Item, Follow>(
        _ items: [Item],
        limit: @escaping @Sendable () async -> Int,
        work: @escaping @Sendable (Item) async -> Follow?,
        followUp: @escaping @Sendable (Follow) async -> Void
    ) async {
        guard !items.isEmpty else { return }
        await withTaskGroup(of: BoundedParallelOutcome<Follow>.self) { group in
            var queue = items[...]
            var inFlight = 0
            while true {
                if !Task.isCancelled, !queue.isEmpty {
                    let cap = max(1, await limit())
                    while inFlight < cap, let item = queue.popFirst() {
                        inFlight += 1
                        group.addTask { .worked(await work(item)) }
                    }
                }
                guard let outcome = await group.next() else { break }
                switch outcome {
                case let .worked(follow):
                    inFlight -= 1
                    if let follow, !Task.isCancelled {
                        group.addTask {
                            await followUp(follow)
                            return .followed
                        }
                    }
                case .followed:
                    break
                }
            }
        }
    }
}
