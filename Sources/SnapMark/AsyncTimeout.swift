import Foundation

enum AsyncTimeout {
    static func run<T>(
        seconds: TimeInterval,
        timeoutError: Error,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        let race = AsyncTimeoutRace<T>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                race.start(
                    continuation: continuation,
                    seconds: seconds,
                    timeoutError: timeoutError,
                    operation: operation
                )
            }
        } onCancel: {
            race.cancel()
        }
    }
}

private final class AsyncTimeoutRace<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var terminalResult: Result<T, Error>?
    private var operationTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?

    func start(
        continuation: CheckedContinuation<T, Error>,
        seconds: TimeInterval,
        timeoutError: Error,
        operation: @escaping () async throws -> T
    ) {
        lock.lock()
        if let terminalResult {
            lock.unlock()
            continuation.resume(with: terminalResult)
            return
        }
        self.continuation = continuation
        lock.unlock()

        let operationTask = Task { [weak self] in
            do {
                self?.finish(.success(try await operation()))
            } catch {
                self?.finish(.failure(error))
            }
        }
        store(operationTask: operationTask)

        let timerTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(max(0.01, seconds) * 1_000_000_000))
            } catch {
                return
            }
            self?.finish(.failure(timeoutError))
        }
        store(timerTask: timerTask)
    }

    func cancel() {
        finish(.failure(CancellationError()))
    }

    private func finish(_ result: Result<T, Error>) {
        lock.lock()
        guard terminalResult == nil else {
            lock.unlock()
            return
        }
        terminalResult = result
        let continuation = self.continuation
        self.continuation = nil
        let operationTask = self.operationTask
        let timerTask = self.timerTask
        lock.unlock()

        operationTask?.cancel()
        timerTask?.cancel()
        continuation?.resume(with: result)
    }

    private func store(operationTask: Task<Void, Never>) {
        lock.lock()
        self.operationTask = operationTask
        let alreadyFinished = terminalResult != nil
        lock.unlock()
        if alreadyFinished { operationTask.cancel() }
    }

    private func store(timerTask: Task<Void, Never>) {
        lock.lock()
        self.timerTask = timerTask
        let alreadyFinished = terminalResult != nil
        lock.unlock()
        if alreadyFinished { timerTask.cancel() }
    }
}
