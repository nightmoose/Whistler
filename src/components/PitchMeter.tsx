"use client";

import { centsOff, midiToName } from "@/lib/music/notes";
import type { LivePitch } from "@/hooks/useWhistleRecorder";

export function PitchMeter({
  live,
  recording,
}: {
  live: LivePitch;
  recording: boolean;
}) {
  const hasPitch = live.midi !== null && live.frequency !== null;
  const name = hasPitch ? midiToName(live.midi!) : "—";
  const cents = hasPitch ? centsOff(live.midi!) : 0;
  const hz = hasPitch ? live.frequency!.toFixed(1) : "silence";
  const needle = Math.max(-50, Math.min(50, cents));

  return (
    <div className="relative overflow-hidden rounded-[28px] border border-[var(--hairline)] bg-[var(--panel)] px-6 py-7">
      <div
        className={`pointer-events-none absolute inset-0 transition-opacity ${
          recording ? "opacity-100" : "opacity-0"
        }`}
        style={{
          background:
            "radial-gradient(ellipse at 50% 120%, color-mix(in oklab, var(--blood) 28%, transparent), transparent 60%)",
        }}
      />
      <div className="relative flex flex-col items-center gap-4">
        <p className="text-[11px] font-medium uppercase tracking-[0.28em] text-[var(--muted)]">
          {recording ? "listening" : "ready"}
        </p>
        <p className="font-display text-7xl leading-none tracking-tight text-[var(--paper)] sm:text-8xl">
          {name}
        </p>
        <p className="font-mono text-sm text-[var(--muted)]">{hasPitch ? `${hz} Hz` : hz}</p>
        <div className="mt-2 w-full max-w-sm">
          <div className="relative h-2 rounded-full bg-[var(--ink-2)]">
            <div className="absolute left-1/2 top-0 h-full w-px bg-[var(--brass)]" />
            <div
              className="absolute top-1/2 h-4 w-4 -translate-y-1/2 rounded-full bg-[var(--brass)] shadow-[0_0_12px_var(--brass)] transition-all duration-75"
              style={{ left: `calc(50% + ${needle}%)`, marginLeft: "-8px" }}
            />
          </div>
          <div className="mt-2 flex justify-between font-mono text-[10px] text-[var(--muted)]">
            <span>−50¢</span>
            <span>in tune</span>
            <span>+50¢</span>
          </div>
        </div>
      </div>
    </div>
  );
}
