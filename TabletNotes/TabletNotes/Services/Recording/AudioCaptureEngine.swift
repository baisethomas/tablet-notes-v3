import Foundation
#if canImport(AVFoundation) && os(iOS)
import AVFoundation
import UIKit

/// A PCM16 little-endian **mono** audio chunk emitted for streaming consumers
/// (live captions). Consumers never touch audio hardware — they only read
/// these values.
struct AudioChunk: Sendable {
    let data: Data
    let sampleRate: Double
}

enum AudioCaptureError: LocalizedError {
    case alreadyRecording
    case captureUnavailable(String)
    case startFailed(String)

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "A recording is already in progress."
        case .captureUnavailable(let reason):
            return "Audio input is unavailable: \(reason)"
        case .startFailed(let reason):
            return "Could not start audio capture: \(reason)"
        }
    }
}

/// Seam for the capture engine (house rule: new services get a protocol and a
/// mock) so `RecordingService` is testable without AVFoundation hardware —
/// including the restart-failure, interruption, and finalization paths.
protocol AudioCapturing: AnyObject {
    var state: AudioCaptureEngine.State { get }
    var recordedDuration: TimeInterval { get }
    var onEvent: ((AudioCaptureEngine.Event) -> Void)? { get set }
    func start() throws -> AudioCaptureEngine.StartedCapture
    func pause()
    func resume() throws
    @discardableResult func stop() -> URL?
    func finalizeForTermination()
    func makeCaptionStream() -> AsyncStream<AudioChunk>
}

/// The ONLY object in the app that touches `AVAudioSession` or audio-capture
/// hardware (TAB-71). Before this existed, `AVAudioRecorder` (disk) and a
/// second `AVAudioEngine` tap (live captions) ran simultaneously against the
/// shared session; every route change or interruption was a race between them,
/// and losing it raised uncatchable `installTap`/`engine.start()` NSExceptions
/// mid-recording.
///
/// One engine, one input tap, two consumers of the same buffers:
///   1. Disk: an `AVAudioFile` (AAC/m4a) written on every tap callback — the
///      file grows continuously; a crash loses at most one buffer.
///   2. Captions: an `AsyncStream<AudioChunk>` of PCM16-mono conversions of
///      the same buffers. If no consumer is attached (or the consumer dies),
///      capture is completely unaffected.
///
/// Concurrency model — deliberately a locked class, not an actor: the views'
/// existing contract requires *synchronous* `stopRecording()` (the finalized
/// file must exist on disk when the call returns, because the save/transcribe
/// pipeline starts immediately), and the tap callback arrives on a realtime
/// audio thread that cannot hop into an actor per-buffer. All mutable state is
/// guarded by one lock; tap-side state lives in `CaptureSink`, which is only
/// ever touched from the tap's serial callback context plus lock-guarded
/// reads. This mirrors the house precedent that recording infrastructure is
/// intentionally not `@MainActor`.
final class AudioCaptureEngine: AudioCapturing, @unchecked Sendable {
    static let shared = AudioCaptureEngine()

    enum State: Equatable {
        case idle
        case recording
        case paused
    }

    struct StartedCapture {
        let url: URL
        let fileName: String
    }

    /// Events the owning facade (RecordingService) reacts to. Delivered on an
    /// arbitrary queue; the facade is responsible for any main-actor hops.
    ///
    /// EVERY event carries the URL of the capture it belongs to: the facade's
    /// handlers run on queued main-actor hops, and a new recording may start
    /// before a queued event executes. The facade drops any event whose URL is
    /// not the capture it is currently tracking — a stale interruption must
    /// not phantom-pause a new recording, and a stale failure must not stop
    /// one (PR #36 review rounds 2-3).
    enum Event {
        case interruptionBegan(url: URL?)
        case interruptionEndedAndResumed(url: URL?)
        /// Capture failed unrecoverably and the file was finalized.
        case captureFailed(url: URL?, reason: String)

        var captureURL: URL? {
            switch self {
            case .interruptionBegan(let url),
                 .interruptionEndedAndResumed(let url),
                 .captureFailed(let url, _):
                return url
            }
        }
    }

    private let lock = NSLock()
    private let engine = AVAudioEngine()
    private var sink: CaptureSink?
    private var currentURL: URL?
    private var stateLocked: State = .idle
    private var notificationTokens: [NSObjectProtocol] = []

    var onEvent: ((Event) -> Void)?

    /// Target format for the caption stream. 16 kHz PCM16 mono is
    /// AssemblyAI-supported and a fraction of the mic bandwidth.
    static let captionSampleRate: Double = 16000

    private init() {
        installNotificationObservers()
    }

    // Installing an AVAudioEngine tap while the input hardware reports a
    // zero-rate/zero-channel format raises an uncatchable NSException.
    static func isCaptureFormatUsable(sampleRate: Double, channelCount: AVAudioChannelCount) -> Bool {
        sampleRate > 0 && channelCount > 0
    }

    var state: State {
        lock.lock(); defer { lock.unlock() }
        return stateLocked
    }

    /// Seconds of audio actually written to disk. Frame-based, so pauses and
    /// interruptions are accounted for exactly (the old wall-clock duration
    /// drifted across pauses).
    var recordedDuration: TimeInterval {
        lock.lock(); defer { lock.unlock() }
        return sink?.recordedDuration ?? 0
    }

    // MARK: - Capture lifecycle

    /// Starts capture. Synchronous by design: when this returns, the engine is
    /// running and the output file exists — the caller writes the recovery
    /// manifest immediately after, with no suspension point in between.
    func start() throws -> StartedCapture {
        lock.lock(); defer { lock.unlock() }
        guard stateLocked == .idle else { throw AudioCaptureError.alreadyRecording }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth, .defaultToSpeaker])
            try session.setActive(true)
        } catch {
            throw AudioCaptureError.captureUnavailable("audio session activation failed: \(error.localizedDescription)")
        }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard Self.isCaptureFormatUsable(sampleRate: inputFormat.sampleRate, channelCount: inputFormat.channelCount) else {
            throw AudioCaptureError.captureUnavailable("input format \(inputFormat) not usable")
        }

        let fileName = "sermon_\(UUID().uuidString).m4a"
        let url = Self.audioRecordingsDirectory.appendingPathComponent(fileName)
        try FileManager.default.createDirectory(
            at: Self.audioRecordingsDirectory,
            withIntermediateDirectories: true
        )

        // The m4a's nominal format is fixed at start from the current input;
        // if a route change later shifts the tap format, the sink converts
        // incoming buffers back to the file's processing format.
        let fileSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: inputFormat.sampleRate,
            AVNumberOfChannelsKey: Int(inputFormat.channelCount),
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        // Fragmented, so an interrupted recording is still playable (TAB-86).
        let writer: CaptureFileWriting
        do {
            writer = try FragmentedM4AWriter(
                url: url,
                settings: fileSettings,
                inputFormat: inputFormat
            )
        } catch {
            throw AudioCaptureError.startFailed("could not create output file: \(error.localizedDescription)")
        }

        let newSink = CaptureSink(writer: writer)

        try installTapAndStartLocked(sink: newSink)

        sink = newSink
        currentURL = url
        stateLocked = .recording
        print("[AudioCaptureEngine] Started capture to \(fileName) at \(inputFormat.sampleRate)Hz/\(inputFormat.channelCount)ch")
        return StartedCapture(url: url, fileName: fileName)
    }

    func pause() {
        lock.lock(); defer { lock.unlock() }
        guard stateLocked == .recording else { return }
        engine.pause()
        stateLocked = .paused
        print("[AudioCaptureEngine] Paused")
    }

    func resume() throws {
        lock.lock(); defer { lock.unlock() }
        guard stateLocked == .paused else { return }
        try resumeEngineLocked()
        stateLocked = .recording
        print("[AudioCaptureEngine] Resumed")
    }

    /// Stops capture and finalizes the m4a **before returning** — callers hand
    /// the URL straight to the save/transcribe pipeline.
    @discardableResult
    func stop() -> URL? {
        lock.lock(); defer { lock.unlock() }
        guard stateLocked != .idle else { return nil }
        let url = currentURL

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        // Finalize explicitly rather than relying on the last reference being
        // dropped — that implicit finalize is exactly what an interrupted
        // process skips, and it left 14 recordings unreadable (TAB-86). The
        // file is already playable at this point; this completes it.
        sink?.finishCaptionStream()
        sink?.finishFile()
        sink = nil
        currentURL = nil
        stateLocked = .idle

        if let url {
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
            print("[AudioCaptureEngine] Stopped; finalized \(url.lastPathComponent) (\(size) bytes)")
        }
        return url
    }

    /// Called on app termination while recording: finalize the file on disk
    /// and deliberately leave the recovery manifest (owned by the facade) in
    /// place so next launch recovers the recording.
    func finalizeForTermination() {
        lock.lock(); defer { lock.unlock() }
        guard stateLocked != .idle else { return }
        print("[AudioCaptureEngine] Finalizing capture for termination")
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        sink?.finishCaptionStream()
        sink = nil
        stateLocked = .idle
    }

    // MARK: - Caption stream

    /// Attaches (or replaces) the caption consumer. Capture never depends on
    /// this stream: if nobody consumes it, chunks are dropped at the sink.
    func makeCaptionStream() -> AsyncStream<AudioChunk> {
        lock.lock(); defer { lock.unlock() }
        let (stream, continuation) = AsyncStream.makeStream(
            of: AudioChunk.self,
            bufferingPolicy: .bufferingNewest(32)
        )
        if let sink {
            sink.replaceCaptionContinuation(continuation)
        } else {
            // No active capture: hand back a stream that ends immediately.
            continuation.finish()
        }
        return stream
    }

    // MARK: - Internals

    static var audioRecordingsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AudioRecordings", isDirectory: true)
    }

    /// Precondition: lock held. Installs the tap (format nil = node's live
    /// format, so an app-supplied format mismatch is structurally impossible)
    /// and starts the engine, routing both AVFoundation calls through the ObjC
    /// shim: they can still raise NSExceptions on hardware races, and those
    /// must surface as throwable Swift errors, never a process kill.
    private func installTapAndStartLocked(sink: CaptureSink) throws {
        let inputNode = engine.inputNode

        if let exception = ObjCExceptionCatcher.catching({
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { buffer, _ in
                sink.consume(buffer: buffer)
            }
        }) {
            throw AudioCaptureError.startFailed("installTap raised \(exception.name.rawValue): \(exception.reason ?? "no reason")")
        }

        do {
            try startEngineThroughShimLocked()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw error
        }
    }

    /// Precondition: lock held.
    private func resumeEngineLocked() throws {
        try startEngineThroughShimLocked()
    }

    /// Precondition: lock held.
    private func startEngineThroughShimLocked() throws {
        var startError: Error?
        let exception = ObjCExceptionCatcher.catching {
            self.engine.prepare()
            do {
                try self.engine.start()
            } catch {
                startError = error
            }
        }
        if let exception {
            throw AudioCaptureError.startFailed("engine start raised \(exception.name.rawValue): \(exception.reason ?? "no reason")")
        }
        if let startError {
            throw AudioCaptureError.startFailed(startError.localizedDescription)
        }
    }

    /// Precondition: lock held. Reinstalls the tap after the engine's node
    /// graph was invalidated by a route/configuration change. The file and
    /// caption formats are fixed; the sink re-derives conversion from each
    /// buffer's own format, so a changed input format is handled per-buffer.
    private func reinstallTapLocked() {
        guard stateLocked == .recording, let sink else { return }
        engine.inputNode.removeTap(onBus: 0)
        do {
            try installTapAndStartLocked(sink: sink)
            print("[AudioCaptureEngine] Tap reinstalled after configuration change")
        } catch {
            failCaptureLocked(context: "reinstall tap after configuration change", error: error)
        }
    }

    /// Precondition: lock held. Capture cannot continue: finalize what is on
    /// disk (recording is sacred — partial audio beats none) and surface the
    /// failure so the facade auto-stop-saves the partial recording. Silently
    /// staying in `.recording` here would show a live recording UI while no
    /// audio is being written — the worst possible failure mode for this app.
    private func failCaptureLocked(context: String, error: Error) {
        print("[AudioCaptureEngine] ⚠️ Capture failed (\(context)): \(error)")
        let failedURL = currentURL
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        sink?.finishCaptionStream()
        sink = nil
        currentURL = nil
        stateLocked = .idle
        // The facade's handler dispatches async immediately; safe under lock.
        onEvent?(.captureFailed(url: failedURL, reason: error.localizedDescription))
    }

    // MARK: - Notifications

    private func installNotificationObservers() {
        let center = NotificationCenter.default

        notificationTokens.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: nil
        ) { [weak self] notification in
            self?.handleInterruption(notification)
        })

        notificationTokens.append(center.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            // The engine stops itself on a configuration change (route change,
            // sample-rate change). Reinstall the tap and restart — in ONE
            // place, by the single owner. This is the exact race that used to
            // kill the app when two capture stacks handled it independently.
            guard let self else { return }
            self.lock.lock()
            self.reinstallTapLocked()
            self.lock.unlock()
        })

        notificationTokens.append(center.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.finalizeForTermination()
        })

        notificationTokens.append(center.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.lock.lock()
            if self.stateLocked == .recording && !self.engine.isRunning {
                print("[AudioCaptureEngine] Engine stopped during backgrounding; restarting")
                do {
                    try self.resumeEngineLocked()
                } catch {
                    // A swallowed restart failure would leave the UI showing a
                    // live recording while nothing is written (PR #36 review):
                    // finalize the partial recording and surface the failure.
                    self.failCaptureLocked(context: "restart after foregrounding", error: error)
                }
            }
            self.lock.unlock()
        })
    }

    private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            lock.lock()
            let wasRecording = stateLocked == .recording
            let interruptedURL = currentURL
            if wasRecording {
                engine.pause()
                stateLocked = .paused
            }
            lock.unlock()
            if wasRecording {
                print("[AudioCaptureEngine] Interrupted (call/alarm) — paused")
                onEvent?(.interruptionBegan(url: interruptedURL))
            }

        case .ended:
            let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            guard options.contains(.shouldResume) else { return }

            lock.lock()
            guard stateLocked == .paused else {
                lock.unlock()
                return
            }
            do {
                try AVAudioSession.sharedInstance().setActive(true)
                try resumeEngineLocked()
                stateLocked = .recording
                let resumedURL = currentURL
                lock.unlock()
                print("[AudioCaptureEngine] Resumed after interruption")
                onEvent?(.interruptionEndedAndResumed(url: resumedURL))
            } catch {
                // Same unrecoverable-failure path as configuration changes and
                // foreground restarts: finalize the partial recording and
                // surface a URL-tagged failure.
                failCaptureLocked(context: "resume after interruption", error: error)
                lock.unlock()
            }

        @unknown default:
            break
        }
    }
}

/// Tap-side state. `consume(buffer:)` runs only on the tap's serial callback
/// context; the continuation and frame counter are additionally lock-guarded
/// because the engine (any thread) swaps/reads them.
private final class CaptureSink: @unchecked Sendable {
    /// Writes through `CaptureFileWriting` rather than owning an `AVAudioFile`
    /// so the container stays readable mid-recording (TAB-86).
    private let writer: CaptureFileWriting
    private let stateLock = NSLock()
    private var captionContinuation: AsyncStream<AudioChunk>.Continuation?
    private var framesWritten: AVAudioFramePosition = 0

    /// Converter from the current incoming buffer format to the file's
    /// processing format; rebuilt whenever the incoming format changes.
    private var fileConverter: AVAudioConverter?
    private var fileConverterInputFormat: AVAudioFormat?

    /// Converter to the caption format (PCM16 mono @ 16 kHz); rebuilt on
    /// incoming-format change.
    private var captionConverter: AVAudioConverter?
    private var captionConverterInputFormat: AVAudioFormat?
    private let captionFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: AudioCaptureEngine.captionSampleRate,
        channels: 1,
        interleaved: false
    )

    init(writer: CaptureFileWriting) {
        self.writer = writer
    }

    var recordedDuration: TimeInterval {
        stateLock.lock(); defer { stateLock.unlock() }
        return Double(framesWritten) / writer.processingFormat.sampleRate
    }

    /// Completes the container. Safe to call once; the engine owns the timing.
    func finishFile() {
        writer.finish()
    }

    func replaceCaptionContinuation(_ continuation: AsyncStream<AudioChunk>.Continuation) {
        stateLock.lock()
        let previous = captionContinuation
        captionContinuation = continuation
        stateLock.unlock()
        previous?.finish()
    }

    func finishCaptionStream() {
        stateLock.lock()
        let continuation = captionContinuation
        captionContinuation = nil
        stateLock.unlock()
        continuation?.finish()
    }

    /// Tap callback. Never throws, never crashes capture: a failed conversion
    /// or write logs and drops that buffer — the next buffer tries again.
    func consume(buffer: AVAudioPCMBuffer) {
        guard buffer.frameLength > 0 else { return }

        writeToFile(buffer)
        emitCaptionChunk(buffer)
    }

    private func writeToFile(_ buffer: AVAudioPCMBuffer) {
        let targetFormat = writer.processingFormat
        let bufferToWrite: AVAudioPCMBuffer

        if buffer.format == targetFormat {
            bufferToWrite = buffer
        } else {
            guard let converted = convert(buffer, to: targetFormat, converter: &fileConverter, lastInputFormat: &fileConverterInputFormat) else {
                print("[AudioCaptureEngine] ⚠️ Dropped buffer: file conversion failed (\(buffer.format) → \(targetFormat))")
                return
            }
            bufferToWrite = converted
        }

        do {
            try writer.write(bufferToWrite)
            stateLock.lock()
            framesWritten += AVAudioFramePosition(bufferToWrite.frameLength)
            stateLock.unlock()
        } catch {
            print("[AudioCaptureEngine] ⚠️ File write failed: \(error)")
        }
    }

    private func emitCaptionChunk(_ buffer: AVAudioPCMBuffer) {
        stateLock.lock()
        let continuation = captionContinuation
        stateLock.unlock()
        guard let continuation, let captionFormat else { return }

        let captionBuffer: AVAudioPCMBuffer
        if buffer.format == captionFormat {
            captionBuffer = buffer
        } else {
            guard let converted = convert(buffer, to: captionFormat, converter: &captionConverter, lastInputFormat: &captionConverterInputFormat) else {
                return
            }
            captionBuffer = converted
        }

        let frameLength = Int(captionBuffer.frameLength)
        guard frameLength > 0, let channelData = captionBuffer.int16ChannelData?[0] else { return }
        let data = Data(bytes: channelData, count: frameLength * MemoryLayout<Int16>.size)
        continuation.yield(AudioChunk(data: data, sampleRate: captionFormat.sampleRate))
    }

    private func convert(
        _ buffer: AVAudioPCMBuffer,
        to targetFormat: AVAudioFormat,
        converter: inout AVAudioConverter?,
        lastInputFormat: inout AVAudioFormat?
    ) -> AVAudioPCMBuffer? {
        if converter == nil || lastInputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: targetFormat)
            lastInputFormat = buffer.format
        }
        guard let converter else { return nil }

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up) + 16)
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return nil }

        var fed = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, outStatus in
            if fed {
                outStatus.pointee = .noDataNow
                return nil
            }
            fed = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard conversionError == nil, status != .error, output.frameLength > 0 else { return nil }
        return output
    }
}
#endif
