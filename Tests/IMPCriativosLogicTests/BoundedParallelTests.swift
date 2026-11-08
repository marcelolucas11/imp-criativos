import XCTest

/// Contador seguro entre tarefas.
actor Probe {
    var running = 0
    var peak = 0
    var worked: [Int] = []
    var followed: [Int] = []
    func start() { running += 1; peak = max(peak, running) }
    func end(_ i: Int) { running -= 1; worked.append(i) }
    func follow(_ i: Int) { followed.append(i) }
}

actor Dial {
    var value: Int
    init(_ v: Int) { value = v }
    func set(_ v: Int) { value = v }
}

/// Variações em paralelo com limite (1.0.0-beta.19), com uma "IA de mentira" que demora e às vezes falha.
final class BoundedParallelTests: XCTestCase {
    private static func fakeAI(_ i: Int) async {
        try? await Task.sleep(nanoseconds: UInt64.random(in: 2_000_000...15_000_000))
    }

    func testEveryItemRunsExactlyOnceAndRespectsLimit() async {
        let probe = Probe()
        let items = Array(1...50)
        await BoundedParallel.run(items, limit: { 4 }, work: { i -> Int? in
            await probe.start()
            await Self.fakeAI(i)
            await probe.end(i)
            return i % 7 == 0 ? nil : i // múltiplos de 7 "falham": sem checagem
        }, followUp: { i in await probe.follow(i) })

        let worked = await probe.worked.sorted()
        let followed = await probe.followed.sorted()
        let peak = await probe.peak
        XCTAssertEqual(worked, items, "nenhuma variação perdida nem repetida")
        XCTAssertEqual(followed, items.filter { $0 % 7 != 0 }, "checagem só das que deram certo, uma vez cada")
        XCTAssertLessThanOrEqual(peak, 4)
        XCTAssertGreaterThan(peak, 1, "roda em paralelo de verdade")
    }

    func testLimitChangesMidway() async {
        let probe = Probe()
        let dial = Dial(5)
        await BoundedParallel.run(Array(1...40), limit: { await dial.value }, work: { i -> Int? in
            await probe.start()
            if i == 10 { await dial.set(1) } // segurança: volta para 1 por vez
            await Self.fakeAI(i)
            await probe.end(i)
            return nil
        }, followUp: { _ in })
        let worked = await probe.worked.count
        XCTAssertEqual(worked, 40)
    }

    func testCancelStopsNewWorkAndKeepsNothingRunning() async {
        let probe = Probe()
        let task = Task {
            await BoundedParallel.run(Array(1...100), limit: { 3 }, work: { i -> Int? in
                await probe.start()
                try? await Task.sleep(nanoseconds: 20_000_000)
                await probe.end(i)
                return i
            }, followUp: { i in await probe.follow(i) })
        }
        try? await Task.sleep(nanoseconds: 60_000_000)
        task.cancel()
        await task.value
        let worked = await probe.worked.count
        let running = await probe.running
        XCTAssertLessThan(worked, 100, "pausar não começa variações novas")
        XCTAssertEqual(running, 0, "nada fica rodando depois de pausar")
    }

    func testEmptyListReturns() async {
        await BoundedParallel.run([Int](), limit: { 2 }, work: { _ -> Int? in nil }, followUp: { _ in })
    }
}
