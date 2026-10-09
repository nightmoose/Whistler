import Foundation

enum Notes {
    static let sharp = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
    static let ascii = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    static func freqToMidi(_ freq: Double) -> Double {
        69 + 12 * log2(freq / 440)
    }

    static func midiToFreq(_ midi: Double) -> Double {
        440 * pow(2, (midi - 69) / 12)
    }

    static func midiToFreq(_ midi: Int) -> Double {
        midiToFreq(Double(midi))
    }

    static func midiToName(_ midi: Int, ascii: Bool = false) -> String {
        let pc = ((midi % 12) + 12) % 12
        let octave = Int(floor(Double(midi) / 12.0)) - 1
        let names = ascii ? Self.ascii : sharp
        return "\(names[pc])\(octave)"
    }

    static func centsOff(_ midi: Double) -> Int {
        Int(round((midi - round(midi)) * 100))
    }
}
