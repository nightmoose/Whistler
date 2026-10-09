"use client";

import { midiToName } from "@/lib/music/notes";
import type { NoteEvent } from "@/lib/audio/transcribe";

const STAFF_MIDI = [77, 74, 71, 67, 64]; // F5 D5 B4 G4 E4

function diatonicOffset(midi: number): number {
  const pc = ((midi % 12) + 12) % 12;
  const octave = Math.floor(midi / 12) - 1;
  const steps = [0, 0, 1, 1, 2, 3, 3, 4, 4, 5, 5, 6][pc];
  return (octave - 4) * 7 + steps;
}

function accidental(midi: number): "#" | "b" | null {
  const pc = ((midi % 12) + 12) % 12;
  if ([1, 3, 6, 8, 10].includes(pc)) return "#";
  return null;
}

export function StaffView({ notes }: { notes: NoteEvent[] }) {
  const width = Math.max(520, 80 + notes.length * 36);
  const height = 180;
  const origin = diatonicOffset(64);
  const lineGap = 12;
  const topLine = 36;

  const yFor = (midi: number) => {
    const steps = diatonicOffset(midi) - origin;
    return topLine + 4 * lineGap - steps * (lineGap / 2);
  };

  return (
    <div className="overflow-x-auto rounded-2xl border border-[var(--rule)] bg-[var(--paper)] p-4">
      <svg width={width} height={height} viewBox={`0 0 ${width} ${height}`} role="img" aria-label="Staff notation">
        {STAFF_MIDI.map((midi, i) => {
          const y = topLine + i * lineGap;
          return (
            <g key={midi}>
              <line x1={56} x2={width - 16} y1={y} y2={y} stroke="#1a1612" strokeWidth={1.1} />
              <text x={8} y={y + 4} fontSize={10} fill="#7a6c58" fontFamily="ui-monospace, monospace">
                {midiToName(midi, true).replace(/\d/, "")}
              </text>
            </g>
          );
        })}
        <text x={22} y={topLine + 3.2 * lineGap} fontSize={42} fill="#1a1612" fontFamily="Georgia, serif">
          𝄞
        </text>
        {notes.map((note, i) => {
          const x = 80 + i * 36;
          const y = yFor(note.midi);
          const acc = accidental(note.midi);
          const lowLedgers: number[] = [];
          const highLedgers: number[] = [];
          const step = diatonicOffset(note.midi);
          if (step < origin) {
            for (let s = origin - 2; s >= step; s -= 2) lowLedgers.push(s);
          }
          const topStep = origin + 8;
          if (step > topStep) {
            for (let s = topStep + 2; s <= step; s += 2) highLedgers.push(s);
          }
          const duration = note.duration;
          const filled = duration < 0.85;
          return (
            <g key={note.id}>
              {lowLedgers.map((s) => {
                const ly = topLine + 4 * lineGap - (s - origin) * (lineGap / 2);
                return <line key={s} x1={x - 10} x2={x + 18} y1={ly} y2={ly} stroke="#1a1612" strokeWidth={1} />;
              })}
              {highLedgers.map((s) => {
                const ly = topLine + 4 * lineGap - (s - origin) * (lineGap / 2);
                return <line key={s} x1={x - 10} x2={x + 18} y1={ly} y2={ly} stroke="#1a1612" strokeWidth={1} />;
              })}
              {acc ? (
                <text x={x - 14} y={y + 4} fontSize={14} fill="#1a1612" fontFamily="Georgia, serif">
                  {acc === "#" ? "♯" : "♭"}
                </text>
              ) : null}
              <ellipse
                cx={x + 4}
                cy={y}
                rx={7}
                ry={5}
                transform={`rotate(-18 ${x + 4} ${y})`}
                fill={filled ? "#1a1612" : "none"}
                stroke="#1a1612"
                strokeWidth={1.4}
              />
              {duration < 1.6 ? (
                <line
                  x1={x + 10}
                  x2={x + 10}
                  y1={y}
                  y2={y - 28}
                  stroke="#1a1612"
                  strokeWidth={1.3}
                />
              ) : null}
              {duration < 0.28 ? (
                <path d={`M${x + 10} ${y - 28} C ${x + 18} ${y - 22}, ${x + 16} ${y - 10}, ${x + 12} ${y - 8}`} fill="#1a1612" />
              ) : null}
            </g>
          );
        })}
      </svg>
    </div>
  );
}
