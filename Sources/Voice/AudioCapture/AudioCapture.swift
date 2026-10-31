import AVFoundation

@MainActor
final class AudioCapture {
    private var engine: AVAudioEngine?
    private var processor: AudioProcessor?
    private var configurationObserver: NSObjectProtocol?

    func start() throws -> AsyncThrowingStream<Data, Error> {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let sourceFormat = input.outputFormat(forBus: 0)
        guard sourceFormat.sampleRate > 0, sourceFormat.channelCount > 0,
              let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: sourceFormat, to: target) else {
            throw VoiceTextError.message("当前麦克风不可用或无法转换音频格式。")
        }
        let (stream, continuation) = AsyncThrowingStream<Data, Error>.makeStream(bufferingPolicy: .bufferingOldest(25))
        let processor = AudioProcessor(converter: converter, format: target, continuation: continuation)
        self.processor = processor; self.engine = engine
        input.installTap(onBus: 0, bufferSize: 4096, format: sourceFormat) { buffer, _ in processor.push(buffer) }
        do { engine.prepare(); try engine.start() }
        catch { input.removeTap(onBus: 0); self.engine = nil; self.processor = nil; continuation.finish(throwing: error); throw error }
        configurationObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { _ in
            processor.fail(VoiceTextError.message("麦克风设备发生变化，请检查设备后重新录音。"))
        }
        return stream
    }
    func stop() async {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver); self.configurationObserver = nil }
        engine?.inputNode.removeTap(onBus: 0); engine?.stop(); engine = nil
        let processor = self.processor; self.processor = nil
        await processor?.finish()
    }
}

final class AudioProcessor: @unchecked Sendable {
    private let queue = DispatchQueue(label: "im.voicetext.audio.convert", qos: .userInitiated)
    private let lock = NSLock()
    private var queued = 0
    private var accepting = true
    private let converter: AVAudioConverter
    private let format: AVAudioFormat
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation
    private var pending = Data()
    private var failed = false

    init(converter: AVAudioConverter, format: AVAudioFormat, continuation: AsyncThrowingStream<Data, Error>.Continuation) {
        self.converter = converter; self.format = format; self.continuation = continuation
    }
    func push(_ source: AVAudioPCMBuffer) {
        lock.lock()
        guard accepting else { lock.unlock(); return }
        guard queued < 10 else {
            accepting = false; lock.unlock()
            continuation.finish(throwing: VoiceTextError.message("音频处理跟不上录音速度，请重新录音。")); return
        }
        queued += 1
        guard let copy = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: source.frameLength) else {
            queued -= 1; lock.unlock()
            continuation.finish(throwing: VoiceTextError.message("无法分配录音缓冲。")); return
        }
        copy.frameLength = source.frameLength
        let original = UnsafeMutableAudioBufferListPointer(source.mutableAudioBufferList)
        let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for index in original.indices {
            if let src = original[index].mData, let dst = destination[index].mData {
                memcpy(dst, src, Int(original[index].mDataByteSize))
            }
        }
        queue.async {
            defer { self.lock.lock(); self.queued -= 1; self.lock.unlock() }
            guard !self.failed else { return }
            do { try self.convert(copy) }
            catch { self.failed = true; self.continuation.finish(throwing: error) }
        }
        lock.unlock()
    }

    private func convert(_ source: AVAudioPCMBuffer) throws {
        let capacity = AVAudioFrameCount(ceil(Double(source.frameLength) * 16000 / source.format.sampleRate)) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { throw failure }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if supplied { inputStatus.pointee = .noDataNow; return nil }
            supplied = true; inputStatus.pointee = .haveData; return source
        }
        guard status != .error, error == nil, let bytes = output.int16ChannelData?[0] else { throw error ?? failure }
        try appendPCM(Data(bytes: bytes, count: Int(output.frameLength) * 2))
    }
    private func appendPCM(_ bytes: Data) throws {
        pending.append(bytes)
        while pending.count >= 6400 {
            let packet = Data(pending.prefix(6400)); pending.removeFirst(6400)
            try emit(packet)
        }
    }
    private func drainConverter() throws {
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024) else { throw failure }
        while true {
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, inputStatus in inputStatus.pointee = .endOfStream; return nil }
            guard status != .error, error == nil, let bytes = output.int16ChannelData?[0] else { throw error ?? failure }
            try appendPCM(Data(bytes: bytes, count: Int(output.frameLength) * 2))
            if status == .endOfStream || output.frameLength == 0 { return }
        }
    }
    private func emit(_ packet: Data) throws {
        switch continuation.yield(packet) {
        case .enqueued: break
        case .dropped: throw VoiceTextError.message("网络发送持续积压，已停止本次录音，请重试。")
        case .terminated: throw CancellationError()
        @unknown default: throw failure
        }
    }
    func finish() async {
        stopAccepting()
        await withCheckedContinuation { done in
            queue.async {
                if !self.failed {
                    do {
                        try self.drainConverter()
                        if !self.pending.isEmpty { try self.emit(self.pending) }
                    }
                    catch { self.failed = true; self.continuation.finish(throwing: error) }
                }
                self.pending.removeAll(); self.continuation.finish(); done.resume()
            }
        }
    }
    func fail(_ error: Error) { stopAccepting(); continuation.finish(throwing: error) }
    private func stopAccepting() { lock.lock(); accepting = false; lock.unlock() }
    private var failure: VoiceTextError { .message("录音格式转换失败。") }
}
