import Foundation

protocol BluetoothTelemetryService {
    func telemetryStream() -> AsyncStream<TelemetrySnapshot>
    func startScanning() async
    func stopScanning() async
}

final class VictronBluetoothTelemetryService: BluetoothTelemetryService {
    static let shared = VictronBluetoothTelemetryService()
    
    private(set) var isScanning = false
    private var victronManager: VictronBluetoothManager?
    private var mockTask: Task<Void, Never>?
    private var useMockData = true  // Toggle to switch between real and mock
    
    init() {
        // Initialize Victron manager for real device connection
        self.victronManager = VictronBluetoothManager()
    }
    
    func telemetryStream() -> AsyncStream<TelemetrySnapshot> {
        // Use real Victron data if device is available, otherwise fall back to mock
        if useMockData {
            return mockTelemetryStream()
        } else {
            return realTelemetryStream()
        }
    }
    
    /// Stream real telemetry from Victron SmartSolar MPPT via Bluetooth.
    private func realTelemetryStream() -> AsyncStream<TelemetrySnapshot> {
        guard let manager = victronManager else {
            return mockTelemetryStream()
        }
        
        return AsyncStream { continuation in
            self.isScanning = true
            
            // Create a task that continuously yields Victron data
            let task = Task {
                for await snapshot in manager.telemetryStream() {
                    continuation.yield(snapshot)
                }
            }
            
            // On cleanup, cancel the stream
            continuation.onTermination = { _ in
                task.cancel()
                manager.stopScanning()
                self.isScanning = false
            }
        }
    }
    
    /// Mock telemetry stream for testing/demo purposes.
    private func mockTelemetryStream() -> AsyncStream<TelemetrySnapshot> {
        return AsyncStream { continuation in
            self.isScanning = true
            
            self.mockTask = Task {
                let snapshots = [
                    TelemetrySnapshot.mock,
                    TelemetrySnapshot.driveMock
                ]
                
                var index = 0
                while !Task.isCancelled {
                    let snapshot = snapshots[index % snapshots.count]
                    continuation.yield(snapshot)
                    index += 1
                    
                    try? await Task.sleep(for: .seconds(3))
                }
                
                continuation.finish()
            }
        }
    }
    
    func startScanning() async {
        isScanning = true
        // Victron manager will start scanning when telemetryStream() is consumed
    }
    
    func stopScanning() async {
        isScanning = false
        mockTask?.cancel()
        mockTask = nil
        victronManager?.stopScanning()
    }
    
    /// Switch between mock and real data sources for testing.
    func setMockDataEnabled(_ enabled: Bool) {
        useMockData = enabled
    }
}

// MARK: - Backward Compatibility Alias
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
