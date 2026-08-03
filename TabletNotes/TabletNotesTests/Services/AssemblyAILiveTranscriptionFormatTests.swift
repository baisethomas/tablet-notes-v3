import Foundation
import Testing
@testable import TabletNotes

// Regression coverage for the Crashlytics crash where installTap raised an
// uncatchable NSException ("Failed to create tap due to format mismatch")
// during an active recording. startAudioCapture now refuses to install a tap
// when the input hardware reports an unusable format, throwing a catchable
// Swift error instead so live captions degrade while the recording continues.
struct AssemblyAILiveTranscriptionFormatTests {
    @Test func rejectsZeroSampleRate() {
        #expect(!AssemblyAILiveTranscriptionService.isCaptureFormatUsable(sampleRate: 0, channelCount: 1))
    }

    @Test func rejectsZeroChannels() {
        #expect(!AssemblyAILiveTranscriptionService.isCaptureFormatUsable(sampleRate: 48000, channelCount: 0))
    }

    @Test func rejectsNegativeSampleRate() {
        #expect(!AssemblyAILiveTranscriptionService.isCaptureFormatUsable(sampleRate: -1, channelCount: 1))
    }

    @Test func acceptsTypicalHardwareFormats() {
        #expect(AssemblyAILiveTranscriptionService.isCaptureFormatUsable(sampleRate: 48000, channelCount: 1))
        #expect(AssemblyAILiveTranscriptionService.isCaptureFormatUsable(sampleRate: 44100, channelCount: 2))
    }
}
