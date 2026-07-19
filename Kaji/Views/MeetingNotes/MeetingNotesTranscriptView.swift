import SwiftUI

struct MeetingNotesTranscriptView: View {
    let document: MeetingSessionDocument?
    let partialSegments: [MeetingTranscriptSegment]
    let status: MeetingNotesCoordinatorStatus

    var body: some View {
        ScrollView {
            if let document {
                let segments = document.transcriptSegments.filter(\.isFinal) + partialSegments.filter { partial in
                    document.tracks.contains(where: { $0.id == partial.trackID })
                }
                if segments.isEmpty, document.recordingGaps.isEmpty, document.transcriptionGaps.isEmpty {
                    MeetingNotesEmptyState(
                        icon: status == .recording ? "waveform" : "text.bubble",
                        title: status == .recording ? "Listening for speech" : "No transcript",
                        detail: status == .recording
                            ? "Final transcript segments can be delayed while local audio is processed."
                            : "This meeting does not have final transcript segments."
                    )
                } else {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(timeline(document: document, segments: segments)) { entry in
                            switch entry.content {
                            case let .segment(segment):
                                MeetingTranscriptSegmentRow(
                                    segment: segment,
                                    metadata: document.committedTranscriptMetadata.first { $0.id == segment.id },
                                    sourceName: sourceName(for: segment.trackID, in: document),
                                    captureStartMilliseconds: captureStartMilliseconds(in: document)
                                )
                            case let .gap(gap):
                                MeetingTranscriptGapRow(
                                    gap: gap,
                                    sourceName: sourceName(for: gap.trackID, in: document),
                                    captureStartMilliseconds: captureStartMilliseconds(in: document)
                                )
                            case let .transcriptionGap(gap):
                                MeetingTranscriptTranscriptionGapRow(
                                    gap: gap,
                                    sourceName: sourceName(for: gap.trackID, in: document),
                                    captureStartMilliseconds: captureStartMilliseconds(in: document)
                                )
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                MeetingNotesEmptyState(
                    icon: "text.bubble",
                    title: "No meeting selected",
                    detail: "Choose a meeting from History to read its transcript."
                )
            }
        }
    }

    private func sourceName(for trackID: UUID, in document: MeetingSessionDocument) -> String {
        document.tracks.first(where: { $0.id == trackID })?.displayName ?? "Unknown source"
    }

    private func captureStartMilliseconds(in document: MeetingSessionDocument) -> Int64 {
        document.session.lifecycle.startedAtMilliseconds ?? document.session.lifecycle.createdAtMilliseconds
    }

    private func timeline(
        document: MeetingSessionDocument,
        segments: [MeetingTranscriptSegment]
    ) -> [MeetingTranscriptTimelineEntry] {
        let segmentEntries = segments.map {
            MeetingTranscriptTimelineEntry(id: $0.id, startMilliseconds: $0.startMilliseconds, content: .segment($0))
        }
        let gapEntries = document.recordingGaps.map {
            MeetingTranscriptTimelineEntry(id: $0.id, startMilliseconds: $0.startMilliseconds, content: .gap($0))
        }
        let transcriptionGapEntries = document.transcriptionGaps.map {
            MeetingTranscriptTimelineEntry(
                id: $0.id,
                startMilliseconds: $0.startMilliseconds,
                content: .transcriptionGap($0)
            )
        }
        return (segmentEntries + gapEntries + transcriptionGapEntries).sorted {
            if $0.startMilliseconds == $1.startMilliseconds { return $0.id.uuidString < $1.id.uuidString }
            return $0.startMilliseconds < $1.startMilliseconds
        }
    }
}

private struct MeetingTranscriptTimelineEntry: Identifiable {
    enum Content {
        case segment(MeetingTranscriptSegment)
        case gap(MeetingRecordingGap)
        case transcriptionGap(MeetingTranscriptionGap)
    }

    let id: UUID
    let startMilliseconds: Int64
    let content: Content
}

private struct MeetingTranscriptSegmentRow: View {
    let segment: MeetingTranscriptSegment
    let metadata: MeetingCommittedTranscriptMetadata?
    let sourceName: String
    let captureStartMilliseconds: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Text(MeetingNotesTimeFormatter.transcript(
                    segment.startMilliseconds,
                    relativeTo: captureStartMilliseconds
                ))
                .kajiFont(size: 10, weight: .medium, design: .monospaced)
                .foregroundStyle(KajiTheme.fgDim)
                Text(segment.speakerLabel ?? sourceName)
                    .kajiFont(size: 10, weight: .semibold)
                    .foregroundStyle(KajiTheme.fgMuted)
                    .lineLimit(1)
                if segment.speakerLabel != nil {
                    Text(sourceName)
                        .kajiFont(size: 10)
                        .foregroundStyle(KajiTheme.fgDim)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(segment.isFinal ? "Final" : "Live")
                    .kajiFont(size: 9, weight: .medium, design: .monospaced)
                    .foregroundStyle(segment.isFinal ? KajiTheme.fgDim : KajiTheme.accent)
            }
            Text(segment.text)
                .kajiFont(size: 12)
                .foregroundStyle(segment.isFinal ? KajiTheme.fg : KajiTheme.fgMuted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if let metadata {
                Text(provenance(metadata))
                    .kajiFont(size: 9, design: .monospaced)
                    .foregroundStyle(KajiTheme.fgDim)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KajiTheme.secondaryBackground.opacity(0.5), in: RoundedRectangle(cornerRadius: KajiShape.tileRadius))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private func provenance(_ metadata: MeetingCommittedTranscriptMetadata) -> String {
        var values = [metadata.providerID, metadata.modelID]
        if let language = metadata.language?.code { values.append(language) }
        return values.joined(separator: " · ")
    }

    private var accessibilityDescription: String {
        let time = MeetingNotesTimeFormatter.transcript(
            segment.startMilliseconds,
            relativeTo: captureStartMilliseconds
        )
        return "\(time), \(segment.speakerLabel ?? sourceName), \(segment.text)"
    }
}

private struct MeetingTranscriptTranscriptionGapRow: View {
    let gap: MeetingTranscriptionGap
    let sourceName: String
    let captureStartMilliseconds: Int64

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            KajiIcon(systemName: "exclamationmark.triangle", size: 11)
                .foregroundStyle(KajiTheme.diffHunkFg)
            VStack(alignment: .leading, spacing: 3) {
                Text("Transcription gap at \(relativeStartTime)")
                    .kajiFont(size: 11, weight: .semibold)
                    .foregroundStyle(KajiTheme.fg)
                Text("\(sourceName): \(gap.code) (\(gap.classification.rawValue)).")
                    .kajiFont(size: 10)
                    .foregroundStyle(KajiTheme.fgMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(KajiTheme.diffHunkBg.opacity(0.45), in: RoundedRectangle(cornerRadius: KajiShape.tileRadius))
    }

    private var relativeStartTime: String {
        MeetingNotesTimeFormatter.transcript(
            gap.startMilliseconds,
            relativeTo: captureStartMilliseconds
        )
    }
}

private struct MeetingTranscriptGapRow: View {
    let gap: MeetingRecordingGap
    let sourceName: String
    let captureStartMilliseconds: Int64

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            KajiIcon(systemName: "exclamationmark.triangle", size: 11)
                .foregroundStyle(KajiTheme.diffHunkFg)
            VStack(alignment: .leading, spacing: 3) {
                Text("Audio gap at \(relativeStartTime)")
                    .kajiFont(size: 11, weight: .semibold)
                    .foregroundStyle(KajiTheme.fg)
                Text("\(sourceName): \(gap.droppedBufferCount) buffers were unavailable (\(gap.reason)).")
                    .kajiFont(size: 10)
                    .foregroundStyle(KajiTheme.fgMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(KajiTheme.diffHunkBg.opacity(0.45), in: RoundedRectangle(cornerRadius: KajiShape.tileRadius))
        .overlay(RoundedRectangle(cornerRadius: KajiShape.tileRadius).stroke(KajiTheme.diffHunkFg.opacity(0.25), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var relativeStartTime: String {
        MeetingNotesTimeFormatter.transcript(gap.startMilliseconds, relativeTo: captureStartMilliseconds)
    }
}
