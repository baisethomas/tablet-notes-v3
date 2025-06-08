import Foundation
import Combine

protocol TranscriptionServiceProtocol {
    var transcriptPublisher: AnyPublisher<String, Never> { get }
    var errorPublisher: AnyPublisher<Error?, Never> { get }
    func startTranscription(audioFileURL: URL) throws
    func stopTranscription() throws
    func resetTranscription() throws
} 