import XCTest

/// Regras do Modo rápido com segurança (1.0.0-beta.19).
final class SpeedPolicyTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    /// Respostas boas na velocidade original e depois no nível atual, com o mesmo tempo por imagem.
    private func warm(_ p: inout SpeedPolicy, seconds: Double = 40, count: Int, at now: Date) {
        for _ in 0..<count { p.recordSuccess(seconds: seconds, now: now) }
    }

    func testStartsAtOriginalSpeed() {
        let p = SpeedPolicy(base: 2, ceiling: 5, fast: true)
        XCTAssertEqual(p.limit, 2)
    }

    func testRaisesOneStepAtATimeUpToCeiling() {
        var p = SpeedPolicy(base: 2, ceiling: 4, fast: true)
        warm(&p, count: 3, at: t0)
        XCTAssertEqual(p.limit, 3, "sobe depois de 3 respostas boas com referência medida")
        warm(&p, count: 3, at: t0)
        XCTAssertEqual(p.limit, 4)
        warm(&p, count: 10, at: t0)
        XCTAssertEqual(p.limit, 4, "nunca passa do teto")
    }

    func testNeverRaisesWhenFastModeIsOff() {
        var p = SpeedPolicy(base: 2, ceiling: 6, fast: false)
        warm(&p, count: 20, at: t0)
        XCTAssertEqual(p.limit, 2)
    }

    func testTroubleReturnsToOriginalAndHoldsForTenMinutes() {
        var p = SpeedPolicy(base: 2, ceiling: 5, fast: true)
        warm(&p, count: 6, at: t0)
        XCTAssertEqual(p.limit, 4)
        let change = p.recordTrouble("IA ocupada (HTTP 503)", now: t0)
        XCTAssertEqual(change, .lowered(to: 2, reason: "IA ocupada (HTTP 503)"))
        XCTAssertEqual(p.limit, 2)
        XCTAssertTrue(p.isSafeMode(now: t0.addingTimeInterval(60)))
        warm(&p, count: 10, at: t0.addingTimeInterval(9 * 60))
        XCTAssertEqual(p.limit, 2, "não sobe durante o modo seguro")
        warm(&p, count: 3, at: t0.addingTimeInterval(11 * 60))
        XCTAssertEqual(p.limit, 3, "volta a subir depois do modo seguro")
    }

    func testRepeatedTroubleHoldsForThirtyMinutes() {
        var p = SpeedPolicy(base: 2, ceiling: 5, fast: true)
        p.recordTrouble("429", now: t0)
        p.recordTrouble("429", now: t0.addingTimeInterval(60))
        p.recordTrouble("429", now: t0.addingTimeInterval(120))
        XCTAssertTrue(p.isSafeMode(now: t0.addingTimeInterval(25 * 60)))
        XCTAssertEqual(p.risk(now: t0.addingTimeInterval(180)), .high)
    }

    func testStepsDownWhenMoreRequestsDoNotPayOff() {
        var p = SpeedPolicy(base: 2, ceiling: 5, fast: true)
        warm(&p, seconds: 40, count: 3, at: t0)
        XCTAssertEqual(p.limit, 3)
        // com 3 pedidos, cada imagem passou a levar o dobro: 3/2 ÷ 2 = 0,75 → não compensa
        for _ in 0..<6 { p.recordSuccess(seconds: 80, now: t0) }
        XCTAssertEqual(p.limit, 2)
    }

    func testMacHoldKeepsOriginalSpeed() {
        var p = SpeedPolicy(base: 2, ceiling: 5, fast: true)
        warm(&p, count: 3, at: t0)
        XCTAssertEqual(p.limit, 3)
        XCTAssertEqual(p.setMacHold("o Mac está quente"), .lowered(to: 2, reason: "o Mac está quente"))
        warm(&p, count: 10, at: t0)
        XCTAssertEqual(p.limit, 2)
        XCTAssertEqual(p.risk(now: t0), .high)
        p.setMacHold(nil)
        warm(&p, count: 3, at: t0)
        XCTAssertEqual(p.limit, 3)
    }

    func testTurningFastModeOffDropsToOriginal() {
        var p = SpeedPolicy(base: 2, ceiling: 5, fast: true)
        warm(&p, count: 6, at: t0)
        XCTAssertEqual(p.limit, 4)
        p.configure(base: 2, ceiling: 5, fast: false)
        XCTAssertEqual(p.limit, 2)
        p.configure(base: 3, ceiling: 2, fast: true)
        XCTAssertEqual(p.limit, 3, "teto nunca fica abaixo da velocidade original")
        XCTAssertEqual(p.ceiling, 3)
    }

    func testLimitAlwaysWithinBounds() {
        var p = SpeedPolicy(base: 2, ceiling: 6, fast: true)
        var rng = SystemRandomNumberGenerator()
        var now = t0
        for _ in 0..<2000 {
            now = now.addingTimeInterval(Double.random(in: 1...120, using: &rng))
            switch Int.random(in: 0..<10, using: &rng) {
            case 0: p.recordTrouble("teste", now: now)
            case 1: p.setMacHold(Bool.random() ? "quente" : nil)
            default: p.recordSuccess(seconds: Double.random(in: 10...200, using: &rng), now: now)
            }
            XCTAssertGreaterThanOrEqual(p.limit, p.base)
            XCTAssertLessThanOrEqual(p.limit, p.ceiling)
        }
    }
}
