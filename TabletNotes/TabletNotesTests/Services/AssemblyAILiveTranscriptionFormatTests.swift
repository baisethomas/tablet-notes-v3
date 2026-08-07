import Foundation
import AVFoundation
import Testing
@testable import TabletNotes

// Regression coverage for the Crashlytics crash where installTap raised an
// uncatchable NSException ("Failed to create tap due to format mismatch")
// during an active recording. AudioCaptureEngine (which replaced the dual
// AVAudioRecorder + second-engine stacks in TAB-71) refuses to install a tap
// when the input hardware reports an unusable format, and routes
// installTap/engine.start through the ObjC shim so residual races surface as
// throwable Swift errors instead of a process kill.
//
// The stale-WebSocket identity checks that used to live here
// (belongsToLiveConnection) are structurally replaced by the generation
// counter in StreamingTranscriber — covered by StreamingTranscriberTests.
struct AssemblyAILiveTranscriptionFormatTests {
    @Test func rejectsZeroSampleRate() {
        #expect(!AudioCaptureEngine.isCaptureFormatUsable(sampleRate: 0, channelCount: 1))
    }

    @Test func rejectsZeroChannels() {
        #expect(!AudioCaptureEngine.isCaptureFormatUsable(sampleRate: 48000, channelCount: 0))
    }

    @Test func rejectsNegativeSampleRate() {
        #expect(!AudioCaptureEngine.isCaptureFormatUsable(sampleRate: -1, channelCount: 1))
    }

    @Test func acceptsTypicalHardwareFormats() {
        #expect(AudioCaptureEngine.isCaptureFormatUsable(sampleRate: 48000, channelCount: 1))
        #expect(AudioCaptureEngine.isCaptureFormatUsable(sampleRate: 44100, channelCount: 2))
    }

    // The format guard cannot close the route-change window between the check
    // and installTap/start, so those calls run inside an ObjC @try/@catch shim.
    @Test func catchesRaisedObjCException() {
        let exception = ObjCExceptionCatcher.catching {
            NSException(
                name: NSExceptionName("TNTestException"),
                reason: "Failed to create tap due to format mismatch",
                userInfo: nil
            ).raise()
        }

        #expect(exception != nil)
        #expect(exception?.name.rawValue == "TNTestException")
        #expect(exception?.reason == "Failed to create tap due to format mismatch")
    }

    @Test func returnsNilWhenBlockCompletesNormally() {
        let exception = ObjCExceptionCatcher.catching {
            _ = 1 + 1
        }

        #expect(exception == nil)
    }
}
