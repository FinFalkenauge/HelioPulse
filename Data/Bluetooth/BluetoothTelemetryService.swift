import Foundation

protocol BluetoothTelemetryService: AnyObject {
    var onConnectionStateText: ((String) -> Void)? { get set }
    var onHistoryPayload: ((VictronHistoryPayload) -> Void)? { get set }
    var isMockDataEnabled: Bool { get }
    func telemetryStream() -> AsyncStream<TelemetrySnapshot>
    func startScanning() async
    func stopScanning() async
}

final class VictronBluetoothTelemetryService: BluetoothTelemetryService {
    static let shared = VictronBluetoothTelemetryService()
    
    private(set) var isScanning = false
    private var victronManager: VictronBluetoothManager?
    private var mockTask: Task<Void, Never>?
    private var useMockData = false  // Real Victron telemetry is default for TestFlight
    var onConnectionStateText: ((String) -> Void)?
    var onHistoryPayload: ((VictronHistoryPayload) -> Void)?
    var isMockDataEnabled: Bool { useMockData }
    
    init() {
        // Delay Bluetooth manager setup until scanning starts to reduce launch-time overhead.
    }
    
    func telemetryStream() -> AsyncStream<TelemetrySnapshot> {
        // Real Victron data is default; mock mode is opt-in only.
        if useMockData {
            return mockTelemetryStream()
        } else {
            return realTelemetryStream()
        }
    }
    
    /// Stream real telemetry from Victron SmartSolar MPPT via Bluetooth.
    private func realTelemetryStream() -> AsyncStream<TelemetrySnapshot> {
        let manager = ensureVictronManager()
        
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
        _ = ensureVictronManager()
        isScanning = true
        onConnectionStateText?("Bluetooth: Suche nach Victron Regler …")
        // Victron manager will start scanning when telemetryStream() is consumed
    }
    
    func stopScanning() async {
        isScanning = false
        mockTask?.cancel()
        mockTask = nil
        victronManager?.stopScanning()
        onConnectionStateText?("Bluetooth: Nicht verbunden")
    }
    
    /// Switch between mock and real data sources for testing.
    func setMockDataEnabled(_ enabled: Bool) {
        useMockData = enabled
        onConnectionStateText?(enabled ? "Bluetooth: Demo-Modus aktiv" : "Bluetooth: Suche nach Victron Regler …")
    }

    private func ensureVictronManager() -> VictronBluetoothManager {
        if let existing = victronManager {
            return existing
        }

        let manager = VictronBluetoothManager()
        manager.onConnectionStateChange = { [weak self] state in
            switch state {
            case .idle:
                self?.isScanning = false
                self?.onConnectionStateText?("Bluetooth: Inaktiv")
            case .scanning:
                self?.isScanning = true
                self?.onConnectionStateText?("Bluetooth: Suche nach Victron Regler …")
            case .connecting:
                self?.isScanning = true
                self?.onConnectionStateText?("Bluetooth: Verbinde …")
            case .connected:
                self?.isScanning = false
                self?.onConnectionStateText?("Bluetooth: Verbunden, warte auf vollständige Live-Telemetrie …")
            case .disconnected:
                self?.isScanning = true
                self?.onConnectionStateText?("Bluetooth: Verbindung verloren")
            }
        }
        manager.onHistoryPayload = { [weak self] payload in
            self?.onHistoryPayload?(payload)
        }
        victronManager = manager
        return manager
    }
}

// MARK: - Backward Compatibility Alias
final class MockBluetoothTelemetryService: BluetoothTelemetryService {
    private var continuation: AsyncStream<TelemetrySnapshot>.Continuation?
    private var timer: Task<Void, Never>?
    var onConnectionStateText: ((String) -> Void)?
    var onHistoryPayload: ((VictronHistoryPayload) -> Void)?
    var isMockDataEnabled: Bool { true }

    func telemetryStream() -> AsyncStream<TelemetrySnapshot> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.yield(.mock)
        }
    }

    func startScanning() async {
        guard timer == nil else { return }
        onConnectionStateText?("Bluetooth: Demo-Modus aktiv")

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
        onConnectionStateText?("Bluetooth: Inaktiv")
    }
}
