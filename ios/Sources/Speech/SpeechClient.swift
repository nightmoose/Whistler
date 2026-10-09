import Foundation

enum SpeechError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}

struct SpeechTake: Equatable {
    var audio: Data
    var spoken: String
    var filename: String
    var direction: SpeechDirection
}

struct SpeechClient {
    var apiKey: String
    var session: URLSession = .shared

    func voices() async -> [VoiceChoice] {
        guard !apiKey.isEmpty, let url = URL(string: "https://api.x.ai/v1/tts/voices") else {
            return SpeechMarkup.fallbackVoices
        }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return SpeechMarkup.fallbackVoices }
            let choices = SpeechMarkup.normalizeVoices(data)
            return choices.isEmpty ? SpeechMarkup.fallbackVoices : choices
        } catch {
            return SpeechMarkup.fallbackVoices
        }
    }

    func generate(_ request: SpeechRequest) async throws -> SpeechTake {
        if apiKey.isEmpty {
            throw SpeechError.message("Save an API key on this phone first.")
        }
        var spoken = request.text
        var direction = SpeechDirection.none
        if !request.how.isEmpty {
            let directed = try await shape(request.text, how: request.how)
            let applied = SpeechMarkup.applyDirection(original: request.text, directed: directed)
            spoken = applied.spoken
            direction = applied.direction
        }
        let (status, data) = try await post(
            URL(string: "https://api.x.ai/v1/tts")!,
            body: SpeechMarkup.ttsBody(request, spoken: spoken),
            timeout: 60,
            offline: "Could not reach the speech service."
        )
        if !(200..<300).contains(status) || !SpeechMarkup.looksLikeWav(data) {
            let detail = SpeechMarkup.apiFailure(status: status, body: String(decoding: data, as: UTF8.self))
            throw SpeechError.message(detail)
        }
        return SpeechTake(audio: data, spoken: spoken, filename: SpeechMarkup.fileName(for: request.text), direction: direction)
    }

    private func shape(_ text: String, how: String) async throws -> String? {
        let (status, data) = try await post(
            URL(string: "https://api.x.ai/v1/responses")!,
            body: SpeechMarkup.directionBody(text: text, how: how),
            timeout: 45,
            offline: "Could not reach Grok to shape the delivery."
        )
        if !(200..<300).contains(status) {
            throw SpeechError.message(SpeechMarkup.apiFailure(status: status, body: String(decoding: data, as: UTF8.self)))
        }
        guard let spoken = SpeechMarkup.readDirection(data) else {
            throw SpeechError.message("Grok did not return a usable delivery.")
        }
        return spoken
    }

    private func post(_ url: URL, body: [String: Any], timeout: TimeInterval, offline: String) async throws -> (Int, Data) {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await session.data(for: request)
            return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
        } catch {
            throw SpeechError.message(offline)
        }
    }
}
