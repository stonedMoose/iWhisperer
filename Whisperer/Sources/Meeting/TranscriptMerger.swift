import Foundation

/// Merges whisper.cpp transcription segments with speaker diarization labels.
enum TranscriptMerger {
    struct MergedSegment {
        let start: Double
        let end: Double
        let text: String
        let speaker: String
    }

    /// Assign speaker labels to transcription segments by finding the diarization
    /// segment with the greatest time overlap for each transcription segment.
    static func merge(
        transcriptionSegments: [(start: Double, end: Double, text: String)],
        speakerSegments: [SpeakerSegment]
    ) -> [MergedSegment] {
        transcriptionSegments.map { tseg in
            let speaker = bestOverlappingSpeaker(
                start: tseg.start,
                end: tseg.end,
                speakerSegments: speakerSegments
            )
            return MergedSegment(
                start: tseg.start,
                end: tseg.end,
                text: tseg.text,
                speaker: speaker
            )
        }
    }

    private static func bestOverlappingSpeaker(
        start: Double,
        end: Double,
        speakerSegments: [SpeakerSegment]
    ) -> String {
        var bestSpeaker = "UNKNOWN"
        var bestOverlap: Double = 0

        for seg in speakerSegments {
            let overlapStart = max(start, seg.start)
            let overlapEnd = min(end, seg.end)
            let overlap = max(0, overlapEnd - overlapStart)

            if overlap > bestOverlap {
                bestOverlap = overlap
                bestSpeaker = seg.speaker
            }
        }

        return bestSpeaker
    }
}
