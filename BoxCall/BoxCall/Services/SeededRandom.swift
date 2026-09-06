import Foundation

/// Deterministic random source (SplitMix64).
///
/// The market-making agents need *some* jitter so the tape looks alive,
/// but a test that cannot reproduce a quote is not a test. Every agent
/// takes a generator by `inout` reference; production passes a
/// clock-seeded one, tests pass a fixed seed and get byte-identical
/// quotes every run.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        // Avoid the all-zero state, which SplitMix64 handles fine but
        // which makes the first few draws look suspiciously patterned.
        self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    /// Seeds from a string (a contract id, say) so each contract gets
    /// its own reproducible stream without the caller inventing numbers.
    init(seed string: String) {
        var h: UInt64 = 0xCBF29CE484222325          // FNV-1a offset basis
        for byte in string.utf8 {
            h ^= UInt64(byte)
            h = h &* 0x100000001B3                  // FNV-1a prime
        }
        self.init(seed: h)
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    /// Uniform double in [0, 1).
    mutating func unit() -> Double {
        // Top 53 bits give a double with full mantissa precision.
        Double(next() >> 11) * (1.0 / 9007199254740992.0)
    }

    /// Uniform double in the given closed-ish range.
    mutating func double(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + unit() * (range.upperBound - range.lowerBound)
    }

    /// Symmetric jitter in [-magnitude, +magnitude].
    mutating func jitter(_ magnitude: Double) -> Double {
        double(in: -magnitude...magnitude)
    }
}

extension SeededGenerator {
    /// A generator seeded from the wall clock. Use in production paths
    /// where reproducibility does not matter.
    static func live() -> SeededGenerator {
        SeededGenerator(seed: UInt64(bitPattern: Int64(Date().timeIntervalSince1970 * 1_000_000)))
    }
}
