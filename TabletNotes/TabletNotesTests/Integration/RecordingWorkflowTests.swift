import Foundation
import Testing
@testable import TabletNotes

@MainActor
struct RecordingWorkflowTests {
    private let mockAuthService = MockAuthService()
    private let mockRecordingService = MockRecordingService()
    private let mockSupabaseService = MockSupabaseService()

    private func setupTest() async throws {
        mockRecordingService.resetState()
        mockSupabaseService.clearMockData()
        mockAuthService.resetState()
        _ = try await mockAuthService.signIn(email: "test@example.com", password: "password123")
    }

    @Test func testCompleteRecordingWorkflow() async throws {
        try await setupTest()

        let hasPermission = try await mockRecordingService.requestPermissions()
        #expect(hasPermission == true)

        try mockRecordingService.startRecording(serviceType: "Sunday Service")
        guard let recordingURL = mockRecordingService.getCurrentRecordingURL() else {
            Issue.record("Expected recording URL after starting recording")
            return
        }
        #expect(mockRecordingService.isRecording == true)
        #expect(recordingURL.pathExtension == "m4a")

        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(mockRecordingService.getRecordingDuration() > 0)

        guard let finalURL = mockRecordingService.stopRecording() else {
            Issue.record("Expected recording URL when stopping recording")
            return
        }
        #expect(mockRecordingService.isRecording == false)
        #expect(finalURL == recordingURL)

        let testAudioData = Data("Mock audio data for recording".utf8)
        let upload = try await mockSupabaseService.getSignedUploadURL(
            for: finalURL.lastPathComponent,
            contentType: "audio/m4a",
            fileSize: testAudioData.count
        )

        try await mockSupabaseService.uploadFile(data: testAudioData, to: upload.uploadUrl)
        let downloadURL = try await mockSupabaseService.getSignedDownloadURL(for: upload.path)

        #expect(upload.path.hasSuffix(finalURL.lastPathComponent))
        #expect(mockSupabaseService.storedFile(at: upload.path) == testAudioData)
        #expect(downloadURL.absoluteString.contains(finalURL.lastPathComponent))
    }

    @Test func testRecordingWorkflowWithPauseResume() async throws {
        try await setupTest()

        try mockRecordingService.startRecording(serviceType: "Sunday Service")
        #expect(mockRecordingService.isRecording == true)

        try await Task.sleep(nanoseconds: 100_000_000)
        let durationBeforePause = mockRecordingService.getRecordingDuration()

        try mockRecordingService.pauseRecording()
        #expect(mockRecordingService.isRecording == true)
        #expect(mockRecordingService.isPaused == true)

        try await Task.sleep(nanoseconds: 100_000_000)
        let durationWhilePaused = mockRecordingService.getRecordingDuration()
        #expect(durationWhilePaused == durationBeforePause)

        try mockRecordingService.resumeRecording()
        #expect(mockRecordingService.isPaused == false)

        try await Task.sleep(nanoseconds: 100_000_000)
        let finalDuration = mockRecordingService.getRecordingDuration()
        #expect(finalDuration > durationWhilePaused)

        _ = mockRecordingService.stopRecording()
        #expect(mockRecordingService.isRecording == false)
    }

    @Test func testRecordingWorkflowWithAuthenticationFailure() async throws {
        mockSupabaseService.clearMockData()
        mockRecordingService.resetState()

        try mockRecordingService.startRecording(serviceType: "Sunday Service")
        _ = mockRecordingService.stopRecording()

        mockSupabaseService.setShouldFailNextCall(.authenticationRequired)

        await #expect(throws: MockSupabaseError.self) {
            try await mockSupabaseService.getSignedUploadURL(
                for: "test.m4a",
                contentType: "audio/m4a",
                fileSize: 0
            )
        }
    }

    @Test func testRecordingWorkflowWithNetworkFailure() async throws {
        try await setupTest()

        try mockRecordingService.startRecording(serviceType: "Sunday Service")
        guard let recordingURL = mockRecordingService.getCurrentRecordingURL() else {
            Issue.record("Expected recording URL after starting recording")
            return
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        _ = mockRecordingService.stopRecording()

        let upload = try await mockSupabaseService.getSignedUploadURL(
            for: recordingURL.lastPathComponent,
            contentType: "audio/m4a",
            fileSize: 0
        )
        mockSupabaseService.setShouldFailNextCall(.networkError)

        await #expect(throws: MockSupabaseError.self) {
            try await mockSupabaseService.uploadFile(data: Data(), to: upload.uploadUrl)
        }
    }

    @Test func testRecordingWorkflowWithPermissionDenied() async throws {
        try await setupTest()
        mockRecordingService.setShouldFailNextCall(true, error: RecordingError.permissionDenied)

        await #expect(throws: RecordingError.self) {
            try await mockRecordingService.requestPermissions()
        }

        await #expect(throws: RecordingError.self) {
            try mockRecordingService.startRecording(serviceType: "Sunday Service")
        }
    }

    @Test func testSermonCreationAndAudioUploadWorkflow() async throws {
        try await setupTest()
        guard let user = mockAuthService.currentUser else {
            Issue.record("User should be signed in")
            return
        }

        let sermon = Sermon(
            title: "Integration Test Sermon",
            audioFileName: "test-recording.m4a",
            date: Date(),
            serviceType: "Sunday Service",
            userId: user.id
        )

        let upload = try await mockSupabaseService.getSignedUploadURL(
            for: sermon.audioFileName,
            contentType: "audio/m4a",
            fileSize: 32
        )
        let sermonAudio = Data("Sermon audio".utf8)
        try await mockSupabaseService.uploadFile(data: sermonAudio, to: upload.uploadUrl)

        #expect(sermon.userId == user.id)
        #expect(sermon.audioFileURL.lastPathComponent == sermon.audioFileName)
        #expect(mockSupabaseService.storedFile(at: upload.path) == sermonAudio)
    }

    @Test func testUserProfileUpdateWorkflow() async throws {
        try await setupTest()
        guard let user = mockAuthService.currentUser else {
            Issue.record("User should be signed in")
            return
        }

        let updatedAuthUser = try await mockAuthService.updateProfile(name: "Updated Name", email: nil)
        try await mockSupabaseService.updateUserProfile(updatedAuthUser)

        #expect(updatedAuthUser.name == "Updated Name")
        #expect(mockSupabaseService.storedUser(id: user.id)?.name == "Updated Name")
    }

    @Test func testWorkflowWithRetryLogic() async throws {
        try await setupTest()

        let upload = try await mockSupabaseService.getSignedUploadURL(
            for: "retry-test.m4a",
            contentType: "audio/m4a",
            fileSize: 15
        )
        mockSupabaseService.setShouldFailNextCall(.networkError)

        await #expect(throws: MockSupabaseError.self) {
            try await mockSupabaseService.uploadFile(data: Data(), to: upload.uploadUrl)
        }

        let retryData = Data("Retry test data".utf8)
        try await mockSupabaseService.uploadFile(data: retryData, to: upload.uploadUrl)

        #expect(mockSupabaseService.storedFile(at: upload.path) == retryData)
    }

    @Test func testConcurrentRecordingAttempts() async throws {
        try await setupTest()

        try mockRecordingService.startRecording(serviceType: "Sunday Service")
        #expect(mockRecordingService.isRecording == true)

        await #expect(throws: RecordingError.self) {
            try mockRecordingService.startRecording(serviceType: "Sunday Service")
        }

        #expect(mockRecordingService.isRecording == true)

        _ = mockRecordingService.stopRecording()
        #expect(mockRecordingService.isRecording == false)
    }
}
