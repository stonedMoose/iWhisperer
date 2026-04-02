import AVFoundation
import Foundation

/// Thread-safe audio capture using whisper.cpp's expected 16 kHz mono Float32 format.
///
/// ## Thread-safety model
/// `AudioCapture` is `@unchecked Sendable` because AVAudioEngine's tap callback fires on
/// an arbitrary real-time audio thread, making it impossible to use Swift actor isolation
/// (which requires async hops) for the hot path. Instead, all mutable state
/// (`audioBuffer`, `onSamples`, `accumulateBuffer`) is serialised through a dedicated
/// serial `DispatchQueue` (`bufferQueue`). The invariant is:
///   - **Every read and write** of the three mutable properties goes through `bufferQueue`.
///   - `engine` is only touched on the caller's thread (always `@MainActor` in practice)
///     before/after the tap is installed or removed, never concurrently with itself.
final class AudioCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()

    // All three properties below are accessed exclusively via `bufferQueue`.
    private var audioBuffer: [Float] = []
    private var onSamples: (([Float]) -> Void)?
    private var accumulateBuffer = true

    /// Serial queue that serialises all access to the mutable audio-buffer state.
    /// Using a serial DispatchQueue (vs. NSLock) lets us use `sync` for reads/writes
    /// and keeps the locking discipline explicit and easy to audit.
    private let bufferQueue = DispatchQueue(label: "fr.moose.Whisperer.AudioCapture.buffer")

    /// Request microphone permission. Returns true if granted.
    static func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func setOnSamples(_ callback: (([Float]) -> Void)?) {
        bufferQueue.sync { onSamples = callback }
    }

    func setAccumulateBuffer(_ enabled: Bool) {
        bufferQueue.sync {
            accumulateBuffer = enabled
            if !enabled { audioBuffer.removeAll() }
        }
    }

    /// Start capturing audio from the microphone at 16kHz mono (what whisper.cpp expects).
    func startRecording(deviceUID: String = "") throws {
        if !deviceUID.isEmpty, let deviceID = AudioDeviceManager.deviceID(forUID: deviceUID) {
            var id = deviceID
            let status = AudioUnitSetProperty(
                engine.inputNode.audioUnit!,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &id,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            if status != noErr {
                Log.audio.error("Failed to set input device \(deviceUID): \(status)")
            }
        }

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

        bufferQueue.sync { audioBuffer.removeAll() }

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
                // bufferQueue serialises all mutable state; sync is safe on the audio thread
                // because this closure does no I/O and finishes in microseconds.
                let callback: (([Float]) -> Void)? = self.bufferQueue.sync {
                    if self.accumulateBuffer {
                        self.audioBuffer.append(contentsOf: samples)
                    }
                    return self.onSamples
                }
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

        return bufferQueue.sync {
            let samples = audioBuffer
            audioBuffer.removeAll()
            onSamples = nil
            return samples
        }
    }

    /// Return the last `lengthMs` of audio for the streaming sliding window.
    /// The buffer is capped at `lengthMs` to prevent unbounded growth while
    /// preserving the full window worth of context for the next iteration.
    /// (The `keepMs` parameter is retained for API compatibility but unused.)
    func getWindow(lengthMs: Int, keepMs: Int) -> [Float] {
        bufferQueue.sync {
            let lengthSamples = lengthMs * 16

            let maxSamples = min(audioBuffer.count, lengthSamples)
            if maxSamples <= 0 { return [] }

            let window = Array(audioBuffer.suffix(maxSamples))

            // Cap buffer at lengthSamples to prevent unbounded growth.
            // Keeps the full window worth of context so consecutive calls
            // share ~(lengthMs - stepMs) seconds of overlap — required for
            // LocalAgreement to find stable words across iterations.
            if audioBuffer.count > lengthSamples {
                audioBuffer = Array(audioBuffer.suffix(lengthSamples))
            }

            return window
        }
    }

    /// Return all samples captured so far without clearing the buffer.
    func peekSamples() -> [Float] {
        bufferQueue.sync { audioBuffer }
    }

    /// Current number of captured samples.
    var sampleCount: Int {
        bufferQueue.sync { audioBuffer.count }
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
