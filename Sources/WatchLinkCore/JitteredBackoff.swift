public enum JitteredBackoff: Sendable {
    public static func delay(attempt: Int, max maxDelay: Duration = .seconds(5)) -> Duration {
        let exponential = Duration.seconds(1 << min(attempt, 10))
        let clamped = min(exponential, maxDelay)
        let jitter = Duration.milliseconds(Int.random(in: 0...1000))
        return clamped + jitter
    }
}
