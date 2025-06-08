import Foundation
import Combine

protocol RecordingServiceProtocol {
    var isRecordingPublisher: AnyPublisher<Bool, Never> { get }
    var audioFileURLPublisher: AnyPublisher<URL?, Never> { get }
    func startRecording() throws
    func stopRecording() throws
    func pauseRecording() throws
    func resumeRecording() throws
} 