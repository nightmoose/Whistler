import Foundation
import Observation

@MainActor
@Observable
final class SpeakModel {
    var text = ""
    var how = ""
    var voiceId = "eve"
    var customVoice = ""
    var speed = 1.0
    var language = "en"
    var voices = SpeechMarkup.fallbackVoices
    var keyDraft = ""
    var hasKey = false
    var replacingKey = false
    var busy = false
    var status = ""
    var spoken = ""
    var direction = SpeechDirection.none
    var fileURL: URL?

    func prepare() async {
        hasKey = APIKeyStore.load() != nil
        replacingKey = !hasKey
        guard let key = APIKeyStore.load() else { return }
        voices = await SpeechClient(apiKey: key).voices()
        if let first = voices.first, !voices.contains(where: { $0.voiceId == voiceId }) {
            voiceId = first.voiceId
        }
    }

    func saveKey() {
        guard APIKeyStore.save(keyDraft) else {
            status = "That key could not be saved."
            return
        }
        keyDraft = ""
        hasKey = true
        replacingKey = false
        status = "Key saved on this phone."
        Task { await prepare() }
    }

    func forgetKey() {
        APIKeyStore.clear()
        hasKey = false
        replacingKey = true
        voices = SpeechMarkup.fallbackVoices
        status = "Key removed from this phone."
    }

    func addDirection(_ phrase: String) {
        how = SpeechMarkup.adding(phrase, to: how)
    }

    func keepReading() {
        guard !spoken.isEmpty else { return }
        text = spoken
        how = ""
    }

    func generate() async {
        guard !busy else { return }
        let chosen = customVoice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? voiceId : customVoice
        switch SpeechMarkup.parse(text: text, how: how, voiceId: chosen, speed: speed, language: language) {
        case .failure(let error):
            status = error.message
            return
        case .success(let request):
            guard let key = APIKeyStore.load() else {
                hasKey = false
                replacingKey = true
                status = "Save an API key on this phone first."
                return
            }
            busy = true
            status = request.how.isEmpty ? "Recording the take…" : "Shaping the delivery, then recording the take…"
            spoken = ""
            fileURL = nil
            defer { busy = false }
            do {
                let take = try await SpeechClient(apiKey: key).generate(request)
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(take.filename)
                try take.audio.write(to: url, options: Data.WritingOptions.atomic)
                fileURL = url
                spoken = take.spoken
                direction = take.direction
                switch take.direction {
                case .rejected:
                    status = "\(take.filename) is ready. The direction would have changed the words, so this take uses the line as written."
                case .applied where take.spoken != request.text:
                    status = "\(take.filename) is ready. The reading is below if you want to keep it."
                default:
                    status = "\(take.filename) is ready."
                }
            } catch {
                status = error.localizedDescription
            }
        }
    }

    func play() {
        guard let fileURL else { return }
        do {
            try Playback.play(file: fileURL)
        } catch {
            status = "Could not play that take."
        }
    }
}
