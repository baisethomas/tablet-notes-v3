import AVFoundation
import Foundation
import Testing

@testable import TabletNotes

/// TAB-86: a recording interrupted before `finish()` must still be playable.
///
/// "Interrupted" is modelled by writing buffers and then reading the file
/// **without finishing** — which is exactly the on-disk state left behind when
/// the process is killed mid-recording. No microphone is involved; the buffers
/// are synthesised, so this runs anywhere.
@Suite("Capture file writers")
struct CaptureFileWriterTests {

    // MARK: - Fixtures

    private static let sampleRate: Double = 44_100

    private static var inputFormat: AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
    }

    private static var encoderSettings: [String: Any] {
        [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
    }

    /// A second of a 220 Hz tone — deliberately not silence, so a decoder that
    /// merely opens the file without reading samples cannot pass by accident.
    private static func toneBuffer(seconds: Double, startPhase: Double = 0) -> AVAudioPCMBuffer {
        let format = inputFormat
        let frames = AVAudioFrameCount(seconds * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let step = 2.0 * Double.pi * 220.0 / sampleRate
        for channel in 0..<Int(format.channelCount) {
            guard let data = buffer.floatChannelData?[channel] else { continue }
            for frame in 0..<Int(frames) {
                data[frame] = Float(sin(startPhase + Double(frame) * step) * 0.5)
            }
        }
        return buffer
    }

    private static func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("tab86-\(UUID().uuidString).m4a")
    }

    /// Duration a decoder can actually read back, or nil if the file cannot be
    /// opened at all. Uses `AVAudioFile(forReading:)` — the same container
    /// parsing that the transcription provider and the app's own player need.
    private static func readableDuration(_ url: URL) -> TimeInterval? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        guard file.length > 0 else { return nil }
        return Double(file.length) / file.processingFormat.sampleRate
    }

    // MARK: - The regression

    @Test("AVAudioFile leaves an unreadable file when the process never finishes it")
    func unfragmentedWriterIsUnreadableBeforeFinish() throws {
        let url = Self.tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let writer = try UnfragmentedM4AWriter(url: url, settings: Self.encoderSettings)
        for index in 0..<6 {
            try writer.write(Self.toneBuffer(seconds: 1, startPhase: Double(index)))
        }

        // The process dies here — finish() is never called.
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        #expect(size > 0, "audio bytes did reach disk")
        #expect(
            Self.readableDuration(url) == nil,
            "this is the TAB-86 bug: bytes on disk, no index, nothing can read them"
        )
    }

    @Test("Fragmented writer leaves a playable file when the process never finishes it")
    func fragmentedWriterSurvivesAnInterruption() async throws {
        let url = Self.tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let writer = try FragmentedM4AWriter(
            url: url,
            settings: Self.encoderSettings,
            inputFormat: Self.inputFormat,
            fragmentInterval: 1.0
        )
        for index in 0..<6 {
            try writer.write(Self.toneBuffer(seconds: 1, startPhase: Double(index)))
        }
        // Give the writer a moment to flush fragments to disk.
        try await Task.sleep(nanoseconds: 500_000_000)

        // The process dies here — finish() is never called.
        let duration = Self.readableDuration(url)
        #expect(duration != nil, "an interrupted fragmented file must still open")
        #expect(
            (duration ?? 0) >= 3,
            "should recover most of the 6s written, got \(duration.map { "\($0)s" } ?? "nothing")"
        )
    }

    @Test("Fragmented writer produces a complete file when finished normally")
    func fragmentedWriterIsCompleteAfterFinish() throws {
        let url = Self.tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let writer = try FragmentedM4AWriter(
            url: url,
            settings: Self.encoderSettings,
            inputFormat: Self.inputFormat,
            fragmentInterval: 1.0
        )
        for index in 0..<3 {
            try writer.write(Self.toneBuffer(seconds: 1, startPhase: Double(index)))
        }
        writer.finish()

        let duration = try #require(Self.readableDuration(url))
        #expect(duration >= 2.5 && duration <= 3.5, "expected ~3s, got \(duration)s")
    }
}
