export type CaptureHandle = {
  sampleRate: number;
  stop: () => Float32Array;
};

type ChunkHandler = (chunk: Float32Array) => void;

async function connectTap(
  ctx: AudioContext,
  source: AudioNode,
  onChunk: ChunkHandler,
): Promise<() => void> {
  const mute = ctx.createGain();
  mute.gain.value = 0;

  try {
    await ctx.audioWorklet.addModule("/worklets/capture-processor.js");
    const node = new AudioWorkletNode(ctx, "capture-processor");
    node.port.onmessage = (event: MessageEvent<Float32Array>) => {
      onChunk(event.data);
    };
    source.connect(node);
    node.connect(mute);
    mute.connect(ctx.destination);
    return () => {
      node.port.onmessage = null;
      node.disconnect();
      mute.disconnect();
    };
  } catch {
    const bufferSize = 2048;
    const processor = ctx.createScriptProcessor(bufferSize, 1, 1);
    processor.onaudioprocess = (event) => {
      onChunk(event.inputBuffer.getChannelData(0).slice());
    };
    source.connect(processor);
    processor.connect(mute);
    mute.connect(ctx.destination);
    return () => {
      processor.onaudioprocess = null;
      processor.disconnect();
      mute.disconnect();
    };
  }
}

export async function startCapture(
  onLiveChunk: ChunkHandler,
  modeHighpassHz: number,
): Promise<CaptureHandle> {
  const stream = await navigator.mediaDevices.getUserMedia({
    audio: {
      echoCancellation: false,
      noiseSuppression: false,
      autoGainControl: false,
      channelCount: 1,
    },
  });

  const ctx = new AudioContext();
  if (ctx.state === "suspended") await ctx.resume();

  const source = ctx.createMediaStreamSource(stream);
  const filter = ctx.createBiquadFilter();
  filter.type = "highpass";
  filter.frequency.value = modeHighpassHz;
  filter.Q.value = 0.7;
  source.connect(filter);

  const chunks: Float32Array[] = [];
  const disconnect = await connectTap(ctx, filter, (chunk) => {
    const copy = chunk instanceof Float32Array ? chunk.slice() : Float32Array.from(chunk);
    chunks.push(copy);
    onLiveChunk(copy);
  });

  return {
    sampleRate: ctx.sampleRate,
    stop: () => {
      disconnect();
      source.disconnect();
      filter.disconnect();
      for (const track of stream.getTracks()) track.stop();
      void ctx.close();
      return concat(chunks);
    },
  };
}

function concat(chunks: Float32Array[]): Float32Array {
  let total = 0;
  for (const c of chunks) total += c.length;
  const out = new Float32Array(total);
  let offset = 0;
  for (const c of chunks) {
    out.set(c, offset);
    offset += c.length;
  }
  return out;
}
