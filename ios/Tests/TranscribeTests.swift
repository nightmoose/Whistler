import XCTest
@testable import Whistler

final class TranscribeTests: XCTestCase {
    func testYinHearsA5() {
        let sr = 44100.0
        let result = Yin.pitch(samples: sine(880, seconds: 0.12, sampleRate: sr), sampleRate: sr, minFreq: 400, maxFreq: 4000)
        XCTAssertNotNil(result.frequency)
        XCTAssertEqual(result.frequency!, 880, accuracy: 1)
        XCTAssertGreaterThan(result.confidence, 0.8)
    }

    func testYinHearsC5() {
        let sr = 44100.0
        let freq = Notes.midiToFreq(72)
        let result = Yin.pitch(samples: sine(freq, seconds: 0.12, sampleRate: sr), sampleRate: sr, minFreq: 400, maxFreq: 4000)
        XCTAssertEqual(result.frequency!, freq, accuracy: 1)
    }

    func testSegmentsTwoNoteWhistle() {
        let sr = 44100.0
        let samples =
            sine(0.0001, seconds: 0.15, sampleRate: sr, amp: 0) +
            sine(Notes.midiToFreq(81), seconds: 0.4, sampleRate: sr) +
            sine(0.0001, seconds: 0.12, sampleRate: sr, amp: 0) +
            sine(Notes.midiToFreq(84), seconds: 0.4, sampleRate: sr) +
            sine(0.0001, seconds: 0.15, sampleRate: sr, amp: 0)
        let notes = Transcribe.run(samples: samples, sampleRate: sr, mode: .whistle).notes
        XCTAssertGreaterThanOrEqual(notes.count, 2)
        XCTAssertEqual(notes[0].midi, 81)
        XCTAssertEqual(notes[1].midi, 84)
    }

    func testRecoversDemoMelodyPitches() {
        let sr = 44100.0
        let rendered = Synth.renderMelody(Synth.demoMelody, sampleRate: sr)
        let notes = Transcribe.run(samples: rendered.samples, sampleRate: sr, mode: .whistle).notes
        let expected = collapse(Synth.demoMelody.map(\.midi))
        let got = collapse(notes.map(\.midi))
        XCTAssertGreaterThanOrEqual(got.count, expected.count - 1, "contour \(got)")
        var matched = 0
        var i = 0
        for pitch in expected {
            while i < got.count && got[i] != pitch { i += 1 }
            if i < got.count && got[i] == pitch {
                matched += 1
                i += 1
            }
        }
        XCTAssertGreaterThanOrEqual(matched, expected.count - 1, "contour \(got)")
    }

    func testMidiHeader() {
        let data = MIDIFile.data(from: [
            NoteEvent(id: "a", midi: 76, frequency: Notes.midiToFreq(76), start: 0, duration: 0.5),
            NoteEvent(id: "b", midi: 79, frequency: Notes.midiToFreq(79), start: 0.5, duration: 0.5),
        ])
        XCTAssertEqual(String(bytes: data.prefix(4), encoding: .ascii), "MThd")
        XCTAssertEqual(String(bytes: data[14..<18], encoding: .ascii), "MTrk")
        XCTAssertEqual(data[9], 0)
    }

    func testMidiRoundTrip() throws {
        let original = [
            NoteEvent(id: "a", midi: 76, frequency: Notes.midiToFreq(76), start: 0, duration: 0.5),
            NoteEvent(id: "b", midi: 79, frequency: Notes.midiToFreq(79), start: 0.5, duration: 0.5),
        ]
        let parsed = try MIDIFile.parse(MIDIFile.data(from: original))
        XCTAssertEqual(parsed.notes.map(\.midi), [76, 79])
        XCTAssertEqual(parsed.notes[0].start, 0, accuracy: 0.02)
        XCTAssertEqual(parsed.notes[0].duration, 0.5, accuracy: 0.02)
        XCTAssertEqual(parsed.notes[1].start, 0.5, accuracy: 0.02)
        XCTAssertEqual(parsed.notes[1].duration, 0.5, accuracy: 0.02)
    }

    func testMidiRunningStatusAndNoteOnVelocityZero() throws {
        // Type 0, 480 PPQ, 120 BPM. Running-status note-ons; vel 0 ends the first note.
        var bytes: [UInt8] = [
            0x4D, 0x54, 0x68, 0x64, 0, 0, 0, 6, 0, 0, 0, 1, 0x01, 0xE0,
        ]
        var track: [UInt8] = [
            0x00, 0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20, // tempo 500000
            0x00, 0x90, 60, 0x40, // C4 on
            0x81, 0x70, 60, 0x00, // running status, vel 0 = off after 240 ticks (eighth)
            0x00, 64, 0x40, // E4 on (running)
            0x81, 0x70, 0x80, 64, 0x40, // E4 off after 240 ticks
            0x00, 0xFF, 0x2F, 0x00,
        ]
        bytes.append(contentsOf: [0x4D, 0x54, 0x72, 0x6B])
        let len = track.count
        bytes.append(contentsOf: [UInt8((len >> 24) & 0xFF), UInt8((len >> 16) & 0xFF), UInt8((len >> 8) & 0xFF), UInt8(len & 0xFF)])
        bytes.append(contentsOf: track)
        let parsed = try MIDIFile.parse(Data(bytes))
        XCTAssertEqual(parsed.notes.map(\.midi), [60, 64])
        XCTAssertEqual(parsed.notes[0].duration, 0.25, accuracy: 0.02)
        XCTAssertEqual(parsed.notes[1].duration, 0.25, accuracy: 0.02)
    }

    func testBridgesBriefHolesInAHeldNote() {
        let sr = 44100.0
        let samples =
            sine(Notes.midiToFreq(81), seconds: 0.22, sampleRate: sr) +
            sine(0.0001, seconds: 0.025, sampleRate: sr, amp: 0) +
            sine(Notes.midiToFreq(81), seconds: 0.22, sampleRate: sr)
        let notes = Transcribe.run(samples: samples, sampleRate: sr, mode: .whistle).notes
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes[0].midi, 81)
    }

    func testKeepsLegatoScaleRun() {
        let sr = 44100.0
        // Andy Griffith / Fishin' Hole opening, whistle octave, connected like a real pucker.
        let melody = [79, 81, 83, 84, 86, 88, 91, 88, 86, 83]
        let samples = legato(melody, noteSeconds: 0.11, glideSeconds: 0.02, sampleRate: sr)
        let notes = Transcribe.run(samples: samples, sampleRate: sr, mode: .whistle).notes
        let got = notes.map(\.midi)
        var matched = 0
        var i = 0
        for pitch in melody {
            while i < got.count && got[i] != pitch { i += 1 }
            if i < got.count && got[i] == pitch {
                matched += 1
                i += 1
            }
        }
        XCTAssertGreaterThanOrEqual(notes.count, 8, "dropped too many notes: \(got)")
        XCTAssertGreaterThanOrEqual(matched, 8, "scale order lost: \(got)")
    }

    func testAutotunePullsFlatNotesUpToTheKey() {
        let flatB = NoteEvent(
            id: "b",
            midi: 70,
            frequency: Notes.midiToFreq(70.4),
            start: 0,
            duration: 0.3,
            rawMidi: 70.4 // 60 cents below B4
        )
        let neighbors = [67, 69, 71, 72, 74, 76].enumerated().map { index, midi in
            NoteEvent(
                id: "n\(index)",
                midi: midi,
                frequency: Notes.midiToFreq(midi),
                start: Double(index) * 0.3,
                duration: 0.25,
                rawMidi: Double(midi)
            )
        }
        let tuned = Autotune.apply(neighbors + [flatB], enabled: true)
        XCTAssertEqual(tuned.notes.first { $0.id == "b" }?.midi, 71)
        XCTAssertTrue(tuned.key?.pitchClasses.contains(11) == true, "key should include B, got \(tuned.key?.name ?? "nil")")
    }

    func testAsWhistledKeepsTheFlatRound() {
        let flatB = NoteEvent(id: "b", midi: 70, frequency: Notes.midiToFreq(70.4), start: 0, duration: 0.3, rawMidi: 70.4)
        let raw = Autotune.apply([flatB], enabled: false)
        XCTAssertEqual(raw.notes[0].midi, 70)
        XCTAssertNil(raw.key)
    }

    func testGuitarTab() {
        let tab = Guitar.tab(from: [
            NoteEvent(id: "a", midi: 76, frequency: Notes.midiToFreq(76), start: 0, duration: 0.3),
            NoteEvent(id: "b", midi: 79, frequency: Notes.midiToFreq(79), start: 0.4, duration: 0.3),
        ])
        XCTAssertEqual(tab.hits.count, 2)
        XCTAssertTrue(tab.ascii.contains("e|"))
        XCTAssertTrue(tab.hits.allSatisfy { $0.fret >= 0 && $0.fret <= 20 })
        XCTAssertEqual(Notes.midiToName(76, ascii: true), "E5")
    }
}

private func collapse(_ midis: [Int]) -> [Int] {
    var out: [Int] = []
    for midi in midis where out.last != midi {
        out.append(midi)
    }
    return out
}

private func legato(_ midis: [Int], noteSeconds: Double, glideSeconds: Double, sampleRate: Double) -> [Float] {
    var samples: [Float] = sine(0.0001, seconds: 0.08, sampleRate: sampleRate, amp: 0)
    for (index, midi) in midis.enumerated() {
        samples += sine(Notes.midiToFreq(midi), seconds: noteSeconds, sampleRate: sampleRate)
        if index + 1 < midis.count {
            samples += glide(
                from: Notes.midiToFreq(midi),
                to: Notes.midiToFreq(midis[index + 1]),
                seconds: glideSeconds,
                sampleRate: sampleRate
            )
        }
    }
    samples += sine(0.0001, seconds: 0.08, sampleRate: sampleRate, amp: 0)
    return samples
}

private func glide(from: Double, to: Double, seconds: Double, sampleRate: Double) -> [Float] {
    let n = max(1, Int(seconds * sampleRate))
    var out = [Float](repeating: 0, count: n)
    var phase = 0.0
    for i in 0..<n {
        let t = Double(i) / Double(max(n - 1, 1))
        let freq = from + (to - from) * t
        phase += 2 * Double.pi * freq / sampleRate
        let env: Float = 0.35 + 0.15 * Float(sin(Double.pi * t))
        out[i] = env * 0.5 * Float(sin(phase))
    }
    return out
}

private func sine(_ freq: Double, seconds: Double, sampleRate: Double, amp: Float = 0.5) -> [Float] {
    let n = Int(seconds * sampleRate)
    var out = [Float](repeating: 0, count: n)
    let attack = Int(sampleRate * 0.01)
    let release = Int(sampleRate * 0.02)
    for i in 0..<n {
        let env: Float
        if i < attack {
            env = Float(i) / Float(max(attack, 1))
        } else if i > n - release {
            env = max(0, Float(n - i) / Float(max(release, 1)))
        } else {
            env = 1
        }
        out[i] = amp * env * Float(sin(2 * Double.pi * freq * Double(i) / sampleRate))
    }
    return out
}
