import { describe, expect, it } from "vitest";
import { midiToFreq, midiToName } from "@/lib/music/notes";
import { notesToMidiBytes } from "@/lib/audio/midi";
import { DEMO_MELODY, renderMelody } from "@/lib/audio/synth";
import { notesToTab } from "@/lib/audio/tab";
import { transcribe } from "@/lib/audio/transcribe";
import { yinPitch } from "@/lib/audio/yin";

function sine(freq: number, seconds: number, sampleRate: number, amp = 0.5): Float32Array {
  const n = Math.floor(seconds * sampleRate);
  const out = new Float32Array(n);
  for (let i = 0; i < n; i++) {
    const env =
      i < sampleRate * 0.01
        ? i / (sampleRate * 0.01)
        : i > n - sampleRate * 0.02
          ? Math.max(0, (n - i) / (sampleRate * 0.02))
          : 1;
    out[i] = amp * env * Math.sin((2 * Math.PI * freq * i) / sampleRate);
  }
  return out;
}

function concat(parts: Float32Array[]): Float32Array {
  const n = parts.reduce((s, p) => s + p.length, 0);
  const out = new Float32Array(n);
  let o = 0;
  for (const p of parts) {
    out.set(p, o);
    o += p.length;
  }
  return out;
}

describe("yinPitch", () => {
  it("hears a 880 Hz whistle as A5", () => {
    const sr = 44100;
    const result = yinPitch(sine(880, 0.12, sr), sr, { minFreq: 400, maxFreq: 4000 });
    expect(result.frequency).not.toBeNull();
    expect(result.frequency!).toBeCloseTo(880, 0);
    expect(result.confidence).toBeGreaterThan(0.8);
  });

  it("hears C5", () => {
    const sr = 44100;
    const freq = midiToFreq(72);
    const result = yinPitch(sine(freq, 0.12, sr), sr, { minFreq: 400, maxFreq: 4000 });
    expect(result.frequency!).toBeCloseTo(freq, 0);
  });
});

describe("transcribe", () => {
  it("segments a two-note whistle", () => {
    const sr = 44100;
    const samples = concat([
      sine(0.0001, 0.15, sr, 0),
      sine(midiToFreq(81), 0.4, sr),
      sine(0.0001, 0.12, sr, 0),
      sine(midiToFreq(84), 0.4, sr),
      sine(0.0001, 0.15, sr, 0),
    ]);
    const { notes } = transcribe(samples, { sampleRate: sr, mode: "whistle" });
    expect(notes.length).toBeGreaterThanOrEqual(2);
    expect(notes[0].midi).toBe(81);
    expect(notes[1].midi).toBe(84);
  });

  it("recovers the demo melody pitches", () => {
    const sr = 44100;
    const { samples } = renderMelody(DEMO_MELODY, sr);
    const { notes } = transcribe(samples, { sampleRate: sr, mode: "whistle" });
    const expected = DEMO_MELODY.map((n) => n.midi);
    expect(notes.length).toBeGreaterThanOrEqual(expected.length - 2);
    const got = notes.map((n) => n.midi);
    let matched = 0;
    let i = 0;
    for (const pitch of expected) {
      while (i < got.length && got[i] !== pitch) i += 1;
      if (i < got.length && got[i] === pitch) {
        matched += 1;
        i += 1;
      }
    }
    expect(matched).toBeGreaterThanOrEqual(expected.length - 2);
  });
});

describe("midi + tab", () => {
  it("writes a Type 0 MIDI file", () => {
    const bytes = notesToMidiBytes([
      { id: "a", midi: 76, frequency: midiToFreq(76), start: 0, duration: 0.5 },
      { id: "b", midi: 79, frequency: midiToFreq(79), start: 0.5, duration: 0.5 },
    ]);
    const header = String.fromCharCode(...bytes.slice(0, 4));
    const track = String.fromCharCode(...bytes.slice(14, 18));
    expect(header).toBe("MThd");
    expect(track).toBe("MTrk");
    expect(bytes[9]).toBe(0);
  });

  it("places a guitar-friendly tab an octave or two down", () => {
    const tab = notesToTab([
      { id: "a", midi: 76, frequency: midiToFreq(76), start: 0, duration: 0.3 },
      { id: "b", midi: 79, frequency: midiToFreq(79), start: 0.4, duration: 0.3 },
    ]);
    expect(tab.hits.length).toBe(2);
    expect(tab.ascii).toContain("e|");
    expect(tab.hits.every((h) => h.fret >= 0 && h.fret <= 20)).toBe(true);
    expect(midiToName(76, true)).toBe("E5");
  });
});
