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
    ///
    /// Throws if the file may be incomplete. It deliberately does *not* mean
    /// "the recording is gone" — the caller still gets its URL and the audio
    /// written so far. It means the caller must not report unqualified success.
    func finish() throws
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

    func finish() throws {
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
    /// Finalization did not complete cleanly. The file is still playable up to
    /// the last written fragment — this reports *incompleteness*, not loss.
    case finishIncomplete(String)

    var errorDescription: String? {
        switch self {
        case .couldNotCreateWriter(let detail): return "Could not start the audio writer: \(detail)"
        case .notWritable(let detail): return "The audio writer stopped accepting data: \(detail)"
        case .bufferConversionFailed: return "Could not convert an audio buffer for writing"
        case .finishIncomplete(let detail): return "The recording may be incomplete: \(detail)"
        }
    }
}

/// Writes a **fragmented** MP4 via `AVAssetWriter`.
///
/// The difference that matters: `movieFragmentInterval` makes the writer emit
/// an index up front and then a `moof`/`mdat` fragment pair every interval. This
/// is a documented guarantee, not an inference — `AVAssetWriter.h` states that
/// with movie fragments "a partially written asset whose writing is unexpectedly
/// interrupted can be successfully opened and played up to multiples of the
/// specified time interval."
///
/// Scope, stated precisely: this bounds the loss to the **current fragment**. It
/// is not a claim that no sample can ever be lost to a hard kill — samples
/// buffered since the last fragment boundary go with the process. Reducing the
/// worst case from "the entire recording" to "≤ one fragment" is the goal.
/// Verified only by reading a file back mid-write; the force-quit-on-device
/// check is what actually exercises process death.
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

    /// Buffers the encoder was not ready for, held rather than dropped.
    private var pending: [CMSampleBuffer] = []
    /// ~19s at the engine's 4096-frame tap size — generous, but bounded.
    private static let maxPendingBuffers = 200
    /// Audio that never reached the encoder. Surfaced by `finish()`; a non-zero
    /// value means the recording really is missing samples.
    private var droppedBuffers = 0

    let processingFormat: AVAudioFormat

    /// - Parameter fragmentInterval: seconds of audio per fragment, and so the
    ///   worst-case loss on an interruption.
    ///
    ///   10s follows Apple's documented guidance ("for best writing performance
    ///   ... set the movieFragmentInterval to 10 seconds or greater"). A shorter
    ///   interval would narrow the loss window, but the write-performance cost
    ///   is not something this change can measure on device, and the difference
    ///   between losing 5s and 10s is immaterial next to losing all 45 minutes.
    ///   Parameterised so tests need not wait.
    init(
        url: URL,
        settings: [String: Any],
        inputFormat: AVAudioFormat,
        fragmentInterval: TimeInterval = 10
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
        let pts = CMTime(
            value: framesWritten,
            timescale: CMTimeScale(processingFormat.sampleRate)
        )
        guard let sample = Self.makeSampleBuffer(from: buffer, presentationTime: pts) else {
            throw CaptureWriterError.bufferConversionFailed
        }
        framesWritten += AVAudioFramePosition(buffer.frameLength)

        // The tap must never block, but audio must never be silently dropped
        // either — this app records things that cannot be re-captured. So a
        // buffer the encoder is not ready for is held and retried on the next
        // write rather than discarded.
        pending.append(sample)
        drainPendingLocked()
    }

    /// Appends as much of the backlog as the encoder will currently take.
    ///
    /// `expectsMediaDataInRealTime` means the input is ready essentially always
    /// for audio, so in practice the queue holds at most one buffer. The cap
    /// exists so a wedged encoder cannot grow it without bound; hitting it is
    /// logged loudly because it means audio really was lost.
    private func drainPendingLocked() {
        while let next = pending.first, input.isReadyForMoreMediaData {
            guard input.append(next) else {
                print("[FragmentedM4AWriter] ⚠️ append failed: \(writer.error?.localizedDescription ?? "unknown")")
                return
            }
            pending.removeFirst()
        }
        if pending.count > Self.maxPendingBuffers {
            let overflow = pending.count - Self.maxPendingBuffers
            pending.removeFirst(overflow)
            droppedBuffers += overflow
            print("[FragmentedM4AWriter] ⚠️ encoder backlog exceeded \(Self.maxPendingBuffers) buffers; dropped \(overflow)")
        }
    }

    /// Bounded so a wedged `finishWriting` cannot hang the stop path forever.
    /// Audio finalization is normally well under a second.
    private static let finishTimeout: DispatchTimeInterval = .seconds(5)

    /// How long `finish()` will keep retrying the backlog before giving up.
    private static let drainTimeout: TimeInterval = 3

    func finish() throws {
        lock.lock()
        guard started, !finished else { lock.unlock(); return }
        // Blocks further writes, which makes it safe to release the lock
        // between drain attempts below.
        finished = true
        lock.unlock()

        // Retry rather than drain once. `pending` is only ever non-empty
        // because `isReadyForMoreMediaData` was false — so a single synchronous
        // drain at exactly that moment makes no progress, and discarding the
        // queue would throw away the tail of the recording (up to the 200-buffer
        // cap, ~19s) at the precise moment the user pressed stop. The audio is
        // sitting in memory; wait briefly for the encoder to take it.
        let deadline = Date().addingTimeInterval(Self.drainTimeout)
        while true {
            lock.lock()
            drainPendingLocked()
            let remaining = pending.count
            lock.unlock()
            if remaining == 0 || Date() >= deadline { break }
            Thread.sleep(forTimeInterval: 0.02)
        }

        lock.lock()
        let unwritten = pending.count + droppedBuffers
        pending.removeAll()
        lock.unlock()

        input.markAsFinished()

        // Synchronous on purpose: callers hand the URL straight to the
        // save/upload pipeline, so the file must be closed before this returns.
        // (The previous AVAudioFile path also finalized synchronously here —
        // writing a ~500KB index for a 45-minute recording — so this is not a
        // new stall, just a visible one.)
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        let timedOut = done.wait(timeout: .now() + Self.finishTimeout) == .timedOut

        // Everything below reports *incompleteness*. In every one of these
        // cases the fragments already on disk are playable and the caller
        // keeps its URL — what must not happen is reporting clean success.
        if timedOut {
            throw CaptureWriterError.finishIncomplete("finalization timed out; file is playable up to the last fragment")
        }
        if unwritten > 0 {
            throw CaptureWriterError.finishIncomplete("\(unwritten) buffer(s) never reached the encoder")
        }
        if writer.status == .failed {
            throw CaptureWriterError.finishIncomplete(
                writer.error?.localizedDescription ?? "writer failed during finalization"
            )
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
