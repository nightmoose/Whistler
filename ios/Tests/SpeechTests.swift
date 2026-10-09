import XCTest
@testable import Whistler

final class SpeechTests: XCTestCase {
    func testParseTrimsTheLineAndLowercasesTheVoice() {
        let parsed = SpeechMarkup.parse(text: " Drop the beat ", how: "whispered", voiceId: "Eve", speed: 1, language: "en")
        guard case .success(let request) = parsed else {
            XCTFail("expected a request")
            return
        }
        XCTAssertEqual(request.text, "Drop the beat")
        XCTAssertEqual(request.voiceId, "eve")
    }

    func testParseRejectsEmptyLineBadVoiceAndWildSpeed() {
        XCTAssertTrue(isFailure(SpeechMarkup.parse(text: "  ", how: "", voiceId: "eve", speed: 1, language: "en")))
        XCTAssertTrue(isFailure(SpeechMarkup.parse(text: "Hi", how: "", voiceId: "../x", speed: 1, language: "en")))
        XCTAssertTrue(isFailure(SpeechMarkup.parse(text: "Hi", how: "", voiceId: "eve", speed: 2, language: "en")))
        XCTAssertTrue(isFailure(SpeechMarkup.parse(text: "Hi", how: "", voiceId: "eve", speed: 1, language: "klingon")))
    }

    func testDirectionKeepsTagsAndRefusesARewrite() {
        let kept = SpeechMarkup.applyDirection(original: "Drop the beat", directed: "<whisper>Drop the beat.</whisper> [laugh]")
        XCTAssertEqual(kept.direction, .applied)
        XCTAssertTrue(kept.spoken.contains("<whisper>"))
        XCTAssertTrue(kept.spoken.contains("[laugh]"))

        let rewritten = SpeechMarkup.applyDirection(original: "Drop the beat", directed: "Drop the bass")
        XCTAssertEqual(rewritten.spoken, "Drop the beat")
        XCTAssertEqual(rewritten.direction, .rejected)
    }

    func testUnknownTagsAreStripped() {
        let cleaned = SpeechMarkup.applyDirection(original: "Drop the beat", directed: "<shout>Drop the beat</shout> [scream]")
        XCTAssertEqual(cleaned.spoken, "Drop the beat")
        XCTAssertEqual(cleaned.direction, .applied)
    }

    func testDirectionPromptUsesTheCurrentModel() {
        let body = SpeechMarkup.directionBody(text: "Drop the beat", how: "whispered, then a laugh")
        XCTAssertEqual(body["model"] as? String, "grok-4.7")
        let input = body["input"] as? String ?? ""
        XCTAssertTrue(input.contains("Drop the beat"))
        XCTAssertTrue(input.contains("whispered, then a laugh"))
        XCTAssertTrue(input.contains("[pause]"))
        XCTAssertTrue(input.contains("<whisper>"))
    }

    func testReadsEitherResponseShape() {
        let direct = #"{"output_text":"{\"text\":\"<slow>Drop the beat</slow>\"}"}"#
        XCTAssertEqual(SpeechMarkup.readDirection(Data(direct.utf8)), "<slow>Drop the beat</slow>")
        let nested: [String: Any] = [
            "output": [["type": "message", "content": [["type": "output_text", "text": "{\"text\":\"Drop the beat\"}"]]]],
        ]
        XCTAssertEqual(SpeechMarkup.readDirection(nested), "Drop the beat")
        XCTAssertNil(SpeechMarkup.readDirection(["output_text": "not json"]))
    }

    func testFileIsStudioWavNamedFromTheLine() throws {
        let parsed = SpeechMarkup.parse(text: "Drop the beat!", how: "", voiceId: "rex", speed: 0.85, language: "en")
        guard case .success(let request) = parsed else {
            XCTFail("expected a request")
            return
        }
        let body = SpeechMarkup.ttsBody(request, spoken: request.text)
        XCTAssertEqual(body["voice_id"] as? String, "rex")
        XCTAssertEqual(body["speed"] as? Double, 0.85)
        let format = body["output_format"] as? [String: Any]
        XCTAssertEqual(format?["codec"] as? String, "wav")
        XCTAssertEqual(format?["sample_rate"] as? Int, 48_000)
        XCTAssertEqual(SpeechMarkup.fileName(for: "Drop the beat!"), "drop-the-beat.wav")
        XCTAssertEqual(SpeechMarkup.utteranceKey("<whisper>Don't stop.</whisper>"), "dontstop")
    }

    func testVoiceListDropsJunk() {
        let json = #"{"voices":[{"voice_id":"Rex","name":"Rex"},{"voice_id":"eve","name":"Eve"},{"voice_id":"not a voice","name":"No"}]}"#
        XCTAssertEqual(SpeechMarkup.normalizeVoices(Data(json.utf8)).map(\.voiceId), ["eve", "rex"])
    }

    func testRejectedKeyMessageDoesNotEchoTheSecret() {
        let message = SpeechMarkup.apiFailure(status: 401, body: #"{"error":{"message":"bad key sk-secret"}}"#)
        XCTAssertEqual(message, "The API key was rejected. Check it and save it again.")
        XCTAssertFalse(message.contains("secret"))
    }

    func testGenerateSendsWavAndRefusesARewrittenLyric() async throws {
        let wav = Data([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x41, 0x56, 0x45])
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SpeechStub.self]
        let session = URLSession(configuration: config)
        let capture = SpeechCapture()
        SpeechStub.handler = { request in
            let url = request.url?.absoluteString ?? ""
            if url.hasSuffix("/responses") {
                let body = #"{"output_text":"{\"text\":\"Drop the bass\"}"}"#
                return (200, Data(body.utf8), "application/json")
            }
            capture.ttsBody = SpeechStub.bodyString(request)
            capture.authorization = request.value(forHTTPHeaderField: "Authorization")
            return (200, wav, "audio/wav")
        }
        let request = SpeechRequest(text: "Drop the beat", how: "angrier", voiceId: "eve", speed: 1, language: "en")
        let take = try await SpeechClient(apiKey: "secret", session: session).generate(request)
        XCTAssertEqual(take.direction, .rejected)
        XCTAssertEqual(take.spoken, "Drop the beat")
        XCTAssertEqual(take.filename, "drop-the-beat.wav")
        XCTAssertTrue(SpeechMarkup.looksLikeWav(take.audio))
        XCTAssertTrue(capture.ttsBody.contains("\"text\":\"Drop the beat\""))
        XCTAssertTrue(capture.ttsBody.contains("\"codec\":\"wav\""))
        XCTAssertEqual(capture.authorization, "Bearer secret")
        SpeechStub.handler = nil
    }

    private func isFailure(_ result: Result<SpeechRequest, SpeechParseError>) -> Bool {
        if case .failure = result { return true }
        return false
    }
}

final class SpeechCapture {
    var ttsBody = ""
    var authorization: String?
}

final class SpeechStub: URLProtocol {
    static var handler: ((URLRequest) -> (Int, Data, String))?

    static func bodyString(_ request: URLRequest) -> String {
        if let body = request.httpBody {
            return String(data: body, encoding: .utf8) ?? ""
        }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: 1024)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (status, data, type) = handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": type])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
