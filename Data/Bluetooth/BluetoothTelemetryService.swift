import Foundation

protocol BluetoothTelemetryService {
    func telemetryStream() -> AsyncStream<TelemetrySnapshot>
    func startScanning() async
    func stopScanning() async
}

final class MockBluetoothTelemetryService: BluetoothTelemetryService {
    private var continuation: AsyncStream<TelemetrySnapshot>.Continuation?
    private var timer: Task<Void, Never>?

    func telemetryStream() -> AsyncStream<TelemetrySnapshot> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.yield(.mock)
        }
    }

    func startScanning() async {
        guard timer == nil else { return }

        timer = Task {
            var toggle = false
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                toggle.toggle()
                continuation?.yield(toggle ? .driveMock : .mock)
            }
        }
    }

    func stopScanning() async {
        timer?.cancel()
        timer = nil
    }
}
