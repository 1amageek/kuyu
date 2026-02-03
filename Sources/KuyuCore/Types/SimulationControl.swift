import Foundation

public actor SimulationControl {
    private var paused = false
    private var stopped = false

    public init() {}

    public func requestPause() {
        paused = true
    }

    public func requestResume() {
        paused = false
    }

    public func togglePause() {
        paused.toggle()
    }

    public func requestStop() {
        stopped = true
    }

    public func reset() {
        paused = false
        stopped = false
    }

    public func isPaused() -> Bool {
        paused
    }

    public func isStopped() -> Bool {
        stopped
    }

    public func checkpoint() async throws {
        if stopped {
            throw CancellationError()
        }
        while paused {
            if stopped {
                throw CancellationError()
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        if stopped {
            throw CancellationError()
        }
    }
}
