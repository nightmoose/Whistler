import Foundation

enum Yin {
    struct Result {
        var frequency: Double?
        var confidence: Double
        var tau: Double?
    }

    static func rms(_ samples: UnsafeBufferPointer<Float>) -> Double {
        var sum: Double = 0
        for i in 0..<samples.count {
            let v = Double(samples[i])
            sum += v * v
        }
        return sqrt(sum / Double(max(samples.count, 1)))
    }

    static func rms(_ samples: [Float]) -> Double {
        samples.withUnsafeBufferPointer { rms($0) }
    }

    /// YIN fundamental-frequency estimator (de Cheveigné & Kawahara, 2002).
    static func pitch(
        samples: UnsafeBufferPointer<Float>,
        sampleRate: Double,
        minFreq: Double = 80,
        maxFreq: Double = 5000,
        threshold: Double = 0.12
    ) -> Result {
        let n = samples.count
        let tauMin = max(2, Int(floor(sampleRate / maxFreq)))
        let tauMax = min(n / 2 - 1, Int(floor(sampleRate / minFreq)))
        if tauMax <= tauMin + 2 {
            return Result(frequency: nil, confidence: 0, tau: nil)
        }

        var d = [Float](repeating: 0, count: tauMax + 1)
        for tau in 1...tauMax {
            var sum: Float = 0
            let limit = n - tau
            for i in 0..<limit {
                let delta = samples[i] - samples[i + tau]
                sum += delta * delta
            }
            d[tau] = sum
        }

        var cmndf = [Float](repeating: 0, count: tauMax + 1)
        cmndf[0] = 1
        var running: Float = 0
        for tau in 1...tauMax {
            running += d[tau]
            cmndf[tau] = running > 0 ? (d[tau] * Float(tau)) / running : 1
        }

        var tauEstimate = -1
        var tau = tauMin
        while tau < tauMax {
            if cmndf[tau] < Float(threshold) {
                while tau + 1 <= tauMax && cmndf[tau + 1] < cmndf[tau] {
                    tau += 1
                }
                tauEstimate = tau
                break
            }
            tau += 1
        }

        if tauEstimate < 0 {
            var minVal: Float = 1
            var minTau = -1
            for t in tauMin...tauMax {
                if cmndf[t] < minVal {
                    minVal = cmndf[t]
                    minTau = t
                }
            }
            if minVal < 0.28 {
                tauEstimate = minTau
            } else {
                return Result(frequency: nil, confidence: 0, tau: nil)
            }
        }

        var betterTau = Double(tauEstimate)
        if tauEstimate > 0 && tauEstimate < tauMax {
            let s0 = Double(cmndf[tauEstimate - 1])
            let s1 = Double(cmndf[tauEstimate])
            let s2 = Double(cmndf[tauEstimate + 1])
            let denom = 2 * (2 * s1 - s2 - s0)
            if abs(denom) > 1e-12 {
                betterTau = Double(tauEstimate) + (s2 - s0) / denom
            }
        }

        if betterTau <= 0 {
            return Result(frequency: nil, confidence: 0, tau: nil)
        }

        return Result(
            frequency: sampleRate / betterTau,
            confidence: Double(1 - cmndf[tauEstimate]),
            tau: betterTau
        )
    }

    static func pitch(
        samples: [Float],
        sampleRate: Double,
        minFreq: Double = 80,
        maxFreq: Double = 5000,
        threshold: Double = 0.12
    ) -> Result {
        samples.withUnsafeBufferPointer {
            pitch(samples: $0, sampleRate: sampleRate, minFreq: minFreq, maxFreq: maxFreq, threshold: threshold)
        }
    }
}
