import Testing
@testable import WatchLinkCore

@Suite("JitteredBackoff")
struct JitteredBackoffTests {
    @Test("delay increases exponentially")
    func exponentialGrowth() {
        let d1 = JitteredBackoff.delay(attempt: 0, max: .seconds(30))
        let d2 = JitteredBackoff.delay(attempt: 1, max: .seconds(30))
        let d3 = JitteredBackoff.delay(attempt: 2, max: .seconds(30))

        #expect(d1 < d2)
        #expect(d2 < d3)
    }

    @Test("delay is clamped to max")
    func clamped() {
        let delay = JitteredBackoff.delay(attempt: 20, max: .seconds(5))
        #expect(delay <= .seconds(6)) // 5s max + up to 1s jitter
    }

    @Test("delay is never negative")
    func nonNegative() {
        for attempt in 0...10 {
            let delay = JitteredBackoff.delay(attempt: attempt)
            #expect(delay >= .zero)
        }
    }
}
