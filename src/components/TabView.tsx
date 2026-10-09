"use client";

import { notesToTab, octaveShiftLabel } from "@/lib/audio/tab";
import type { NoteEvent } from "@/lib/audio/transcribe";

export function TabView({ notes }: { notes: NoteEvent[] }) {
  const tab = notesToTab(notes);
  const shift = octaveShiftLabel(tab.octaveShift);

  return (
    <div className="rounded-2xl border border-[var(--rule)] bg-[var(--paper)] p-4">
      {shift ? <p className="mb-3 text-xs text-[var(--ink-3)]">{shift}</p> : null}
      <pre className="overflow-x-auto font-mono text-[13px] leading-6 text-[var(--ink)]">{tab.ascii}</pre>
    </div>
  );
}
