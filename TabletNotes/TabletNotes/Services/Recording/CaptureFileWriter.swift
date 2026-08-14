import AVFoundation
import Foundation

/// How captured audio reaches disk (TAB-86).
///
/// This exists as a seam for one reason: **the container must stay readable
/// while the recording is still in progress.**
///
/// `AVAudioFile` does not satisfy that. It writes the `moov` atom — the index
/// that makes an m4a decodable — only when the last reference is dropped. Kill
/// the app mid-recording and the file on disk is `ftyp` plus raw AAC frames
/// with no index, which no decoder can open. Production evidence: 14 of 14
/// interrupted recordings on one account were unplayable, sizes 0.1–22 MB, all
/// imported by recovery as "Recovered Recording from …" and then failed
/// transcription forever.
///
/// Splitting this out also makes the behaviour testable without a microphone —
/// the writers take PCM buffers, so a test can synthesise them.
protocol CaptureFileWriting: AnyObject {
    /// Format the writer expects; callers convert to it before writing.
    var processingFormat: AVAudioFormat { get }

    /// Appends one buffer. Throwing is the writer's way of saying "this buffer
    /// was dropped" — capture continues, since a lost buffer is far better than
    /// a lost recording.
    func write(_ buffer: AVAudioPCMBuffer) throws

    /// Completes the file. After this the writer must not be written to again.
    /// A writer that is never finished must still leave a **playable** file.
    func finish()
}

// MARK: - The pre-TAB-86 behaviour, kept for comparison in tests

/// `AVAudioFile`-backed writer: finalizes only on deallocation.
///
/// Retained deliberately so the regression test can demonstrate the failure
/// this issue is about, rather than asserting it from memory. Not used by the
/// capture engine.
final class UnfragmentedM4AWriter: CaptureFileWriting {
    private var file: AVAudioFile?
    let processingFormat: AVAudioFormat

    init(url: URL, settings: [String: Any]) throws {
        let file = try AVAudioFile(forWriting: url, settings: settings)
        self.file = file
        self.processingFormat = file.processingFormat
    }

    func write(_ buffer: AVAudioPCMBuffer) throws {
        try file?.write(from: buffer)
    }

    func finish() {
        // Dropping the reference is what writes the moov — which is precisely
        // why an interrupted process produces an unreadable file.
        file = nil
    }
}

// MARK: - Crash-safe writer

enum CaptureWriterError: LocalizedError {
    case couldNotCreateWriter(String)
    case notWritable(String)
    case bufferConversionFailed

    var errorDescription: String? {
        switch self {
        case .couldNotCreateWriter(let detail): return "Could not start the audio writer: \(detail)"
        case .notWritable(let detail): return "The audio writer stopped accepting data: \(detail)"
        case .bufferConversionFailed: return "Could not convert an audio buffer for writing"
        }
    }
}

/// Writes a **fragmented** MP4 via `AVAssetWriter`.
///
/// The difference that matters: `movieFragmentInterval` makes the writer emit
/// an index up front and then a `moof`/`mdat` fragment pair every interval, so
/// the file on disk is continuously playable. An interruption costs at most the
/// current fragment instead of the entire recording.
///
/// Everything else is deliberately unchanged — same AAC encoder settings, same
/// `.m4a` path and extension, so playback, upload, and the transcription
/// provider see the same kind of file they always have.
final class FragmentedM4AWriter: CaptureFileWriting {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let lock = NSLock()
    private var framesWritten: AVAudioFramePosition = 0
    private var started = false
    private var finished = false

    let processingFormat: AVAudioFormat

    /// - Parameter fragmentInterval: seconds of audio per fragment. This is the
    ///   worst-case loss on an interruption, so it is short. It is a parameter
    ///   only so tests need not wait.
    init(
        url: URL,
        settings: [String: Any],
        inputFormat: AVAudioFormat,
        fragmentInterval: TimeInterval = 5
    ) throws {
        do {
            writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
        } catch {
            throw CaptureWriterError.couldNotCreateWriter(error.localizedDescription)
        }

        // The whole point of this class.
        writer.movieFragmentInterval = CMTime(seconds: fragmentInterval, preferredTimescale: 600)
        writer.shouldOptimizeForNetworkUse = false

        input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        // Capture is live: never make the tap wait on the encoder.
        input.expectsMediaDataInRealTime = true

        guard writer.canAdd(input) else {
            throw CaptureWriterError.couldNotCreateWriter("writer rejected the audio input")
        }
        writer.add(input)

        guard writer.startWriting() else {
            throw CaptureWriterError.couldNotCreateWriter(
                writer.error?.localizedDescription ?? "startWriting() returned false"
            )
        }
        writer.startSession(atSourceTime: .zero)

        processingFormat = inputFormat
        started = true
    }

    func write(_ buffer: AVAudioPCMBuffer) throws {
        lock.lock(); defer { lock.unlock() }
        guard started, !finished else { return }

        guard writer.status == .writing else {
            throw CaptureWriterError.notWritable(
                writer.error?.localizedDescription ?? "status \(writer.status.rawValue)"
            )
        }
        // Dropping a buffer the encoder is not ready for is correct here: the
        // alternative is blocking the audio tap, which risks the whole capture.
        guard input.isReadyForMoreMediaData else { return }

        let pts = CMTime(
            value: framesWritten,
            timescale: CMTimeScale(processingFormat.sampleRate)
        )
        guard let sample = Self.makeSampleBuffer(from: buffer, presentationTime: pts) else {
            throw CaptureWriterError.bufferConversionFailed
        }
        guard input.append(sample) else {
            throw CaptureWriterError.notWritable(
                writer.error?.localizedDescription ?? "append() returned false"
            )
        }
        framesWritten += AVAudioFramePosition(buffer.frameLength)
    }

    func finish() {
        lock.lock()
        guard started, !finished else { lock.unlock(); return }
        finished = true
        lock.unlock()

        input.markAsFinished()

        // Callers hand the URL straight to save/upload, so the file has to be
        // complete before this returns. The wait is bounded; on timeout the
        // fragments already on disk still make a playable file, which is the
        // guarantee this class exists to provide.
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        if done.wait(timeout: .now() + 10) == .timedOut {
            print("[FragmentedM4AWriter] finishWriting timed out; fragments on disk remain playable")
        }
    }

    /// Wraps a PCM buffer as a `CMSampleBuffer` for `AVAssetWriterInput`.
    private static func makeSampleBuffer(
        from buffer: AVAudioPCMBuffer,
        presentationTime: CMTime
    ) -> CMSampleBuffer? {
        let formatDescription = buffer.format.formatDescription
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(buffer.format.sampleRate)),
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        let created = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: nil,
            dataReady: false,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleCount: CMItemCount(buffer.frameLength),
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )
        guard created == noErr, let sampleBuffer else { return nil }

        // Copies the samples, so the PCM buffer need not outlive this call.
        let attached = CMSampleBufferSetDataBufferFromAudioBufferList(
            sampleBuffer,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            bufferList: buffer.audioBufferList
        )
        guard attached == noErr else { return nil }
        return sampleBuffer
    }
}
