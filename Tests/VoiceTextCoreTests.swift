import XCTest
import AVFoundation
import AppKit
@testable import VoiceTextCore

final class VoiceTextCoreTests: XCTestCase {
    func testSingleModifierShortcutsDistinguishSidesAndFireOnlyOnRelease() throws {
        var tracker = SingleKeyShortcutTracker()
        for code: UInt16 in [54, 55, 56, 60, 58, 61, 59, 62, 63] {
            let mask = try XCTUnwrap(SingleKeyShortcutTracker.modifierMask(for: code))
            let down = try XCTUnwrap(NSEvent.keyEvent(with: .flagsChanged, location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: mask), timestamp: 0, windowNumber: 0,
                context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code))
            let up = try XCTUnwrap(NSEvent.keyEvent(with: .flagsChanged, location: .zero,
                modifierFlags: [], timestamp: 1, windowNumber: 0, context: nil,
                characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code))
            XCTAssertNil(tracker.releasedKey(for: down))
            XCTAssertEqual(tracker.releasedKey(for: up), code)
            XCTAssertNil(tracker.releasedKey(for: up))
        }
    }

    func testModifierShortcutsIgnoreTypingChordsAndSessionChanges() throws {
        func event(_ code: UInt16, _ flags: UInt, type: NSEvent.EventType = .flagsChanged) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(with: type, location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: flags), timestamp: 0, windowNumber: 0,
                context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code))
        }
        var tracker = SingleKeyShortcutTracker()
        XCTAssertNil(tracker.releasedKey(for: try event(56, 0x20002)))
        XCTAssertNil(tracker.releasedKey(for: try event(0, 0x20002, type: .keyDown)))
        XCTAssertNil(tracker.releasedKey(for: try event(56, 0)))
        // IMK may send only device-independent flags, unlike local AppKit events.
        XCTAssertNil(tracker.releasedKey(for: try event(61, 0x80000)))
        XCTAssertEqual(tracker.releasedKey(for: try event(61, 0)), 61)
        XCTAssertNil(tracker.releasedKey(for: try event(60, 0x20000)))
        XCTAssertEqual(tracker.releasedKey(for: try event(60, 0)), 60)
        // Both Option keys share the same generic flag but have distinct physical flags.
        XCTAssertNil(tracker.releasedKey(for: try event(58, 0x80020)))
        XCTAssertNil(tracker.releasedKey(for: try event(61, 0x80060)))
        XCTAssertNil(tracker.releasedKey(for: try event(58, 0x80040)))
        XCTAssertNil(tracker.releasedKey(for: try event(61, 0)))
        XCTAssertNil(tracker.releasedKey(for: try event(62, 0x42000)))
        tracker.reset()
        XCTAssertNil(tracker.releasedKey(for: try event(62, 0)))
    }

    func testEmptyTranscriptIsNoSpeechWhileMalformedResponseRemainsAnError() throws {
        for provider in [ASRProvider.openAI, .qwen] {
            let json = provider == .openAI ? #"{"text":"  "}"# : #"{"choices":[{"message":{"content":"  "}}]}"#
            XCTAssertThrowsError(try ASRRequests.transcript(Data(json.utf8), provider: provider)) {
                XCTAssertEqual($0 as? VoiceTextError, .noSpeech)
            }
            XCTAssertThrowsError(try ASRRequests.transcript(Data("{}".utf8), provider: provider)) {
                XCTAssertNotEqual($0 as? VoiceTextError, .noSpeech)
            }
        }
    }

    func testLocalCredentialsPersistDeleteAndRestrictAccess() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("credentials.json")
        let store = CredentialStore(file: file)
        XCTAssertEqual(try store.read("asr.doubao"), "")
        try store.save("asr-secret", account: "asr.doubao")
        try store.save("cleanup-secret", account: "cleanup")
        XCTAssertEqual(try CredentialStore(file: file).read("asr.doubao"), "asr-secret")
        try store.save("", account: "asr.doubao")
        XCTAssertEqual(try store.read("asr.doubao"), "")
        XCTAssertEqual(try store.read("cleanup"), "cleanup-secret")
        let manager = FileManager.default
        XCTAssertEqual((try manager.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual((try manager.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }

    func testCorruptCredentialsAreNotOverwritten() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("credentials.json")
        let original = Data("not-json".utf8)
        try original.write(to: file)
        let store = CredentialStore(file: file)
        XCTAssertThrowsError(try store.save("replacement", account: "asr.doubao"))
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    func testDoubaoHandshakeErrorsExplainAuthenticationAndPreserveCancellation() throws {
        let url = try ServiceConfiguration.preset(.doubao).url(streaming: true)
        for status in [401, 403, 404, 429, 500] {
            let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil))
            let error = DoubaoWebSocket.connectionFailure(URLError(.badServerResponse), response: response)
            XCTAssertThrowsError(try ASRRequests.check(response)) { expected in
                XCTAssertEqual(error.localizedDescription, expected.localizedDescription)
            }
        }
        let error = DoubaoWebSocket.connectionFailure(URLError(.badServerResponse), response: nil)
        XCTAssertTrue(error.localizedDescription.contains("密钥"))
        XCTAssertTrue(DoubaoWebSocket.connectionFailure(CancellationError(), response: nil) is CancellationError)
    }

    func testUTF8OffsetsBecomeCocoaRanges() {
        let text = "中😀e\u{301}文"
        XCTAssertEqual(TextOffsets.utf16Offset(3, in: text), 1)
        XCTAssertEqual(TextOffsets.utf16Offset(7, in: text), 3)
        XCTAssertEqual(TextOffsets.utf16Offset(text.utf8.count, in: text), text.utf16.count)
        XCTAssertEqual(TextOffsets.utf16Offset(-5, in: text), 0)
        XCTAssertEqual(TextOffsets.utf16Offset(999, in: text), text.utf16.count)
    }

    func testDoubao2ConsoleAuthentication() throws {
        for resource in ["volc.seedasr.sauc.duration", "volc.seedasr.sauc.concurrent"] {
            let config = ServiceConfiguration(endpoint: ASRProvider.doubao.defaultEndpoint, model: resource)
            let modern = try DoubaoSession.makeRequest(configuration: config, key: "api-key", appID: nil)
            XCTAssertEqual(modern.value(forHTTPHeaderField: "X-Api-Resource-Id"), resource)
            XCTAssertEqual(modern.value(forHTTPHeaderField: "X-Api-Key"), "api-key")
            XCTAssertNil(modern.value(forHTTPHeaderField: "X-Api-Access-Key"))
            let legacy = try DoubaoSession.makeRequest(configuration: config, key: "token", appID: "123")
            XCTAssertEqual(legacy.value(forHTTPHeaderField: "X-Api-App-Key"), "123")
            XCTAssertEqual(legacy.value(forHTTPHeaderField: "X-Api-Access-Key"), "token")
            XCTAssertNil(legacy.value(forHTTPHeaderField: "X-Api-Key"))
        }
        XCTAssertThrowsError(try DoubaoSession.makeRequest(configuration: .preset(.doubao), key: "token", appID: ""))
        XCTAssertThrowsError(try DoubaoSession.makeRequest(configuration: .init(endpoint: ASRProvider.doubao.defaultEndpoint, model: "invalid"), key: "key", appID: nil))
    }

    func testDoubaoPacketsUseGzipAndExplicitFinalFlag() throws {
        let pcm = Data(repeating: 0x17, count: 6400)
        let frame = try DoubaoProtocol.audio(pcm, final: true)
        XCTAssertEqual(Array(frame.prefix(4)), [0x11, 0x22, 0x01, 0])
        var cursor = 4
        XCTAssertEqual(try frame.readUInt32(at: &cursor), UInt32(frame.count - 8))
        XCTAssertEqual(try DoubaoProtocol.gunzip(frame.subdata(in: 8..<frame.count)), pcm)
        let request = try DoubaoProtocol.request()
        let body = try DoubaoProtocol.gunzip(request.subdata(in: 8..<request.count))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let audio = try XCTUnwrap(json["audio"] as? [String: Any])
        XCTAssertEqual(audio["rate"] as? Int, 16000)
        XCTAssertEqual((json["request"] as? [String: Any])?["model_name"] as? String, "bigmodel")
    }

    func testDoubaoResponsesAreSnapshotsAndRecognizeLastPacket() throws {
        let interim = try response(text: "你好", final: false)
        let final = try response(text: "你好世界。", final: true)
        XCTAssertEqual(try DoubaoProtocol.parse(interim), .init(text: "你好", final: false))
        XCTAssertEqual(try DoubaoProtocol.parse(final), .init(text: "你好世界。", final: true))
        for count in [0, 3, 7, final.count - 1] { XCTAssertThrowsError(try DoubaoProtocol.parse(Data(final.prefix(count)))) }
        var error = Data([0x11, 0xf0, 0x10, 0]); error.appendUInt32(45000001); error.appendUInt32(0)
        XCTAssertThrowsError(try DoubaoProtocol.parse(error))
        XCTAssertThrowsError(try DoubaoProtocol.gunzip(Data("bad gzip".utf8)))
    }

    func testFileProvidersHaveDifferentRequestAndResponseShapes() throws {
        let pcm = Data([1, 2, 3, 4])
        let body = try ASRRequests.qwenBody(wav: pcm, model: "qwen3-asr-flash")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["stream"] as? Bool, false)
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages.first?["content"] as? [[String: Any]])
        XCTAssertEqual((content.first?["input_audio"] as? [String: Any])?["data"] as? String, "data:audio/wav;base64,AQIDBA==")
        XCTAssertEqual(try ASRRequests.transcript(Data(#"{"text":"中文听写"}"#.utf8), provider: .openAI), "中文听写")
        XCTAssertEqual(try ASRRequests.transcript(Data(#"{"choices":[{"message":{"content":"完成。"}}]}"#.utf8), provider: .qwen), "完成。")
        XCTAssertThrowsError(try ASRRequests.transcript(Data(#"{"choices":[]}"#.utf8), provider: .qwen))
        XCTAssertThrowsError(try ASRRequests.transcript(Data(#"{"text":" "}"#.utf8), provider: .openAI))
        XCTAssertThrowsError(try ServiceConfiguration(endpoint: "http://example.com", model: "m").url())
        XCTAssertThrowsError(try ServiceConfiguration(endpoint: "https://key@example.com", model: "m").url())
        XCTAssertEqual(try ServiceConfiguration.preset(.doubao).url(streaming: true).scheme, "wss")
    }

    func testWAVHeaderLengthAndCleanup() throws {
        let wave = try WAVFile()
        let url = wave.url
        try wave.append(Data(repeating: 1, count: 32000))
        try wave.finish(); try wave.finish()
        let data = try Data(contentsOf: url)
        XCTAssertEqual(data.count, 32044)
        XCTAssertEqual(String(data: data.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertEqual(Array(data[24..<28]), [0x80, 0x3e, 0, 0])
        XCTAssertEqual(Array(data[40..<44]), [0, 0x7d, 0, 0])
        wave.remove(); XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testHardwareFormatConversionAndFinalTailWithoutMicrophone() async throws {
        let sourceFormat = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 2, interleaved: false))
        let target = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true))
        let converter = try XCTUnwrap(AVAudioConverter(from: sourceFormat, to: target))
        let source = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: 48000))
        source.frameLength = 48000
        let channels = try XCTUnwrap(source.floatChannelData)
        for channel in 0..<2 {
            for sample in 0..<48000 { channels[channel][sample] = Float(sin(Double(sample) * 2 * .pi * 440 / 48000)) * 0.2 }
        }
        let (stream, continuation) = AsyncThrowingStream<Data, Error>.makeStream(bufferingPolicy: .bufferingOldest(25))
        let processor = AudioProcessor(converter: converter, format: target, continuation: continuation)
        processor.push(source)
        await processor.finish()
        var bytes = Data()
        var sizes: [Int] = []
        for try await packet in stream { bytes.append(packet); sizes.append(packet.count) }
        XCTAssertEqual(bytes.count, 32000, accuracy: 64)
        XCTAssertTrue(sizes.dropLast().allSatisfy { $0 == 6400 })
        XCTAssertTrue(bytes.contains { $0 != 0 })
    }

    func testStreamingSessionOnlyCompletesAfterFinalAndSendsOneEndPacket() async throws {
        let transport = MockDoubaoTransport()
        let session = DoubaoSession(configuration: .preset(.doubao), key: "test-only", makeTransport: { _ in transport })
        try await session.start()
        try await session.append(Data(repeating: 1, count: 6400))
        try await session.append(Data(repeating: 2, count: 6400))
        let result = try await session.finish()
        XCTAssertEqual(result.text, "你好世界。")
        XCTAssertEqual(transport.audioFlags, [0, 2])
        do { _ = try await session.finish(); XCTFail("finish must not emit a second result") } catch {}
        XCTAssertEqual(transport.audioFlags, [0, 2])
        XCTAssertTrue(transport.closed)
    }

    func testCancelUnblocksFinalWaitAndNeverRestartsOldSession() async throws {
        let transport = MockDoubaoTransport(autoFinal: false)
        let endSent = expectation(description: "end packet sent")
        transport.onFinal = { endSent.fulfill() }
        let session = DoubaoSession(configuration: .preset(.doubao), key: "test-only", makeTransport: { _ in transport })
        try await session.start(); try await session.append(Data(repeating: 1, count: 6400))
        let waiting = Task { try await session.finish() }
        await fulfillment(of: [endSent], timeout: 2)
        await session.cancel()
        do { _ = try await waiting.value; XCTFail("cancelled final must not be returned") }
        catch { XCTAssertTrue(error is CancellationError) }
        do { try await session.start(); XCTFail("cancelled session must not restart") } catch {}
        XCTAssertTrue(transport.closed)
    }

    func testFinalTimeoutClosesConnection() async throws {
        let transport = MockDoubaoTransport(autoFinal: false)
        let session = DoubaoSession(configuration: .preset(.doubao), key: "test-only", finalTimeout: .milliseconds(20), makeTransport: { _ in transport })
        try await session.start(); try await session.append(Data(repeating: 1, count: 6400))
        do { _ = try await session.finish(); XCTFail("missing final must time out") }
        catch { XCTAssertTrue(error.localizedDescription.contains("超时")) }
        XCTAssertTrue(transport.closed)
    }

    func testBlockedAudioSendTimesOutWhileRecording() async throws {
        let transport = MockDoubaoTransport(blockAudio: true)
        let session = DoubaoSession(configuration: .preset(.doubao), key: "test-only", sendTimeout: .milliseconds(20), makeTransport: { _ in transport })
        try await session.start()
        try await session.append(Data(repeating: 1, count: 6400))
        do { try await session.append(Data(repeating: 2, count: 6400)); XCTFail("blocked audio must not wait indefinitely") }
        catch { XCTAssertTrue(error.localizedDescription.contains("发送超时")) }
        XCTAssertTrue(transport.closed)
    }

    func testHistoryPersistsRawAndFinalWithPagination() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("history.sqlite")
        let first = HistoryStore(url: url)
        let id = try await first.insert(.init(text: "原始转写", provider: .doubao, model: "volc.seedasr.sauc.duration"))
        try await first.update(id: id, finalText: "整理后的文本。")
        for i in 0..<34 { _ = try await first.insert(.init(text: "记录 \(i)", provider: .qwen, model: "qwen3-asr-flash")) }
        let reopened = HistoryStore(url: url)
        let page1 = try await reopened.page(limit: 30)
        let page2 = try await reopened.page(offset: 30, limit: 30)
        XCTAssertEqual(page1.count, 30); XCTAssertEqual(page2.count, 5)
        let original = try XCTUnwrap(page2.first { $0.id == id })
        XCTAssertEqual(original.rawText, "原始转写"); XCTAssertEqual(original.finalText, "整理后的文本。")
        try await reopened.delete(id: id)
        let remaining = try await reopened.page(offset: 30)
        XCTAssertEqual(remaining.count, 4)
        try await reopened.clear()
        let empty = try await reopened.page(); XCTAssertTrue(empty.isEmpty)
    }

    private func response(text: String, final: Bool) throws -> Data {
        let body = try DoubaoProtocol.gzip(JSONSerialization.data(withJSONObject: ["result": ["text": text]]))
        var data = Data([0x11, final ? 0x93 : 0x91, 0x11, 0])
        data.appendUInt32(final ? UInt32.max : 1); data.appendUInt32(UInt32(body.count)); data.append(body)
        return data
    }
}

private final class MockDoubaoTransport: DoubaoTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var inbox: [Data] = []
    private var pending: CheckedContinuation<Data, Error>?
    private var pendingSend: CheckedContinuation<Void, Error>?
    private var flags: [UInt8] = []
    private var isClosed = false
    private let autoFinal: Bool
    private let blockAudio: Bool
    var onFinal: (() -> Void)?
    var audioFlags: [UInt8] { lock.withLock { flags } }
    var closed: Bool { lock.withLock { isClosed } }
    init(autoFinal: Bool = true, blockAudio: Bool = false) { self.autoFinal = autoFinal; self.blockAudio = blockAudio }
    func connect() async throws {}
    func send(_ data: Data) async throws {
        guard data[1] >> 4 == 2 else { return }
        let final = data[1] & 2 != 0
        lock.withLock { flags.append(data[1] & 15) }
        if blockAudio && !final {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.lock()
                if isClosed { lock.unlock(); continuation.resume(throwing: CancellationError()) }
                else { pendingSend = continuation; lock.unlock() }
            }
        }
        if final { onFinal?() }
        if !final || autoFinal {
            let body = try DoubaoProtocol.gzip(JSONSerialization.data(withJSONObject: ["result": ["text": final ? "你好世界。" : "你好"]]))
            var response = Data([0x11, final ? 0x93 : 0x91, 0x11, 0])
            response.appendUInt32(final ? UInt32.max : 1); response.appendUInt32(UInt32(body.count)); response.append(body)
            let waiter = lock.withLock { () -> CheckedContinuation<Data, Error>? in
                if let waiter = pending { pending = nil; return waiter }
                inbox.append(response); return nil
            }
            waiter?.resume(returning: response)
        }
    }
    func receive() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if isClosed { lock.unlock(); continuation.resume(throwing: CancellationError()) }
            else if !inbox.isEmpty { let first = inbox.removeFirst(); lock.unlock(); continuation.resume(returning: first) }
            else { pending = continuation; lock.unlock() }
        }
    }
    func close() {
        let (waiter, sender) = lock.withLock { () -> (CheckedContinuation<Data, Error>?, CheckedContinuation<Void, Error>?) in
            isClosed = true
            let waiter = pending, sender = pendingSend
            pending = nil; pendingSend = nil
            return (waiter, sender)
        }
        waiter?.resume(throwing: CancellationError())
        sender?.resume(throwing: CancellationError())
    }
}
