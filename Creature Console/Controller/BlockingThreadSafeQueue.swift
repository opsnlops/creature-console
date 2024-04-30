import Foundation

class BlockingThreadSafeQueue<T> {
    private var queue: [T] = []
    private let accessQueue = DispatchQueue(label: "BlockingThreadSafeQueueAccess", attributes: .concurrent)
    private let semaphore = DispatchSemaphore(value: 0)
    private var isCancelled = false // Flag for cancellation state

    func enqueue(_ element: T) {
        accessQueue.async(flags: .barrier) {
            self.queue.append(element)
            self.semaphore.signal() // Signal to wake up any waiting dequeue
        }
    }

    func cancel() {
        accessQueue.async(flags: .barrier) {
            self.isCancelled = true // Set cancellation flag
            self.semaphore.signal() // Signal to wake up any waiting dequeue
        }
    }

    func dequeue() -> T? {
        semaphore.wait() // Block until semaphore is signaled

        if isCancelled {
            return nil // Return nil if cancellation flag is set
        }

        return accessQueue.sync {
            if !self.queue.isEmpty {
                return self.queue.removeFirst() // Return the first element
            }
            return nil // Return nil if queue is empty
        }
    }
}

