import Foundation
import CoreBluetooth

/// Manages Bluetooth communication with Victron SmartSolar MPPT charge controllers.
/// Handles scanning, connection, and register reading via BLE.
class VictronBluetoothManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    enum ConnectionState {
        case idle
        case scanning
        case connecting
        case connected
        case disconnected(Error?)
    }
    
    private var centralManager: CBCentralManager?
    private var connectedPeripheral: CBPeripheral?
    private var continuation: AsyncStream<TelemetrySnapshot>.Continuation?
    private var onTerminate: (() -> Void)?
    var onConnectionStateChange: ((ConnectionState) -> Void)?
    
    // Custom Victron VE.Direct BLE UUIDs
    private let victronServiceCustomUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    private let victronTxUUID = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    private let victronRxUUID = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")
    
    private var txCharacteristic: CBCharacteristic?
    private var rxCharacteristic: CBCharacteristic?
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5
    private var scanTimeoutTask: Task<Void, Never>?
    private var noDataTimeoutTask: Task<Void, Never>?
    private var textBuffer = ""
    private var hasReceivedDataSinceConnect = false
    
    override init() {
        super.init()
        self.centralManager = CBCentralManager(delegate: self, queue: .main)
    }
    
    /// Start scanning for Victron MPPT devices and stream telemetry.
    func telemetryStream() -> AsyncStream<TelemetrySnapshot> {
        return AsyncStream { continuation in
            self.continuation = continuation
            self.onTerminate = { continuation.finish() }
            
            // Start scanning for Victron devices
            if let centralManager = centralManager, centralManager.state == .poweredOn {
                startScan(on: centralManager)
            }

            continuation.onTermination = { _ in
                self.stopScanning()
            }
        }
    }
    
    /// Stop scanning and disconnect.
    func stopScanning() {
        centralManager?.stopScan()
        scanTimeoutTask?.cancel()
        scanTimeoutTask = nil
        noDataTimeoutTask?.cancel()
        noDataTimeoutTask = nil
        if let peripheral = connectedPeripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        connectedPeripheral = nil
        txCharacteristic = nil
        rxCharacteristic = nil
        hasReceivedDataSinceConnect = false
        onConnectionStateChange?(.idle)
    }
    
    // MARK: - CBCentralManagerDelegate
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn, continuation != nil {
            startScan(on: central)
        } else if central.state != .poweredOn {
            onConnectionStateChange?(.disconnected(nil))
        }
    }
    
    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi: NSNumber
    ) {
        // Look for Victron MPPT devices (name typically contains "Victron" or has known UUIDs)
        // Match known Victron device name prefixes (SmartSolar, MPPT, BlueSolar, VE.Direct, Victron)
        if let name = peripheral.name,
           name.localizedCaseInsensitiveContains("Victron") ||
           name.localizedCaseInsensitiveContains("MPPT") ||
           name.localizedCaseInsensitiveContains("SmartSolar") ||
           name.localizedCaseInsensitiveContains("BlueSolar") ||
           name.localizedCaseInsensitiveContains("VE.Direct") {
            central.stopScan()
            scanTimeoutTask?.cancel()
            scanTimeoutTask = nil
            connectedPeripheral = peripheral
            peripheral.delegate = self
            onConnectionStateChange?(.connecting)
            central.connect(peripheral, options: nil)
        }
    }
    
    func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        reconnectAttempts = 0
        hasReceivedDataSinceConnect = false
        onConnectionStateChange?(.connected)
        // Discover all services for maximum compatibility across Victron firmware variants.
        peripheral.discoverServices(nil)
        scheduleNoDataTimeout(for: peripheral, on: central)
    }
    
    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        onConnectionStateChange?(.disconnected(error))
        retryOrRescan(on: central)
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        onConnectionStateChange?(.disconnected(error))
        noDataTimeoutTask?.cancel()
        noDataTimeoutTask = nil
        hasReceivedDataSinceConnect = false
        connectedPeripheral = nil
        txCharacteristic = nil
        rxCharacteristic = nil
        retryOrRescan(on: central)
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
        
        // Discover characteristics on all services. Some devices expose telemetry on unexpected UUIDs.
        if let services = peripheral.services {
            for service in services {
                if service.uuid == victronServiceCustomUUID {
                    peripheral.discoverCharacteristics([victronTxUUID, victronRxUUID], for: service)
                } else {
                    peripheral.discoverCharacteristics(nil, for: service)
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
                    peripheral.setNotifyValue(true, for: characteristic)
                } else {
                    // Fallback: subscribe/read any characteristic that can provide telemetry.
                    if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
                        peripheral.setNotifyValue(true, for: characteristic)
                    }
                    if characteristic.properties.contains(.read) {
                        peripheral.readValue(for: characteristic)
                    }
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
            hasReceivedDataSinceConnect = true
            noDataTimeoutTask?.cancel()
            noDataTimeoutTask = nil
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
        if let text = String(data: data, encoding: .utf8) {
            textBuffer.append(text)
            if textBuffer.count > 4096 {
                textBuffer.removeFirst(textBuffer.count - 4096)
            }

            let lines = textBuffer.components(separatedBy: "\n")
            if lines.count > 1 {
                textBuffer = lines.last ?? ""
                let completeBlock = lines.dropLast().joined(separator: "\n")
                if let registers = VictronRegisterParser.parseTextFrame(completeBlock) {
                    return VictronRegisterParser.buildSnapshot(registers: registers)
                }
            }
        }
        
        return nil
    }

    private func startScan(on central: CBCentralManager) {
        onConnectionStateChange?(.scanning)
        // Scan without UUID filter so Victron devices are discoverable regardless of firmware version.
        // Some MPPT models don't advertise the custom service UUID until connected.
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        scanTimeoutTask?.cancel()
        scanTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self else { return }
            if self.connectedPeripheral == nil {
                central.stopScan()
                self.startScan(on: central)
            }
        }
    }

    private func retryOrRescan(on central: CBCentralManager) {
        reconnectAttempts += 1
        guard reconnectAttempts <= maxReconnectAttempts else {
            reconnectAttempts = 0
            startScan(on: central)
            return
        }

        if let peripheral = connectedPeripheral {
            central.connect(peripheral, options: nil)
        } else {
            startScan(on: central)
        }
    }

    private func scheduleNoDataTimeout(for peripheral: CBPeripheral, on central: CBCentralManager) {
        noDataTimeoutTask?.cancel()
        noDataTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard let self else { return }
            guard self.connectedPeripheral?.identifier == peripheral.identifier else { return }
            guard !self.hasReceivedDataSinceConnect else { return }
            central.cancelPeripheralConnection(peripheral)
        }
    }
}
