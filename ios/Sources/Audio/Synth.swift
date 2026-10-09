import Foundation

struct SynthNote {
    var midi: Int
    var duration: Double
    var gap: Double = 0.05
}

enum Synth {
    static let demoMelody: [SynthNote] = [
        SynthNote(midi: 76, duration: 0.32),
        SynthNote(midi: 76, duration: 0.32),
        SynthNote(midi: 77, duration: 0.32),
        SynthNote(midi: 79, duration: 0.32),
        SynthNote(midi: 79, duration: 0.32),
        SynthNote(midi: 77, duration: 0.32),
        SynthNote(midi: 76, duration: 0.32),
        SynthNote(midi: 74, duration: 0.32),
        SynthNote(midi: 72, duration: 0.32),
        SynthNote(midi: 72, duration: 0.32),
        SynthNote(midi: 74, duration: 0.32),
        SynthNote(midi: 76, duration: 0.32),
        SynthNote(midi: 76, duration: 0.48),
        SynthNote(midi: 74, duration: 0.22),
        SynthNote(midi: 74, duration: 0.5, gap: 0.1),
    ]

    static func renderMelody(
        _ melody: [SynthNote],
        sampleRate: Double,
        leadIn: Double = 0.12
    ) -> (samples: [Float], notes: [NoteEvent]) {
        var t = leadIn
        var notes: [NoteEvent] = []
        for step in melody {
            notes.append(
                NoteEvent(
                    id: "s\(notes.count)",
                    midi: step.midi,
                    frequency: Notes.midiToFreq(step.midi),
                    start: t,
                    duration: step.duration
                )
            )
            t += step.duration + step.gap
        }

        let total = t + 0.15
        var samples = [Float](repeating: 0, count: Int(ceil(total * sampleRate)))
        for note in notes {
            let freq = Notes.midiToFreq(note.midi)
            let start = Int(note.start * sampleRate)
            let n = Int(note.duration * sampleRate)
            let attack = max(1, n * 8 / 100)
            let release = max(1, n * 16 / 100)
            for i in 0..<n {
                let env: Double
                if i < attack {
                    env = Double(i) / Double(attack)
                } else if i > n - release {
                    env = max(0, Double(n - i) / Double(release))
                } else {
                    env = 1
                }
                let localT = Double(i) / sampleRate
                let vibrato = 1 + 0.004 * sin(2 * Double.pi * 5.2 * localT)
                let phase = 2 * Double.pi * freq * vibrato * localT
                let tone = sin(phase) + 0.08 * sin(2 * phase)
                let idx = start + i
                if idx < samples.count {
                    samples[idx] += Float(0.42 * env * tone)
                }
            }
        }
        return (samples, notes)
    }
}
