"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { startCapture, type CaptureHandle } from "@/lib/audio/capture";
import { playNotes, playPcm, stopPlayback } from "@/lib/audio/playback";
import { DEMO_MELODY, renderMelody } from "@/lib/audio/synth";
import {
  SOURCE_RANGES,
  transcribe,
  type NoteEvent,
  type PitchFrame,
  type SourceMode,
  type Transcription,
} from "@/lib/audio/transcribe";
import { rms, yinPitch } from "@/lib/audio/yin";
import { freqToMidi } from "@/lib/music/notes";

export type LivePitch = {
  frequency: number | null;
  midi: number | null;
  confidence: number;
  rms: number;
};

const EMPTY_LIVE: LivePitch = { frequency: null, midi: null, confidence: 0, rms: 0 };

export function useWhistleRecorder() {
  const [mode, setMode] = useState<SourceMode>("whistle");
  const [recording, setRecording] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [live, setLive] = useState<LivePitch>(EMPTY_LIVE);
  const [elapsed, setElapsed] = useState(0);
  const [transcription, setTranscription] = useState<Transcription | null>(null);
  const [pcm, setPcm] = useState<{ samples: Float32Array; sampleRate: number } | null>(null);

  const captureRef = useRef<CaptureHandle | null>(null);
  const liveBufRef = useRef<Float32Array>(new Float32Array(2048));
  const liveLinearRef = useRef<Float32Array>(new Float32Array(2048));
  const liveOffsetRef = useRef(0);
  const lastLiveAtRef = useRef(0);
  const startedAtRef = useRef(0);
  const timerRef = useRef<number | null>(null);
  const modeRef = useRef(mode);

  useEffect(() => {
    modeRef.current = mode;
  }, [mode]);

  const resetLiveBuffer = () => {
    liveBufRef.current.fill(0);
    liveOffsetRef.current = 0;
  };

  const ingestLive = useCallback((chunk: Float32Array) => {
    const buf = liveBufRef.current;
    let offset = liveOffsetRef.current;
    for (let i = 0; i < chunk.length; i++) {
      buf[offset] = chunk[i];
      offset += 1;
      if (offset >= buf.length) offset = 0;
    }
    liveOffsetRef.current = offset;

    const now = performance.now();
    if (now - lastLiveAtRef.current < 50) return;
    lastLiveAtRef.current = now;

    const linear = liveLinearRef.current;
    linear.set(buf.subarray(offset), 0);
    linear.set(buf.subarray(0, offset), buf.length - offset);

    const range = SOURCE_RANGES[modeRef.current];
    const level = rms(linear);
    const yin = yinPitch(linear, captureRef.current?.sampleRate ?? 44100, {
      minFreq: range.minFreq,
      maxFreq: range.maxFreq,
      threshold: 0.12,
    });
    const voiced =
      yin.frequency !== null &&
      yin.confidence >= 0.55 &&
      level >= 0.004 &&
      yin.frequency >= range.minFreq * 0.92 &&
      yin.frequency <= range.maxFreq * 1.05;

    setLive({
      frequency: voiced ? yin.frequency : null,
      midi: voiced && yin.frequency ? freqToMidi(yin.frequency) : null,
      confidence: voiced ? yin.confidence : 0,
      rms: level,
    });
  }, []);

  const stopTimer = () => {
    if (timerRef.current !== null) {
      window.clearInterval(timerRef.current);
      timerRef.current = null;
    }
  };

  const start = useCallback(async () => {
    setError(null);
    stopPlayback();
    resetLiveBuffer();
    setTranscription(null);
    setPcm(null);
    setLive(EMPTY_LIVE);
    const hipass = modeRef.current === "hum" ? 70 : modeRef.current === "any" ? 60 : 350;
    try {
      const handle = await startCapture(ingestLive, hipass);
      captureRef.current = handle;
      startedAtRef.current = performance.now();
      setRecording(true);
      setElapsed(0);
      timerRef.current = window.setInterval(() => {
        setElapsed((performance.now() - startedAtRef.current) / 1000);
      }, 100);
    } catch (err) {
      const message = err instanceof Error ? err.message : "Microphone permission was denied.";
      setError(
        message.includes("Permission") || message.includes("NotAllowed")
          ? "Microphone access is needed to catch a whistle. Allow it and try again."
          : message,
      );
    }
  }, [ingestLive]);

  const finishSamples = useCallback(
    (samples: Float32Array, sampleRate: number) => {
      setBusy(true);
      try {
        const result = transcribe(samples, {
          sampleRate,
          mode: modeRef.current,
        });
        setTranscription(result);
        setPcm({ samples, sampleRate });
      } finally {
        setBusy(false);
        setLive(EMPTY_LIVE);
      }
    },
    [],
  );

  const stop = useCallback(() => {
    stopTimer();
    setRecording(false);
    const handle = captureRef.current;
    captureRef.current = null;
    if (!handle) return;
    const samples = handle.stop();
    finishSamples(samples, handle.sampleRate);
  }, [finishSamples]);

  const toggle = useCallback(() => {
    if (recording) stop();
    else void start();
  }, [recording, start, stop]);

  const runDemo = useCallback(async () => {
    setError(null);
    stopPlayback();
    setRecording(false);
    const sampleRate = 44100;
    const { samples } = renderMelody(DEMO_MELODY, sampleRate);
    finishSamples(samples, sampleRate);
    await playPcm(samples, sampleRate);
  }, [finishSamples]);

  const playScore = useCallback(async () => {
    if (transcription?.notes.length) await playNotes(transcription.notes);
  }, [transcription]);

  const playOriginal = useCallback(async () => {
    if (pcm) await playPcm(pcm.samples, pcm.sampleRate);
  }, [pcm]);

  const updateNote = useCallback((id: string, patch: Partial<NoteEvent>) => {
    setTranscription((current) => {
      if (!current) return current;
      return {
        ...current,
        notes: current.notes.map((n) => (n.id === id ? { ...n, ...patch } : n)),
      };
    });
  }, []);

  const removeNote = useCallback((id: string) => {
    setTranscription((current) => {
      if (!current) return current;
      return { ...current, notes: current.notes.filter((n) => n.id !== id) };
    });
  }, []);

  const clear = useCallback(() => {
    stopPlayback();
    setTranscription(null);
    setPcm(null);
    setError(null);
    setElapsed(0);
  }, []);

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (event.target instanceof HTMLInputElement || event.target instanceof HTMLSelectElement) return;
      if (event.code === "Space") {
        event.preventDefault();
        toggle();
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [toggle]);

  useEffect(() => {
    return () => {
      stopTimer();
      if (captureRef.current) captureRef.current.stop();
      stopPlayback();
    };
  }, []);

  return {
    mode,
    setMode,
    recording,
    busy,
    error,
    live,
    elapsed,
    transcription,
    start,
    stop,
    toggle,
    runDemo,
    playScore,
    playOriginal,
    updateNote,
    removeNote,
    clear,
    hasOriginal: Boolean(pcm),
  };
}

export type { PitchFrame };
