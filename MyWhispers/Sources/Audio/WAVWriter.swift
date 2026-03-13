import Foundation

final class WAVWriter {
    private let fileHandle: FileHandle
    let url: URL
    private var dataSize: UInt32 = 0
    private let sampleRate: UInt32 = 16000
    private let bitsPerSample: UInt16 = 32
    private let channels: UInt16 = 1

    init(url: URL) throws {
        self.url = url

        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        FileManager.default.createFile(atPath: url.path, contents: nil)
        self.fileHandle = try FileHandle(forWritingTo: url)
        writeHeader()
    }

    private func writeHeader() {
        var header = Data()
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)

        // RIFF header
        header.append(contentsOf: "RIFF".utf8)
        header.append(uint32: 0) // placeholder for file size - 8
        header.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        header.append(contentsOf: "fmt ".utf8)
        header.append(uint32: 16) // chunk size
        header.append(uint16: 3)  // format: IEEE float
        header.append(uint16: channels)
        header.append(uint32: sampleRate)
        header.append(uint32: byteRate)
        header.append(uint16: blockAlign)
        header.append(uint16: bitsPerSample)

        // data chunk
        header.append(contentsOf: "data".utf8)
        header.append(uint32: 0) // placeholder for data size

        fileHandle.write(header)
    }

    func writeSamples(_ samples: [Float]) {
        let data = samples.withUnsafeBufferPointer { buffer in
            Data(bytes: buffer.baseAddress!, count: buffer.count * MemoryLayout<Float>.size)
        }
        fileHandle.write(data)
        dataSize += UInt32(data.count)
    }

    func finalize() throws {
        // Patch data size at offset 40
        fileHandle.seek(toFileOffset: 40)
        var size = dataSize
        fileHandle.write(Data(bytes: &size, count: 4))

        // Patch RIFF size at offset 4
        fileHandle.seek(toFileOffset: 4)
        var riffSize = dataSize + 36
        fileHandle.write(Data(bytes: &riffSize, count: 4))

        fileHandle.closeFile()
    }

    func cancel() {
        fileHandle.closeFile()
        try? FileManager.default.removeItem(at: url)
    }
}

private extension Data {
    mutating func append(uint16 value: UInt16) {
        var v = value.littleEndian
        append(Data(bytes: &v, count: 2))
    }

    mutating func append(uint32 value: UInt32) {
        var v = value.littleEndian
        append(Data(bytes: &v, count: 4))
    }
}
