export type YinResult = {
  frequency: number | null;
  confidence: number;
  tau: number | null;
};

export function rms(samples: ArrayLike<number>): number {
  let sum = 0;
  const n = samples.length;
  for (let i = 0; i < n; i++) {
    const v = samples[i];
    sum += v * v;
  }
  return Math.sqrt(sum / n);
}

/**
 * YIN fundamental-frequency estimator (de Cheveigné & Kawahara, 2002).
 * Whistling is nearly sinusoidal, so the CMNDF dip is usually very deep.
 */
export function yinPitch(
  samples: ArrayLike<number>,
  sampleRate: number,
  options?: {
    minFreq?: number;
    maxFreq?: number;
    threshold?: number;
  },
): YinResult {
  const minFreq = options?.minFreq ?? 80;
  const maxFreq = options?.maxFreq ?? 5000;
  const threshold = options?.threshold ?? 0.12;
  const n = samples.length;

  const tauMin = Math.max(2, Math.floor(sampleRate / maxFreq));
  const tauMax = Math.min(Math.floor(n / 2) - 1, Math.floor(sampleRate / minFreq));
  if (tauMax <= tauMin + 2) {
    return { frequency: null, confidence: 0, tau: null };
  }

  const d = new Float32Array(tauMax + 1);
  for (let tau = 1; tau <= tauMax; tau++) {
    let sum = 0;
    const limit = n - tau;
    for (let i = 0; i < limit; i++) {
      const delta = samples[i] - samples[i + tau];
      sum += delta * delta;
    }
    d[tau] = sum;
  }

  const cmndf = new Float32Array(tauMax + 1);
  cmndf[0] = 1;
  let running = 0;
  for (let tau = 1; tau <= tauMax; tau++) {
    running += d[tau];
    cmndf[tau] = running > 0 ? (d[tau] * tau) / running : 1;
  }

  let tauEstimate = -1;
  for (let tau = tauMin; tau < tauMax; tau++) {
    if (cmndf[tau] < threshold) {
      while (tau + 1 <= tauMax && cmndf[tau + 1] < cmndf[tau]) {
        tau += 1;
      }
      tauEstimate = tau;
      break;
    }
  }

  if (tauEstimate < 0) {
    let minVal = 1;
    let minTau = -1;
    for (let tau = tauMin; tau <= tauMax; tau++) {
      if (cmndf[tau] < minVal) {
        minVal = cmndf[tau];
        minTau = tau;
      }
    }
    if (minVal < 0.28) {
      tauEstimate = minTau;
    } else {
      return { frequency: null, confidence: 0, tau: null };
    }
  }

  let betterTau = tauEstimate;
  if (tauEstimate > 0 && tauEstimate < tauMax) {
    const s0 = cmndf[tauEstimate - 1];
    const s1 = cmndf[tauEstimate];
    const s2 = cmndf[tauEstimate + 1];
    const denom = 2 * (2 * s1 - s2 - s0);
    if (Math.abs(denom) > 1e-12) {
      betterTau = tauEstimate + (s2 - s0) / denom;
    }
  }

  if (betterTau <= 0) {
    return { frequency: null, confidence: 0, tau: null };
  }

  return {
    frequency: sampleRate / betterTau,
    confidence: 1 - cmndf[tauEstimate],
    tau: betterTau,
  };
}
