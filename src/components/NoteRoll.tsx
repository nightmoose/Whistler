"use client";

import { midiToName } from "@/lib/music/notes";
import type { NoteEvent } from "@/lib/audio/transcribe";

export function NoteRoll({
  notes,
  duration,
  selectedId,
  onSelect,
}: {
  notes: NoteEvent[];
  duration: number;
  selectedId?: string | null;
  onSelect?: (id: string) => void;
}) {
  if (notes.length === 0) {
    return (
      <div className="flex h-40 items-center justify-center rounded-2xl border border-dashed border-[var(--rule)] bg-[var(--paper)] text-sm text-[var(--ink-3)]">
        Notes will land here as the transcription settles.
      </div>
    );
  }

  const minMidi = Math.min(...notes.map((n) => n.midi)) - 2;
  const maxMidi = Math.max(...notes.map((n) => n.midi)) + 2;
  const span = Math.max(1, maxMidi - minMidi);
  const width = Math.max(640, duration * 140);
  const height = Math.max(160, span * 14 + 24);

  return (
    <div className="overflow-x-auto rounded-2xl border border-[var(--rule)] bg-[var(--paper)]">
      <svg
        width={width}
        height={height}
        viewBox={`0 0 ${width} ${height}`}
        role="img"
        aria-label="Piano roll of transcribed notes"
      >
        {Array.from({ length: span + 1 }, (_, i) => {
          const midi = maxMidi - i;
          const y = ((maxMidi - midi) / span) * (height - 20) + 10;
          const line = midi % 12 === 0;
          return (
            <g key={midi}>
              <line
                x1={48}
                x2={width}
                y1={y}
                y2={y}
                stroke={line ? "#d7c9a8" : "#eee4cc"}
                strokeWidth={line ? 1.2 : 0.6}
              />
              {line ? (
                <text x={8} y={y + 4} fontSize={10} fill="#7a6c58" fontFamily="ui-monospace, monospace">
                  {midiToName(midi, true)}
                </text>
              ) : null}
            </g>
          );
        })}
        {notes.map((note) => {
          const x = 48 + (note.start / duration) * (width - 64);
          const w = Math.max(10, (note.duration / duration) * (width - 64));
          const y = ((maxMidi - note.midi) / span) * (height - 20) + 4;
          const selected = note.id === selectedId;
          return (
            <g key={note.id} onClick={() => onSelect?.(note.id)} className="cursor-pointer">
              <rect
                x={x}
                y={y}
                width={w}
                height={12}
                rx={4}
                fill={selected ? "#c44536" : "#c4892a"}
                opacity={0.92}
              />
              {w > 28 ? (
                <text
                  x={x + 6}
                  y={y + 10}
                  fontSize={9}
                  fill="#fffaf0"
                  fontFamily="ui-monospace, monospace"
                >
                  {midiToName(note.midi, true)}
                </text>
              ) : null}
            </g>
          );
        })}
      </svg>
    </div>
  );
}
