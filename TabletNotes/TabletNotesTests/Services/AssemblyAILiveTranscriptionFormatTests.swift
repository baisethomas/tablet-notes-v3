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

    // Receive and send callbacks queued on a task that teardown or reconnection
    // already cancelled still fire. Acting on them would flip isConnected true
    // with no socket and no tap (stranding startLiveTranscription() behind
    // `guard !isConnected`), or clear the new session's isConnected and drop its
    // audio buffers. Both paths gate on belongsToLiveConnection.
    @Test func acceptsCallbackFromTheLiveTask() {
        let session = URLSession(configuration: .ephemeral)
        let task = session.webSocketTask(with: URL(string: "wss://example.com/socket")!)

        #expect(AssemblyAILiveTranscriptionService.belongsToLiveConnection(task, currentTask: task))
    }

    @Test func rejectsCallbackFromAReplacedTask() {
        let session = URLSession(configuration: .ephemeral)
        let staleTask = session.webSocketTask(with: URL(string: "wss://example.com/socket")!)
        let liveTask = session.webSocketTask(with: URL(string: "wss://example.com/socket")!)

        #expect(!AssemblyAILiveTranscriptionService.belongsToLiveConnection(staleTask, currentTask: liveTask))
    }

    @Test func rejectsCallbackAfterTeardownClearsTheTask() {
        let session = URLSession(configuration: .ephemeral)
        let staleTask = session.webSocketTask(with: URL(string: "wss://example.com/socket")!)

        #expect(!AssemblyAILiveTranscriptionService.belongsToLiveConnection(staleTask, currentTask: nil))
    }

    @Test func rejectsCallbackWhenNoTaskWasCaptured() {
        let session = URLSession(configuration: .ephemeral)
        let liveTask = session.webSocketTask(with: URL(string: "wss://example.com/socket")!)

        #expect(!AssemblyAILiveTranscriptionService.belongsToLiveConnection(nil, currentTask: liveTask))
    }

    @Test func returnsNilWhenBlockCompletesNormally() {
        var ran = false
        let exception = ObjCExceptionCatcher.catching { ran = true }

        #expect(exception == nil)
        #expect(ran)
    }
}
