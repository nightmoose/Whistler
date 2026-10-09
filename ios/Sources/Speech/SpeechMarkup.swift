import Foundation

enum SpeechDirection: String, Equatable {
    case none
    case applied
    case rejected
}

struct SpeechParseError: Error, Equatable {
    var message: String
}

struct VoiceChoice: Equatable, Identifiable {
    var voiceId: String
    var name: String
    var id: String { voiceId }
}

struct SpeechRequest: Equatable {
    var text: String
    var how: String
    var voiceId: String
    var speed: Double
    var language: String
}

enum SpeechMarkup {
    static let sampleRate = 48_000
    static let speedMin = 0.7
    static let speedMax = 1.5
    static let textLimit = 4_000
    static let howLimit = 400
    static let model = "grok-4.7"

    static let inlineTags = [
        "pause", "long-pause", "hum-tune", "laugh", "chuckle", "giggle", "cry",
        "tsk", "tongue-click", "lip-smack", "breath", "inhale", "exhale", "sigh",
    ]
    static let wrapTags = [
        "soft", "whisper", "loud", "build-intensity", "decrease-intensity",
        "higher-pitch", "lower-pitch", "slow", "fast", "sing-song", "singing", "emphasis",
    ]
    static let languages: [(code: String, label: String)] = [
        ("en", "English"),
        ("auto", "Detect language"),
        ("ar-EG", "Arabic (Egypt)"),
        ("ar-SA", "Arabic (Saudi Arabia)"),
        ("ar-AE", "Arabic (UAE)"),
        ("bn", "Bengali"),
        ("zh", "Chinese"),
        ("fr", "French"),
        ("de", "German"),
        ("hi", "Hindi"),
        ("id", "Indonesian"),
        ("it", "Italian"),
        ("ja", "Japanese"),
        ("ko", "Korean"),
        ("pt-BR", "Portuguese (Brazil)"),
        ("pt-PT", "Portuguese (Portugal)"),
        ("ru", "Russian"),
        ("es-MX", "Spanish (Mexico)"),
        ("es-ES", "Spanish (Spain)"),
        ("tr", "Turkish"),
        ("vi", "Vietnamese"),
    ]
    static let fallbackVoices: [VoiceChoice] = [
        VoiceChoice(voiceId: "ara", name: "Ara"),
        VoiceChoice(voiceId: "eve", name: "Eve"),
        VoiceChoice(voiceId: "leo", name: "Leo"),
        VoiceChoice(voiceId: "rex", name: "Rex"),
        VoiceChoice(voiceId: "sal", name: "Sal"),
    ]
    static let directionPhrases = ["whispered", "soft", "loud", "slow", "fast", "sung", "a pause", "a laugh", "breathy"]

    static func parse(text: String, how: String, voiceId: String, speed: Double, language: String) -> Result<SpeechRequest, SpeechParseError> {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty { return .failure(SpeechParseError(message: "Type the line you want spoken.")) }
        if line.count > textLimit { return .failure(SpeechParseError(message: "Keep the line under \(textLimit) characters.")) }
        let direction = how.trimmingCharacters(in: .whitespacesAndNewlines)
        if direction.count > howLimit { return .failure(SpeechParseError(message: "Keep the direction under \(howLimit) characters.")) }
        let voice = voiceId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !isVoiceId(voice) { return .failure(SpeechParseError(message: "Pick a voice, or paste a voice id.")) }
        guard speed.isFinite else { return .failure(SpeechParseError(message: "Set a speed between 0.7 and 1.5.")) }
        let rounded = (speed * 100).rounded() / 100
        if rounded < speedMin || rounded > speedMax { return .failure(SpeechParseError(message: "Set a speed between 0.7 and 1.5.")) }
        let requested = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let canonical = languages.first(where: { $0.code.lowercased() == requested })?.code else {
            return .failure(SpeechParseError(message: "Pick a language the speech API supports."))
        }
        return .success(SpeechRequest(text: line, how: direction, voiceId: voice.lowercased(), speed: rounded, language: canonical))
    }

    static func isVoiceId(_ value: String) -> Bool {
        value.range(of: "^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$", options: .regularExpression) != nil
    }

    static func ttsBody(_ request: SpeechRequest, spoken: String) -> [String: Any] {
        [
            "text": spoken,
            "voice_id": request.voiceId,
            "language": request.language,
            "speed": request.speed,
            "output_format": ["codec": "wav", "sample_rate": sampleRate],
        ]
    }

    static func directionBody(text: String, how: String) -> [String: Any] {
        let inline = inlineTags.map { "[\($0)]" }.joined(separator: " ")
        let wrap = wrapTags.map { "<\($0)>…</\($0)>" }.joined(separator: " ")
        let input = """
        You mark up one spoken line for a text-to-speech take in a piece of music.
        Do not add, remove, translate, or respell any word. You may add punctuation.
        You may insert only these inline tags: \(inline).
        You may wrap phrases only with these tags: \(wrap).
        Follow the direction. If it asks for something the tags cannot do, do the closest thing and still keep every word.
        Return JSON with a single text field.

        Line:
        \(text)

        Direction:
        \(how)
        """
        return [
            "model": model,
            "input": input,
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "spoken_line",
                    "strict": true,
                    "schema": [
                        "type": "object",
                        "properties": ["text": ["type": "string"]],
                        "required": ["text"],
                        "additionalProperties": false,
                    ],
                ],
            ],
        ]
    }

    static func fileName(for text: String) -> String {
        let stripped = text
            .replacingOccurrences(of: "\\[[^\\]]*\\]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "</?[A-Za-z][\\w-]*>", with: " ", options: .regularExpression)
            .lowercased()
        var words: [String] = []
        var current = ""
        for character in stripped {
            if character.isLetter || character.isNumber || character == "'" {
                current.append(character)
            } else if !current.isEmpty {
                words.append(current.replacingOccurrences(of: "'", with: ""))
                current = ""
            }
        }
        if !current.isEmpty { words.append(current.replacingOccurrences(of: "'", with: "")) }
        let slug = words.prefix(6).joined(separator: "-")
        var cut = String(slug.prefix(48))
        if cut.hasSuffix("-") { cut.removeLast() }
        return (cut.isEmpty ? "spoken" : cut) + ".wav"
    }

    // Letters and numbers only, so a delivery note cannot quietly rewrite the lyric.
    static func utteranceKey(_ text: String) -> String {
        let stripped = text
            .replacingOccurrences(of: "\\[[^\\]]*\\]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "</?[A-Za-z][\\w-]*>", with: "", options: .regularExpression)
        return stripped.unicodeScalars
            .filter { CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0) }
            .map { String($0) }
            .joined()
            .lowercased()
    }

    static func stripUnknownTags(_ text: String) -> String {
        let inline = Set(inlineTags)
        let wrap = Set(wrapTags)
        let withoutInline = replacing(text, pattern: "\\[([^\\]]*)\\]") { whole, inner in
            inline.contains(inner.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) ? whole : ""
        }
        return replacing(withoutInline, pattern: "</?([A-Za-z][\\w-]*)>") { whole, inner in
            wrap.contains(inner.lowercased()) ? whole : ""
        }
    }

    static func applyDirection(original: String, directed: String?) -> (spoken: String, direction: SpeechDirection) {
        guard let directed else { return (original, .rejected) }
        let cleaned = stripUnknownTags(directed).trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty || utteranceKey(cleaned) != utteranceKey(original) {
            return (original, .rejected)
        }
        return (cleaned, .applied)
    }

    static func readDirection(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return readDirection(json)
    }

    static func readDirection(_ json: Any) -> String? {
        guard let record = json as? [String: Any] else { return nil }
        var chunks: [String] = []
        if let text = record["output_text"] as? String { chunks.append(text) }
        if let output = record["output"] as? [[String: Any]] {
            for item in output {
                guard let content = item["content"] as? [[String: Any]] else { continue }
                for part in content {
                    if let text = part["text"] as? String { chunks.append(text) }
                }
            }
        }
        return chunks.compactMap(textFromModel).first
    }

    static func normalizeVoices(_ data: Data) -> [VoiceChoice] {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let voices = json["voices"] as? [[String: Any]]
        else { return [] }
        var seen = Set<String>()
        var choices: [VoiceChoice] = []
        for voice in voices {
            guard let raw = voice["voice_id"] as? String, isVoiceId(raw) else { continue }
            let voiceId = raw.lowercased()
            if seen.contains(voiceId) { continue }
            seen.insert(voiceId)
            let name = (voice["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            choices.append(VoiceChoice(voiceId: voiceId, name: name.isEmpty ? voiceId : name))
        }
        return choices.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func apiFailure(status: Int, body: String) -> String {
        if status == 401 || status == 403 { return "The API key was rejected. Check it and save it again." }
        if let data = body.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let message: String
            if let error = json["error"] as? String {
                message = error
            } else if let error = json["error"] as? [String: Any], let text = error["message"] as? String {
                message = text
            } else if let text = json["message"] as? String {
                message = text
            } else {
                message = ""
            }
            if !message.isEmpty, message.count < 240, message.range(of: "api[_-]?key", options: [.regularExpression, .caseInsensitive]) == nil {
                return message
            }
        }
        return "The speech service returned \(status)."
    }

    static func looksLikeWav(_ data: Data) -> Bool {
        guard data.count >= 12 else { return false }
        let bytes = [UInt8](data.prefix(12))
        return bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46
            && bytes[8] == 0x57 && bytes[9] == 0x41 && bytes[10] == 0x56 && bytes[11] == 0x45
    }

    static func adding(_ phrase: String, to how: String) -> String {
        let trimmed = how.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return phrase }
        if trimmed.lowercased().contains(phrase.lowercased()) { return trimmed }
        return "\(trimmed), \(phrase)"
    }

    private static func textFromModel(_ chunk: String) -> String? {
        let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if let direct = jsonText(trimmed) { return direct }
        guard let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}"), start < end else { return nil }
        return jsonText(String(trimmed[start...end]))
    }

    private static func jsonText(_ value: String) -> String? {
        guard
            let data = value.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let text = json["text"] as? String
        else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func replacing(_ text: String, pattern: String, _ body: (String, String) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var out = ""
        var cursor = 0
        for match in matches {
            if match.range.location > cursor {
                out += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            }
            let whole = ns.substring(with: match.range)
            let inner = match.numberOfRanges > 1 && match.range(at: 1).location != NSNotFound
                ? ns.substring(with: match.range(at: 1))
                : ""
            out += body(whole, inner)
            cursor = match.range.location + match.range.length
        }
        if cursor < ns.length { out += ns.substring(from: cursor) }
        return out
    }
}
