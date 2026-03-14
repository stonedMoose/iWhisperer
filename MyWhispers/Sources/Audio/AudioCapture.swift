import AVFoundation
import Foundation

final class AudioCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var audioBuffer: [Float] = []
    private let bufferLock = NSLock()
    private var onSamples: (([Float]) -> Void)?
    private var accumulateBuffer = true

    /// Request microphone permission. Returns true if granted.
    static func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func setOnSamples(_ callback: (([Float]) -> Void)?) {
        bufferLock.lock()
        onSamples = callback
        bufferLock.unlock()
    }

    func setAccumulateBuffer(_ enabled: Bool) {
        bufferLock.lock()
        accumulateBuffer = enabled
        if !enabled { audioBuffer.removeAll() }
        bufferLock.unlock()
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
            var provided = false
            converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                if !provided {
                    provided = true
                    outStatus.pointee = .haveData
                    return buffer
                }
                outStatus.pointee = .noDataNow
                return nil
            }

            if error == nil, let channelData = convertedBuffer.floatChannelData?[0] {
                let samples = Array(UnsafeBufferPointer(
                    start: channelData,
                    count: Int(convertedBuffer.frameLength)
                ))
                self.bufferLock.lock()
                if self.accumulateBuffer {
                    self.audioBuffer.append(contentsOf: samples)
                }
                let callback = self.onSamples
                self.bufferLock.unlock()
                callback?(samples)
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
        onSamples = nil
        bufferLock.unlock()

        return samples
    }

    /// Return the last `lengthMs` of audio, retaining `keepMs` overlap context.
    /// Used by streaming mode to get a sliding window of audio.
    func getWindow(lengthMs: Int, keepMs: Int) -> [Float] {
        bufferLock.lock()
        defer { bufferLock.unlock() }

        let lengthSamples = lengthMs * 16
        let keepSamples = keepMs * 16

        let maxSamples = min(audioBuffer.count, lengthSamples)
        if maxSamples <= 0 { return [] }

        let window = Array(audioBuffer.suffix(maxSamples))

        // Trim buffer to retain only keepMs overlap for next window
        let retainCount = min(audioBuffer.count, keepSamples)
        audioBuffer = Array(audioBuffer.suffix(retainCount))

        return window
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
