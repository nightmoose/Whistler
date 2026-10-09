import type { NoteEvent } from "@/lib/audio/transcribe";

const PPQ = 480;
const WHISTLE_PROGRAM = 78; // General MIDI "Whistle"

function vlq(value: number): number[] {
  const bytes: number[] = [];
  let v = value >>> 0;
  bytes.unshift(v & 0x7f);
  v >>= 7;
  while (v > 0) {
    bytes.unshift((v & 0x7f) | 0x80);
    v >>= 7;
  }
  return bytes;
}

function u16(n: number): number[] {
  return [(n >> 8) & 0xff, n & 0xff];
}

function u32(n: number): number[] {
  return [(n >> 24) & 0xff, (n >> 16) & 0xff, (n >> 8) & 0xff, n & 0xff];
}

function secondsToTicks(seconds: number, bpm: number): number {
  return Math.max(0, Math.round(seconds * (bpm / 60) * PPQ));
}

type MidiEvent = { tick: number; bytes: number[] };

export function notesToMidiBytes(notes: NoteEvent[], bpm = 120): Uint8Array {
  const usPerBeat = Math.round(60_000_000 / bpm);
  const events: MidiEvent[] = [
    { tick: 0, bytes: [0xff, 0x51, 0x03, (usPerBeat >> 16) & 0xff, (usPerBeat >> 8) & 0xff, usPerBeat & 0xff] },
    { tick: 0, bytes: [0xff, 0x58, 0x04, 0x04, 0x02, 0x18, 0x08] },
    { tick: 0, bytes: [0xc0, WHISTLE_PROGRAM] },
  ];

  for (const note of notes) {
    const start = secondsToTicks(note.start, bpm);
    const end = Math.max(start + 1, secondsToTicks(note.start + note.duration, bpm));
    const pitch = Math.max(0, Math.min(127, note.midi));
    events.push({ tick: start, bytes: [0x90, pitch, 0x64] });
    events.push({ tick: end, bytes: [0x80, pitch, 0x40] });
  }

  events.sort((a, b) => a.tick - b.tick || a.bytes[0] - b.bytes[0]);

  const track: number[] = [];
  let lastTick = 0;
  for (const event of events) {
    track.push(...vlq(event.tick - lastTick), ...event.bytes);
    lastTick = event.tick;
  }
  const endTick = events.length ? events[events.length - 1].tick : 0;
  track.push(...vlq(Math.max(0, endTick - lastTick)), 0xff, 0x2f, 0x00);

  const header = [
    0x4d, 0x54, 0x68, 0x64,
    ...u32(6),
    ...u16(0),
    ...u16(1),
    ...u16(PPQ),
    0x4d, 0x54, 0x72, 0x6b,
    ...u32(track.length),
  ];

  return Uint8Array.from([...header, ...track]);
}

export function downloadMidi(notes: NoteEvent[], filename = "whistler.mid", bpm = 120) {
  const bytes = notesToMidiBytes(notes, bpm);
  const blob = new Blob([Uint8Array.from(bytes)], { type: "audio/midi" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}
