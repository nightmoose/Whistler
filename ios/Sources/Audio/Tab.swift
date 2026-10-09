import Foundation

struct TabHit {
    var string: Int
    var fret: Int
    var midi: Int
    var start: Double
    var duration: Double
}

struct GuitarTab {
    var hits: [TabHit]
    var octaveShift: Int
    var ascii: String

    var shiftLabel: String? {
        guard octaveShift != 0 else { return nil }
        let octaves = abs(octaveShift / 12)
        let dir = octaveShift < 0 ? "lower" : "higher"
        let plural = octaves == 1 ? "" : "s"
        return "Tab is \(octaves) octave\(plural) \(dir) than the whistle"
    }
}

enum Guitar {
    static let strings: [(name: String, midi: Int)] = [
        ("e", 64), ("B", 59), ("G", 55), ("D", 50), ("A", 45), ("E", 40),
    ]

    static func tab(from notes: [NoteEvent]) -> GuitarTab {
        let shift = octaveShift(for: notes)
        var hits: [TabHit] = []
        var preferFret = 3
        for note in notes {
            let midi = note.midi + shift
            guard let placed = place(midi: midi, preferFret: preferFret) else { continue }
            hits.append(
                TabHit(string: placed.string, fret: placed.fret, midi: midi, start: note.start, duration: note.duration)
            )
            preferFret = placed.fret
        }
        return GuitarTab(hits: hits, octaveShift: shift, ascii: render(hits))
    }

    private static func octaveShift(for notes: [NoteEvent]) -> Int {
        guard let maxMidi = notes.map(\.midi).max(), let minMidi = notes.map(\.midi).min() else { return 0 }
        var shift = 0
        var high = maxMidi
        var low = minMidi
        while high > 76 && low - 12 >= 40 {
            shift -= 12
            high -= 12
            low -= 12
        }
        while low < 40 {
            shift += 12
            high += 12
            low += 12
        }
        return shift
    }

    private static func place(midi: Int, preferFret: Int) -> (string: Int, fret: Int)? {
        var best: (string: Int, fret: Int, cost: Double)?
        for (index, string) in strings.enumerated() {
            let fret = midi - string.midi
            guard fret >= 0 && fret <= 20 else { continue }
            let extra = fret > 12 ? Double(fret - 12) : 0
            let cost = abs(Double(fret - preferFret)) + Double(index) * 0.15 + extra
            if best == nil || cost < best!.cost {
                best = (index, fret, cost)
            }
        }
        return best.map { ($0.string, $0.fret) }
    }

    private static func render(_ hits: [TabHit], colsPerSecond: Double = 8) -> String {
        if hits.isEmpty {
            return strings.map { "\($0.name)|--|" }.joined(separator: "\n")
        }
        let last = hits.last!
        let totalTime = last.start + last.duration
        let cols = max(8, Int(ceil(totalTime * colsPerSecond)) + 4)
        var rows = Array(repeating: Array(repeating: "-", count: cols), count: strings.count)
        for hit in hits {
            let col = min(cols - 2, max(0, Int(round(hit.start * colsPerSecond))))
            let label = Array(String(hit.fret))
            for (i, ch) in label.enumerated() where col + i < cols {
                rows[hit.string][col + i] = String(ch)
            }
        }
        return strings.enumerated().map { "\($1.name)|\(rows[$0].joined())|" }.joined(separator: "\n")
    }
}
