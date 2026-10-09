import { freqToMidi, midiToName } from "@/lib/music/notes";
import { rms, yinPitch } from "@/lib/audio/yin";

export type SourceMode = "whistle" | "hum" | "any";

export const SOURCE_RANGES: Record<SourceMode, { minFreq: number; maxFreq: number }> = {
  whistle: { minFreq: 480, maxFreq: 4200 },
  hum: { minFreq: 80, maxFreq: 900 },
  any: { minFreq: 70, maxFreq: 5000 },
};

export type PitchFrame = {
  time: number;
  frequency: number | null;
  midi: number | null;
  rms: number;
  confidence: number;
};

export type NoteEvent = {
  id: string;
  midi: number;
  frequency: number;
  start: number;
  duration: number;
};

export type TranscribeOptions = {
  sampleRate: number;
  mode?: SourceMode;
  hopSize?: number;
  windowSize?: number;
  yinThreshold?: number;
  minNoteDuration?: number;
  minRms?: number;
  /** Split a note when pitch stays this many cents away. Vibrato lives under this. */
  pitchChangeCents?: number;
};

export type Transcription = {
  frames: PitchFrame[];
  notes: NoteEvent[];
  duration: number;
  sampleRate: number;
};

export function extractPitchTrack(
  samples: Float32Array,
  options: TranscribeOptions,
): PitchFrame[] {
  const mode = options.mode ?? "whistle";
  const { minFreq, maxFreq } = SOURCE_RANGES[mode];
  const hop = options.hopSize ?? 512;
  const windowSize = options.windowSize ?? 2048;
  const threshold = options.yinThreshold ?? 0.12;
  const { sampleRate } = options;
  const frames: PitchFrame[] = [];

  for (let start = 0; start + windowSize <= samples.length; start += hop) {
    const window = samples.subarray(start, start + windowSize);
    const level = rms(window);
    const yin = yinPitch(window, sampleRate, { minFreq, maxFreq, threshold });
    const inRange =
      yin.frequency !== null &&
      yin.frequency >= minFreq * 0.92 &&
      yin.frequency <= maxFreq * 1.05;
    const voiced = inRange && yin.confidence >= 0.55 && level >= (options.minRms ?? 0.004);

    frames.push({
      time: start / sampleRate,
      frequency: voiced ? yin.frequency : null,
      midi: voiced && yin.frequency ? freqToMidi(yin.frequency) : null,
      rms: level,
      confidence: voiced ? yin.confidence : 0,
    });
  }

  return frames;
}

export function segmentNotes(
  frames: PitchFrame[],
  options?: { minNoteDuration?: number; pitchChangeCents?: number },
): NoteEvent[] {
  const minDur = options?.minNoteDuration ?? 0.07;
  const splitCents = options?.pitchChangeCents ?? 90;
  const notes: NoteEvent[] = [];

  let active: { midis: number[]; freqs: number[]; start: number } | null = null;
  let pendingMidi: number | null = null;
  let pendingCount = 0;

  const close = (endTime: number) => {
    if (!active) return;
    const duration = endTime - active.start;
    if (duration >= minDur && active.midis.length > 0) {
      const midi = median(active.midis);
      const frequency = median(active.freqs);
      notes.push({
        id: `n${notes.length}-${active.start.toFixed(3)}`,
        midi: Math.round(midi),
        frequency,
        start: active.start,
        duration,
      });
    }
    active = null;
    pendingMidi = null;
    pendingCount = 0;
  };

  for (let i = 0; i < frames.length; i++) {
    const frame = frames[i];
    const nextTime = i + 1 < frames.length ? frames[i + 1].time : frame.time + 0.01;

    if (frame.midi === null || frame.frequency === null) {
      close(frame.time);
      continue;
    }

    const midiInt = Math.round(frame.midi);

    if (!active) {
      active = { midis: [frame.midi], freqs: [frame.frequency], start: frame.time };
      pendingMidi = null;
      pendingCount = 0;
      continue;
    }

    const current = median(active.midis);
    const cents = Math.abs(frame.midi - current) * 100;
    const jumped = cents >= splitCents && midiInt !== Math.round(current);

    if (jumped) {
      if (pendingMidi === midiInt) {
        pendingCount += 1;
      } else {
        pendingMidi = midiInt;
        pendingCount = 1;
      }
      if (pendingCount >= 2) {
        close(frame.time);
        active = { midis: [frame.midi], freqs: [frame.frequency], start: frame.time };
        pendingMidi = null;
        pendingCount = 0;
      } else {
        active.midis.push(frame.midi);
        active.freqs.push(frame.frequency);
      }
    } else {
      pendingMidi = null;
      pendingCount = 0;
      active.midis.push(frame.midi);
      active.freqs.push(frame.frequency);
    }

    if (i === frames.length - 1) {
      close(nextTime);
    }
  }

  if (active) {
    const last = frames[frames.length - 1];
    close(last.time + 0.01);
  }

  return mergeTinyNeighbors(notes);
}

export function transcribe(
  samples: Float32Array,
  options: TranscribeOptions,
): Transcription {
  const frames = extractPitchTrack(samples, options);
  const notes = segmentNotes(frames, {
    minNoteDuration: options.minNoteDuration,
    pitchChangeCents: options.pitchChangeCents,
  });
  return {
    frames,
    notes,
    duration: samples.length / options.sampleRate,
    sampleRate: options.sampleRate,
  };
}

export function notesToNameLine(notes: NoteEvent[], ascii = false): string {
  return notes.map((n) => midiToName(n.midi, ascii)).join("  ");
}

function median(values: number[]): number {
  if (values.length === 0) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid];
}

function mergeTinyNeighbors(notes: NoteEvent[]): NoteEvent[] {
  if (notes.length < 2) return notes;
  const out: NoteEvent[] = [];
  for (const note of notes) {
    const prev = out[out.length - 1];
    const gap = prev ? note.start - (prev.start + prev.duration) : Infinity;
    const flicker = prev && (prev.duration < 0.11 || note.duration < 0.11);
    if (prev && prev.midi === note.midi && gap < 0.05 && flicker) {
      prev.duration = note.start + note.duration - prev.start;
    } else {
      out.push({ ...note });
    }
  }
  return out;
}
