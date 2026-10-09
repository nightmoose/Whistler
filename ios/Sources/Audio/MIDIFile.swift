import Foundation

enum MIDIFile {
    private static let ppq = 480
    private static let whistleProgram = 78

    struct Parsed: Equatable {
        var notes: [NoteEvent]
        var bpm: Double
        var duration: Double
    }

    enum ParseError: Error, LocalizedError {
        case truncated
        case notMIDI
        case unsupportedDivision
        case noNotes

        var errorDescription: String? {
            switch self {
            case .truncated: return "That MIDI file is truncated."
            case .notMIDI: return "That file is not a MIDI sequence."
            case .unsupportedDivision: return "That MIDI file uses a timing format Whistler doesn't read."
            case .noNotes: return "No notes in that MIDI file."
            }
        }
    }

    static func data(from notes: [NoteEvent], bpm: Double = 120) -> Data {
        let usPerBeat = Int(round(60_000_000 / bpm))
        var events: [(tick: Int, bytes: [UInt8])] = [
            (0, [0xFF, 0x51, 0x03, UInt8((usPerBeat >> 16) & 0xFF), UInt8((usPerBeat >> 8) & 0xFF), UInt8(usPerBeat & 0xFF)]),
            (0, [0xFF, 0x58, 0x04, 0x04, 0x02, 0x18, 0x08]),
            (0, [0xC0, UInt8(whistleProgram)]),
        ]

        for note in notes {
            let start = secondsToTicks(note.start, bpm: bpm)
            let end = max(start + 1, secondsToTicks(note.start + note.duration, bpm: bpm))
            let pitch = UInt8(max(0, min(127, note.midi)))
            events.append((start, [0x90, pitch, 0x64]))
            events.append((end, [0x80, pitch, 0x40]))
        }

        events.sort { lhs, rhs in
            if lhs.tick != rhs.tick { return lhs.tick < rhs.tick }
            return lhs.bytes[0] < rhs.bytes[0]
        }

        var track = [UInt8]()
        var lastTick = 0
        for event in events {
            track.append(contentsOf: vlq(event.tick - lastTick))
            track.append(contentsOf: event.bytes)
            lastTick = event.tick
        }
        let endTick = events.last?.tick ?? 0
        track.append(contentsOf: vlq(max(0, endTick - lastTick)))
        track.append(contentsOf: [0xFF, 0x2F, 0x00])

        var bytes: [UInt8] = [0x4D, 0x54, 0x68, 0x64]
        bytes.append(contentsOf: u32(6))
        bytes.append(contentsOf: u16(0))
        bytes.append(contentsOf: u16(1))
        bytes.append(contentsOf: u16(ppq))
        bytes.append(contentsOf: [0x4D, 0x54, 0x72, 0x6B])
        bytes.append(contentsOf: u32(track.count))
        bytes.append(contentsOf: track)
        return Data(bytes)
    }

    static func writeTemporary(_ notes: [NoteEvent]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("whistler.mid")
        try data(from: notes).write(to: url, options: .atomic)
        return url
    }

    static func parse(_ data: Data) throws -> Parsed {
        var offset = 0
        guard ascii(data, &offset, 4) == "MThd" else { throw ParseError.notMIDI }
        let headerLen = try u32(data, &offset)
        guard headerLen >= 6, offset + headerLen <= data.count else { throw ParseError.truncated }
        let format = try u16(data, &offset)
        let trackCount = try u16(data, &offset)
        let division = try u16(data, &offset)
        offset += max(0, headerLen - 6)
        _ = format
        guard division & 0x8000 == 0 else { throw ParseError.unsupportedDivision }
        let ticksPerQuarter = max(1, division)

        var rawNotes: [RawNote] = []
        var tempos: [(tick: Int, usPerBeat: Int)] = [(0, 500_000)]
        var lastTick = 0

        for _ in 0..<trackCount {
            if offset + 8 > data.count { break }
            let tag = ascii(data, &offset, 4)
            let length = try u32(data, &offset)
            guard offset + length <= data.count else { throw ParseError.truncated }
            if tag != "MTrk" {
                offset += length
                continue
            }
            let end = offset + length
            let parsed = try parseTrack(data, from: &offset, end: end)
            rawNotes.append(contentsOf: parsed.notes)
            tempos.append(contentsOf: parsed.tempos)
            lastTick = max(lastTick, parsed.endTick)
            offset = end
        }

        tempos.sort { $0.tick < $1.tick }
        let pitched = rawNotes.filter { $0.channel != 9 }
        let chosen = pitched.isEmpty ? rawNotes : pitched
        guard !chosen.isEmpty else { throw ParseError.noNotes }

        var notes: [NoteEvent] = []
        for (index, raw) in chosen.enumerated() {
            let start = seconds(for: raw.startTick, ppq: ticksPerQuarter, tempos: tempos)
            let end = seconds(for: max(raw.startTick + 1, raw.endTick), ppq: ticksPerQuarter, tempos: tempos)
            notes.append(
                NoteEvent(
                    id: "m\(index)-\(raw.startTick)",
                    midi: Int(raw.pitch),
                    frequency: Notes.midiToFreq(Int(raw.pitch)),
                    start: start,
                    duration: max(0.04, end - start)
                )
            )
        }
        notes.sort { $0.start < $1.start || ($0.start == $1.start && $0.midi < $1.midi) }
        let duration = notes.map { $0.start + $0.duration }.max() ?? 0
        let firstTempo = tempos.first(where: { $0.tick == 0 })?.usPerBeat ?? tempos[0].usPerBeat
        let bpm = 60_000_000.0 / Double(firstTempo)
        return Parsed(notes: notes, bpm: bpm, duration: duration)
    }

    private struct RawNote {
        var pitch: UInt8
        var channel: UInt8
        var startTick: Int
        var endTick: Int
    }

    private static func parseTrack(_ data: Data, from offset: inout Int, end: Int) throws -> (notes: [RawNote], tempos: [(tick: Int, usPerBeat: Int)], endTick: Int) {
        var tick = 0
        var running: UInt8 = 0
        var tempos: [(tick: Int, usPerBeat: Int)] = []
        var open: [UInt16: [Int]] = [:]
        var notes: [RawNote] = []

        func key(_ channel: UInt8, _ pitch: UInt8) -> UInt16 {
            UInt16(channel) << 8 | UInt16(pitch)
        }

        func noteOn(channel: UInt8, pitch: UInt8, velocity: UInt8) {
            if velocity == 0 {
                noteOff(channel: channel, pitch: pitch)
                return
            }
            open[key(channel, pitch), default: []].append(tick)
        }

        func noteOff(channel: UInt8, pitch: UInt8) {
            let k = key(channel, pitch)
            guard var stack = open[k], let start = stack.popLast() else { return }
            open[k] = stack
            notes.append(RawNote(pitch: pitch, channel: channel, startTick: start, endTick: max(start + 1, tick)))
        }

        while offset < end {
            tick += try vlq(data, &offset)
            guard offset < end else { break }
            var status = data[offset]
            if status < 0x80 {
                guard running != 0 else { throw ParseError.truncated }
                status = running
            } else {
                offset += 1
                running = status < 0xF0 ? status : 0
            }

            if status == 0xFF {
                let type = try u8(data, &offset)
                let len = try vlq(data, &offset)
                let payload = try take(data, &offset, len)
                if type == 0x51, payload.count == 3 {
                    let us = Int(payload[0]) << 16 | Int(payload[1]) << 8 | Int(payload[2])
                    tempos.append((tick, max(1, us)))
                }
                if type == 0x2F { break }
                continue
            }
            if status == 0xF0 || status == 0xF7 {
                let len = try vlq(data, &offset)
                _ = try take(data, &offset, len)
                continue
            }

            let command = status & 0xF0
            let channel = status & 0x0F
            switch command {
            case 0x80:
                let pitch = try u8(data, &offset)
                _ = try u8(data, &offset)
                noteOff(channel: channel, pitch: pitch)
            case 0x90:
                let pitch = try u8(data, &offset)
                let vel = try u8(data, &offset)
                noteOn(channel: channel, pitch: pitch, velocity: vel)
            case 0xA0, 0xB0, 0xE0:
                _ = try u8(data, &offset)
                _ = try u8(data, &offset)
            case 0xC0, 0xD0:
                _ = try u8(data, &offset)
            default:
                break
            }
        }

        for (k, starts) in open {
            let channel = UInt8(k >> 8)
            let pitch = UInt8(k & 0xFF)
            for start in starts {
                notes.append(RawNote(pitch: pitch, channel: channel, startTick: start, endTick: max(start + 1, tick)))
            }
        }
        return (notes, tempos, tick)
    }

    private static func seconds(for tick: Int, ppq: Int, tempos: [(tick: Int, usPerBeat: Int)]) -> Double {
        var t = 0.0
        var lastTick = 0
        var usPerBeat = 500_000
        for change in tempos where change.tick <= tick {
            if change.tick > lastTick {
                t += Double(change.tick - lastTick) * Double(usPerBeat) / 1_000_000.0 / Double(ppq)
                lastTick = change.tick
            }
            usPerBeat = change.usPerBeat
        }
        if tick > lastTick {
            t += Double(tick - lastTick) * Double(usPerBeat) / 1_000_000.0 / Double(ppq)
        }
        return t
    }

    private static func ascii(_ data: Data, _ offset: inout Int, _ count: Int) -> String {
        let end = min(data.count, offset + count)
        let slice = data[offset..<end]
        offset = end
        return String(bytes: slice, encoding: .ascii) ?? ""
    }

    private static func u8(_ data: Data, _ offset: inout Int) throws -> UInt8 {
        guard offset < data.count else { throw ParseError.truncated }
        let value = data[offset]
        offset += 1
        return value
    }

    private static func u16(_ data: Data, _ offset: inout Int) throws -> Int {
        let hi = try u8(data, &offset)
        let lo = try u8(data, &offset)
        return Int(hi) << 8 | Int(lo)
    }

    private static func u32(_ data: Data, _ offset: inout Int) throws -> Int {
        let b0 = try u8(data, &offset)
        let b1 = try u8(data, &offset)
        let b2 = try u8(data, &offset)
        let b3 = try u8(data, &offset)
        return Int(b0) << 24 | Int(b1) << 16 | Int(b2) << 8 | Int(b3)
    }

    private static func vlq(_ data: Data, _ offset: inout Int) throws -> Int {
        var value = 0
        for _ in 0..<4 {
            let byte = try u8(data, &offset)
            value = (value << 7) | Int(byte & 0x7F)
            if byte & 0x80 == 0 { return value }
        }
        throw ParseError.truncated
    }

    private static func take(_ data: Data, _ offset: inout Int, _ count: Int) throws -> [UInt8] {
        guard offset + count <= data.count else { throw ParseError.truncated }
        let slice = Array(data[offset..<(offset + count)])
        offset += count
        return slice
    }

    private static func secondsToTicks(_ seconds: Double, bpm: Double) -> Int {
        max(0, Int(round(seconds * (bpm / 60) * Double(ppq))))
    }

    private static func vlq(_ value: Int) -> [UInt8] {
        var v = UInt32(max(0, value))
        var bytes: [UInt8] = [UInt8(v & 0x7F)]
        v >>= 7
        while v > 0 {
            bytes.insert(UInt8((v & 0x7F) | 0x80), at: 0)
            v >>= 7
        }
        return bytes
    }

    private static func u16(_ n: Int) -> [UInt8] {
        [UInt8((n >> 8) & 0xFF), UInt8(n & 0xFF)]
    }

    private static func u32(_ n: Int) -> [UInt8] {
        [
            UInt8((n >> 24) & 0xFF),
            UInt8((n >> 16) & 0xFF),
            UInt8((n >> 8) & 0xFF),
            UInt8(n & 0xFF),
        ]
    }
}
