import AVFoundation
import Foundation

enum Playback {
    private static var audioPlayer: AVAudioPlayer?

    static func play(samples: [Float], sampleRate: Double) throws {
        stop()
        try configureSession()
        let wav = WAV.data(samples: samples, sampleRate: sampleRate)
        let player = try AVAudioPlayer(data: wav)
        player.prepareToPlay()
        player.play()
        audioPlayer = player
    }

    static func play(notes: [NoteEvent], sampleRate: Double = 44100) throws {
        guard !notes.isEmpty else { return }
        let end = notes.map { $0.start + $0.duration }.max() ?? 0
        var samples = [Float](repeating: 0, count: Int(ceil((end + 0.2) * sampleRate)))
        let overlap = max(1, maxSimultaneous(notes))
        let amp = min(0.42, 0.55 / Double(overlap))
        for note in notes {
            let freq = Notes.midiToFreq(note.midi)
            let start = Int(note.start * sampleRate)
            let n = max(1, Int(note.duration * sampleRate))
            let attack = max(1, n * 8 / 100)
            let release = max(1, n * 16 / 100)
            for i in 0..<n {
                let env: Double
                if i < attack { env = Double(i) / Double(attack) }
                else if i > n - release { env = max(0, Double(n - i) / Double(release)) }
                else { env = 1 }
                let localT = Double(i) / sampleRate
                let phase = 2 * Double.pi * freq * localT
                let tone = sin(phase) + 0.08 * sin(2 * phase)
                let idx = start + i
                if idx >= 0 && idx < samples.count {
                    samples[idx] += Float(amp * env * tone)
                }
            }
        }
        try play(samples: samples, sampleRate: sampleRate)
    }

    private static func maxSimultaneous(_ notes: [NoteEvent]) -> Int {
        var events: [(Double, Int)] = []
        events.reserveCapacity(notes.count * 2)
        for note in notes {
            events.append((note.start, 1))
            events.append((note.start + note.duration, -1))
        }
        events.sort { $0.0 < $1.0 || ($0.0 == $1.0 && $0.1 < $1.1) }
        var current = 0
        var peak = 0
        for event in events {
            current += event.1
            peak = max(peak, current)
        }
        return max(1, peak)
    }

    static func play(file url: URL) throws {
        stop()
        try configureSession()
        let player = try AVAudioPlayer(contentsOf: url)
        player.prepareToPlay()
        player.play()
        audioPlayer = player
    }

    static func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
    }

    static func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
        try session.setActive(true)
    }
}

enum WAV {
    static func data(samples: [Float], sampleRate: Double) -> Data {
        let rate = UInt32(sampleRate)
        var pcm = [Int16](repeating: 0, count: samples.count)
        for i in 0..<samples.count {
            let clipped = max(-1, min(1, samples[i]))
            pcm[i] = Int16(clipped * 32767)
        }
        let dataSize = UInt32(pcm.count * 2)
        var header = Data()
        func append(_ string: String) { header.append(contentsOf: string.utf8) }
        func appendU32(_ v: UInt32) {
            var le = v.littleEndian
            header.append(Data(bytes: &le, count: 4))
        }
        func appendU16(_ v: UInt16) {
            var le = v.littleEndian
            header.append(Data(bytes: &le, count: 2))
        }
        append("RIFF")
        appendU32(36 + dataSize)
        append("WAVE")
        append("fmt ")
        appendU32(16)
        appendU16(1)
        appendU16(1)
        appendU32(rate)
        appendU32(rate * 2)
        appendU16(2)
        appendU16(16)
        append("data")
        appendU32(dataSize)
        var payload = Data(header)
        pcm.withUnsafeBytes { payload.append(contentsOf: $0) }
        return payload
    }
}
