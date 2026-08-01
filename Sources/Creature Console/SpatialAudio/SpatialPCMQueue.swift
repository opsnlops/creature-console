#if os(macOS)
    import Synchronization

    /// A single-producer/single-consumer PCM queue. The audio render callback is the only
    /// consumer; the stage scheduler is the only producer. Atomic cursors publish writes
    /// without taking a lock on Core Audio's real-time thread.
    final class SpatialPCMQueue: @unchecked Sendable {
        private let storage: UnsafeMutablePointer<Float>
        private let capacity: Int64
        private let readPosition = Atomic<Int64>(0)
        private let writePosition = Atomic<Int64>(0)
        private let underrunCount = Atomic<UInt64>(0)

        init(capacity: Int) {
            precondition(capacity > 0)
            storage = .allocate(capacity: capacity)
            storage.initialize(repeating: 0, count: capacity)
            self.capacity = Int64(capacity)
        }

        deinit {
            storage.deinitialize(count: Int(capacity))
            storage.deallocate()
        }

        var availableFrames: Int {
            let read = readPosition.load(ordering: .acquiring)
            let write = writePosition.load(ordering: .acquiring)
            return Int(max(0, write - read))
        }

        var underruns: UInt64 {
            underrunCount.load(ordering: .relaxed)
        }

        func canWrite(frameCount: Int) -> Bool {
            guard frameCount >= 0 else {
                return false
            }
            let read = readPosition.load(ordering: .acquiring)
            let write = max(writePosition.load(ordering: .acquiring), read)
            return Int64(frameCount) <= capacity - (write - read)
        }

        @discardableResult
        func write(_ samples: UnsafeBufferPointer<Float>) -> Bool {
            let read = readPosition.load(ordering: .acquiring)
            var write = writePosition.load(ordering: .relaxed)
            if write < read {
                write = read
            }

            guard Int64(samples.count) <= capacity - (write - read) else {
                return false
            }

            copy(samples, toAbsolutePosition: write)
            writePosition.store(write + Int64(samples.count), ordering: .releasing)
            return true
        }

        @discardableResult
        func write(_ samples: [Float]) -> Bool {
            samples.withUnsafeBufferPointer { write($0) }
        }

        func clearAndPrime(silenceFrames: Int) {
            let read = readPosition.load(ordering: .acquiring)
            let primeCount = min(max(silenceFrames, 0), Int(capacity))
            fillWithZeros(fromAbsolutePosition: read, count: primeCount)
            writePosition.store(read + Int64(primeCount), ordering: .releasing)
            underrunCount.store(0, ordering: .relaxed)
        }

        func read(into destination: UnsafeMutablePointer<Float>, frameCount: Int) -> Bool {
            let read = readPosition.load(ordering: .relaxed)
            let write = writePosition.load(ordering: .acquiring)
            let available = Int(max(0, write - read))
            let copied = min(frameCount, available)

            copyFromStorage(
                atAbsolutePosition: read,
                into: destination,
                count: copied
            )
            if copied < frameCount {
                destination.advanced(by: copied).update(
                    repeating: 0,
                    count: frameCount - copied
                )
                underrunCount.wrappingAdd(1, ordering: .relaxed)
            }
            // Only consume frames that existed. The render callback may ask for a block that
            // straddles the producer's write edge; the silent tail must not skip future PCM.
            readPosition.store(read + Int64(copied), ordering: .releasing)
            return copied == 0
        }

        private func copy(
            _ samples: UnsafeBufferPointer<Float>,
            toAbsolutePosition position: Int64
        ) {
            let start = Int(position % capacity)
            let firstCount = min(samples.count, Int(capacity) - start)
            storage.advanced(by: start).update(
                from: samples.baseAddress!,
                count: firstCount
            )
            if firstCount < samples.count {
                storage.update(
                    from: samples.baseAddress!.advanced(by: firstCount),
                    count: samples.count - firstCount
                )
            }
        }

        private func copyFromStorage(
            atAbsolutePosition position: Int64,
            into destination: UnsafeMutablePointer<Float>,
            count: Int
        ) {
            guard count > 0 else {
                return
            }
            let start = Int(position % capacity)
            let firstCount = min(count, Int(capacity) - start)
            destination.update(from: storage.advanced(by: start), count: firstCount)
            if firstCount < count {
                destination.advanced(by: firstCount).update(
                    from: storage,
                    count: count - firstCount
                )
            }
        }

        private func fillWithZeros(fromAbsolutePosition position: Int64, count: Int) {
            guard count > 0 else {
                return
            }
            let start = Int(position % capacity)
            let firstCount = min(count, Int(capacity) - start)
            storage.advanced(by: start).update(repeating: 0, count: firstCount)
            if firstCount < count {
                storage.update(repeating: 0, count: count - firstCount)
            }
        }
    }
#endif
