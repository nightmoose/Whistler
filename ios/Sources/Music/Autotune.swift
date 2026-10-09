import Foundation

enum Autotune {
    struct Key: Equatable {
        var tonic: Int
        var isMinor: Bool

        var name: String {
            let letter = Notes.sharp[tonic]
            return isMinor ? "\(letter) minor" : "\(letter) major"
        }

        var pitchClasses: Set<Int> {
            let steps = isMinor ? [0, 2, 3, 5, 7, 8, 10] : [0, 2, 4, 5, 7, 9, 11]
            return Set(steps.map { ($0 + tonic) % 12 })
        }
    }

    /// Round with a flat-friendly window: ~65¢ below still belongs to the note above.
    static func biasedRound(_ raw: Double) -> Int {
        Int(floor(raw + 0.65))
    }

    /// Krumhansl-Kessler key profiles, rotated so index 0 is the tonic.
    private static let majorProfile: [Double] = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
    private static let minorProfile: [Double] = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]

    static func detectKey(notes: [NoteEvent]) -> Key? {
        guard notes.count >= 3 else { return nil }
        var best: (key: Key, score: Double)?
        for tonic in 0..<12 {
            for isMinor in [false, true] {
                let profile = isMinor ? minorProfile : majorProfile
                var score = 0.0
                for note in notes {
                    let pc = ((biasedRound(note.rawMidi) % 12) + 12) % 12
                    let degree = (pc - tonic + 12) % 12
                    score += profile[degree] * max(0.05, note.duration)
                }
                if !isMinor { score *= 1.12 }
                if best == nil || score > best!.score {
                    best = (Key(tonic: tonic, isMinor: isMinor), score)
                }
            }
        }
        return best?.key
    }

    static func snap(_ rawMidi: Double, to key: Key) -> Int {
        let lo = Int(floor(rawMidi)) - 4
        let hi = Int(floor(rawMidi)) + 4
        var bestMidi = biasedRound(rawMidi)
        var bestDist = abs(Double(bestMidi) - rawMidi)
        var bestInKey = key.pitchClasses.contains(pc(bestMidi))

        for midi in lo...hi {
            guard key.pitchClasses.contains(pc(midi)) else { continue }
            let dist = abs(Double(midi) - rawMidi)
            let closer = dist + 0.001 < bestDist
            let tieGoUp = abs(dist - bestDist) <= 0.001 && midi > bestMidi
            if !bestInKey || closer || tieGoUp {
                bestMidi = midi
                bestDist = dist
                bestInKey = true
            }
        }
        return bestMidi
    }

    static func apply(_ notes: [NoteEvent], enabled: Bool) -> (notes: [NoteEvent], key: Key?) {
        let key = detectKey(notes: notes)
        var out = notes
        for i in out.indices {
            guard !out[i].locked else { continue }
            let midi: Int
            if enabled, let key {
                midi = snap(out[i].rawMidi, to: key)
            } else {
                midi = Int(round(out[i].rawMidi))
            }
            out[i].midi = midi
            out[i].frequency = Notes.midiToFreq(midi)
        }
        return (out, enabled ? key : nil)
    }

    private static func pc(_ midi: Int) -> Int {
        ((midi % 12) + 12) % 12
    }
}
