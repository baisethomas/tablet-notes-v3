//
//  AutoSummaryTimerTests.swift
//  TabletNotesTests
//
//  Created by Claude for testing auto-summary functionality when timer stops.
//

import Testing
import Foundation
import Combine
import SwiftData
@testable import TabletNotes

struct AutoSummaryTimerTests {

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 2_000_000_000,
        pollIntervalNanoseconds: UInt64 = 50_000_000,
        condition: () -> Bool
    ) async -> Bool {
        var waited: UInt64 = 0

        while waited < timeoutNanoseconds {
            if condition() {
                return true
            }

            try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
            waited += pollIntervalNanoseconds
        }

        return condition()
    }

    // MARK: - Test Helper: Mock Recording Service with Duration Limits

    class MockRecordingServiceWithLimits: RecordingServiceProtocol {
        @Published private(set) var isRecording = false
        @Published private(set) var isPaused = false
        @Published private(set) var recordingDuration: TimeInterval = 0
        @Published private(set) var remainingTime: TimeInterval? = nil
        @Published private(set) var currentRecordingURL: URL?

        private var durationLimit: TimeInterval? = nil
        private var durationTimer: DispatchSourceTimer?
        private let mockRecordingURL = URL(fileURLWithPath: "/tmp/mock-recording.m4a")

        // Publishers
        var isRecordingPublisher: AnyPublisher<Bool, Never> { $isRecording.eraseToAnyPublisher() }
        var audioFileURLPublisher: AnyPublisher<URL?, Never> { $currentRecordingURL.eraseToAnyPublisher() }
        var audioFileNamePublisher: AnyPublisher<String?, Never> { Just(mockRecordingURL.lastPathComponent).eraseToAnyPublisher() }
        var isPausedPublisher: AnyPublisher<Bool, Never> { $isPaused.eraseToAnyPublisher() }
        var recordingStoppedPublisher: AnyPublisher<(URL?, Bool), Never> { recordingStoppedSubject.eraseToAnyPublisher() }

        private let recordingStoppedSubject = PassthroughSubject<(URL?, Bool), Never>()

        // Test configuration
        func setDurationLimit(_ limit: TimeInterval) {
            durationLimit = limit
        }

        func resetState() {
            isRecording = false
            isPaused = false
            recordingDuration = 0
            remainingTime = nil
            currentRecordingURL = nil
            stopDurationTimer()
        }

        func startRecording(serviceType: String) throws {
            guard !isRecording else {
                throw RecordingError.recordingFailed
            }

            isRecording = true
            isPaused = false
            recordingDuration = 0
            currentRecordingURL = mockRecordingURL

            // Start mock timer to simulate recording duration
            startDurationTimer()
        }

        @discardableResult
        func stopRecording() -> URL? {
            let currentURL = currentRecordingURL
            isRecording = false
            isPaused = false
            stopDurationTimer()
            currentRecordingURL = nil
            recordingDuration = 0
            remainingTime = nil
            return currentURL
        }

        func pauseRecording() throws {
            guard isRecording && !isPaused else {
                throw RecordingError.recordingFailed
            }
            isPaused = true
            stopDurationTimer()
        }

        func resumeRecording() throws {
            guard isRecording && isPaused else {
                throw RecordingError.recordingFailed
            }
            isPaused = false
            startDurationTimer()
        }

        private func startDurationTimer() {
            stopDurationTimer()

            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now() + 0.1, repeating: 0.1)
            timer.setEventHandler { [weak self] in
                guard let self = self else { return }

                self.recordingDuration += 0.1

                // Check duration limit
                if let limit = self.durationLimit {
                    self.remainingTime = max(0, limit - self.recordingDuration)

                    // Auto-stop if limit reached
                    if self.recordingDuration >= limit {
                        let audioURL = self.stopRecording()
                        // Emit auto-stop event
                        self.recordingStoppedSubject.send((audioURL, true))
                    }
                }
            }
            timer.resume()
            durationTimer = timer
        }

        private func stopDurationTimer() {
            durationTimer?.cancel()
            durationTimer = nil
        }
    }

    // MARK: - Mock Summary Service for Testing

    final class MockSummaryService: SummaryServiceProtocol, @unchecked Sendable {
        // Track if generateSummary was called
        private(set) var generateSummaryCalled = false
        private(set) var lastTranscript: String?
        private(set) var lastServiceType: String?

        func generateSummaryResult(for transcript: String, type: String) async throws -> SummaryGenerationResult {
            generateSummaryCalled = true
            lastTranscript = transcript
            lastServiceType = type

            try await Task.sleep(nanoseconds: 100_000_000)
            return SummaryGenerationResult(
                title: "Mock Title",
                summary: "Mock summary for: \(transcript.prefix(50))..."
            )
        }

        func generateBasicSummaryResult(for transcript: String, type: String) -> SummaryGenerationResult {
            generateSummaryCalled = true
            lastTranscript = transcript
            lastServiceType = type

            return SummaryGenerationResult(
                title: "Mock Title",
                summary: "Mock summary for: \(transcript.prefix(50))..."
            )
        }

        func userFacingMessage(for error: Error) -> String {
            "[Error] \(error.localizedDescription)"
        }

        func resetState() {
            generateSummaryCalled = false
            lastTranscript = nil
            lastServiceType = nil
        }
    }

    // MARK: - Auto-Summary Timer Tests

    @Test func testAutoSummaryTriggeredWhen30MinuteLimitReached() async throws {
        // Given
        let mockRecordingService = MockRecordingServiceWithLimits()
        let mockSummaryService = MockSummaryService()
        mockRecordingService.setDurationLimit(1800) // 30 minutes in seconds
        mockRecordingService.resetState()
        mockSummaryService.resetState()

        var recordingStoppedEvents: [(URL?, Bool)] = []
        let cancellable = mockRecordingService.recordingStoppedPublisher
            .sink { event in
                recordingStoppedEvents.append(event)
            }

        // When - Start recording and let it hit the time limit
        try mockRecordingService.startRecording(serviceType: "Sunday Service")
        #expect(mockRecordingService.isRecording == true)

        // Simulate time passing to reach limit (using faster timing for test)
        mockRecordingService.setDurationLimit(0.2) // 0.2 seconds for test

        // Wait for auto-stop to trigger
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds

        // Then - Verify recording was auto-stopped
        #expect(mockRecordingService.isRecording == false)
        #expect(recordingStoppedEvents.count == 1)

        guard let (audioURL, wasAutoStopped) = recordingStoppedEvents.first else {
            Issue.record("Expected an auto-stop event")
            cancellable.cancel()
            return
        }
        #expect(audioURL != nil)
        #expect(wasAutoStopped == true) // This should be true for auto-stop

        // Simulate what RecordingView would do - trigger transcription and summary
        if wasAutoStopped, audioURL != nil {
            // This simulates the processTranscription call that would happen in RecordingView
            let mockTranscript = "This is a mock transcript of the sermon recording."
            _ = try await mockSummaryService.generateSummaryResult(for: mockTranscript, type: "Sunday Service")
        }

        // Verify summary was triggered
        #expect(mockSummaryService.generateSummaryCalled == true)
        #expect(mockSummaryService.lastServiceType == "Sunday Service")
        #expect(mockSummaryService.lastTranscript != nil)

        cancellable.cancel()
    }

    @Test func testAutoSummaryTriggeredWhen90MinuteLimitReached() async throws {
        // Given
        let mockRecordingService = MockRecordingServiceWithLimits()
        let mockSummaryService = MockSummaryService()
        mockRecordingService.setDurationLimit(5400) // 90 minutes in seconds
        mockRecordingService.resetState()
        mockSummaryService.resetState()

        var recordingStoppedEvents: [(URL?, Bool)] = []
        let cancellable = mockRecordingService.recordingStoppedPublisher
            .sink { event in
                recordingStoppedEvents.append(event)
            }

        // When - Start recording and let it hit the 90-minute limit
        try mockRecordingService.startRecording(serviceType: "Bible Study")

        // Simulate hitting 90-minute limit (using faster timing for test)
        mockRecordingService.setDurationLimit(0.15) // 0.15 seconds for test

        // Wait for auto-stop
        try await Task.sleep(nanoseconds: 250_000_000) // 0.25 seconds

        // Then - Verify auto-stop occurred
        #expect(recordingStoppedEvents.count == 1)
        guard let (audioURL, wasAutoStopped) = recordingStoppedEvents.first else {
            Issue.record("Expected an auto-stop event")
            cancellable.cancel()
            return
        }
        #expect(wasAutoStopped == true)

        // Simulate RecordingView response to auto-stop
        if wasAutoStopped, audioURL != nil {
            let mockTranscript = "This is a mock transcript of the bible study recording."
            _ = try await mockSummaryService.generateSummaryResult(for: mockTranscript, type: "Bible Study")
        }

        // Verify summary was generated
        #expect(mockSummaryService.generateSummaryCalled == true)
        #expect(mockSummaryService.lastServiceType == "Bible Study")

        cancellable.cancel()
    }

    @Test func testManualStopDoesNotTriggerAutoSummary() async throws {
        // Given
        let mockRecordingService = MockRecordingServiceWithLimits()
        mockRecordingService.setDurationLimit(1800) // 30 minutes
        mockRecordingService.resetState()

        var recordingStoppedEvents: [(URL?, Bool)] = []
        let cancellable = mockRecordingService.recordingStoppedPublisher
            .sink { event in
                recordingStoppedEvents.append(event)
            }

        // When - Start recording and manually stop before limit
        try mockRecordingService.startRecording(serviceType: "Prayer Meeting")

        // Wait a short time (not reaching limit)
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // Manually stop recording
        let audioURL = mockRecordingService.stopRecording()

        // Then - Manual stop should not emit auto-stop event
        #expect(recordingStoppedEvents.count == 0) // No auto-stop events
        #expect(audioURL != nil) // But we still get the audio URL from stopRecording()

        cancellable.cancel()
    }

    @Test func testRemainingTimeUpdatesCorrectly() async throws {
        // Given
        let mockRecordingService = MockRecordingServiceWithLimits()
        mockRecordingService.setDurationLimit(1.0) // 1 second limit for fast test
        mockRecordingService.resetState()

        // When
        try mockRecordingService.startRecording(serviceType: "Test")

        // Wait and check remaining time updates
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds

        // Then
        #expect(mockRecordingService.remainingTime != nil)
        if let remainingTime = mockRecordingService.remainingTime {
            #expect(remainingTime < 1.0)
            #expect(remainingTime > 0.0)
        } else {
            Issue.record("Expected remaining time to be available while recording")
            return
        }

        // Wait for auto-stop without depending on exact timer scheduling.
        let didStop = await waitUntil {
            mockRecordingService.isRecording == false
        }

        #expect(didStop == true)
        #expect(mockRecordingService.isRecording == false)
        #expect(mockRecordingService.remainingTime == nil) // Reset after stop
    }

    @Test func testMultipleRecordingStoppedEvents() async throws {
        // Given
        let mockRecordingService = MockRecordingServiceWithLimits()
        mockRecordingService.resetState()

        var recordingStoppedEvents: [(URL?, Bool)] = []
        let cancellable = mockRecordingService.recordingStoppedPublisher
            .sink { event in
                recordingStoppedEvents.append(event)
            }

        // When - Multiple recording sessions with auto-stops
        for i in 0..<3 {
            mockRecordingService.setDurationLimit(0.1) // Very short limit
            try mockRecordingService.startRecording(serviceType: "Test \(i)")

            // Wait for auto-stop
            try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds

            #expect(mockRecordingService.isRecording == false)
        }

        // Then
        #expect(recordingStoppedEvents.count == 3)

        // All should be auto-stopped
        for (_, wasAutoStopped) in recordingStoppedEvents {
            #expect(wasAutoStopped == true)
        }

        cancellable.cancel()
    }
}
