import Foundation

protocol BluetoothTelemetryService {
    func startScanning() async
    func stopScanning() async
}

final class MockBluetoothTelemetryService: BluetoothTelemetryService {
    func startScanning() async {
        // Placeholder for CoreBluetooth scanner integration.
    }

    func stopScanning() async {
        // Placeholder for CoreBluetooth scanner integration.
    }
}
