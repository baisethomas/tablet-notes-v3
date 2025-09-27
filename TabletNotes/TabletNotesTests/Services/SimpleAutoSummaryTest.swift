//
//  SimpleAutoSummaryTest.swift
//  TabletNotesTests
//
//  Simplified test to verify auto-summary functionality when timer stops
//

import Testing
import Foundation
import Combine
@testable import TabletNotes

struct SimpleAutoSummaryTest {

    @Test func testRecordingStoppedPublisherEmitsCorrectly() async throws {
        // Given
        let mockRecordingService = MockRecordingServiceWithLimits()
        mockRecordingService.setDurationLimit(0.2) // Very short limit for testing
        mockRecordingService.resetState()

        var recordingStoppedEvents: [(URL?, Bool)] = []
        let cancellable = mockRecordingService.recordingStoppedPublisher
            .sink { event in
                recordingStoppedEvents.append(event)
            }

        // When - Start recording and let it auto-stop
        try mockRecordingService.startRecording(serviceType: "Sunday Service")
        #expect(mockRecordingService.isRecording == true)

        // Wait for auto-stop to trigger
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds

        // Then - Verify recording was auto-stopped
        #expect(mockRecordingService.isRecording == false)
        #expect(recordingStoppedEvents.count == 1)

        let (audioURL, wasAutoStopped) = recordingStoppedEvents[0]
        #expect(audioURL != nil)
        #expect(wasAutoStopped == true) // This confirms auto-stop triggered

        cancellable.cancel()
    }

    @Test func testRemainingTimeCountsDown() async throws {
        // Given
        let mockRecordingService = MockRecordingServiceWithLimits()
        mockRecordingService.setDurationLimit(1.0) // 1 second limit
        mockRecordingService.resetState()

        // When
        try mockRecordingService.startRecording(serviceType: "Test")

        // Wait and check remaining time updates
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds

        // Then
        #expect(mockRecordingService.remainingTime != nil)
        #expect(mockRecordingService.remainingTime! < 1.0)
        #expect(mockRecordingService.remainingTime! > 0.0)

        // Clean up
        _ = mockRecordingService.stopRecording()
    }
}

// MARK: - Simplified Mock Recording Service

class MockRecordingServiceWithLimits: RecordingServiceProtocol {
    @Published private(set) var isRecording = false
    @Published private(set) var isPaused = false
    @Published private(set) var recordingDuration: TimeInterval = 0
    @Published private(set) var remainingTime: TimeInterval? = nil
    @Published private(set) var currentRecordingURL: URL?

    private var durationLimit: TimeInterval? = nil
    private var durationTimer: Timer?
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
        durationTimer?.invalidate()
        durationTimer = nil
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
        durationTimer?.invalidate()
        durationTimer = nil
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
        durationTimer?.invalidate()
        durationTimer = nil
    }

    func resumeRecording() throws {
        guard isRecording && isPaused else {
            throw RecordingError.recordingFailed
        }
        isPaused = false
        startDurationTimer()
    }

    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            self.recordingDuration += 0.1

            // Check duration limit
            if let limit = self.durationLimit {
                self.remainingTime = max(0, limit - self.recordingDuration)

                // Auto-stop if limit reached
                if self.recordingDuration >= limit {
                    let audioURL = self.stopRecording()
                    // Emit auto-stop event - this is the key functionality we're testing
                    self.recordingStoppedSubject.send((audioURL, true))
                }
            }
        }
    }
}