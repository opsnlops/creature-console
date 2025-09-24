import Foundation

public actor BlockingThreadSafeQueue<Element: Sendable> {
    private var buffer: [Element] = []
    private var waiters: [CheckedContinuation<Element?, Never>] = []
    private var isCancelled = false

    public init() {}

    // Enqueue an element. If a waiter is pending, resume it immediately; otherwise buffer.
    public func enqueue(_ element: Element) {
        guard !isCancelled else { return }
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume(returning: element)
        } else {
            buffer.append(element)
        }
    }

    // Cancel the queue: unblocks all pending and future dequeues with nil.
    public func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume(returning: nil)
        }
    }

    // Dequeue the next element, suspending until available. Returns nil if the queue is cancelled.
    public func dequeue() async -> Element? {
        if !buffer.isEmpty {
            return buffer.removeFirst()
        }
        if isCancelled {
            return nil
        }
        return await withCheckedContinuation { (continuation: CheckedContinuation<Element?, Never>) in
            waiters.append(continuation)
        }
    }
}
