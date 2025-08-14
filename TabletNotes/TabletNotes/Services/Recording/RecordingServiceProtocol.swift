import Foundation
import Combine

protocol RecordingServiceProtocol {
    var isRecordingPublisher: AnyPublisher<Bool, Never> { get }
    var audioFileURLPublisher: AnyPublisher<URL?, Never> { get }
    var audioFileNamePublisher: AnyPublisher<String?, Never> { get }
    var isPausedPublisher: AnyPublisher<Bool, Never> { get }
    func startRecording(serviceType: String) throws
    func stopRecording()
    func pauseRecording() throws
    func resumeRecording() throws
} 