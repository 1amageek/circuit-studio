import Foundation

/// Threshold-crossing measurements on a sampled transient waveform — the primitives the
/// timing characterizer and the STA-vs-SPICE validator use to extract propagation delay
/// (50%→50%) and output transition/slew (e.g. 20%↔80%) from CoreSpice output. Operates on
/// raw (time, value) arrays so it is testable without a simulator.
public enum WaveformTiming {

    public enum Direction: Sendable { case rising, falling }

    /// The interpolated time of the first `threshold` crossing in `direction` strictly
    /// after `after`. Returns nil if the wave never crosses that way.
    public static func crossing(
        times: [Double], values: [Double], threshold: Double,
        direction: Direction, after: Double = -.infinity
    ) -> Double? {
        let n = min(times.count, values.count)
        guard n >= 2 else { return nil }
        for i in 1..<n {
            let t0 = times[i - 1], t1 = times[i]
            if t1 <= after { continue }
            let a = values[i - 1], b = values[i]
            let crosses: Bool
            switch direction {
            case .rising: crosses = a < threshold && b >= threshold
            case .falling: crosses = a > threshold && b <= threshold
            }
            guard crosses else { continue }
            let dv = b - a
            let frac = dv == 0 ? 0 : (threshold - a) / dv
            let t = t0 + frac * (t1 - t0)
            if t > after { return t }
        }
        return nil
    }

    /// Propagation delay: the (signed) time from the input crossing 50% in `inputDirection`
    /// to the output crossing 50% in `outputDirection`, both being the first such crossings
    /// after the window start `after`. The output edge is located within the same window
    /// (not forced to be after the input edge), so a slow input into a lightly loaded gate —
    /// whose output can cross 50% before the input does — yields the correct small/negative
    /// delay rather than being missed. Returns nil if either edge is absent.
    public static func propagationDelay(
        inputTimes: [Double], inputValues: [Double],
        outputTimes: [Double], outputValues: [Double],
        mid: Double, inputDirection: Direction, outputDirection: Direction,
        after: Double = -.infinity
    ) -> Double? {
        guard let tIn = crossing(times: inputTimes, values: inputValues, threshold: mid,
                                 direction: inputDirection, after: after) else { return nil }
        guard let tOut = crossing(times: outputTimes, values: outputValues, threshold: mid,
                                  direction: outputDirection, after: after) else { return nil }
        return tOut - tIn
    }

    /// Output transition (slew): time between the `lower` and `upper` threshold crossings of
    /// one edge in `direction`, searched after `after`. For a rising edge that is
    /// lower→upper; for a falling edge it is upper→lower (the elapsed magnitude either way).
    public static func transition(
        times: [Double], values: [Double], lower: Double, upper: Double,
        direction: Direction, after: Double = -.infinity
    ) -> Double? {
        switch direction {
        case .rising:
            guard let tLo = crossing(times: times, values: values, threshold: lower, direction: .rising, after: after),
                  let tHi = crossing(times: times, values: values, threshold: upper, direction: .rising, after: tLo)
            else { return nil }
            return tHi - tLo
        case .falling:
            guard let tHi = crossing(times: times, values: values, threshold: upper, direction: .falling, after: after),
                  let tLo = crossing(times: times, values: values, threshold: lower, direction: .falling, after: tHi)
            else { return nil }
            return tLo - tHi
        }
    }
}
