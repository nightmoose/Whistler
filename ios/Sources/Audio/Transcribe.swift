import Foundation

enum SourceMode: String, CaseIterable, Identifiable {
    case whistle
    case hum
    case any

    var id: String { rawValue }

    var title: String {
        switch self {
        case .whistle: return "Whistle"
        case .hum: return "Hum"
        case .any: return "Any"
        }
    }

    var hint: String {
        switch self {
        case .whistle: return "G4 – whistle"
        case .hum: return "low voice"
        case .any: return "wider catch"
        }
    }

    var minFreq: Double {
        switch self {
        case .whistle: return 380
        case .hum: return 80
        case .any: return 70
        }
    }

    var maxFreq: Double {
        switch self {
        case .whistle: return 4200
        case .hum: return 900
        case .any: return 5000
        }
    }

    var highpassHz: Double {
        switch self {
        case .whistle: return 350
        case .hum: return 70
        case .any: return 60
        }
    }
}

struct PitchFrame {
    var time: Double
    var frequency: Double?
    var midi: Double?
    var rms: Double
    var confidence: Double
}

struct NoteEvent: Identifiable, Equatable {
    var id: String
    var midi: Int
    var rawMidi: Double
    var frequency: Double
    var start: Double
    var duration: Double
    var locked: Bool

    init(
        id: String,
        midi: Int,
        frequency: Double,
        start: Double,
        duration: Double,
        rawMidi: Double? = nil,
        locked: Bool = false
    ) {
        self.id = id
        self.midi = midi
        self.rawMidi = rawMidi ?? Double(midi)
        self.frequency = frequency
        self.start = start
        self.duration = duration
        self.locked = locked
    }
}

struct Transcription {
    var frames: [PitchFrame]
    var notes: [NoteEvent]
    var duration: Double
    var sampleRate: Double
}

enum Voicing {
    static let yinThreshold = 0.18
    static let minConfidence = 0.38
    static let minRms = 0.002
    static let unvoicedHang = 0.045
    static let splitHang = 0.038
    static let minNoteDuration = 0.045
    static let pitchChangeCents = 80.0
    static let hopSize = 256
    static let windowSize = 1024
}

enum Transcribe {
    static func extractPitchTrack(
        samples: [Float],
        sampleRate: Double,
        mode: SourceMode = .whistle,
        hopSize: Int = Voicing.hopSize,
        windowSize: Int = Voicing.windowSize,
        yinThreshold: Double = Voicing.yinThreshold,
        minRms: Double = Voicing.minRms
    ) -> [PitchFrame] {
        var frames: [PitchFrame] = []
        guard samples.count >= windowSize else { return frames }
        return samples.withUnsafeBufferPointer { buf in
        var start = 0
        while start + windowSize <= samples.count {
            let window = UnsafeBufferPointer(start: buf.baseAddress! + start, count: windowSize)
            let level = Yin.rms(window)
            let yin = Yin.pitch(
                samples: window,
                sampleRate: sampleRate,
                minFreq: mode.minFreq,
                maxFreq: mode.maxFreq,
                threshold: yinThreshold
            )
            let inRange = yin.frequency.map { $0 >= mode.minFreq * 0.92 && $0 <= mode.maxFreq * 1.05 } ?? false
            let voiced = inRange && yin.confidence >= Voicing.minConfidence && level >= minRms
            let freq = voiced ? yin.frequency : nil
            frames.append(
                PitchFrame(
                    time: Double(start) / sampleRate,
                    frequency: freq,
                    midi: freq.map(Notes.freqToMidi),
                    rms: level,
                    confidence: voiced ? yin.confidence : 0
                )
            )
            start += hopSize
        }
        return frames
        }
    }

    static func segmentNotes(
        _ frames: [PitchFrame],
        minNoteDuration: Double = Voicing.minNoteDuration,
        pitchChangeCents: Double = Voicing.pitchChangeCents,
        splitHang: Double = Voicing.splitHang,
        unvoicedHang: Double = Voicing.unvoicedHang
    ) -> [NoteEvent] {
        var notes: [NoteEvent] = []
        var activeMidis: [Double] = []
        var activeFreqs: [Double] = []
        var activeStart: Double = 0
        var hasActive = false
        var pending: [(midi: Double, freq: Double, time: Double)] = []
        var unvoicedSince: Double?

        func close(at endTime: Double) {
            defer {
                hasActive = false
                activeMidis = []
                activeFreqs = []
                pending = []
                unvoicedSince = nil
            }
            guard hasActive, !activeMidis.isEmpty else { return }
            let duration = endTime - activeStart
            guard duration >= minNoteDuration else { return }
            let raw = median(activeMidis)
            let rounded = activeMidis.map { Int(round($0)) }
            let midi = modal(rounded) ?? Int(round(raw))
            let core = zip(activeMidis, activeFreqs).filter { Int(round($0.0)) == midi }.map(\.1)
            notes.append(
                NoteEvent(
                    id: "n\(notes.count)-\(String(format: "%.3f", activeStart))",
                    midi: midi,
                    frequency: median(core.isEmpty ? activeFreqs : core),
                    start: activeStart,
                    duration: duration,
                    rawMidi: raw
                )
            )
        }

        for i in 0..<frames.count {
            let frame = frames[i]
            let nextTime = i + 1 < frames.count ? frames[i + 1].time : frame.time + 0.01

            guard let midi = frame.midi, let frequency = frame.frequency else {
                if hasActive {
                    if unvoicedSince == nil { unvoicedSince = frame.time }
                    if frame.time - unvoicedSince! >= unvoicedHang {
                        close(at: unvoicedSince!)
                    }
                }
                pending = []
                if i == frames.count - 1, hasActive {
                    close(at: unvoicedSince ?? frame.time)
                }
                continue
            }

            unvoicedSince = nil
            let midiInt = Int(round(midi))

            if !hasActive {
                hasActive = true
                activeMidis = [midi]
                activeFreqs = [frequency]
                activeStart = frame.time
                pending = []
                if i == frames.count - 1 { close(at: nextTime) }
                continue
            }

            let current = median(activeMidis)
            let jumped = abs(midi - current) * 100 >= pitchChangeCents && midiInt != Int(round(current))

            if jumped {
                if pending.last.map({ Int(round($0.midi)) }) != midiInt {
                    pending = [(midi, frequency, frame.time)]
                } else {
                    pending.append((midi, frequency, frame.time))
                }
                if let first = pending.first, frame.time - first.time >= splitHang {
                    let held = pending
                    close(at: first.time)
                    hasActive = true
                    activeMidis = held.map(\.midi)
                    activeFreqs = held.map(\.freq)
                    activeStart = first.time
                    pending = []
                }
            } else {
                pending = []
                activeMidis.append(midi)
                activeFreqs.append(frequency)
            }

            if i == frames.count - 1 {
                close(at: nextTime)
            }
        }

        if hasActive, let last = frames.last {
            close(at: last.time + 0.01)
        }

        return mergeTinyNeighbors(notes)
    }

    static func run(
        samples: [Float],
        sampleRate: Double,
        mode: SourceMode = .whistle
    ) -> Transcription {
        let frames = extractPitchTrack(samples: samples, sampleRate: sampleRate, mode: mode)
        let notes = segmentNotes(frames)
        return Transcription(
            frames: frames,
            notes: notes,
            duration: Double(samples.count) / sampleRate,
            sampleRate: sampleRate
        )
    }

    static func nameLine(_ notes: [NoteEvent], ascii: Bool = false) -> String {
        notes.map { Notes.midiToName($0.midi, ascii: ascii) }.joined(separator: "  ")
    }
}

private func median(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    let mid = sorted.count / 2
    if sorted.count.isMultiple(of: 2) {
        return (sorted[mid - 1] + sorted[mid]) / 2
    }
    return sorted[mid]
}

private func modal(_ values: [Int]) -> Int? {
    guard !values.isEmpty else { return nil }
    var counts: [Int: Int] = [:]
    for value in values { counts[value, default: 0] += 1 }
    return counts.max { lhs, rhs in
        if lhs.value != rhs.value { return lhs.value < rhs.value }
        return lhs.key < rhs.key
    }?.key
}

private func mergeTinyNeighbors(_ notes: [NoteEvent]) -> [NoteEvent] {
    guard notes.count >= 2 else { return notes }
    var out: [NoteEvent] = []
    for note in notes {
        if var prev = out.last {
            let gap = note.start - (prev.start + prev.duration)
            let flicker = prev.duration < 0.11 || note.duration < 0.11
            if prev.midi == note.midi && (gap < 0.035 || (gap < 0.08 && flicker)) {
                prev.duration = note.start + note.duration - prev.start
                out[out.count - 1] = prev
                continue
            }
        }
        out.append(note)
    }
    return out
}
