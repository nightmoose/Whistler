import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class WhistleSession {
    var mode: SourceMode = .whistle {
        didSet { recorder.mode = mode }
    }
    /// Mirrors ProStatus.isPro; set by the app.
    var isPro = false {
        didSet {
            if !isPro, !Gate(isPro: false).allows(mode: mode) {
                mode = .whistle
            }
        }
    }
    /// Set when the session wants the paywall shown (e.g. the free recording cap was hit).
    var paywallTrigger: PaywallTrigger?
    var isRecording = false
    var isBusy = false
    var live: LivePitch = .empty
    var elapsed: TimeInterval = 0
    var errorMessage: String?
    var transcription: Transcription?
    var selectedNoteID: String?
    var importedName: String?
    var autotuneEnabled = true
    var detectedKey: Autotune.Key?

    private let recorder = Recorder()
    private var original: (samples: [Float], sampleRate: Double)?
    private var ticker: Task<Void, Never>?
    private var startedAt: Date?

    var notes: [NoteEvent] {
        transcription?.notes ?? []
    }

    var selectedNote: NoteEvent? {
        notes.first { $0.id == selectedNoteID }
    }

    var nameLine: String {
        Transcribe.nameLine(notes, ascii: true)
    }

    var tab: GuitarTab {
        Guitar.tab(from: notes)
    }

    var hasOriginal: Bool { original != nil }

    var keyLabel: String? {
        guard autotuneEnabled, let detectedKey else { return nil }
        return detectedKey.name
    }

    init() {
        recorder.onLive = { [weak self] pitch in
            Task { @MainActor in
                self?.live = pitch
            }
        }
    }

    func toggle() {
        if isRecording {
            stop()
        } else {
            Task { await start() }
        }
    }

    func start() async {
        errorMessage = nil
        Playback.stop()
        transcription = nil
        original = nil
        selectedNoteID = nil
        importedName = nil
        detectedKey = nil
        live = .empty
        if !Gate(isPro: isPro).allows(mode: mode) { mode = .whistle }
        recorder.mode = mode

        let granted = await requestMic()
        guard granted else {
            errorMessage = "Microphone access is needed to catch a whistle. Enable it in Settings."
            return
        }

        do {
            try recorder.start()
            isRecording = true
            startedAt = Date()
            elapsed = 0
            ticker = Task { [weak self] in
                while let self, !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(100))
                    await MainActor.run {
                        if let started = self.startedAt, self.isRecording {
                            self.tick(elapsed: Date().timeIntervalSince(started))
                        }
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Updates the clock and enforces the free-tier cap: on hitting it the take is
    /// stopped cleanly (and still transcribed) and the paywall is requested.
    func tick(elapsed: TimeInterval) {
        guard isRecording else { return }
        if RecordingCap.shouldStop(elapsed: elapsed, isPro: isPro) {
            self.elapsed = RecordingCap.freeLimit
            stop()
            paywallTrigger = PaywallTrigger(reason: .recordingCap)
        } else {
            self.elapsed = elapsed
        }
    }

    /// Selects a source mode, or requests the paywall if it needs Pro.
    /// Returns true if the mode was selected.
    @discardableResult
    func select(mode newMode: SourceMode) -> Bool {
        guard Gate(isPro: isPro).allows(mode: newMode) else {
            if let feature = newMode.proFeature {
                paywallTrigger = PaywallTrigger(reason: .feature(feature))
            }
            return false
        }
        mode = newMode
        return true
    }

    func stop() {
        ticker?.cancel()
        ticker = nil
        isRecording = false
        live = .empty
        let captured = recorder.stop()
        finish(samples: captured.samples, sampleRate: captured.sampleRate, keepOriginal: true)
    }

    private func cancelRecording() {
        ticker?.cancel()
        ticker = nil
        isRecording = false
        live = .empty
        _ = recorder.stop()
    }

    func runDemo() {
        errorMessage = nil
        Playback.stop()
        isRecording = false
        let rendered = Synth.renderMelody(Synth.demoMelody, sampleRate: 44100)
        finish(samples: rendered.samples, sampleRate: 44100, keepOriginal: true)
        try? Playback.play(samples: rendered.samples, sampleRate: 44100)
    }

    func playScore() {
        guard !notes.isEmpty else { return }
        try? Playback.play(notes: notes, sampleRate: original?.sampleRate ?? 44100)
    }

    func stopPlayback() {
        Playback.stop()
    }

    func importMIDI(from url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let data = try Data(contentsOf: url)
            try importMIDI(data: data, name: url.deletingPathExtension().lastPathComponent)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn't read that MIDI file."
        }
    }

    func importMIDI(data: Data, name: String, play: Bool = true) throws {
        Playback.stop()
        if isRecording { cancelRecording() }
        let parsed = try MIDIFile.parse(data)
        original = nil
        selectedNoteID = nil
        importedName = name
        errorMessage = nil
        elapsed = parsed.duration
        publish(notes: parsed.notes, frames: [], duration: parsed.duration, sampleRate: 44100)
        if play {
            try? Playback.play(notes: notes)
        }
    }

    func playOriginal() {
        guard let original else { return }
        try? Playback.play(samples: original.samples, sampleRate: original.sampleRate)
    }

    func bumpSelected(by delta: Int) {
        guard let id = selectedNoteID, var transcription else { return }
        guard let index = transcription.notes.firstIndex(where: { $0.id == id }) else { return }
        let midi = max(40, min(100, transcription.notes[index].midi + delta))
        transcription.notes[index].midi = midi
        transcription.notes[index].rawMidi = Double(midi)
        transcription.notes[index].frequency = Notes.midiToFreq(midi)
        transcription.notes[index].locked = true
        self.transcription = transcription
    }

    func toggleAutotune() {
        autotuneEnabled.toggle()
        reapplyAutotune()
    }

    func reapplyAutotune() {
        guard var transcription else {
            detectedKey = nil
            return
        }
        let tuned = Autotune.apply(transcription.notes, enabled: autotuneEnabled)
        transcription.notes = tuned.notes
        detectedKey = tuned.key
        self.transcription = transcription
    }

    func dropSelected() {
        guard let id = selectedNoteID, var transcription else { return }
        transcription.notes.removeAll { $0.id == id }
        self.transcription = transcription
        selectedNoteID = nil
    }

    func clear() {
        Playback.stop()
        transcription = nil
        original = nil
        selectedNoteID = nil
        importedName = nil
        detectedKey = nil
        errorMessage = nil
        elapsed = 0
        live = .empty
    }

    func midiURL() throws -> URL {
        try MIDIFile.writeTemporary(notes)
    }

    private func finish(samples: [Float], sampleRate: Double, keepOriginal: Bool) {
        isBusy = true
        if keepOriginal {
            original = (samples, sampleRate)
        }
        let currentMode = mode
        Task.detached(priority: .userInitiated) {
            let result = Transcribe.run(samples: samples, sampleRate: sampleRate, mode: currentMode)
            await MainActor.run {
                self.publish(notes: result.notes, frames: result.frames, duration: result.duration, sampleRate: result.sampleRate)
                self.isBusy = false
                self.live = .empty
            }
        }
    }

    private func publish(notes: [NoteEvent], frames: [PitchFrame], duration: Double, sampleRate: Double) {
        let tuned = Autotune.apply(notes, enabled: autotuneEnabled)
        detectedKey = tuned.key
        transcription = Transcription(
            frames: frames,
            notes: tuned.notes,
            duration: duration,
            sampleRate: sampleRate
        )
    }

    private func requestMic() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
