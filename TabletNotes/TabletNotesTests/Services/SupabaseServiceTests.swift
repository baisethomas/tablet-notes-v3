import Foundation
import Testing
@testable import TabletNotes

struct SupabaseServiceTests {
    private let mockSupabaseService = MockSupabaseService()

    private func setupTest() {
        mockSupabaseService.clearMockData()
    }

    @Test func testGetSignedUploadURLSuccess() async throws {
        setupTest()

        let result = try await mockSupabaseService.getSignedUploadURL(
            for: "test-recording.m4a",
            contentType: "audio/m4a",
            fileSize: 128
        )

        #expect(result.path == "mock-user/test-recording.m4a")
        #expect(result.uploadUrl.absoluteString.contains("test-recording.m4a"))
    }

    @Test func testGetSignedUploadURLForFileURLUsesFilename() async throws {
        setupTest()

        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        try Data("audio".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let result = try await mockSupabaseService.getSignedUploadURL(for: fileURL)

        #expect(result.path.hasSuffix(fileURL.lastPathComponent))
        #expect(result.uploadUrl.absoluteString.contains(fileURL.lastPathComponent))
    }

    @Test func testGetSignedUploadURLFailure() async throws {
        setupTest()
        mockSupabaseService.setShouldFailNextCall(.signedURLFailed)

        await #expect(throws: MockSupabaseError.self) {
            try await mockSupabaseService.getSignedUploadURL(
                for: "test.m4a",
                contentType: "audio/m4a",
                fileSize: 32
            )
        }
    }

    @Test func testUploadFileSuccessStoresData() async throws {
        setupTest()
        let testData = Data("Test audio data".utf8)
        let upload = try await mockSupabaseService.getSignedUploadURL(
            for: "stored-file.m4a",
            contentType: "audio/m4a",
            fileSize: testData.count
        )

        try await mockSupabaseService.uploadFile(data: testData, to: upload.uploadUrl)

        #expect(mockSupabaseService.storedFile(at: upload.path) == testData)
    }

    @Test func testUploadFileFailure() async throws {
        setupTest()
        let upload = try await mockSupabaseService.getSignedUploadURL(
            for: "test.m4a",
            contentType: "audio/m4a",
            fileSize: 16
        )
        mockSupabaseService.setShouldFailNextCall(.uploadFailed)

        await #expect(throws: MockSupabaseError.self) {
            try await mockSupabaseService.uploadFile(data: Data("Test".utf8), to: upload.uploadUrl)
        }
    }

    @Test func testGetSignedDownloadURLSuccess() async throws {
        setupTest()
        let path = "mock-user/downloadable.m4a"
        mockSupabaseService.seedFile(data: Data("audio".utf8), at: path)

        let downloadURL = try await mockSupabaseService.getSignedDownloadURL(for: path)

        #expect(downloadURL.absoluteString.contains("download"))
        #expect(downloadURL.absoluteString.contains("downloadable.m4a"))
    }

    @Test func testGetSignedDownloadURLMissingFile() async throws {
        setupTest()

        await #expect(throws: MockSupabaseError.self) {
            try await mockSupabaseService.getSignedDownloadURL(for: "mock-user/missing-file.m4a")
        }
    }

    @Test func testGetSignedDownloadURLFailure() async throws {
        setupTest()
        let path = "mock-user/failing-download.m4a"
        mockSupabaseService.seedFile(data: Data("audio".utf8), at: path)
        mockSupabaseService.setShouldFailNextCall(.downloadURLFailed)

        await #expect(throws: MockSupabaseError.self) {
            try await mockSupabaseService.getSignedDownloadURL(for: path)
        }
    }

    @Test func testUpdateUserProfileSuccess() async throws {
        setupTest()
        let user = User(id: UUID(), email: "test@example.com", name: "Original Name")
        user.name = "Updated Name"

        try await mockSupabaseService.updateUserProfile(user)

        #expect(mockSupabaseService.storedUser(id: user.id)?.name == "Updated Name")
    }

    @Test func testUpdateUserProfileFailure() async throws {
        setupTest()
        let user = User(id: UUID(), email: "test@example.com", name: "Updated Name")
        mockSupabaseService.setShouldFailNextCall(.updateFailed)

        await #expect(throws: MockSupabaseError.self) {
            try await mockSupabaseService.updateUserProfile(user)
        }
    }

    @Test func testUploadAndDownloadFlowUsesSameStoragePath() async throws {
        setupTest()
        let payload = Data("Integration audio".utf8)
        let upload = try await mockSupabaseService.getSignedUploadURL(
            for: "integration-test.m4a",
            contentType: "audio/m4a",
            fileSize: payload.count
        )

        try await mockSupabaseService.uploadFile(data: payload, to: upload.uploadUrl)
        let downloadURL = try await mockSupabaseService.getSignedDownloadURL(for: upload.path)

        #expect(mockSupabaseService.storedFile(at: upload.path) == payload)
        #expect(downloadURL.absoluteString.contains("integration-test.m4a"))
    }
}
