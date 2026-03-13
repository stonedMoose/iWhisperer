import AVFoundation
import Foundation

final class AudioCapture: @unchecked Sendable {
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

    /// Start capturing audio from the microphone at 16kHz mono (what whisper.cpp expects).
    func startRecording() throws {
        let inputNode = engine.inputNode
        let nativeFormat = inputNode.outputFormat(forBus: 0)

        // whisper.cpp expects 16kHz mono Float32 audio
        guard let recordingFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioCaptureError.formatCreationFailed
        }

        // Install a converter to downsample from native rate to 16kHz
        guard let converter = AVAudioConverter(from: nativeFormat, to: recordingFormat) else {
            throw AudioCaptureError.converterCreationFailed
        }

        bufferLock.lock()
        audioBuffer.removeAll()
        bufferLock.unlock()

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nativeFormat) { [weak self] buffer, _ in
            guard let self else { return }

            let ratio = 16000.0 / nativeFormat.sampleRate
            let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: recordingFormat,
                frameCapacity: outputFrameCount
            ) else { return }

            var error: NSError?
            converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            if error == nil, let channelData = convertedBuffer.floatChannelData?[0] {
                let samples = Array(UnsafeBufferPointer(
                    start: channelData,
                    count: Int(convertedBuffer.frameLength)
                ))
                self.bufferLock.lock()
                self.audioBuffer.append(contentsOf: samples)
                self.bufferLock.unlock()
            }
        }

        engine.prepare()
        try engine.start()
    }

    /// Stop recording and return the captured audio samples at 16kHz mono.
    func stopRecording() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        bufferLock.lock()
        let samples = audioBuffer
        audioBuffer.removeAll()
        bufferLock.unlock()

        return samples
    }

    /// Return the last `lengthMs` of audio, retaining `keepMs` overlap context.
    /// Used by streaming mode to get a sliding window of audio.
    func getWindow(lengthMs: Int, keepMs: Int) -> [Float] {
        bufferLock.lock()
        let allSamples = audioBuffer
        bufferLock.unlock()

        let lengthSamples = lengthMs * 16  // 16kHz = 16 samples per ms
        let maxSamples = min(allSamples.count, lengthSamples)

        if maxSamples <= 0 { return [] }

        // Take the last `maxSamples` from the buffer
        return Array(allSamples.suffix(maxSamples))
    }

    /// Return all samples captured so far without clearing the buffer.
    func peekSamples() -> [Float] {
        bufferLock.lock()
        let samples = audioBuffer
        bufferLock.unlock()
        return samples
    }

    /// Current number of captured samples.
    var sampleCount: Int {
        bufferLock.lock()
        let count = audioBuffer.count
        bufferLock.unlock()
        return count
    }

}

enum AudioCaptureError: LocalizedError {
    case formatCreationFailed
    case converterCreationFailed

    var errorDescription: String? {
        switch self {
        case .formatCreationFailed: "Failed to create 16kHz audio format."
        case .converterCreationFailed: "Failed to create audio sample rate converter."
        }
    }
}
