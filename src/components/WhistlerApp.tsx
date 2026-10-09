"use client";

import { useMemo, useState, type ReactNode } from "react";
import { downloadMidi } from "@/lib/audio/midi";
import { noteListText, notesToTab } from "@/lib/audio/tab";
import { notesToNameLine, type SourceMode } from "@/lib/audio/transcribe";
import { midiToFreq, midiToName } from "@/lib/music/notes";
import { useWhistleRecorder } from "@/hooks/useWhistleRecorder";
import { NoteRoll } from "@/components/NoteRoll";
import { PitchMeter } from "@/components/PitchMeter";
import { StaffView } from "@/components/StaffView";
import { TabView } from "@/components/TabView";

const MODES: { id: SourceMode; label: string; hint: string }[] = [
  { id: "whistle", label: "Whistle", hint: "500 Hz – 4 kHz" },
  { id: "hum", label: "Hum", hint: "low voice" },
  { id: "any", label: "Any", hint: "wider catch" },
];

export function WhistlerApp() {
  const rec = useWhistleRecorder();
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const notes = useMemo(() => rec.transcription?.notes ?? [], [rec.transcription]);
  const selected = notes.find((n) => n.id === selectedId) ?? null;

  const summary = useMemo(() => notesToNameLine(notes, true), [notes]);

  const copy = async (text: string) => {
    await navigator.clipboard.writeText(text);
  };

  return (
    <div className="mx-auto flex w-full max-w-5xl flex-1 flex-col gap-8 px-5 py-8 sm:py-12">
      <header className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <p className="text-[11px] font-medium uppercase tracking-[0.32em] text-[var(--brass)]">
            on-device transcription
          </p>
          <h1 className="font-display mt-2 text-5xl tracking-tight text-[var(--paper)] sm:text-6xl">
            Whistler
          </h1>
          <p className="mt-3 max-w-xl text-[15px] leading-6 text-[var(--muted)]">
            Whistle a melody you made up. The app hears the pitches, writes the notes, and
            hands you MIDI, staff, and guitar tab — nothing leaves this device.
          </p>
        </div>
        <p className="font-mono text-xs text-[var(--muted)]">space to record</p>
      </header>

      <PitchMeter live={rec.live} recording={rec.recording} />

      <section className="flex flex-col items-center gap-5">
        <button
          type="button"
          onClick={rec.toggle}
          aria-pressed={rec.recording}
          className={`relative grid h-28 w-28 place-items-center rounded-full border-4 transition ${
            rec.recording
              ? "border-[var(--blood)] bg-[var(--blood)] shadow-[0_0_0_12px_rgba(196,69,54,0.18)]"
              : "border-[var(--brass)] bg-[var(--ink-2)] hover:bg-[var(--ink-3)]"
          }`}
        >
          <span
            className={`block bg-[var(--paper)] transition-all ${
              rec.recording ? "h-8 w-8 rounded-md" : "h-16 w-16 rounded-full"
            }`}
          />
          <span className="sr-only">{rec.recording ? "Stop recording" : "Start recording"}</span>
        </button>
        <div className="flex items-center gap-3 font-mono text-sm text-[var(--muted)]">
          <span>{formatTime(rec.elapsed)}</span>
          <span aria-hidden>·</span>
          <span>{rec.recording ? "whistling…" : rec.busy ? "transcribing…" : "idle"}</span>
        </div>
        {rec.error ? (
          <p className="max-w-md text-center text-sm text-[var(--blood)]">{rec.error}</p>
        ) : null}

        <div className="flex flex-wrap items-center justify-center gap-2">
          {MODES.map((mode) => (
            <button
              key={mode.id}
              type="button"
              disabled={rec.recording}
              onClick={() => rec.setMode(mode.id)}
              className={`rounded-full px-3 py-1.5 text-xs font-medium transition ${
                rec.mode === mode.id
                  ? "bg-[var(--brass)] text-[var(--ink)]"
                  : "bg-[var(--ink-2)] text-[var(--muted)] hover:text-[var(--paper)]"
              }`}
            >
              {mode.label}
              <span className="ml-1 opacity-70">{mode.hint}</span>
            </button>
          ))}
        </div>

        <div className="flex flex-wrap justify-center gap-2">
          <GhostButton onClick={() => void rec.runDemo()}>Play a demo whistle</GhostButton>
          {notes.length > 0 ? (
            <>
              <GhostButton onClick={() => void rec.playScore()}>Play notes</GhostButton>
              {rec.hasOriginal ? (
                <GhostButton onClick={() => void rec.playOriginal()}>Play original</GhostButton>
              ) : null}
              <GhostButton onClick={() => downloadMidi(notes)}>Download MIDI</GhostButton>
              <GhostButton onClick={() => void copy(summary)}>Copy note names</GhostButton>
              <GhostButton onClick={() => void copy(notesToTab(notes).ascii)}>Copy tab</GhostButton>
              <GhostButton onClick={rec.clear}>Clear</GhostButton>
            </>
          ) : null}
        </div>
      </section>

      {notes.length > 0 ? (
        <section className="flex flex-col gap-4">
          <div className="flex flex-wrap items-baseline justify-between gap-2">
            <h2 className="font-display text-2xl text-[var(--paper)]">The tune</h2>
            <p className="font-mono text-sm text-[var(--brass)]">{summary}</p>
          </div>
          <NoteRoll
            notes={notes}
            duration={Math.max(rec.transcription?.duration ?? 1, lastEnd(notes))}
            selectedId={selectedId}
            onSelect={setSelectedId}
          />
          {selected ? (
            <div className="flex flex-wrap items-center gap-3 rounded-2xl border border-[var(--hairline)] bg-[var(--panel)] px-4 py-3 text-sm">
              <span className="font-mono text-[var(--paper)]">{midiToName(selected.midi, true)}</span>
              <button
                type="button"
                className="rounded-md bg-[var(--ink-2)] px-2 py-1 text-[var(--paper)]"
                onClick={() =>
                  rec.updateNote(selected.id, {
                    midi: selected.midi + 1,
                    frequency: midiToFreq(selected.midi + 1),
                  })
                }
              >
                ♯ up
              </button>
              <button
                type="button"
                className="rounded-md bg-[var(--ink-2)] px-2 py-1 text-[var(--paper)]"
                onClick={() =>
                  rec.updateNote(selected.id, {
                    midi: selected.midi - 1,
                    frequency: midiToFreq(selected.midi - 1),
                  })
                }
              >
                ♭ down
              </button>
              <button
                type="button"
                className="rounded-md px-2 py-1 text-[var(--blood)]"
                onClick={() => rec.removeNote(selected.id)}
              >
                drop note
              </button>
            </div>
          ) : (
            <p className="text-xs text-[var(--muted)]">Tap a note in the roll to nudge a pitch.</p>
          )}
          <div className="grid gap-4 lg:grid-cols-2">
            <div>
              <h3 className="mb-2 text-xs uppercase tracking-[0.2em] text-[var(--muted)]">Staff</h3>
              <StaffView notes={notes} />
            </div>
            <div>
              <h3 className="mb-2 text-xs uppercase tracking-[0.2em] text-[var(--muted)]">
                Guitar tab
              </h3>
              <TabView notes={notes} />
            </div>
          </div>
          <p className="text-xs leading-5 text-[var(--muted)]">
            MIDI keeps your original timing so it drops into a DAW. Tab is shifted into a
            playable guitar octave when the whistle sits too high. {noteListText(notes)}
          </p>
        </section>
      ) : (
        <section className="rounded-[28px] border border-dashed border-[var(--hairline)] px-6 py-10 text-center">
          <p className="font-display text-2xl text-[var(--paper)]">A quiet room helps.</p>
          <p className="mx-auto mt-3 max-w-md text-sm leading-6 text-[var(--muted)]">
            Whistling is almost a pure sine, which is why this works. Hold each pitch a
            beat, leave a little air between notes, and skip the vibrato if you want a
            cleaner score. Try the demo if you just want to see the pipeline fire.
          </p>
        </section>
      )}
    </div>
  );
}

function GhostButton({
  children,
  onClick,
}: {
  children: ReactNode;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="rounded-full border border-[var(--hairline)] bg-[var(--panel)] px-3.5 py-1.5 text-xs text-[var(--paper)] transition hover:border-[var(--brass)] hover:text-[var(--brass)]"
    >
      {children}
    </button>
  );
}

function formatTime(seconds: number): string {
  const s = Math.max(0, seconds);
  const m = Math.floor(s / 60);
  const r = Math.floor(s % 60);
  const tenths = Math.floor((s % 1) * 10);
  return `${m}:${r.toString().padStart(2, "0")}.${tenths}`;
}

function lastEnd(notes: { start: number; duration: number }[]): number {
  return notes.reduce((max, n) => Math.max(max, n.start + n.duration), 0.5);
}
