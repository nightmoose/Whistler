import { midiToName } from "@/lib/music/notes";
import type { NoteEvent } from "@/lib/audio/transcribe";

/** Standard tuning, high string first. */
export const GUITAR_STRINGS = [
  { name: "e", midi: 64 },
  { name: "B", midi: 59 },
  { name: "G", midi: 55 },
  { name: "D", midi: 50 },
  { name: "A", midi: 45 },
  { name: "E", midi: 40 },
] as const;

export type TabHit = {
  string: number;
  fret: number;
  midi: number;
  start: number;
  duration: number;
};

export type GuitarTab = {
  hits: TabHit[];
  octaveShift: number;
  ascii: string;
};

function placeNote(midi: number, preferFret: number): { string: number; fret: number } | null {
  let best: { string: number; fret: number; cost: number } | null = null;
  for (let s = 0; s < GUITAR_STRINGS.length; s++) {
    const fret = midi - GUITAR_STRINGS[s].midi;
    if (fret < 0 || fret > 20) continue;
    const cost = Math.abs(fret - preferFret) + s * 0.15 + (fret > 12 ? fret - 12 : 0);
    if (!best || cost < best.cost) {
      best = { string: s, fret, cost };
    }
  }
  return best ? { string: best.string, fret: best.fret } : null;
}

/** Drop the melody into a playable guitar register. */
export function guitarOctaveShift(notes: NoteEvent[]): number {
  if (notes.length === 0) return 0;
  const maxMidi = Math.max(...notes.map((n) => n.midi));
  const minMidi = Math.min(...notes.map((n) => n.midi));
  let shift = 0;
  let high = maxMidi;
  let low = minMidi;
  while (high > 76 && low - 12 >= 40) {
    shift -= 12;
    high -= 12;
    low -= 12;
  }
  while (low < 40) {
    shift += 12;
    high += 12;
    low += 12;
  }
  return shift;
}

export function notesToTab(notes: NoteEvent[]): GuitarTab {
  const octaveShift = guitarOctaveShift(notes);
  const hits: TabHit[] = [];
  let preferFret = 3;

  for (const note of notes) {
    const midi = note.midi + octaveShift;
    const placed = placeNote(midi, preferFret);
    if (!placed) continue;
    hits.push({
      string: placed.string,
      fret: placed.fret,
      midi,
      start: note.start,
      duration: note.duration,
    });
    preferFret = placed.fret;
  }

  return { hits, octaveShift, ascii: renderAsciiTab(hits) };
}

export function renderAsciiTab(hits: TabHit[], colsPerSecond = 8): string {
  if (hits.length === 0) {
    return GUITAR_STRINGS.map((s) => `${s.name}|--|`).join("\n");
  }
  const last = hits[hits.length - 1];
  const totalTime = last.start + last.duration;
  const cols = Math.max(8, Math.ceil(totalTime * colsPerSecond) + 4);
  const rows = GUITAR_STRINGS.map(() => Array.from({ length: cols }, () => "-"));

  for (const hit of hits) {
    const col = Math.min(cols - 2, Math.max(0, Math.round(hit.start * colsPerSecond)));
    const label = String(hit.fret);
    for (let i = 0; i < label.length; i++) {
      if (col + i < cols) rows[hit.string][col + i] = label[i];
    }
  }

  return GUITAR_STRINGS.map((s, i) => `${s.name}|${rows[i].join("")}|`).join("\n");
}

export function octaveShiftLabel(shift: number): string | null {
  if (shift === 0) return null;
  const octaves = Math.abs(shift / 12);
  const dir = shift < 0 ? "lower" : "higher";
  return `Tab is ${octaves} octave${octaves === 1 ? "" : "s"} ${dir} than the whistle`;
}

export function noteListText(notes: NoteEvent[]): string {
  return notes.map((n) => midiToName(n.midi, true)).join(" ");
}
