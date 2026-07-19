import Foundation
import Testing

@testable import Kaji

@Suite("Meeting audio event queue", .serialized)
struct MeetingAudioEventQueueTests {
    @Test("all queued event types remain bounded while a consumer is stalled")
    func boundedQueue() async throws {
        let queue = try MeetingAudioEventQueue(audioCapacity: 8)
        for sequence in 0 ..< 5_000 {
            await queue.enqueue(try MeetingAudioTestFixtures.buffer(sequenceNumber: Int64(sequence)))
        }
        await queue.finish()

        let metrics = await queue.metrics()
        var events: [MeetingAudioQueueEvent] = []
        while let event = try await queue.next() {
            events.append(event)
        }
        let retainedSequences = events.compactMap { event -> Int64? in
            guard case let .audio(buffer) = event else { return nil }
            return buffer.sequenceNumber
        }
        let gaps = events.compactMap { event -> MeetingAudioGap? in
            guard case let .gap(gap) = event else { return nil }
            return gap
        }

        #expect(metrics.peakRetainedEventCount <= 8)
        #expect(metrics.retainedEventCount <= 8)
        #expect(events.count <= 8)
        #expect(retainedSequences == retainedSequences.sorted())
        #expect(gaps.count == 1)
        #expect(gaps[0].firstSequenceNumber <= 7)
        #expect(gaps[0].lastSequenceNumber == 4_999)
        #expect(gaps[0].droppedBufferCount >= 4_992)
    }

    @Test("repeated failures coalesce within the event capacity")
    func coalescedFailures() async throws {
        let queue = try MeetingAudioEventQueue(audioCapacity: 2)
        let failure = MeetingAudioCaptureFailure(domain: "capture", code: 7, message: "failed")
        for _ in 0 ..< 5_000 {
            await queue.enqueueFailure(failure)
        }
        await queue.finish()

        guard case let .failure(retained) = try await queue.next() else {
            Issue.record("Expected a coalesced failure")
            return
        }
        #expect(retained.occurrenceCount == 5_000)
        #expect(try await queue.next() == nil)
        #expect(await queue.metrics().peakRetainedEventCount == 1)
    }

    @Test("concurrent callback submissions retain bounded state and preserve accepted order")
    func concurrentIngress() async throws {
        let queue = try MeetingAudioEventQueue(audioCapacity: 10_000)
        let ingress = try MeetingAudioQueueIngress(queue: queue, pendingEventCapacity: 32)
        let firstSource = try MeetingAudioTestFixtures.source()
        let secondSource = try MeetingAudioTestFixtures.source(
            id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            kind: .systemAudio
        )
        var buffers: [(Int64, MeetingOwnedAudioBuffer)] = []
        for index in 0 ..< 5_000 {
            let sequence = Int64(index)
            let source = index.isMultiple(of: 2) ? firstSource : secondSource
            buffers.append((sequence, try MeetingAudioTestFixtures.buffer(
                sequenceNumber: sequence,
                source: source
            )))
        }
        var submissions: [(Int64, MeetingAudioIngressSubmission)] = []
        await withTaskGroup(of: (Int64, MeetingAudioIngressSubmission).self) { group in
            for (sequence, buffer) in buffers {
                group.addTask {
                    (sequence, ingress.submit(buffer))
                }
            }
            for await submission in group {
                submissions.append(submission)
            }
        }
        await ingress.finish()

        var retainedSequences: [Int64] = []
        var gapCount = 0
        while let event = try await queue.next() {
            switch event {
            case let .audio(buffer):
                retainedSequences.append(buffer.sequenceNumber)
            case .gap:
                gapCount += 1
            case .failure:
                break
            }
        }
        let expectedSequences = submissions
            .filter { $0.1.disposition == .accepted }
            .sorted { $0.1.submissionNumber! < $1.1.submissionNumber! }
            .map(\.0)
        let metrics = ingress.metrics()

        #expect(metrics.peakRetainedEventCount <= 32)
        #expect(metrics.peakRetainedAudioBufferCount <= 28)
        #expect(metrics.drainTaskCount == 1)
        #expect(retainedSequences == expectedSequences)
        #expect(submissions.contains { $0.1.disposition == .dropped })
        #expect(gapCount > 0)
    }

    @Test("finish closes admission after draining every accepted submission")
    func finishVersusSubmit() async throws {
        let queue = try MeetingAudioEventQueue(audioCapacity: 4_000)
        let ingress = try MeetingAudioQueueIngress(queue: queue, pendingEventCapacity: 24)
        var buffers: [(Int64, MeetingOwnedAudioBuffer)] = []
        for sequence in 0 ..< 2_000 {
            let value = Int64(sequence)
            buffers.append((value, try MeetingAudioTestFixtures.buffer(sequenceNumber: value)))
        }
        var submissions: [(Int64, MeetingAudioIngressSubmission)] = []
        let finisher = Task {
            await Task.yield()
            await ingress.finish()
        }
        await withTaskGroup(of: (Int64, MeetingAudioIngressSubmission).self) { group in
            for (value, buffer) in buffers {
                group.addTask { (value, ingress.submit(buffer)) }
            }
            for await submission in group {
                submissions.append(submission)
            }
        }
        await finisher.value

        let postFinish = ingress.submit(try MeetingAudioTestFixtures.buffer(sequenceNumber: 2_001))
        var retainedSequences: [Int64] = []
        var gapSequences = Set<Int64>()
        while let event = try await queue.next() {
            switch event {
            case let .audio(buffer):
                retainedSequences.append(buffer.sequenceNumber)
            case let .gap(gap):
                gapSequences.formUnion(gap.firstSequenceNumber ... gap.lastSequenceNumber)
            case .failure:
                break
            }
        }
        let expectedSequences = submissions
            .filter { $0.1.disposition == .accepted }
            .sorted { $0.1.submissionNumber! < $1.1.submissionNumber! }
            .map(\.0)

        #expect(postFinish.disposition == .closed)
        #expect(retainedSequences.allSatisfy { expectedSequences.contains($0) })
        #expect(Set(expectedSequences).isSubset(of: Set(retainedSequences).union(gapSequences)))
    }

    @Test("two saturated sources account for every missing audio sequence with gaps")
    func twoSourceSaturationAccountsForDrops() async throws {
        let queue = try MeetingAudioEventQueue(audioCapacity: 4)
        let ingress = try MeetingAudioQueueIngress(queue: queue, pendingEventCapacity: 4)
        let firstSource = try MeetingAudioTestFixtures.source()
        let secondSource = try MeetingAudioTestFixtures.source(
            id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            kind: .systemAudio
        )
        let sources = [firstSource, secondSource]
        for sequence in 0 ..< 10_000 {
            let source = sources[sequence.isMultiple(of: 2) ? 0 : 1]
            ingress.submit(try MeetingAudioTestFixtures.buffer(
                sequenceNumber: Int64(sequence / 2),
                source: source
            ))
        }
        await ingress.finish()

        var retained: [UUID: Set<Int64>] = [:]
        var covered: [UUID: Set<Int64>] = [:]
        while let event = try await queue.next() {
            switch event {
            case let .audio(buffer):
                retained[buffer.source.trackID, default: []].insert(buffer.sequenceNumber)
            case let .gap(gap):
                covered[gap.source.trackID, default: []].formUnion(
                    gap.firstSequenceNumber ... gap.lastSequenceNumber
                )
            case .failure:
                break
            }
        }

        for source in sources {
            let expected = Set(Int64(0) ..< Int64(5_000))
            let missing = expected.subtracting(retained[source.trackID, default: []])
            #expect(missing.isSubset(of: covered[source.trackID, default: []]))
        }
    }

    @Test("cancel promptly releases retained buffers and closes admission")
    func promptCancel() async throws {
        let queue = try MeetingAudioEventQueue(audioCapacity: 64)
        let ingress = try MeetingAudioQueueIngress(queue: queue, pendingEventCapacity: 64)
        for sequence in 0 ..< 5_000 {
            ingress.submit(try MeetingAudioTestFixtures.buffer(sequenceNumber: Int64(sequence)))
        }
        let clock = ContinuousClock()
        let start = clock.now

        await ingress.cancel()

        #expect(start.duration(to: clock.now) < .seconds(1))
        #expect(ingress.metrics().retainedEventCount == 0)
        #expect(ingress.submit(try MeetingAudioTestFixtures.buffer(sequenceNumber: 5_001)).disposition == .closed)
        #expect(try await queue.next() == nil)
    }

    @Test("a suspended consumer exits with cancellation")
    func cancellation() async throws {
        let queue = try MeetingAudioEventQueue(audioCapacity: 1)
        let consumer = Task { try await queue.next() }
        await Task.yield()
        consumer.cancel()
        var wasCancelled = false
        do {
            _ = try await consumer.value
        } catch is CancellationError {
            wasCancelled = true
        }

        #expect(wasCancelled)
    }
}
