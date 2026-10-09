import AVFoundation
import Foundation
import QuartzCore

struct LivePitch: Equatable {
    var frequency: Double?
    var midi: Double?
    var confidence: Double
    var rms: Double

    static let empty = LivePitch(frequency: nil, midi: nil, confidence: 0, rms: 0)

    var isVoiced: Bool { frequency != nil }
}

final class Recorder {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var captured: [Float] = []
    private var liveBuf = [Float](repeating: 0, count: 2048)
    private var liveOffset = 0
    private var lastLiveAt: CFTimeInterval = 0
    private(set) var sampleRate: Double = 44100
    var mode: SourceMode = .whistle
    var onLive: ((LivePitch) -> Void)?

    var isRunning: Bool { engine.isRunning }

    func start() throws {
        stopEngine()
        captured.removeAll(keepingCapacity: true)
        liveBuf = [Float](repeating: 0, count: 2048)
        liveOffset = 0

        try Playback.configureSession()
        let session = AVAudioSession.sharedInstance()
        try session.setPreferredSampleRate(44100)
        try session.setPreferredIOBufferDuration(0.01)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        sampleRate = format.sampleRate
        let channels = Int(format.channelCount)

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.ingest(buffer: buffer, channels: channels)
        }
        try engine.start()
    }

    func stop() -> (samples: [Float], sampleRate: Double) {
        stopEngine()
        lock.lock()
        let samples = captured
        captured = []
        lock.unlock()
        return (samples, sampleRate)
    }

    private func stopEngine() {
        if engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            engine.reset()
        }
    }

    private func ingest(buffer: AVAudioPCMBuffer, channels: Int) {
        let frames = Int(buffer.frameLength)
        guard frames > 0, let data = buffer.floatChannelData else { return }
        var mono = [Float](repeating: 0, count: frames)
        if channels <= 1 {
            for i in 0..<frames { mono[i] = data[0][i] }
        } else {
            for i in 0..<frames {
                var s: Float = 0
                for c in 0..<channels {
                    s += data[c][i]
                }
                mono[i] = s / Float(channels)
            }
        }

        lock.lock()
        captured.append(contentsOf: mono)
        lock.unlock()

        for sample in mono {
            liveBuf[liveOffset] = sample
            liveOffset += 1
            if liveOffset >= liveBuf.count { liveOffset = 0 }
        }

        let now = CACurrentMediaTime()
        guard now - lastLiveAt >= 0.05 else { return }
        lastLiveAt = now

        var linear = [Float](repeating: 0, count: liveBuf.count)
        let head = liveBuf.count - liveOffset
        if head > 0 {
            linear.replaceSubrange(0..<head, with: liveBuf[liveOffset..<liveBuf.count])
        }
        if liveOffset > 0 {
            linear.replaceSubrange(head..<liveBuf.count, with: liveBuf[0..<liveOffset])
        }

        let level = Yin.rms(linear)
        let yin = Yin.pitch(
            samples: linear,
            sampleRate: sampleRate,
            minFreq: mode.minFreq,
            maxFreq: mode.maxFreq,
            threshold: Voicing.yinThreshold
        )
        let inRange = yin.frequency.map { $0 >= mode.minFreq * 0.92 && $0 <= mode.maxFreq * 1.05 } ?? false
        let voiced = inRange && yin.confidence >= Voicing.minConfidence && level >= Voicing.minRms
        let pitch = LivePitch(
            frequency: voiced ? yin.frequency : nil,
            midi: voiced ? yin.frequency.map(Notes.freqToMidi) : nil,
            confidence: voiced ? yin.confidence : 0,
            rms: level
        )
        onLive?(pitch)
    }
}
