import { midiToFreq } from "@/lib/music/notes";
import type { NoteEvent } from "@/lib/audio/transcribe";

export type SynthNote = { midi: number; duration: number; gap?: number };

/** Whistle-like tone: sine fundamental, faint 2nd harmonic, light vibrato. */
export function renderMelody(
  melody: SynthNote[],
  sampleRate: number,
  leadIn = 0.12,
): { samples: Float32Array; notes: NoteEvent[] } {
  let t = leadIn;
  const notes: NoteEvent[] = [];
  for (const step of melody) {
    notes.push({
      id: `s${notes.length}`,
      midi: step.midi,
      frequency: midiToFreq(step.midi),
      start: t,
      duration: step.duration,
    });
    t += step.duration + (step.gap ?? 0.05);
  }

  const total = t + 0.15;
  const samples = new Float32Array(Math.ceil(total * sampleRate));

  for (const note of notes) {
    const freq = midiToFreq(note.midi);
    const start = Math.floor(note.start * sampleRate);
    const n = Math.floor(note.duration * sampleRate);
    for (let i = 0; i < n; i++) {
      const localT = i / sampleRate;
      const env = envelope(i, n);
      const vibrato = 1 + 0.004 * Math.sin(2 * Math.PI * 5.2 * localT);
      const phase = 2 * Math.PI * freq * vibrato * localT;
      const tone = Math.sin(phase) + 0.08 * Math.sin(2 * phase);
      const idx = start + i;
      if (idx < samples.length) {
        samples[idx] += 0.42 * env * tone;
      }
    }
  }

  return { samples, notes };
}

function envelope(i: number, n: number): number {
  const attack = Math.max(1, Math.floor(n * 0.08));
  const release = Math.max(1, Math.floor(n * 0.16));
  if (i < attack) return i / attack;
  if (i > n - release) return Math.max(0, (n - i) / release);
  return 1;
}

/** A short phrase in whistle range — opening of Ode to Joy, up an octave. */
export const DEMO_MELODY: SynthNote[] = [
  { midi: 76, duration: 0.32 },
  { midi: 76, duration: 0.32 },
  { midi: 77, duration: 0.32 },
  { midi: 79, duration: 0.32 },
  { midi: 79, duration: 0.32 },
  { midi: 77, duration: 0.32 },
  { midi: 76, duration: 0.32 },
  { midi: 74, duration: 0.32 },
  { midi: 72, duration: 0.32 },
  { midi: 72, duration: 0.32 },
  { midi: 74, duration: 0.32 },
  { midi: 76, duration: 0.32 },
  { midi: 76, duration: 0.48 },
  { midi: 74, duration: 0.22 },
  { midi: 74, duration: 0.5, gap: 0.1 },
];
