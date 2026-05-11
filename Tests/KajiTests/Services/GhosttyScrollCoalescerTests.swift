import Foundation
import Testing

@testable import Kaji

@Suite("GhosttyScrollCoalescer")
@MainActor
struct GhosttyScrollCoalescerTests {
    @Test("coalesces precise scroll bursts into one delivery")
    func coalescesPreciseScrollBursts() {
        var queued: [(TimeInterval, @MainActor () -> Void)] = []
        let coalescer = GhosttyScrollCoalescer { delay, action in
            queued.append((delay, action))
        }
        var delivered: [(Double, Double, Bool)] = []

        coalescer.push(x: 1, y: 2, precise: true) { delivered.append(($0, $1, $2)) }
        coalescer.push(x: 3, y: 4, precise: true) { delivered.append(($0, $1, $2)) }

        #expect(queued.count == 1)
        #expect(queued[0].0 == 1.0 / 120.0)
        queued.removeFirst().1()
        #expect(delivered.count == 1)
        #expect(delivered[0].0 == 4)
        #expect(delivered[0].1 == 6)
        #expect(delivered[0].2)
    }

    @Test("flushes before switching precision mode")
    func flushesBeforeSwitchingPrecisionMode() {
        var queued: [(TimeInterval, @MainActor () -> Void)] = []
        let coalescer = GhosttyScrollCoalescer { delay, action in
            queued.append((delay, action))
        }
        var delivered: [(Double, Double, Bool)] = []

        coalescer.push(x: 1, y: 2, precise: true) { delivered.append(($0, $1, $2)) }
        coalescer.push(x: 5, y: 6, precise: false) { delivered.append(($0, $1, $2)) }

        #expect(delivered.count == 1)
        #expect(delivered[0].0 == 1)
        #expect(delivered[0].1 == 2)
        #expect(delivered[0].2)

        #expect(queued.count == 1)
        queued.removeFirst().1()
        #expect(delivered.count == 2)
        #expect(delivered[1].0 == 5)
        #expect(delivered[1].1 == 6)
        #expect(!delivered[1].2)
    }

    @Test("non-precise flushes do not add batch delay")
    func nonPreciseFlushesWithoutDelay() {
        var queued: [(TimeInterval, @MainActor () -> Void)] = []
        let coalescer = GhosttyScrollCoalescer { delay, action in
            queued.append((delay, action))
        }
        var delivered: [(Double, Double, Bool)] = []

        coalescer.push(x: 5, y: 6, precise: false) { delivered.append(($0, $1, $2)) }

        #expect(queued.count == 1)
        #expect(queued[0].0 == 0)
        queued.removeFirst().1()
        #expect(delivered.count == 1)
        #expect(delivered[0].0 == 5)
        #expect(delivered[0].1 == 6)
        #expect(!delivered[0].2)
    }
}
