import Foundation
import CoreBluetooth

/// Manages Bluetooth communication with Victron SmartSolar MPPT charge controllers.
/// Handles scanning, connection, and register reading via BLE.
class VictronBluetoothManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    private var centralManager: CBCentralManager?
    private var connectedPeripheral: CBPeripheral?
    private var continuation: AsyncStream<TelemetrySnapshot>.Continuation?
    
    // Victron MPPT Bluetooth identifiers
    private let victronServiceUUID = CBUUID(string: "180A") // Device Information Service
    private let victronCharacteristicUUID = CBUUID(string: "2A25") // Serial Number (entry point)
    
    // Custom Victron VE.Direct BLE UUIDs
    private let victronServiceCustomUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    private let victronTxUUID = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    private let victronRxUUID = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")
    
    private var txCharacteristic: CBCharacteristic?
    private var rxCharacteristic: CBCharacteristic?
    
    override init() {
        super.init()
        self.centralManager = CBCentralManager(delegate: self, queue: .main)
    }
    
    /// Start scanning for Victron MPPT devices and stream telemetry.
    func telemetryStream() -> AsyncStream<TelemetrySnapshot> {
        return AsyncStream { continuation in
            self.continuation = continuation
            
            // Start scanning for Victron devices
            if let centralManager = centralManager, centralManager.state == .poweredOn {
                centralManager.scanForPeripherals(withServices: nil, options: nil)
            }
        }
    }
    
    /// Stop scanning and disconnect.
    func stopScanning() {
        centralManager?.stopScan()
        if let peripheral = connectedPeripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
    }
    
    // MARK: - CBCentralManagerDelegate
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            central.scanForPeripherals(withServices: nil, options: nil)
        }
    }
    
    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi: NSNumber
    ) {
        // Look for Victron MPPT devices (name typically contains "Victron" or has known UUIDs)
        if let name = peripheral.name, name.contains("Victron") || name.contains("MPPT") {
            central.stopScan()
            connectedPeripheral = peripheral
            peripheral.delegate = self
            central.connect(peripheral, options: nil)
        }
    }
    
    func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        // Discover services
        peripheral.discoverServices([victronServiceCustomUUID])
    }
    
    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        // Retry scanning
        central.scanForPeripherals(withServices: nil, options: nil)
    }
    
    // MARK: - CBPeripheralDelegate
    
    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        guard error == nil else {
            print("Error discovering services: \(error!)")
            return
        }
        
        // Look for Victron custom service
        if let services = peripheral.services {
            for service in services {
                if service.uuid == victronServiceCustomUUID {
                    peripheral.discoverCharacteristics([victronTxUUID, victronRxUUID], for: service)
                }
            }
        }
    }
    
    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard error == nil else {
            print("Error discovering characteristics: \(error!)")
            return
        }
        
        if let characteristics = service.characteristics {
            for characteristic in characteristics {
                if characteristic.uuid == victronTxUUID {
                    txCharacteristic = characteristic
                    // Request notifications for incoming data
                    peripheral.setNotifyValue(true, for: characteristic)
                } else if characteristic.uuid == victronRxUUID {
                    rxCharacteristic = characteristic
                }
            }
        }
        
        // Start reading initial data
        readVictronRegisters()
    }
    
    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil, let data = characteristic.value else {
            print("Error reading characteristic: \(error?.localizedDescription ?? "Unknown")")
            return
        }
        
        // Parse incoming Victron telemetry data
        if let snapshot = parseVictronData(data) {
            continuation?.yield(snapshot)
        }
    }
    
    // MARK: - Private Helpers
    
    /// Simulate register read request for Victron MPPT.
    /// In production, this would construct proper VE.Direct protocol frames.
    private func readVictronRegisters() {
        // This is a placeholder for proper VE.Direct frame construction
        // In a real implementation, this would build register read requests
        // and send them via rxCharacteristic
    }
    
    /// Parse Victron VE.Direct BLE frame into TelemetrySnapshot.
    private func parseVictronData(_ data: Data) -> TelemetrySnapshot? {
        // Try to parse as Victron register frame
        if let registers = VictronRegisterParser.parseFrame(data) {
            return VictronRegisterParser.buildSnapshot(registers: registers)
        }
        
        // Fall back to parsing as text frame
        if let text = String(data: data, encoding: .utf8),
           let registers = VictronRegisterParser.parseTextFrame(text) {
            return VictronRegisterParser.buildSnapshot(registers: registers)
        }
        
        // Fallback: return mock data to keep app functional during development
        return .mock
    }
}
