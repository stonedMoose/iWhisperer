import AVFoundation
import Foundation

final class AudioCapture {
    private let engine = AVAudioEngine()
    private var audioBuffer: [Float] = []
    private let bufferLock = NSLock()

    /// Request microphone permission. Returns true if granted.
    static func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    /// Start capturing audio from the microphone.
    func startRecording() throws {
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        bufferLock.lock()
        audioBuffer.removeAll()
        bufferLock.unlock()

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let frameCount = Int(buffer.frameLength)
            guard let channelData = buffer.floatChannelData?[0] else { return }

            let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))

            self.bufferLock.lock()
            self.audioBuffer.append(contentsOf: samples)
            self.bufferLock.unlock()
        }

        engine.prepare()
        try engine.start()
    }

    /// Stop recording and return the captured audio samples.
    func stopRecording() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        bufferLock.lock()
        let samples = audioBuffer
        audioBuffer.removeAll()
        bufferLock.unlock()

        return samples
    }
}
