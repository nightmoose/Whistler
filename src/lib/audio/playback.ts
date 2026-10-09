import { midiToFreq } from "@/lib/music/notes";
import type { NoteEvent } from "@/lib/audio/transcribe";

let ctx: AudioContext | null = null;
let playing: OscillatorNode[] = [];

function getCtx(): AudioContext {
  if (!ctx || ctx.state === "closed") {
    ctx = new AudioContext();
  }
  return ctx;
}

export async function playNotes(notes: NoteEvent[], when = 0): Promise<void> {
  stopPlayback();
  const audio = getCtx();
  if (audio.state === "suspended") await audio.resume();
  const t0 = audio.currentTime + 0.05 + when;

  playing = [];
  for (const note of notes) {
    const osc = audio.createOscillator();
    const gain = audio.createGain();
    const harm = audio.createOscillator();
    const harmGain = audio.createGain();

    osc.type = "sine";
    harm.type = "sine";
    osc.frequency.value = midiToFreq(note.midi);
    harm.frequency.value = midiToFreq(note.midi) * 2;

    const start = t0 + note.start;
    const end = start + Math.max(0.05, note.duration);

    gain.gain.setValueAtTime(0.0001, start);
    gain.gain.exponentialRampToValueAtTime(0.18, start + 0.02);
    gain.gain.setValueAtTime(0.18, Math.max(start + 0.03, end - 0.05));
    gain.gain.exponentialRampToValueAtTime(0.0001, end);

    harmGain.gain.setValueAtTime(0.0001, start);
    harmGain.gain.exponentialRampToValueAtTime(0.02, start + 0.02);
    harmGain.gain.exponentialRampToValueAtTime(0.0001, end);

    osc.connect(gain);
    harm.connect(harmGain);
    gain.connect(audio.destination);
    harmGain.connect(audio.destination);
    osc.start(start);
    harm.start(start);
    osc.stop(end + 0.01);
    harm.stop(end + 0.01);
    playing.push(osc, harm);
  }
}

export async function playPcm(samples: Float32Array, sampleRate: number): Promise<void> {
  stopPlayback();
  const audio = getCtx();
  if (audio.state === "suspended") await audio.resume();
  const buffer = audio.createBuffer(1, samples.length, sampleRate);
  buffer.getChannelData(0).set(samples);
  const src = audio.createBufferSource();
  src.buffer = buffer;
  src.connect(audio.destination);
  src.start();
}

export function stopPlayback() {
  for (const osc of playing) {
    try {
      osc.stop();
      osc.disconnect();
    } catch {
      /* already stopped */
    }
  }
  playing = [];
}
