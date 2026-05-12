import Foundation
import CoreBluetooth
import OSLog

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
    private var readPollTask: Task<Void, Never>?
    private var readableCharacteristics: [CBCharacteristic] = []
    private var textBuffer = ""
    private var hasReceivedAnyPayloadSinceConnect = false
    private var hasReceivedTelemetrySinceConnect = false
    private var payloadPreviewCount = 0
    private var parseMissCount = 0
    private let logger = Logger(subsystem: "com.heliopulse.app", category: "BLE")
    
    override init() {
        super.init()
        self.centralManager = CBCentralManager(delegate: self, queue: .main)
        logger.notice("VictronBluetoothManager initialized")
    }
    
    /// Start scanning for Victron MPPT devices and stream telemetry.
    func telemetryStream() -> AsyncStream<TelemetrySnapshot> {
        return AsyncStream { continuation in
            self.continuation = continuation
            self.onTerminate = { continuation.finish() }
            self.logger.notice("Telemetry stream opened")
            
            // Start scanning for Victron devices
            if let centralManager = centralManager, centralManager.state == .poweredOn {
                startScan(on: centralManager)
            }

            continuation.onTermination = { _ in
                self.logger.notice("Telemetry stream terminated")
                self.stopScanning()
            }
        }
    }
    
    /// Stop scanning and disconnect.
    func stopScanning() {
        logger.notice("Stop scanning/disconnect requested")
        centralManager?.stopScan()
        scanTimeoutTask?.cancel()
        scanTimeoutTask = nil
        noDataTimeoutTask?.cancel()
        noDataTimeoutTask = nil
        readPollTask?.cancel()
        readPollTask = nil
        if let peripheral = connectedPeripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        connectedPeripheral = nil
        txCharacteristic = nil
        rxCharacteristic = nil
        readableCharacteristics.removeAll()
        hasReceivedAnyPayloadSinceConnect = false
        hasReceivedTelemetrySinceConnect = false
        payloadPreviewCount = 0
        parseMissCount = 0
        onConnectionStateChange?(.idle)
    }
    
    // MARK: - CBCentralManagerDelegate
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        logger.notice("Central state changed: \(self.describe(state: central.state), privacy: .public)")
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
        let discoveredName = peripheral.name ?? "<unknown>"
        logger.debug("Discovered peripheral name=\(discoveredName, privacy: .public) rssi=\(rssi.intValue)")
        if let name = peripheral.name,
           name.localizedCaseInsensitiveContains("Victron") ||
           name.localizedCaseInsensitiveContains("MPPT") ||
           name.localizedCaseInsensitiveContains("SmartSolar") ||
           name.localizedCaseInsensitiveContains("BlueSolar") ||
           name.localizedCaseInsensitiveContains("VE.Direct") {
            logger.notice("Selected peripheral \(name, privacy: .public) id=\(peripheral.identifier.uuidString, privacy: .public)")
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
        hasReceivedAnyPayloadSinceConnect = false
        hasReceivedTelemetrySinceConnect = false
        readableCharacteristics.removeAll()
        logger.notice("Connected to peripheral \(peripheral.identifier.uuidString, privacy: .public)")
        onConnectionStateChange?(.connected)
        // Discover all services for maximum compatibility across Victron firmware variants.
        peripheral.discoverServices(nil)
        scheduleNoDataTimeout(for: peripheral, on: central)
        startReadPolling(for: peripheral)
    }
    
    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        logger.error("Failed to connect: \(error?.localizedDescription ?? "unknown", privacy: .public)")
        onConnectionStateChange?(.disconnected(error))
        retryOrRescan(on: central)
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        logger.warning("Disconnected from peripheral \(peripheral.identifier.uuidString, privacy: .public) reason=\(error?.localizedDescription ?? "none", privacy: .public)")
        onConnectionStateChange?(.disconnected(error))
        noDataTimeoutTask?.cancel()
        noDataTimeoutTask = nil
        readPollTask?.cancel()
        readPollTask = nil
        hasReceivedAnyPayloadSinceConnect = false
        hasReceivedTelemetrySinceConnect = false
        connectedPeripheral = nil
        txCharacteristic = nil
        rxCharacteristic = nil
        readableCharacteristics.removeAll()
        retryOrRescan(on: central)
    }
    
    // MARK: - CBPeripheralDelegate
    
    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        guard error == nil else {
            logger.error("Service discovery error: \(error!.localizedDescription, privacy: .public)")
            return
        }
        logger.notice("Services discovered count=\(peripheral.services?.count ?? 0)")
        
        // Discover characteristics on all services. Some devices expose telemetry on unexpected UUIDs.
        if let services = peripheral.services {
            for service in services {
                logger.debug("Discovering characteristics service=\(service.uuid.uuidString, privacy: .public)")
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
            logger.error("Characteristic discovery error for service=\(service.uuid.uuidString, privacy: .public): \(error!.localizedDescription, privacy: .public)")
            return
        }
        logger.notice("Characteristics discovered service=\(service.uuid.uuidString, privacy: .public) count=\(service.characteristics?.count ?? 0)")
        
        if let characteristics = service.characteristics {
            for characteristic in characteristics {
                logger.debug("Characteristic uuid=\(characteristic.uuid.uuidString, privacy: .public) props=\(characteristic.properties.rawValue)")
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
                        readableCharacteristics.append(characteristic)
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
            logger.error("Read/update error characteristic=\(characteristic.uuid.uuidString, privacy: .public): \(error?.localizedDescription ?? "unknown", privacy: .public)")
            return
        }

        hasReceivedAnyPayloadSinceConnect = true
        noDataTimeoutTask?.cancel()
        noDataTimeoutTask = nil

        self.payloadPreviewCount += 1
        if self.payloadPreviewCount <= 8 || self.payloadPreviewCount % 50 == 0 {
            let preview = self.payloadPreview(for: data)
            let hex = self.hexPreview(for: data)
            logger.debug("Payload #\(self.payloadPreviewCount) char=\(characteristic.uuid.uuidString, privacy: .public) bytes=\(data.count) ascii=\(preview, privacy: .public) hex=\(hex, privacy: .public)")
        }
        
        // Parse incoming Victron telemetry data
        if let snapshot = parseVictronData(data) {
            hasReceivedTelemetrySinceConnect = true
            self.parseMissCount = 0
            logger.notice("Telemetry parsed solarW=\(Int(snapshot.solarPower)) battV=\(String(format: "%.2f", snapshot.batteryVoltage), privacy: .public) loadA=\(String(format: "%.2f", snapshot.loadCurrent), privacy: .public)")
            continuation?.yield(snapshot)
        } else {
            self.parseMissCount += 1
            if self.parseMissCount <= 6 || self.parseMissCount % 25 == 0 {
                logger.debug("Payload parse miss count=\(self.parseMissCount)")
            }
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
            return VictronRegisterParser.buildBinarySnapshot(registers: registers)
        }
        
        // Fall back to parsing as text frame
        let rawText = String(data: data, encoding: .utf8) ?? sanitizedASCIIString(from: data)
        if !rawText.isEmpty {
            textBuffer.append(rawText)
            if textBuffer.count > 4096 {
                textBuffer.removeFirst(textBuffer.count - 4096)
            }

            if let registers = VictronRegisterParser.parseTextFrame(rawText) {
                return VictronRegisterParser.buildTextSnapshot(registers: registers)
            }

            let parts = textBuffer.components(separatedBy: .newlines)
            if parts.count > 1 {
                textBuffer = parts.last ?? ""
                let completeBlock = parts.dropLast().joined(separator: "\n")
                if let registers = VictronRegisterParser.parseTextFrame(completeBlock) {
                    return VictronRegisterParser.buildTextSnapshot(registers: registers)
                }
            }

            if let registers = VictronRegisterParser.parseLooseTextFrame(rawText) {
                return VictronRegisterParser.buildTextSnapshot(registers: registers)
            }

            // Some VE.Direct payloads terminate with "Checksum". Parse eagerly when detected.
            if textBuffer.localizedCaseInsensitiveContains("CHECKSUM"),
               let registers = VictronRegisterParser.parseTextFrame(textBuffer) {
                textBuffer.removeAll(keepingCapacity: true)
                return VictronRegisterParser.buildTextSnapshot(registers: registers)
            }
        }
        
        return nil
    }

    private func sanitizedASCIIString(from data: Data) -> String {
        let mapped = data.map { byte -> Character in
            switch byte {
            case 9, 10, 13:
                return Character(UnicodeScalar(byte))
            case 32...126:
                return Character(UnicodeScalar(byte))
            default:
                return " "
            }
        }
        return String(mapped)
    }

    private func startScan(on central: CBCentralManager) {
        logger.notice("Start scanning for Victron peripherals")
        onConnectionStateChange?(.scanning)
        // Scan without UUID filter so Victron devices are discoverable regardless of firmware version.
        // Some MPPT models don't advertise the custom service UUID until connected.
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        scanTimeoutTask?.cancel()
        scanTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self else { return }
            if self.connectedPeripheral == nil {
                self.logger.warning("Scan timeout reached, restarting scan")
                central.stopScan()
                self.startScan(on: central)
            }
        }
    }

    private func retryOrRescan(on central: CBCentralManager) {
        self.reconnectAttempts += 1
        logger.notice("Retry/rescan attempt=\(self.reconnectAttempts)")
        guard self.reconnectAttempts <= maxReconnectAttempts else {
            self.reconnectAttempts = 0
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
            guard !self.hasReceivedAnyPayloadSinceConnect else { return }
            self.logger.warning("No raw payloads within timeout; forcing reconnect")
            central.cancelPeripheralConnection(peripheral)
        }
    }

    private func startReadPolling(for peripheral: CBPeripheral) {
        readPollTask?.cancel()
        readPollTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard self.connectedPeripheral?.identifier == peripheral.identifier else { continue }
                if !self.readableCharacteristics.isEmpty {
                    self.logger.debug("Polling readable characteristics count=\(self.readableCharacteristics.count)")
                }
                for characteristic in self.readableCharacteristics {
                    peripheral.readValue(for: characteristic)
                }
            }
        }
    }

    private func payloadPreview(for data: Data) -> String {
        let ascii = sanitizedASCIIString(from: data)
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let asciiPreview = String(ascii.prefix(120))
        return asciiPreview.isEmpty ? "<non-ascii payload>" : asciiPreview
    }

    private func hexPreview(for data: Data) -> String {
        data.prefix(24).map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    private func describe(state: CBManagerState) -> String {
        switch state {
        case .unknown: return "unknown"
        case .resetting: return "resetting"
        case .unsupported: return "unsupported"
        case .unauthorized: return "unauthorized"
        case .poweredOff: return "poweredOff"
        case .poweredOn: return "poweredOn"
        @unknown default: return "other"
        }
    }
}
